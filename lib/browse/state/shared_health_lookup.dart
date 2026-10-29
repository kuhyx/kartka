import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:kartka/browse/source_health_lookup.dart';

/// A [SourceHealthLookup] that shares one upstream subscription between
/// every listener and remembers the latest ranks.
///
/// The upstream (the source_health feed) re-reads its tree whenever its
/// last listener leaves and a new one arrives, and the Browse tab is
/// remounted on every tab switch. So the upstream subscription is kept for
/// [linger] after the last listener leaves, and [latest] lets a remounted
/// list start in rank order instead of reordering when data arrives.
class SharedHealthLookup implements SourceHealthLookup {
  /// Shares [_inner]'s stream.
  new(this._inner, {this.linger = const Duration(minutes: 1)});

  final SourceHealthLookup _inner;

  /// How long the upstream subscription outlives its last listener.
  final Duration linger;

  /// The newest ranks seen, or null before the first emission.
  Map<String, SourceHealthSummary>? latest;

  late final _out =
      StreamController<Map<String, SourceHealthSummary>>.broadcast(
        onListen: _start,
        onCancel: () => _stop = Timer(linger, _cancelUpstream),
      );
  StreamSubscription<Map<String, SourceHealthSummary>>? _sub;
  Timer? _stop;

  void _start() {
    _stop?.cancel();
    _sub ??= _inner.watch().listen((ranks) {
      latest = ranks;
      _out.add(ranks);
    }, onError: _out.addError);
  }

  void _cancelUpstream() {
    unawaited(_sub?.cancel());
    _sub = null;
  }

  /// [latest] first (when known), then every upstream emission.
  @override
  Stream<Map<String, SourceHealthSummary>> watch() {
    late final StreamController<Map<String, SourceHealthSummary>> out;
    StreamSubscription<Map<String, SourceHealthSummary>>? sub;
    out = StreamController(
      onListen: () {
        final known = latest;
        if (known != null) out.add(known);
        sub = _out.stream.listen(out.add, onError: out.addError);
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  @override
  Widget? buildBadge(
    BuildContext context,
    String sourceId,
    SourceHealthSummary? summary,
  ) => _inner.buildBadge(context, sourceId, summary);
}
