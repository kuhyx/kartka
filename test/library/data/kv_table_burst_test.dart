import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/library/data/kv_table.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

String _decode(Map<String, Object?> json) => json['t']! as String;

KvTable<String> _table(MemoryKeyValueStore kv) =>
    KvTable<String>(kv, 'n/', decode: _decode, encode: (v) => {'t': v});

class _FlakyKv extends MemoryKeyValueStore {
  bool failNext = false;

  @override
  Future<void> set(String key, String value) async {
    if (failNext) {
      failNext = false;
      throw StateError('disk full');
    }
    await super.set(key, value);
  }
}

void main() {
  const n = 775;

  test('a $n-row batch emits once, copies at most once, tells each row '
      'watcher once', () async {
    final table = _table(MemoryKeyValueStore());
    final emitted = <Map<String, String>>[];
    final tableSub = table.watch().listen(emitted.add);
    final seen = <String, List<String?>>{};
    final rowSubs = [
      for (var i = 0; i < n; i++)
        table.watchRow('$i').listen((v) => (seen['$i'] ??= []).add(v)),
    ];
    await pumpEventQueue();
    expect(emitted, hasLength(1), reason: 'the initial, empty snapshot');
    final base = table.rowCallbacks;

    await table.updateAll({for (var i = 0; i < n; i++) '$i': (_) => 'v$i'});

    // Before: N emissions of ever larger copies (~N^2/2 entries) and every
    // row watcher woken by every write (N^2 callbacks).
    expect(emitted, hasLength(2));
    expect(emitted.last, hasLength(n));
    expect(table.copies, lessThanOrEqualTo(1));
    expect(table.rowsCopied, lessThanOrEqualTo(n));
    expect(table.rowCallbacks - base, n, reason: 'one per changed row');
    expect(seen['0'], [null, 'v0']);
    expect(seen['$n'], isNull);
    expect(emitted.last.keys.take(3), ['0', '1', '2'], reason: 'in order');
    await tableSub.cancel();
    for (final s in rowSubs) {
      await s.cancel();
    }
  });

  test('single awaited writes still emit once each', () async {
    final table = _table(MemoryKeyValueStore());
    final emitted = <int>[];
    final sub = table.watch().listen((m) => emitted.add(m.length));
    await pumpEventQueue();
    for (var i = 0; i < 3; i++) {
      await table.put('$i', 'x');
    }
    expect(emitted, [0, 1, 2, 3]);
    await sub.cancel();
  });

  test('a snapshot already handed out never changes', () async {
    final table = _table(MemoryKeyValueStore());
    await table.putAll({'a': '1', 'b': '2'});
    final before = await table.watch().first;
    await table.putAll({'a': '9', 'c': '3'});
    expect(before, {'a': '1', 'b': '2'});
    expect(() => before['z'] = 'no', throwsUnsupportedError);
    expect(await table.watch().first, {'a': '9', 'b': '2', 'c': '3'});
  });

  test('writes nobody watches copy nothing', () async {
    final table = _table(MemoryKeyValueStore());
    for (var i = 0; i < 50; i++) {
      await table.put('$i', 'x');
    }
    expect(table.copies, 0);
    expect(await table.get('49'), 'x');
  });

  test('null and equal results leave rows and watchers alone', () async {
    final table = _table(
      MemoryKeyValueStore({
        'n/a': jsonEncode({'t': '1'}),
      }),
    );
    final emitted = <Object?>[];
    final sub = table.watch().listen(emitted.add);
    final row = <String?>[];
    final rowSub = table.watchRow('a').listen(row.add);
    await pumpEventQueue();
    await table.updateAll({'a': (_) => '1', 'b': (_) => null});
    expect(emitted, hasLength(1));
    expect(row, ['1']);
    await sub.cancel();
    await rowSub.cancel();
  });

  test('a failed write does not stop the next emission', () async {
    final kv = _FlakyKv();
    final table = _table(kv);
    final emitted = <int>[];
    final sub = table.watch().listen((m) => emitted.add(m.length));
    await pumpEventQueue();
    kv.failNext = true;
    await expectLater(table.put('a', '1'), throwsStateError);
    await table.put('b', '2');
    expect(emitted, [0, 1]);
    await sub.cancel();
  });

  test('a row watcher cancelled before the table loads is not woken', () async {
    final table = _table(MemoryKeyValueStore());
    final seen = <String?>[];
    await table.watchRow('a').listen(seen.add).cancel();
    await table.put('a', '1');
    expect(seen, isEmpty);
    expect(table.rowCallbacks, 0);
  });
}
