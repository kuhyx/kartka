import 'package:kartka/app/feature.dart';
import 'package:kartka/plugins/mangayomi/mangayomi_repo_adapter.dart';
import 'package:kartka/plugins/mangayomi/mangayomi_repo_service.dart';
import 'package:kartka/plugins/runtime/plugin_registrar.dart';

/// Mangayomi JS extensions as Kartka plugins (append `mangayomiFeature,`).
///
/// Services: the [MangayomiRepoAdapter] (a plugin repo type for the Plugins
/// screen) and the [MangayomiRepoService] that installs through the
/// runtime's `PluginRegistrar`. Sources come from the plugins feature's
/// `SourceProvider`; this feature provides none of its own.
KartkaFeature mangayomiFeature(KartkaEnv env) {
  final adapter = MangayomiRepoAdapter();
  return KartkaFeature(
    id: 'mangayomi',
    services: [
      adapter,
      MangayomiRepoService(
        http: env.platform.http,
        registrar: () => env.registry.maybe<PluginRegistrar>(),
        adapter: adapter,
      ),
    ],
  );
}
