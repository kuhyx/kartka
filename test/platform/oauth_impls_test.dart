import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kartka/platform/oauth_impls.dart';
import 'package:kartka/platform/platform.dart';
import 'package:kartka/platform/wrapper_protocol.dart';

void main() {
  group('DeepLinkOAuthRedirect', () {
    test('completes with the first kartka://oauth link', () async {
      final links = StreamController<Uri>.broadcast();
      final opened = <Uri>[];
      final oauth = DeepLinkOAuthRedirect(
        launch: (url) async {
          opened.add(url);
          links
            ..add(Uri.parse('kartka://other?x=1'))
            ..add(Uri.parse('https://oauth/'))
            ..add(Uri.parse('kartka://oauth?code=abc&state=s'));
          return true;
        },
        links: links.stream,
      );
      expect(oauth.redirectUri, Uri.parse('kartka://oauth'));
      final auth = Uri.parse('https://anilist.co/api/v2/oauth/authorize');
      final back = await oauth.authorize(auth);
      expect(back.queryParameters['code'], 'abc');
      expect(opened, [auth]);
      await links.close();
    });

    test('a failed launch or a timeout cancels', () async {
      final links = StreamController<Uri>.broadcast();
      final refused = DeepLinkOAuthRedirect(
        launch: (_) async => false,
        links: links.stream,
      );
      await expectLater(
        refused.authorize(Uri.parse('https://a/')),
        throwsA(isA<OAuthCancelled>()),
      );
      final silent = DeepLinkOAuthRedirect(
        launch: (_) async => true,
        links: links.stream,
      );
      await expectLater(
        silent.authorize(
          Uri.parse('https://a/'),
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<OAuthCancelled>()),
      );
      await links.close();
    });
  });

  group('WrapperOAuthRedirect', () {
    final base = Uri.parse('http://127.0.0.1:8791/');

    test('clears, opens, then polls /oauth/result until it lands', () async {
      var polls = 0;
      final calls = <String>[];
      final client = MockClient((r) async {
        expect(r.headers[KartkaWrapper.apiHeader], '1');
        expect(r.url.path, KartkaWrapper.oauthResultPath);
        calls.add(r.method);
        if (r.method == 'DELETE') return http.Response('', 204);
        polls++;
        return polls < 3
            ? http.Response('', 204)
            : http.Response(
                'http://127.0.0.1:8791/oauth#access_token=t&state=s',
                200,
              );
      });
      final opened = <Uri>[];
      final oauth = WrapperOAuthRedirect(
        client: client,
        base: base,
        open: opened.add,
        pollInterval: Duration.zero,
      );
      expect(oauth.redirectUri, Uri.parse('http://127.0.0.1:8791/oauth'));
      final back = await oauth.authorize(Uri.parse('https://anilist.co/x'));
      expect(back.fragment, 'access_token=t&state=s');
      expect(opened, [Uri.parse('https://anilist.co/x')]);
      expect(calls, ['DELETE', 'GET', 'GET', 'GET']);
    });

    test('gives up after the timeout', () async {
      final oauth = WrapperOAuthRedirect(
        client: MockClient((_) async => http.Response('', 204)),
        base: base,
        open: (_) {},
        pollInterval: const Duration(milliseconds: 1),
      );
      await expectLater(
        oauth.authorize(
          Uri.parse('https://a/'),
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<OAuthCancelled>()),
      );
    });
  });
}
