import 'package:kartka/platform/blob_store.dart';
import 'package:kartka/platform/file_picker.dart';
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/platform/oauth_redirect.dart';

export 'blob_store.dart';
export 'file_picker.dart';
export 'http_client.dart';
export 'image_headers.dart';
export 'key_value_store.dart';
export 'oauth_redirect.dart';
export 'page_image.dart';

/// Every platform service, bundled so features take one argument.
///
/// Built by `createPlatform()` (`lib/platform/create_platform.dart`), which
/// picks the io (Android) or web implementations by conditional import.
/// Tests build one from the in-memory fakes in `lib/platform/memory/`.
class KartkaPlatform {
  /// Bundles the given services.
  const new({
    required this.http,
    required this.blobs,
    required this.kv,
    required this.secrets,
    required this.filePicker,
    required this.oauth,
  });

  /// Network client (direct on Android, `/proxy` on web).
  final KartkaHttp http;

  /// Downloaded pages and covers.
  final BlobStore blobs;

  /// Small persistent state. Never put credentials here: use [secrets].
  final KeyValueStore kv;

  /// Credentials (Suwayomi basic auth, AniList / MAL tokens). Android: the
  /// Keystore via flutter_secure_storage. Web: the desktop wrapper's
  /// `/secrets/` routes, backed by a 0600 file in `~/.config/kartka/`
  /// (never IndexedDB, which any script on the origin can dump).
  final KeyValueStore secrets;

  /// CBZ / folder import.
  final FilePicker filePicker;

  /// OAuth sign-in round trip.
  final OAuthRedirect oauth;
}
