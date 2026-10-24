/// [ProgressRepository] that writes through to RTDB `progress/` and `read/`,
/// and replays merged remote changes into the local one.
library;

import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/sync/decorators/remote_listener.dart';
import 'package:kartka/sync/merge/merge_rules.dart';
import 'package:kartka/sync/sync_engine.dart';
import 'package:kartka/sync/wire/wire.dart';

/// The sync decorator for reading progress and read marks.
class SyncedProgressRepository
    with RemoteListener
    implements ProgressRepository {
  /// Wraps [inner]; remote changes from [engine] are applied to it.
  SyncedProgressRepository(this._inner, Future<SyncEngine> engine) {
    listen(engine, {'progress', 'read'});
  }

  final ProgressRepository _inner;

  @override
  Stream<ReadingProgress?> watch(MangaKey key) => _inner.watch(key);

  @override
  Stream<Set<String>> readChapters(MangaKey key) => _inner.readChapters(key);

  @override
  Stream<Map<String, bool>> readMarks(MangaKey key) => _inner.readMarks(key);

  @override
  Future<void> record(ReadingProgress p) async {
    final engine = await this.engine;
    // Both sides max-merge (isAheadOf), so a stale record is a no-op here
    // and in RTDB alike.
    await _inner.record(p);
    await engine.write(progressPath(p.key), rtdbNormal(p.toJson()));
  }

  @override
  Future<void> markRead(MangaKey key, String chapterUrl) =>
      _mark(key, chapterUrl, read: true);

  @override
  Future<void> markUnread(MangaKey key, String chapterUrl) =>
      _mark(key, chapterUrl, read: false);

  Future<void> _mark(
    MangaKey key,
    String chapterUrl, {
    required bool read,
  }) async {
    final engine = await this.engine;
    await (read
        ? _inner.markRead(key, chapterUrl)
        : _inner.markUnread(key, chapterUrl));
    // `key` is additive to §13's {read, hlc, url}: the path only carries
    // hashes, and the receiver needs the MangaKey to replay the mark.
    await engine.write(readPath(key, chapterUrl), {
      'read': read,
      kHlcField: engine.tick().toStr(),
      'url': chapterUrl,
      'key': key,
    });
  }

  @override
  Future<void> apply(SyncEngine engine, RemoteChange change) async {
    final node = change.node;
    final segments = change.path.split('/');
    if (segments.first == 'progress') {
      final p = progressFromNode(node);
      if (p != null) await _inner.record(p);
      return;
    }
    // A writer that omitted `key`: the library node beside it has it.
    final library = engine.shadow.node('library/${segments[1]}');
    final key = node['key'] ?? library?['key'];
    final (url, read) = (node['url'], node['read']);
    if (key is! String || url is! String || read is! bool) return;
    await (read ? _inner.markRead(key, url) : _inner.markUnread(key, url));
  }
}
