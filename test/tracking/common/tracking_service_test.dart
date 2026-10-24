import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/library/data/local_progress_repository.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/tracking/common/binding_store.dart';
import 'package:kartka/tracking/common/track_binding.dart';
import 'package:kartka/tracking/common/tracking_service.dart';

import '../fakes.dart';
import 'service_fakes.dart';

const _k = 'mangadex|/manga/abc';

void main() {
  late FakeTracker anilist;
  late LocalProgressRepository progress;
  late FakeResolver resolver;
  late KvBindingStore bindings;
  late List<Object> errors;
  late TrackingService service;

  TrackingService build({bool withResolver = true}) => TrackingService(
    trackers: () => [anilist],
    bindings: bindings,
    progress: () => progress,
    resolver: withResolver ? () => resolver : null,
    now: () => DateTime.utc(2026, 10, 24),
    onError: errors.add,
  );

  setUp(() {
    anilist = FakeTracker();
    progress = LocalProgressRepository(MemoryKeyValueStore());
    resolver = FakeResolver();
    bindings = KvBindingStore(MemoryKeyValueStore());
    errors = [];
    service = build();
  });

  tearDown(() => service.dispose());

  Future<TrackBinding> binding() async => (await bindings.all()).single;

  test('bind pushes current local progress up', () async {
    await progress.record(progressAt(_k, 5));
    await service.bind(_k, 'anilist', '30104');
    await pumpEvents();
    expect(anilist.remote['30104'], 5);
    expect((await binding()).lastPushedChapter, 5);
  });

  test('reading forward pushes the floored chapter once', () async {
    await service.bind(_k, 'anilist', '1');
    await progress.record(progressAt(_k, 3.5));
    await pumpEvents();
    await progress.record(progressAt(_k, 3.5, page: 9));
    await pumpEvents();
    expect(anilist.pushes, [('1', 3)]);
    expect(anilist.remote['1'], 3);
  });

  test('never lowers the remote count', () async {
    anilist.remote['1'] = 40;
    await service.bind(_k, 'anilist', '1');
    await progress.record(progressAt(_k, 41));
    await pumpEvents();
    expect(anilist.remote['1'], 41);
    // The fake applies max() like real trackers; check no push went below.
    expect(anilist.pushes.every((p) => p.$2 >= 40), isTrue);
  });

  test('bursts coalesce to the newest chapter', () async {
    await service.bind(_k, 'anilist', '1');
    anilist.gate = Completer();
    await progress.record(progressAt(_k, 1));
    await pumpEvents();
    for (var c = 2.0; c <= 6; c++) {
      await progress.record(progressAt(_k, c));
      await pumpEvents();
    }
    anilist.gate!.complete();
    await pumpEvents();
    await pumpEvents();
    expect(anilist.pushes, [('1', 1), ('1', 6)]);
  });

  test('refresh pulls a higher remote count forward', () async {
    await progress.record(progressAt(_k, 2));
    anilist.remote['1'] = 7;
    await service.bind(_k, 'anilist', '1');
    final p = (await progress.watch(_k).first)!;
    expect(p.chapterNumber, 7);
    expect(p.chapterUrl, '/chapter/7');
    expect(await progress.readChapters(_k).first, {'/chapter/7'});
    expect((await binding()).lastPushedChapter, 7);
    await pumpEvents();
    expect(anilist.pushes, isEmpty);
  });

  test('pull is skipped when the chapter url is unknown', () async {
    resolver.known = false;
    await progress.record(progressAt(_k, 2));
    anilist.remote['1'] = 7;
    await service.bind(_k, 'anilist', '1');
    expect((await progress.watch(_k).first)!.chapterNumber, 2);
  });

  test('pull is skipped without a resolver', () async {
    await service.dispose();
    service = build(withResolver: false);
    anilist.remote['1'] = 7;
    await service.bind(_k, 'anilist', '1');
    expect(await progress.watch(_k).first, isNull);
  });

  test('logged-out trackers are left alone', () async {
    anilist.loggedIn = false;
    anilist.remote['1'] = 7;
    await progress.record(progressAt(_k, 9));
    await service.bind(_k, 'anilist', '1');
    await pumpEvents();
    expect(anilist.pushes, isEmpty);
    expect(anilist.fetches, 0);
    expect((await progress.watch(_k).first)!.chapterNumber, 9);
  });

  test('a binding to an unknown tracker is ignored', () async {
    await service.bind(_k, 'mal', '1');
    await progress.record(progressAt(_k, 3));
    await pumpEvents();
    expect(anilist.pushes, isEmpty);
    expect(errors, isEmpty);
  });

  test('push errors go to onError and later pushes still run', () async {
    await service.bind(_k, 'anilist', '1');
    anilist.pushError = Exception('offline');
    await progress.record(progressAt(_k, 2));
    await pumpEvents();
    expect(errors, hasLength(1));
    anilist.pushError = null;
    await progress.record(progressAt(_k, 3));
    await pumpEvents();
    expect(anilist.remote['1'], 3);
  });

  test('unbind stops pushing', () async {
    await service.bind(_k, 'anilist', '1');
    await service.unbind(_k, 'anilist');
    await progress.record(progressAt(_k, 4));
    await pumpEvents();
    expect(anilist.pushes, isEmpty);
    expect(await bindings.all(), isEmpty);
  });

  test('start resumes listening for stored bindings', () async {
    await bindings.put(
      const TrackBinding(key: _k, service: 'anilist', remoteId: '1'),
    );
    await service.start();
    await service.start();
    await progress.record(progressAt(_k, 2));
    await pumpEvents();
    expect(anilist.pushes, [('1', 2)]);
  });

  test('refresh with no bindings does nothing', () async {
    await service.refresh(_k);
    expect(anilist.fetches, 0);
  });

  test('exposes trackers and bindings', () async {
    expect(service.tracker('anilist'), anilist);
    expect(service.tracker('mal'), isNull);
    expect(service.trackers, [anilist]);
    await service.bind(_k, 'anilist', '1');
    expect((await service.watchBindings(_k).first).single.remoteId, '1');
  });

  test('refresh errors go to onError', () async {
    await service.bind(_k, 'anilist', '1');
    anilist.loggedIn = true;
    final failing = FakeTracker()..pushError = Exception('x');
    await service.dispose();
    service = TrackingService(
      trackers: () => [failing],
      bindings: bindings,
      progress: () => throw StateError('no repo'),
      onError: errors.add,
    );
    await service.refresh(_k);
    expect(errors.single, isA<StateError>());
  });

  test('defaults: errors are dropped, real clock is used', () async {
    await service.dispose();
    service = TrackingService(
      trackers: () => [anilist],
      bindings: bindings,
      progress: () => progress,
      resolver: () => resolver,
    );
    anilist.remote['1'] = 2;
    await service.bind(_k, 'anilist', '1');
    final p = (await progress.watch(_k).first)!;
    expect(p.readAt.year, greaterThanOrEqualTo(2026));
    anilist.pushError = Exception('dropped');
    await progress.record(progressAt(_k, 5));
    await pumpEvents();
  });

  test('a repository that fails to watch reports through onError', () async {
    await bindings.put(
      const TrackBinding(key: _k, service: 'anilist', remoteId: '1'),
    );
    await service.dispose();
    service = TrackingService(
      trackers: () => [anilist],
      bindings: bindings,
      progress: () => throw StateError('no repo'),
      onError: errors.add,
    );
    await service.start();
    expect(errors.single, isA<StateError>());
  });
}
