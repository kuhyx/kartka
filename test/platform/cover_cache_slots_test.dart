import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/cover_cache.dart';

Uint8List _png(String tag) =>
    Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, ...utf8.encode(tag)]);

/// A grid of uncached covers sent all at once filled the source's rate
/// limiter on the server, and the next browse page queued behind them for
/// up to 41 s (89e1ec6e). Network loads now run [CoverCache.maxLoads] per
/// host at a time, newest first (the covers just scrolled to).
void main() {
  test(
    'at most maxLoads per host; the newest waiting cover goes next',
    () async {
      final started = <String>[];
      final gates = <String, Completer<Uint8List>>{};
      final cache = CoverCache(
        load: (url) {
          started.add(url);
          return (gates[url] = Completer<Uint8List>()).future;
        },
      );
      final done = [
        for (var i = 0; i < 5; i++) cache.get('https://a.test/$i.jpg'),
      ];
      final failed = expectLater(done[1], throwsStateError);
    final other = cache.get('https://b.test/x.jpg');
      await pumpEventQueue();
      expect(started, [
        'https://a.test/0.jpg',
        'https://a.test/1.jpg',
        'https://b.test/x.jpg',
      ]);
      gates['https://a.test/0.jpg']!.complete(_png('0'));
      await pumpEventQueue();
      expect(started.last, 'https://a.test/4.jpg', reason: 'newest first');
      gates['https://a.test/1.jpg']!.completeError(StateError('404'));
      await pumpEventQueue();
      expect(
        started.last,
        'https://a.test/3.jpg',
        reason: 'a failure frees too',
      );
      for (final u in ['4', '3']) {
        gates['https://a.test/$u.jpg']!.complete(_png(u));
      }
      await pumpEventQueue();
      gates['https://a.test/2.jpg']!.complete(_png('2'));
      gates['https://b.test/x.jpg']!.complete(_png('x'));
      expect(await done.first, _png('0'));
      await failed;
      expect(
        await Future.wait([done[2], done[3], done[4], other]),
        hasLength(4),
      );
    },
  );

  test('a cached cover never waits for a slot', () async {
    final gate = Completer<Uint8List>();
    final cache = CoverCache(load: (_) => gate.future, maxLoads: 1);
    unawaited(cache.get('https://a.test/slow.jpg'));
    gate.complete(_png('s'));
    await pumpEventQueue();
    expect(cache.peek('https://a.test/slow.jpg'), isNotNull);
  });
}
