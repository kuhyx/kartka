/// Which settings sync (DOCS-contracts-runtime §16). Everything else stays
/// on the device: the download queue and storage, tracker tokens, the sync
/// credentials, per-manga reader modes. The wrapper port is a constant.
library;

import 'package:kartka/core/settings/settings_sync.dart';
import 'package:kartka/sync/rtdb_transport.dart';

/// One synced setting: its platform store, and how the UI names it.
typedef SyncedSetting = ({SettingsVault vault, String label});

/// The auto-download toggle's store key (`autoDownloadKvKey`).
const String kAutoDownloadSetting = 'downloads/auto_new_chapters';

/// Synced settings by store key. A peer's node for any other key is ignored.
const Map<String, SyncedSetting> kSyncedSettings = {
  'suwayomi.serverUrl': (
    vault: SettingsVault.plain,
    label: 'Suwayomi server URL',
  ),
  'suwayomi.username': (
    vault: SettingsVault.secret,
    label: 'Suwayomi username',
  ),
  'suwayomi.password': (
    vault: SettingsVault.secret,
    label: 'Suwayomi password',
  ),
  'mangadex.settings': (vault: SettingsVault.plain, label: 'MangaDex settings'),
  'reader.settings': (vault: SettingsVault.plain, label: 'Reader settings'),
  'plugins.repos': (vault: SettingsVault.plain, label: 'Plugin repos'),
  kAutoDownloadSetting: (vault: SettingsVault.plain, label: 'Auto-download'),
};

/// `settings/<key>`, the key escaped into one RTDB segment.
String settingPath(String key) => 'settings/${rtdbKey(key)}';
