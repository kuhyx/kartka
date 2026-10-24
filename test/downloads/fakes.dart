import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/platform/platform.dart';

/// The recorded page list in `test/fixtures/downloads/chapter_pages.json`.
List<PageRef> fixturePages() {
  final raw = File('test/fixtures/downloads/chapter_pages.json')
      .readAsStringSync();
  return [
    for (final p in jsonDecode(raw) as List<Object?>)
      PageRef.fromJson(p! as Map<String, Object?>),
  ];
}

/// Deterministic fake image bytes for [url] (length = url length).
Uint8List fakeImage(String url) => Uint8List.fromList(utf8.encode(url));

class MemoryBlobs implements BlobStore {
  final Map<String, Uint8List> data = {};

  @override
  Future<void> put(String key, Uint8List bytes) async {
    checkBlobKey(key);
    data[key] = bytes;
  }

  @override
  Future<Uint8List?> get(String key) async => data[key];

  @override
  Future<void> delete(String key) async => data.remove(key);

  @override
  Future<List<String>> list(String prefix) async =>
      data.keys.where((k) => k.startsWith(prefix)).toList()..sort();
}

class MemoryKv implements KeyValueStore {
  final Map<String, String> data = {};

  @override
  Future<String?> get(String key) async => data[key];

  @override
  Future<void> set(String key, String value) async => data[key] = value;

  @override
  Future<void> remove(String key) async => data.remove(key);

  @override
  Future<Map<String, String>> entries({String prefix = ''}) async => {
    for (final e in data.entries)
      if (e.key.startsWith(prefix)) e.key: e.value,
  };
}

/// Serves [pages] for every chapter and [chapterList] for every manga.
class FakeSource implements MangaSource {
  new({this.id = 'mangadex', List<PageRef>? pages, this.chapterList})
    : pageList = pages ?? fixturePages();

  final String id;
  final List<PageRef> pageList;
  List<ChapterInfo>? chapterList;
  int pageCalls = 0;
  int chapterCalls = 0;
  bool failChapters = false;

  @override
  SourceRef get ref =>
      SourceRef(id: id, name: id, lang: 'en', origin: SourceOrigin.native);

  @override
  Future<List<PageRef>> pages(String chapterUrl) async {
    pageCalls++;
    return pageList;
  }

  @override
  Future<List<ChapterInfo>> chapters(String mangaUrl) async {
    chapterCalls++;
    if (failChapters) throw StateError('source down');
    return chapterList ?? const [];
  }

  @override
  Future<SearchPage> popular(int page) => throw UnimplementedError();

  @override
  Future<SearchPage> latest(int page) => throw UnimplementedError();

  @override
  Future<SearchPage> search(String query, int page) =>
      throw UnimplementedError();

  @override
  Future<MangaDetails> details(String mangaUrl) => throw UnimplementedError();
}

/// A page loader that fails the first [failures] calls per URL with [error],
/// and can hold every load on [gate] until the test releases it.
class FakeLoader {
  new({this.failures = 0, this.error, this.gate});

  final int failures;
  final Exception? error;
  Completer<void>? gate;
  final Map<String, int> calls = {};
  final List<Map<String, String>> headersSeen = [];

  Future<Uint8List> call(PageRef page) async {
    final n = calls[page.imageUrl] = (calls[page.imageUrl] ?? 0) + 1;
    headersSeen.add(page.headers);
    final g = gate;
    if (g != null) await g.future;
    final e = error;
    if (n <= failures && e != null) throw e;
    if (n <= failures) throw StateError('flaky ${page.imageUrl}');
    return fakeImage(page.imageUrl);
  }
}
