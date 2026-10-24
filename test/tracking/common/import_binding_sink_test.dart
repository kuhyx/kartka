import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/library/data/local_progress_repository.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/tracking/common/binding_store.dart';
import 'package:kartka/tracking/common/import_binding_sink.dart';
import 'package:kartka/tracking/common/track_binding.dart';
import 'package:kartka/tracking/common/tracking_service.dart';

import '../fakes.dart';
import 'service_fakes.dart';

const _k = 'mangadex|/manga/abc';

void main() {
  late KvBindingStore store;
  late LocalProgressRepository progress;
  late FakeTracker anilist;
  late TrackingService service;
  late ImportBindingSink sink;

  setUp(() {
    store = KvBindingStore(MemoryKeyValueStore());
    progress = LocalProgressRepository(MemoryKeyValueStore());
    anilist = FakeTracker();
    service = TrackingService(
      trackers: () => [anilist],
      bindings: store,
      progress: () => progress,
    );
    sink = ImportBindingSink(service);
  });

  tearDown(() => service.dispose());

  test('binds a new link with its imported remote count', () async {
    expect(
      await sink.bind(_k, 'anilist', '30104', lastPushedChapter: 12),
      isTrue,
    );
    expect(await store.all(), [
      const TrackBinding(
        key: _k,
        service: 'anilist',
        remoteId: '30104',
        lastPushedChapter: 12,
      ),
    ]);
  });

  test('zero imported chapters stores no count', () async {
    await sink.bind(_k, 'mal', '7');
    expect((await store.all()).single.lastPushedChapter, isNull);
  });

  test('is idempotent and never lowers the count', () async {
    await sink.bind(_k, 'anilist', '1', lastPushedChapter: 12);
    expect(await sink.bind(_k, 'anilist', '1', lastPushedChapter: 12), isFalse);
    expect(await sink.bind(_k, 'anilist', '1', lastPushedChapter: 3), isFalse);
    expect(await sink.bind(_k, 'anilist', '1', lastPushedChapter: 20), isTrue);
    expect((await store.all()).single.lastPushedChapter, 20);
  });

  test('an existing binding to another remote id wins', () async {
    await sink.bind(_k, 'anilist', '1');
    expect(await sink.bind(_k, 'anilist', '2', lastPushedChapter: 50), isFalse);
    expect((await store.all()).single.remoteId, '1');
  });

  test('imported bindings are followed for pushes right away', () async {
    await sink.bind(_k, 'anilist', '1', lastPushedChapter: 2);
    await finish(progress, _k, 4);
    await pumpEvents();
    expect(anilist.pushes, [('1', 4)]);
  });

  test('any tracker id is accepted, e.g. mangaupdates', () async {
    expect(await sink.bind(_k, 'mangaupdates', '55'), isTrue);
    expect((await store.all()).single.service, 'mangaupdates');
  });
}
