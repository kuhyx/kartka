/// The platform stores as features should hand them to their settings
/// stores, so writes to synced settings reach sync (contracts §16).
library;

import 'package:kartka/app/feature.dart';
import 'package:kartka/core/settings/settings_sync.dart';

export 'package:kartka/core/settings/settings_sync.dart';

/// `env.platform.kv`, reporting writes to the registered [SettingsSync].
SyncedKeyValueStore syncedKv(KartkaEnv env) =>
    SyncedKeyValueStore(env.platform.kv, SettingsVault.plain, () => _of(env));

/// `env.platform.secrets`, reporting writes to the registered [SettingsSync].
SyncedKeyValueStore syncedSecrets(KartkaEnv env) => SyncedKeyValueStore(
  env.platform.secrets,
  SettingsVault.secret,
  () => _of(env),
);

// Called only after the registry is built (see SyncedKeyValueStore).
SettingsSync? _of(KartkaEnv env) => env.registry.maybe<SettingsSync>();
