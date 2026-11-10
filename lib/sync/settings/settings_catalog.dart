/// Which settings sync (DOCS-contracts-runtime §16). Everything else stays
/// on the device: the download queue and storage, tracker tokens, the sync
/// credentials, per-manga reader modes. The wrapper port is a constant.
library;

import 'package:kartka/core/settings/settings_sync.dart';
import 'package:kartka/sync/rtdb_transport.dart';

/// One synced setting: its platform store, and the spoken name that sync
/// problems use (never painted: textgate).
typedef SyncedSetting = ({SettingsVault vault, String semanticLabel});

/// The auto-download toggle's store key (`autoDownloadKvKey`).
const String kAutoDownloadSetting = 'downloads/auto_new_chapters';

/// Synced settings by store key. A peer's node for any other key is ignored.
const Map<String, SyncedSetting> kSyncedSettings = {
  'suwayomi.serverUrl': (
    vault: SettingsVault.plain,
    semanticLabel: 'Suwayomi server URL',
  ),
  'suwayomi.username': (
    vault: SettingsVault.secret,
    semanticLabel: 'Suwayomi username',
  ),
  'suwayomi.password': (
    vault: SettingsVault.secret,
    semanticLabel: 'Suwayomi password',
  ),
  'mangadex.settings': (
    vault: SettingsVault.plain,
    semanticLabel: 'MangaDex settings',
  ),
  'reader.settings': (
    vault: SettingsVault.plain,
    semanticLabel: 'Reader settings',
  ),
  'plugins.repos': (vault: SettingsVault.plain, semanticLabel: 'Plugin repos'),
  'browse.languages': (
    vault: SettingsVault.plain,
    semanticLabel: 'Browse languages',
  ),
  kAutoDownloadSetting: (
    vault: SettingsVault.plain,
    semanticLabel: 'Auto-download',
  ),
  // The source-health scoring profile; the evaluator reads it too.
  'sourceHealth.scoring': (
    vault: SettingsVault.plain,
    semanticLabel: 'Source scoring profile',
  ),
};

/// `settings/<key>`, the key escaped into one RTDB segment.
String settingPath(String key) => 'settings/${rtdbKey(key)}';
