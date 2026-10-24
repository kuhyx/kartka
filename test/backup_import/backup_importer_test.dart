import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/backup_import/backup_planner.dart';
import 'package:kartka/backup_import/import_plan.dart';
import 'package:kartka/backup_import/source_mapper.dart';
import 'package:kartka/backup_import/tachibk_decoder.dart';
import 'package:kartka/core/models/models.dart';

import 'fake_setup.dart';
import 'fixture_builder.dart';

void main() {
  late ImportPlan plan;
  late Fakes f;

  setUp(() {
    plan = const BackupPlanner(SourceMapper())
        .plan(decodeTachibk(buildSyntheticTachibk()));
    f = Fakes();
  });

  test('first import writes everything', () async {
    final r = await f.importer.apply(plan);
    expect(f.library.entries, hasLength(6));
    expect(f.categories.categories.values.map((c) => c.name), [
      'Reading',
      'Later',
      'Empty',
    ]);
    const dexKey = 'mangadex|/manga/$mdUuid';
    expect(f.categories.membership[dexKey], {plan.categories.first.id});
    expect(f.progress.read[dexKey], {
      '/chapter/c1',
      '/chapter/c2',
      '/chapter/c3',
    });
    expect(f.progress.progress[dexKey]!.chapterUrl, '/chapter/c3');
    expect(f.bindings.bound['$dexKey#anilist'], ('134187', 3));
    expect(f.bindings.bound['$dexKey#mal'], ('139022', 3));
    expect(r.entries, 6);
    expect(r.categories, 3);
    expect(r.memberships, 3);
    expect(r.readMarks, 6);
    expect(r.progress, 3);
    expect(r.bindings, 2);
    expect(r.changedNothing, isFalse);
  });

  test('importing twice is idempotent: zero writes the second time', () async {
    await f.importer.apply(plan);
    final before = f.totalWrites;
    final again = await f.importer.apply(plan);
    expect(f.totalWrites, before);
    expect(again.changedNothing, isTrue);
  });

  test('an existing category with the same name is reused', () async {
    await f.categories.upsert(
      Category(
        id: 'mine',
        name: 'reading',
        order: 9,
        updatedAt: DateTime.utc(2026),
      ),
    );
    await f.importer.apply(plan);
    expect(
      f.categories.categories.keys,
      isNot(contains(plan.categories.first.id)),
    );
    expect(f.categories.membership['mangadex|/manga/$mdUuid'], {'mine'});
  });

  test('existing entries and newer progress are left alone', () async {
    const key = 'mangadex|/manga/$mdUuid';
    final existing = plan.manga.first.entry.copyWith(title: 'Renamed by me');
    await f.library.upsert(existing);
    await f.progress.record(
      ReadingProgress(
        key: key,
        chapterUrl: '/chapter/c9',
        chapterNumber: 9,
        page: 1,
        readAt: DateTime.utc(2026),
      ),
    );
    await f.importer.apply(plan);
    expect(f.library.entries[key]!.title, 'Renamed by me');
    expect(f.progress.progress[key]!.chapterNumber, 9);
  });

  test('a chapter the user marked unread stays unread', () async {
    const key = 'mangadex|/manga/$mdUuid';
    await f.progress.markUnread(key, '/chapter/c2');
    await f.importer.apply(plan);
    expect(f.progress.read[key], {'/chapter/c1', '/chapter/c3'});
  });

  test('missing binding sink skips trackers without failing', () async {
    final r = await Fakes(withBindings: false).importer.apply(plan);
    expect(r.bindings, 0);
  });

  test('reports progress and yields to the event loop', () async {
    final seen = <(int, int)>[];
    await f.importer.apply(plan, onProgress: (d, t) => seen.add((d, t)));
    expect(seen.last, (6, 6));
    expect(seen.first, (1, 6));
  });
}
