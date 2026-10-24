import 'package:kartka/core/models/json_fields.dart';

/// Where a source's code runs (DOCS-contracts §1).
enum SourceOrigin {
  /// A Dart source compiled into the app (e.g. `mangadex`).
  native,

  /// A Tachiyomi extension run by the self-hosted Suwayomi server.
  suwayomi,

  /// A JS plugin installed from a repo (§6).
  plugin,

  /// CBZ files and folders on this device.
  local,
}

/// Identifies a source.
///
/// Ids: `'mangadex'`, `'local'`, `'suwayomi:<tachiyomiSourceId>'`,
/// `'plugin:<pluginId>'`. Ids are always strings: Tachiyomi's numeric ids
/// exceed 2^53 and would lose precision as a JS number on web.
class SourceRef {
  /// Creates a source reference.
  const new({
    required this.id,
    required this.name,
    required this.lang,
    required this.origin,
  });

  /// Decodes the shape written by [toJson].
  factory fromJson(Map<String, Object?> json) => SourceRef(
    id: readString(json, 'id'),
    name: readString(json, 'name'),
    lang: readString(json, 'lang'),
    origin: SourceOrigin.values.byName(readString(json, 'origin')),
  );

  /// Stable source id (see the class doc for the formats).
  final String id;

  /// Human-readable name.
  final String name;

  /// Content language (BCP-47-ish, e.g. `en`, `pl`, `all`).
  final String lang;

  /// Where the source runs.
  final SourceOrigin origin;

  /// JSON shape: field names as keys, [origin] by enum name.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'lang': lang,
    'origin': origin.name,
  };

  @override
  bool operator ==(Object other) =>
      other is SourceRef &&
      other.id == id &&
      other.name == name &&
      other.lang == lang &&
      other.origin == origin;

  @override
  int get hashCode => Object.hash(id, name, lang, origin);

  @override
  String toString() => 'SourceRef($id)';
}
