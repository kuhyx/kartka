import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/settings/settings_sync.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/settings/settings_catalog.dart';

import '../fakes.dart';
import 'settings_harness.dart';

const _url = 'suwayomi.serverUrl';
const _user = 'suwayomi.username';
const _pass = 'suwayomi.password';

void main() {
  late InMemoryRtdb db;
  late TestClock clock;
  setUp(() {
    db = InMemoryRtdb();
    clock = TestClock();
  });

  test('a plain setting saved on one device reaches the other', () async {
    final a = await SettingsDevice.create('dev-a', db, clock: clock);
    final b = await SettingsDevice.create('dev-b', db, clock: clock);
    final changed = <String>[];
    b.settings.remoteChanges.listen(changed.add);
    await a.kv.set(_url, 'https://manga.example');
    await a.settle();
    await b.poll();
    expect(await b.local.get(_url), 'https://manga.example');
    expect(changed, [_url]);
    // And back the other way, newest write winning.
    clock.advance();
    await b.kv.set(_url, 'https://other.example');
    await b.settle();
    await a.poll();
    expect(await a.local.get(_url), 'https://other.example');
  });

  test('the password syncs, and only ciphertext ever leaves it', () async {
    final a = await SettingsDevice.create('dev-a', db, clock: clock);
    final b = await SettingsDevice.create('dev-b', db, clock: clock);
    const secret = 'hunter2-Very-Secret';
    await a.secrets.set(_user, 'kuhy-user');
    await a.secrets.set(_pass, secret);
    await a.settle();
    await b.poll();
    expect(await b.secretsLocal.get(_pass), secret);
    expect(await b.secretsLocal.get(_user), 'kuhy-user');
    final basic = base64.encode(utf8.encode('kuhy-user:$secret'));
    final leaks = [secret, 'kuhy-user', basic];
    final uploaded = jsonEncode(db.tree);
    final shadows = [
      for (final d in [a, b]) ...(await d.shadowKv.entries()).values,
    ].join('\n');
    for (final s in leaks) {
      expect(uploaded, isNot(contains(s)));
      expect(shadows, isNot(contains(s)));
    }
    final node = (db.tree['settings']! as Map)[rtdbKey(_pass)]! as Map;
    expect((node['enc']! as Map).keys, containsAll(['ct', 'salt', 'nonce']));
  });

  test('a wrong sync password keeps the local value and says so', () async {
    final a = await SettingsDevice.create('dev-a', db, clock: clock);
    final b = await SettingsDevice.create(
      'dev-b',
      db,
      clock: clock,
      password: 'different',
    );
    await b.secretsLocal.set(_pass, 'mine');
    final problems = <Map<String, String>>[];
    b.settings.watchProblems().listen(problems.add);
    await a.secrets.set(_pass, 'theirs');
    await a.settle();
    await b.poll();
    expect(await b.secretsLocal.get(_pass), 'mine');
    expect(problems.last, {_pass: "Couldn't decrypt synced Suwayomi password"});
    expect(b.engine.shadow.unapplied, contains(settingPath(_pass)));
    // Saving locally makes this device's value the synced one again.
    clock.advance();
    await b.secrets.set(_pass, 'mine-again');
    await b.settle();
    expect(problems.last, isEmpty);
  });

  test('without a sync password secrets are neither sent nor read', () async {
    final a = await SettingsDevice.create(
      'dev-a',
      db,
      clock: clock,
      password: null,
    );
    await a.secrets.set(_pass, 'local-only');
    await a.settle();
    expect(db.tree['settings'], isNull);
    expect(await a.settings.watchProblems().first, {
      _pass:
          'Suwayomi password not synced: set a sync passphrase in More → Sync',
    });
    final b = await SettingsDevice.create('dev-b', db, clock: clock);
    await b.secrets.set(_pass, 'from-b');
    await b.settle();
    await a.poll();
    expect(await a.secretsLocal.get(_pass), 'local-only');
    expect(
      (await a.settings.watchProblems().first)[_pass],
      "Couldn't decrypt synced Suwayomi password: set the sync passphrase "
      'in More → Sync',
    );
  });

  test('re-saving an unchanged value pushes nothing new', () async {
    final a = await SettingsDevice.create('dev-a', db, clock: clock);
    await a.kv.set(_url, 'https://x');
    await a.secrets.set(_pass, 'p');
    await a.settle();
    final before = jsonEncode(db.tree);
    clock.advance();
    await a.kv.set(_url, 'https://x');
    await a.secrets.set(_pass, 'p');
    await a.settle();
    expect(jsonEncode(db.tree), before);
  });

  test('device-local keys never sync, in either direction', () async {
    final a = await SettingsDevice.create('dev-a', db, clock: clock);
    final b = await SettingsDevice.create('dev-b', db, clock: clock);
    await a.kv.set('downloads/queue', '[]');
    await a.secrets.set('anilist.token', 'tok');
    // A synced key written through the wrong store is not synced either.
    await a.kv.set(_pass, 'plain-text');
    await a.settle();
    expect(db.tree['settings'], isNull);
    // A peer cannot plant arbitrary keys: only catalogued ones apply.
    db.tree['settings'] = {
      'sync~2Edirty': {'key': 'sync.dirty', 'value': 'x', 'hlc': '0'},
      'odd': {'key': _url, 'value': 'moved', 'hlc': '0'},
      rtdbKey(_url): {'key': _url, 'value': 7, 'hlc': '0'},
    };
    db.tree['revs'] = {'dev-z': '1'};
    await b.engine.syncNow();
    await b.settle();
    expect(await b.local.get('sync.dirty'), isNull);
    expect(await b.local.get(_url), isNull);
  });

  test('a removed setting is removed on the peer', () async {
    final a = await SettingsDevice.create('dev-a', db, clock: clock);
    final b = await SettingsDevice.create('dev-b', db, clock: clock);
    await a.kv.set(kAutoDownloadSetting, 'true');
    await a.secrets.set(_user, 'u');
    await a.settle();
    await b.poll();
    expect(await b.local.get(kAutoDownloadSetting), 'true');
    clock.advance();
    await a.kv.remove(kAutoDownloadSetting);
    await a.secrets.remove(_user);
    await a.settle();
    await b.poll();
    expect(await b.local.get(kAutoDownloadSetting), isNull);
    expect(await b.secretsLocal.get(_user), isNull);
  });

  test('changes merged before start are replayed once it attaches', () async {
    final a = await SettingsDevice.create('dev-a', db, clock: clock);
    await a.kv.set(_url, 'https://early');
    await a.settle();
    // An engine with no settings service yet (or one that crashed before
    // replaying) merges the node and leaves it marked unapplied.
    final shadow = MemoryKeyValueStore();
    await (await engineFor('dev-b', db, clock: clock, kv: shadow)).poll();
    final b = await SettingsDevice.create(
      'dev-b',
      db,
      clock: clock,
      shadowKv: shadow,
    );
    expect(await b.local.get(_url), 'https://early');
    expect(b.engine.shadow.unapplied, isEmpty);
  });

  test('the catalogue is exactly the settings kuhy chose to sync', () {
    expect(kSyncedSettings.keys.toSet(), {
      _url,
      _user,
      _pass,
      'mangadex.settings',
      'reader.settings',
      'plugins.repos',
      kAutoDownloadSetting,
    });
    for (final key in [_user, _pass]) {
      expect(kSyncedSettings[key]!.vault, SettingsVault.secret);
    }
  });
}
