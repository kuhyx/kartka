import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;
import 'package:kartka/core/models/manga_key.dart';
import 'package:kartka/platform/platform.dart';
import 'package:kartka/sources/local/archive_scan.dart';
import 'package:kartka/sources/local/import_plan.dart';
import 'package:kartka/sources/local/local_index.dart';

export 'package:kartka/sources/local/local_index.dart';

/// Outcome of one [LocalLibrary.importFiles] call.
@immutable
class ImportReport {
  /// Creates a report.
  const new({
    required this.chapters,
    required this.mangaUrls,
    required this.errors,
  });

  /// Chapters imported (new or replaced).
  final int chapters;

  /// Series keys of the manga those chapters went into.
  final Set<String> mangaUrls;

  /// One message per file or folder that could not be imported.
  final List<String> errors;

  /// One-line, user-facing summary.
  String get summary {
    if (chapters == 0 && errors.isEmpty) return 'Nothing to import';
    final ch = chapters == 1 ? 'chapter' : 'chapters';
    final failed = errors.isEmpty ? '' : ', ${errors.length} failed';
    return 'Imported $chapters $ch into ${mangaUrls.length} manga$failed';
  }
}

/// Local CBZ/folder library: page bytes in the [BlobStore], the series index
/// as JSON in the [KeyValueStore]. Imports run one at a time.
class LocalLibrary {
  /// Creates a library over the platform stores; [clock] is for tests.
  new({
    required BlobStore blobs,
    required KeyValueStore kv,
    DateTime Function()? clock,
  }) : _blobs = blobs,
       _kv = kv,
       _clock = clock ?? DateTime.now;

  /// KeyValueStore key of the JSON index.
  static const indexKey = 'local.index';

  final BlobStore _blobs;
  final KeyValueStore _kv;
  final DateTime Function() _clock;
  final _changes = StreamController<LocalIndex>.broadcast();
  LocalIndex? _index;
  Future<void> _tail = Future.value();

  /// Emits the index after every import or removal that changed it.
  Stream<LocalIndex> get changes => _changes.stream;

  /// The current index (read from the KeyValueStore once, then cached).
  Future<LocalIndex> load() async =>
      _index ??= LocalIndex.decode(await _kv.get(indexKey));

  /// Imports [files] (CBZ/ZIP archives and/or images with relative paths
  /// from a picked folder). Unreadable files are reported in the result;
  /// storage failures propagate.
  Future<ImportReport> importFiles(List<PickedFile> files) =>
      _serial(() => _import(files));

  /// Removes the manga with series key [url] and deletes its pages.
  Future<void> remove(String url) => _serial(() async {
    final change = (await load()).remove(url);
    await _commit(change);
  });

  Future<T> _serial<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<ImportReport> _import(List<PickedFile> files) async {
    final byPath = {for (final f in files) normalizePath(_pathOf(f)): f};
    final errors = <String>[];
    final mangaUrls = <String>{};
    var chapters = 0;
    for (final unit in planImport(byPath.keys)) {
      final ScannedChapter scanned;
      try {
        scanned = await _scan(unit, byPath);
      } on LocalImportException catch (e) {
        errors.add(e.message);
        continue;
      } on Object {
        errors.add('Could not read ${unit.path}');
        continue;
      }
      final url = chapterUrlFor(scanned);
      final keys = await _storePages(url, scanned.pages);
      final change = (await load()).add(scanned, keys, _clock().toUtc());
      await _commit(change, notify: false);
      mangaUrls.add(seriesKey(scanned.seriesTitle));
      chapters++;
    }
    if (chapters > 0) _changes.add(_index!);
    return ImportReport(
      chapters: chapters,
      mangaUrls: mangaUrls,
      errors: errors,
    );
  }

  String _pathOf(PickedFile f) => f.relativePath ?? f.name;

  Future<ScannedChapter> _scan(
    ImportUnit unit,
    Map<String, PickedFile> byPath,
  ) async {
    switch (unit) {
      case ArchiveUnit(:final path):
        return scanArchive(path, await byPath[path]!.readBytes());
      case FolderUnit(:final imagePaths, :final comicInfoPath):
        final pages = <Uint8List>[
          for (final p in imagePaths) await byPath[p]!.readBytes(),
        ];
        final info = comicInfoPath == null
            ? null
            : await byPath[comicInfoPath]!.readBytes();
        return scanFolder(unit, pages, info);
    }
  }

  Future<List<String>> _storePages(String chapterUrl, List<Uint8List> pages) {
    final dir = 'local/${mangaKeyHash(chapterUrl)}';
    return Future.wait([
      for (var i = 0; i < pages.length; i++)
        _put('$dir/${i.toString().padLeft(4, '0')}', pages[i]),
    ]);
  }

  Future<String> _put(String key, Uint8List bytes) async {
    await _blobs.put(key, bytes);
    return key;
  }

  Future<void> _commit(IndexChange change, {bool notify = true}) async {
    _index = change.index;
    await _kv.set(indexKey, jsonEncode(change.index.toJson()));
    await Future.wait(change.orphanBlobKeys.map(_blobs.delete));
    if (notify) _changes.add(change.index);
  }
}
