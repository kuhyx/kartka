import 'dart:async';

import 'package:kartka/browse/source_registry.dart';
import 'package:kartka/core/source/manga_source.dart';

/// No registered source has the route's source id (not installed, server
/// unreachable, or an id kartka has no source for, e.g. `sy-builtin:*`).
class SourceUnavailable implements Exception {
  /// Creates the error for [sourceId].
  const new(this.sourceId);

  /// The missing source id.
  final String sourceId;

  @override
  String toString() => 'Source $sourceId is not available';
}

/// The source [sourceId] of [sources], waiting up to [wait] for a runtime
/// source (Suwayomi, plugin) to appear; else fails with
/// [SourceUnavailable], at once when [SourceRegistry.settled] lists lack
/// it (2d26b6d5: a dead source timed its screen for the whole wait).
/// Completes without awaiting the subscription's cancel, so a slow
/// provider teardown never delays the screen.
Future<MangaSource> waitForSource(
  SourceRegistry sources,
  String sourceId,
  Duration wait,
) {
  final found = Completer<MangaSource>();
  late final StreamSubscription<void> sub;
  late final Timer timer;
  void fail() {
    if (found.isCompleted) return;
    timer.cancel();
    found.completeError(SourceUnavailable(sourceId));
    unawaited(sub.cancel());
  }

  timer = Timer(wait, fail);
  sub = sources.watch().listen((_) {
    final source = sources.byId(sourceId);
    if (found.isCompleted) return;
    if (source == null) {
      if (sources.settled) fail();
      return;
    }
    timer.cancel();
    found.complete(source);
    unawaited(sub.cancel());
  });
  return found.future;
}

/// Calls [then] once [sources] lists [sourceId]; cancel the result to stop.
StreamSubscription<void> whenListed(
  SourceRegistry sources,
  String sourceId,
  void Function() then,
) => sources
    .watch()
    .where((_) => sources.byId(sourceId) != null)
    .take(1)
    .listen((_) => then());
