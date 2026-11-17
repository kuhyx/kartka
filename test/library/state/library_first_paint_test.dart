import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/state/library_controller.dart';

import '../support/fakes.dart';

/// The grid's first paint waits only for the library rows: the per-entry
/// fact streams (unread, downloads, tracking, progress: 4 x N, each a
/// chapter-list read) start after it, so a big library does not hold the
/// `library.load` spinner past 1 s (perf.slow a133bbb8).
void main() {
  test('facts start only after the first paint', () async {
    final f = Fakes();
    for (var i = 0; i < 20; i++) {
      await f.deps.repos.library.upsert(entry('/m$i'));
    }
    final painted = <void Function()>[];
    var notified = 0;
    final c = LibraryController(f.deps, afterPaint: painted.add)
      ..addListener(() => notified++)
      ..start();
    addTearDown(c.dispose);
    await pumpEventQueue();
    expect(c.loaded, isTrue);
    expect(c.items, hasLength(20));
    expect(notified, greaterThan(0), reason: 'the grid shows at once');
    expect(f.unread.controllers, isEmpty, reason: 'no fact stream yet');

    // A second emission before the paint does not start them either.
    await f.deps.repos.library.upsert(entry('/late'));
    await pumpEventQueue();
    expect(f.unread.controllers, isEmpty);
    expect(painted, hasLength(1), reason: 'one deferred start');

    painted.single();
    await pumpEventQueue();
    expect(f.unread.controllers, hasLength(21));
    f.dl.emit(mangaKeyOf('mangadex', '/late'), true);
    await pumpEventQueue();
    final late = c.items.singleWhere((i) => i.mangaUrl == '/late');
    expect(late.downloaded, isTrue);

    // Later emissions track new entries at once, as before.
    await f.deps.repos.library.upsert(entry('/new'));
    await pumpEventQueue();
    expect(f.unread.controllers, hasLength(22));
  });

  test('a dispose before the paint starts nothing', () async {
    final f = Fakes();
    await f.deps.repos.library.upsert(entry('/a'));
    final painted = <void Function()>[];
    final c = LibraryController(f.deps, afterPaint: painted.add)..start();
    await pumpEventQueue();
    c.dispose();
    painted.single();
    await pumpEventQueue();
    expect(f.unread.controllers, isEmpty);
  });
}
