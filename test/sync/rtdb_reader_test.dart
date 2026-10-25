import 'package:crdt_sync/crdt_sync.dart' show FirebaseSyncError;
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/sync/polling_rtdb_reader.dart';
import 'package:kartka/sync/rtdb_reader.dart';
import 'package:kartka/sync/rtdb_transport.dart';

const _cap = Duration(seconds: 2);

void main() {
  group('InMemoryRtdbReader', () {
    test('get walks the tree; missing paths are null', () async {
      final r = InMemoryRtdbReader({
        'source_health': {
          'h': {'score': 0.8},
        },
      });
      expect(await r.get('source_health/h/score'), 0.8);
      expect(await r.get('source_health/h/score/x'), isNull);
      expect(await r.get('nope'), isNull);
    });

    test('watch emits now and on change, never twice in a row', () async {
      final r = InMemoryRtdbReader({'a': 1});
      final seen = <Object?>[];
      final sub = r.watch('a').listen(seen.add);
      await pumpEventQueue();
      r
        ..replace({'a': 1})
        ..replace({'a': 2});
      await pumpEventQueue();
      expect(seen, [1, 2]);
      await sub.cancel().timeout(_cap);
    });

    test('first and cancel complete (regression: hung forever)', () async {
      final r = InMemoryRtdbReader({'a': 1});
      expect(await r.watch('a').first.timeout(_cap), 1);
      final sub = r.watch('a').listen((_) {});
      await pumpEventQueue();
      await sub.cancel().timeout(_cap);
    });
  });

  group('PollingRtdbReader', () {
    test('signed out reads null', () async {
      final r = PollingRtdbReader(() async => null);
      expect(await r.get('source_health'), isNull);
    });

    test('watch polls, dedupes, and cancel completes', () async {
      final db = InMemoryRtdb({'a': 1});
      final r = PollingRtdbReader(
        () async => db,
        interval: const Duration(milliseconds: 10),
      );
      expect(await r.watch('a').first.timeout(_cap), 1);
      final seen = <Object?>[];
      final sub = r.watch('a').listen(seen.add);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await db.patch({'a': 2});
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(seen, [1, 2]);
      await sub.cancel().timeout(_cap);
    });

    test('a failing poll surfaces an error and keeps polling', () async {
      final db = InMemoryRtdb({'a': 1})..failWith = FirebaseSyncError('x');
      final r = PollingRtdbReader(
        () async => db,
        interval: const Duration(milliseconds: 10),
      );
      final errors = <Object>[];
      final values = <Object?>[];
      final sub = r.watch('a').listen(values.add, onError: errors.add);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      db.failWith = null;
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(errors, isNotEmpty);
      expect(values, [1]);
      await sub.cancel().timeout(_cap);
    });

    test('an error does not stick: the same value re-emits after it', () async {
      final db = InMemoryRtdb({'a': 1});
      final r = PollingRtdbReader(
        () async => db,
        interval: const Duration(milliseconds: 10),
      );
      final events = <String>[];
      final sub = r
          .watch('a')
          .listen(
            (v) => events.add('data $v'),
            onError: (Object _) {
              if (events.last != 'error') events.add('error');
            },
          );
      await Future<void>.delayed(const Duration(milliseconds: 25));
      db.failWith = FirebaseSyncError('x');
      await Future<void>.delayed(const Duration(milliseconds: 25));
      db.failWith = null;
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(events, ['data 1', 'error', 'data 1']);
      await sub.cancel().timeout(_cap);
    });
  });
}
