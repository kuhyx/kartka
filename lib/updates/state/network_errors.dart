/// Which update-check failures are the network's, not the source's.
///
/// Matched on the error's text: `lib/updates` may not import `dart:io` or
/// `package:http` (import boundaries), and their exceptions reach here
/// wrapped (`ClientException with SocketException: ...`) anyway.
library;

import 'dart:async';

final _transient = RegExp(
  'Failed host lookup|Network is unreachable|No route to host|'
  'Connection reset|connection abort|Connection closed|Connection refused|'
  r'Connection timed out|timed out|: timeout\b|HandshakeException',
  caseSensitive: false,
);

final _offline = RegExp(
  'Failed host lookup|Network is unreachable|No route to host',
  caseSensitive: false,
);

/// Whether [error] is worth retrying: a lookup, connection or timeout
/// failure (Suwayomi's own upstream timeout included), not a source error.
bool isTransientNetworkError(Object error) =>
    error is TimeoutException || _transient.hasMatch('$error');

/// Whether [error] means the server cannot be reached at all (no DNS
/// answer, no route): checking more of its manga would fail the same way.
bool isOfflineError(Object error) => _offline.hasMatch('$error');
