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
    if (engine == null) return _inner.upsert(e);
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
    if (engine == null) return _inner.remove(key);
    final path = libraryPath(key);
    final known = engine.shadow.node(path);
    final current = known == null ? null : libraryFromNode(known);
    final tick = engine.tick();
    // A tombstone upsert stamped with the tick, not inner.remove: remove
    // stamps its own clock, which a later remote re-add could fail to beat.
    await (current == null
        ? _inner.remove(key)
        : _inner.upsert(
            current.copyWith(removed: true, updatedAt: localStamp(tick)),
          ));
    final delta = stampChanges(known, {
      'key': key,
      'removed': true,
    }, tick.toStr());
    if (delta != null) await engine.write(path, delta);
  }

  @override
  Future<void> apply(SyncEngine engine, RemoteChange change) async {
    final entry = libraryFromNode(change.node);
    if (entry == null) return;
    await _inner.upsert(entry.copyWith(updatedAt: localStamp(engine.tick())));
  }
}
