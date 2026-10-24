import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/sync/merge/merge_rules.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_engine.dart';
import 'package:kartka/sync/sync_feed.dart';

import 'fakes.dart';

Node _read(SyncEngine e, int i) => {
  'read': true,
  kHlcField: e.tick().toStr(),
  'url': '/c/$i',
};

void main() {
  late InMemoryRtdb db;
  setUp(() => db = InMemoryRtdb());

  test('a peer fetches only the changed node, not the subtrees', () async {
    final a = await engineFor('dev-a', db);
    final b = await engineFor('dev-b', db);
    await a.writeAll({for (var i = 0; i < 300; i++) 'read/h/c$i': _read(a, i)});
    await b.poll(); // first sight of dev-a: full pull
    await a.write('read/h/c1', {..._read(a, 1), 'read': false});
    final before = db.reads;
    await b.poll();
    // revs + log/dev-a + the one node.
    expect(db.reads - before, 3);
    expect(b.shadow.node('read/h/c1'), containsPair('read', false));
  });

  test('the feed keeps a window of revisions and prunes older ones', () async {
    final a = await engineFor('dev-a', db);
    for (var i = 0; i < kFeedWindow + 2; i++) {
      await a.write('read/h/c$i', _read(a, i));
    }
    final log = (db.tree['log']! as Map)['dev-a'] as Map;
    expect(log.containsKey('r1'), isFalse);
    expect(log.containsKey('r2'), isFalse);
    expect(log['r${kFeedWindow + 2}'], 'read/h/c${kFeedWindow + 1}');
  });

  test('a peer too far behind falls back to a full pull', () async {
    final a = await engineFor('dev-a', db);
    final b = await engineFor('dev-b', db);
    await a.write('read/h/c0', _read(a, 0));
    await b.poll();
    for (var i = 1; i <= kFeedWindow + 1; i++) {
      await a.write('read/h/c$i', _read(a, i));
    }
    await b.poll();
    expect(b.shadow.namespace('read'), hasLength(kFeedWindow + 2));
  });

  test('big pushes go out in chunks with one revision, logged as *', () async {
    final a = await engineFor('dev-a', db);
    await a.writeAll({
      for (var i = 0; i < kPushChunk + 5; i++) 'read/h/c$i': _read(a, i),
    });
    expect(db.writes, 2);
    expect(db.tree['revs'], {'dev-a': '1'});
    expect((db.tree['log']! as Map)['dev-a'], {'r1': '*'});
    final b = await engineFor('dev-b', db);
    await b.poll();
    expect(b.shadow.namespace('read'), hasLength(kPushChunk + 5));
  });

  test('a missing or malformed log entry means a full pull', () async {
    final now = {'dev-a': '3'};
    expect((await planPull(db, now, {'dev-a': '2'})).full, isTrue);
    await db.patch({'log/dev-a/r3': '*'});
    expect((await planPull(db, now, {'dev-a': '2'})).full, isTrue);
    expect((await planPull(db, now, {'dev-a': 'x'})).full, isTrue);
    expect((await planPull(db, now, {'dev-a': '4'})).full, isTrue);
    await db.patch({'log/dev-a/r3': 'read/h/c1\nread/h/c2'});
    final delta = await planPull(db, now, {'dev-a': '2'});
    expect(delta.full, isFalse);
    expect(delta.paths, {'read/h/c1', 'read/h/c2'});
    final none = await planPull(db, now, now);
    expect(none.full, isFalse);
    expect(none.paths, isEmpty);
  });

  test('more than the delta budget of paths means a full pull', () async {
    final paths = [for (var i = 0; i <= kFeedMaxDelta; i++) 'read/h/c$i'];
    await db.patch({'log/dev-a/r1': paths.join('\n')});
    final plan = await planPull(db, {'dev-a': '1'}, {'dev-a': '0'});
    expect(plan.full, isTrue);
  });

  test('page turns coalesce into one push per deferral window', () async {
    const window = Duration(milliseconds: 100);
    final a = await engineFor('dev-a', db, deferFor: window);
    for (var page = 0; page < 10; page++) {
      await a.writeDeferred('progress/h', {'chapterNumber': 1, 'page': page});
    }
    expect(db.writes, 0);
    await Future<void>.delayed(window * 2);
    expect(db.writes, 1);
    expect((db.tree['progress']! as Map)['h'], containsPair('page', 9));
    await a.writeDeferred('progress/h', {'chapterNumber': 1, 'page': 10});
    await a.flush();
    expect(db.writes, 2);
    await a.writeDeferred('progress/h', {'chapterNumber': 1, 'page': 3});
    await Future<void>.delayed(window * 2);
    expect(db.writes, 2, reason: 'a stale page is a no-op');
    await a.dispose();
  });
}
