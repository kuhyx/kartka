import 'package:kartka/core/models/models.dart';

/// What is known about one manga for telling whether two listings are the
/// same series: the wanted library entry, or one search hit. Everything but
/// [title] may be unknown (a source that is down, a hit not fetched).
class MangaFacts {
  /// Creates the facts.
  const new({
    required this.title,
    this.altTitles = const [],
    this.authors = const [],
    this.description,
    this.chapters,
    this.readChapter,
  });

  /// The facts of [details]: its alt titles come from its description
  /// ([altTitlesIn]), [chapters] is its chapter count when listed.
  factory of(MangaDetails details, {int? chapters, double? readChapter}) =>
      MangaFacts(
        title: details.title,
        altTitles: altTitlesIn(details.description),
        authors: details.authors,
        description: details.description,
        chapters: chapters,
        readChapter: readChapter,
      );

  /// Display title.
  final String title;

  /// Other names of the series (other languages, old titles).
  final List<String> altTitles;

  /// Authors and artists.
  final List<String> authors;

  /// Synopsis.
  final String? description;

  /// How many chapters the source lists; null when not fetched.
  final int? chapters;

  /// The chapter number kuhy has read up to (the wanted entry's progress).
  final double? readChapter;

  /// [title] and [altTitles].
  List<String> get names => [title, ...altTitles];

  /// These facts with [name] as one more alt title (a manual search).
  MangaFacts withName(String name) => MangaFacts(
    title: title,
    altTitles: [...altTitles, name],
    authors: authors,
    description: description,
    chapters: chapters,
    readChapter: readChapter,
  );

  /// These facts with the details of [details] and [chapters] filled in.
  MangaFacts withDetails(MangaDetails? details, {int? chapters}) => MangaFacts(
    title: title,
    altTitles: {
      ...altTitles,
      if (details != null && details.title != title) details.title,
      ...altTitlesIn(details?.description),
    }.toList(),
    authors: details?.authors ?? authors,
    description: details?.description ?? description,
    chapters: chapters ?? this.chapters,
    readChapter: readChapter,
  );
}

final _label = RegExp(
  r'^\s*(?:alternative|alternate|alt\.?|associated|other|also known as)'
  r'(?:\s+(?:names?|titles?|name\(s\)|title\(s\)))?\s*[:：]\s*(.*)$',
  caseSensitive: false,
);
final _bullet = RegExp(r'^\s*[-•*·]\s*(.+)$');
final _separator = RegExp(r'\s*(?:[;|,、]|\s/\s)\s*');

/// The alternative titles a source wrote into [description]: a line like
/// `Alternative Titles: A; B, C` (also `Associated Names`, `Alt name(s)`,
/// `Also known as`, ...), split on `;` `,` `|` `、` and ` / `, or a label
/// line followed by a bullet list. A bare `/` is kept (`Fate/Zero`).
List<String> altTitlesIn(String? description) {
  if (description == null) return const [];
  final out = <String>[];
  final lines = description.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final rest = _label.firstMatch(lines[i])?[1]?.trim();
    if (rest == null) continue;
    if (rest.isNotEmpty) {
      out.addAll(rest.split(_separator).where((t) => t.trim().isNotEmpty));
      continue;
    }
    for (; i + 1 < lines.length; i++) {
      final item = _bullet.firstMatch(lines[i + 1])?[1]?.trim();
      if (item == null) break;
      out.add(item);
    }
  }
  return [for (final t in out) t.trim()];
}
