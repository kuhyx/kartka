import 'dart:async';

import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/core/source/source_provider.dart';

/// The source with [sourceId] among [providers], or null.
///
/// Every provider's current list is read at once, and the first list that
/// has the id wins. Asked one after another, each slow provider (a plugin
/// runtime or the in-app extension host starting) added up to [wait] before
/// the next was read: a 5 s `reader.open` on build 615 (971debc8). A
/// provider that has not emitted within [wait] or fails counts as a miss,
/// so one slow runtime cannot keep a downloaded chapter from opening.
Future<MangaSource?> findSource(
  Iterable<SourceProvider> providers,
  String sourceId, {
  Duration wait = const Duration(seconds: 5),
}) {
  final all = providers.toList();
  if (all.isEmpty) return Future.value();
  final result = Completer<MangaSource?>();
  var pending = all.length;
  void missed() {
    if (--pending == 0 && !result.isCompleted) result.complete(null);
  }

  for (final provider in all) {
    Future<List<MangaSource>> first;
    try {
      first = provider.watch().first.timeout(wait, onTimeout: () => const []);
    } on Object {
      missed();
      continue;
    }
    first.then((sources) {
      for (final s in sources) {
        if (s.ref.id == sourceId) {
          if (!result.isCompleted) result.complete(s);
          return;
        }
      }
      missed();
    }, onError: (Object _) => missed()).ignore();
  }
  return result.future;
}
