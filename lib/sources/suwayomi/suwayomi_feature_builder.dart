import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/app/settings_stores.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/sources/suwayomi/suwayomi_client.dart';
import 'package:kartka/sources/suwayomi/suwayomi_extensions.dart';
import 'package:kartka/sources/suwayomi/suwayomi_settings.dart';
import 'package:kartka/sources/suwayomi/suwayomi_source.dart';
import 'package:kartka/sources/suwayomi/suwayomi_source_provider.dart';
import 'package:kartka/sources/suwayomi/ui/extensions_screen.dart';
import 'package:kartka/sources/suwayomi/ui/suwayomi_settings_screen.dart';

/// Route of the Suwayomi settings screen.
const suwayomiSettingsRoute = '/suwayomi';

/// Route of the Suwayomi extensions screen.
const suwayomiExtensionsRoute = '/suwayomi/extensions';

/// The Suwayomi-Server part: one source per installed extension source,
/// basic-auth image headers for the server, settings and extensions screens.
///
/// [titleOf] finds the library title of a manga the server has not seen.
KartkaFeature buildSuwayomiFeature(KartkaEnv env, {TitleLookup? titleOf}) {
  final platform = env.platform;
  // Synced to the user's other devices; the credentials encrypted (§16).
  final kv = syncedKv(env);
  final secrets = syncedSecrets(env);
  final store = SuwayomiSettingsStore(
    kv: kv,
    secrets: secrets,
    reloadOn: kv.remoteChanges,
  );
  // Load now (kv + secrets only, no network) so image headers and the
  // extensions screen work before Browse ever watches the sources.
  unawaited(store.load());
  SuwayomiSettings current() => store.current ?? const SuwayomiSettings();
  final client = SuwayomiClient(http: platform.http, settings: current);
  final provider = SuwayomiSourceProvider(
    store: store,
    client: client,
    titleOf: titleOf,
  );
  final extensions = SuwayomiExtensionsApi(
    client: client,
    settings: current,
    onChanged: provider.refresh,
  );
  return KartkaFeature(
    id: 'source-suwayomi',
    // The extensions API is the Sources tab's Install port.
    services: [provider, extensions],
    settingsTiles: [
      (context) => ListTile(
        leading: const Icon(Icons.dns_outlined),
        title: const Text('Suwayomi server'),
        subtitle: const Text('Server, login and extensions'),
        onTap: () => context.push(suwayomiSettingsRoute),
      ),
    ],
    routes: [
      GoRoute(
        path: suwayomiSettingsRoute,
        builder: (context, _) => SuwayomiSettingsScreen(
          store: store,
          testConnection: (s) => SuwayomiClient(
            http: platform.http,
            settings: () => s,
          ).testConnection(),
          onOpenExtensions: () => context.push(suwayomiExtensionsRoute),
          syncProblems: secrets.watchProblems().map(
            (p) => [
              for (final MapEntry(:key, :value) in p.entries)
                if (SuwayomiSettingsStore.keys.contains(key)) value,
            ],
          ),
        ),
      ),
      GoRoute(
        path: suwayomiExtensionsRoute,
        builder: (_, _) => ExtensionsScreen(
          api: extensions,
          diagnostics: DiagnosticsLog.of(platform.diagnostics),
        ),
      ),
    ],
  );
}
