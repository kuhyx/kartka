import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/source_health/install/install_ports.dart';
import 'package:kartka/source_health/install/rejected_pruner.dart';

import 'autoinstall_fakes.dart';

class _Store implements ExtensionSourceLister, ExtensionRemover {
  new(this.sources, {this.fails = false});

  final Map<String, Set<String>> sources;
  final bool fails;
  final removed = <String>[];

  @override
  Future<Map<String, Set<String>>> packageSources() async {
    if (fails) throw StateError('runtime down');
    return sources;
  }

  @override
  Future<void> removeExtension(String pkg) async => removed.add(pkg);
}

class _Pruning extends FakeSuwayomi
    implements ExtensionSourceLister, ExtensionRemover {
  new() : super({'pkg.bad'});

  @override
  Future<Map<String, Set<String>>> packageSources() async => {
    'pkg.bad': {'suwayomi:9'},
  };

  @override
  Future<void> removeExtension(String pkg) async => calls.add('remove:$pkg');
}

void main() {
  test(
    'removes an extension whose every source is rejected and unused',
    () async {
      final store = _Store({
        'pkg.bad': {'s:1', 's:2'},
        'pkg.half': {'s:3', 's:4'},
        'pkg.read': {'s:5'},
        'pkg.none': {},
      });
      final removed = await pruneRejected(
        store,
        rejected: {'s:1', 's:2', 's:3', 's:5'},
        library: {'s:5'},
      );
      expect(removed, ['pkg.bad']);
      expect(store.removed, ['pkg.bad']);
    },
  );

  test(
    'nothing rejected, no lister or a failed read removes nothing',
    () async {
      final store = _Store({
        'pkg.bad': {'s:1'},
      });
      expect(await pruneRejected(store, rejected: {}, library: {}), isEmpty);
      expect(
        await pruneRejected(Object(), rejected: {'s:1'}, library: {}),
        isEmpty,
      );
      final down = _Store({}, fails: true);
      expect(
        await pruneRejected(down, rejected: {'s:1'}, library: {}),
        isEmpty,
      );
      expect(store.removed, isEmpty);
    },
  );

  test('the Keep auto-install prunes rejected extensions', () async {
    final rig = ReconcileRig(suwayomi: _Pruning());
    await rig.reconciler.reconcile(
      [keepRecord('suwayomi:1', pkg: 'pkg.a')],
      'W1',
      rejected: {'suwayomi:9'},
    );
    expect(rig.suwayomi.calls, ['list', 'install:pkg.a', 'remove:pkg.bad']);
  });
}
