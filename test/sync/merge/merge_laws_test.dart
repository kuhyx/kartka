import 'package:glados/glados.dart';
import 'package:kartka/sync/merge/merge_rules.dart';
import 'package:kartka/sync/merge/tracker_merge.dart';

import 'node_generators.dart';

/// Every merge must be a join: commutative, associative and idempotent, so
/// devices converge whatever order (and however often) they see each other.
void _joinLaws(String name, Generator<Node> gen, Merge merge) {
  group('$name is a join', () {
    Glados2(gen, gen).test('commutative', (a, b) {
      expect(canon(merge(a, b)), canon(merge(b, a)));
    });
    Glados3(gen, gen, gen).test('associative', (a, b, c) {
      expect(canon(merge(merge(a, b), c)), canon(merge(a, merge(b, c))));
    });
    Glados(gen).test('idempotent', (a) {
      expect(canon(merge(a, a)), canon(a));
    });
    Glados2(gen, gen).test('absorbs: merging the result again is a no-op', (
      a,
      b,
    ) {
      final ab = merge(a, b);
      expect(canon(merge(ab, b)), canon(ab));
    });
  });
}

void main() {
  _joinLaws('mergeLwwNode', any.lwwNode, mergeLwwNode);
  _joinLaws('mergeRegister', any.registerNode, mergeRegister);
  _joinLaws('mergeProgress', any.progressNode, mergeProgress);
  _joinLaws('mergeTracker', any.trackerNode, mergeTracker);

  Glados2(any.trackerNode, any.trackerNode).test(
    'a tracker never forgets a pushed chapter',
    (a, b) {
      final m = mergeTracker(a, b);
      for (final side in [a, b]) {
        final pushed = (side[kPushedField] as Map?) ?? const {};
        for (final MapEntry(:key, :value) in pushed.entries) {
          final kept = ((m[kPushedField] as Map?) ?? const {})[key] as int;
          expect(kept, greaterThanOrEqualTo(value as int));
        }
      }
    },
  );

  group('progress is monotonic', () {
    Glados2(any.progressNode, any.progressNode).test(
      'the merge is never behind either input',
      (a, b) {
        final m = mergeProgress(a, b);
        expect(compareProgress(m, a), greaterThanOrEqualTo(0));
        expect(compareProgress(m, b), greaterThanOrEqualTo(0));
      },
    );
    Glados2(any.progressNode, any.progressNode).test(
      'the merge is one of the inputs, never a blend',
      (a, b) {
        final m = canon(mergeProgress(a, b));
        expect(m == canon(a) || m == canon(b), isTrue);
      },
    );
  });

  group('LWW picks the newer clock per field', () {
    Glados2(any.lwwNode, any.lwwNode).test('each field keeps the max hlc', (
      a,
      b,
    ) {
      final m = mergeLwwNode(a, b);
      final clocks = (m['hlc'] as Map?) ?? const {};
      for (final field in clocks.keys) {
        final ca = (a['hlc'] as Map?)?[field] as String?;
        final cb = (b['hlc'] as Map?)?[field] as String?;
        final mc = clocks[field] as String;
        expect(compareHlc(mc, ca), greaterThanOrEqualTo(0));
        expect(compareHlc(mc, cb), greaterThanOrEqualTo(0));
      }
    });
  });
}
