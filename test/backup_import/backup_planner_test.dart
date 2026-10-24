import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/backup_import/backup_planner.dart';
import 'package:kartka/backup_import/import_plan.dart';
import 'package:kartka/backup_import/source_mapper.dart';
import 'package:kartka/backup_import/tachibk_decoder.dart';

import 'fixture_builder.dart';

void main() {
  final plan = const BackupPlanner(SourceMapper())
      .plan(decodeTachibk(buildSyntheticTachibk()));
  PlannedManga byTitle(String t) =>
      plan.manga.firstWhere((m) => m.entry.title == t);

  test('only library entries are planned', () {
    expect(plan.manga, hasLength(6));
    expect(plan.summary.entries, 6);
    expect(plan.summary.notInLibrary, 1);
    expect(plan.manga.any((m) => m.entry.title == 'Not In Library'), isFalse);
  });

  test('MangaDex entry keeps its url and gets the native key', () {
    final m = byTitle('Dex One');
    expect(m.entry.key, 'mangadex|/manga/$mdUuid');
    expect(m.entry.sourceId, 'mangadex');
    expect(m.entry.mangaUrl, '/manga/$mdUuid');
    expect(m.entry.coverUrl, 'https://cover.example/Dex One.jpg');
    expect(
      m.entry.addedAt,
      DateTime.fromMillisecondsSinceEpoch(1666622369105, isUtc: true),
    );
    expect(
      m.entry.updatedAt,
      DateTime.fromMillisecondsSinceEpoch(1700000600000, isUtc: true),
    );
    expect(byTitle('Dex Zwei').entry.sourceId, 'mangadex');
  });

  test('read chapters, last-read progress and readAt', () {
    final m = byTitle('Dex One');
    expect(m.readChapterUrls, ['/chapter/c1', '/chapter/c2', '/chapter/c3']);
    final p = m.progress!;
    expect((p.chapterUrl, p.chapterNumber, p.page), ('/chapter/c3', 3.0, 4));
    expect(p.key, m.entry.key);
    expect(
      p.readAt,
      DateTime.fromMillisecondsSinceEpoch(1700000500000, isUtc: true),
    );
  });

  test('an unfinished later chapter becomes the progress', () {
    final m = byTitle('Allmanga Title');
    expect(m.entry.sourceId, 'suwayomi:4709139914729853090');
    expect(m.readChapterUrls, ['/ch/10']);
    expect((m.progress!.chapterUrl, m.progress!.page), ('/ch/11', 5));
  });

  test('chapters without a number never set progress', () {
    final m = byTitle('My Custom Title');
    expect(m.readChapterUrls, ['/ch/unnumbered']);
    expect(m.progress, isNull);
    expect(m.entry.coverUrl, 'https://custom.example/cover.png');
  });

  test('categories map by order and get stable ids', () {
    expect(plan.categories.map((c) => c.name), ['Reading', 'Later', 'Empty']);
    final reading = plan.categories.first;
    expect(
      reading.id,
      'sy-${'reading'.codeUnits.map((c) => c.toRadixString(16)).join()}',
    );
    expect(byTitle('Dex One').categoryIds, [reading.id]);
    expect(byTitle('Allmanga Title').categoryIds, hasLength(2));
    expect(plan.summary.categories, 3);
    expect(plan.summary.memberships, 3);
  });

  test('trackers: only AniList and MAL are bound, all are counted', () {
    final bindings = byTitle('Dex One').bindings;
    expect(bindings.map((b) => (b.service, b.remoteId, b.lastChapter)), [
      ('anilist', '134187', 3),
      ('mal', '139022', 3),
    ]);
    expect(plan.summary.trackersByService, {
      'anilist': 1,
      'mal': 1,
      'mangaupdates': 1,
    });
    expect(plan.summary.trackersImported, 2);
    expect(plan.summary.chaptersRead, 6);
  });

  test('unmapped sources are reported with names and counts', () {
    expect(plan.summary.unmappedSources.map((u) => (u.name, u.id, u.entries)), [
      ('E-Hentai', '6901', 1),
    ]);
    expect(byTitle('EH gallery').entry.sourceId, 'suwayomi:6901');
    expect(byTitle('Local Manga').entry.sourceId, 'local');
  });

  test('duplicate keys are planned once', () {
    final data = decodeTachibk(buildSyntheticTachibk());
    data.manga.add(data.manga.first);
    final p = const BackupPlanner(SourceMapper()).plan(data);
    expect(p.manga, hasLength(6));
    expect(p.summary.duplicates, 1);
  });

  test('unknown tracker ids get a generic service name', () {
    expect(trackerService(2), 'anilist');
    expect(trackerService(1), 'mal');
    expect(trackerService(60), 'mdlist');
    expect(trackerService(77), 'tracker77');
  });
}
