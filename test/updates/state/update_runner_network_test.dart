import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/updates/chapter_update_checker.dart';
import 'package:kartka/library/ports.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/updates/state/network_errors.dart';
import 'package:kartka/updates/state/update_runner.dart';

const _lookup =
    'ClientException with SocketException: Failed host lookup: '
    "'suwayomi.kuhy.duckdns.org' (OS Error: No address associated with "
    'hostname, errno = 7), uri=https://suwayomi.kuhy.duckdns.org/api/graphql';

const _upstreamTimeout =
    'SuwayomiException: Exception while fetching data (/fetchSourceManga) '
    ': timeout';

UpdateResult _found(MangaKey key) =>
    UpdateFound(key, chapters: const [], added: const [], firstCheck: false);

void main() {
  test('transient and offline errors are told apart from source errors', () {
    expect(isTransientNetworkError(TimeoutException('slow')), isTrue);
    expect(isTransientNetworkError(Exception(_lookup)), isTrue);
    for (final text in [
      'ClientException: Software caused connection abort, uri=x',
      'ClientException: Connection reset by peer',
      'ClientException: Connection closed before full header was received',
      _upstreamTimeout,
    ]) {
      expect(isTransientNetworkError(Exception(text)), isTrue, reason: text);
      expect(isOfflineError(Exception(text)), isFalse, reason: text);
    }
    expect(isOfflineError(Exception(_lookup)), isTrue);
    expect(isOfflineError(Exception('Network is unreachable')), isTrue);
    expect(isTransientNetworkError(StateError('Unknown source x')), isFalse);
    expect(isOfflineError(StateError('Unknown source x')), isFalse);
  });

  test('a transient failure is retried with backoff, then works', () async {
    final key = mangaKeyOf('suwayomi:1', '/a');
    final waits = <Duration>[];
    var calls = 0;
    final runner = UpdateRunner(
      libraryKeys: () async => [key],
      check: (k) async => ++calls < 3
          ? UpdateFailed(k, Exception('ClientException: Connection reset'))
          : _found(k),
      delay: (d) async => waits.add(d),
    );
    final summary = await runner.updateAll();
    expect(calls, 3);
    expect(waits, const [Duration(seconds: 1), Duration(seconds: 2)]);
    expect(summary.failed, 0);
  });

  test('the default backoff really waits', () async {
    final key = mangaKeyOf('mangadex', '/a');
    var calls = 0;
    final runner = UpdateRunner(
      libraryKeys: () async => [key],
      check: (k) async => ++calls < 2
          ? UpdateFailed(k, TimeoutException('slow'))
          : _found(k),
      backoff: Duration.zero,
    );
    expect((await runner.updateAll()).failed, 0);
    expect(calls, 2);
  });

  test('a source error is not retried and is logged when it happens', () async {
    final log = DiagnosticsLog(MemoryBlobStore());
    // One source: checked one after the other.
    final first = mangaKeyOf('sy-builtin:6901', '/a');
    final second = mangaKeyOf('sy-builtin:6901', '/b');
    var now = DateTime.utc(2026, 10, 29, 9);
    var calls = 0;
    final runner = UpdateRunner(
      libraryKeys: () async => [first, second],
      check: (k) async {
        calls++;
        now = now.add(const Duration(minutes: 1));
        return UpdateFailed(k, StateError('Unknown source $k'));
      },
      diagnostics: log,
      clock: () => now,
      delay: (_) => fail('no retry for a source error'),
    );
    final summary = await runner.updateAll();
    expect(calls, 2);
    expect(summary.failed, 2);
    final entries = await log.entries();
    expect(entries.map((e) => e.kind), everyElement('updates.check'));
    // Each failure carries the time it happened, not the end of the run.
    expect(entries.map((e) => e.at).toSet(), hasLength(2));
  });

  test('a server that cannot be resolved stops its checks once', () async {
    final log = DiagnosticsLog(MemoryBlobStore());
    final suwayomi = [
      for (var i = 1; i <= 6; i++) mangaKeyOf('suwayomi:$i', '/m$i'),
    ];
    final dex = mangaKeyOf('mangadex', '/d');
    final tried = <MangaKey>{};
    var calls = 0;
    final runner = UpdateRunner(
      libraryKeys: () async => [...suwayomi, dex],
      check: (k) async {
        if (k == dex) return _found(k);
        tried.add(k);
        calls++;
        return UpdateFailed(k, Exception(_lookup));
      },
      diagnostics: log,
      delay: (_) async {},
    );
    final summary = await runner.updateAll();
    // Only the two in flight (2 per server) were tried, 3 times each.
    expect(tried, hasLength(2));
    expect(calls, 6);
    expect(summary.failed, 0);
    expect(summary.notChecked, 6);
    expect(summary.message, 'No new chapters · offline: 6 not checked');
    final entry = (await log.entries()).single;
    expect(entry.kind, 'updates.offline');
    expect(entry.sourceId, 'suwayomi');
    expect(entry.error, contains('Failed host lookup'));
    expect(entry.error, contains('6 not checked'));
  });

  test('summary text with failures and an offline server', () {
    expect(
      const UpdateSummary(
        newChapters: 2,
        manga: 1,
        failed: 3,
        notChecked: 4,
      ).message,
      '2 new chapters in 1 manga · 3 failed · offline: 4 not checked',
    );
  });
}
