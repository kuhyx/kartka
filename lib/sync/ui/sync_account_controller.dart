/// What the sync account screen drives, behind an interface so widget tests
/// need no keystore, Firebase or engine.
library;

import 'package:crdt_sync_flutter/crdt_sync_flutter.dart';
import 'package:flutter/material.dart';
import 'package:kartka/sync/sync_config.dart';
import 'package:kartka/sync/sync_engine.dart';
import 'package:kartka/sync/sync_runtime.dart';
import 'package:kartka/sync/sync_status.dart';
import 'package:sync_settings_ui/sync_settings_ui.dart';

/// The sync account screen's view of sync.
abstract interface class SyncAccountController {
  /// Current status.
  SyncStatus get status;

  /// Status changes.
  Stream<SyncStatus> get changes;

  /// Full pull + push now.
  Future<void> syncNow();

  /// Cheap status check when the screen opens.
  Future<void> refresh();

  /// Opens the sign-in / sign-out screen; resyncs when it closes.
  Future<void> manageAccount(BuildContext context);
}

/// The production controller over a started engine.
class EngineAccountController implements SyncAccountController {
  /// Drives [engine]; account changes go through [runtime].
  new(this.engine, this.runtime);

  /// The started engine.
  final SyncEngine engine;

  /// Owner of the cached session.
  final SyncRuntime runtime;

  @override
  SyncStatus get status => engine.status;

  @override
  Stream<SyncStatus> get changes => engine.statusChanges;

  @override
  Future<void> syncNow() => engine.syncNow();

  @override
  Future<void> refresh() => engine.poll();

  @override
  Future<void> manageAccount(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => buildAccountSettingsScreen()),
    );
    await runtime.accountChanged();
  }
}

/// The shared sign-in / sign-out screen (sync_settings_ui) wired to
/// crdt_sync_flutter's keystore-backed account store.
Widget buildAccountSettingsScreen() => SyncSettingsScreen(
  accountLoader: loadAccount,
  accountSaver: saveAccount,
  accountClearer: clearAccount,
  sessionProbe: () => isSyncConfigured(kKartkaSync),
  firebaseFactory: () => openSync(kKartkaSync),
  // No Android OAuth client is registered for Kartka's package yet, and
  // the desktop build is web, where GIS only signs in via its own button.
  googleAvailable: false,
  googleUnavailableReason:
      'Google sign-in is not set up for Kartka; use email and password.',
);
