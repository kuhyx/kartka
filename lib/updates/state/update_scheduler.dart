import 'dart:async';

import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/updates/chapter_update_checker.dart';

/// Checks one manga (normally `ChapterUpdateChecker.check`).
typedef CheckManga = Future<UpdateResult> Function(MangaKey key);

/// Checks every key with [check], at most [maxTotal] at once and at most
/// [maxPerSource] per source (so no one site gets a burst), and completes
/// with every result in completion order. [onResult] hears each result with
/// the count finished so far.
///
/// When a slot frees, the first queued key whose source is below its limit
/// starts, so a long run of one source at the queue head never stalls the
/// rest. A [check] that throws despite its contract becomes [UpdateFailed].
Future<List<UpdateResult>> checkAll(
  List<MangaKey> keys,
  CheckManga check, {
  int maxTotal = 4,
  int maxPerSource = 1,
  void Function(UpdateResult result, int done)? onResult,
}) {
  if (keys.isEmpty) return Future.value(const []);
  final queue = [...keys];
  final results = <UpdateResult>[];
  final perSource = <String, int>{};
  final finished = Completer<List<UpdateResult>>();
  var active = 0;

  late final void Function() pump;
  void start(MangaKey key, String source) {
    active++;
    perSource[source] = (perSource[source] ?? 0) + 1;
    unawaited(
      Future.sync(() => check(key))
          .onError<Object>((e, s) => UpdateFailed(key, e, s))
          .then((result) {
            active--;
            perSource[source] = perSource[source]! - 1;
            results.add(result);
            onResult?.call(result, results.length);
            if (results.length == keys.length) {
              finished.complete(results);
            } else {
              pump();
            }
          }),
    );
  }

  pump = () {
    for (var i = 0; i < queue.length && active < maxTotal;) {
      final source = splitMangaKey(queue[i]).$1;
      if ((perSource[source] ?? 0) >= maxPerSource) {
        i++;
      } else {
        start(queue.removeAt(i), source);
      }
    }
  };
  pump();
  return finished.future;
}
