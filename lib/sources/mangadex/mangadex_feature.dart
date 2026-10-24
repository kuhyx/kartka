import 'package:kartka/app/feature.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/sources/mangadex/mangadex_image_headers.dart';
import 'package:kartka/sources/mangadex/mangadex_settings_store.dart';
import 'package:kartka/sources/mangadex/mangadex_settings_tile.dart';
import 'package:kartka/sources/mangadex/mangadex_source.dart';

/// The MangaDex part: the native source, its settings tile and store, and
/// the image headers MangaDex hosts need.
KartkaFeature mangadexFeature(KartkaEnv env) {
  final store = MangadexSettingsStore(env.platform.kv);
  final source = MangaDexSource(http: env.platform.http, settings: store);
  return KartkaFeature(
    id: 'source-mangadex',
    settingsTiles: [(_) => MangadexSettingsTile(store: store)],
    services: [
      StaticSourceProvider([source]),
      const MangadexImageHeaders(),
      store,
    ],
  );
}
