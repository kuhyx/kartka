import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/state/library_controller.dart';
import 'package:kartka/library/state/library_query.dart';

import '../support/fakes.dart';

void main() {
  late Fakes f;
  late LibraryController c;
  var notified = 0;

  setUp(() async {
    f = Fakes();
    await f.deps.repos.library.upsert(entry('/a', title: 'Akira'));
    await f.deps.repos.library.upsert(entry('/b', title: 'Berserk'));
    c = LibraryController(f.deps)
      ..addListener(() => notified++)
      ..start();
    await pumpEventQueue();
    notified = 0;
  });
  tearDown(() => c.dispose());

  const a = 'mangadex|/a';
  const b = 'mangadex|/b';

  test('joins entries with progress and port facts', () async {
    expect(c.loaded, isTrue);
    expect([for (final i in c.visible) i.title], ['Akira', 'Berserk']);
    await f.deps.repos.progress.record(
      ReadingProgress(
        key: b,
        chapterUrl: '/c1',
        chapterNumber: 1,
        page: 0,
        readAt: t0,
      ),
    );
    f.unread.emit(a, 3);
    f.dl.emit(b, true);
    f.tracked.emit(a, true);
    await pumpEventQueue();
    final byKey = {for (final i in c.items) i.key: i};
    expect(byKey[a]!.unread, 3);
    expect(byKey[a]!.tracked, isTrue);
    expect(byKey[b]!.downloaded, isTrue);
    expect(byKey[b]!.lastReadAt, t0);
    expect(notified, greaterThan(0));
  });

  test('query changes re-filter and notify', () {
    c.query = c.query.copyWith(search: 'ber');
    expect([for (final i in c.visible) i.key], [b]);
    expect(notified, 1);
  });

  test(
    'removed entries drop out and their subscriptions are cancelled',
    () async {
      await f.deps.repos.library.remove(a);
      await pumpEventQueue();
      expect([for (final i in c.items) i.key], [b]);
      expect(f.unread.cancelled, 1);
    },
  );

  test('selection: enter, toggle, select all, exit', () {
    expect(c.selecting, isFalse);
    c.startSelecting();
    expect(c.selecting, isTrue);
    expect(c.selected, isEmpty);
    c.toggle(a);
    expect(c.selected, {a});
    c.toggle(a);
    expect(c.selected, isEmpty);
    expect(c.selecting, isTrue);
    c.selectAllVisible();
    expect(c.selected, {a, b});
    c.clearSelection();
    expect(c.selecting, isFalse);
    expect(c.selected, isEmpty);
  });

  test('remove selected, then undo restores them', () async {
    c
      ..startSelecting()
      ..toggle(a);
    final batch = await c.removeSelected();
    await pumpEventQueue();
    expect(c.selecting, isFalse);
    expect([for (final i in c.items) i.key], [b]);
    await c.restore(batch);
    await pumpEventQueue();
    expect([for (final i in c.items) i.key], [a, b]);
  });

  test(
    'categories: tabs follow the repository; a deleted tab resets',
    () async {
      final cats = f.deps.repos.categories;
      await cats.upsert(Category(id: 'x', name: 'X', order: 0, updatedAt: t0));
      await pumpEventQueue();
      expect([for (final cat in c.categories) cat.id], ['x']);
      c.query = const LibraryQuery(categoryId: 'x');
      expect(c.visible, isEmpty);
      await cats.upsert(
        Category(
          id: 'x',
          name: 'X',
          order: 0,
          updatedAt: t0.add(const Duration(seconds: 1)),
          removed: true,
        ),
      );
      await pumpEventQueue();
      expect(c.query.categoryId, isNull);
    },
  );

  test('set categories for the selection; tri-state membership', () async {
    final cats = f.deps.repos.categories;
    await cats.upsert(Category(id: 'x', name: 'X', order: 0, updatedAt: t0));
    await cats.upsert(Category(id: 'y', name: 'Y', order: 1, updatedAt: t0));
    await cats.setMembership(a, 'x', true);
    await pumpEventQueue();
    c
      ..startSelecting()
      ..selectAllVisible();
    expect(c.selectionMembership(), {'x': null, 'y': false});
    await c.setCategories({'x': true, 'y': false});
    await pumpEventQueue();
    expect(c.selectionMembership(), {'x': true, 'y': false});
    expect(c.items.every((i) => i.categoryIds.contains('x')), isTrue);
    await c.setCategories({'x': false});
    await pumpEventQueue();
    expect(c.selectionMembership(), {'x': false, 'y': false});
  });

  test('source availability: unknown until every provider emitted', () async {
    bool available(String key) =>
        c.items.firstWhere((i) => i.key == key).sourceAvailable;
    expect(available(a), isTrue);
    f.sources.emit(['other']);
    await pumpEventQueue();
    expect(available(a), isFalse);
    f.sources.emit(['mangadex']);
    await pumpEventQueue();
    expect(available(a), isTrue);
  });

  test('no providers means no source is available', () async {
    final none = Fakes(providers: const []);
    await none.deps.repos.library.upsert(entry('/a'));
    final c2 = LibraryController(none.deps)..start();
    await pumpEventQueue();
    expect(c2.items.single.sourceAvailable, isFalse);
    c2.dispose();
  });
}
