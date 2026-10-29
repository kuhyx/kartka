import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/source_health/install/keep_reconciler.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';
import 'package:kartka/source_health/model/source_health_record.dart';

import '../ui/harness.dart';
import 'autoinstall_fakes.dart';

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('a new published run triggers a reconcile keyed by its runId; the '
      'same run again does nothing', () async {
    final rig = ReconcileRig();
    final feed = ControlledFeed();
    var notified = 0;
    rig.reconciler.addListener(() => notified++);
    await rig.reconciler.start(feed);
    final records = [keepRecord('suwayomi:1', pkg: 'pkg.a')];
    feed.controller.add(records);
    await settle();
    expect(rig.suwayomi.calls, isEmpty, reason: 'waits for the meta');
    feed.meta.add(const SourceHealthMeta(runId: '2026-W44'));
    await settle();
    expect(rig.suwayomi.calls, ['list', 'install:pkg.a']);
    expect(rig.reconciler.state.publishId, '2026-W44');
    expect(notified, greaterThan(0));
    feed.controller.add(records);
    await settle();
    expect(rig.suwayomi.calls, hasLength(2));
    // Next week's run reconciles again (nothing missing now: only lists).
    feed.meta.add(const SourceHealthMeta(runId: '2026-W45'));
    await settle();
    expect(rig.suwayomi.calls, ['list', 'install:pkg.a', 'list']);
    rig.reconciler.dispose();
  });

  test('a run without meta is keyed by its newest probe time', () async {
    final rig = ReconcileRig();
    final feed = ControlledFeed();
    await rig.reconciler.start(feed);
    feed.meta.add(null);
    feed.controller.add([
      SourceHealthRecord(
        id: 'suwayomi:1',
        name: 'One',
        pkg: 'pkg.a',
        verdict: keepRecord('x').verdict,
        probedAt: DateTime.utc(2026, 10, 25, 12),
      ),
    ]);
    await settle();
    expect(rig.reconciler.state.publishId, '2026-10-25T12:00:00.000Z');
    rig.reconciler.dispose();
  });

  test('nothing to key by (no meta, no probe times) means no run', () async {
    final rig = ReconcileRig();
    final feed = ControlledFeed();
    await rig.reconciler.start(feed);
    feed.meta.addError(StateError('meta unreadable'));
    feed.controller
      ..addError(StateError('read failed'))
      ..add([keepRecord('suwayomi:1', pkg: 'pkg.a')]);
    await settle();
    expect(rig.suwayomi.calls, isEmpty);
    rig.reconciler.dispose();
  });

  test('a publish arriving mid-run is reconciled right after', () async {
    final rig = ReconcileRig();
    final gate = Completer<String?>();
    final slow = KeepReconciler(
      kv: rig.kv,
      probe: (_) => gate.future,
      suwayomi: () => rig.suwayomi,
    );
    final feed = ControlledFeed();
    await slow.start(feed);
    feed.controller.add([keepRecord('suwayomi:1', pkg: 'pkg.a')]);
    feed.meta.add(const SourceHealthMeta(runId: 'W1'));
    await settle();
    feed.controller.add([
      keepRecord('suwayomi:1', pkg: 'pkg.a'),
      keepRecord('suwayomi:2', pkg: 'pkg.b'),
    ]);
    feed.meta.add(const SourceHealthMeta(runId: 'W2'));
    await settle();
    expect(rig.suwayomi.calls, ['list', 'install:pkg.a']);
    gate.complete(null);
    await settle();
    expect(rig.suwayomi.calls, [
      'list',
      'install:pkg.a',
      'list',
      'install:pkg.b',
    ]);
    expect(slow.state.publishId, 'W2');
    slow.dispose();
  });
}
