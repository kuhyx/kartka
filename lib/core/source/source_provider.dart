import 'dart:async';

import 'package:kartka/core/source/manga_source.dart';

/// Supplies sources (DOCS-contracts §10): the only way sources reach the app.
///
/// Registered through `KartkaFeature.services`; consumers merge
/// `registry.all<SourceProvider>()`. A stream because some sets change at
/// runtime (installed plugins, the Suwayomi server's extension list).
abstract interface class SourceProvider {
  /// The current sources, re-emitted whenever the set changes.
  Stream<List<MangaSource>> watch();
}

/// A [SourceProvider] whose set never changes.
class StaticSourceProvider implements SourceProvider {
  /// Provides exactly [sources].
  new(List<MangaSource> sources) : sources = List.unmodifiable(sources);

  /// The fixed set.
  final List<MangaSource> sources;

  @override
  Stream<List<MangaSource>> watch() => Stream.value(sources);
}
