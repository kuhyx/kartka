import 'dart:async';

import 'package:kartka/core/source/source_provider.dart';

/// Which source ids the registered providers currently offer.
///
/// Unknown (everything counts as available, so nothing flashes a badge)
/// until every provider has emitted once; then an id is available iff some
/// provider's latest list contains it. No providers means nothing is.
class SourceAvailability {
  /// Watches [providers], calling [onChange] after every emission.
  new(List<SourceProvider> providers, void Function() onChange)
    : _latest = List.filled(providers.length, null) {
    for (final (i, p) in providers.indexed) {
      _subs.add(
        p.watch().listen((sources) {
          _latest[i] = {for (final s in sources) s.ref.id};
          onChange();
        }),
      );
    }
  }

  final List<Set<String>?> _latest;
  final _subs = <StreamSubscription<Object?>>[];

  /// Whether [sourceId] is offered (or availability is not known yet).
  bool isAvailable(String sourceId) {
    if (_latest.any((ids) => ids == null)) return true;
    return _latest.any((ids) => ids!.contains(sourceId));
  }

  /// Stops watching.
  Future<void> dispose() => Future.wait(_subs.map((s) => s.cancel()));
}
