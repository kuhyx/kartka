/// [LibraryRepository] that writes through to RTDB `library/` and replays
/// merged remote entries into the local repository it wraps.
library;

import 'dart:async';

import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/sync/decorators/remote_listener.dart';
import 'package:kartka/sync/sync_engine.dart';
import 'package:kartka/sync/wire/wire.dart';

/// The sync decorator for the library.
class SyncedLibraryRepository with RemoteListener implements LibraryRepository {
  /// Wraps [inner]; remote `library/` changes from [engine] are applied to it.
  SyncedLibraryRepository(this._inner, Future<SyncEngine> engine) {
    listen(engine, {'library'});
  }

  final LibraryRepository _inner;

  @override
  Stream<List<LibraryEntry>> watch() => _inner.watch();

  @override
  Future<void> upsert(LibraryEntry e) async {
    final engine = await this.engine;
    final tick = engine.tick();
    // The local repo's LWW must accept every write made through sync, so it
    // gets the monotonic tick, never the caller's (possibly skewed) clock.
    await _inner.upsert(e.copyWith(updatedAt: localStamp(tick)));
    final path = libraryPath(e.key);
    final delta = stampChanges(
      engine.shadow.node(path),
      libraryValues(e),
      tick.toStr(),
    );
    if (delta != null) await engine.write(path, delta);
  }

  @override
  Future<void> remove(MangaKey key) async {
    final engine = await this.engine;
    await _inner.remove(key);
    final path = libraryPath(key);
    final delta = stampChanges(engine.shadow.node(path), {
      'key': key,
      'removed': true,
    }, engine.tick().toStr());
    if (delta != null) await engine.write(path, delta);
  }

  @override
  Future<void> apply(SyncEngine engine, RemoteChange change) async {
    final entry = libraryFromNode(change.node);
    if (entry == null) return;
    if (entry.removed) return _inner.remove(entry.key);
    await _inner.upsert(entry.copyWith(updatedAt: localStamp(engine.tick())));
  }
}
