import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/browse/state/shared_health_lookup.dart';

class _Upstream implements SourceHealthLookup {
  final controller =
      StreamController<Map<String, SourceHealthSummary>>.broadcast();
  int watches = 0;

  @override
  Stream<Map<String, SourceHealthSummary>> watch() {
    watches++;
    return controller.stream;
  }

  @override
  Widget? buildBadge(
    BuildContext context,
    String sourceId,
    SourceHealthSummary? summary,
  ) => const Text('badge');
}

const _ranks = {'a': SourceHealthSummary(rank: 1, verdict: HealthVerdict.keep)};

void main() {
  test('listeners share one upstream subscription and get the latest', () {
    fakeAsync((async) {
      final up = _Upstream();
      final shared = SharedHealthLookup(up);
      expect(shared.latest, isNull);
      final first = <Map<String, SourceHealthSummary>>[];
      final sub = shared.watch().listen(first.add);
      up.controller.add(_ranks);
      async.flushMicrotasks();
      expect(first, [_ranks]);
      expect(shared.latest, _ranks);
      final second = <Map<String, SourceHealthSummary>>[];
      final sub2 = shared.watch().listen(second.add);
      async.flushMicrotasks();
      expect(second, [_ranks]);
      unawaited(sub.cancel());
      unawaited(sub2.cancel());
      // Back within the linger window: the same upstream subscription.
      async.elapse(const Duration(seconds: 30));
      final sub3 = shared.watch().listen((_) {});
      async.flushMicrotasks();
      expect(up.watches, 1);
      unawaited(sub3.cancel());
      // Gone longer than the linger: upstream is cancelled, then re-joined.
      async.elapse(const Duration(minutes: 2));
      expect(up.controller.hasListener, isFalse);
      final sub4 = shared.watch().listen((_) {});
      async.flushMicrotasks();
      expect(up.watches, 2);
      unawaited(sub4.cancel());
    });
  });

  test('errors are forwarded to every listener', () {
    fakeAsync((async) {
      final up = _Upstream();
      final shared = SharedHealthLookup(up);
      final errors = <Object>[];
      final sub = shared.watch().listen((_) {}, onError: errors.add);
      up.controller.addError(StateError('x'));
      async.flushMicrotasks();
      expect(errors, hasLength(1));
      unawaited(sub.cancel());
      async.elapse(const Duration(minutes: 2));
    });
  });

  testWidgets('buildBadge delegates to the upstream', (t) async {
    final shared = SharedHealthLookup(_Upstream());
    await t.pumpWidget(
      Builder(
        builder: (c) => Directionality(
          textDirection: TextDirection.ltr,
          child: shared.buildBadge(c, 'a', null)!,
        ),
      ),
    );
    expect(find.text('badge'), findsOneWidget);
  });
}
