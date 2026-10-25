/// The sync engine's one-at-a-time operation queue.
library;

import 'dart:async';

import 'package:crdt_sync/crdt_sync.dart' show RemoteSyncError;
import 'package:kartka/core/diagnostics/diagnostic_entry.dart';
import 'package:kartka/core/diagnostics/diagnostics_log.dart';
import 'package:kartka/core/redact.dart';

/// A whole http(s) URL. Its path may name the account (`users/<uid>/`), so
/// a sync diagnostics line drops it entirely, not just its query.
final _url = RegExp(r'''https?://[^\s"'<>]*''', caseSensitive: false);

String _scrub(String text) => redactUrlQueries(text).replaceAll(_url, '<url>');

/// Runs sync operations strictly one after another.
///
/// A failing operation rejects only its own future: the queue carries on
/// with the next one. A [RemoteSyncError] is the engine's to report (as a
/// status); anything else is a bug, logged to [diagnostics] as `sync.error`
/// with its type and a message stripped of URLs.
class SyncQueue {
  /// A queue stamping logged failures with the time from the given clock.
  new(this._now, {this.diagnostics});

  /// Where unexpected failures are recorded; null logs nothing.
  final DiagnosticsLog? diagnostics;

  final DateTime Function() _now;
  Future<void> _tail = Future.value();

  /// Runs [job] once every earlier job has settled; its error reaches only
  /// the returned future.
  Future<void> run(Future<void> Function() job) {
    final result = _tail.then((_) => job());
    _tail = result.then((_) {}, onError: _log);
    return result;
  }

  void _log(Object error, StackTrace stack) {
    if (error is RemoteSyncError) return;
    final type = '${error.runtimeType}';
    final message = _scrub('$error');
    unawaited(
      diagnostics?.append(
        DiagnosticEntry.failure(
          at: _now(),
          kind: 'sync.error',
          // `FormatException.toString` already names its type; a TypeError's
          // does not, so the type leads unless the message starts with it.
          error: message.startsWith(type) ? message : '$type: $message',
          stack: StackTrace.fromString(_scrub('$stack')),
        ),
      ),
    );
  }
}
