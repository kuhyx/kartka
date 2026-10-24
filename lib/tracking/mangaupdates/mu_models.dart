/// MangaUpdates API v1 shapes Kartka reads, and its errors.
library;

/// `list_id` of the user's standard Reading List.
const muReadingList = 0;

/// Standard list ids to the `type` names `ListsModelV1` uses.
const muListTypes = {
  0: 'read',
  1: 'wish',
  2: 'complete',
  3: 'unfinished',
  4: 'hold',
};

/// Series types that are not comics; search hides them.
const muHiddenTypes = {'Novel', 'Drama CD'};

int? _int(Object? v) => v is num ? v.toInt() : null;

Map<String, Object?>? _map(Object? v) => v is Map<String, Object?> ? v : null;

/// One series search hit (`SeriesModelSearchV1`).
class MuSeries {
  /// Creates a hit.
  const new({required this.id, required this.title, this.coverUrl, this.type});

  /// Parses `results[].record`; throws [FormatException] without id/title.
  factory fromJson(Map<String, Object?> json) {
    final id = _int(json['series_id']);
    final title = json['title'];
    if (id == null || title is! String) {
      throw const FormatException('series without id or title');
    }
    final url = _map(_map(json['image'])?['url']);
    final cover = url?['thumb'] ?? url?['original'];
    final type = json['type'];
    return MuSeries(
      id: id,
      title: title,
      coverUrl: cover is String ? cover : null,
      type: type is String ? type : null,
    );
  }

  /// Series id (int64).
  final int id;

  /// Main title.
  final String title;

  /// Thumbnail, else the original image.
  final String? coverUrl;

  /// `Manga`, `Manhwa`, `Novel`, ...
  final String? type;
}

/// The user's list entry for one series (`ListsSeriesModelV1`).
class MuListItem {
  /// Creates an entry.
  const new({
    required this.seriesId,
    required this.listId,
    required this.chapter,
    this.listType,
  });

  /// Parses a `GET /lists/series/{id}` body.
  factory fromJson(Map<String, Object?> json) {
    final id = _int(_map(json['series'])?['id']);
    final listId = _int(json['list_id']);
    if (id == null || listId == null) {
      throw const FormatException('list entry without series or list id');
    }
    final type = json['list_type'];
    return MuListItem(
      seriesId: id,
      listId: listId,
      chapter: _int(_map(json['status'])?['chapter']) ?? 0,
      listType: type is String && type.isNotEmpty ? type : null,
    );
  }

  /// Series id.
  final int seriesId;

  /// List the series is on (0-4 standard, 101+ custom).
  final int listId;

  /// Chapters read.
  final int chapter;

  /// `read`, `wish`, ... when the server sends it.
  final String? listType;

  /// List type for `TrackStatus.status`: [listType], the standard name for
  /// [listId], or `list<id>` for a custom list.
  String get status => listType ?? muListTypes[listId] ?? 'list$listId';
}

/// A MangaUpdates request failed.
class MuException implements Exception {
  /// Creates an exception with an optional HTTP [statusCode].
  const new(this.message, {this.statusCode});

  /// What went wrong (the API's `reason` when it sent one).
  final String message;

  /// HTTP status, when the failure came from a response.
  final int? statusCode;

  /// Name shown in [toString].
  String get kind => 'MuException';

  @override
  String toString() =>
      statusCode == null ? '$kind: $message' : '$kind($statusCode): $message';
}

/// Not logged in, or MangaUpdates refused the credentials or session.
class MuAuthException extends MuException {
  /// Creates an auth failure.
  const new(super.message, {super.statusCode});

  @override
  String get kind => 'MuAuthException';
}
