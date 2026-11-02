import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:kartka/sources/local/comic_info.dart';
import 'package:kartka/sources/local/local_paths.dart';
import 'package:kartka/sources/local/natural_sort.dart';

export 'package:kartka/sources/local/local_paths.dart';

/// A file the user picked that cannot be imported (corrupt, no images).
class LocalImportException implements Exception {
  /// Creates the exception with a user-facing [message].
  const new(this.message);

  /// What went wrong, naming the offending file.
  final String message;

  @override
  String toString() => 'LocalImportException: $message';
}

/// One chapter read from a CBZ/ZIP or a folder of images, pages in natural
/// order, ready to be written to the BlobStore.
@immutable
class ScannedChapter {
  /// Creates a scanned chapter.
  const new({required this.name, required this.pages, this.folder, this.info});

  /// Archive file stem, or the folder's name for folder chapters.
  final String name;

  /// The directory containing the archive/folder, if any.
  final String? folder;

  /// `ComicInfo.xml` metadata when the chapter has one.
  final ComicInfo? info;

  /// Page image bytes in reading order.
  final List<Uint8List> pages;

  /// Series used to group chapters: ComicInfo `Series`, else the containing
  /// folder, else the chapter's own name (a one-chapter manga).
  String get seriesTitle => info?.series ?? folder ?? name;

  /// Chapter display name: ComicInfo `Title`, else [name].
  String get chapterTitle => info?.title ?? name;
}

/// Reads a CBZ/ZIP. Throws [LocalImportException] when the bytes are not a
/// readable ZIP or hold no images. [path] is the picked file's (relative)
/// path, used for naming only.
ScannedChapter scanArchive(String path, Uint8List bytes) {
  try {
    return _scan(path, bytes);
  } on LocalImportException {
    rethrow;
    // Entries decompress lazily, so corrupt data surfaces while reading a
    // page (FormatException) or as an Error; all mean "unreadable" here.
  } on Object {
    throw LocalImportException('Not a readable CBZ/ZIP: ${baseName(path)}');
  }
}

ScannedChapter _scan(String path, Uint8List bytes) {
  // verify: archive >= 4.6 no longer throws on a truncated or garbled entry,
  // so check the CRCs to keep rejecting corrupt files.
  final archive = ZipDecoder().decodeBytes(bytes, verify: true);
  final entries = {
    for (final f in archive.files)
      if (f.isFile && !isJunkPath(f.name)) normalizePath(f.name): f,
  };
  final images = naturalSorted(entries.keys.where(isImagePath));
  if (images.isEmpty) {
    throw LocalImportException('No images in ${baseName(path)}');
  }
  final infoPath = entries.keys.where(isComicInfoPath).firstOrNull;
  return ScannedChapter(
    name: fileStem(path),
    folder: parentName(path),
    info: infoPath == null
        ? null
        : ComicInfo.parseBytes(entries[infoPath]!.content),
    pages: [for (final p in images) entries[p]!.content],
  );
}
