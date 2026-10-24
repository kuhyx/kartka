import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/registry.dart';

import '../helpers/fake_platform.dart';

abstract interface class _Port {
  String get name;
}

class _Impl implements _Port {
  new(this.name);
  @override
  final String name;
}

Widget _a(BuildContext _) => const Text('a');
Widget _b(BuildContext _) => const Text('b');

void main() {
  test('services are found by type, in registry order', () {
    final registry = KartkaRegistry([
      KartkaFeature(id: 'one', services: [_Impl('first'), 42]),
      const KartkaFeature(id: 'empty'),
      KartkaFeature(id: 'two', services: [_Impl('second')]),
    ]);
    expect(registry.all<_Port>().map((p) => p.name), ['first', 'second']);
    expect(registry.maybe<_Port>()!.name, 'first');
    expect(registry.maybe<int>(), 42);
    expect(registry.maybe<String>(), isNull);
    expect(registry.all<String>(), isEmpty);
  });

  test('routes, tiles and tabs merge; the first tab filler wins', () {
    final route = GoRoute(path: '/x', builder: (_, _) => const SizedBox());
    final registry = KartkaRegistry([
      KartkaFeature(
        id: 'one',
        routes: [route],
        tabs: const {KartkaTab.library: _a},
        settingsTiles: const [_a],
      ),
      const KartkaFeature(
        id: 'two',
        tabs: {KartkaTab.library: _b, KartkaTab.more: _b},
        settingsTiles: [_b],
      ),
    ]);
    expect(registry.routes, [route]);
    expect(registry.settingsTiles, [_a, _b]);
    expect(registry.tab(KartkaTab.library), _a);
    expect(registry.tab(KartkaTab.more), _b);
    expect(registry.tab(KartkaTab.browse), isNull);
    expect(registry.features.map((f) => f.id), ['one', 'two']);
  });

  test('build runs factories with the platform and wires the registry', () {
    final platform = fakePlatform();
    late KartkaEnv seen;
    final registry = KartkaRegistry.build(platform, [
      (env) {
        seen = env;
        return const KartkaFeature(id: 'probe');
      },
    ]);
    expect(seen.platform, same(platform));
    expect(seen.registry, same(registry));
  });

  test('the shipped registry builds', () {
    final registry = KartkaRegistry.build(
      fakePlatform(),
      kartkaFeatureFactories,
    );
    expect(registry.features.length, kartkaFeatureFactories.length);
  });
}
