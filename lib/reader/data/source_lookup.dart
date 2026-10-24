import 'dart:async';

import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/core/source/source_provider.dart';

/// The source with [sourceId] among [providers], or null.
///
/// Each provider's current list is read once; a provider that has not
/// emitted within [wait] or fails is skipped, so one slow plugin runtime
/// cannot keep a downloaded chapter from opening.
Future<MangaSource?> findSource(
  Iterable<SourceProvider> providers,
  String sourceId, {
  Duration wait = const Duration(seconds: 5),
}) async {
  for (final provider in providers) {
    final List<MangaSource> sources;
    try {
      sources = await provider.watch().first.timeout(
        wait,
        onTimeout: () => const [],
      );
    } on Object {
      continue;
    }
    for (final s in sources) {
      if (s.ref.id == sourceId) return s;
    }
  }
  return null;
}
