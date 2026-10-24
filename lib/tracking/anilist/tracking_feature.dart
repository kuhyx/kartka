import 'dart:async';
import 'dart:developer' as developer;

import 'package:kartka/app/feature.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/tracking/anilist/anilist_api.dart';
import 'package:kartka/tracking/anilist/anilist_auth.dart';
import 'package:kartka/tracking/anilist/anilist_tracker.dart';
import 'package:kartka/tracking/common/binding_store.dart';
import 'package:kartka/tracking/common/chapter_url_resolver.dart';
import 'package:kartka/tracking/common/import_binding_sink.dart';
import 'package:kartka/tracking/common/tracked_lookup.dart';
import 'package:kartka/tracking/common/tracker.dart';
import 'package:kartka/tracking/common/tracking_service.dart';
import 'package:kartka/tracking/common/tracking_slot.dart';

/// The tracking part: the AniList [Tracker], the shared [TrackingService]
/// (which drives every registered tracker, MAL and others included), and
/// the ports library, browse and backup-import consume.
KartkaFeature trackingFeature(KartkaEnv env) {
  final platform = env.platform;
  final anilist = AniListTracker(
    api: AniListApi(platform.http),
    auth: AniListAuth(
      secrets: platform.secrets,
      oauth: platform.oauth,
      clientIds: const AniListClientIds.fromEnvironment(),
    ),
  );
  final store = LazyBindingStore(
    KvBindingStore(platform.kv),
    () => env.registry.all<BindingStoreDecorator>(),
  );
  final service = TrackingService(
    trackers: () => env.registry.all<Tracker>(),
    bindings: store,
    progress: () =>
        env.registry.maybe<LibraryRepositories>()?.progress ??
        (throw StateError('tracking needs the library part')),
    resolver: () => env.registry.maybe<ChapterUrlResolver>(),
    onError: (e) => developer.log('$e', name: 'kartka.tracking'),
  );
  // The registry is complete once every factory ran; start right after.
  scheduleMicrotask(() => unawaited(service.start()));
  return KartkaFeature(
    id: 'tracking',
    services: [
      anilist,
      service,
      BindingTrackedLookup(store),
      TrackingDetailSlot(service),
      ImportBindingSink(service),
    ],
  );
}
