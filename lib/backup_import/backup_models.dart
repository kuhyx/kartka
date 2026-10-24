/// Plain data read from a TachiyomiSY `.tachibk`; no Kartka types here.
///
/// Field numbers follow the documented Tachiyomi/Mihon/SY backup schema
/// (Apache-2.0 projects; this file is an independent re-statement of it).
/// Int64 ids (source ids, tracker media ids) are strings so they survive
/// dart2js, where `int` is a 53-bit double.
library;

/// A parsed backup.
class BackupData {
  /// Creates a backup.
  const BackupData({
    required this.manga,
    required this.categories,
    required this.sources,
  });

  /// Every manga record, library entries and history-only ones alike.
  final List<BackupManga> manga;

  /// Library categories.
  final List<BackupCategory> categories;

  /// Source id to name table written by Tachiyomi.
  final List<BackupSource> sources;
}

/// `BackupManga`.
class BackupManga {
  /// Creates an empty manga record, filled in by the decoder.
  BackupManga();

  /// Tachiyomi's numeric source id (decimal string).
  String sourceId = '0';

  /// Source-relative manga url.
  String url = '';

  /// Title as reported by the source.
  String title = '';

  /// Author, if known.
  String? author;

  /// Cover url as reported by the source.
  String? thumbnailUrl;

  /// Time added to the library, epoch milliseconds (0 = unknown).
  int dateAdded = 0;

  /// False for history-only records that are not in the library. Protobuf
  /// omits defaults, so an absent field means true.
  bool favorite = true;

  /// Last modification, epoch seconds (0 = unknown).
  int lastModifiedAt = 0;

  /// SY: user-set title override.
  String? customTitle;

  /// SY: user-set cover override.
  String? customThumbnailUrl;

  /// SY: user-set status override.
  int customStatus = 0;

  /// SY: true when an E-Hentai style flat metadata blob was present.
  bool hasFlatMetadata = false;

  /// Publication status code.
  int status = 0;

  /// Genre tags.
  final List<String> genres = [];

  /// Category *orders* (not ids) this manga belongs to.
  final List<int> categories = [];

  /// Chapters known to the backup.
  final List<BackupChapter> chapters = [];

  /// Tracker bindings.
  final List<BackupTracking> tracking = [];

  /// Per-chapter read history.
  final List<BackupHistory> history = [];

  /// SY: merged-manga references.
  final List<BackupMergedReference> mergedReferences = [];
}

/// `BackupChapter`.
class BackupChapter {
  /// Source-relative chapter url.
  String url = '';

  /// Display name.
  String name = '';

  /// Whether the chapter is marked read.
  bool read = false;

  /// Last page opened (0-based).
  int lastPageRead = 0;

  /// Parsed chapter number; negative when unknown.
  double number = 0;

  /// Source order (0 = newest).
  int sourceOrder = 0;
}

/// `BackupCategory`.
class BackupCategory {
  /// Display name.
  String name = '';

  /// Sort order; manga reference categories by this value.
  int order = 0;

  /// Tachiyomi's database id (0 in old backups).
  int id = 0;
}

/// `BackupTracking`.
class BackupTracking {
  /// Tracker id: 1 MAL, 2 AniList, 3 Kitsu, 4 Shikimori, 5 Bangumi, 6 Komga,
  /// 7 MangaUpdates, 8 Kavita, 9 Suwayomi, 60 MDList.
  int syncId = 0;

  /// Remote media id (decimal string), `0` when unlinked.
  String mediaId = '0';

  /// Remote page url.
  String trackingUrl = '';

  /// Title on the tracker.
  String title = '';

  /// Highest chapter read according to the tracker.
  double lastChapterRead = 0;
}

/// `BackupHistory`.
class BackupHistory {
  /// Chapter url.
  String url = '';

  /// Last read time, epoch milliseconds.
  int lastRead = 0;
}

/// `BackupSource`.
class BackupSource {
  /// Creates a source record.
  const BackupSource(this.name, this.sourceId);

  /// Source name at backup time.
  final String name;

  /// Numeric source id (decimal string).
  final String sourceId;
}

/// SY `BackupMergedMangaReference`.
class BackupMergedReference {
  /// Whether this is the info manga of the merge.
  bool isInfoManga = false;

  /// Url of the merged manga.
  String mangaUrl = '';

  /// Source id of the merged manga (decimal string).
  String mangaSourceId = '0';
}
