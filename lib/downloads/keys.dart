/// Storage keys and offline page URLs used by the downloads part.
///
/// Offline pages: every downloaded page is one BlobStore blob under
/// `downloads/<mangaKeyHash>/<chapterUrlHash>/<index:4>`, and
/// `DownloadRepository.offlinePages` returns
/// `PageRef(imageUrl: 'kartka-blob://<blobKey>', headers: {})`
/// (DOCS-contracts §11); `lib/platform/page_image.dart` resolves it.
library;

import 'package:kartka/core/models/manga_key.dart';

export 'package:kartka/platform/page_image.dart' show blobPageUrl;

/// KeyValueStore key of the persisted queue.
const queueKvKey = 'downloads/queue';

/// KeyValueStore key of the downloaded-chapter index.
const indexKvKey = 'downloads/index';

/// KeyValueStore key of the "auto-download new chapters" setting.
const autoDownloadKvKey = 'downloads/auto_new_chapters';

/// KeyValueStore key of the last auto-download check time (UTC ISO-8601).
const autoLastCheckKvKey = 'downloads/auto_last_check';

/// KeyValueStore key prefix of each manga's known chapter URLs.
const knownChaptersKvPrefix = 'downloads/known/';

/// The source id part of a `'<sourceId>|<mangaUrl>'` key.
String sourceIdOf(MangaKey key) {
  final bar = key.indexOf('|');
  return bar < 0 ? key : key.substring(0, bar);
}

/// Stable id of the task downloading [chapterUrl] of [key].
String taskId(MangaKey key, String chapterUrl) =>
    '${mangaKeyHash(key)}/${mangaKeyHash(chapterUrl)}';

/// Prefix shared by all page blobs of one chapter.
String chapterBlobPrefix(MangaKey key, String chapterUrl) =>
    'downloads/${taskId(key, chapterUrl)}/';

/// BlobStore key of page [index] of a chapter.
String pageBlobKey(MangaKey key, String chapterUrl, int index) =>
    '${chapterBlobPrefix(key, chapterUrl)}${index.toString().padLeft(4, '0')}';
