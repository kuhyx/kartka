import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/backup_import/tracker_binding_sink.dart';
import 'package:kartka/browse/manga_detail_slot.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/library/ports.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/tracking/anilist/anilist_tracker.dart';
import 'package:kartka/tracking/anilist/tracking_feature.dart';
import 'package:kartka/tracking/common/tracker.dart';
import 'package:kartka/tracking/common/tracking_service.dart';
import 'package:kartka/tracking/common/ui/track_button.dart';

import '../common/service_fakes.dart';
import '../fakes.dart';

const _k = 'mangadex|/manga/abc';

KartkaRegistry _registry({
  bool withLibrary = true,
  List<Object> extra = const [],
}) {
  final kv = MemoryKeyValueStore();
  return KartkaRegistry.build(memoryPlatform(kv: kv), [
    if (withLibrary)
      (_) => KartkaFeature(
        id: 'library',
        services: [LibraryRepositories(kv, decorators: () => const [])],
      ),
    trackingFeature,
    (_) => KartkaFeature(id: 'extra', services: extra),
  ]);
}

void main() {
  test('publishes tracker, service and every port', () async {
    final r = _registry();
    await pumpEvents();
    expect(r.all<Tracker>().single, isA<AniListTracker>());
    expect(r.maybe<TrackingService>(), isNotNull);
    expect(r.maybe<TrackedLookup>(), isNotNull);
    expect(r.maybe<MangaDetailSlot>(), isNotNull);
    expect(r.maybe<TrackerBindingSink>(), isNotNull);
    expect(r.maybe<TrackingService>()!.trackers, r.all<Tracker>());
  });

  test('imported bindings show up in the tracked lookup', () async {
    final r = _registry();
    await pumpEvents();
    final seen = <bool>[];
    final sub = r.maybe<TrackedLookup>()!.isTracked(_k).listen(seen.add);
    await pumpEvents();
    await r.maybe<TrackerBindingSink>()!.bind(_k, 'anilist', '1');
    await pumpEvents();
    await sub.cancel();
    expect(seen, [false, true]);
  });

  test('without the library part, progress errors are logged', () async {
    final r = _registry(withLibrary: false);
    await r.maybe<TrackerBindingSink>()!.bind(_k, 'anilist', '1');
    await r.maybe<TrackingService>()!.refresh(_k);
    await pumpEvents();
  });

  test(
    'other trackers and the chapter resolver come from the registry',
    () async {
      final fake = FakeTracker(id: 'mangaupdates')..remote['1'] = 3;
      final r = _registry(extra: [fake, FakeResolver()]);
      await r.maybe<TrackerBindingSink>()!.bind(_k, 'mangaupdates', '1');
      await r.maybe<TrackingService>()!.refresh(_k);
      final progress = r.maybe<LibraryRepositories>()!.progress;
      expect((await progress.watch(_k).first)!.chapterNumber, 3);
    },
  );

  test(
    'opening the detail screen pulls remote progress via the slot',
    () async {
      final fake = FakeTracker(id: 'mangaupdates')..remote['1'] = 4;
      final r = _registry(extra: [fake, FakeResolver()]);
      await r.maybe<TrackerBindingSink>()!.bind(_k, 'mangaupdates', '1');
      r.maybe<MangaDetailSlot>()!.opened(_k);
      await pumpEvents();
      final progress = r.maybe<LibraryRepositories>()!.progress;
      expect((await progress.watch(_k).first)!.chapterNumber, 4);
    },
  );

  testWidgets('the detail slot renders the track button', (tester) async {
    final slot = _registry().maybe<MangaDetailSlot>()!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => slot.build(
              context,
              _k,
              const MangaDetails(
                sourceId: 'mangadex',
                url: '/manga/abc',
                title: 'Yotsuba',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TrackButton), findsOneWidget);
    expect(find.bySemanticsLabel('Track'), findsOneWidget);
  });
}
