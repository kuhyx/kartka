import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/state/category_actions.dart';

import '../support/fakes.dart';

void main() {
  late Fakes f;
  late CategoryActions actions;
  var ids = 0;

  setUp(() {
    f = Fakes();
    ids = 0;
    actions = CategoryActions(f.deps, newId: () => 'id${ids++}');
  });

  Future<List<Category>> live() => f.deps.repos.categories.watch().first;

  test(
    'create appends at the end with trimmed names; blanks ignored',
    () async {
      await actions.create('  Reading ', const []);
      await actions.create('Done', await live());
      await actions.create('   ', await live());
      final cats = await live();
      expect(
        [for (final c in cats) (c.id, c.name, c.order)],
        [('id0', 'Reading', 0), ('id1', 'Done', 1)],
      );
    },
  );

  test('rename wins over the stored row even at the same clock', () async {
    await actions.create('A', const []);
    final a = (await live()).single;
    await actions.rename(a, 'B');
    expect((await live()).single.name, 'B');
    await actions.rename((await live()).single, ' ');
    expect((await live()).single.name, 'B');
  });

  test('delete tombstones the category', () async {
    await actions.create('A', const []);
    await actions.delete((await live()).single);
    expect(await live(), isEmpty);
  });

  test(
    'move reorders and rewrites only the rows whose order changed',
    () async {
      for (final n in ['A', 'B', 'C']) {
        await actions.create(n, await live());
      }
      await actions.move(await live(), 2, 0);
      expect([for (final c in await live()) c.name], ['C', 'A', 'B']);
      await actions.move(await live(), 0, 2);
      expect([for (final c in await live()) c.name], ['A', 'B', 'C']);
      await actions.move(await live(), 1, 1);
      expect([for (final c in await live()) c.order], [0, 1, 2]);
    },
  );

  test('default ids are random hex', () {
    final a = CategoryActions(f.deps);
    expect(a.newId(), matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(a.newId(), isNot(a.newId()));
  });
}
