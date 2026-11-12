import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/memory/memory_fakes.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sync/firebase_transport.dart';
import 'package:kartka/sync/json_equal.dart';
import 'package:kartka/sync/off_ui_json.dart';
import 'package:kartka/sync/sync_shadow.dart';

class _Writer implements RtdbWriter {
  @override
  Future<String> idToken() async => 'tok';

  @override
  Future<void> patchValues(String path, Map<String, Object?> values) async {}
}

Map<String, Object?> _big() => {
  for (var i = 0; i < 4000; i++) 'k$i': {'title': 'manga $i', 'n': i},
};

void main() {
  test('jsonEquals: deep, key-order blind, type and length aware', () {
    expect(jsonEquals({'a': 1, 'b': 2}, {'b': 2, 'a': 1}), isTrue);
    expect(
      jsonEquals(
        {
          'x': [1, 'y', null, true],
        },
        {
          'x': [1, 'y', null, true],
        },
      ),
      isTrue,
    );
    expect(jsonEquals({'a': 1}, {'a': 2}), isFalse);
    expect(jsonEquals({'a': 1}, {'b': 1}), isFalse);
    expect(jsonEquals({'a': 1}, {'a': 1, 'b': 1}), isFalse);
    expect(jsonEquals([1, 2], [2, 1]), isFalse);
    expect(jsonEquals([1], [1, 1]), isFalse);
    expect(jsonEquals({'a': null}, <String, Object?>{}), isFalse);
    expect(jsonEquals([1], {'0': 1}), isFalse);
    expect(jsonEquals({'0': 1}, [1]), isFalse);
    expect(jsonEquals('1', 1), isFalse);
    expect(jsonEquals(null, null), isTrue);
  });

  test('decodeJsonOffUi: small inline, large in an isolate, same value', () {
    expect(decodeJsonOffUi('{"a":1}'), completion({'a': 1}));
    final text = jsonEncode(_big());
    expect(text.length, greaterThan(offUiJsonChars));
    expect(decodeJsonOffUi(text), completion(_big()));
    expect(decodeJsonOffUi('{bad'), throwsFormatException);
    expect(
      decodeJsonOffUi('[${'1,' * offUiJsonChars}x]'),
      throwsFormatException,
    );
  });

  test('a large RTDB response is decoded off the UI isolate', () async {
    final body = jsonEncode(_big());
    final t = FirebaseTransport(
      root: 'kartka',
      writer: _Writer(),
      http: FakeKartkaHttp((r) => FakeKartkaHttp.text(body)),
      databaseUrl: 'https://db.example/',
    );
    expect(await t.get('library'), _big());
  });

  test('a large persisted shadow loads the same off the UI isolate', () async {
    final kv = MemoryKeyValueStore({
      for (var i = 0; i < 800; i++)
        'sync.b.library/h$i': jsonEncode({
          'library/h$i': {'title': 'manga $i' * 20},
        }),
      'sync.b.library/bad': '{bad',
      'sync.peers': '{bad',
    });
    final s = await SyncShadow.load(kv);
    expect(s.paths, hasLength(800));
    expect(s.node('library/h7'), {'title': 'manga 7' * 20});
    expect(s.peers, isEmpty, reason: 'a corrupt peers entry reads as none');
  });

  test('big unapplied/dirty lists decode off the UI isolate', () async {
    final paths = [for (var i = 0; i < 4000; i++) 'read/h${i % 50}/c$i'];
    final kv = MemoryKeyValueStore({
      'sync.b.library/h1': jsonEncode({
        'library/h1': {'title': 'one'},
      }),
      'sync.unapplied': jsonEncode(paths),
      'sync.dirty': jsonEncode(paths.take(2000).toList()),
    });
    expect(
      (await kv.get('sync.unapplied'))!.length,
      greaterThan(offUiJsonChars),
    );
    final before = offUiRuns;

    final s = await SyncShadow.load(kv);

    // Before: the lists were parsed inline; only the (tiny) buckets could
    // have gone off the UI isolate.
    expect(offUiRuns, before + 1);
    expect(s.unapplied, hasLength(4000));
    expect(s.dirty, hasLength(2000));
    expect(s.node('library/h1'), {'title': 'one'});
  });

  test('missing or corrupt lists read as empty', () async {
    final kv = MemoryKeyValueStore({
      'sync.unapplied': '{bad',
      'sync.dirty': '{"a":1}',
    });
    final s = await SyncShadow.load(kv);
    expect(s.unapplied, isEmpty);
    expect(s.dirty, isEmpty);
    expect((await SyncShadow.load(MemoryKeyValueStore())).dirty, isEmpty);
  });
}
