import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/source/challenge.dart';
import 'package:kartka/platform/challenge_detect.dart';
import 'package:kartka/platform/http_client.dart';

KartkaResponse res(int status, String body, [Map<String, String>? h]) =>
    KartkaResponse(
      statusCode: status,
      bodyBytes: utf8.encode(body),
      headers: h ?? const {},
    );

void main() {
  test('cf-mitigated: challenge is cloudflare at any status', () {
    expect(
      challengeKindOf(res(200, '', {'cf-mitigated': 'challenge'})),
      'cloudflare',
    );
  });

  test('blocking statuses with a marker are challenges', () {
    expect(
      challengeKindOf(res(503, '<title>Just a moment...</title>')),
      'cloudflare',
    );
    expect(
      challengeKindOf(res(403, '<script>window._cf_chl_opt={}</script>')),
      'cloudflare',
    );
    expect(
      challengeKindOf(res(403, '<div class="g-recaptcha"></div>')),
      'captcha',
    );
    expect(
      challengeKindOf(res(429, '<div class="h-captcha"></div>')),
      'captcha',
    );
    expect(
      challengeKindOf(res(403, '<title>DDoS-Guard</title>')),
      'ddos-guard',
    );
  });

  test('ordinary pages and plain errors are not challenges', () {
    expect(challengeKindOf(res(200, 'solve the captcha in chapter 3')), isNull);
    expect(challengeKindOf(res(200, '<div class="g-recaptcha">')), isNull);
    expect(challengeKindOf(res(403, 'Forbidden')), isNull);
    expect(challengeKindOf(res(404, 'Just a moment...')), isNull);
  });

  test('ChallengeRequired names its url and kind', () {
    final c = ChallengeRequired(Uri.parse('https://a.test/'), 'captcha');
    expect('$c', 'ChallengeRequired(captcha, https://a.test/)');
  });
}
