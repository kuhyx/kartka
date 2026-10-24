import 'package:kartka/core/models/json_fields.dart';

/// One chapter of a manga (DOCS-contracts §1).
class ChapterInfo {
  /// Creates chapter info.
  const new({
    required this.url,
    required this.name,
    this.number,
    this.uploadedAt,
    this.scanlator,
  });

  /// Decodes the shape written by [toJson].
  factory fromJson(Map<String, Object?> json) => ChapterInfo(
    url: readString(json, 'url'),
    name: readString(json, 'name'),
    number: readOptDouble(json, 'number'),
    uploadedAt: readOptDate(json, 'uploadedAt'),
    scanlator: readOptString(json, 'scanlator'),
  );

  /// The source's identifier for this chapter.
  final String url;

  /// Display name, e.g. `Vol.2 Ch.13 - The Gate`.
  final String name;

  /// Chapter number when the source gives one (decimals allowed: 13.5).
  final double? number;

  /// Upload time, compared by instant (time zone does not matter).
  final DateTime? uploadedAt;

  /// Scanlation group, when known.
  final String? scanlator;

  /// JSON shape; [uploadedAt] as UTC ISO-8601.
  Map<String, Object?> toJson() => {
    'url': url,
    'name': name,
    'number': number,
    'uploadedAt': uploadedAt == null ? null : writeDate(uploadedAt!),
    'scanlator': scanlator,
  };

  @override
  bool operator ==(Object other) =>
      other is ChapterInfo &&
      other.url == url &&
      other.name == name &&
      other.number == number &&
      sameInstant(other.uploadedAt, uploadedAt) &&
      other.scanlator == scanlator;

  @override
  int get hashCode =>
      Object.hash(url, name, number, instantHash(uploadedAt), scanlator);

  @override
  String toString() => 'ChapterInfo($url)';
}
