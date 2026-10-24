import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/backup_import/tracker_binding_sink.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/platform/key_value_store.dart';

class _MemoryKv implements KeyValueStore {
  final Map<String, String> data = {};

  @override
  Future<String?> get(String key) async => data[key];

  @override
  Future<void> set(String key, String value) async => data[key] = value;

  @override
  Future<void> remove(String key) async => data.remove(key);

  @override
  Future<Map<String, String>> entries({String prefix = ''}) async => {
    for (final e in data.entries)
      if (e.key.startsWith(prefix)) e.key: e.value,
  };
}

void main() {
  final kv = _MemoryKv();
  final store = KvTrackerBindingStore(kv);
  const key = 'mangadex|/manga/x';
  final path = '${KvTrackerBindingStore.prefix}${mangaKeyHash(key)}/anilist';

  test('writes a binding record once and is then idempotent', () async {
    expect(await store.bind(key, 'anilist', '1', lastPushedChapter: 5), isTrue);
    expect(jsonDecode(kv.data[path]!), {
      'key': key,
      'remoteId': '1',
      'lastPushedChapter': 5,
    });
    expect(
      await store.bind(key, 'anilist', '1', lastPushedChapter: 5),
      isFalse,
    );
  });

  test('never lowers the pushed chapter, raises it when higher', () async {
    expect(
      await store.bind(key, 'anilist', '1', lastPushedChapter: 2),
      isFalse,
    );
    expect(await store.bind(key, 'anilist', '1', lastPushedChapter: 9), isTrue);
    expect((jsonDecode(kv.data[path]!) as Map)['lastPushedChapter'], 9);
  });

  test('an existing binding to another remote id wins', () async {
    expect(
      await store.bind(key, 'anilist', '2', lastPushedChapter: 99),
      isFalse,
    );
    expect((jsonDecode(kv.data[path]!) as Map)['remoteId'], '1');
  });
}
