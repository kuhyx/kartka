import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/state/paged_controller.dart';

PageFetcher<int> pagesOf(List<List<int>> pages, {List<int>? calls}) {
  return (page) async {
    calls?.add(page);
    return (items: pages[page - 1], hasNext: page < pages.length);
  };
}

void main() {
  test('appends pages in order and stops at the last page', () async {
    final calls = <int>[];
    final c = PagedController<int>(
      pagesOf([
        [1, 2],
        [3],
      ], calls: calls),
      keyOf: (i) => i,
    );
    expect(c.canLoadMore, isTrue);
    await c.loadMore();
    await c.loadMore();
    await c.loadMore();
    expect(c.items, [1, 2, 3]);
    expect(c.hasNext, isFalse);
    expect(calls, [1, 2]);
  });

  test('dedupes items repeated across pages', () async {
    final c = PagedController<int>(
      pagesOf([
        [1, 2],
        [2, 3],
      ]),
      keyOf: (i) => i,
    );
    await c.loadMore();
    await c.loadMore();
    expect(c.items, [1, 2, 3]);
  });

  test('ignores loadMore while a fetch is in flight', () async {
    final gate = Completer<PageResult<int>>();
    var calls = 0;
    final c = PagedController<int>((_) {
      calls++;
      return gate.future;
    }, keyOf: (i) => i);
    final first = c.loadMore();
    expect(c.loading, isTrue);
    await c.loadMore();
    gate.complete((items: [1], hasNext: false));
    await first;
    expect(calls, 1);
    expect(c.loading, isFalse);
  });

  test('records an error and retries the same page', () async {
    final calls = <int>[];
    var fail = true;
    final c = PagedController<int>((page) async {
      calls.add(page);
      if (fail) throw StateError('boom');
      return (items: [7], hasNext: false);
    }, keyOf: (i) => i);
    await c.loadMore();
    expect(c.error, isA<StateError>());
    expect(c.items, isEmpty);
    fail = false;
    await c.loadMore();
    expect(c.error, isNull);
    expect(c.items, [7]);
    expect(calls, [1, 1]);
  });

  test('reset swaps the fetcher and drops stale in-flight results', () async {
    final stale = Completer<PageResult<int>>();
    final c = PagedController<int>((_) => stale.future, keyOf: (i) => i);
    final pending = c.loadMore();
    await c.reset(fetch: pagesOf([
      [9],
    ]));
    stale.complete((items: [1], hasNext: true));
    await pending;
    expect(c.items, [9]);
    expect(c.hasNext, isFalse);
    expect(c.loading, isFalse);
  });

  test('a stale failure does not surface after reset', () async {
    final stale = Completer<PageResult<int>>();
    final c = PagedController<int>((_) => stale.future, keyOf: (i) => i);
    final pending = c.loadMore();
    await c.reset(fetch: pagesOf([
      [4],
    ]));
    stale.completeError(StateError('old'));
    await pending;
    expect(c.error, isNull);
    expect(c.items, [4]);
  });

  test('reset without a fetcher reloads from page 1', () async {
    final calls = <int>[];
    final c = PagedController<int>(
      pagesOf([
        [1],
        [2],
      ], calls: calls),
      keyOf: (i) => i,
    );
    await c.loadMore();
    await c.reset();
    expect(calls, [1, 1]);
    expect(c.items, [1]);
  });
}
