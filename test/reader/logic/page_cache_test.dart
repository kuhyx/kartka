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

  test('get fetches once and caches the future', () async {
    final c = make();
    final a = c.get(1);
    final b = c.get(1);
    expect(await a, [1]);
    expect(await b, [1]);
    expect(fetched, [1]);
    expect(c.contains(1), isTrue);
  });

  test('prefetch starts fetches without awaiting', () async {
    final c = make()..prefetch([2, 3]);
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
    make().prefetch([4]);
    await Future<void>.delayed(Duration.zero);
    expect(fetched, [4]);
  });

  test('retain evicts everything outside the window', () async {
    final c = make()..prefetch([0, 1, 2]);
    await Future<void>.delayed(Duration.zero);
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
}
