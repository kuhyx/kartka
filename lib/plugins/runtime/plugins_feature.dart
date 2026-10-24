import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/registry.dart';
import 'package:kartka/plugins/runtime/engine.dart';
import 'package:kartka/plugins/runtime/engine_default.dart';
import 'package:kartka/plugins/runtime/kartka_host_services.dart';
import 'package:kartka/plugins/runtime/plugin_manager.dart';
import 'package:kartka/plugins/runtime/plugin_repo_adapter.dart';
import 'package:kartka/plugins/runtime/plugin_source_provider.dart';
import 'package:kartka/plugins/runtime/plugin_store.dart';
import 'package:kartka/plugins/runtime/plugins_screen.dart';
import 'package:kartka/plugins/runtime/third_party_licenses.g.dart';

/// Route of the Plugins screen.
const String pluginsRoute = '/plugins';

/// The plugin runtime feature (append `pluginsFeature,` to the registry).
///
/// Services: a `SourceProvider` of installed plugins, and the
/// `PluginManager` (which is the `PluginRegistrar` port the Mangayomi
/// converter uses). [engineFactory] is overridable for tests.
KartkaFeature pluginsFeature(
  KartkaEnv env, {
  JsEngineFactory engineFactory = createDefaultEngine,
}) {
  // The bundled HTML parser (MIT/BSD) must ship its notices in the app.
  LicenseRegistry.addLicense(
    () => Stream.value(
      const LicenseEntryWithLineBreaks([
        'node-html-parser (plugin HTML parser bundle)',
      ], kHtmlParserLicenses),
    ),
  );
  final store = PluginStore(env.platform.kv);
  final manager = PluginManager(
    http: env.platform.http,
    store: store,
    // Lazy: the registry is only complete after every factory has run.
    adapters: () => env.registry.all<PluginRepoAdapter>(),
  );
  final provider = PluginSourceProvider(
    registrar: manager,
    services: (id) =>
        KartkaHostServices(pluginId: id, http: env.platform.http, store: store),
    engineFactory: engineFactory,
  );
  return KartkaFeature(
    id: 'plugins',
    routes: [
      GoRoute(
        path: pluginsRoute,
        builder: (context, state) => PluginsScreen(manager: manager),
      ),
    ],
    settingsTiles: [
      (context) => ListTile(
        leading: const Icon(Icons.extension_outlined),
        title: const Text('Plugins'),
        subtitle: const Text('Install JS sources from a repository'),
        onTap: () => context.push(pluginsRoute),
      ),
    ],
    services: [provider, manager],
  );
}
