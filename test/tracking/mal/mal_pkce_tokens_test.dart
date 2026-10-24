import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' as glados;
import 'package:kartka/tracking/mal/mal_pkce.dart';
import 'package:kartka/tracking/mal/mal_tokens.dart';

import 'mal_fakes.dart';

void main() {
  group('PKCE', () {
    test('verifier is 128 unreserved characters', () {
      final verifier = malCodeVerifier(Random(1));
      expect(verifier, hasLength(128));
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(verifier), isTrue);
    });

    test('state is shorter but from the same alphabet', () {
      final state = malState(Random(2));
      expect(state, hasLength(32));
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(state), isTrue);
    });

    test('rejects verifier lengths outside 43..128', () {
      expect(() => malCodeVerifier(Random(), length: 42), throwsArgumentError);
      expect(() => malCodeVerifier(Random(), length: 129), throwsArgumentError);
    });

    test('MAL only supports plain: the challenge is the verifier', () {
      expect(malCodeChallengeMethod, 'plain');
      expect(malCodeChallenge('abc'), 'abc');
    });
  });

  group('MalTokens', () {
    test('built from a token response with expires_in', () {
      final json = jsonDecode(fixture('token_ok.json')) as Map<String, Object?>;
      final tokens = MalTokens.fromTokenResponse(json, testNow);
      expect(tokens.accessToken, 'access-1');
      expect(tokens.refreshToken, 'refresh-1');
      expect(tokens.expiresAt, testNow.add(const Duration(seconds: 2678400)));
    });

    test('token response missing fields is rejected', () {
      expect(
        () => MalTokens.fromTokenResponse({'access_token': 'a'}, testNow),
        throwsFormatException,
      );
    });

    test('expired five minutes before expiresAt', () {
      final tokens = validTokens();
      expect(tokens.isExpired(testNow), isFalse);
      final edge = tokens.expiresAt.subtract(const Duration(minutes: 5));
      expect(tokens.isExpired(edge), isTrue);
    });

    glados.Glados2(
      glados.any.lowercaseLetters,
      glados.any.intInRange(0, 1 << 31),
    ).test('JSON round-trips', (access, seconds) {
      final tokens = MalTokens(
        accessToken: access,
        refreshToken: 'r$access',
        expiresAt: DateTime.fromMillisecondsSinceEpoch(seconds, isUtc: true),
      );
      final back = MalTokens.fromJson(
        jsonDecode(jsonEncode(tokens.toJson())) as Map<String, Object?>,
      );
      expect(back, tokens);
      expect(back.hashCode, tokens.hashCode);
    });

    test('fromJson rejects malformed data', () {
      expect(() => MalTokens.fromJson({}), throwsFormatException);
      expect(
        () => MalTokens.fromJson({
          'accessToken': 'a',
          'refreshToken': 'b',
          'expiresAt': 'not a date',
        }),
        throwsFormatException,
      );
    });

    test('toString hides the secrets', () {
      expect(validTokens().toString(), isNot(contains('access-0')));
    });
  });

  group('StringMalTokenStore', () {
    late Map<String, String> backing;
    late StringMalTokenStore store;

    setUp(() {
      backing = {};
      store = StringMalTokenStore(
        read: (k) async => backing[k],
        write: (k, v) async => backing[k] = v,
        delete: (k) async => backing.remove(k),
      );
    });

    test('write, read, clear', () async {
      expect(await store.read(), isNull);
      await store.write(validTokens());
      expect(backing.keys, [StringMalTokenStore.defaultKey]);
      expect(await store.read(), validTokens());
      await store.clear();
      expect(await store.read(), isNull);
    });

    test('corrupt stored value reads as logged out', () async {
      backing[StringMalTokenStore.defaultKey] = '{not json';
      expect(await store.read(), isNull);
      backing[StringMalTokenStore.defaultKey] = '[1]';
      expect(await store.read(), isNull);
    });
  });
}
