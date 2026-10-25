import 'dart:async';
import 'dart:typed_data';

import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/migration/migration_deps.dart';
import 'package:kartka/migration/migration_target.dart';
import 'package:kartka/platform/blob_store.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/tracking/common/binding_store.dart';
import 'package:kartka/tracking/common/chapter_url_resolver.dart';
import 'package:kartka/tracking/common/tracking_service.dart';

/// Chapters numbered [numbers] under [prefix], oldest first.
List<ChapterInfo> chaptersOf(String prefix, Iterable<num> numbers) => [
  for (final n in numbers)
    ChapterInfo(url: '$prefix/$n', name: 'Ch. $n', number: n.toDouble()),
];

/// A scriptable source: search results per query, chapters per manga url.
class ScriptedSource implements MangaSource {
  new(String id, {String? name})
    : ref = SourceRef(
        id: id,
        name: name ?? id,
        lang: 'en',
        origin: SourceOrigin.suwayomi,
      );

  @override
  final SourceRef ref;

  /// Search results by query.
  final Map<String, List<MangaSummary>> results = {};

  /// Chapters by manga url.
  final Map<String, List<ChapterInfo>> chapterLists = {};

  /// Queries searched, in order.
  final List<String> searched = [];

  /// Thrown by [search] when set.
  Error? searchError;

  /// When set, [search] waits for it.
  Completer<void>? gate;

  /// Thrown by [chapters] when set.
  Error? chaptersError;

  /// A result titled [title] at [url] for [query].
  void offer(String query, String title, String url) => (results[query] ??= [])
      .add(MangaSummary(sourceId: ref.id, url: url, title: title));

  @override
  Future<SearchPage> search(String query, int page) async {
    searched.add(query);
    await gate?.future;
    if (searchError case final e?) throw e;
    return SearchPage(items: results[query] ?? const [], hasNext: false);
  }

  @override
  Future<List<ChapterInfo>> chapters(String mangaUrl) async {
    if (chaptersError case final e?) throw e;
    return chapterLists[mangaUrl] ?? const [];
  }

  @override
  Future<SearchPage> popular(int page) => throw UnimplementedError();

  @override
  Future<SearchPage> latest(int page) => throw UnimplementedError();

  @override
  Future<MangaDetails> details(String mangaUrl) => throw UnimplementedError();

  @override
  Future<List<PageRef>> pages(String chapterUrl) => throw UnimplementedError();
}

/// Old chapter numbers per key, the way browse's chapter cache answers.
class FakeNumbers implements ChapterUrlResolver {
  final Map<MangaKey, List<ChapterInfo>> lists = {};

  @override
  Future<double?> numberOf(MangaKey key, String chapterUrl) async {
    for (final c in lists[key] ?? const <ChapterInfo>[]) {
      if (c.url == chapterUrl) return c.number;
    }
    return null;
  }

  @override
  Future<String?> resolve(MangaKey key, int chapterNumber) async => null;
}

/// A blob store whose writes fail.
class BrokenBlobStore extends MemoryBlobStore {
  @override
  Future<void> put(String key, Uint8List bytes) async =>
      throw StateError('disk full');
}

/// Real repositories over memory stores, a tracking service, an Atsumaru.
class World {
  new({BlobStore? backups}) : backups = backups ?? MemoryBlobStore();

  final repos = LibraryRepositories(
    MemoryKeyValueStore(),
    decorators: () => const [],
    now: () => DateTime.utc(2026, 10, 25),
  );
  final bindings = KvBindingStore(MemoryKeyValueStore());
  late final tracking = TrackingService(
    trackers: () => const [],
    bindings: bindings,
    progress: () => repos.progress,
  );
  final numbers = FakeNumbers();
  final BlobStore backups;
  final target = ScriptedSource(atsumaruSourceId, name: 'Atsumaru');
  MangaSource? Function() lookup = () => null;

  late final deps = MigrationDeps(
    library: repos.library,
    categories: repos.categories,
    progress: repos.progress,
    findTarget: () async => lookup(),
    backups: backups,
    tracking: tracking,
    chapterNumbers: numbers,
    clock: () => DateTime.utc(2026, 10, 25, 12, 30, 5),
  );

  /// Makes [target] the available Atsumaru.
  void install() => lookup = () => target;

  /// Adds an entry titled [title] on [sourceId] at [url].
  Future<LibraryEntry> add(
    String title, {
    String sourceId = 'old',
    String? url,
  }) async {
    final e = LibraryEntry(
      key: mangaKeyOf(sourceId, url ?? '/$title'),
      sourceId: sourceId,
      mangaUrl: url ?? '/$title',
      title: title,
      addedAt: DateTime.utc(2025),
      updatedAt: DateTime.utc(2025),
    );
    await repos.library.upsert(e);
    return e;
  }

  /// Current live library entries by key.
  Future<Map<MangaKey, LibraryEntry>> entries() async => {
    for (final e in await repos.library.watch().first) e.key: e,
  };
}
