import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/logic/page_cache.dart';

void main() {
  late List<int> fetched;
  late bool fail;
  PageCache make() => PageCache(
    fetch: (i) async {
      fetched.add(i);
      if (fail) throw StateError('boom $i');
      return Uint8List.fromList([i]);
    },
  );

  setUp(() {
    fetched = [];
    fail = false;
  });

  test('dropFrom forgets every page at the index and after', () async {
    final first = Completer<void>();
    final c = PageCache(
      fetch: (i) async {
        fetched.add(i);
        if (i == 0) await first.future;
        return Uint8List.fromList([i]);
      },
    )..focus(0, [2, 5]);
    c.waitFor(6).ignore();
    expect(fetched, [0], reason: 'the rest wait for page 0');
    await c.get(4);
    c.dropFrom(4);
    first.complete();
    await pumpEventQueue();
    expect(fetched, [0, 4, 2]);
    expect((c.contains(2), c.contains(4), c.peek(4)), (true, false, null));
  });

  test('get fetches once and caches the future', () async {
    final c = make();
    final a = c.get(1);
    final b = c.get(1);
    expect(await a, [1]);
    expect(await b, [1]);
    expect(fetched, [1]);
    expect(c.contains(1), isTrue);
  });

  test('focus starts fetches without awaiting', () async {
    final c = make()..focus(2, [3]);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(fetched, [2, 3]);
    expect(await c.get(2), [2]);
    expect(fetched, [2, 3]);
  });

  test('failed fetches are evicted so a retry refetches', () async {
    fail = true;
    final c = make();
    await expectLater(c.get(0), throwsStateError);
    expect(c.contains(0), isFalse);
    fail = false;
    expect(await c.get(0), [0]);
    expect(fetched, [0, 0]);
  });

  test('failed prefetches do not surface as unhandled errors', () async {
    fail = true;
    make().focus(4, [5]);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(fetched, [4, 5]);
  });

  test('retain evicts everything outside the window', () async {
    final c = make();
    await Future.wait([c.get(0), c.get(1), c.get(2)]);
    c.retain({1});
    expect(c.contains(0), isFalse);
    expect(c.contains(1), isTrue);
    expect(c.contains(2), isFalse);
    c.clear();
    expect(c.contains(1), isFalse);
  });

  test('a stale failure does not evict the refetched entry', () async {
    final pending = <Completer<Uint8List>>[];
    final c = PageCache(
      fetch: (i) {
        final done = Completer<Uint8List>();
        pending.add(done);
        return done.future;
      },
    );
    final first = c.get(0);
    c.retain({});
    final second = c.get(0);
    pending[0].completeError(StateError('stale'));
    await expectLater(first, throwsStateError);
    expect(c.contains(0), isTrue);
    pending[1].complete(Uint8List(1));
    expect(await second, hasLength(1));
  });

  test('peek: the loaded bytes, synchronously; gone once dropped', () async {
    final c = make();
    final pending = c.get(1);
    expect(c.peek(1), isNull);
    final bytes = await pending;
    expect(c.peek(1), same(bytes));
    await c.get(2);
    c.retain({2});
    expect(c.peek(1), isNull);
    expect(c.peek(2), isNotNull);
    c.clear();
    expect(c.peek(2), isNull);
    fail = true;
    await expectLater(c.get(3), throwsStateError);
    expect(c.peek(3), isNull);
  });
}
