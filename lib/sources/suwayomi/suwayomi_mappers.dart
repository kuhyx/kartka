import 'package:kartka/core/models/models.dart';

/// Prefix of every Suwayomi-backed source id (`suwayomi:<numeric id>`).
const suwayomiPrefix = 'suwayomi:';

/// Suwayomi's own local source; kartka's local part covers that ground.
const suwayomiLocalSourceId = '0';

/// Kartka source id for Suwayomi's [serverId]. Ids exceed 2^53, so they
/// stay strings end to end (a JS double on web would round them).
String kartkaSourceId(String serverId) => '$suwayomiPrefix$serverId';

/// Turns a server-relative path into an absolute URL.
typedef UrlResolver = String Function(String path);

/// One installed source as listed by the server.
class SuwayomiSourceInfo {
  /// Creates the info.
  const new({
    required this.serverId,
    required this.ref,
    required this.supportsLatest,
  });

  /// Parses a `sources.nodes[]` entry.
  factory fromJson(Map<String, Object?> json) {
    final id = json['id']! as String;
    return SuwayomiSourceInfo(
      serverId: id,
      ref: SourceRef(
        id: kartkaSourceId(id),
        name: json['name']! as String,
        lang: json['lang']! as String,
        origin: SourceOrigin.suwayomi,
      ),
      supportsLatest: json['supportsLatest'] as bool? ?? false,
    );
  }

  /// Tachiyomi numeric source id, as a string.
  final String serverId;

  /// The kartka-facing reference.
  final SourceRef ref;

  /// Whether the source has a "latest" listing.
  final bool supportsLatest;
}

/// Maps a `MangaType` with `url title thumbnailUrl` to a summary.
MangaSummary mangaSummaryFrom(
  Map<String, Object?> json,
  String sourceId,
  UrlResolver resolve,
) => MangaSummary(
  sourceId: sourceId,
  url: json['url']! as String,
  title: json['title']! as String,
  coverUrl: _cover(json, resolve),
);

/// Maps a full `MangaType` to details.
MangaDetails mangaDetailsFrom(
  Map<String, Object?> json,
  String sourceId,
  UrlResolver resolve,
) => MangaDetails(
  sourceId: sourceId,
  url: json['url']! as String,
  title: json['title']! as String,
  coverUrl: _cover(json, resolve),
  authors: _people(json),
  description: _nonEmpty(json['description'] as String?),
  genres: [for (final g in json['genre'] as List? ?? const []) g as String],
  status: _statuses[json['status']] ?? MangaStatus.unknown,
);

/// Maps a `ChapterType`; Tachiyomi's `-1` number and `0` date mean unknown.
ChapterInfo chapterFrom(Map<String, Object?> json) {
  final number = (json['chapterNumber'] as num?)?.toDouble();
  final millis = int.tryParse('${json['uploadDate']}') ?? 0;
  return ChapterInfo(
    url: json['url']! as String,
    name: json['name']! as String,
    number: number == null || number < 0 ? null : number,
    uploadedAt: millis <= 0
        ? null
        : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
    scanlator: _nonEmpty(json['scanlator'] as String?),
  );
}

/// Maps `fetchChapterPages.pages` to refs carrying the auth [headers].
List<PageRef> pageRefsFrom(
  List<Object?> pages,
  UrlResolver resolve,
  Map<String, String> headers,
) => [
  for (final (i, path) in pages.indexed)
    PageRef(index: i, imageUrl: resolve(path! as String), headers: headers),
];

String? _cover(Map<String, Object?> json, UrlResolver resolve) {
  final thumb = _nonEmpty(json['thumbnailUrl'] as String?);
  return thumb == null ? null : resolve(thumb);
}

List<String> _people(Map<String, Object?> json) {
  final names = <String>[];
  for (final field in ['author', 'artist']) {
    for (final name in '${json[field] ?? ''}'.split(',')) {
      final trimmed = name.trim();
      if (trimmed.isNotEmpty && !names.contains(trimmed)) names.add(trimmed);
    }
  }
  return names;
}

String? _nonEmpty(String? value) =>
    value == null || value.trim().isEmpty ? null : value;

const Map<String, MangaStatus> _statuses = {
  'UNKNOWN': MangaStatus.unknown,
  'ONGOING': MangaStatus.ongoing,
  'COMPLETED': MangaStatus.completed,
  'LICENSED': MangaStatus.licensed,
  'PUBLISHING_FINISHED': MangaStatus.publishingFinished,
  'CANCELLED': MangaStatus.cancelled,
  'ON_HIATUS': MangaStatus.onHiatus,
};
