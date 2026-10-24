import 'package:flutter/foundation.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/progress_repository.dart';
import 'package:kartka/library/data/kv_table.dart';
import 'package:kartka/library/data/mark.dart';
import 'package:kartka/platform/key_value_store.dart';

/// [ProgressRepository] on a [KeyValueStore].
///
/// Progress lives under `progress/<mangaKeyHash>` and only moves forward
/// (`ReadingProgress.isAheadOf`). Read marks live under
/// `read/<mangaKeyHash>/<sha1(chapterUrl)>` as LWW [Mark]s, so `markUnread`
/// is a tombstone (contracts §4).
///
/// The read set holds the explicit marks: deriving "everything before the
/// current chapter" needs the chapter list, which this repository does not
/// have, so the reader marks a chapter read when it is finished.
class LocalProgressRepository implements ProgressRepository {
  /// Creates the repository; [now] stamps read marks.
  LocalProgressRepository(KeyValueStore store, {DateTime Function()? now})
    : _now = now ?? _utcNow,
      _progress = KvTable(
        store,
        'progress/',
        decode: ReadingProgress.fromJson,
        encode: (p) => p.toJson(),
      ),
      _marks = KvTable(
        store,
        'read/',
        decode: Mark.fromJson,
        encode: (m) => m.toJson(),
      );

  final DateTime Function() _now;
  final KvTable<ReadingProgress> _progress;
  final KvTable<Mark> _marks;

  @override
  Stream<ReadingProgress?> watch(MangaKey key) {
    final id = mangaKeyHash(key);
    return _progress.watch().map((rows) => rows[id]).distinct();
  }

  @override
  Future<void> record(ReadingProgress p) => _progress.update(
    mangaKeyHash(p.key),
    (current) => p.isAheadOf(current) ? p : null,
  );

  @override
  Future<void> markRead(MangaKey key, String chapterUrl) =>
      _mark(key, chapterUrl, on: true);

  @override
  Future<void> markUnread(MangaKey key, String chapterUrl) =>
      _mark(key, chapterUrl, on: false);

  Future<void> _mark(MangaKey key, String chapterUrl, {required bool on}) =>
      _marks.update(
        '${mangaKeyHash(key)}/${mangaKeyHash(chapterUrl)}',
        (current) => flip(current, key, chapterUrl, on: on, now: _now()),
      );

  @override
  Stream<Set<String>> readChapters(MangaKey key) => _marks
      .watch()
      .map(
        (rows) => Set<String>.unmodifiable({
          for (final m in rows.values)
            if (m.key == key && m.on) m.target,
        }),
      )
      .distinct(setEquals);
}

DateTime _utcNow() => DateTime.now().toUtc();
