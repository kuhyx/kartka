/// Unlocks kartka's e2e key: Argon2id of the shared crdt-sync passphrase
/// (header at `kartka-e2e/e2e`), read from and cached in
/// `KartkaPlatform.secrets`: the Android Keystore, or on the web build the
/// wrapper's `/secrets` file, never browser storage. Until it opens, no
/// transport exists, so nothing is pulled or pushed (fail closed).
library;

import 'package:crdt_sync/crdt_sync.dart'
    show
        Argon2Params,
        E2eCipher,
        E2eLockReason,
        E2eLocked,
        E2eReady,
        RemoteStore,
        RemoteSyncError;
import 'package:crdt_sync_flutter/crdt_sync_flutter.dart'
    show openEncryptedStoreFromKeystore;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/sync/e2e/sealed_transport.dart';
import 'package:kartka/sync/rtdb_transport.dart';

/// Thrown by the transport opener while the key is locked; the engine shows
/// it as a failed sync and retries on the next poll.
class E2eLockedSyncError extends RemoteSyncError {
  /// Locked for [reason].
  new(this.reason) : super('e2e locked: ${reason.name}');

  /// Why the key did not open.
  final E2eLockReason reason;
}

/// The e2e key of this install.
class KartkaE2e {
  /// Keeps the passphrase and the derived key in [secrets]. [params] is
  /// the Argon2id cost of a header this device creates (lowered by tests).
  new(KeyValueStore secrets, {this.params = Argon2Params.recommended})
    : storage = SecretsSecureStorage(secrets);

  /// `KartkaPlatform.secrets` as crdt_sync_flutter's keystore type.
  final FlutterSecureStorage storage;

  /// Argon2id cost for a new header.
  final Argon2Params params;

  /// Whether the last unlock failed (drives the lock button).
  final ValueNotifier<bool> locked = ValueNotifier(false);

  /// The cipher for the e2e root [root] (rooted at `kartka-e2e`); throws
  /// [E2eLockedSyncError] while there is no (right) passphrase.
  Future<E2eCipher> unlock(RtdbTransport root) async {
    final state = await openEncryptedStoreFromKeystore(
      store: E2eHeaderStore(root),
      oldPrefix: kLegacyRoot,
      storage: storage,
      params: params,
    );
    locked.value = state is! E2eReady;
    if (state case E2eReady(:final store)) {
      return store.key.cipher(acceptPlaintext: false);
    }
    // E2eOff cannot come back once a key exists; treat it as unreadable.
    final reason = state is E2eLocked ? state.reason : E2eLockReason.badHeader;
    throw E2eLockedSyncError(reason);
  }
}

/// Just enough of crdt_sync's [RemoteStore] for the header: the one string
/// leaf `kartka-e2e/e2e`. Lists nothing, so crdt_sync's own log copy is a
/// no-op (kartka copies its tree itself, `legacy_import.dart`).
class E2eHeaderStore implements RemoteStore {
  /// Reads and writes the header through [_root].
  new(this._root);

  final RtdbTransport _root;

  String _rel(String path) {
    final prefix = '${kE2eLayout.prefix}/';
    if (!path.startsWith(prefix)) {
      throw RemoteSyncError('not under the e2e root: $path');
    }
    return path.substring(prefix.length);
  }

  @override
  Future<String?> getFileText(String path) async {
    final value = await _root.get(_rel(path));
    // Not a header anyone wrote: unlock reports badHeader, never overwrites.
    return value == null || value is String ? value as String? : '$value';
  }

  @override
  Future<void> putFileText(
    String path,
    String text, {
    required String message,
  }) => _root.patch({_rel(path): text});

  @override
  Future<List<String>> listDirectory(String path) async => const [];

  @override
  Future<void> deleteFile(String path, {String message = ''}) =>
      throw RemoteSyncError('kartka never deletes the e2e header');

  @override
  Future<bool> canAccessRemote() async => true;

  @override
  void close() {}
}

/// A [FlutterSecureStorage] over a [KeyValueStore], so crdt_sync_flutter's
/// passphrase and key cache land in `KartkaPlatform.secrets`.
class SecretsSecureStorage extends FlutterSecureStorage {
  /// Stores into [secrets].
  const new(this.secrets);

  /// The backing store.
  final KeyValueStore secrets;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => secrets.get(key);

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => value == null ? secrets.remove(key) : secrets.set(key, value);

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => secrets.remove(key);

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => secrets.entries();
}
