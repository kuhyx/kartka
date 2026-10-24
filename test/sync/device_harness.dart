import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/library/data/local_category_repository.dart';
import 'package:kartka/library/data/local_library_repository.dart';
import 'package:kartka/library/data/local_progress_repository.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sync/decorators/sync_repository_decorator.dart';
import 'package:kartka/sync/decorators/synced_categories.dart';
import 'package:kartka/sync/decorators/synced_library.dart';
import 'package:kartka/sync/decorators/synced_progress.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_engine.dart';

import 'fakes.dart';

/// One simulated install: the library part's real local repositories,
/// decorated by sync, over a shared in-memory RTDB.
class Device {
  new _(this.engine, this.library, this.categories, this.progress);

  /// Builds device [id] syncing through [db].
  static Future<Device> create(
    String id,
    InMemoryRtdb db, {
    TestClock? clock,
  }) async {
    final c = clock ?? TestClock();
    final kv = MemoryKeyValueStore();
    final engine = await engineFor(id, db, clock: c);
    final decorator = SyncRepositoryDecorator(Future.value(engine));
    DateTime now() => c.now;
    return Device._(
      engine,
      decorator.library(LocalLibraryRepository(kv, now: now))
          as SyncedLibraryRepository,
      decorator.categories(LocalCategoryRepository(kv, now: now))
          as SyncedCategoryRepository,
      decorator.progress(LocalProgressRepository(kv, now: now))
          as SyncedProgressRepository,
    );
  }

  /// The device's engine.
  final SyncEngine engine;

  /// Decorated library repository.
  final SyncedLibraryRepository library;

  /// Decorated category repository.
  final SyncedCategoryRepository categories;

  /// Decorated progress repository.
  final SyncedProgressRepository progress;

  /// One foreground poll, then waits until every change is replayed.
  Future<void> poll() async {
    await engine.poll();
    await settle();
  }

  /// Waits until every received remote change is replayed locally.
  Future<void> settle() async {
    await pumpEventQueue();
    await library.settled;
    await categories.settled;
    await progress.settled;
  }

  /// Stops the decorators' subscriptions.
  Future<void> dispose() async {
    await library.dispose();
    await categories.dispose();
    await progress.dispose();
  }
}
