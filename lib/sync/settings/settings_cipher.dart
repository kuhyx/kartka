/// On-device encryption of synced secrets (DOCS-contracts-runtime §16).
///
/// AES-256-GCM under a key derived from the sync account's password with
/// PBKDF2-HMAC-SHA256. Every record carries its own random salt and nonce,
/// so RTDB (and the persisted sync shadow) only ever hold ciphertext. The
/// setting's key is the GCM associated data: a record cannot be replayed as
/// another setting. On web `cryptography` runs both through WebCrypto.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// PBKDF2 rounds for new records; also the minimum a record may claim.
const int kPbkdf2Iterations = 200000;

// Bounds what a record may ask a device to compute.
const _maxIterations = 10000000;
const _version = 1;
const _kdf = 'pbkdf2-hmac-sha256';
const _macLength = 16;

/// Seals and opens secret setting values.
class SettingsCipher {
  /// A cipher deriving keys with [iterations] PBKDF2 rounds.
  new({this.iterations = kPbkdf2Iterations, Random? random})
    : _random = random ?? Random.secure();

  /// Rounds for new records, and the fewest an opened record may use.
  final int iterations;

  final Random _random;
  final Map<String, Future<SecretKey>> _keys = {};
  static final _aes = AesGcm.with256bits();

  /// Number of derived keys held in memory.
  int get cachedKeys => _keys.length;

  /// Encrypts [plaintext] for the setting [context].
  Future<Map<String, Object?>> seal(
    String plaintext, {
    required String password,
    required String context,
  }) async {
    final salt = _bytes(16);
    final nonce = _bytes(12);
    final box = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: await _key(password, salt, iterations),
      nonce: nonce,
      aad: utf8.encode(context),
    );
    return {
      'v': _version,
      'kdf': _kdf,
      'iter': iterations,
      'salt': base64.encode(salt),
      'nonce': base64.encode(nonce),
      'ct': base64.encode([...box.cipherText, ...box.mac.bytes]),
    };
  }

  /// The plaintext of [record], or null when it is malformed, weaker than
  /// [iterations], tampered with, or sealed under another password/context.
  Future<String?> open(
    Object? record, {
    required String password,
    required String context,
  }) async {
    if (record is! Map) return null;
    final iter = record['iter'];
    if (record['v'] != _version || record['kdf'] != _kdf) return null;
    if (iter is! int || iter < iterations || iter > _maxIterations) return null;
    try {
      final salt = base64.decode('${record['salt']}');
      final nonce = base64.decode('${record['nonce']}');
      final ct = base64.decode('${record['ct']}');
      if (nonce.length != 12 || ct.length < _macLength) return null;
      final cut = ct.length - _macLength;
      final clear = await _aes.decrypt(
        SecretBox(ct.sublist(0, cut), nonce: nonce, mac: Mac(ct.sublist(cut))),
        secretKey: await _key(password, salt, iter),
        aad: utf8.encode(context),
      );
      return utf8.decode(clear);
    } on Exception {
      // Bad base64/UTF-8, a wrong nonce length, or a failed GCM tag.
      return null;
    }
  }

  Future<SecretKey> _key(String password, List<int> salt, int rounds) {
    final id = '$rounds:${base64.encode(salt)}:$password';
    // A handful of settings, each with one salt: the cache stays tiny.
    if (_keys.length > 64) _keys.clear();
    return _keys[id] ??= Pbkdf2.hmacSha256(
      iterations: rounds,
      bits: 256,
    ).deriveKeyFromPassword(password: password, nonce: salt);
  }

  Uint8List _bytes(int n) =>
      Uint8List.fromList([for (var i = 0; i < n; i++) _random.nextInt(256)]);
}
