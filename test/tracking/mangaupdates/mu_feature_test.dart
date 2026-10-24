import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/tracking/common/tracker.dart';
import 'package:kartka/tracking/mangaupdates/mu_feature.dart';
import 'package:kartka/tracking/mangaupdates/mu_session.dart';
import 'package:kartka/tracking/mangaupdates/mu_settings_tile.dart';
import 'package:kartka/tracking/mangaupdates/mu_tracker.dart';

import 'mu_fakes.dart';

void main() {
  late FakeKartkaHttp http;
  late MemoryKeyValueStore secrets;
  late MemoryKeyValueStore kv;
  late KartkaEnv env;

  setUp(() {
    http = FakeKartkaHttp((_) => fx('login_ok.json'));
    secrets = MemoryKeyValueStore();
    kv = MemoryKeyValueStore();
    env = KartkaEnv(memoryPlatform(http: http, kv: kv, secrets: secrets));
  });

  test('always registers one Tracker: nothing to configure', () {
    final feature = mangaUpdatesFeature(env);
    expect(feature.id, 'tracking-mangaupdates');
    expect(feature.services.single, isA<Tracker>());
    expect(feature.settingsTiles, hasLength(1));
  });

  test('login goes through KartkaHttp; token to secrets, not kv', () async {
    final tracker =
        mangaUpdatesFeature(env).services.single as MangaUpdatesTracker;
    await tracker.loginWith('kuhy', 'hunter2');
    expect(
      http.requests.single.url.toString(),
      'https://api.mangaupdates.com/v1/account/login',
    );
    final stored = await secrets.entries();
    expect(stored.keys, [MuSessionStore.defaultKey]);
    expect(stored.values.single, isNot(contains('hunter2')));
    expect(await kv.entries(), isEmpty);
    expect(await tracker.isLoggedIn(), isTrue);
  });

  testWidgets('settings tile is the MangaUpdates tile', (tester) async {
    final feature = mangaUpdatesFeature(env);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Builder(builder: feature.settingsTiles.single)),
      ),
    );
    expect(find.byType(MuSettingsTile), findsOneWidget);
  });
}
