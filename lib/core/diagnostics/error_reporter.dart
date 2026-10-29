import 'dart:async';

import 'package:kartka/core/diagnostics/diagnostic_entry.dart';
import 'package:kartka/core/diagnostics/diagnostics_log.dart';

/// Records errors the user saw (or that escaped) in the [DiagnosticsLog].
///
/// The one door for the app-wide hooks (uncaught errors, error snackbars,
/// failed pages). It guards the log, which rewrites its file on every
/// append, against error loops: an identical `kind` + message inside
/// [window] is dropped, and at most [maxPerMinute] reports are kept per
/// minute. It never throws and never reports from inside a report.
class ErrorReporter {
  /// A reporter into [log], stamping entries with [now].
  new(this.log, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// The shared reporter for [log].
  factory of(DiagnosticsLog log) => _shared[log] ??= ErrorReporter(log);

  static final _shared = Expando<ErrorReporter>('errorReporter');

  /// How long an identical error stays suppressed.
  static const window = Duration(seconds: 30);

  /// Most reports kept in one minute.
  static const maxPerMinute = 20;

  /// Innermost frames always kept; the rest are the first kartka frames.
  static const _innerFrames = 2;

  /// Where reports go.
  final DiagnosticsLog log;

  final DateTime Function() _now;
  final _lastSeen = <String, DateTime>{};
  DateTime? _minute;
  int _inMinute = 0;
  bool _busy = false;

  /// Repeats currently remembered by the guard (for tests).
  int get tracked => _lastSeen.length;

  /// Records [error] (with [stack]) as a [kind] entry, unless suppressed;
  /// [sourceId] names the source involved, if any.
  void report(
    String kind,
    Object? error, {
    StackTrace? stack,
    String? sourceId,
  }) {
    if (_busy) return;
    _busy = true;
    try {
      final at = _now();
      final entry = DiagnosticEntry.failure(
        at: at,
        kind: kind,
        error: error,
        stack: _focus(stack),
        sourceId: sourceId,
      );
      if (_allowed('$kind|${entry.error}', at)) unawaited(log.append(entry));
    } on Object {
      // An error whose toString throws: nothing sensible to record.
    } finally {
      _busy = false;
    }
  }

  bool _allowed(String key, DateTime at) {
    _lastSeen.removeWhere((_, seen) => at.difference(seen) >= window);
    if (_lastSeen.containsKey(key)) return false;
    final minute = _minute;
    if (minute == null || at.difference(minute) >= const Duration(minutes: 1)) {
      _minute = at;
      _inMinute = 0;
    }
    if (_inMinute >= maxPerMinute) return false;
    _inMinute++;
    _lastSeen[key] = at;
    return true;
  }

  /// The innermost frames, then the first `package:kartka/` frames, so a
  /// framework-deep stack still names the app code that triggered it.
  static StackTrace? _focus(StackTrace? stack) {
    if (stack == null) return null;
    final frames = [
      for (final line in '$stack'.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    final kept = [
      ...frames.take(_innerFrames),
      ...frames.skip(_innerFrames).where((f) => f.contains('package:kartka/')),
    ];
    return StackTrace.fromString(kept.join('\n'));
  }
}
