import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/tracking/mal/mal_auth.dart';
import 'package:kartka/tracking/mal/mal_transport.dart';

import 'mal_fakes.dart';

const _client = MalOAuthClient(clientId: 'cid', redirectUri: 'kartka://oauth');

void main() {
  late FakeTransport http;
  late MemoryTokenStore store;
  Uri? launched;
  late Uri Function(Uri authorize) callback;

  MalAuth build() => MalAuth(
    client: _client,
    send: http.send,
    store: store,
    launch: (uri) async {
      launched = uri;
      return callback(uri);
    },
    random: Random(7),
    now: () => testNow,
  );

  Uri okCallback(Uri authorize) => Uri.parse(
    'kartka://oauth?code=the-code'
    '&state=${authorize.queryParameters['state']}',
  );

  setUp(() {
    http = FakeTransport((_) => fx(200, 'token_ok.json'));
    store = MemoryTokenStore();
    launched = null;
    callback = okCallback;
  });

  test('authorize URL carries the plain PKCE challenge', () {
    final uri = build().authorizeUrl('v' * 43, 'st');
    expect(uri.toString(), startsWith(malAuthorizeEndpoint));
    expect(uri.queryParameters, {
      'response_type': 'code',
      'client_id': 'cid',
      'code_challenge': 'v' * 43,
      'code_challenge_method': 'plain',
      'state': 'st',
      'redirect_uri': 'kartka://oauth',
    });
  });

  test(
    'login exchanges the code with the same verifier and redirect',
    () async {
      final tokens = await build().login();
      expect(tokens.accessToken, 'access-1');
      expect(store.tokens, tokens);
      final request = http.requests.single;
      expect(request.method, MalMethod.post);
      expect(request.url, Uri.parse(malTokenEndpoint));
      expect(
        request.headers['Content-Type'],
        'application/x-www-form-urlencoded',
      );
      final form = Uri.splitQueryString(request.body!);
      expect(form, {
        'client_id': 'cid',
        'grant_type': 'authorization_code',
        'code': 'the-code',
        'code_verifier': launched!.queryParameters['code_challenge'],
        'redirect_uri': 'kartka://oauth',
      });
      expect(form.containsKey('client_secret'), isFalse);
    },
  );

  test('login rejects a callback with the wrong state', () async {
    callback = (_) => Uri.parse('kartka://oauth?code=c&state=forged');
    await expectLater(build().login(), throwsA(isA<MalAuthException>()));
    expect(http.requests, isEmpty);
    expect(store.tokens, isNull);
  });

  test('login surfaces a denied consent', () async {
    callback = (a) => Uri.parse(
      'kartka://oauth?error=access_denied'
      '&state=${a.queryParameters['state']}',
    );
    await expectLater(
      build().login(),
      throwsA(
        isA<MalAuthException>().having(
          (e) => e.message,
          'message',
          contains('access_denied'),
        ),
      ),
    );
  });

  test('login without a code fails', () async {
    callback = (a) =>
        Uri.parse('kartka://oauth?state=${a.queryParameters['state']}');
    await expectLater(build().login(), throwsA(isA<MalAuthException>()));
  });

  test('a rejected code exchange stores nothing', () async {
    http.handler = (_) => fx(400, 'invalid_grant.json');
    await expectLater(
      build().login(),
      throwsA(
        isA<MalAuthException>().having((e) => e.statusCode, 'status', 400),
      ),
    );
    expect(store.tokens, isNull);
  });

  test('refresh rotates both tokens', () async {
    http.handler = (_) => fx(200, 'token_refreshed.json');
    store.tokens = validTokens();
    final fresh = await build().refresh(validTokens());
    expect(fresh.accessToken, 'access-2');
    expect(fresh.refreshToken, 'refresh-2');
    expect(store.tokens, fresh);
    expect(Uri.splitQueryString(http.requests.single.body!), {
      'client_id': 'cid',
      'grant_type': 'refresh_token',
      'refresh_token': 'refresh-0',
    });
  });

  test('failed refresh logs out', () async {
    http.handler = (_) => fx(400, 'invalid_grant.json');
    store.tokens = validTokens();
    await expectLater(
      build().refresh(validTokens()),
      throwsA(isA<MalAuthException>()),
    );
    expect(store.tokens, isNull);
  });

  test('a non-JSON token body is an auth failure', () async {
    http.handler = (_) => const MalResponse(200, '<html>');
    await expectLater(build().login(), throwsA(isA<MalAuthException>()));
  });

  test('exception toString names the status', () {
    expect(
      const MalAuthException('nope', statusCode: 401).toString(),
      'MalAuthException(401): nope',
    );
    expect(const MalException('x').toString(), 'MalException: x');
  });
}
