import 'package:crdt_sync/crdt_sync.dart' show Hlc;
import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' show Glados2, any;
import 'package:kartka/core/models/models.dart';
import 'package:kartka/sync/merge/merge_rules.dart';

import 'node_generators.dart';

String _h(int wall, [String node = 'dev-a']) =>
    Hlc(wallTimeMs: wall, counter: 0, nodeId: node).toStr();

void main() {
  group('compareHlc', () {
    test('null and garbage sort below any clock, and equal each other', () {
      expect(compareHlc(null, _h(1)), lessThan(0));
      expect(compareHlc(_h(1), 'garbage'), greaterThan(0));
      expect(compareHlc(null, 'garbage'), 0);
    });
    test('the device id breaks ties within one millisecond', () {
      expect(compareHlc(_h(5, 'b'), _h(5, 'a')), greaterThan(0));
    });
  });

  group('canon', () {
    test('sorts keys and folds integral doubles (RTDB echoes 2.0 as 2)', () {
      expect(
        canon({
          'b': 2.0,
          'a': [1.5],
        }),
        canon({
          'a': [1.5],
          'b': 2,
        }),
      );
    });
  });

  group('rtdbNormal', () {
    test('drops nulls and an empty clock map', () {
      expect(rtdbNormal({'a': null, 'b': 1, 'hlc': <String, Object?>{}}), {
        'b': 1,
      });
    });
    test('keeps a non-empty clock map', () {
      expect(
        rtdbNormal({
          'hlc': {'b': _h(1)},
        }),
        {
          'hlc': {'b': _h(1)},
        },
      );
    });
  });

  group('mergeLwwNode', () {
    test('a rename and a removal on two devices both survive', () {
      final a = {
        'title': 'New',
        'removed': false,
        'hlc': {'title': _h(9), 'removed': _h(1)},
      };
      final b = {
        'title': 'Old',
        'removed': true,
        'hlc': {'title': _h(1), 'removed': _h(8)},
      };
      expect(mergeLwwNode(a, b), {
        'title': 'New',
        'removed': true,
        'hlc': {'title': _h(9), 'removed': _h(8)},
      });
    });
    test('a newer clock for a field RTDB dropped (null) still wins', () {
      final cleared = {
        'hlc': {'coverUrl': _h(9)},
      };
      final stale = {
        'coverUrl': 'x',
        'hlc': {'coverUrl': _h(1)},
      };
      expect(mergeLwwNode(stale, cleared), cleared);
      expect(
        mergeLwwNode(cleared, {
          'hlc': {'coverUrl': _h(3)},
        }),
        cleared,
      );
    });
    test('a malformed clock map counts as no clocks', () {
      expect(mergeLwwNode({'title': 'a', 'hlc': 'bad'}, {'title': 'b'}), {
        'title': 'b',
      });
      expect(
        mergeLwwNode({
          'hlc': {'t': 5},
        }, {}),
        <String, Object?>{},
      );
    });
  });

  group('mergeRegister', () {
    test('the newer hlc wins whole, even when it is an unmark', () {
      final read = {'read': true, 'hlc': _h(1), 'url': '/c/1'};
      final unread = {'read': false, 'hlc': _h(2), 'url': '/c/1'};
      expect(mergeRegister(read, unread), unread);
      expect(mergeRegister(unread, read), unread);
    });
  });

  group('compareProgress', () {
    test('a missing or non-numeric chapterNumber sorts lowest', () {
      expect(
        compareProgress({'chapterNumber': 0, 'page': 0}, {'page': 9}),
        greaterThan(0),
      );
      expect(
        compareProgress({'chapterNumber': 'x'}, {'chapterNumber': 0}),
        lessThan(0),
      );
    });
    test('readAt breaks a tie in position', () {
      expect(compareProgress({'readAt': 'b'}, {'readAt': 'a'}), greaterThan(0));
    });

    // Differential: on well-formed nodes the node order agrees with THE
    // never-decrease ordering, ReadingProgress.isAheadOf (contracts §14).
    Glados2(any.progressNode, any.progressNode).test(
      'agrees with ReadingProgress.isAheadOf',
      (a, b) {
        if (a['chapterNumber'] == null || b['chapterNumber'] == null) return;
        final pa = ReadingProgress.fromJson(a);
        final pb = ReadingProgress.fromJson(b);
        if (pa.isAheadOf(pb)) expect(compareProgress(a, b), greaterThan(0));
        if (pb.isAheadOf(pa)) expect(compareProgress(a, b), lessThan(0));
      },
    );
  });
}
