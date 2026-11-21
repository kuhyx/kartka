import 'dart:async';

import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/core/source/source_provider.dart';

/// Finds the reader's source by id among every provider's latest list.
///
/// The first lookup subscribes to every provider once and keeps their
/// lists, so later lookups answer at once, a miss included. Before, each
/// open re-listed every provider, one after another: a slow one (a plugin
/// runtime, the in-app extension host) added up to 5 s each (a 5 s
/// `reader.open` on build 615), and a cold miss took 0.83 s on the web
/// build (971debc8).
class SourceLookup {
  /// A lookup over [_providers], read at the first lookup (the registry is
  /// late).
  new(this._providers);

  final Iterable<SourceProvider> Function() _providers;
  List<_Kept>? _kept;
  final _changed = StreamController<void>.broadcast(sync: true);

  /// The source with [id], or null once every provider has listed without
  /// it. A provider that has not listed within [wait] or fails counts as a
  /// miss, so one slow runtime cannot keep a downloaded chapter from
  /// opening.
  Future<MangaSource?> find(
    String id, {
    Duration wait = const Duration(seconds: 5),
  }) async {
    final kept = _kept ??= [for (final p in _providers()) _keep(p)];
    MangaSource? hit() {
      for (final k in kept) {
        for (final s in k.sources) {
          if (s.ref.id == id) return s;
        }
      }
      return null;
    }

    bool settled() => kept.every((k) => k.listed);
    if (hit() case final s?) return s;
    if (settled()) return null;
    final done = Completer<MangaSource?>();
    final sub = _changed.stream.listen((_) {
      final s = hit();
      if ((s != null || settled()) && !done.isCompleted) done.complete(s);
    });
    try {
      return await done.future.timeout(wait, onTimeout: hit);
    } finally {
      await sub.cancel();
    }
  }

  _Kept _keep(SourceProvider provider) {
    final kept = _Kept();
    void listed([List<MangaSource>? sources]) {
      if (sources != null) kept.sources = sources;
      kept.listed = true;
      _changed.add(null);
    }

    try {
      provider.watch().listen(
        listed,
        onError: (Object _) => listed(), // keeps its last list
        onDone: listed,
      );
    } on Object {
      kept.listed = true;
    }
    return kept;
  }
}

/// One provider's latest list, and whether it has listed (or failed) yet.
class _Kept {
  List<MangaSource> sources = const [];
  bool listed = false;
}
