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
/// [SourceUnavailable]. Completes without awaiting the subscription's
/// cancel, so a slow provider teardown never delays the screen.
Future<MangaSource> waitForSource(
  SourceRegistry sources,
  String sourceId,
  Duration wait,
) {
  final found = Completer<MangaSource>();
  late final StreamSubscription<void> sub;
  final timer = Timer(wait, () {
    if (found.isCompleted) return;
    found.completeError(SourceUnavailable(sourceId));
    unawaited(sub.cancel());
  });
  sub = sources.watch().listen((_) {
    final source = sources.byId(sourceId);
    if (source == null || found.isCompleted) return;
    timer.cancel();
    found.complete(source);
    unawaited(sub.cancel());
  });
  return found.future;
}
