import 'package:collection/collection.dart';
import 'package:kartka/core/models/json_fields.dart';

const _headers = MapEquality<String, String>();

/// One page image of a chapter (DOCS-contracts §1).
class PageRef {
  /// Creates a page reference.
  const new({
    required this.index,
    required this.imageUrl,
    this.headers = const {},
  });

  /// Decodes the shape written by [toJson].
  factory fromJson(Map<String, Object?> json) => PageRef(
    index: readInt(json, 'index'),
    imageUrl: readString(json, 'imageUrl'),
    headers: readStringMap(json, 'headers'),
  );

  /// Zero-based page position in the chapter.
  final int index;

  /// Absolute image URL (or a BlobStore key for an offline page).
  final String imageUrl;

  /// Request headers the image host needs (e.g. `Referer`).
  final Map<String, String> headers;

  /// JSON shape: field names as keys.
  Map<String, Object?> toJson() => {
    'index': index,
    'imageUrl': imageUrl,
    'headers': headers,
  };

  @override
  bool operator ==(Object other) =>
      other is PageRef &&
      other.index == index &&
      other.imageUrl == imageUrl &&
      _headers.equals(other.headers, headers);

  @override
  int get hashCode => Object.hash(index, imageUrl, _headers.hash(headers));

  @override
  String toString() => 'PageRef($index, $imageUrl)';
}
