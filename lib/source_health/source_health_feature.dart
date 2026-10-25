import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/app/settings_stores.dart';
import 'package:kartka/browse/browse_routes.dart';
import 'package:kartka/browse/source_registry.dart';
import 'package:kartka/core/diagnostics/diagnostics_log.dart';
import 'package:kartka/source_health/feed/rtdb_feed.dart';
import 'package:kartka/source_health/feed/source_health_feed.dart';
import 'package:kartka/source_health/install/install_ports.dart';
import 'package:kartka/source_health/install/source_installs.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/scoring/profile_store.dart';
import 'package:kartka/source_health/scoring/scored_feed.dart';
import 'package:kartka/source_health/source_health_lookup_impl.dart';
import 'package:kartka/source_health/ui/sources_tab.dart';
import 'package:kartka/sync/rtdb_reader.dart';

/// The source-health part: fills the Sources tab (with Install / Open per
/// source) and supplies Browse's `SourceHealthLookup`, both fed from RTDB `/kartka/source_health` and
/// re-scored with the synced scoring profile (`sourceHealth.scoring`).
KartkaFeature sourceHealthFeature(KartkaEnv env) {
  final store = ScoringProfileStore(syncedKv(env));
  final feed = ScoredHealthFeed(
    _RegistryFeed(() => env.registry.maybe<RtdbReader>()),
    store,
  );
  // Built on first use: the registry is complete only then, and the source
  // list subscribes to every provider.
  late final installs = SourceInstalls(
    sourceIds: SourceRegistry.fromRegistry(env.registry)
        .watch()
        .map((all) => {for (final s in all) s.ref.id}),
    open: (context, id) => unawaited(context.push(sourceRoute(id))),
    suwayomi: () => env.registry.maybe<SuwayomiExtensionInstaller>(),
    plugins: () => env.registry.maybe<PluginRepoInstaller>(),
    diagnostics: DiagnosticsLog.of(env.platform.diagnostics),
  );
  return KartkaFeature(
    id: 'source-health',
    tabs: {
      KartkaTab.sources: (_) =>
          SourcesTab(feed: feed, scoring: store, installs: installs),
    },
    services: [FeedSourceHealthLookup(feed)],
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
