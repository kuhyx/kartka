import 'package:kartka/platform/http_client.dart';

/// Statuses an interstitial is served with.
const _blocking = {403, 429, 503};

/// Body markers, checked in order: (lower-case needle, kind).
const _markers = [
  ('<title>just a moment', 'cloudflare'),
  ('<title>attention required', 'cloudflare'),
  ('cf_chl_opt', 'cloudflare'),
  ('/cdn-cgi/challenge-platform/', 'cloudflare'),
  ('id="challenge-form"', 'cloudflare'),
  ('cf-turnstile', 'cloudflare'),
  ('<title>ddos-guard', 'ddos-guard'),
  ('g-recaptcha', 'captcha'),
  ('h-captcha', 'captcha'),
];

/// The challenge [response] is (`cloudflare`, `captcha`, `ddos-guard`),
/// or null (docs/DOCS-contracts-webview.md §2): `cf-mitigated: challenge`
/// at any status, otherwise a blocking status (403 / 429 / 503) carrying a
/// marker. A normal page mentioning "captcha" is never one.
String? challengeKindOf(KartkaResponse response) {
  if (response.headers['cf-mitigated']?.toLowerCase() == 'challenge') {
    return 'cloudflare';
  }
  if (!_blocking.contains(response.statusCode)) return null;
  final body = response.body.toLowerCase();
  for (final (needle, kind) in _markers) {
    if (body.contains(needle)) return kind;
  }
  return null;
}
