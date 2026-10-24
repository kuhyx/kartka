import 'dart:async';

import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/tracking/common/chapter_url_resolver.dart';
import 'package:kartka/tracking/common/progress_rules.dart';

/// Finished-chapter count per manga, the number trackers receive.
///
/// Counts like Mihon: only chapters explicitly marked read (`readMarks`
/// true; the reader marks a chapter at its last page) count, and the count
/// is the floor of the highest such chapter number. Opening a chapter
/// counts nothing. Numbers come from progress emissions (the reader
/// records a chapter before finishing it) or the resolver's `numberOf`;
/// a mark whose number is unknown is ignored.
class FinishedChapters {
  /// Creates the counter; both getters are read lazily.
  new(this._progress, {required this._resolver});

  final ProgressRepository Function() _progress;
  final ChapterUrlResolver? Function() _resolver;

  /// The finished count of [key] right now, or `null` when none counts.
  Future<int?> current(MangaKey key) async {
    final repo = _progress();
    final p = await repo.watch(key).first;
    return await _count(key, await repo.readMarks(key).first, {
      if (p != null) p.chapterUrl: p.chapterNumber,
    });
  }

  Future<int?> _count(
    MangaKey key,
    Map<String, bool> marks,
    Map<String, double> numbers,
  ) async {
    double? best;
    for (final MapEntry(key: url, value: read) in marks.entries) {
      if (!read) continue;
      final n = numbers[url] ?? await _resolver()?.numberOf(key, url);
      if (n == null) continue;
      numbers[url] = n;
      if (best == null || n > best) best = n;
    }
    return chaptersReadFrom(best);
  }

  /// Emits the finished count of [key] whenever it may have changed.
  Stream<int> watch(MangaKey key) {
    final numbers = <String, double>{};
    var marks = const <String, bool>{};
    var chain = Future<void>.value();
    final subs = <StreamSubscription<Object?>>[];
    late final StreamController<int> out;

    Future<void> recount() async {
      final count = await _count(key, marks, numbers);
      if (count != null && !out.isClosed) out.add(count);
    }

    void schedule() => chain = chain
        .then((_) => recount())
        .catchError((Object e) => out.addError(e));

    out = StreamController<int>(
      onListen: () {
        try {
          final repo = _progress();
          subs
            ..add(
              repo.watch(key).listen((p) {
                if (p == null) return;
                numbers[p.chapterUrl] = p.chapterNumber;
                schedule();
              }, onError: out.addError),
            )
            ..add(
              repo.readMarks(key).listen((m) {
                marks = m;
                schedule();
              }, onError: out.addError),
            );
        } on Object catch (e) {
          out.addError(e);
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
        await out.close();
      },
    );
    return out.stream;
  }
}
