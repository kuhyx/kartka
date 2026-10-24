/// Lenient readers for the evaluator's JSON.
///
/// The §5 record is written by another program (and may be older or newer
/// than this app), so a field of the wrong type reads as missing rather than
/// throwing: one odd field must never hide a whole source from the ranking.
library;

/// [json] as a string-keyed map, or null.
Map<String, Object?>? asMap(Object? json) =>
    json is Map ? json.cast<String, Object?>() : null;

/// A non-empty string at [key], or null.
String? readString(Map<String, Object?> json, String key) {
  final v = json[key];
  return v is String && v.isNotEmpty ? v : null;
}

/// A number at [key] as a double, or null.
double? readDouble(Map<String, Object?> json, String key) {
  final v = json[key];
  return v is num ? v.toDouble() : null;
}

/// A number at [key] rounded to an int, or null.
int? readInt(Map<String, Object?> json, String key) {
  final v = json[key];
  return v is num && v.isFinite ? v.round() : null;
}

/// The string elements of the list at [key]; anything else is skipped.
List<String> readStrings(Map<String, Object?> json, String key) {
  final v = json[key];
  return v is List ? List.unmodifiable(v.whereType<String>()) : const [];
}

/// An ISO-8601 timestamp at [key] in UTC, or null.
DateTime? readInstant(Map<String, Object?> json, String key) {
  final v = json[key];
  return v is String ? DateTime.tryParse(v)?.toUtc() : null;
}

/// [entries] without the null values, so a missing field stays missing on
/// the way back out (keeps toJson → fromJson a fixed point).
Map<String, Object?> compact(Map<String, Object?> entries) => {
  for (final e in entries.entries)
    if (e.value != null) e.key: e.value,
};
