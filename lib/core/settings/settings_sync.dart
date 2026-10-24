/// Settings that follow kuhy across devices (DOCS-contracts-runtime §16).
///
/// Features keep their own settings stores. They hand those stores a
/// [SyncedKeyValueStore] instead of the platform's, and that wrapper reports
/// every write to the [SettingsSync] port, which sync supplies through
/// `KartkaFeature.services`. No feature talks to RTDB, and a key the sync
/// catalogue does not list never leaves the device.
library;

import 'package:kartka/platform/key_value_store.dart';

/// Which platform store a setting lives in.
enum SettingsVault {
  /// `KartkaPlatform.kv`: synced as is.
  plain,

  /// `KartkaPlatform.secrets`: encrypted on the device before upload.
  secret,
}

/// The settings sync port.
abstract interface class SettingsSync {
  /// Reports that [key] in [vault] was set to [value] (null: removed).
  ///
  /// Returns once the change is queued, never waiting for the network.
  /// Keys outside the sync catalogue are ignored.
  Future<void> changed(String key, String? value, SettingsVault vault);

  /// Keys whose local value a peer just replaced (already stored locally).
  Stream<String> get remoteChanges;

  /// Current sync problems by key, e.g. "Couldn't decrypt synced Suwayomi
  /// password"; emits the current map first, then every change.
  Stream<Map<String, String>> watchProblems();
}

/// A [KeyValueStore] over a local one that reports writes to sync.
///
/// [_sync] is looked up lazily: features build these while the registry is
/// still being built, and `KartkaEnv.registry` is set only afterwards.
class SyncedKeyValueStore implements KeyValueStore {
  /// Wraps [_local], the platform store for [_vault].
  const new(this._local, this._vault, this._sync);

  final KeyValueStore _local;
  final SettingsVault _vault;
  final SettingsSync? Function() _sync;

  @override
  Future<String?> get(String key) => _local.get(key);

  @override
  Future<Map<String, String>> entries({String prefix = ''}) =>
      _local.entries(prefix: prefix);

  @override
  Future<void> set(String key, String value) async {
    await _local.set(key, value);
    await _sync()?.changed(key, value, _vault);
  }

  @override
  Future<void> remove(String key) async {
    await _local.remove(key);
    await _sync()?.changed(key, null, _vault);
  }

  /// [SettingsSync.remoteChanges], or nothing when sync is not registered.
  Stream<String> get remoteChanges => _later((s) => s.remoteChanges);

  /// [SettingsSync.watchProblems], or nothing when sync is not registered.
  Stream<Map<String, String>> watchProblems() =>
      _later((s) => s.watchProblems());

  Stream<T> _later<T>(Stream<T> Function(SettingsSync sync) pick) async* {
    // A factory may subscribe; the registry exists once it has returned.
    await Future<void>.value();
    final sync = _sync();
    if (sync != null) yield* pick(sync);
  }
}
