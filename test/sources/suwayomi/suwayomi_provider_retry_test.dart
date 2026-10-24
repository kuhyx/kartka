import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/sources/suwayomi/suwayomi_client.dart';
import 'package:kartka/sources/suwayomi/suwayomi_settings.dart';
import 'package:kartka/sources/suwayomi/suwayomi_source_provider.dart';

import 'fakes.dart';

/// Answers 502 to the first [failures] requests, then the recorded sources.
FakeKartkaHttp flakyHttp(int failures) {
  final ok = fixture('sources');
  var calls = 0;
  return FakeKartkaHttp((_) {
    if (calls++ < failures) return FakeKartkaHttp.text('', status: 502);
    final response = ok['response'];
    return FakeKartkaHttp.text(
      response is String ? response : jsonEncode(response),
      status: ok['status']! as int,
    );
  });
}

/// A Keystore whose reads hang until [gate] completes, then fail.
class _GatedSecrets extends MemoryKeyValueStore {
  final gate = Completer<void>();

  @override
  Future<String?> get(String key) async {
    await gate.future;
    throw StateError('keystore');
  }
}

/// A failed fetch must not be cached as "no Suwayomi sources": the provider
/// retries by itself with backoff and the next watcher fetches again.
void main() {
  late SuwayomiSettingsStore store;
  setUp(
    () => store = SuwayomiSettingsStore(
      kv: MemoryKeyValueStore(),
      secrets: MemoryKeyValueStore(),
    ),
  );

  SuwayomiSourceProvider provider(FakeKartkaHttp http) =>
      SuwayomiSourceProvider(
        store: store,
        client: SuwayomiClient(
          http: http,
          settings: () => store.current ?? const SuwayomiSettings(),
        ),
      );

  test('is a RefreshableSourceProvider', () {
    expect(provider(flakyHttp(0)), isA<RefreshableSourceProvider>());
  });

  test('the next watcher re-fetches after a failed fetch', () async {
    await store.save(fixtureSettings);
    final p = provider(flakyHttp(1));
    addTearDown(p.dispose);
    expect(await p.watch().first, isEmpty);
    expect((await p.watch().first).length, 2);
  });

  test('retries a failed fetch by itself and re-emits', () {
    fakeAsync((async) {
      final http = flakyHttp(1);
      final p = provider(http);
      final emitted = <int>[];
      unawaited(store.save(fixtureSettings));
      async.flushMicrotasks();
      final sub = p.watch().listen((s) => emitted.add(s.length));
      async.flushMicrotasks();
      expect(emitted, [0]);
      async.elapse(const Duration(milliseconds: 1999));
      expect(emitted, [0]);
      async.elapse(const Duration(milliseconds: 1));
      expect(emitted, [0, 2]);
      async.elapse(const Duration(minutes: 10));
      expect(http.requests, hasLength(2), reason: 'stops once it succeeds');
      unawaited(sub.cancel());
      unawaited(p.dispose());
      async.flushMicrotasks();
    });
  });

  test('backs off 2, 4, 8 ... capped at 60 s, until disposed', () {
    fakeAsync((async) {
      final http = flakyHttp(1 << 30);
      final p = provider(http);
      unawaited(store.save(fixtureSettings));
      async.flushMicrotasks();
      final sub = p.watch().listen((_) {});
      async.flushMicrotasks();
      final counts = <int>[http.requests.length];
      // Retries land at t = 2, 6, 14, 30, 62, 122, 182 s.
      for (final t in [2, 6, 14, 30, 62, 122, 182]) {
        async.elapse(Duration(seconds: t) - async.elapsed);
        counts.add(http.requests.length);
      }
      expect(counts, [1, 2, 3, 4, 5, 6, 7, 8]);
      async.elapse(const Duration(seconds: 59));
      expect(http.requests, hasLength(8));
      unawaited(sub.cancel());
      unawaited(p.dispose());
      async.elapse(const Duration(minutes: 10));
      expect(http.requests, hasLength(8), reason: 'disposed');
    });
  });

  test('a save resets the backoff to the fast cadence', () {
    fakeAsync((async) {
      final http = flakyHttp(1 << 30);
      final p = provider(http);
      unawaited(store.save(fixtureSettings));
      async.flushMicrotasks();
      final sub = p.watch().listen((_) {});
      async.elapse(const Duration(seconds: 14)); // 4 requests, next in 16 s
      unawaited(store.save(fixtureSettings)); // request 5, next in 2 s
      async.elapse(const Duration(seconds: 2));
      expect(http.requests, hasLength(6));
      unawaited(sub.cancel());
      unawaited(p.dispose());
      async.flushMicrotasks();
    });
  });

  test('a fetch that fails after dispose schedules nothing', () {
    fakeAsync((async) {
      final secrets = _GatedSecrets();
      final p = SuwayomiSourceProvider(
        store: SuwayomiSettingsStore(
          kv: MemoryKeyValueStore(),
          secrets: secrets,
        ),
        client: SuwayomiClient(
          http: flakyHttp(0),
          settings: () => const SuwayomiSettings(),
        ),
      );
      Object? error;
      var done = false;
      unawaited(
        p.refresh().then<void>(
          (_) => done = true,
          onError: (Object e) => error = e,
        ),
      );
      async.flushMicrotasks();
      unawaited(p.dispose());
      async.flushMicrotasks();
      secrets.gate.complete();
      async.flushMicrotasks();
      expect(done, isTrue);
      expect(error, isNull);
      expect(async.pendingTimers, isEmpty);
    });
  });
}
