import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/settings/settings_sync.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/source_health/scoring/profile.dart';
import 'package:kartka/source_health/scoring/profile_store.dart';
import 'package:kartka/source_health/ui/scoring_page.dart';

import '../../helpers/spoken_icon.dart';
import 'harness.dart';

void main() {
  late MemoryKeyValueStore local;
  late ScoringProfileStore store;

  Future<void> pump(WidgetTester tester) async {
    tallSurface(tester);
    local = MemoryKeyValueStore();
    store = ScoringProfileStore(
      SyncedKeyValueStore(local, SettingsVault.plain, () => null),
    );
    await tester.runAsync(() => store.ready);
    await tester.pumpWidget(host(ScoringPage(store: store)));
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pump();
    await tester.pump();
  }

  Future<Map<String, Object?>?> stored(WidgetTester tester) async {
    final raw = await tester.runAsync(() => local.get(kScoringSetting));
    return raw == null ? null : jsonDecode(raw) as Map<String, Object?>;
  }

  testWidgets('shows the defaults with every control and Reset disabled', (
    tester,
  ) async {
    await pump(tester);
    expect(spokenIcon('Using the evaluator defaults'), findsOne);
    for (final label in [
      'Coverage (with complete chapters)',
      'Uptime',
      'Image quality',
      'Speed (latency)',
    ]) {
      expect(spokenIcon('$label: share of the score'), findsOne, reason: label);
    }
    expect(find.text('50 %'), findsOne);
    expect(find.text('≥ 0.90'), findsOne);
    expect(spokenContaining('Keep at score ≥ 0.90'), findsOne);
    expect(find.byKey(const Key('only-3')), findsOne);
    expect(find.byKey(const Key('only-4')), findsNothing);
    for (final wire in [
      'blocking',
      'coverage',
      'uptime',
      'needsBrowserEngine',
      'pagesNeverLoad',
    ]) {
      expect(find.byKey(Key('cut-$wire')), findsOne, reason: wire);
      expect(find.byKey(const Key('cut-subset')), findsNothing);
    }
    final reset = tester.widget<IconButton>(
      find.byKey(const Key('reset-scoring')),
    );
    expect(reset.onPressed, isNull);
  });

  testWidgets('dragging a weight re-scores live and stores on release', (
    tester,
  ) async {
    await pump(tester);
    await tester.drag(
      find.byKey(const Key('weight-0')),
      const Offset(-2000, 0),
    );
    await tester.pump();
    expect(store.profile.value.weights.completeCoverage, 0);
    expect(store.profile.value.isDefault, isFalse);
    expect(spokenIcon('Using a custom profile, synced'), findsOne);
    final json = await stored(tester);
    expect((json!['weights']! as Map)['completeCoverage'], 0);
    expect(find.text('0 %'), findsOne);
  });

  testWidgets('"Only this" zeroes the others; a zero weight becomes 1', (
    tester,
  ) async {
    await pump(tester);
    await tapKey(tester, 'only-2');
    expect(store.profile.value.weights.values, [0, 0, 0.15, 0]);
    expect(find.text('100 %'), findsOne);
    expect(
      (await stored(tester))!['weights'],
      containsPair('imageQuality', 0.15),
    );
    await tapKey(tester, 'only-0');
    expect(store.profile.value.weights.values, [1, 0, 0, 0]);
  });

  testWidgets('the last non-zero weight cannot be dragged to 0', (
    tester,
  ) async {
    await pump(tester);
    await tapKey(tester, 'only-1');
    await tester.drag(
      find.byKey(const Key('weight-1')),
      const Offset(-2000, 0),
    );
    await tester.pump();
    expect(store.profile.value.weights.uptime, greaterThan(0));
    expect(store.profile.value.weights.total, greaterThan(0));
  });

  testWidgets('switches, the keep bar and Reset edit and restore the profile', (
    tester,
  ) async {
    await pump(tester);
    await tapKey(tester, 'pages-multiplier');
    expect(store.profile.value.pagesLoadMultiplier, isFalse);
    await tapKey(tester, 'cut-blocking');
    await tapKey(tester, 'cut-pagesNeverLoad');
    expect(store.profile.value.cuts, hasLength(2));
    await tapKey(tester, 'cut-blocking');
    expect(store.profile.value.cuts, hasLength(1));
    await tester.drag(
      find.byKey(const Key('keep-score')),
      const Offset(-2000, 0),
    );
    await tester.pump();
    expect(store.profile.value.keepScore, 0);
    expect((await stored(tester))!['keepScore'], 0);
    await tapKey(tester, 'reset-scoring');
    expect(store.profile.value, defaultScoringProfile);
    expect(await stored(tester), isNull);
    expect(find.text('≥ 0.90'), findsOne);
  });
}
