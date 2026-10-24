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
    final settled = c.results;
    gate.complete();
    await old;
    expect(c.results, same(settled));
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
}
