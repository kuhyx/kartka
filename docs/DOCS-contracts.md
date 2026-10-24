# Kartka — contracts between parts

Every part codes against these. Changing one is a coordinator decision; note
the change here in the same commit.

## 1. Core models (`lib/core/models/`, immutable, `==`/`hashCode`, JSON)

```dart
/// Stable across devices: '<sourceId>|<mangaUrl>'.
typedef MangaKey = String;

class SourceRef { String id; String name; String lang; SourceOrigin origin; }
enum SourceOrigin { native, suwayomi, plugin, local }
// Source ids: 'mangadex', 'local', 'suwayomi:<tachiyomiSourceId>',
// 'plugin:<pluginId>'. Suwayomi keeps Tachiyomi's numeric source ids, so a
// .tachibk entry maps to 'suwayomi:<id>' unless a native source claims it.

class MangaSummary { String sourceId; String url; String title; String? coverUrl; }
class MangaDetails extends MangaSummary {
  List<String> authors; String? description; List<String> genres;
  MangaStatus status; Map<String, String> trackerIds; // 'anilist' -> '123'
}
class ChapterInfo {
  String url; String name; double? number; DateTime? uploadedAt;
  String? scanlator;
}
class PageRef { int index; String imageUrl; Map<String, String> headers; }
class SearchPage { List<MangaSummary> items; bool hasNext; }
```

## 2. Source interface (`lib/core/source/manga_source.dart`)

```dart
abstract interface class MangaSource {
  SourceRef get ref;
  Future<SearchPage> popular(int page);
  Future<SearchPage> latest(int page);
  Future<SearchPage> search(String query, int page);
  Future<MangaDetails> details(String mangaUrl);
  Future<List<ChapterInfo>> chapters(String mangaUrl);
  Future<List<PageRef>> pages(String chapterUrl);
}
```

All HTTP goes through `lib/platform/http_client.dart` (`KartkaHttp`): Android
uses a direct client; web routes through the desktop wrapper's `/proxy` (CORS).
Sources never import `package:http` directly.

## 3. Feature registry (`lib/app/registry.dart`)

Each part exports one `KartkaFeature` (routes, settings tiles, sources it
provides) and appends ONE line to the list in `registry.dart`. Parts do not
edit each other's files.

## 4. Sync model (RTDB root `/kartka/`, via crdt_sync_flutter)

| Path | Value | Merge |
|---|---|---|
| `library/<mangaKeyHash>` | `{key, title, coverUrl, sourceId, addedAt, removed}` | LWW per field |
| `categories/<id>` | `{name, order, removed}` | LWW per field |
| `membership/<mangaKeyHash>/<categoryId>` | `bool` | LWW |
| `progress/<mangaKeyHash>` | `{chapterNumber, chapterUrl, page, readAt}` | max(chapterNumber, page); never decreases |
| `trackers/<mangaKeyHash>/<service>` | `{remoteId, lastPushedChapter}` | max |
| `source_health/<sourceIdHash>` | §5 record, written by the evaluator only | evaluator wins |

`mangaKeyHash` = lowercase hex SHA-1 of `MangaKey` (RTDB-safe key).
Read chapters set = derived from progress + explicit per-chapter marks in
`read/<mangaKeyHash>/<chapterUrlHash>: {read: bool, at: ms}` (LWW per chapter, so
markUnread is a `read: false` tombstone).

## 5. Source-health record (evaluator → RTDB → app UI)

```json
{
  "id": "suwayomi:2499283573021220255", "name": "MangaDex", "lang": "en",
  "origin": "suwayomi", "probedAt": "2026-10-24T12:00:00Z",
  "uptime": {"windowDays": 7, "probes": 28, "ok": 27, "ratio": 0.964,
             "status": "accruing|final"},
  "latencyMs": {"p50": 420, "p95": 1300},
  "blocking": {"challengeRate": 0.0, "kinds": ["cloudflare","captcha","403","429"]},
  "coverage": {"referenceSize": 650, "found": 512, "ratio": 0.788},
  "chapterCompleteness": {"sampled": 40, "medianRatio": 0.97},
  "imageQuality": {"sampledPages": 120, "medianWidthPx": 1100,
                   "medianJpegQuality": 88},
  "subsetOf": {"sourceId": "mangadex", "overlap": 0.93},
  "score": 0.81, "rank": 3,
  "verdict": "keep|cut|pending",
  "cutReasons": ["uptime<0.95", "blocking", "coverage<0.60", "subset"]
}
```

- **Reference set**: titles in the SY backup + AniList top 500 manga by
  popularity, stored at `tools/source_eval/data/reference.json`.
- **Chapter completeness**: source chapter count / AniList (fallback
  MangaUpdates) chapter count for sampled reference titles, capped at 1.
- **Subset**: ≥ 90 % of a source's found titles also found by a higher-ranked
  source with ≥ its image quality → `subsetOf` set, verdict `cut`.
- **Cut rules**: uptime ratio < 0.95 (only once `final`), challengeRate > 0,
  coverage < 0.60, subset. Otherwise `keep`; `pending` while uptime accrues.
- **Score**: 0.30 coverage + 0.20 completeness + 0.20 uptime + 0.15 image
  quality (width/1400 capped) + 0.15 latency (1 − p95/5000 capped at 0).
- Cadence: uptime probe 4×/day; full metrics weekly; both systemd timers on
  the server host. JSON also written to `tools/source_eval/out/latest.json`.

## 6. Plugin API v1 (`lib/plugins/runtime/`)

