import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/diagnostics/diagnostics_log.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_engine.dart';
import 'package:kartka/sync/sync_shadow.dart';
import 'package:kartka/sync/sync_status.dart';

const _secretUrl =
    'https://kartka.firebaseio.com/users/u1/revs.json?auth=SECRET#tok=X';

/// A store whose next write throws [error], once: a repository bug, not a
/// sync or network failure.
class _ThrowingStore extends MemoryKeyValueStore {
  Object? error;

  @override
  Future<void> set(String key, String value) async {
    if (error case final e?) {
      error = null;
      Error.throwWithStackTrace(e, StackTrace.current);
    }
    await super.set(key, value);
  }
}

void main() {
  late InMemoryRtdb db;
  late MemoryBlobStore blobs;
  late _ThrowingStore store;
  late List<Object> throwOnOpen;

  setUp(() {
    db = InMemoryRtdb();
    blobs = MemoryBlobStore();
    store = _ThrowingStore();
    throwOnOpen = [];
  });

  Future<SyncEngine> engine() async => SyncEngine(
    shadow: await SyncShadow.load(store),
    deviceId: 'dev-a',
    open: () async {
      if (throwOnOpen.isNotEmpty) {
        Error.throwWithStackTrace(throwOnOpen.removeAt(0), StackTrace.current);
      }
      return db;
    },
    now: () => DateTime.utc(2026, 10, 25, 12),
    diagnostics: DiagnosticsLog(blobs),
  );

  void expectNoLeak(String text) {
    for (final leak in ['SECRET', 'auth=', 'tok=', 'http', '?', 'u1']) {
      expect(text, isNot(contains(leak)), reason: leak);
    }
  }

  for (final (name, error) in <(String, Object)>[
    ('StateError', StateError('store closed at $_secretUrl')),
    ('FormatException', const FormatException('bad json at $_secretUrl')),
  ]) {
    test('a $name mid-sync leaves "syncing"; the next sync runs', () async {
      final a = await engine();
      final phases = <SyncPhase>[];
      a.statusChanges.listen((s) => phases.add(s.phase));
      store.error = error;
      final failed = a.syncNow();
      // Queued behind the failing sync, before it settles.
      final next = a.poll();
      final errors = <SyncStatus>[];
      a.statusChanges
          .where((s) => s.phase == SyncPhase.error)
          .listen(errors.add);
      await expectLater(failed, throwsA(same(error)));
      await next.timeout(const Duration(seconds: 2));
      await pumpEventQueue(); // Broadcast status events arrive async.
      expect(phases, [
        SyncPhase.syncing,
        SyncPhase.error,
        SyncPhase.syncing,
        SyncPhase.idle,
      ]);
      expect(errors.single.message, contains(name));
      expectNoLeak(errors.single.message!);
      expect(a.status.phase, SyncPhase.idle);
      expect(a.status.lastSync, DateTime.utc(2026, 10, 25, 12));

      final entries = await DiagnosticsLog(blobs).entries();
      expect(entries.single.kind, 'sync.error');
      expect(entries.single.error, startsWith(name));
      expectNoLeak(
        utf8.decode(await blobs.get(DiagnosticsLog.defaultKey) ?? []),
      );
    });
  }

  test('a non-sync error opening the transport leaves "checking"', () async {
    final a = await engine();
    expect(a.status.phase, SyncPhase.syncing);
    throwOnOpen.add(StateError('no keystore at $_secretUrl'));
    await expectLater(a.poll(), throwsStateError);
    expect(a.status.phase, SyncPhase.error);
    expectNoLeak(a.status.message!);
    await a.poll();
    expect(a.status.phase, SyncPhase.idle);
  });
}
