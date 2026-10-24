import 'dart:convert';

import 'package:glados/glados.dart';
import 'package:kartka/core/models/models.dart';

import '../../helpers/generators.dart';

/// Encodes [json] to a JSON string and back, as RTDB and the wrapper do.
Map<String, Object?> _wire(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

/// Round-trip, equality and hash laws for one model type.
void _laws<T extends Object>(
  String name,
  Generator<T> gen,
  Map<String, Object?> Function(T) toJson,
  T Function(Map<String, Object?>) fromJson,
) {
  group(name, () {
    Glados(gen).test('fromJson(toJson(x)) == x through a JSON string', (x) {
      final back = fromJson(_wire(toJson(x)));
      expect(back, x);
      expect(back.hashCode, x.hashCode);
      expect(back.toString(), x.toString());
    });
    Glados2(gen, gen).test('equal values have equal hashes', (a, b) {
      if (a == b) expect(a.hashCode, b.hashCode);
      expect(a == b, toJson(a).toString() == toJson(b).toString());
    });
  });
}

void main() {
  _laws('SourceRef', any.sourceRef, (x) => x.toJson(), SourceRef.fromJson);
  _laws(
    'MangaSummary',
    any.mangaSummary,
    (x) => x.toJson(),
    MangaSummary.fromJson,
  );
  _laws(
    'MangaDetails',
    any.mangaDetails,
    (x) => x.toJson(),
    MangaDetails.fromJson,
  );
  _laws(
    'ChapterInfo',
    any.chapterInfo,
    (x) => x.toJson(),
    ChapterInfo.fromJson,
  );
  _laws('PageRef', any.pageRef, (x) => x.toJson(), PageRef.fromJson);
  _laws('SearchPage', any.searchPage, (x) => x.toJson(), SearchPage.fromJson);
  _laws(
    'LibraryEntry',
    any.libraryEntry,
    (x) => x.toJson(),
    LibraryEntry.fromJson,
  );
  _laws('Category', any.category, (x) => x.toJson(), Category.fromJson);
  _laws(
    'ReadingProgress',
    any.readingProgress,
    (x) => x.toJson(),
    ReadingProgress.fromJson,
  );
  _laws(
    'DownloadState',
    any.downloadState,
    (x) => x.toJson(),
    DownloadState.fromJson,
  );
}
