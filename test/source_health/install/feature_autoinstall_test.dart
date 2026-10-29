import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/app/screen_observer.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/source_health/feed/source_health_feed.dart';
import 'package:kartka/source_health/install/auto_install_state.dart';
import 'package:kartka/source_health/install/keep_reconciler.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/scoring/profile.dart';
import 'package:kartka/source_health/source_health_feature.dart';
import 'package:kartka/sync/rtdb_reader.dart';

import '../../browse/fakes.dart';
import 'autoinstall_fakes.dart';

Map<String, Object?> _published(SourceHealthRecord r) => {
  ...r.toJson(),
  'probedAt': '2026-10-25T12:00:00Z',
  'defaultScore': 0.95,
  'score': 0.95,
};

void main() {
  test('the feature reconciles a published run on start, without asking, '
      'and remembers it on the device', () async {
    final suwayomi = FakeSuwayomi();
    final kv = MemoryKeyValueStore();
    final reader = InMemoryRtdbReader({
      'source_health': {
        // As published today: probe times and defaultScore on every record.
        'h1': _published(keepRecord('suwayomi:1', pkg: 'pkg.a')),
        'h2': _published(
          keepRecord('suwayomi:2', pkg: 'pkg.cut', verdict: HealthVerdict.cut),
        ),
      },
      'source_health_meta': const SourceHealthMeta(
        runId: '2026-W44',
        profile: defaultScoringProfile,
      ).toJson(),
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
    // Let a late meta poll land too: still one run, keyed by the run id.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(suwayomi.calls, ['list', 'install:pkg.a']);
    expect(reconciler.status, 'Installed 1 source');
    expect(reconciler.state.publishId, '2026-W44');
    expect((await AutoInstallState.load(kv)).publishId, '2026-W44');
  });
}
