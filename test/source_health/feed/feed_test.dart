import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/source_health/feed/fixture_feed.dart';
import 'package:kartka/source_health/feed/rtdb_feed.dart';
import 'package:kartka/source_health/feed/source_health_feed.dart';
import 'package:kartka/sync/rtdb_reader.dart';

import '../fixtures.dart';

void main() {
  group('parseHealthCollection', () {
    test('accepts a list, an RTDB map keyed by hash, or {sources: [...]}', () {
      final list = fixtureJson('records.json');
      final byHash = fixtureJson('rtdb_snapshot.json');
      expect(parseHealthCollection(list), hasLength(6));
      expect(parseHealthCollection(byHash), hasLength(6));
      expect(parseHealthCollection({'sources': list}), hasLength(6));
      expect(
        parseHealthCollection(byHash).toSet(),
        parseHealthCollection(list).toSet(),
      );
    });

    test('skips malformed entries and keeps the newest duplicate', () {
      final records = parseHealthCollection([
        {'id': 'a', 'rank': 1, 'probedAt': '2026-10-20T00:00:00Z'},
        {'id': 'a', 'rank': 2, 'probedAt': '2026-10-24T00:00:00Z'},
        {'id': 'a', 'rank': 3, 'probedAt': '2026-10-21T00:00:00Z'},
        {'id': 'b'},
        {'name': 'no id'},
        'junk',
        null,
      ]);
      expect(records.map((r) => (r.id, r.rank)), [('a', 2), ('b', null)]);
    });

    test('null, scalars and empty maps are an empty ranking', () {
      expect(parseHealthCollection(null), isEmpty);
      expect(parseHealthCollection(42), isEmpty);
      expect(parseHealthCollection(<String, Object?>{}), isEmpty);
    });
  });

  test('fixture feed emits the parsed fixture once', () async {
    final feed = FixtureSourceHealthFeed(fixtureJson('records.json'));
    expect(await feed.watch().toList(), [fixtureRecords()]);
  });

  group('RtdbSourceHealthFeed', () {
    test('reads /kartka/source_health and follows updates', () async {
      final reader = InMemoryRtdbReader({
        'source_health': fixtureJson('rtdb_snapshot.json'),
      });
      final SourceHealthFeed feed = RtdbSourceHealthFeed(reader);
      expect(RtdbSourceHealthFeed.path, 'source_health');
      final seen = <int>[];
      final sub = feed.watch().listen((rs) => seen.add(rs.length));
      await pumpEventQueue();
      reader.replace({
        'source_health': {
          'h1': {'id': 'mangadex', 'verdict': 'keep'},
        },
      });
      await pumpEventQueue();
      reader.replace(<String, Object?>{});
      await pumpEventQueue();
      // Not awaited: InMemoryRtdbReader.watch is an async* parked in
      // `await for`, so its cancel() only completes on the next change.
      unawaited(sub.cancel());
      expect(seen, [6, 1, 0]);
    });

    test('passes read errors through to the UI', () async {
      final feed = RtdbSourceHealthFeed(_FailingReader());
      await expectLater(feed.watch(), emitsError(isA<StateError>()));
    });
  });
}

class _FailingReader implements RtdbReader {
  @override
  Future<Object?> get(String path) => throw StateError('offline');

  @override
  Stream<Object?> watch(String path) => Stream.error(StateError('offline'));
}
