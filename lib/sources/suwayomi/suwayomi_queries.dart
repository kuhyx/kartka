/// GraphQL documents sent to Suwayomi-Server (schema of v2.4).
///
/// Byte-identical to the ones in `test/fixtures/suwayomi/record.sh`; a test
/// compares every recorded fixture's query with these constants.
abstract final class SuwayomiQueries {
  /// Server name and version (connection test).
  static const about = 'query KartkaAbout { aboutServer { name version } }';

  /// Every installed source.
  static const sources =
      'query KartkaSources { sources { nodes '
      '{ id name lang displayName supportsLatest } } }';

  /// One page of POPULAR / LATEST / SEARCH results; registers the manga.
  static const sourceManga =
      r'mutation KartkaSourceManga($source: LongString!, '
      r'$type: FetchSourceMangaType!, $page: Int!, $query: String) '
      r'{ fetchSourceManga(input: {source: $source, type: $type, '
      r'page: $page, query: $query}) '
      '{ hasNextPage mangas { id url title thumbnailUrl } } }';

  /// Server-side id of the manga at `url` of `source`, if registered.
  static const mangaId =
      r'query KartkaMangaId($source: LongString!, $url: String!) '
      r'{ mangas(condition: {sourceId: $source, url: $url}, first: 1) '
      '{ nodes { id } } }';

  /// Refreshes and returns one manga's details.
  static const details =
      r'mutation KartkaDetails($id: Int!) { fetchMangaAndChapters(input: '
      r'{id: $id, fetchManga: true, fetchChapters: false}) { manga '
      '{ id url title thumbnailUrl author artist description genre status } '
      '} }';

  /// Refreshes and returns one manga's chapters.
  static const chapters =
      r'mutation KartkaChapters($id: Int!) { fetchMangaAndChapters(input: '
      r'{id: $id, fetchManga: false, fetchChapters: true}) { chapters '
      '{ id url name chapterNumber uploadDate scanlator sourceOrder } } }';

  /// Server-side ids of every chapter with `url` (any source).
  static const chapterId =
      r'query KartkaChapterId($url: String!) { chapters(condition: '
      r'{url: $url}) { nodes { id manga { sourceId } } } }';

  /// Page image paths of one chapter.
  static const pages =
      r'mutation KartkaPages($id: Int!) { fetchChapterPages(input: '
      r'{chapterId: $id}) { pages } }';

  static const _extensionFields =
      'pkgName name lang versionName iconUrl isInstalled hasUpdate isObsolete';

  /// Refreshes the extension list from the configured stores.
  static const extensions =
      'mutation KartkaExtensions { fetchExtensions(input: {}) '
      '{ extensions { $_extensionFields } } }';

  /// Installs, updates or uninstalls one extension (`id` is its pkgName).
  static const updateExtension =
      r'mutation KartkaUpdateExtension($id: String!, '
      r'$patch: UpdateExtensionPatchInput!) { updateExtension(input: '
      r'{id: $id, patch: $patch}) '
      '{ extension { $_extensionFields } } }';
}
