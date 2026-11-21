import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/source_health/install/uninstall_marks.dart';

import 'autoinstall_fakes.dart';

void main() {
  test('marks survive a reload and clear on install', () async {
    final kv = MemoryKeyValueStore();
    final marks = UninstallMarks(kv);
    expect(await marks.load(), isEmpty);
    await marks.mark('pkg.a');
    await marks.mark('pkg.b');
    await marks.mark('pkg.a');
    expect(await UninstallMarks(kv).load(), {'pkg.a', 'pkg.b'});
    await marks.clear('pkg.a');
    await marks.clear('pkg.gone');
    expect(await UninstallMarks(kv).load(), {'pkg.b'});
  });

  test('unreadable storage reads as no marks', () async {
    final kv = MemoryKeyValueStore();
    await kv.set(UninstallMarks.kvKey, '{not json');
    expect(await UninstallMarks(kv).load(), isEmpty);
    await kv.set(UninstallMarks.kvKey, '{"a": 1}');
    expect(await UninstallMarks(kv).load(), isEmpty);
  });

  test('the Keep auto-install skips a package the user uninstalled, even '
      'when the library uses it', () async {
    final rig = ReconcileRig();
    await UninstallMarks(rig.kv).mark('pkg.gone');
    await rig.reconciler.reconcile(
      [
        keepRecord('suwayomi:1', pkg: 'pkg.gone'),
        keepRecord('suwayomi:2', pkg: 'pkg.new'),
      ],
      'W1',
      library: {'suwayomi:1'},
    );
    expect(rig.suwayomi.calls, ['list', 'install:pkg.new']);
    expect(rig.reconciler.state.publishId, 'W1');
  });
}
