/// The stricter redaction applied before a diagnostics entry leaves the
/// device as an error report (RTDB, then a file on the PC).
library;

import 'package:kartka/core/redact.dart';

final _email = RegExp(r'[\w.+-]+@[\w-]+(\.[\w-]+)+');
final _bearer = RegExp(r'\b(Bearer|Basic)\s+[^\s,;]+', caseSensitive: false);
final _jwt = RegExp(r'eyJ[\w-]+\.[\w-]+\.[\w-]*');
final _named = RegExp(
  r'\b(cookie|set-cookie|authorization|password|passwd|token|secret|'
  r'api[_-]?key|session)\b(\s*[:=]\s*)[^\s,]+',
  caseSensitive: false,
);
final _home = RegExp(r'/(home|Users)/[^/\s]+/');

/// [text] passed through [redactUrlQueries], with emails, bearer and basic
/// credentials, JWTs, `name=value` secrets (cookie, password, token, ...)
/// and the user name in home-directory paths replaced.
///
/// Over-redaction is the cheap mistake here: a report that loses a word is
/// still fixable, one that leaks a token is not.
String redactForReport(String text) =>
    redactUrlQueries(text)
        .replaceAll(_jwt, '<jwt>')
        .replaceAllMapped(_bearer, (m) => '${m[1]} <redacted>')
        .replaceAllMapped(_named, (m) => '${m[1]}${m[2]}<redacted>')
        .replaceAll(_email, '<email>')
        .replaceAll(_home, '~/');
