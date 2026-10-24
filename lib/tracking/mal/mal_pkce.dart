/// PKCE helpers for MyAnimeList OAuth2.
library;

import 'dart:math';

const _alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

/// The only `code_challenge_method` MAL accepts.
///
/// MAL does not support S256: a hashed challenge fails the exchange with
/// "Failed to verify `code_verifier`" (MAL forum, topic of
/// forum/message/60163774, post #29; MAL OAuth guide, blog eid=835707).
/// Do not "upgrade" this to S256.
const malCodeChallengeMethod = 'plain';

/// A random PKCE verifier of [length] (43..128) unreserved characters.
String malCodeVerifier(Random random, {int length = 128}) {
  if (length < 43 || length > 128) {
    throw ArgumentError.value(length, 'length', 'must be 43..128');
  }
  return _randomString(random, length);
}

/// A random OAuth `state` value.
String malState(Random random) => _randomString(random, 32);

/// The challenge for [verifier] under the `plain` method: the verifier.
String malCodeChallenge(String verifier) => verifier;

String _randomString(Random random, int length) => String.fromCharCodes(
  List.generate(
    length,
    (_) => _alphabet.codeUnitAt(random.nextInt(_alphabet.length)),
  ),
);
