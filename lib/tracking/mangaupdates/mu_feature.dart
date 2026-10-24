/// The MangaUpdates part's [KartkaFeature]: supplies a [MangaUpdatesTracker]
/// as a `Tracker` service (contracts §10) and a login tile in More.
library;

import 'package:kartka/app/feature.dart';
import 'package:kartka/platform/platform.dart';
import 'package:kartka/tracking/mangaupdates/mu_api.dart';
import 'package:kartka/tracking/mangaupdates/mu_client.dart';
import 'package:kartka/tracking/mangaupdates/mu_session.dart';
import 'package:kartka/tracking/mangaupdates/mu_settings_tile.dart';
import 'package:kartka/tracking/mangaupdates/mu_tracker.dart';

/// Builds the tracker on [platform]: HTTP via `KartkaHttp`, the session
/// token in `secrets` (never `kv`, §13).
MangaUpdatesTracker buildMuTracker(KartkaPlatform platform) {
  final store = MuSessionStore(platform.secrets);
  return MangaUpdatesTracker(
    api: MuApi(
      client: MuClient(http: platform.http),
      store: store,
    ),
    store: store,
  );
}

/// Feature factory for `kartkaFeatureFactories`.
///
/// Unlike AniList and MAL there is nothing to configure (no OAuth client),
/// so the tracker is always registered.
KartkaFeature mangaUpdatesFeature(KartkaEnv env) {
  final tracker = buildMuTracker(env.platform);
  return KartkaFeature(
    id: 'tracking-mangaupdates',
    services: [tracker],
    settingsTiles: [(context) => MuSettingsTile(tracker: tracker)],
  );
}
