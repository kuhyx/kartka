// Runs against kuhy's personal backup when it exists on this machine; skipped
// everywhere else. The backup is never committed.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/backup_import/backup_planner.dart';
import 'package:kartka/backup_import/source_mapper.dart';
import 'package:kartka/backup_import/tachibk_decoder.dart';

import 'fake_setup.dart';

File? _backup() {
  final home = Platform.environment['HOME'];
  if (home == null) return null;
  final dir = Directory('$home/data/kartka/backup');
  if (!dir.existsSync()) return null;
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.tachibk'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return files.isEmpty ? null : files.last;
}

void main() {
  final file = _backup();
  final skip = file == null ? 'no backup in ~/data/kartka/backup' : false;

  test('real SY backup: counts and idempotent import', () async {
    final data = decodeTachibk(file!.readAsBytesSync());
    final plan = const BackupPlanner(SourceMapper()).plan(data);
    final s = plan.summary;
    final favorites = data.manga.where((m) => m.favorite).length;
    expect(s.entries + s.duplicates, favorites);
    expect(s.notInLibrary, data.manga.length - favorites);
    expect(s.categories, data.categories.length);
    expect(
      plan.manga.where((m) => m.entry.sourceId == 'mangadex').length,
      greaterThan(0),
    );
    // The old MangaDex id lands on native `mangadex`, URLs unchanged
    // (same Keiyoushi shape). In this backup all 269 are history only.
    final legacy = data.manga.where((m) => m.sourceId == legacyMangaDexId);
    for (final m in legacy) {
      expect(const SourceMapper().map(m.sourceId).sourceId, 'mangadex');
      expect(m.url, matches(RegExp(r'^/manga/[0-9a-f-]{36}$')));
    }
    for (final m in plan.manga) {
      if (m.tachiyomiSourceId == legacyMangaDexId) {
        expect(m.entry.sourceId, 'mangadex');
      }
    }
    expect(
      plan.unavailable(null).map((u) => u.id),
      isNot(contains(legacyMangaDexId)),
    );
    if (file.path.contains('2026-10-24_08-29')) {
      expect(legacy, hasLength(269));
      expect(data.manga, hasLength(2657));
      expect(favorites, 774);
      expect(s.categories, 3);
      expect(plan.unavailable(null).map((u) => u.id), contains('6901'));
    }
    expect(
      plan.manga
          .expand((m) => m.bindings)
          .where((b) => b.service == 'mangaupdates'),
      hasLength(s.trackersByService['mangaupdates'] ?? 0),
    );
    if (file.path.contains('2026-10-24_08-29')) {
      expect(s.trackersByService['mangaupdates'], 483);
    }
    final f = Fakes();
    final first = await f.importer.apply(plan);
    expect(first.entries, s.entries);
    final writes = f.totalWrites;
    expect((await f.importer.apply(plan)).changedNothing, isTrue);
    expect(f.totalWrites, writes);
  }, skip: skip);
}
