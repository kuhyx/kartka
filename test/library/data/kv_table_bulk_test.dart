import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/library/data/kv_table.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

String _decode(Map<String, Object?> json) => json['t']! as String;

KvTable<String> _table(MemoryKeyValueStore kv) =>
    KvTable<String>(kv, 'n/', decode: _decode, encode: (v) => {'t': v});

void main() {
  test(
    'every watcher shares one snapshot instead of copying the rows',
    () async {
      final kv = MemoryKeyValueStore({
        for (var i = 0; i < 10; i++) 'n/$i': jsonEncode({'t': '$i'}),
      });
      final table = _table(kv);
      final firsts = await Future.wait([
        for (var i = 0; i < 20; i++) table.watch().first,
      ]);
      expect(firsts.every((m) => identical(m, firsts.first)), isTrue);
      await table.put('0', 'changed');
      final after = await table.watch().first;
      expect(after['0'], 'changed');
      expect(identical(after, firsts.first), isFalse);
      expect(firsts.first['0'], '0', reason: 'old snapshots are immutable');
    },
  );

  test('a large table decodes off the UI isolate to the same rows', () async {
    final rows = {for (var i = 0; i < 3000; i++) '$i': 'title $i ' * 4};
    final kv = MemoryKeyValueStore({
      for (final MapEntry(:key, :value) in rows.entries)
        'n/$key': jsonEncode({'t': value}),
      'n/bad': '{nope',
      'n/list': '[1]',
    });
    expect(
      (await kv.entries()).values.fold(0, (n, v) => n + v.length),
      greaterThan(kvTableOffUiChars),
    );
    expect(await _table(kv).load(), rows);
  });
}
