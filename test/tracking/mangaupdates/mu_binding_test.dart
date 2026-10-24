// End to end with tracking/common: a MangaUpdates link from an SY backup is
// accepted by the import sink, and later local progress reaches the API.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/library/data/local_progress_repository.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/tracking/common/binding_store.dart';
import 'package:kartka/tracking/common/import_binding_sink.dart';
import 'package:kartka/tracking/common/tracking_service.dart';
import 'package:kartka/tracking/mangaupdates/mu_tracker.dart';

import '../common/service_fakes.dart';
import 'mu_fakes.dart';

const _key = 'mangadex|/manga/abc';

// Series id and count from kuhy's 2026-10-24 backup (field 100 = mediaId).
const _remote = '57847596550';

void main() {
  test('backup binding is accepted, then progress is pushed up', () async {
    final http = FakeKartkaHttp(
      (r) => r.method == 'GET'
          ? FakeKartkaHttp.text(
              jsonEncode({
                'series': {'id': int.parse(_remote)},
                'list_id': 0,
                'status': {'chapter': 32},
              }),
            )
          : fx('list_update_ok.json'),
    );
    final s = buildStack(http, FakeClock());
    await s.store.write(testSession);
    final tracker = MangaUpdatesTracker(api: s.api, store: s.store);
    final progress = LocalProgressRepository(MemoryKeyValueStore());
    final service = TrackingService(
      trackers: () => [tracker],
      bindings: KvBindingStore(MemoryKeyValueStore()),
      progress: () => progress,
    );
    addTearDown(service.dispose);

    final sink = ImportBindingSink(service);
    expect(
      await sink.bind(_key, 'mangaupdates', _remote, lastPushedChapter: 32),
      isTrue,
    );
    expect(service.tracker('mangaupdates'), same(tracker));

    // Only finished chapters count (tracking/common FinishedChapters).
    await finish(progress, _key, 40);
    await pumpEventQueue();
    final calls = [for (final r in http.requests) '${r.method} ${r.url.path}'];
    expect(calls, [
      'GET /v1/lists/series/$_remote',
      'POST /v1/lists/series/update',
    ]);
    final body = jsonDecode(http.requests.last.body!) as List<Object?>;
    expect(body.single, containsPair('status', {'chapter': 40}));
  });
}
