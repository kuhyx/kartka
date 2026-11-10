import 'package:crdt_sync/crdt_sync.dart' show Hlc;
import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' show Glados, StringAnys, any;
import 'package:kartka/core/models/models.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/wire/wire.dart';

String _h(int ms, [int counter = 0]) =>
    Hlc(wallTimeMs: ms, counter: counter, nodeId: 'd').toStr();

void main() {
  Glados(any.stringOf(r'ab.$#[]/~2F7E')).test(
    'rtdbKey round-trips and never contains a forbidden character',
    (id) {
      final key = rtdbKey(id);
      expect(rtdbKeyDecode(key), id);
      expect(key, isNot(matches(r'[.$#\[\]/]')));
    },
  );

  group('stampChanges', () {
    test('stamps only changed fields; nulls are stamped but omitted', () {
      final old = {
        'title': 'A',
        'coverUrl': 'x',
        'hlc': {'title': _h(1), 'coverUrl': _h(1)},
      };
      expect(stampChanges(old, {'title': 'A', 'coverUrl': null}, _h(2)), {
        'hlc': {'coverUrl': _h(2)},
      });
    });
    test('an unclocked old value is re-stamped; no change is null', () {
      expect(stampChanges({'title': 'A'}, {'title': 'A'}, _h(2)), {
        'title': 'A',
        'hlc': {'title': _h(2)},
      });
      final clocked = {
        'title': 'A',
        'hlc': {'title': _h(1)},
      };
      expect(stampChanges(clocked, {'title': 'A'}, _h(2)), isNull);
    });
  });

  test('maxHlcTime takes the newest valid clock, skipping garbage', () {
    expect(
      maxHlcTime({
        'hlc': {'a': _h(5000), 'b': 'junk', 'c': _h(9000)},
      }),
      DateTime.fromMillisecondsSinceEpoch(9000, isUtc: true),
    );
    expect(maxHlcTime({}), DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
  });

  test('localStamp keeps same-millisecond ticks ordered', () {
    final a = localStamp(Hlc.fromStr(_h(1000)));
    final b = localStamp(Hlc.fromStr(_h(1000, 1)));
    expect(b.isAfter(a), isTrue);
  });

  test('libraryFromNode derives sourceId/mangaUrl from the key', () {
    final e = libraryFromNode({
      'key': 'mangadex|/manga/1',
      'title': 'T',
      'addedAt': '2026-01-01T00:00:00.000Z',
      'hlc': {'title': _h(7000)},
    })!;
    expect(
      (e.sourceId, e.mangaUrl, e.removed),
      ('mangadex', '/manga/1', false),
    );
    expect(e.updatedAt.millisecondsSinceEpoch, 7000);
    expect(libraryFromNode({'key': 'k', 'title': 'T'}), isNull);
  });

  test('categoryFromNode falls back to the id in the path', () {
    final c = categoryFromNode('categories/${rtdbKey('a/b.c')}', {
      'name': 'N',
      'order': 2.0,
      'removed': true,
    })!;
    expect((c.id, c.order, c.removed), ('a/b.c', 2, true));
    expect(categoryFromNode('categories/x', {'name': 'N'}), isNull);
  });

  test('progressFromNode rejects malformed nodes', () {
    final ok = {
      'key': 'k',
      'chapterUrl': '/c',
      'chapterNumber': 3,
      'page': 1,
      'readAt': '2026-10-24T00:00:00.000Z',
    };
    expect(progressFromNode(ok)!.chapterNumber, 3.0);
    expect(progressFromNode(ok)!.pageCount, isNull);
    expect(progressFromNode({...ok, 'pageCount': 30})!.pageCount, 30);
    expect(progressFromNode({...ok, 'pageCount': 'x'})!.pageCount, isNull);
    expect(progressFromNode({...ok, 'readAt': 'never'}), isNull);
    expect(progressFromNode({...ok, 'page': 'x'}), isNull);
  });

  test('paths hash keys and escape category ids', () {
    final key = mangaKeyOf('s', '/m');
    expect(libraryPath(key), 'library/${mangaKeyHash(key)}');
    expect(progressPath(key), 'progress/${mangaKeyHash(key)}');
    expect(membershipPath(key, 'a.b'), 'membership/${mangaKeyHash(key)}/a~2Eb');
    expect(
      readPath(key, '/c/1'),
      'read/${mangaKeyHash(key)}/${mangaKeyHash('/c/1')}',
    );
  });
}
