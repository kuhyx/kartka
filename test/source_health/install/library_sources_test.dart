import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/source_health/install/auto_install_state.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';
import 'package:kartka/source_health/model/source_health_record.dart';

import '../ui/harness.dart';
import 'autoinstall_fakes.dart';

// The live library (2026-10-29): Cyanide & Happiness (20 entries) and Gone
// with the Blastwave (1) were never installed on the server; E-Hentai is an
// SY built-in and old Bato.to is gone, so nothing can install those two.
const _explosm = 'suwayomi:491094567635736188';
const _gwtb = 'suwayomi:4006397036545425884';
const Set<String> _library = {
  _explosm,
  _gwtb,
  'sy-builtin:6901',
  'suwayomi:789',
};

final List<SourceHealthRecord> _records = [
  keepRecord('suwayomi:1', pkg: 'pkg.keep'),
  keepRecord(_explosm, pkg: 'pkg.explosm', verdict: HealthVerdict.pending),
  keepRecord(_gwtb, pkg: 'pkg.gwtb', verdict: HealthVerdict.cut),
  keepRecord('suwayomi:2', pkg: 'pkg.unused', verdict: HealthVerdict.cut),
];

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('every installable source the library uses is installed, any '
      'verdict; sources nobody serves are left to migration', () async {
    final rig = ReconcileRig()..probeFailures[_gwtb] = 'unreachable';
    await rig.reconciler.reconcile(_records, 'W44', library: _library);
    expect(
      rig.suwayomi.calls,
      unorderedEquals([
        'list',
        'install:pkg.keep',
        'install:pkg.explosm',
        'install:pkg.gwtb',
      ]),
    );
    expect(rig.probed, unorderedEquals(['suwayomi:1', _explosm, _gwtb]));
    expect(rig.reconciler.status, 'Installed 3 sources, 1 failed its test');
    expect(rig.reconciler.state.librarySources, _library.toList()..sort());
  });

  test('reruns when the library starts using a new source, not when it '
      'drops one; also after a restart', () async {
    final rig = ReconcileRig();
    await rig.reconciler.reconcile(_records, 'W44', library: _library);
    expect(rig.reconciler.needsRun('W44', _library), isFalse);
    expect(rig.reconciler.needsRun('W44', {_explosm}), isFalse);
    await rig.reconciler.reconcile(_records, 'W44', library: {_explosm});
    expect(rig.suwayomi.calls.where((c) => c == 'list'), hasLength(1));

    final again = ReconcileRig(suwayomi: rig.suwayomi, kv: rig.kv);
    await again.reconciler.load();
    expect(again.reconciler.needsRun('W44', _library), isFalse);
    final grown = {..._library, 'suwayomi:2'};
    expect(again.reconciler.needsRun('W44', grown), isTrue);
    await again.reconciler.reconcile(_records, 'W44', library: grown);
    expect(again.suwayomi.calls.last, 'install:pkg.unused');
  });

  test('state stored before library sources reads as none', () {
    final old = AutoInstallState.fromJson(const {'publishId': 'W43'});
    expect(old.publishId, 'W43');
    expect(old.librarySources, isEmpty);
  });

  test('watches the library: waits for it, then installs what a new entry '
      'needs', () async {
    final rig = ReconcileRig(withLibrary: true);
    final feed = ControlledFeed();
    await rig.reconciler.start(feed);
    feed.controller.add(_records);
    feed.meta.add(const SourceHealthMeta(runId: 'W44'));
    await settle();
    expect(rig.suwayomi.calls, isEmpty, reason: 'waits for the library');
    rig.library.add({'suwayomi:1'});
    await settle();
    expect(rig.suwayomi.calls, ['list', 'install:pkg.keep']);
    rig.library.add({'suwayomi:1', _explosm});
    await settle();
    expect(rig.suwayomi.calls.last, 'install:pkg.explosm');
    rig.library.addError(StateError('unreadable'));
    await settle();
    rig.reconciler.dispose();
  });
}
