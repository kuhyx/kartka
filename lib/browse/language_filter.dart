/// The Browse language filter: which source languages Browse lists, and in
/// which order. The Sources ranking tab has its own filter and ignores this.
library;

import 'package:flutter/foundation.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/browse/source_ordering.dart';
import 'package:kartka/core/models/source_ref.dart';

/// The one bucket for sources that serve every language (`all`, `multi`).
const String kAllLanguages = 'all';

/// The selection when the synced setting is unset.
const List<String> kDefaultBrowseLanguages = ['en', kAllLanguages, 'ja'];

const Map<String, String> _labels = {
  kAllLanguages: 'All languages',
  'ar': 'Arabic',
  'de': 'German',
  'en': 'English',
  'es': 'Spanish',
  'es-419': 'Spanish (Latin America)',
  'fr': 'French',
  'id': 'Indonesian',
  'it': 'Italian',
  'ja': 'Japanese',
  'ko': 'Korean',
  'pl': 'Polish',
  'pt': 'Portuguese',
  'pt-br': 'Portuguese (Brazil)',
  'ru': 'Russian',
  'th': 'Thai',
  'tr': 'Turkish',
  'uk': 'Ukrainian',
  'vi': 'Vietnamese',
  'zh': 'Chinese',
  'zh-hans': 'Chinese (Simplified)',
  'zh-hant': 'Chinese (Traditional)',
};

/// The filter bucket of a source language: lower-cased and trimmed, with
/// `all` and `multi` folded into [kAllLanguages]. Region codes stay apart
/// (`pt-br` is not `pt`).
String languageBucket(String lang) {
  final code = lang.trim().toLowerCase();
  return code == 'multi' ? kAllLanguages : code;
}

/// Display name of a bucket; unknown codes are shown upper-cased.
String languageLabel(String bucket) => _labels[bucket] ?? bucket.toUpperCase();

/// The sources of one language, grouped by origin.
@immutable
class LanguageSection {
  /// Creates a section.
  const new(this.language, this.groups);

  /// The bucket ([languageBucket]) every source here belongs to.
  final String language;

  /// Origin groups in [groupSources] order.
  final List<SourceGroup> groups;
}

/// The Browse list: one section per [selected] language that has sources,
/// in [selected] order; inside a section, [groupSources] order (origin, then
/// rank, then name). Sources of unselected languages are dropped.
List<LanguageSection> sectionSources(
  Iterable<SourceRef> sources,
  Map<String, SourceHealthSummary> health,
  List<String> selected,
) => [
  for (final lang in selected)
    if (groupSources(
          sources.where((s) => languageBucket(s.lang) == lang),
          health,
        )
        case final groups when groups.isNotEmpty)
      LanguageSection(lang, groups),
];

/// Number of [sources] per language bucket.
Map<String, int> languageCounts(Iterable<SourceRef> sources) {
  final counts = <String, int>{};
  for (final s in sources) {
    counts.update(languageBucket(s.lang), (n) => n + 1, ifAbsent: () => 1);
  }
  return counts;
}

/// The picker's rows: languages present in [counts], the [selected] ones
/// first in selection order, then the others by code.
List<String> pickerLanguages(Map<String, int> counts, List<String> selected) {
  final rest = counts.keys.where((l) => !selected.contains(l)).toList()..sort();
  return [...selected.where(counts.containsKey), ...rest];
}
