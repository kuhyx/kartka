import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/sync/e2e/sealed_transport.dart';
import 'package:kartka/sync/merge/merge_rules.dart';
import 'package:kartka/sync/rtdb_transport.dart';

import 'e2e_fixtures.dart';

Map<String, Object?> _at(InMemoryRtdb db, String path) {
  Object? node = db.tree;
  for (final s in path.split('/')) {
    node = (node! as Map<String, Object?>)[s];
  }
  return node! as Map<String, Object?>;
}

const _b = '2026-01-01T00:00:00.000Z-0000-dev-a';
const _c = '2026-01-02T00:00:00.000Z-0000-dev-a';

void main() {
  late InMemoryRtdb db;
  late SealedTransport t;
  setUp(() async {
    db = InMemoryRtdb();
    t = SealedTransport(db, await testCipher());
  });

  test(
    'nodes round-trip; only path, newest hlc and tombstone are clear',
    () async {
      final node = {
        'title': 'Berserk',
        'removed': true,
        'gone': null,
        kHlcField: {'title': _b, 'removed': _c},
      };
      await t.patch({'library/h1': node});
      final stored = _at(db, 'library/h1');
      expect(stored.keys, unorderedEquals(['p', 'h', 'd']));
      expect(stored['h'], _c);
      expect(stored['d'], isTrue);
      expect(await t.get('library/h1'), {
        'title': 'Berserk',
        'removed': true,
        kHlcField: {'title': _b, 'removed': _c},
      });
      expect(await t.get('library'), {'h1': await t.get('library/h1')});
    },
  );

  test('numeric keys read back as a list still open', () async {
    await t.patch({
      'membership/h/0': {'member': true, kHlcField: 'a'},
      'membership/h/1': {'member': false, kHlcField: 'b'},
    });
    final h = _at(db, 'membership')['h']! as Map<String, Object?>;
    db.tree['membership'] = {
      'h': [h['0'], h['1']],
    };
    expect(await t.get('membership'), {
      'h': {
        '0': {'member': true, kHlcField: 'a'},
        '1': {'member': false, kHlcField: 'b'},
      },
    });
    expect(_at(db, 'membership')['h'], isA<List<Object?>>());
  });

  test(
    'moved, edited, plaintext or foreign-key nodes read as absent',
    () async {
      await t.patch({
        'read/h/c1': {'read': true, kHlcField: 'a'},
      });
      final sealed = _at(db, 'read/h/c1');
      db.tree['read'] = {
        'h': {
          'moved': sealed,
          'edited': {...sealed, 'd': true},
          'plain': {'read': true, kHlcField: 'a'},
          'json': {
            'p': jsonEncode({'read': true}),
          },
        },
      };
      final other = SealedTransport(db, await testCipher(9));
      expect(await t.get('read'), {'h': <String, Object?>{}});
      await t.patch({
        'read/h/c2': {'read': true, kHlcField: 'a'},
      });
      expect(await other.get('read/h/c2'), isNull);
    },
  );

  test('revs, log and source_health pass through clear', () async {
    await t.patch({
      'revs/dev-a': '3',
      'log/dev-a/r3': 'library/h1',
      'source_health/x': {'id': 'mangadex'},
    });
    expect(db.tree['revs'], {'dev-a': '3'});
    expect(await t.get('log/dev-a/r3'), 'library/h1');
    expect(await t.get('source_health'), {
      'x': {'id': 'mangadex'},
    });
  });

  test('errors are sealed per report; null deletes', () async {
    await t.patch({
      'errors/dev-a/e1': {'message': 'boom'},
    });
    expect(canon(db.tree), isNot(contains('boom')));
    expect(await t.get('errors/dev-a/e1'), {'message': 'boom'});
    await t.patch({'errors/dev-a/e1': null});
    expect(db.tree, isEmpty);
  });

  test('a node pruned to nothing deletes it', () async {
    await t.patch({
      'progress/h': {'page': 1},
    });
    await t.patch({
      'progress/h': {'page': null},
    });
    expect(db.tree, isEmpty);
  });

  test('anything without a rule is refused', () async {
    for (final bad in [
      {'misc/x': 1},
      {'library': <String, Object?>{}},
      {'library/h/title': 'x'},
      {'library/h': 'x'},
      {'': 1},
    ]) {
      await expectLater(t.patch(bad), throwsA(isA<E2eLayoutError>()));
    }
    await expectLater(t.get('misc'), throwsA(isA<E2eLayoutError>()));
    expect(db.writes, 0);
    expect('${const E2eLayoutError('x')}', 'E2eLayoutError: x');
  });

  test('tombstones per namespace', () {
    expect(isTombstone('categories', {'removed': true}), isTrue);
    expect(isTombstone('membership', {'member': false}), isTrue);
    expect(isTombstone('read', {'read': false}), isTrue);
    expect(isTombstone('settings', {'key': 'k'}), isTrue);
    expect(isTombstone('settings', {'key': 'k', 'enc': 'x'}), isFalse);
    expect(isTombstone('progress', {'page': 1}), isFalse);
  });

  test('the legacy tree only reads', () async {
    final old = InMemoryRtdb({
      'revs': {'dev-a': '1'},
    });
    expect(await LegacyTree(old).get('revs'), {'dev-a': '1'});
    expect(kE2eLayout.prefix, 'kartka-e2e');
    expect(kE2eLayout.e2ePath, 'kartka-e2e/e2e');
  });
}
