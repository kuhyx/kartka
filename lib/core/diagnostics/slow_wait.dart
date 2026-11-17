import 'dart:async';

import 'package:kartka/core/diagnostics/diagnostic_entry.dart';
import 'package:kartka/core/diagnostics/diagnostics_log.dart';

/// Diagnostics kind of a user-visible wait that lasted over a second.
const perfSlowKind = 'perf.slow';

/// Reports every user-visible wait that outlasts [threshold] as one
/// `perf.slow` entry (route on top when it began, operation, milliseconds),
/// so the PC can file a ticket to bring it under a second.
///
/// A wait that ends within [threshold] writes nothing. One still going after
/// [stillWaiting] is written at once (a hung load never ends), and its end
/// writes a second entry with the same wait id and the final duration. The
/// signature the PC groups by is route + operation only, never the time, so
/// every slow wait of one operation lands in one ticket. At most
/// [maxPerMinute] entries a minute are kept. Never throws.
class SlowWaitReporter {
  /// A reporter into [log], reading time from [now].
  new(
    this.log, {
    DateTime Function()? now,
    this.threshold = const Duration(seconds: 1),
    this.stillWaiting = const Duration(seconds: 5),
  }) : _now = now ?? DateTime.now;

  /// The shared reporter for [log]; [now] only counts on the first call.
  factory of(DiagnosticsLog log, {DateTime Function()? now}) =>
      _shared[log] ??= SlowWaitReporter(log, now: now);

  static final _shared = Expando<SlowWaitReporter>('slowWait');

  /// Most entries kept in one minute.
  static const maxPerMinute = 30;

  /// Where reports go.
  final DiagnosticsLog log;

  /// A wait must last longer than this to be reported.
  final Duration threshold;

  /// A wait this long is reported before it ends.
  final Duration stillWaiting;

  final DateTime Function() _now;
  DateTime? _minute;
  int _inMinute = 0;
  int _serial = 0;

  /// Starts timing a wait on [operation] (`reader.open`); call
  /// [SlowWait.end] when the wait is over.
  SlowWait begin(String operation) {
    final at = _now();
    return SlowWait._(
      this,
      operation: operation,
      route: log.route,
      started: at,
      id: '${at.microsecondsSinceEpoch.toRadixString(36)}-${_serial++}',
    );
  }

  void _write(SlowWait w, Duration took, {required bool still}) {
    final at = _now();
    final minute = _minute;
    if (minute == null || at.difference(minute) >= const Duration(minutes: 1)) {
      _minute = at;
      _inMinute = 0;
    }
    if (_inMinute >= maxPerMinute) return;
    _inMinute++;
    final ms = took.inMilliseconds;
    unawaited(
      log.append(
        DiagnosticEntry(
          at: at,
          kind: perfSlowKind,
          error: '${w.operation} waited $ms ms',
          route: w.route,
          operation: w.operation,
          durationMs: ms,
          waitId: w.id,
          still: still,
        ),
      ),
    );
  }
}

/// One timed wait of a [SlowWaitReporter].
class SlowWait {
  new _(
    this._reporter, {
    required this.operation,
    required this.route,
    required this.started,
    required this.id,
  }) {
    _timer = Timer(_reporter.stillWaiting, _stillGoing);
  }

  final SlowWaitReporter _reporter;

  /// What is awaited.
  final String operation;

  /// The route pattern on top when the wait began.
  final String? route;

  /// When it began.
  final DateTime started;

  /// Names this wait across its reports.
  final String id;

  late final Timer _timer;
  bool _reportedStill = false;
  bool _ended = false;

  void _stillGoing() {
    _reportedStill = true;
    _reporter._write(this, _reporter._now().difference(started), still: true);
  }

  /// Ends the wait; writes it when it lasted over the threshold. Repeat
  /// calls do nothing.
  void end() {
    if (_ended) return;
    _ended = true;
    _timer.cancel();
    final took = _reporter._now().difference(started);
    if (_reportedStill || took > _reporter.threshold) {
      _reporter._write(this, took, still: false);
    }
  }
}
