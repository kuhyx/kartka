/// Which update-check and download failures are the network's, not the
/// source's, and which server a source's requests go to.
///
/// Matched on the error's text: only `lib/platform` may import `dart:io` or
/// `package:http` (import boundaries), and their exceptions reach here
/// wrapped (`ClientException with SocketException: ...`) anyway. Android
/// extension chapters fetch in Java (OkHttp), and only its message comes
/// back (`ExtensionRuntimeException`), so Java's texts are matched too:
/// `Unable to resolve host "<h>"` is its failed DNS lookup, and a bare
/// `timeout` its socket timeout (07626036: the phone's network dropping
/// mid-check).
library;

import 'dart:async';

final _transient = RegExp(
  'Failed host lookup|Unable to resolve host|Network is unreachable|'
  'No route to host|Connection reset|connection abort|Connection closed|'
  'Connection refused|'
  r'Connection timed out|timed out|: timeout\b|^timeout$|HandshakeException',
  caseSensitive: false,
);

final _offline = RegExp(
  'Failed host lookup|Unable to resolve host|Network is unreachable|'
  'No route to host',
  caseSensitive: false,
);

/// Whether [error] is worth retrying: a lookup, connection or timeout
/// failure (Suwayomi's own upstream timeout included), not a source error.
bool isTransientNetworkError(Object error) =>
    error is TimeoutException || _transient.hasMatch('$error');

/// Whether [error] means the server cannot be reached at all (no DNS
/// answer, no route): checking more of its manga would fail the same way.
bool isOfflineError(Object error) => _offline.hasMatch('$error');

final _environment = RegExp(
  'Failed host lookup|Unable to resolve host|Network is unreachable|'
  'No route to host|'
  'Name or service not known|connection abort|Connection reset|'
  'Connection refused|Timed out waiting for WebView|'
  r'KartkaHttpException\(50[0234],|not on the server for |gone from |'
  r'^timeout$',
  caseSensitive: false,
);

/// Whether [error] (an error or its logged text) is the environment's
/// state, not a bug: no network or DNS, a dropped connection, our server
/// down (5xx), its upstream site down or slow, a manga the server no
/// longer has. The screens show these (Retry, "not checked", cached
/// data); they stay in the device log and never become a PC ticket.
bool isEnvironmentError(Object error) => _environment.hasMatch('$error');

/// The server a source's requests go to: every `suwayomi:*` source is one
/// Suwayomi-Server, anything else its own host.
String serverOf(String sourceId) =>
    sourceId.startsWith('suwayomi:') ? 'suwayomi' : sourceId;
