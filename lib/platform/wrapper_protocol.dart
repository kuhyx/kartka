/// The HTTP contract between the web build and the desktop wrapper.
library;

/// The desktop wrapper's fixed loopback port: the one definition.
///
/// It cannot move once in use: the OAuth redirect registered at AniList and
/// MAL is `http://127.0.0.1:47391/oauth`, and the browser keys IndexedDB
/// (the app's data) by origin. Out of the crowded 87xx range on purpose
/// (sufler's TTS holds 8791). `desktop/` mirrors it; a test there reads this
/// file to keep the two equal.
const kartkaWrapperPort = 47391;

///
/// The wrapper is a separate pure-Dart package (`desktop/`) and cannot
/// import this file, so `desktop/lib/src/protocol.dart` repeats these
/// values; tests on both sides pin them to the same literals.
abstract final class KartkaWrapper {
  /// See [kartkaWrapperPort].
  static const int port = kartkaWrapperPort;

  /// Header every API call must carry (value `1`). A custom header makes a
  /// cross-site request non-simple, so other pages cannot reach the API
  /// without a CORS preflight the wrapper never grants.
  static const apiHeader = 'x-kartka';

  /// Prefix for upstream request headers sent through [proxyPath]; lets the
  /// page pass headers a browser forbids it to set (Referer, Cookie).
  static const requestHeaderPrefix = 'x-kartka-h-';

  /// Prefix for upstream response headers returned by [proxyPath]; exposes
  /// headers the browser hides from fetch (Set-Cookie).
  static const responseHeaderPrefix = 'x-kartka-r-';

  /// `<METHOD> /proxy?url=<absolute http(s) URL>`.
  static const proxyPath = '/proxy';

  /// `GET|PUT|DELETE /files/<blobKey>`, `GET /files?prefix=` (JSON list).
  static const filesPath = '/files';

  /// `GET|PUT|DELETE /secrets/<key>`, `GET /secrets?prefix=` (JSON map).
  static const secretsPath = '/secrets';

  /// OAuth redirect target (an HTML page that hands the URL back).
  static const oauthPath = '/oauth';

  /// `POST` (the callback page) / `GET` (the app; 204 while empty, consumed
  /// on read) / `DELETE` (clear a stale result).
  static const oauthResultPath = '/oauth/result';

  /// `GET`: a seeded Firebase session, served once per wrapper launch and
  /// only when the wrapper ran with `--sync-credentials` (the headless agent
  /// instance); 404 otherwise. DOCS-contracts-runtime §17.
  static const syncCredentialsPath = '/sync-credentials';
}
