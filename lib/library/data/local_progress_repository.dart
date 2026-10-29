import 'package:flutter/foundation.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/progress_repository.dart';
import 'package:kartka/library/data/kv_table.dart';
import 'package:kartka/library/data/lww.dart';
import 'package:kartka/library/data/mark_set.dart';
import 'package:kartka/platform/key_value_store.dart';

/// [ProgressRepository] on a [KeyValueStore].
///
/// Progress lives under `progress/<mangaKeyHash>` and only moves forward
/// (`ReadingProgress.isAheadOf`). Read marks live under
/// `read/<mangaKeyHash>`, one [MarkSet] of LWW marks per manga, so
/// `markUnread` is a tombstone (contracts §4) and `markReadMany` is one
/// store write.
///
/// The read set holds the explicit marks: deriving "everything before the
/// current chapter" needs the chapter list, which this repository does not
/// have, so the reader marks a chapter read when it is finished.
class LocalProgressRepository implements ProgressRepository {
  /// Creates the repository; [now] stamps read marks.
  new(KeyValueStore store, {DateTime Function()? now})
    : _now = now ?? utcNow,
      _progress = KvTable(
        store,
        'progress/',
        decode: ReadingProgress.fromJson,
        encode: (p) => p.toJson(),
      ),
      _marks = KvTable(
        store,
        'read/',
        decode: MarkSet.fromJson,
        encode: (m) => m.toJson(),
      );

  final DateTime Function() _now;
  final KvTable<ReadingProgress> _progress;
  final KvTable<MarkSet> _marks;

  @override
  Stream<ReadingProgress?> watch(MangaKey key) {
    final id = mangaKeyHash(key);
    return _progress.watchRow(id).distinct();
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

  @override
  Future<void> markReadMany(MangaKey key, Iterable<String> chapterUrls) =>
      _marks.update(
        mangaKeyHash(key),
        (current) =>
            MarkSet.apply(current, key, chapterUrls, on: true, now: _now()),
      );

  Future<void> _mark(MangaKey key, String chapterUrl, {required bool on}) =>
      _marks.update(
        mangaKeyHash(key),
        (current) =>
            MarkSet.apply(current, key, [chapterUrl], on: on, now: _now()),
      );

  @override
  Stream<Map<String, bool>> readMarks(MangaKey key) {
    final id = mangaKeyHash(key);
    return _marks
        .watchRow(id)
        .map(
          (row) => Map<String, bool>.unmodifiable({
            for (final MapEntry(:key, :value) in (row?.marks ?? {}).entries)
              key: value.on,
          }),
        )
        .distinct(mapEquals);
  }

  @override
  Stream<Set<String>> readChapters(MangaKey key) => readMarks(key)
      .map(
        (marks) => Set<String>.unmodifiable({
          for (final MapEntry(:key, :value) in marks.entries)
            if (value) key,
        }),
      )
      .distinct(setEquals);
}
