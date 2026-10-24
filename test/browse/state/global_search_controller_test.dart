import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/state/global_search_controller.dart';

import '../fakes.dart';

void main() {
  test('fans out page 1 and keeps errors per source', () async {
    final ok = FakeSource('a');
    final bad = FakeSource('b')..failWith = StateError('down');
    final c = GlobalSearchController([ok, bad]);
    await c.search('  one piece ');
    expect(c.query, 'one piece');
    expect(ok.calls, ['search(one piece):1']);
    expect(c.results[0].items, hasLength(3));
    expect(c.results[0].error, isNull);
    expect(c.results[1].error, isA<StateError>());
    expect(c.results.every((r) => !r.loading), isTrue);
  });

  test('publishes fast sources before slow ones finish', () async {
    final slow = FakeSource('slow')..searchGate = Completer<void>();
    final fast = FakeSource('fast');
    final c = GlobalSearchController([slow, fast]);
    final done = c.search('x');
    await Future<void>.delayed(Duration.zero);
    expect(c.results[0].loading, isTrue);
    expect(c.results[1].items, isNotEmpty);
    slow.searchGate!.complete();
    await done;
    expect(c.results[0].items, isNotEmpty);
  });

  test('a source past the timeout reports a TimeoutException', () async {
    final hung = FakeSource('hung')..searchGate = Completer<void>();
    final c = GlobalSearchController([
      hung,
    ], timeout: const Duration(milliseconds: 10));
    await c.search('x');
    expect(c.results.single.error, isA<TimeoutException>());
  });

  test('a newer search supersedes an older one', () async {
    final gate = Completer<void>();
    final s = FakeSource('s')..searchGate = gate;
    final c = GlobalSearchController([s]);
    final old = c.search('old');
    s.searchGate = null;
    await c.search('new');
    expect(c.query, 'new');
    final settled = c.results.single;
    gate.complete();
    await old;
    expect(c.results.single, same(settled));
  });

  test('empty query clears results', () async {
    final c = GlobalSearchController([FakeSource('a')]);
    await c.search('x');
    await c.search('   ');
    expect(c.results, isEmpty);
  });

  test('results arriving after dispose are dropped', () async {
    final s = FakeSource('s')..searchGate = Completer<void>();
    final c = GlobalSearchController([s]);
    final pending = c.search('x');
    c.dispose();
    s.searchGate!.complete();
    await pending;
  });

  test('updateSources searches added, drops removed, keeps others', () async {
    final a = FakeSource('a');
    final b = FakeSource('b');
    final c = GlobalSearchController([a]);
    await c.updateSources([a]); // No query yet: nothing searched.
    expect(a.calls, isEmpty);
    await c.search('q');
    await c.updateSources([b, a]);
    expect(a.calls, ['search(q):1']);
    expect(b.calls, ['search(q):1']);
    expect(c.results.map((r) => r.source.id), ['b', 'a']);
    await c.updateSources([b]);
    expect(c.results.map((r) => r.source.id), ['b']);
  });

  test('a source removed mid-search drops its late result', () async {
    final slow = FakeSource('s')..searchGate = Completer<void>();
    final c = GlobalSearchController([slow]);
    final pending = c.search('q');
    await c.updateSources([]);
    slow.searchGate!.complete();
    await pending;
    expect(c.results, isEmpty);
  });
}