A plugin is one JS file plus a manifest
`{id, name, version, lang, baseUrl, apiVersion: 1, icon?}`, hosted in a repo
whose `index.json` lists manifests + file URLs (Tachiyomi-repo style). The
plugin defines `popular(page)`, `latest(page)`, `search(query, page)`,
`details(url)`, `chapters(url)`, `pages(url)` returning §1 shapes as JSON.
The host exposes only `kartka.http.get/post(url, {headers, body})`,
`kartka.html.select(html, css)` → `[{text, attrs, html}]`, `kartka.log()`,
`kartka.prefs.get/set`. No filesystem, no eval of fetched code. The Mangayomi
converter wraps a Mangayomi JS extension in a shim that maps its `MProvider`
methods to these six.

## 7. Platform seam (`lib/platform/`)

`KartkaHttp`, `BlobStore` (downloaded pages: files on Android, IndexedDB or
wrapper files on web), `KeyValueStore`, `FilePicker` (CBZ import),
`OAuthRedirect` (Android deep link `kartka://oauth`, web
`http://127.0.0.1:<wrapperPort>/oauth`).

## 8. Repositories (`lib/core/repositories/`, interfaces written by foundation; local impls by library part)

```dart
abstract interface class LibraryRepository {
  Stream<List<LibraryEntry>> watch();          // removed entries excluded
  Future<void> upsert(LibraryEntry e);          // LWW on updatedAt
  Future<void> remove(MangaKey key);
}
abstract interface class CategoryRepository {
  Stream<List<Category>> watch();
  Future<void> upsert(Category c);
  Future<void> setMembership(MangaKey key, String categoryId, bool member);
  Stream<Map<MangaKey, Set<String>>> watchMembership(); // true values only
}
abstract interface class ProgressRepository {
  Stream<ReadingProgress?> watch(MangaKey key);
  Future<void> record(ReadingProgress p);       // ignored if not > current
  Future<void> markRead(MangaKey key, String chapterUrl);
  Future<void> markUnread(MangaKey key, String chapterUrl);
  Stream<Set<String>> readChapters(MangaKey key);
}
abstract interface class DownloadRepository {   // owner: downloads part
  Future<void> enqueue(MangaKey key, ChapterInfo chapter);
  Stream<DownloadState> watch(MangaKey key, String chapterUrl);
  Future<List<PageRef>?> offlinePages(MangaKey key, String chapterUrl);
}
```

`LibraryEntry {key, sourceId, mangaUrl, title, coverUrl, addedAt, updatedAt,
removed}`, `Category {id, name, order, updatedAt, removed}`,
`ReadingProgress {key, chapterUrl, chapterNumber, page, readAt}` live in
`lib/core/models/`. Local impls are in-memory + KeyValueStore-backed; the sync
part decorates them (same interfaces), so UI never knows sync exists.
Tracking listens to `ProgressRepository.watch` — no direct coupling.

## 9. Tracker interface (`lib/tracking/common/tracker.dart`; owner: AniList part)

```dart
abstract interface class Tracker {
  String get id;                                   // 'anilist' | 'mal'
  String get name;
  Future<bool> isLoggedIn();
  Future<void> login();                            // via OAuthRedirect (§7)
  Future<void> logout();
  Future<List<TrackSearchResult>> search(String title);
  Future<TrackStatus?> fetch(String remoteId);
  Future<void> pushProgress(String remoteId, int chaptersRead); // never lowers
}
class TrackSearchResult { String remoteId; String title; String? coverUrl; int? chapters; }
class TrackStatus { String remoteId; int chaptersRead; int? totalChapters; String status; double? score; }
```

`TrackingService` (common) binds a `MangaKey` to `remoteId`s (stored in sync
path `trackers/`), listens to `ProgressRepository`, pushes `max(local, remote)`
and pulls remote progress forward into local on refresh.

Library-local ports (lib/library/, default no-op, real impls injected by their
owners via the registry): `UnreadCounts.watch(key) → Stream<int?>` (browse
supplies, from its chapter cache), `DownloadedLookup.hasDownloads(key) →
Stream<bool>` (downloads supplies), `TrackedLookup.isTracked(key) →
Stream<bool>` (tracking-anilist supplies from TrackingService bindings).

## 10. Service lookup, routes, keys (owner: foundation)

- `KartkaFeature` gets `List<Object> services` (default empty). Consumers ask
  `registry.all<T>()` / `registry.maybe<T>()`, which is how every port is supplied
  (SourceHealthLookup, UnreadCounts, DownloadedLookup, TrackedLookup,
  Tracker, MangaDetailSlot, ...). Ports live in the CONSUMER's dir;
  foundation never imports feature dirs.
- `lib/app/routes.dart`: `mangaRoute(sourceId, mangaUrl)`,
  `readRoute(sourceId, mangaUrl, chapterUrl)` + matching parsers;
  every segment is `Uri.encodeComponent`-encoded. Router: go_router (foundation pins it).
- `lib/core/models/manga_key.dart`: `MangaKey mangaKeyOf(String sourceId,
  String url)` and `String mangaKeyHash(MangaKey)` (sha1 hex, §4).

## 11. Blob page URLs and FilePicker (owner: foundation)

- A page stored in BlobStore is `PageRef(imageUrl: 'kartka-blob://<blobKey>',
  headers: {})`. Not `blob:`, which is the browser's object-URL scheme on web.
  `lib/platform/page_image.dart` (foundation) resolves either scheme:
  kartka-blob → BlobStore bytes, http(s) → KartkaHttp with headers. Reader,
  downloads and local all use it.
- `FilePicker.pickFiles({List<String> extensions, bool multiple})` and
  `FilePicker.pickDirectory()` return `List<PickedFile>`, where
  `PickedFile {String name; String? relativePath; Future<Uint8List> readBytes()}`.
  On web, directory picking uses webkitdirectory. Android path reads stay in
  lib/platform/io/.
