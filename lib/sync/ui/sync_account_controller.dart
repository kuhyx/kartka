/// What the sync account screen drives, behind an interface so widget tests
/// need no keystore, Firebase or engine.
library;

import 'package:crdt_sync_flutter/crdt_sync_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:kartka/sync/google_client.dart';
import 'package:kartka/sync/settings/synced_settings.dart';
import 'package:kartka/sync/sync_config.dart';
import 'package:kartka/sync/sync_engine.dart';
import 'package:kartka/sync/sync_runtime.dart';
import 'package:kartka/sync/sync_status.dart';
import 'package:kartka/sync/ui/google_route.dart';
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

  /// Synced-settings problems by key, e.g. a secret this device can't open;
  /// the current map first, then every change.
  Stream<Map<String, String>> watchProblems();

  /// Whether this device has a sync passphrase of its own.
  Future<bool> hasPassphrase();

  /// Sets or changes this device's sync passphrase (§16).
  Future<void> setPassphrase(String passphrase);
}

/// The production controller over a started engine.
class EngineAccountController implements SyncAccountController {
  /// Drives [engine]; account changes go through [runtime], the passphrase
  /// through [settings] (none: no synced secrets to key).
  new(this.engine, this.runtime, [this.settings]);

  /// The started engine.
  final SyncEngine engine;

  /// Owner of the cached session.
  final SyncRuntime runtime;

  /// The synced settings service.
  final SyncedSettings? settings;

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

  @override
  Stream<Map<String, String>> watchProblems() =>
      settings?.watchProblems() ?? Stream.value(const {});

  @override
  Future<bool> hasPassphrase() async =>
      await settings?.passphrase.isSet ?? false;

  @override
  Future<void> setPassphrase(String passphrase) async =>
      await settings?.setPassphrase(passphrase);
}

/// This build's Google route: the plugin on Android, the GIS button on the
/// web (desktop) build.
GoogleRoute get platformGoogleRoute => googleRouteFor(
  isWeb: kIsWeb,
  pluginSupported: googleSignInSupported(kKartkaGoogleClientId),
  clientId: kKartkaGoogleClientId,
);

/// The shared sign-in / sign-out screen (sync_settings_ui) wired to
/// crdt_sync_flutter's keystore-backed account store.
///
/// [route] and [sources] exist for tests; production takes the platform's.
Widget buildAccountSettingsScreen({
  GoogleRoute? route,
  GoogleTokenSources sources = const GoogleTokenSources(),
}) {
  final google = route ?? platformGoogleRoute;
  final offered = google != GoogleRoute.none;
  // A Builder so the web route has a context under the Navigator for its
  // dialog; the shared screen's factory takes no arguments.
  return Builder(
    builder: (context) => SyncSettingsScreen(
      accountLoader: kartkaSyncAccess.loadAccount,
      accountSaver: saveAccount,
      accountClearer: clearAccount,
      sessionProbe: () => isSyncConfigured(kKartkaSync),
      firebaseFactory: kartkaSyncAccess.openSync,
      googleFirebaseFactory: offered
          ? () => signInWithGoogle(
              kKartkaSync,
              tokenFetcher: () =>
                  fetchGoogleIdToken(context, google, sources: sources),
            )
          : null,
      // No unavailable reason (textgate: no painted sentence); without one
      // the shared screen simply omits the Google button.
      googleAvailable: offered,
    ),
  );
}
