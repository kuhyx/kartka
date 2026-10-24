import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/oauth_redirect.dart';
import 'package:kartka/tracking/anilist/anilist_auth.dart';

import '../fakes.dart';

final Uri _web = Uri.parse('http://127.0.0.1:8791/oauth');
final Uri _android = Uri.parse('kartka://oauth');
final _t0 = DateTime.utc(2026, 10, 24, 12);

Uri _granted(Uri base, {String token = 'TOK', String expires = '31536000'}) =>
    base.replace(
      fragment: 'access_token=$token&token_type=Bearer&expires_in=$expires',
    );

void main() {
  late MemoryKv secrets;
  var now = _t0;

  AniListAuth auth(FakeOAuth oauth, {String android = 'A', String web = 'W'}) =>
      AniListAuth(
        secrets: secrets,
        oauth: oauth,
        clientIds: AniListClientIds(android: android, web: web),
        now: () => now,
      );

  setUp(() {
    secrets = MemoryKv();
    now = _t0;
  });

  test('web login uses the web client id and stores the token', () async {
    final oauth = FakeOAuth(_web, result: _granted(_web));
    final a = auth(oauth);
    await a.login();
    expect(
      oauth.opened.single.toString(),
      'https://anilist.co/api/v2/oauth/authorize?client_id=W&response_type=token',
    );
    expect(await a.token(), 'TOK');
    final stored =
        jsonDecode(secrets.data[AniListAuth.tokenKey]!) as Map<String, Object?>;
    expect(stored['expiresAt'], '2027-10-24T12:00:00.000Z');
  });

  test('android login uses the android client id', () async {
    final oauth = FakeOAuth(_android, result: _granted(_android));
    await auth(oauth).login();
    expect(oauth.opened.single.queryParameters['client_id'], 'A');
  });

  test('missing client id fails before opening the browser', () async {
    final oauth = FakeOAuth(_web, result: _granted(_web));
    await expectLater(auth(oauth, web: '').login(), throwsStateError);
    expect(oauth.opened, isEmpty);
  });

  test('a denied grant stores nothing', () async {
    final oauth = FakeOAuth(
      _web,
      result: _web.replace(query: 'error=access_denied'),
    );
    final a = auth(oauth);
    await expectLater(a.login(), throwsA(isA<AniListAuthError>()));
    expect(await a.token(), isNull);
    expect(
      const AniListAuthError('access_denied').toString(),
      contains('access_denied'),
    );
  });

  test('a redirect without a token is an error', () async {
    final oauth = FakeOAuth(_web, result: _web);
    await expectLater(auth(oauth).login(), throwsA(isA<AniListAuthError>()));
  });

  test('cancelled sign-in propagates', () async {
    final oauth = FakeOAuth(_web, error: const OAuthCancelled());
    await expectLater(auth(oauth).login(), throwsA(isA<OAuthCancelled>()));
  });

  test('an expired token reads as logged out', () async {
    final a = auth(FakeOAuth(_web, result: _granted(_web, expires: '60')));
    await a.login();
    now = _t0.add(const Duration(seconds: 61));
    expect(await a.token(), isNull);
  });

  test('missing expires_in keeps the token without expiry', () async {
    final redirect = _web.replace(fragment: 'access_token=X');
    final a = auth(FakeOAuth(_web, result: redirect));
    await a.login();
    now = _t0.add(const Duration(days: 4000));
    expect(await a.token(), 'X');
  });

  test('corrupt stored token reads as logged out', () async {
    secrets.data[AniListAuth.tokenKey] = 'not json';
    expect(await auth(FakeOAuth(_web)).token(), isNull);
  });

  test('logout forgets the token', () async {
    final a = auth(FakeOAuth(_web, result: _granted(_web)));
    await a.login();
    await a.logout();
    expect(await a.token(), isNull);
  });

  test('fromEnvironment reads dart-defines (empty in tests)', () {
    const ids = AniListClientIds.fromEnvironment();
    expect(ids.forRedirect(_web), isNull);
    expect(ids.forRedirect(_android), isNull);
  });
}
