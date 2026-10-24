import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/library/data/kv_table.dart';

import '../support/memory_kv.dart';

KvTable<int> _table(MemoryKv kv) => KvTable<int>(
  kv,
  'n/',
  decode: (json) => json['v']! as int,
  encode: (v) => {'v': v},
);

void main() {
  test('put persists under the prefix and reloads in a fresh table', () async {
    final kv = MemoryKv();
    await _table(kv).put('a', 1);
    expect(kv.data, {
      'n/a': jsonEncode({'v': 1}),
    });
    expect(await _table(kv).load(), {'a': 1});
  });

  test('corrupt or foreign rows are skipped, not fatal', () async {
    final kv = MemoryKv()
      ..data['n/bad'] = '{nope'
      ..data['n/list'] = '[1]'
      ..data['n/wrong'] = jsonEncode({'v': 'str'})
      ..data['n/ok'] = jsonEncode({'v': 2})
      ..data['other/x'] = jsonEncode({'v': 3});
    expect(await _table(kv).load(), {'ok': 2});
  });

  test('watch emits the snapshot then every change', () async {
    final kv = MemoryKv();
    final table = _table(kv);
    await table.put('a', 1);
    final seen = <Map<String, int>>[];
    final sub = table.watch().listen(seen.add);
    await pumpEventQueue();
    await table.put('b', 2);
    await pumpEventQueue();
    await sub.cancel();
    expect(seen, [
      {'a': 1},
      {'a': 1, 'b': 2},
    ]);
  });

  test('snapshots are immutable copies', () async {
    final table = _table(MemoryKv());
    await table.put('a', 1);
    final snap = await table.watch().first;
    await table.put('a', 5);
    expect(snap, {'a': 1});
    expect(() => snap['z'] = 0, throwsUnsupportedError);
  });

  test('get reads one row after load', () async {
    final table = _table(MemoryKv());
    expect(await table.get('a'), isNull);
    await table.put('a', 7);
    expect(await table.get('a'), 7);
  });
}
