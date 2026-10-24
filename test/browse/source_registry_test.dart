import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/browse/source_registry.dart';
import 'package:kartka/core/source/source_provider.dart';

import 'fakes.dart';

Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  test('combines static sources and live providers, first id wins', () async {
    final md = FakeSource('mangadex');
    final p1 = FakeSourceProvider();
    final p2 = FakeSourceProvider();
    final reg = SourceRegistry([
      StaticSourceProvider([md]),
      p1,
      p2,
    ]);
    final seen = <List<String>>[];
    await tick();
    final sub = reg.watch().listen(
      (l) => seen.add([for (final s in l) s.ref.id]),
    );
    await tick();
    p2.controller.add([FakeSource('plugin:a')]);
    await tick();
    p1.controller.add([FakeSource('suwayomi:1'), FakeSource('mangadex')]);
    await tick();
    expect(seen, [
      ['mangadex'],
      ['mangadex', 'plugin:a'],
      ['mangadex', 'suwayomi:1', 'plugin:a'],
    ]);
    expect(reg.byId('mangadex'), same(md));
    expect(reg.byId('suwayomi:1'), isNotNull);
    expect(reg.byId('nope'), isNull);

    p1.controller.add([]);
    await tick();
    expect(reg.current.map((s) => s.ref.id), ['mangadex', 'plugin:a']);
    expect(reg.byId('suwayomi:1'), isNull);
    await sub.cancel();
    await reg.dispose();
  });

  test('a provider error keeps its last list', () async {
    final p = FakeSourceProvider();
    final reg = SourceRegistry([p]);
    p.controller.add([FakeSource('plugin:x')]);
    await tick();
    p.controller.addError(StateError('down'));
    await tick();
    expect(reg.current.single.ref.id, 'plugin:x');
    await reg.dispose();
  });

  test('fromRegistry reads SourceProvider services', () async {
    final reg = SourceRegistry.fromRegistry(
      KartkaRegistry([
        KartkaFeature(
          id: 'a',
          services: [
            StaticSourceProvider([FakeSource('mangadex')]),
            'unrelated',
          ],
        ),
      ]),
    );
    await tick();
    expect(reg.current.single.ref.id, 'mangadex');
  });
}
