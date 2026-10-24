import 'dart:async';

import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/core/source/source_provider.dart';

/// Live id → [MangaSource] map merged from every [SourceProvider] (§13).
///
/// Providers are read lazily (the registry is only complete after every
/// feature factory ran) and subscribed on the first [find].
class SourceDirectory {
  /// Creates a directory over [providers].
  new(this.providers, {this.firstEmission = const Duration(seconds: 10)});

  /// Returns the providers to merge (normally `registry.all<SourceProvider>`).
  final List<SourceProvider> Function() providers;

  /// How long the first [find] waits for providers to emit.
  final Duration firstEmission;

  final List<StreamSubscription<List<MangaSource>>> _subs = [];
  final Map<int, List<MangaSource>> _latest = {};
  Future<void>? _started;

  Future<void> _start() {
    final firsts = <Future<void>>[];
    var slot = 0;
    for (final provider in providers()) {
      final i = slot++;
      final first = Completer<void>();
      firsts.add(first.future);
      _subs.add(
        provider.watch().listen((sources) {
          _latest[i] = sources;
          if (!first.isCompleted) first.complete();
        }),
      );
    }
    return Future.wait(firsts).timeout(firstEmission, onTimeout: () => []);
  }

  /// The source with [id], or `null` when no provider offers it.
  Future<MangaSource?> find(String id) async {
    await (_started ??= _start());
    for (final list in _latest.values) {
      for (final s in list) {
        if (s.ref.id == id) return s;
      }
    }
    return null;
  }

  /// Stops listening to providers.
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
  }
}
