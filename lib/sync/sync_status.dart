/// What the sync account screen shows.
library;

import 'package:crdt_sync/crdt_sync.dart' show RemoteSyncError;
import 'package:kartka/core/redact.dart';

/// Coarse sync state.
enum SyncPhase {
  /// No account on this device; the app works locally only.
  signedOut,

  /// Signed in and up to date (as of [SyncStatus.lastSync]).
  idle,

  /// A pull or push is running.
  syncing,

  /// The last attempt failed; local changes are kept and retried.
  error,
}

/// Immutable snapshot of the engine's state.
class SyncStatus {
  /// Creates a status.
  const new({required this.phase, this.lastSync, this.message});

  /// [SyncPhase.error] for [error]. A [RemoteSyncError] shows its message
  /// minus URL queries; anything else (a bug, whose message may quote a URL
  /// or a token) shows only its type.
  new failed(Object error, {this.lastSync})
    : phase = SyncPhase.error,
      message = error is RemoteSyncError
          ? redactUrlQueries(error.message)
          : 'unexpected ${error.runtimeType}';

  /// Current phase.
  final SyncPhase phase;

  /// When a full sync last completed, if ever.
  final DateTime? lastSync;

  /// Error detail for [SyncPhase.error].
  final String? message;

  /// Copy with [phase] replaced, keeping [lastSync].
  SyncStatus copyWith({required SyncPhase phase}) =>
      SyncStatus(phase: phase, lastSync: lastSync);

  @override
  bool operator ==(Object other) =>
      other is SyncStatus &&
      other.phase == phase &&
      other.lastSync == lastSync &&
      other.message == message;

  @override
  int get hashCode => Object.hash(phase, lastSync, message);

  @override
  String toString() => 'SyncStatus($phase, $lastSync, $message)';
}
