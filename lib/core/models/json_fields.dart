/// Typed readers shared by the model `fromJson` constructors.
///
/// Not exported from `models.dart`: these are the decoding rules, not API.
/// Two rules matter across platforms and are why these exist at all:
///
/// * numbers are read as `num` and converted, because on web a JSON `1.0`
///   decodes to an `int` and a bare `as double` cast throws;
/// * instants are written as UTC ISO-8601 and compared by microseconds, so a
///   value survives a round trip through any device's local time zone.
library;

/// Reads a required string field.
String readString(Map<String, Object?> json, String key) =>
    json[key]! as String;

/// Reads an optional string field.
String? readOptString(Map<String, Object?> json, String key) =>
    json[key] as String?;

/// Reads a required integer, accepting any JSON number.
int readInt(Map<String, Object?> json, String key) =>
    (json[key]! as num).toInt();

/// Reads an optional double, accepting any JSON number.
double? readOptDouble(Map<String, Object?> json, String key) =>
    (json[key] as num?)?.toDouble();

/// Reads a required double, accepting any JSON number.
double readDouble(Map<String, Object?> json, String key) =>
    (json[key]! as num).toDouble();

/// Reads a boolean that defaults to `false` when absent.
bool readBool(Map<String, Object?> json, String key) =>
    (json[key] as bool?) ?? false;

/// Reads a required ISO-8601 instant.
DateTime readDate(Map<String, Object?> json, String key) =>
    DateTime.parse(readString(json, key));

/// Reads an optional ISO-8601 instant.
DateTime? readOptDate(Map<String, Object?> json, String key) {
  final raw = readOptString(json, key);
  return raw == null ? null : DateTime.parse(raw);
}

/// Reads a list of strings (absent means empty), unmodifiable.
List<String> readStringList(Map<String, Object?> json, String key) =>
    List.unmodifiable(
      ((json[key] as List<Object?>?) ?? const []).cast<String>(),
    );

/// Reads a string-to-string map (absent means empty), unmodifiable.
Map<String, String> readStringMap(Map<String, Object?> json, String key) =>
    Map.unmodifiable(
      ((json[key] as Map<String, Object?>?) ?? const {}).cast<String, String>(),
    );

/// Reads a nested JSON object.
Map<String, Object?> readObject(Object? raw) => raw! as Map<String, Object?>;

/// Writes an instant as UTC ISO-8601 (see the library doc).
String writeDate(DateTime value) => value.toUtc().toIso8601String();

/// Equality of two optional instants by the moment they denote.
bool sameInstant(DateTime? a, DateTime? b) =>
    a?.microsecondsSinceEpoch == b?.microsecondsSinceEpoch;

/// Hash consistent with [sameInstant].
int instantHash(DateTime? value) => value?.microsecondsSinceEpoch.hashCode ?? 0;
