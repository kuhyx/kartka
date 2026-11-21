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
///
/// `suwayomi.serverUrl` stays on its device (todo ff807202): the phone runs
/// extensions in-app and must never point at the desktop's server.
const Map<String, SyncedSetting> kSyncedSettings = {
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
  'browse.contentType': (
    vault: SettingsVault.plain,
    semanticLabel: 'Browse content type',
  ),
  kAutoDownloadSetting: (
    vault: SettingsVault.plain,
    semanticLabel: 'Auto-download',
  ),
  // Auto-shelving's memory (`autoShelveMemoryKey`): synced, so a manual
  // move-out sticks on every device, not only the one that shelved it.
  'library.autoshelve': (
    vault: SettingsVault.plain,
    semanticLabel: 'Auto-shelve memory',
  ),
  // Extensions the user uninstalled (`UninstallMarks`): synced, because
  // every desktop drives one Suwayomi server, and kuhy's "keep only these"
  // holds on the phone too; the Keep auto-install skips them everywhere.
  'sourceHealth.userUninstalled': (
    vault: SettingsVault.plain,
    semanticLabel: 'Uninstalled extensions',
  ),
  // The source-health scoring profile; the evaluator reads it too.
  'sourceHealth.scoring': (
    vault: SettingsVault.plain,
    semanticLabel: 'Source scoring profile',
  ),
};

/// `settings/<key>`, the key escaped into one RTDB segment.
String settingPath(String key) => 'settings/${rtdbKey(key)}';
