/// The HTTP contract with the web build.
///
/// Mirrors `lib/platform/wrapper_protocol.dart` in the app, which this
/// package cannot import (the app is a Flutter package). Both sides pin
/// these values in tests.
library;

/// Fixed loopback port: the OAuth redirect is `http://127.0.0.1:47391/oauth`,
/// and the browser keys the app's IndexedDB by origin. Mirrors the app's
/// `kartkaWrapperPort` (lib/platform/wrapper_protocol.dart), the one
/// definition; test/protocol_test.dart fails if the two differ.
const kartkaPort = 47391;

/// Header (value `1`) every API call carries; makes cross-site requests
/// non-simple so they need a CORS preflight this server never grants.
const apiHeader = 'x-kartka';

/// Prefix of upstream request headers sent to `/proxy`.
const requestHeaderPrefix = 'x-kartka-h-';

/// Prefix of upstream response headers returned by `/proxy`.
const responseHeaderPrefix = 'x-kartka-r-';

/// Set on a 502 the proxy itself produced (upstream unreachable).
const proxyErrorHeader = 'x-kartka-proxy-error';

/// Route paths.
const proxyPath = '/proxy';

/// Blob files: `/files/<key>`, `/files?prefix=`.
const filesPath = '/files';

/// Secrets: `/secrets/<key>`, `/secrets?prefix=`.
const secretsPath = '/secrets';

/// OAuth redirect page.
const oauthPath = '/oauth';

/// OAuth result slot.
const oauthResultPath = '/oauth/result';

/// Same string as the app's `kartkaUserAgent`: honest, no personal data.
const kartkaUserAgent = 'Kartka/0.1 (+https://github.com/kuhyx/kartka)';

/// Methods `/proxy` forwards.
const proxyMethods = {'GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE'};
