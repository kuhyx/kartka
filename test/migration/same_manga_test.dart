import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/migration/same_manga.dart';

const _knight =
    'A young knight sworn to the frozen kingdom befriends an emperor '
    'penguin who can talk. Together they cross the ice sheet to stop the '
    'sorcerer who stole the midnight sun from the capital.';

const _cook =
    'Penguin chef Knight runs a tiny ramen stall in Osaka and dreams of '
    'winning the national noodle championship against his rival bakery.';

void main() {
  const wanted = MangaFacts(
    title: 'Knight and Penguin',
    authors: ['Sato Kenji'],
    description: _knight,
    chapters: 40,
  );
  const match = SameManga(wanted);

  group('titles', () {
    test('exact, punctuation and & aside, or through an alt title', () {
      expect(
        match.titleScore(const MangaFacts(title: 'knight AND penguin')),
        1,
      );
      expect(match.titleScore(const MangaFacts(title: 'Knight & Penguin!')), 1);
      expect(
        match.titleScore(
          const MangaFacts(
            title: 'Kishi to Pengin',
            altTitles: ['Knight and Penguin'],
          ),
        ),
        1,
      );
      expect(match.titleScore(const MangaFacts(title: 'Penguin Highway')), 0);
    });
  });

  test('authors match in either name order, else disagree', () {
    expect(
      match.authorScore(const MangaFacts(title: 'x', authors: ['KENJI Sato'])),
      1,
    );
    expect(
      match.authorScore(const MangaFacts(title: 'x', authors: ['Mori Aya'])),
      0,
    );
    expect(match.authorScore(const MangaFacts(title: 'x')), isNull);
  });

  test('descriptions: shared words count, unrelated ones do not', () {
    final same = match.descriptionScore(
      const MangaFacts(title: 'x', description: 'Read online! $_knight'),
    );
    expect(same, 1);
    expect(
      match.descriptionScore(const MangaFacts(title: 'x', description: _cook)),
      0,
    );
    expect(
      match.descriptionScore(const MangaFacts(title: 'x', description: 'Hi')),
      isNull,
    );
  });

  test('chapter counts: far fewer than kuhy has is implausible', () {
    expect(match.chapterScore(const MangaFacts(title: 'x', chapters: 38)), 1);
    expect(
      match.chapterScore(const MangaFacts(title: 'x', chapters: 4)),
      lessThan(0.3),
    );
    expect(match.chapterScore(const MangaFacts(title: 'x', chapters: 0)), 0);
    const read = SameManga(MangaFacts(title: 'x', readChapter: 150));
    expect(read.chapterScore(const MangaFacts(title: 'x', chapters: 160)), 1);
    expect(
      read.chapterScore(const MangaFacts(title: 'x', chapters: 12)),
      lessThan(0.1),
    );
    expect(
      const SameManga(MangaFacts(title: 'x'))
          .chapterScore(const MangaFacts(title: 'x', chapters: 3)),
      isNull,
    );
  });

  test('the same title by another author about something else ranks below '
      'the real one, and below a hit not checked yet', () {
    const wrong = MangaFacts(
      title: 'Knight and Penguin',
      authors: ['Mori Aya'],
      description: _cook,
      chapters: 41,
    );
    const right = MangaFacts(
      title: 'Knight & Penguin',
      authors: ['Kenji Sato'],
      description: _knight,
      chapters: 39,
    );
    const unchecked = MangaFacts(title: 'Knight and Penguin');
    expect(match.score(right), greaterThan(match.score(unchecked)));
    expect(match.score(unchecked), greaterThan(match.score(wrong)));
    expect(match.score(right), greaterThan(0.9));
    expect(match.score(wrong), lessThan(strongMatch));
  });

  test('a reference with nothing but a title stays neutral', () {
    const bare = SameManga(MangaFacts(title: 'Knight and Penguin'));
    final s = bare.score(
      const MangaFacts(title: 'Knight and Penguin', authors: ['Mori Aya']),
    );
    expect(s, closeTo(titleWeight + (1 - titleWeight) / 2, 1e-9));
  });

  test('MangaFacts.of reads details and the alt titles in a description', () {
    final facts = MangaFacts.of(
      const MangaDetails(
        sourceId: 's',
        url: '/k',
        title: 'Kishi to Pengin',
        authors: ['Sato Kenji'],
        description:
            '$_knight\n\nAlternative Titles: Knight and Penguin; 騎士とペンギン, '
            'Le Chevalier et le Pingouin',
      ),
      chapters: 7,
    );
    expect(facts.altTitles, [
      'Knight and Penguin',
      '騎士とペンギン',
      'Le Chevalier et le Pingouin',
    ]);
    expect(facts.chapters, 7);
    expect(facts.authors, ['Sato Kenji']);
  });

  test('altTitlesIn reads several label styles and bullet lists', () {
    expect(altTitlesIn(null), isEmpty);
    expect(altTitlesIn('Associated Names: A / B | C'), ['A', 'B', 'C']);
    expect(altTitlesIn('Also known as: Kn&P'), ['Kn&P']);
    expect(altTitlesIn('Alt name(s):\n- One\n• Two\n\nStory text'), [
      'One',
      'Two',
    ]);
    expect(altTitlesIn('Just a story: with a colon.'), isEmpty);
  });
}
