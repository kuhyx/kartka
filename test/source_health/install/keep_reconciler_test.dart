import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/source_health/install/auto_install_state.dart';

import 'autoinstall_fakes.dart';

void main() {
  test('installs only the missing keep sources, on both sides', () async {
    final rig = ReconcileRig(
      suwayomi: FakeSuwayomi({'pkg.have'}),
      plugins: FakePlugins(),
    );
    await rig.reconciler.reconcile([
      keepRecord('suwayomi:1', pkg: 'pkg.new'),
      keepRecord('suwayomi:2', pkg: 'pkg.have'),
      keepRecord('plugin:p', plugin: 'p'),
      keepRecord('suwayomi:3', pkg: 'pkg.cut', verdict: HealthVerdict.cut),
      keepRecord('suwayomi:4', pkg: 'pkg.wait', verdict: HealthVerdict.pending),
      keepRecord('mangadex'), // native: nothing to install
    ], '2026-W44');
    expect(rig.suwayomi.calls, ['list', 'install:pkg.new']);
    expect(rig.plugins!.calls, ['list', 'install:p']);
    expect(rig.probed, unorderedEquals(['suwayomi:1', 'plugin:p']));
    expect(rig.reconciler.state.publishId, '2026-W44');
    expect(rig.reconciler.status, 'Installed 2 sources');
  });

  test('one extension serving several keep sources installs once, and '
      'each of its sources is tested', () async {
    final rig = ReconcileRig();
    await rig.reconciler.reconcile([
      keepRecord('suwayomi:en', pkg: 'pkg.all'),
      keepRecord('suwayomi:ja', pkg: 'pkg.all'),
    ], 'W1');
    expect(rig.suwayomi.calls, ['list', 'install:pkg.all']);
    expect(rig.probed, ['suwayomi:en', 'suwayomi:ja']);
  });

  test('a record with pkg and plugin installs through Suwayomi only', () async {
    final rig = ReconcileRig(plugins: FakePlugins());
    await rig.reconciler.reconcile([
      keepRecord('suwayomi:1', pkg: 'pkg.a', plugin: 'a'),
    ], 'W1');
    expect(rig.suwayomi.calls, ['list', 'install:pkg.a']);
    expect(rig.plugins!.calls, ['list']);
  });

  test('never uninstalls: an installed cut source is left alone', () async {
    final rig = ReconcileRig(suwayomi: FakeSuwayomi({'pkg.cut'}));
    await rig.reconciler.reconcile([
      keepRecord('suwayomi:1', pkg: 'pkg.cut', verdict: HealthVerdict.cut),
    ], 'W1');
    expect(rig.suwayomi.calls, ['list']);
    expect(rig.suwayomi.installed, {'pkg.cut'});
    expect(rig.reconciler.status, isNull);
  });

  test('is idempotent per publish id, also across restarts', () async {
    final rig = ReconcileRig();
    final records = [keepRecord('suwayomi:1', pkg: 'pkg.a')];
    await rig.reconciler.reconcile(records, 'W1');
    await rig.reconciler.reconcile(records, 'W1');
    expect(rig.suwayomi.calls, ['list', 'install:pkg.a']);

    // A fresh reconciler on the same device storage remembers W1.
    final again = ReconcileRig(suwayomi: rig.suwayomi, kv: rig.kv);
    await again.reconciler.load();
    expect(again.reconciler.state.publishId, 'W1');
    expect(again.reconciler.needsRun('W1'), isFalse);
    expect(again.reconciler.needsRun('W2'), isTrue);
    expect(again.reconciler.status, 'Installed 1 source');
  });

  test('a failed test leaves the source installed, flags it and logs it '
      'without URLs', () async {
    final rig = ReconcileRig()
      ..probeFailures['suwayomi:1'] =
          'HTTP 500 from https://secret.test/x?token=1';
    await rig.reconciler.reconcile([
      keepRecord('suwayomi:1', pkg: 'pkg.a'),
      keepRecord('suwayomi:2', pkg: 'pkg.b'),
    ], 'W1');
    expect(rig.suwayomi.installed, {'pkg.a', 'pkg.b'});
    expect(
      rig.reconciler.flagOf('suwayomi:1'),
      'Installed — test failed: HTTP 500 from <url>',
    );
    expect(rig.reconciler.flagOf('suwayomi:2'), isNull);
    expect(rig.reconciler.status, 'Installed 2 sources, 1 failed its test');
    final logged = await rig.log.entries();
    expect(logged, hasLength(1));
    expect(logged.single.kind, 'sources.autoinstall');
    expect(logged.single.sourceId, 'suwayomi:1');
    expect(logged.single.error, contains('test failed: HTTP 500 from <url>'));
    expect(logged.single.error, isNot(contains('secret')));
  });

  test('a failed install is flagged, logged and not tested', () async {
    final rig = ReconcileRig();
    rig.suwayomi.failing['pkg.a'] = StateError('boom at https://x.test/');
    await rig.reconciler.reconcile([
      keepRecord('suwayomi:1', pkg: 'pkg.a'),
    ], 'W1');
    expect(rig.probed, isEmpty);
    expect(
      rig.reconciler.flagOf('suwayomi:1'),
      contains('Auto-install failed'),
    );
    expect(rig.reconciler.status, '1 source failed to install');
    final logged = await rig.log.entries();
    expect(logged.single.kind, 'sources.autoinstall');
    expect(logged.single.error, contains('install failed'));
    expect(logged.single.error, isNot(contains('x.test')));
  });

  test('flags survive a restart and a later publish re-tests them', () async {
    final rig = ReconcileRig()..probeFailures['suwayomi:1'] = 'empty';
    final records = [keepRecord('suwayomi:1', pkg: 'pkg.a')];
    await rig.reconciler.reconcile(records, 'W1');
    final again = ReconcileRig(suwayomi: rig.suwayomi, kv: rig.kv);
    await again.reconciler.load();
    expect(again.reconciler.flagOf('suwayomi:1'), contains('test failed'));
    // Next week it passes: installed already, so only re-tested.
    await again.reconciler.reconcile(records, 'W2');
    expect(again.probed, ['suwayomi:1']);
    expect(again.reconciler.flagOf('suwayomi:1'), isNull);
    expect(
      rig.suwayomi.calls.where((c) => c.startsWith('install')),
      hasLength(1),
    );
  });

  test('an unreadable side is skipped and the publish is retried later, '
      'while the other side still installs', () async {
    final rig = ReconcileRig(plugins: FakePlugins());
    rig.suwayomi.listError = StateError('server down');
    await rig.reconciler.reconcile([
      keepRecord('suwayomi:1', pkg: 'pkg.a'),
      keepRecord('plugin:p', plugin: 'p'),
    ], 'W1');
    expect(rig.suwayomi.calls, ['list']);
    expect(rig.plugins!.calls, ['list', 'install:p']);
    expect(rig.reconciler.state.publishId, isNull);
    expect(rig.reconciler.needsRun('W1'), isTrue);
  });

  test('an installer that cannot list counts as unreadable', () async {
    final rig = ReconcileRig(blind: BlindSuwayomi());
    await rig.reconciler.reconcile([
      keepRecord('suwayomi:1', pkg: 'pkg.a'),
    ], 'W1');
    expect(rig.blind!.calls, isEmpty);
    expect(rig.reconciler.state.publishId, isNull);
  });

  test('a side with no installer registered plans nothing and still '
      'completes the publish', () async {
    final rig = ReconcileRig(); // no plugin side
    await rig.reconciler.reconcile([keepRecord('plugin:p', plugin: 'p')], 'W1');
    expect(rig.probed, isEmpty);
    expect(rig.reconciler.state.publishId, 'W1');
  });

  test('installs run at most two at a time', () async {
    final rig = ReconcileRig();
    await rig.reconciler.reconcile([
      for (var i = 0; i < 6; i++) keepRecord('suwayomi:$i', pkg: 'pkg.$i'),
    ], 'W1');
    expect(rig.suwayomi.installed, hasLength(6));
    expect(rig.suwayomi.maxInFlight, 2);
  });

  test('the state round-trips through JSON and tolerates junk', () {
    const state = AutoInstallState(
      publishId: 'W1',
      installed: ['a', 'b'],
      failures: {
        'a': AutoInstallFailure(AutoInstallStage.test, 'empty'),
        'c': AutoInstallFailure(AutoInstallStage.install, 'boom'),
      },
    );
    expect(AutoInstallState.fromJson(state.toJson()), state);
    expect(AutoInstallState.fromJson('nonsense'), const AutoInstallState());
    expect(
      AutoInstallState.fromJson(const {
        'failures': {
          'x': 'bad',
          'y': {'stage': 'odd', 'reason': 'r'},
        },
      }).failures,
      {'y': const AutoInstallFailure(AutoInstallStage.install, 'r')},
    );
    expect(state.hashCode, AutoInstallState.fromJson(state.toJson()).hashCode);
    const failure = AutoInstallFailure(AutoInstallStage.test, 'x');
    expect(
      failure.hashCode,
      const AutoInstallFailure(AutoInstallStage.test, 'x').hashCode,
    );
  });

  test('a corrupt stored state reads as never ran', () async {
    final rig = ReconcileRig();
    await rig.kv.set(AutoInstallState.kvKey, '{not json');
    await rig.reconciler.load();
    expect(rig.reconciler.state, const AutoInstallState());
  });

  test('status wording', () {
    String? status(int installed, int tests, int installs) => AutoInstallState(
      installed: [for (var i = 0; i < installed; i++) 'i$i'],
      failures: {
        for (var i = 0; i < tests; i++)
          'i$i': const AutoInstallFailure(AutoInstallStage.test, 'x'),
        for (var i = 0; i < installs; i++)
          'f$i': const AutoInstallFailure(AutoInstallStage.install, 'x'),
      },
    ).status;
    expect(status(0, 0, 0), isNull);
    expect(status(5, 1, 0), 'Installed 5 sources, 1 failed its test');
    expect(
      status(3, 2, 1),
      'Installed 3 sources, 2 failed their tests, '
      '1 failed to install',
    );
    expect(status(0, 0, 2), '2 sources failed to install');
  });
}
