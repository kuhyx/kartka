import 'package:kartka/plugins/mangayomi/mangayomi_entry.dart';

/// Recognises and parses Mangayomi repo indexes (`index.json`).
///
/// A Mangayomi repo index is a top-level JSON array of source entries that
/// carry `sourceCodeLanguage`; Kartka's own repo `index.json` is an object.
abstract final class MangayomiIndex {
  /// True when [json] has the shape of a Mangayomi repo index.
  static bool looksLike(Object? json) =>
      json is List &&
      json.isNotEmpty &&
      json.every((e) => e is Map && e.containsKey('sourceCodeLanguage'));

  /// The installable JS manga sources in [json], in index order.
  ///
  /// Dart, anime and novel sources, entries without a `.js` source file and
  /// malformed entries are skipped. Throws [FormatException] when [json] is
  /// not a Mangayomi index at all.
  static List<MangayomiEntry> parse(Object? json) {
    if (!looksLike(json)) {
      throw const FormatException('not a Mangayomi repo index');
    }
    final out = <MangayomiEntry>[];
    for (final e in json! as List) {
      final map = (e as Map).cast<String, Object?>();
      if (!MangayomiEntry.isConvertible(map)) continue;
      try {
        out.add(MangayomiEntry.fromJson(map));
      } on FormatException {
        continue;
      }
    }
    return out;
  }

  /// The index URL for a repo given as an index URL, a repo root URL, or a
  /// GitHub `owner/repo` shorthand.
  static Uri indexUrl(String repo) {
    final s = repo.trim();
    if (RegExp(r'^[\w.-]+/[\w.-]+$').hasMatch(s)) {
      return Uri.parse('https://raw.githubusercontent.com/$s/main/index.json');
    }
    final uri = Uri.parse(s);
    if (uri.path.endsWith('.json')) return uri;
    final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    return uri.replace(path: '${path}index.json');
  }
}
