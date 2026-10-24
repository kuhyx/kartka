import 'package:collection/collection.dart';
import 'package:kartka/core/models/json_fields.dart';
import 'package:kartka/core/models/manga_key.dart';

/// Publication status.
///
/// Values and order mirror Tachiyomi's `SManga` status codes 0-6, so
/// `MangaStatus.values[code]` maps a `.tachibk` or Suwayomi status directly.
enum MangaStatus {
  /// Code 0.
  unknown,

  /// Code 1.
  ongoing,

  /// Code 2.
  completed,

  /// Code 3.
  licensed,

  /// Code 4.
  publishingFinished,

  /// Code 5.
  cancelled,

  /// Code 6.
  onHiatus,
}

const _strings = ListEquality<String>();
const _stringMap = MapEquality<String, String>();

/// A manga as listed by a search or browse page (DOCS-contracts §1).
class MangaSummary {
  /// Creates a summary.
  const new({
    required this.sourceId,
    required this.url,
    required this.title,
    this.coverUrl,
  });

  /// Decodes the shape written by [toJson]; extra keys are ignored.
  factory fromJson(Map<String, Object?> json) => MangaSummary(
    sourceId: readString(json, 'sourceId'),
    url: readString(json, 'url'),
    title: readString(json, 'title'),
    coverUrl: readOptString(json, 'coverUrl'),
  );

  /// Id of the source this manga lives in.
  final String sourceId;

  /// Source-relative (or absolute) manga URL; the source's own identifier.
  final String url;

  /// Display title.
  final String title;

  /// Cover image URL, when the source lists one.
  final String? coverUrl;

  /// This manga's cross-device key.
  MangaKey get key => mangaKeyOf(sourceId, url);

  /// JSON shape: field names as keys; absent optionals are `null`.
  Map<String, Object?> toJson() => {
    'sourceId': sourceId,
    'url': url,
    'title': title,
    'coverUrl': coverUrl,
  };

  @override
  bool operator ==(Object other) =>
      other is MangaSummary &&
      other.runtimeType == runtimeType &&
      other.sourceId == sourceId &&
      other.url == url &&
      other.title == title &&
      other.coverUrl == coverUrl;

  @override
  int get hashCode => Object.hash(sourceId, url, title, coverUrl);

  @override
  String toString() => 'MangaSummary($key)';
}

/// A manga's full detail page (DOCS-contracts §1).
class MangaDetails extends MangaSummary {
  /// Creates details.
  const new({
    required super.sourceId,
    required super.url,
    required super.title,
    super.coverUrl,
    this.authors = const [],
    this.description,
    this.genres = const [],
    this.status = MangaStatus.unknown,
    this.trackerIds = const {},
  });

  /// Decodes the shape written by [toJson].
  factory fromJson(Map<String, Object?> json) => MangaDetails(
    sourceId: readString(json, 'sourceId'),
    url: readString(json, 'url'),
    title: readString(json, 'title'),
    coverUrl: readOptString(json, 'coverUrl'),
    authors: readStringList(json, 'authors'),
    description: readOptString(json, 'description'),
    genres: readStringList(json, 'genres'),
    status: MangaStatus.values.byName(
      readOptString(json, 'status') ?? MangaStatus.unknown.name,
    ),
    trackerIds: readStringMap(json, 'trackerIds'),
  );

  /// Authors and artists, in source order.
  final List<String> authors;

  /// Synopsis, when the source has one.
  final String? description;

  /// Genre / tag names.
  final List<String> genres;

  /// Publication status.
  final MangaStatus status;

  /// Tracker service id to remote id, e.g. `{'anilist': '123'}`.
  final Map<String, String> trackerIds;

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'authors': authors,
    'description': description,
    'genres': genres,
    'status': status.name,
    'trackerIds': trackerIds,
  };

  @override
  bool operator ==(Object other) =>
      super == other &&
      other is MangaDetails &&
      _strings.equals(other.authors, authors) &&
      other.description == description &&
      _strings.equals(other.genres, genres) &&
      other.status == status &&
      _stringMap.equals(other.trackerIds, trackerIds);

  @override
  int get hashCode => Object.hash(
    super.hashCode,
    _strings.hash(authors),
    description,
    _strings.hash(genres),
    status,
    _stringMap.hash(trackerIds),
  );

  @override
  String toString() => 'MangaDetails($key)';
}
