import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/sources/suwayomi/suwayomi_settings.dart';

import 'fakes.dart';

void main() {
  group('SuwayomiSettings', () {
    test('defaults to not configured and no auth', () {
      const s = SuwayomiSettings();
      expect(s.isConfigured, isFalse);
      expect(s.authHeaders, isEmpty);
      expect(s.owns('http://127.0.0.1:4599/x'), isFalse);
    });

    test('resolves server paths and passes absolute urls through', () {
      expect(fixtureSettings.base, 'http://127.0.0.1:4599');
      expect(
        fixtureSettings.graphqlUri,
        Uri.parse('http://127.0.0.1:4599/api/graphql'),
      );
      expect(fixtureSettings.resolve('/a'), 'http://127.0.0.1:4599/a');
      expect(fixtureSettings.resolve('a'), 'http://127.0.0.1:4599/a');
      expect(fixtureSettings.resolve('https://cdn.x/a'), 'https://cdn.x/a');
    });

    test('owns only URLs on the same origin and path prefix', () {
      const sub = SuwayomiSettings(serverUrl: 'https://h.org/manga/');
      expect(sub.owns('https://h.org/manga/api/v1/x'), isTrue);
      expect(sub.owns('https://h.org/other'), isFalse);
      expect(sub.owns('http://h.org/manga/x'), isFalse);
      expect(sub.owns('https://h.org:8443/manga/x'), isFalse);
      expect(sub.owns('https://evil.org/manga/x'), isFalse);
      expect(sub.owns('http://[::1'), isFalse);
    });

    test('value equality', () {
      const a = SuwayomiSettings(serverUrl: 'u', username: 'n', password: 'p');
      expect(a, const SuwayomiSettings(serverUrl: 'u', username: 'n', password: 'p'));
      expect(a.hashCode, isNot(const SuwayomiSettings().hashCode));
      expect(a == const SuwayomiSettings(serverUrl: 'u'), isFalse);
    });
  });

  group('SuwayomiSettingsStore', () {
    test('keeps credentials out of the plain store', () async {
      final kv = MemoryKv();
      final secrets = MemoryKv();
      final store = SuwayomiSettingsStore(kv: kv, secrets: secrets);
      final saved = expectLater(store.changes, emits(fixtureSettings));
      await store.save(fixtureSettings);
      await saved;
      expect(kv.values.values, ['http://127.0.0.1:4599/']);
      expect(secrets.values.values, containsAll(['kartka', 'fixture']));
      expect(store.current, fixtureSettings);

      final reloaded = SuwayomiSettingsStore(kv: kv, secrets: secrets);
      expect(reloaded.current, isNull);
      expect(await reloaded.load(), fixtureSettings);
    });

    test('loads empty settings when nothing is stored', () async {
      final store = SuwayomiSettingsStore(kv: MemoryKv(), secrets: MemoryKv());
      expect(await store.load(), const SuwayomiSettings());
    });
  });
}
