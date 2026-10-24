import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/app/settings_stores.dart';
import 'package:kartka/downloads/downloads_feature.dart';
import 'package:kartka/downloads/keys.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/plugins/runtime/plugin_manager.dart';
import 'package:kartka/plugins/runtime/plugins_feature.dart';
import 'package:kartka/reader/data/reader_settings.dart';
import 'package:kartka/reader/logic/reader_mode.dart';
import 'package:kartka/reader/reader_feature.dart';
import 'package:kartka/sources/mangadex/mangadex_feature.dart';
import 'package:kartka/sources/mangadex/mangadex_settings_store.dart';
import 'package:kartka/sources/suwayomi/suwayomi_feature.dart';
import 'package:kartka/sources/suwayomi/suwayomi_settings.dart';
import 'package:kartka/sources/suwayomi/suwayomi_source_provider.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/settings/settings_catalog.dart';
import 'package:kartka/sync/settings/sync_passphrase.dart';
import 'package:kartka/sync/settings/synced_settings.dart';
import 'package:kartka/sync/sync_engine.dart';

import '../fakes.dart';
import 'settings_harness.dart';

/// One app install: the real feature factories over a memory platform,
/// plus sync's settings service over a shared RTDB.
class _App {
  new _(this.env, this.engine, this.settings);

  static Future<_App> create(String id, InMemoryRtdb db, TestClock c) async {
    final engine = await engineFor(id, db, clock: c);
    final env = KartkaEnv(memoryPlatform());
    final settings = SyncedSettings(
      started: Future.value(engine),
      start: () async => engine,
      kv: env.platform.kv,
      secrets: env.platform.secrets,
      passphrase: SyncPassphrase(
        env.platform.secrets,
        fallback: () async => 'sync-pass',
      ),
      cipher: testCipher,
    );
    env.registry = KartkaRegistry([
      for (final f in <KartkaFeatureFactory>[
        suwayomiFeature,
        mangadexFeature,
        pluginsFeature,
        downloadsFeature,
        readerFeature,
        (_) => KartkaFeature(id: 'sync', services: [settings]),
      ])
        f(env),
    ]);
    await pumpEventQueue();
    return _App._(env, engine, settings);
  }

  final KartkaEnv env;
  final SyncEngine engine;
  final SyncedSettings settings;

  SuwayomiSettingsStore get suwayomi =>
      env.registry.maybe<SuwayomiSourceProvider>()!.store;

  Future<void> settle() async {
    for (var i = 0; i < 3; i++) {
      await pumpEventQueue();
      await settings.settled;
    }
  }

  Future<void> poll() async {
    await settle();
    await engine.poll();
    await settle();
  }
}

void main() {
  test('settings saved through the features reach the other device', () async {
    final db = InMemoryRtdb();
    final clock = TestClock();
    final desktop = await _App.create('desktop', db, clock);
    final phone = await _App.create('phone', db, clock);
    const server = SuwayomiSettings(
      serverUrl: 'https://suwayomi.example',
      username: 'kuhy',
      password: 'Secret-Pass-1',
    );
    final announced = expectLater(phone.suwayomi.changes, emitsThrough(server));
    await desktop.suwayomi.save(server);
    final dex = desktop.env.registry.maybe<MangadexSettingsStore>()!;
    await dex.save(dex.value.copyWith(languages: ['pl'], dataSaver: true));
    await readerDeps(desktop.env).prefs.saveSettings(
      const ReaderSettings(defaultMode: ReaderMode.webtoon, prefetchAhead: 5),
    );
    await desktop.env.registry.maybe<PluginManager>()!.store.setRepos([
      'https://repo.example/index.json',
    ]);
    // The phone had auto-download baselines from an earlier "on" period.
    await phone.env.platform.kv.set('${knownChaptersKvPrefix}x', '["/c/1"]');
    await syncedKv(desktop.env).set(autoDownloadKvKey, 'true');
    await desktop.settle();
    await phone.poll();

    await announced;
    expect(phone.suwayomi.current, server);
    final phoneDex = phone.env.registry.maybe<MangadexSettingsStore>()!.value;
    expect(phoneDex.languages, ['pl']);
    expect(phoneDex.dataSaver, isTrue);
    final reader = await readerDeps(phone.env).prefs.settings();
    expect(reader.defaultMode, ReaderMode.webtoon);
    expect(reader.prefetchAhead, 5);
    expect(await phone.env.registry.maybe<PluginManager>()!.repos(), [
      'https://repo.example/index.json',
    ]);
    final kv = phone.env.platform.kv;
    expect(await kv.get(autoDownloadKvKey), 'true');
    expect(await kv.entries(prefix: knownChaptersKvPrefix), isEmpty);
    expect(kAutoDownloadSetting, autoDownloadKvKey);
  });
}
