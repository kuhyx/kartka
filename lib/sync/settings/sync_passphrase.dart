/// The sync passphrase (DOCS-contracts-runtime §16): what synced secrets
/// are sealed under on a device that signed in with Google, which leaves
/// crdt_sync_flutter an empty sync password.
///
/// Entered once per device and kept in `KartkaPlatform.secrets` under a key
/// the sync catalogue does not list, so it never leaves the device. A device
/// without one falls back to its sync account password, as before.
library;

import 'package:crdt_sync_flutter/crdt_sync_flutter.dart' show storedAccount;
import 'package:kartka/platform/key_value_store.dart';

/// The sync account password crdt_sync_flutter keeps in the keystore, or
/// null when this device has none (a Google or seeded-session sign-in).
Future<String?> storedSyncPassword() async {
  final password = (await storedAccount())?.password;
  return password == null || password.isEmpty ? null : password;
}

/// The passphrase's key in the secret store.
const String kSyncPassphraseKey = 'sync.passphrase';

/// This device's key source for synced secrets.
class SyncPassphrase {
  /// Reads and writes [secrets]; [fallback] is the sync password.
  const new(this.secrets, {this.fallback = storedSyncPassword});

  /// The platform's secret store (written directly, never synced).
  final KeyValueStore secrets;

  /// The sync account password; null when this device has none.
  final Future<String?> Function() fallback;

  /// Whether this device has a passphrase of its own.
  Future<bool> get isSet async => await _stored() != null;

  /// The passphrase, else the sync password, else null.
  Future<String?> key() async => await _stored() ?? await fallback();

  /// Stores [passphrase]; it must not be empty.
  Future<void> set(String passphrase) {
    if (passphrase.isEmpty) {
      throw ArgumentError.value(passphrase, 'passphrase', 'is empty');
    }
    return secrets.set(kSyncPassphraseKey, passphrase);
  }

  Future<String?> _stored() async {
    final stored = await secrets.get(kSyncPassphraseKey);
    return stored == null || stored.isEmpty ? null : stored;
  }
}
