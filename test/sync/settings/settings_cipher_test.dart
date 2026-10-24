import 'dart:convert';

import 'package:glados/glados.dart';
import 'package:kartka/sync/settings/settings_cipher.dart';

/// Low iterations keep the property runs fast; production uses
/// [kPbkdf2Iterations] (asserted below).
final _fast = SettingsCipher(iterations: 1000);

void main() {
  test('production PBKDF2 runs at least 200k iterations', () async {
    expect(kPbkdf2Iterations, greaterThanOrEqualTo(200000));
    final sealed = await SettingsCipher().seal(
      'pw',
      password: 'sync',
      context: 'k',
    );
    expect(sealed['iter'], kPbkdf2Iterations);
    expect(sealed['kdf'], 'pbkdf2-hmac-sha256');
  });

  Glados3(any.letterOrDigits, any.letterOrDigits, any.lowercaseLetters).test(
    'seal then open returns the plaintext',
    (text, password, context) async {
      // '-' is outside the base64 alphabet, so it can only leak verbatim.
      final plain = 'pw-$text';
      final sealed = await _fast.seal(
        plain,
        password: 'p$password',
        context: context,
      );
      expect(jsonEncode(sealed), isNot(contains('pw-')));
      expect(
        await _fast.open(sealed, password: 'p$password', context: context),
        plain,
      );
    },
  );

  Glados(any.letterOrDigits).test('a wrong password never opens', (pw) async {
    final sealed = await _fast.seal('secret', password: 'right', context: 'k');
    expect(await _fast.open(sealed, password: 'x$pw', context: 'k'), isNull);
  });

  test('salt and nonce are random per record', () async {
    final a = await _fast.seal('same', password: 'p', context: 'k');
    final b = await _fast.seal('same', password: 'p', context: 'k');
    expect(a['salt'], isNot(b['salt']));
    expect(a['nonce'], isNot(b['nonce']));
    expect(a['ct'], isNot(b['ct']));
    expect(base64.decode(a['salt']! as String), hasLength(16));
    expect(base64.decode(a['nonce']! as String), hasLength(12));
  });

  test('the context is authenticated: a record cannot be moved', () async {
    final sealed = await _fast.seal('pw', password: 'p', context: 'password');
    expect(
      await _fast.open(sealed, password: 'p', context: 'username'),
      isNull,
    );
  });

  test('tampering, malformed or weakened records are rejected', () async {
    final good = await _fast.seal('pw', password: 'p', context: 'k');
    Future<String?> open(Object? r) =>
        _fast.open(r, password: 'p', context: 'k');
    final ct = base64.decode(good['ct']! as String)..[0] ^= 1;
    expect(await open({...good, 'ct': base64.encode(ct)}), isNull);
    expect(
      await open({
        ...good,
        'ct': base64.encode([1, 2]),
      }),
      isNull,
    );
    expect(await open({...good, 'salt': '%%%'}), isNull);
    expect(await open({...good, 'iter': 10}), isNull);
    expect(await open({...good, 'iter': 'many'}), isNull);
    expect(await open({...good, 'v': 2}), isNull);
    expect(await open({...good, 'nonce': null}), isNull);
    expect(await open('not a record'), isNull);
    expect(await open(null), isNull);
    // A record from a stronger future setting still opens.
    final strong = SettingsCipher(iterations: 2000, random: Random(1));
    final sealed = await strong.seal('pw', password: 'p', context: 'k');
    expect(await open(sealed), 'pw');
  });

  test('derived keys are cached per salt', () async {
    final sealed = await _fast.seal('pw', password: 'p', context: 'k');
    final before = _fast.cachedKeys;
    for (var i = 0; i < 3; i++) {
      expect(await _fast.open(sealed, password: 'p', context: 'k'), 'pw');
    }
    expect(_fast.cachedKeys, before);
  });
}
