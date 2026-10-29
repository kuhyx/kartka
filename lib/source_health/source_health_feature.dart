import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/app/settings_stores.dart';
import 'package:kartka/browse/browse_routes.dart';
import 'package:kartka/browse/source_registry.dart';
import 'package:kartka/core/diagnostics/diagnostics_log.dart';
import 'package:kartka/migration/better/better_route.dart';
import 'package:kartka/source_health/feed/rtdb_feed.dart';
import 'package:kartka/source_health/feed/source_health_feed.dart';
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
/// (`sourceHealth.scoring`). Also installs every Keep source on its own
/// ([KeepReconciler], a service the migration part reads with the feed).
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
  );
  // Reconciles on start and on every new publish (DOCS-contracts-source-
  // health §5 "Keep auto-install"), once the registry is complete.
  scheduleMicrotask(() => unawaited(autoInstall.start(feed)));
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
        feed: feed,
        scoring: store,
        installs: installs,
        autoInstall: autoInstall,
        onMigrate: (context) => unawaited(context.push(betterSourcesRoute)),
      ),
    },
    services: [FeedSourceHealthLookup(feed), feed, autoInstall],
  );
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
