import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/migration/dedupe/dupe_rule.dart';

import '../fakes.dart';

/// kuhy's AllManga source (Suwayomi) as the agent instance saw it.
const _allManga = 'suwayomi:4709139914729853090';
const _full = '/manga/JwXg7frBAC4dCXMzX/mata-onaji-yume-wo-miteita';
const _bare = 'JwXg7frBAC4dCXMzX';
const _title = 'I Had That Same Dream Again';
const _blurb =
    'Elementary school student Nanoka Koyanagi considers herself weird. '
    'She often uses it as an excuse to avoid doing things she dislikes.';

/// One library entry of [url] on [source] with 12 dated, read chapters;
/// [detailed] stores the details (author and description), else none.
Dupe _entry(
  String url, {
  String source = _allManga,
  String title = _title,
  bool detailed = false,
}) {
  final chapters = [
    for (final c in chaptersOf('$source$url', [
      for (var n = 1; n <= 12; n++) n,
    ]))
      ChapterInfo(
        url: c.url,
        name: c.name,
        number: c.number,
        uploadedAt: DateTime.utc(2022, 8, 17),
      ),
  ];
  return Dupe(
    entry: LibraryEntry(
      key: mangaKeyOf(source, url),
      sourceId: source,
      mangaUrl: url,
      title: title,
      addedAt: DateTime.utc(2025),
      updatedAt: DateTime.utc(2025),
    ),
    facts: (
      details: detailed
          ? MangaDetails(
              sourceId: source,
              url: url,
              title: title,
              authors: const ['Kirihara Idumi'],
              description: _blurb,
            )
          : null,
      chapters: chapters,
      readUrls: {for (final c in chapters) c.url},
    ),
  );
}

void main() {
  test('one source, a bare id and its full url: the same manga', () {
    final full = _entry(_full, detailed: true);
    final bare = _entry(_bare);
    expect(isDuplicate(full, bare), isTrue);
    expect(isDuplicate(bare, full), isTrue);
  });

  test('the entry with stored details wins, whichever key sorts first', () {
    for (final url in [_full, 'https://allmanga.to$_full']) {
      final plan = planMerges([_entry(_bare), _entry(url, detailed: true)]);
      expect(plan, hasLength(1));
      expect(plan.single.winner.entry.mangaUrl, url);
      expect(plan.single.losers.single.entry.mangaUrl, _bare);
    }
  });

  test('one source, unrelated urls: never the same manga', () {
    for (final (x, y) in [
      ('/manga/abc', '/manga/xyz'),
      ('/manga/abc', '/manga/abc-colored'),
      ('/series.php?id=1', '/series.php?id=2'),
      ('/manga', '/title'),
    ]) {
      expect(
        isDuplicate(_entry(x, detailed: true), _entry(y)),
        isFalse,
        reason: '$x vs $y',
      );
    }
  });

  test('one source, one url is one entry, not a pair', () {
    expect(isDuplicate(_entry(_full, detailed: true), _entry(_full)), isFalse);
  });

  test('urls only matter on one source', () {
    expect(
      isDuplicate(
        _entry('/manga/abc', detailed: true),
        _entry('/manga/xyz', source: 'mangadex'),
      ),
      isTrue,
    );
  });
}
