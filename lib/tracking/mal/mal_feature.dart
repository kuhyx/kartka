/// The MyAnimeList part's [KartkaFeature]: supplies a [MalTracker] as a
/// `Tracker` service (contracts §10) for `TrackingService` to pick up.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:kartka/app/feature.dart';
import 'package:kartka/tracking/mal/mal_api.dart';
import 'package:kartka/tracking/mal/mal_auth.dart';
import 'package:kartka/tracking/mal/mal_http.dart';
import 'package:kartka/tracking/mal/mal_session.dart';
import 'package:kartka/tracking/mal/mal_tokens.dart';
import 'package:kartka/tracking/mal/mal_tracker.dart';

/// Android client id, baked in from `~/.config/kartka/oauth.json` with
/// `--dart-define-from-file` (written by tools/tracking/register_mal.sh).
const malAndroidClientId = String.fromEnvironment(
  'KARTKA_MAL_CLIENT_ID_ANDROID',
);

/// Web (desktop Chrome app) client id, same source.
const malWebClientId = String.fromEnvironment('KARTKA_MAL_CLIENT_ID_WEB');

/// Feature factory for `kartkaFeatureFactories`.
///
/// Without a client id for this platform (no oauth.json at build time) the
/// feature registers no tracker, so the app still builds and runs.
/// [isWeb] and [clientId] exist for tests.
KartkaFeature malFeature(
  KartkaEnv env, {
  bool isWeb = kIsWeb,
  String? clientId,
}) {
  final id = clientId ?? (isWeb ? malWebClientId : malAndroidClientId);
  if (id.isEmpty) return const KartkaFeature(id: 'tracking-mal');
  final platform = env.platform;
  final send = malSendVia(platform.http);
  // Tokens are credentials: KartkaPlatform.secrets, never kv (§13).
  final store = StringMalTokenStore(
    read: platform.secrets.get,
    write: platform.secrets.set,
    delete: platform.secrets.remove,
  );
  final auth = MalAuth(
    client: MalOAuthClient(
      clientId: id,
      redirectUri: platform.oauth.redirectUri.toString(),
    ),
    send: send,
    store: store,
    launch: platform.oauth.authorize,
  );
  final session = MalSession(auth: auth, store: store, send: send);
  return KartkaFeature(
    id: 'tracking-mal',
    services: [
      MalTracker(
        auth: auth,
        store: store,
        api: MalApi(clientId: id, send: send, session: session),
      ),
    ],
  );
}
