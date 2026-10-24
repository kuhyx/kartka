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
  /// Wraps `inner`; remote changes from `engine` are applied to it.
  new(this._inner, Future<SyncEngine> engine) {
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
    if (engine == null) {
      await _inner.record(p);
      return;
    }
    // Both sides max-merge (isAheadOf), so a stale record is a no-op here
    // and in RTDB alike.
    await _inner.record(p);
    final path = progressPath(p.key);
    final node = rtdbNormal(p.toJson());
    // Page turns within one chapter coalesce into one push per few seconds;
    // a chapter change (or a first record) goes out at once.
    final pushed = engine.shadow.node(path)?['chapterUrl'];
    if (pushed == p.chapterUrl) {
      await engine.writeDeferred(path, node);
      return;
    }
    await engine.flush();
    await engine.write(path, node);
  }

  @override
  Future<void> markReadMany(MangaKey key, Iterable<String> chapterUrls) async {
    final urls = chapterUrls.toList();
    final engine = await this.engine;
    await _inner.markReadMany(key, urls);
    if (engine == null || urls.isEmpty) return;
    final hlc = engine.tick().toStr();
    // One atomic multi-path PATCH and one revision for the whole manga.
    await engine.writeAll({
      for (final url in urls)
        readPath(key, url): {
          'read': true,
          kHlcField: hlc,
          'url': url,
          'key': key,
        },
    });
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
    if (engine == null) return;
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
