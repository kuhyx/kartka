import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart' show FirebaseSyncError;
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/memory/memory_fakes.dart';
import 'package:kartka/sync/firebase_transport.dart';
import 'package:kartka/sync/rtdb_transport.dart';

class _Writer implements RtdbWriter {
  final List<(String, Map<String, Object?>)> patches = [];

  @override
  Future<String> idToken() async => 'tok';

  @override
  Future<void> patchValues(String path, Map<String, Object?> values) async =>
      patches.add((path, values));
}

void main() {
  group('InMemoryRtdb', () {
    test('behaves like RTDB: nulls delete, empty maps vanish', () async {
      final db = InMemoryRtdb();
      await db.patch({
        'a/b/c': 1,
        'a/b/d': {'x': null},
        'e': {'f': null, 'g': 2},
      });
      expect(db.tree, {
        'a': {
          'b': {'c': 1},
        },
        'e': {'g': 2},
      });
      await db.patch({'a/b/c': null});
      expect(db.tree, {
        'e': {'g': 2},
      });
      expect(await db.get('e/g'), 2);
      expect(await db.get('e/g/h'), isNull);
      expect(await db.get(''), {
        'e': {'g': 2},
      });
    });

    test('reads return copies, and failWith fails every call', () async {
      final db = InMemoryRtdb({
        'l': [1, 2],
      });
      final copy = await db.get('l');
      (copy! as List).add(3);
      expect(db.tree['l'], [1, 2]);
      db.failWith = FirebaseSyncError('down');
      expect(db.get('l'), throwsA(isA<FirebaseSyncError>()));
      expect(db.patch({}), throwsA(isA<FirebaseSyncError>()));
    });
  });

  group('FirebaseTransport', () {
    test('GETs /kartka/<path>.json with the token, decoding JSON', () async {
      final http = FakeKartkaHttp(
        (r) => FakeKartkaHttp.text(jsonEncode({'a': 1})),
      );
      final writer = _Writer();
      final t = FirebaseTransport(
        writer: writer,
        http: http,
        databaseUrl: 'https://db.example/',
      );
      expect(await t.get('source_health/x~2Ey'), {'a': 1});
      final url = http.requests.single.url;
      expect(url.path, '/kartka/source_health/x~2Ey.json');
      expect(url.queryParameters['auth'], 'tok');
      await t.get('');
      expect(http.requests.last.url.path, '/kartka.json');
    });

    test('a non-2xx read throws instead of looking empty', () async {
      final t = FirebaseTransport(
        writer: _Writer(),
        http: FakeKartkaHttp(),
        databaseUrl: 'https://db.example',
      );
      expect(t.get('revs'), throwsA(isA<FirebaseSyncError>()));
    });

    test('patches go through the crdt_sync writer at /kartka', () async {
      final writer = _Writer();
      final t = FirebaseTransport(
        writer: writer,
        http: FakeKartkaHttp(),
        databaseUrl: 'https://db.example',
      );
      await t.patch({'revs/d': '1'});
      expect(writer.patches.single.$1, 'kartka');
      expect(writer.patches.single.$2, {'revs/d': '1'});
    });
  });
}
