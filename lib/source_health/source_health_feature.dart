import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/app/screen_observer.dart';
import 'package:kartka/app/settings_stores.dart';
import 'package:kartka/browse/browse_routes.dart';
import 'package:kartka/browse/source_registry.dart';
import 'package:kartka/core/diagnostics/diagnostics_log.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/migration/better/better_route.dart';
import 'package:kartka/platform/agent_probe.dart';
import 'package:kartka/source_health/feed/reporting_feed.dart';
import 'package:kartka/source_health/feed/rtdb_feed.dart';
import 'package:kartka/source_health/feed/source_health_feed.dart';
import 'package:kartka/source_health/install/extension_autoupdate.dart';
import 'package:kartka/source_health/install/install_ports.dart';
import 'package:kartka/source_health/install/keep_reconciler.dart';
import 'package:kartka/source_health/install/source_installs.dart';
import 'package:kartka/source_health/install/source_probe.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/scoring/profile_store.dart';
import 'package:kartka/source_health/scoring/scored_feed.dart';
import 'package:kartka/source_health/source_health_lookup_impl.dart';
import 'package:kartka/source_health/ui/sources_tab.dart';
import 'package:kartka/sync/rtdb_reader.dart';

/// The source-health part: fills the Sources tab (with Install / Open per
/// source) and supplies Browse's `SourceHealthLookup`, both fed from RTDB
/// `/kartka/source_health` and re-scored with the synced scoring profile
/// (`sourceHealth.scoring`). Also installs every Keep source, and every
/// source a library entry uses, on its own ([KeepReconciler], a service the
/// migration part reads with the feed), and updates every outdated
/// Suwayomi extension once a day ([ExtensionAutoUpdater]).
KartkaFeature sourceHealthFeature(KartkaEnv env) {
  final store = ScoringProfileStore(syncedKv(env));
  final feed = ScoredHealthFeed(
    _RegistryFeed(() => env.registry.maybe<RtdbReader>()),
    store,
  );
  final diagnostics = DiagnosticsLog.of(env.platform.diagnostics);
  SuwayomiExtensionInstaller? suwayomi() =>
      env.registry.maybe<SuwayomiExtensionInstaller>();
  PluginRepoInstaller? plugins() => env.registry.maybe<PluginRepoInstaller>();
  // Built on first use: the registry is complete only then, and the source
  // list subscribes to every provider.
  late final sources = SourceRegistry.fromRegistry(env.registry);
  final autoInstall = KeepReconciler(
    kv: env.platform.kv,
    probe: (id) => probeSource(sources, id),
    suwayomi: suwayomi,
    plugins: plugins,
    diagnostics: diagnostics,
    librarySources: () => librarySourceIds(env.registry),
  );
  final autoUpdate = ExtensionAutoUpdater(
    kv: env.platform.kv,
    updater: () => env.registry.maybe<SuwayomiExtensionUpdater>(),
    isAgent: isAgentInstance,
    diagnostics: diagnostics,
  );
  // Reconciles on start and on every new publish (DOCS-contracts-source-
  // health §5 "Keep auto-install"), and updates stale extensions, from the
  // app's first screen on: a bare registry (tests, tools) never starts.
  final startOnFirstScreen = _OnFirstScreen(() {
    unawaited(autoInstall.start(feed));
    unawaited(autoUpdate.run());
  });
  late final installs = SourceInstalls(
    sourceIds: sources.watch().map((all) => {for (final s in all) s.ref.id}),
    open: (context, id) => unawaited(context.push(sourceRoute(id))),
    suwayomi: suwayomi,
    plugins: plugins,
    diagnostics: diagnostics,
    autoInstall: autoInstall,
  );
  return KartkaFeature(
    id: 'source-health',
    tabs: {
      KartkaTab.sources: (_) => SourcesTab(
        feed: ReportingHealthFeed(
          feed,
          DiagnosticsLog.of(env.platform.diagnostics),
        ),
        scoring: store,
        installs: installs,
        autoInstall: autoInstall,
        onMigrate: (context) => unawaited(context.push(betterSourcesRoute)),
      ),
    },
    services: [
      FeedSourceHealthLookup(feed),
      feed,
      autoInstall,
      autoUpdate,
      startOnFirstScreen,
    ],
  );
}

/// The source ids of the library's entries, re-emitted when they change;
/// none without a library part (a bare registry).
Stream<Set<String>> librarySourceIds(KartkaRegistry registry) {
  final library = registry.maybe<LibraryRepositories>()?.library;
  if (library == null) return Stream.value(const {});
  return library.watch().map((all) => {for (final e in all) e.sourceId});
}

/// Runs its callback on the first screen report only.
class _OnFirstScreen implements ScreenObserver {
  new(this._run);

  void Function()? _run;

  @override
  void screenChanged(String pattern) {
    final run = _run;
    _run = null;
    run?.call();
  }
}

/// Resolves the sync part's [RtdbReader] lazily: the registry is only
/// complete after every factory has run.
class _RegistryFeed implements SourceHealthFeed {
  new(this._reader);

  final RtdbReader? Function() _reader;

  @override
  Stream<List<SourceHealthRecord>> watch() {
    final reader = _reader();
    if (reader == null) {
      return Stream.error(
        StateError('Source health is read through sync, which is not set up.'),
      );
    }
    return RtdbSourceHealthFeed(reader).watch();
  }

  /// Without sync the records stream already shows the error; the header
  /// just falls back to counting records.
  @override
  Stream<SourceHealthMeta?> watchMeta() {
    final reader = _reader();
    return reader == null
        ? Stream.value(null)
        : RtdbSourceHealthFeed(reader).watchMeta();
  }
}
