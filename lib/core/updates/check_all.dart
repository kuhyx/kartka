import 'dart:async';

import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/net/network_errors.dart';
import 'package:kartka/core/updates/chapter_update_checker.dart';

/// Checks one manga (normally `ChapterUpdateChecker.check`).
typedef CheckManga = Future<UpdateResult> Function(MangaKey key);

/// Checks every key with [check], at most [maxTotal] at once, at most
/// [maxPerSource] per source (so no one site gets a burst) and at most
/// [maxPerHost] per server ([hostOf]), and completes
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
  int maxPerHost = 2,
  String Function(String sourceId) hostOf = serverOf,
  void Function(UpdateResult result, int done)? onResult,
}) {
  if (keys.isEmpty) return Future.value(const []);
  final queue = [...keys];
  final results = <UpdateResult>[];
  final perSource = <String, int>{};
  final perHost = <String, int>{};
  final finished = Completer<List<UpdateResult>>();
  var active = 0;

  late final void Function() pump;
  void start(MangaKey key, String source, String host) {
    active++;
    perSource[source] = (perSource[source] ?? 0) + 1;
    perHost[host] = (perHost[host] ?? 0) + 1;
    unawaited(
      Future.sync(() => check(key))
          .onError<Object>((e, s) => UpdateFailed(key, e, s))
          .then((result) {
            active--;
            perSource[source] = perSource[source]! - 1;
            perHost[host] = perHost[host]! - 1;
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
      final host = hostOf(source);
      if ((perSource[source] ?? 0) >= maxPerSource ||
          (perHost[host] ?? 0) >= maxPerHost) {
        i++;
      } else {
        start(queue.removeAt(i), source, host);
      }
    }
  };
  pump();
  return finished.future;
}
