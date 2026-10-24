import 'dart:convert';

import 'package:glados/glados.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/settings/settings_catalog.dart';
import 'package:kartka/sync/settings/sync_passphrase.dart';

import '../fakes.dart';
import 'settings_harness.dart';

const _user = 'suwayomi.username';
const _pass = 'suwayomi.password';

/// Two Google-signed-in devices (no sync password) over one RTDB.
Future<List<SettingsDevice>> _googleDevices(InMemoryRtdb db, TestClock c) =>
    Future.wait([
      for (final id in ['dev-a', 'dev-b'])
        SettingsDevice.create(id, db, clock: c, password: null),
    ]);

Map<String, Object?> _enc(InMemoryRtdb db, String key) =>
    ((db.tree['settings']! as Map)[rtdbKey(key)]! as Map)['enc']!
        as Map<String, Object?>;

void main() {
  Glados2(any.nonEmptyLetterOrDigits, any.letterOrDigits).test(
    'one passphrase on two Google devices round-trips any secret, and '
    'neither the secret nor the passphrase is ever uploaded',
    (x, value) async {
      // '-' is outside base64, so neither can appear inside a ciphertext.
      final passphrase = 'Passphrase-$x';
      final db = InMemoryRtdb();
      final clock = TestClock();
      final [a, b] = await _googleDevices(db, clock);
      await a.settings.setPassphrase(passphrase);
      await b.settings.setPassphrase(passphrase);
      final secret = 'Secret-$value';
      await a.secrets.set(_pass, secret);
      await a.settle();
      await b.poll();
      expect(await b.secretsLocal.get(_pass), secret);
      expect(await b.settings.watchProblems().first, isEmpty);
      final uploaded = jsonEncode(db.tree);
      final persisted = [
        for (final d in [a, b]) ...[
          ...(await d.shadowKv.entries()).values,
          ...(await d.local.entries()).values,
        ],
      ].join('\n');
      for (final leak in [secret, passphrase]) {
        expect(uploaded, isNot(contains(leak)));
        expect(persisted, isNot(contains(leak)));
      }
    },
  );

  late InMemoryRtdb db;
  late TestClock clock;
  setUp(() {
    db = InMemoryRtdb();
    clock = TestClock();
  });

  test('the passphrase stays in the secret store, outside the catalogue', () {
    expect(kSyncedSettings, isNot(contains(kSyncPassphraseKey)));
  });

  test('a value saved before the passphrase uploads once it is set', () async {
    final [a, b] = await _googleDevices(db, clock);
    await a.secrets.set(_user, 'kuhy');
    await a.settle();
    expect(db.tree['settings'], isNull);
    await a.settings.setPassphrase('pp');
    await b.settings.setPassphrase('pp');
    await b.poll();
    expect(await b.secretsLocal.get(_user), 'kuhy');
    expect(await a.settings.watchProblems().first, isEmpty);
  });

  test('a node that arrived first applies when the passphrase is set, '
      'without restarting the engine', () async {
    final [a, b] = await _googleDevices(db, clock);
    await a.settings.setPassphrase('pp');
    await a.secrets.set(_pass, 'from-a');
    await a.settle();
    await b.poll();
    expect(await b.secretsLocal.get(_pass), isNull);
    expect(await b.settings.watchProblems().first, contains(_pass));
    await b.settings.setPassphrase('pp');
    expect(await b.secretsLocal.get(_pass), 'from-a');
    expect(await b.settings.watchProblems().first, isEmpty);
  });

  test('a wrong passphrase on a device without the value deletes nothing, '
      'and its stale value never overwrites a newer peer value', () async {
    final [a, b] = await _googleDevices(db, clock);
    await b.secretsLocal.set(_user, 'stale');
    await a.settings.setPassphrase('right');
    await a.secrets.set(_pass, 'from-a');
    clock.advance();
    await a.secrets.set(_user, 'newer');
    await a.settle();
    await b.poll();
    final before = jsonEncode(db.tree);
    await b.settings.setPassphrase('wrong');
    await b.settle();
    expect(jsonEncode(db.tree), before);
    expect(await b.secretsLocal.get(_user), 'stale');
    expect(await b.settings.watchProblems().first, contains(_pass));
  });

  test("changing the passphrase re-seals this device's secrets", () async {
    final [a, b] = await _googleDevices(db, clock);
    await a.settings.setPassphrase('one');
    await b.settings.setPassphrase('one');
    await a.secrets.set(_pass, 'v');
    await a.settle();
    await b.poll();
    clock.advance();
    await a.settings.setPassphrase('two');
    await a.settle();
    final cipher = testCipher;
    final enc = _enc(db, _pass);
    expect(await cipher.open(enc, password: 'one', context: _pass), isNull);
    expect(await cipher.open(enc, password: 'two', context: _pass), 'v');
    clock.advance();
    await a.secrets.set(_pass, 'w');
    await a.settle();
    await b.poll();
    expect(await b.secretsLocal.get(_pass), 'v');
    await b.settings.setPassphrase('two');
    expect(await b.secretsLocal.get(_pass), 'w');
  });

  test('without a passphrase the sync password still keys secrets', () async {
    final a = await SettingsDevice.create('dev-a', db, clock: clock);
    await a.secrets.set(_pass, 'v');
    await a.settle();
    final enc = _enc(db, _pass);
    expect(
      await testCipher.open(enc, password: 'sync-pass', context: _pass),
      'v',
    );
    expect(await a.settings.passphrase.isSet, isFalse);
  });

  group('SyncPassphrase', () {
    test('an empty stored passphrase is unset and falls back', () async {
      final store = MemoryKeyValueStore();
      final p = SyncPassphrase(store, fallback: () async => 'pw');
      expect(await p.key(), 'pw');
      await store.set(kSyncPassphraseKey, '');
      expect(await p.isSet, isFalse);
      expect(await p.key(), 'pw');
      await p.set('pp');
      expect(await p.isSet, isTrue);
      expect(await p.key(), 'pp');
      expect(() => p.set(''), throwsArgumentError);
    });
  });
}
