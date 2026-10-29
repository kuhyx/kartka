import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/state/library_controller.dart';

import '../support/fakes.dart';

/// Starts a controller over [n] entries; returns it with its notify count
/// once everything initial has arrived, plus the count after a burst of
/// one fact update per entry.
Future<(LibraryController, int, int)> _start(int n) async {
  final f = Fakes();
  for (var i = 0; i < n; i++) {
    await f.deps.repos.library.upsert(entry('/m$i'));
  }
  var notified = 0;
  final c = LibraryController(f.deps)
    ..addListener(() => notified++)
    ..start();
  await pumpEventQueue();
  final atStart = notified;
  notified = 0;
  for (var i = 0; i < n; i++) {
    f.unread.emit(mangaKeyOf('mangadex', '/m$i'), i);
    f.dl.emit(mangaKeyOf('mangadex', '/m$i'), true);
  }
  await pumpEventQueue();
  return (c, atStart, notified);
}

void main() {
  test('notifications do not grow with the library size', () async {
    final (small, smallStart, smallBurst) = await _start(5);
    final (big, bigStart, bigBurst) = await _start(50);
    addTearDown(small.dispose);
    addTearDown(big.dispose);
    expect(bigStart, smallStart, reason: '4 facts x N entries coalesce');
    expect(bigBurst, smallBurst);
    expect(bigBurst, 1, reason: 'one burst, one notify');
    expect(big.items.where((i) => i.downloaded), hasLength(50));
  });

  test('visible is computed once per change, not per read', () async {
    final (c, _, _) = await _start(3);
    addTearDown(c.dispose);
    final first = c.visible;
    expect(identical(c.visible, first), isTrue);
    expect(identical(c.items, c.items), isTrue);
    c.query = c.query.copyWith(search: 'm1');
    expect(identical(c.visible, first), isFalse);
    expect([for (final i in c.visible) i.mangaUrl], ['/m1']);
    c.toggle(mangaKeyOf('mangadex', '/m1'));
    expect(c.visible, hasLength(1), reason: 'selection keeps the list');
  });

  test('an unchanged fact value notifies nothing', () async {
    final f = Fakes();
    await f.deps.repos.library.upsert(entry('/a'));
    var notified = 0;
    final c = LibraryController(f.deps)
      ..addListener(() => notified++)
      ..start();
    addTearDown(c.dispose);
    await pumpEventQueue();
    notified = 0;
    f.dl.emit(mangaKeyOf('mangadex', '/a'), false);
    await pumpEventQueue();
    expect(notified, 0, reason: 'false again is not a change');
  });

  test('no notify after dispose', () async {
    final f = Fakes();
    await f.deps.repos.library.upsert(entry('/a'));
    var notified = 0;
    final c = LibraryController(f.deps)
      ..addListener(() => notified++)
      ..start();
    await pumpEventQueue();
    notified = 0;
    f.dl.emit(mangaKeyOf('mangadex', '/a'), true);
    c.dispose();
    await pumpEventQueue();
    expect(notified, 0);
  });
}
