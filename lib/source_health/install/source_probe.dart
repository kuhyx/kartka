import 'dart:async';

import 'package:kartka/browse/source_registry.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/source_health/install/source_installs.dart';

/// Tests one source; null when it works, else the redacted reason.
typedef SourceProbe = Future<String?> Function(String sourceId);

/// The test a freshly installed source must pass: it shows up in [sources]
/// within [appear] (after a re-list) and its first popular page lists at
/// least one title within [answer]. The app has no probe of its own; this
/// is the evaluator's uptime probe ("popular, page 1") done once.
Future<String?> probeSource(
  SourceRegistry sources,
  String id, {
  Duration appear = const Duration(seconds: 60),
  Duration answer = const Duration(seconds: 30),
}) async {
  try {
    await sources.refresh();
    final source = await _listed(sources, id, appear);
    if (source == null) return 'the source did not appear after install';
    final page = await source.popular(1).timeout(answer);
    return page.items.isEmpty ? 'its popular page listed no titles' : null;
  } on Object catch (e) {
    return stripUrls('$e');
  }
}

/// [id] from [sources], waiting up to [timeout] for it to be listed.
Future<MangaSource?> _listed(
  SourceRegistry sources,
  String id,
  Duration timeout,
) {
  final found = Completer<MangaSource?>();
  late final StreamSubscription<List<MangaSource>> sub;
  void finish(MangaSource? s) {
    if (found.isCompleted) return;
    found.complete(s);
    unawaited(sub.cancel());
  }

  final timer = Timer(timeout, () => finish(null));
  sub = sources.watch().listen((_) {
    if (sources.byId(id) case final s?) finish(s);
  });
  return found.future.whenComplete(timer.cancel);
}
