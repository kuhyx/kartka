import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/ui/precache_queue.dart';

void main() {
  const settle = Duration(milliseconds: 100);
  final bytes = [
    for (var i = 0; i < 4; i++) Uint8List.fromList([i]),
  ];
  final decoded = <int>[];
  var inFlight = 0;
  var maxInFlight = 0;
  Completer<void>? gate;

  Future<void> decode(ImageProvider p) async {
    final b = ((p as ResizeImage).imageProvider as MemoryImage).bytes;
    decoded.add(bytes.indexWhere((x) => identical(x, b)));
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    await gate?.future;
    inFlight--;
  }

  PrecacheQueue make() => PrecacheQueue(decode: decode, settle: settle);

  setUp(() {
    decoded.clear();
    inFlight = 0;
    maxInFlight = 0;
    gate = null;
  });

  test('nothing decodes until the page has settled', () {
    fakeAsync((async) {
      make().schedule([Future.value(bytes[1])], 100);
      async.elapse(settle - const Duration(milliseconds: 1));
      expect(decoded, isEmpty);
      async
        ..elapse(const Duration(milliseconds: 1))
        ..flushMicrotasks();
      expect(decoded, [1]);
    });
  });

  test('pages decode one after another, never two at once', () {
    fakeAsync((async) {
      gate = Completer<void>();
      make().schedule([
        for (var i = 0; i < 3; i++) Future.value(bytes[i]),
      ], 100);
      async
        ..elapse(settle)
        ..flushMicrotasks();
      expect(decoded, [0]);
      gate!.complete();
      async.flushMicrotasks();
      expect(decoded, [0, 1, 2]);
      expect(maxInFlight, 1);
    });
  });

  test('a newer schedule drops what the older one still had queued', () {
    fakeAsync((async) {
      gate = Completer<void>();
      final q = make()
        ..schedule([for (var i = 0; i < 3; i++) Future.value(bytes[i])], 100);
      async
        ..elapse(settle)
        ..flushMicrotasks();
      expect(decoded, [0]);
      q.schedule([Future.value(bytes[3])], 100);
      gate!.complete();
      async.flushMicrotasks();
      expect(decoded, [0], reason: 'pages 1 and 2 are stale');
      async
        ..elapse(settle)
        ..flushMicrotasks();
      expect(decoded, [0, 3]);
      expect(maxInFlight, 1);
    });
  });

  test('rescheduling inside the settle window restarts it', () {
    fakeAsync((async) {
      final q = make()..schedule([Future.value(bytes[0])], 100);
      async.elapse(settle * 0.8);
      q.schedule([Future.value(bytes[1])], 100);
      async
        ..elapse(settle * 0.8)
        ..flushMicrotasks();
      expect(decoded, isEmpty);
      async
        ..elapse(settle)
        ..flushMicrotasks();
      expect(decoded, [1]);
    });
  });

  test('cancel drops everything queued', () {
    fakeAsync((async) {
      final q = make()
        ..schedule([Future.value(bytes[0])], 100)
        ..cancel();
      async
        ..elapse(settle * 2)
        ..flushMicrotasks();
      expect(decoded, isEmpty);
      expect(q.isIdle, isTrue);
    });
  });

  test('a page already decoded at this width is not decoded again', () {
    fakeAsync((async) {
      final q = make()..schedule([Future.value(bytes[0])], 100);
      async
        ..elapse(settle)
        ..flushMicrotasks();
      q.schedule([Future.value(bytes[0]), Future.value(bytes[1])], 100);
      async
        ..elapse(settle)
        ..flushMicrotasks();
      expect(decoded, [0, 1]);
      q.schedule([Future.value(bytes[0])], 200);
      async
        ..elapse(settle)
        ..flushMicrotasks();
      expect(decoded, [0, 1, 0], reason: 'another width is another image');
    });
  });

  test('a page that failed to load is skipped, the rest still decode', () {
    fakeAsync((async) {
      make().schedule([
        Future<Uint8List>.error(StateError('offline')),
        Future.value(bytes[2]),
      ], 100);
      async
        ..elapse(settle)
        ..flushMicrotasks();
      expect(decoded, [2]);
    });
  });

  test('a decode that throws does not stop the queue', () {
    fakeAsync((async) {
      var first = true;
      PrecacheQueue(
        settle: settle,
        decode: (p) async {
          if (first) {
            first = false;
            throw StateError('boom');
          }
          await decode(p);
        },
      ).schedule([Future.value(bytes[0]), Future.value(bytes[1])], 100);
      async
        ..elapse(settle)
        ..flushMicrotasks();
      expect(decoded, [1]);
    });
  });

  test('the memory of decoded pages stays bounded', () {
    fakeAsync((async) {
      final many = [
        for (var i = 0; i < 40; i++) Uint8List.fromList([9, i]),
      ];
      final seen = <Uint8List>[];
      final q = PrecacheQueue(
        settle: settle,
        decode: (p) async =>
            seen.add(((p as ResizeImage).imageProvider as MemoryImage).bytes),
      )..schedule([for (final b in many) Future.value(b)], 100);
      async
        ..elapse(settle)
        ..flushMicrotasks();
      expect(seen, hasLength(40));
      // The first pages fell out of the memory: they decode again.
      q.schedule([Future.value(many.first)], 100);
      async
        ..elapse(settle)
        ..flushMicrotasks();
      expect(seen, hasLength(41));
    });
  });
}
