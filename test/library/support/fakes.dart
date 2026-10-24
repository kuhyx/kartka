import 'dart:async';

import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/library/ports.dart';
import 'package:kartka/library/state/library_deps.dart';

import 'package:kartka/platform/memory/memory_stores.dart';

/// Port fake: one broadcast controller per key, seeded with [initial].
class FakePort<T> {
  new(this.initial);
  final T initial;
  final Map<MangaKey, StreamController<T>> controllers = {};
  int cancelled = 0;

  Stream<T> watch(MangaKey key) {
    final c = controllers[key] = StreamController<T>(
      onCancel: () => cancelled++,
    )..add(initial);
    return c.stream;
  }

  void emit(MangaKey key, T value) => controllers[key]!.add(value);
}

class FakeUnread extends FakePort<int?> implements UnreadCounts {
  new() : super(null);
}

class FakeDownloaded extends FakePort<bool> implements DownloadedLookup {
  new() : super(false);
  @override
  Stream<bool> hasDownloads(MangaKey key) => watch(key);
}

class FakeTracked extends FakePort<bool> implements TrackedLookup {
  new() : super(false);
  @override
  Stream<bool> isTracked(MangaKey key) => watch(key);
}

final t0 = DateTime.utc(2026, 10, 24);

LibraryEntry entry(String url, {String? title, int addedDays = 0}) =>
    LibraryEntry(
      key: mangaKeyOf('mangadex', url),
      sourceId: 'mangadex',
      mangaUrl: url,
      title: title ?? url,
      addedAt: t0.add(Duration(days: addedDays)),
      updatedAt: t0,
    );

/// A deps bundle over a fresh store with fake ports and a fixed clock.
({
  LibraryDeps deps,
  MemoryKeyValueStore kv,
  FakeUnread unread,
  FakeDownloaded dl,
  FakeTracked tracked,
})
fakeDeps({DateTime Function()? clock}) {
  final kv = MemoryKeyValueStore();
  final now = clock ?? () => t0;
  final unread = FakeUnread();
  final dl = FakeDownloaded();
  final tracked = FakeTracked();
  final deps = LibraryDeps(
    repos: LibraryRepositories(kv, decorators: () => [], now: now),
    unread: unread,
    downloaded: dl,
    tracked: tracked,
    clock: now,
  );
  return (deps: deps, kv: kv, unread: unread, dl: dl, tracked: tracked);
}
