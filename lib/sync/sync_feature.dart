/// The sync part's feature (contracts §3, §10, §13): the repository
/// decorator, the read-only [RtdbReader], and More → Sync.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/sync/decorators/sync_repository_decorator.dart';
import 'package:kartka/sync/polling_rtdb_reader.dart';
import 'package:kartka/sync/rtdb_reader.dart';
import 'package:kartka/sync/sync_engine.dart';
import 'package:kartka/sync/sync_runtime.dart';
import 'package:kartka/sync/ui/sync_account_controller.dart';
import 'package:kartka/sync/ui/sync_account_screen.dart';

/// Route of the sync account screen.
const String syncAccountRoute = '/more/sync';

/// The registry entry: production runtime over the platform's storage.
KartkaFeature syncFeature(KartkaEnv env) => syncFeatureWith(
  SyncRuntime(
    kv: env.platform.kv,
    openTransport: () => openFirebaseTransport(env.platform.http),
  ),
);

/// The feature over [runtime]; nothing starts until a repo or the account
/// screen first needs the engine.
KartkaFeature syncFeatureWith(SyncRuntime runtime) => KartkaFeature(
  id: 'sync',
  routes: [
    GoRoute(
      path: syncAccountRoute,
      builder: (context, state) => SyncAccountRoute(runtime: runtime),
    ),
  ],
  settingsTiles: [
    (context) => ListTile(
      leading: const Icon(Icons.cloud_sync_outlined),
      title: const Text('Sync'),
      subtitle: const Text('Account, status, sync now'),
      onTap: () => context.push(syncAccountRoute),
    ),
  ],
  services: <Object>[
    SyncRepositoryDecorator(() => runtime.engine),
    PollingRtdbReader(runtime.transport) as RtdbReader,
  ],
);

/// Waits for the engine, then shows [SyncAccountScreen].
class SyncAccountRoute extends StatelessWidget {
  /// Shows the account screen for [runtime].
  const new({required this.runtime, super.key});

  /// The sync runtime.
  final SyncRuntime runtime;

  @override
  Widget build(BuildContext context) => FutureBuilder<SyncEngine>(
    future: runtime.engine,
    builder: (context, snap) {
      final engine = snap.data;
      if (engine == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Sync')),
          body: Center(
            child: snap.hasError
                ? Text('Sync could not start: ${snap.error}')
                : const CircularProgressIndicator(),
          ),
        );
      }
      return SyncAccountScreen(
        controller: EngineAccountController(engine, runtime),
      );
    },
  );
}
