import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/updates/chapter_update_checker.dart';
import 'package:kartka/library/ports.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/updates/state/update_runner.dart';

final _at = DateTime.utc(2026, 10, 29, 12);
ChapterInfo _ch(String url) => ChapterInfo(url: url, name: url);

void main() {
  final a = mangaKeyOf('mangadex', '/a');
  final b = mangaKeyOf('suwayomi:1', '/b?token=s3cret');
  final c = mangaKeyOf('local', '/c');

  test('summary text', () {
    expect(const UpdateSummary().message, 'No new chapters');
    expect(
      const UpdateSummary(newChapters: 1, manga: 1).message,
      '1 new chapter in 1 manga',
    );
    expect(
      const UpdateSummary(newChapters: 5, manga: 2, failed: 1).message,
      '5 new chapters in 2 manga · 1 failed',
    );
    expect(
      const UpdateSummary(failed: 3).message,
      'No new chapters · 3 failed',
    );
    expect(const UpdateProgress(12, 87).label, 'Checking 12/87');
    expect(const UpdateProgress(1, 2), const UpdateProgress(1, 2));
    expect(
      const UpdateProgress(1, 2).hashCode,
      const UpdateProgress(1, 2).hashCode,
    );
  });

  test('progress, summary and a redacted diagnostics entry', () async {
    final log = DiagnosticsLog(MemoryBlobStore());
    final gates = <MangaKey, Completer<UpdateResult>>{};
    final runner = UpdateRunner(
      libraryKeys: () async => [a, b, c],
      check: (key) => (gates[key] = Completer()).future,
      diagnostics: log,
      clock: () => _at,
    );
    final seen = <UpdateProgress?>[];
    runner.addListener(() => seen.add(runner.progress));
    expect(runner.progress, isNull);

    final run = runner.updateAll();
    // A second trigger joins the run in flight.
    expect(runner.updateAll(), same(run));
    await pumpEventQueue();
    expect(runner.progress, const UpdateProgress(0, 3));
    gates[a]!.complete(
      UpdateFound(
        a,
        chapters: const [],
        added: [_ch('1'), _ch('2')],
        firstCheck: false,
      ),
    );
    await pumpEventQueue();
    expect(runner.progress, const UpdateProgress(1, 3));
    gates[b]!.complete(
      UpdateFailed(b, StateError('GET https://x.test/b?token=s3cret failed')),
    );
    gates[c]!.complete(
      UpdateFound(c, chapters: const [], added: const [], firstCheck: true),
    );
    final summary = await run;
    expect(summary.message, '2 new chapters in 1 manga · 1 failed');
    expect(runner.progress, isNull);
    expect(seen.last, isNull);
    expect(seen, contains(const UpdateProgress(2, 3)));

    final entry = (await log.entries()).single;
    expect(entry.kind, 'updates.check');
    expect(entry.at, _at);
    expect(entry.sourceId, 'suwayomi:1');
    expect(entry.mangaUrl, isNull);
    expect(entry.error, isNot(contains('s3cret')));
    expect(entry.error, isNot(contains('x.test')));

    // After a run finishes, the next trigger starts a fresh one.
    gates.clear();
    final again = runner.updateAll();
    expect(again, isNot(same(run)));
    await pumpEventQueue();
    for (final g in gates.values) {
      g.complete(
        UpdateFound(a, chapters: const [], added: const [], firstCheck: false),
      );
    }
    expect((await again).message, 'No new chapters');
  });

  test('an empty library finishes without progress or logging', () async {
    final runner = UpdateRunner(
      libraryKeys: () async => const [],
      check: (_) => throw StateError('unused'),
    );
    expect((await runner.updateAll()).message, 'No new chapters');
    expect(runner.progress, isNull);
  });
}
