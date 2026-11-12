/// Starts sync lazily and owns its moving parts: the engine, the one cached
/// RTDB transport, and the foreground poll scheduler.
library;

import 'dart:async';

import 'package:crdt_sync/crdt_sync.dart'
    show FirebaseRestClient, FirebaseSyncError, RemoteSyncError;
import 'package:crdt_sync_flutter/crdt_sync_flutter.dart'
    show loadDeviceIdentity;
import 'package:kartka/core/diagnostics/diagnostics_log.dart';
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/sync/e2e/e2e_unlock.dart';
import 'package:kartka/sync/e2e/sealed_transport.dart';
import 'package:kartka/sync/firebase_transport.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_config.dart';
import 'package:kartka/sync/sync_engine.dart';
import 'package:kartka/sync/sync_scheduler.dart';
import 'package:kartka/sync/sync_shadow.dart';
import 'package:kartka/sync/sync_status.dart';

/// Opens the production transport: the sealed e2e root on a signed-in
/// crdt_sync client, or null while signed out. Throws
/// [E2eLockedSyncError] while [e2e] has no key: nothing is sent then.
///
/// [open] defaults to crdt_sync_flutter's `openSync` (via
/// [kartkaSyncAccess]); tests inject a fake.
Future<RtdbTransport?> openFirebaseTransport(
  KartkaHttp http,
  KartkaE2e e2e, {
  Future<FirebaseRestClient?> Function()? open,
}) async {
  try {
    final client = await (open ?? kartkaSyncAccess.openSync)();
    if (client == null) return null;
    FirebaseTransport at(String root) => FirebaseTransport(
      writer: FirebaseRestWriter(client),
      http: http,
      databaseUrl: kKartkaSync.project.databaseUrl,
      root: root,
    );
    final root = at(kE2eLayout.prefix);
    return SealedTransport(
      root,
      await e2e.unlock(root),
      legacy: LegacyTree(at(kLegacyRoot)),
    );
  } on RemoteSyncError {
    rethrow;
  } on Exception catch (e) {
    // A keystore, wrapper or plugin failure: report it as a sync error, so
    // the engine shows it on the account screen instead of crashing a poll.
    throw FirebaseSyncError('cannot open sync: $e');
  }
}

/// The sync part's runtime; nothing starts until [engine] is first read.
class SyncRuntime {
  /// Creates a runtime persisting into [kv].
  new({
    required this.kv,
    required this.openTransport,
    Future<String> Function()? deviceId,
    this.startScheduler = true,
    this.diagnostics,
    this.e2e,
  }) : _deviceId = deviceId ?? _persistedDeviceId;

  /// Where the shadow lives.
  final KeyValueStore kv;

  /// Opens a transport (signed in) or returns null (signed out).
  final Future<RtdbTransport?> Function() openTransport;

  /// Where the engine logs failures that are not sync errors (§7).
  final DiagnosticsLog? diagnostics;

  /// The e2e key, for the lock button (null in tests without one).
  final KartkaE2e? e2e;

  /// Whether starting the engine also starts foreground polling.
  final bool startScheduler;

  final Future<String> Function() _deviceId;
  RtdbTransport? _transport;

  /// This install's device id (`crdt.nodeId`).
  Future<String> deviceId() => _deviceId();

  /// Foreground polling, once started.
  SyncScheduler? scheduler;

  /// The engine, started on first read.
  late final Future<SyncEngine> engine = _start();

  final _started = Completer<SyncEngine>();

  /// Completes once something has started [engine]; never starts it.
  Future<SyncEngine> get started => _started.future;

  /// The shared, cached transport; null while signed out.
  Future<RtdbTransport?> transport() async =>
      _transport ??= await openTransport();

  /// Forgets the cached session after signing in or out, then resyncs.
  Future<void> accountChanged() async {
    _transport = null;
    final e = await engine;
    e.reset();
    await e.syncNow();
    // A signed-out device was backing off; poll at the normal pace again.
    scheduler?.kick();
  }

  Future<SyncEngine> _start() async {
    final e = SyncEngine(
      shadow: await SyncShadow.load(kv),
      deviceId: await _deviceId(),
      open: transport,
      diagnostics: diagnostics,
    );
    if (startScheduler) {
      scheduler = SyncScheduler(
        e.poll,
        onPause: e.flush,
        ok: () => e.status.phase == SyncPhase.idle,
      )..attach();
    }
    _started.complete(e);
    return e;
  }

  /// The per-install uuid crdt_sync_flutter persists under `crdt.nodeId`.
  static Future<String> _persistedDeviceId() async =>
      (await loadDeviceIdentity()).deviceId;
}
