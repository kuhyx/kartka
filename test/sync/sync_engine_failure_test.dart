import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart' show FirebaseSyncError;
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/diagnostics/diagnostics_log.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sync/merge/merge_rules.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_engine.dart';
import 'package:kartka/sync/sync_shadow.dart';
import 'package:kartka/sync/sync_status.dart';

const _secretUrl =
    'https://kartka.firebaseio.com/users/u1/revs.json?auth=SECRET#tok=X';

void main() {
  late InMemoryRtdb db;
  late MemoryBlobStore blobs;
  late List<Object> throwOnOpen;

  setUp(() {
    db = InMemoryRtdb();
    blobs = MemoryBlobStore();
    throwOnOpen = [];
  });

  Future<SyncEngine> engine() async => SyncEngine(
    shadow: await SyncShadow.load(MemoryKeyValueStore()),
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

  Node node(SyncEngine e) => {'title': 'One', 'hlc': e.tick().toStr()};

  Future<String> logFile() async =>
      utf8.decode(await blobs.get(DiagnosticsLog.defaultKey) ?? []);

  for (final (name, error) in [
    ('FormatException', const FormatException('bad json at $_secretUrl')),
    ('TypeError', TypeError()),
  ]) {
    test('a $name in one op reaches its caller; the next op still runs', () {
      return Future(() async {
        final a = await engine();
        throwOnOpen.add(error);
        await expectLater(a.syncNow(), throwsA(same(error)));
        await a
            .write('library/h1', node(a))
            .timeout(const Duration(seconds: 2));
        expect(
          (db.tree['library']! as Map)['h1'],
          containsPair('title', 'One'),
        );
        await a.poll().timeout(const Duration(seconds: 2));
        expect(a.status.phase, SyncPhase.idle);

        final entries = await DiagnosticsLog(blobs).entries();
        expect(entries.single.kind, 'sync.error');
        expect(entries.single.error, startsWith(name));
        expect(entries.single.error, isNot(contains('$name: $name')));
        final file = await logFile();
        for (final leak in ['SECRET', 'auth=', 'tok=', 'http', '?', 'u1']) {
          expect(file, isNot(contains(leak)), reason: leak);
        }
      });
    });
  }

  test('several queued ops after a failure all run, in order', () async {
    final a = await engine();
    throwOnOpen.add(const FormatException('x'));
    final failed = a.syncNow();
    final later = [
      a.write('library/h1', node(a)),
      a.write('library/h2', node(a)),
    ];
    await expectLater(failed, throwsFormatException);
    await Future.wait(later).timeout(const Duration(seconds: 2));
    expect((db.tree['library']! as Map).keys, containsAll(['h1', 'h2']));
  });

  test(
    'a RemoteSyncError is still a status, not a diagnostics entry',
    () async {
      final a = await engine();
      throwOnOpen.add(FirebaseSyncError('offline $_secretUrl'));
      await a.syncNow();
      expect(a.status.phase, SyncPhase.error);
      await a.syncNow();
      expect(a.status.phase, SyncPhase.idle);
      expect(await DiagnosticsLog(blobs).entries(), isEmpty);
    },
  );

  test('without a diagnostics log a failure still frees the queue', () async {
    var opens = 0;
    final a = SyncEngine(
      shadow: await SyncShadow.load(MemoryKeyValueStore()),
      deviceId: 'dev-a',
      open: () async => opens++ == 0 ? throw const FormatException('x') : null,
    );
    await expectLater(a.poll(), throwsFormatException);
    await a.poll().timeout(const Duration(seconds: 2));
    expect(a.status.phase, SyncPhase.signedOut);
  });
}
