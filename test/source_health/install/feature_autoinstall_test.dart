import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/app/screen_observer.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/source_health/feed/source_health_feed.dart';
import 'package:kartka/source_health/install/auto_install_state.dart';
import 'package:kartka/source_health/install/keep_reconciler.dart';
import 'package:kartka/source_health/source_health_feature.dart';
import 'package:kartka/sync/rtdb_reader.dart';

import '../../browse/fakes.dart';
import 'autoinstall_fakes.dart';

void main() {
  test('the feature reconciles a published run on start, without asking, '
      'and remembers it on the device', () async {
    final suwayomi = FakeSuwayomi();
    final kv = MemoryKeyValueStore();
    final reader = InMemoryRtdbReader({
      'source_health': {
        'h1': keepRecord('suwayomi:1', pkg: 'pkg.a').toJson(),
        'h2': keepRecord(
          'suwayomi:2',
          pkg: 'pkg.cut',
          verdict: HealthVerdict.cut,
        ).toJson(),
      },
      'source_health_meta': {'runId': '2026-W44'},
    });
    final registry = KartkaRegistry.build(memoryPlatform(kv: kv), [
      sourceHealthFeature,
      (_) => KartkaFeature(
        id: 'others',
        services: [
          reader,
          suwayomi,
          StaticSourceProvider([FakeSource('suwayomi:1')]),
        ],
      ),
    ]);
    final reconciler = registry.maybe<KeepReconciler>()!;
    expect(registry.maybe<SourceHealthFeed>(), isNotNull);
    // Nothing runs until the app shows its first screen (a bare registry,
    // as in tests, never touches sync).
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(suwayomi.calls, isEmpty);
    for (final o in registry.all<ScreenObserver>()) {
      o
        ..screenChanged('/library')
        ..screenChanged('/browse'); // later screens do not start it again
    }
    for (var i = 0; i < 50 && reconciler.state.publishId == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(suwayomi.calls, ['list', 'install:pkg.a']);
    expect(reconciler.status, 'Installed 1 Keep source');
    expect((await AutoInstallState.load(kv)).publishId, '2026-W44');
  });
}
