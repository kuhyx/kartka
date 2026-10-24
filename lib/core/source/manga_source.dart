import 'package:kartka/core/models/models.dart';

/// A place manga can be browsed and read from (DOCS-contracts §2).
///
/// Implementations do all network I/O through `KartkaHttp`
/// (`lib/platform/http_client.dart`) and never import `package:http`.
abstract interface class MangaSource {
  /// Identity of this source.
  SourceRef get ref;

  /// Popular titles, 1-based [page].
  Future<SearchPage> popular(int page);

  /// Recently updated titles, 1-based [page].
  Future<SearchPage> latest(int page);

  /// Titles matching [query], 1-based [page].
  Future<SearchPage> search(String query, int page);

  /// Full details of the manga at [mangaUrl].
  Future<MangaDetails> details(String mangaUrl);

  /// Chapters of the manga at [mangaUrl], newest first.
  Future<List<ChapterInfo>> chapters(String mangaUrl);

  /// Pages of the chapter at [chapterUrl], in reading order.
  Future<List<PageRef>> pages(String chapterUrl);
}
