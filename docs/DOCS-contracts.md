# Kartka — contracts between parts

Every part codes against these. Changing one is a coordinator decision; note
the change here in the same commit. §10-§15 (service lookup, sync clocks,
decisions log, foundation as built, integration) are in
[`DOCS-contracts-runtime.md`](DOCS-contracts-runtime.md); §5 (source health) is in
[`DOCS-contracts-source-health.md`](DOCS-contracts-source-health.md).

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

`ScreenObserver` (`lib/app/screen_observer.dart`) is a port a feature offers
as a service. The shell's `reportScreens()` sends the top go_router route
PATTERN (`/read/:sourceId/:mangaUrl/:chapterUrl`, `?` when unknown), never
the concrete path, to every `ScreenObserver` service, once per change.
`JankTracker` (`lib/perf/`) is one.

## 4. Sync model (RTDB root `/kartka/`, via crdt_sync_flutter)

| Path | Value | Merge |
|---|---|---|
| `library/<mangaKeyHash>` | `{key, title, coverUrl, sourceId, addedAt, removed}` | LWW per field |
| `categories/<id>` | `{name, order, removed}` | LWW per field |
| `membership/<mangaKeyHash>/<categoryId>` | `bool` | LWW |
| `progress/<mangaKeyHash>` | `{chapterNumber, chapterUrl, page, readAt, pageCount?}` | max(chapterNumber, page); never decreases |
| `trackers/<mangaKeyHash>/<service>` | `{remoteId, lastPushedChapter}` | max |
| `source_health/<sourceIdHash>` | §5 record, written by the evaluator only | evaluator wins |
| `source_health_meta` | §5 run meta (counts, verdicts, skipped candidates), evaluator only | evaluator wins |
| `settings/<key>` | `{key, value}` or `{key, enc}`, plus `hlc` (§16) | LWW per key |

`mangaKeyHash` = lowercase hex SHA-1 of `MangaKey` (RTDB-safe key).
Read chapters set = derived from progress + explicit per-chapter marks in
`read/<mangaKeyHash>/<chapterUrlHash>: {read: bool, at: ms}` (LWW per chapter, so
markUnread is a `read: false` tombstone).

## 5. Source-health record (evaluator → RTDB → app UI)

Moved to [`DOCS-contracts-source-health.md`](DOCS-contracts-source-health.md)
(record fields incl. `pagesLoad` and `langScope`, score, verdict rule, the
`source_health_meta` run-meta node).

## 6. Plugin API v1 (`lib/plugins/runtime/`)

A plugin is one JS file plus a manifest
`{id, name, version, lang, baseUrl, apiVersion: 1, icon?}`, hosted in a repo
whose `index.json` lists manifests + file URLs (Tachiyomi-repo style). The
plugin defines `popular(page)`, `latest(page)`, `search(query, page)`,
`details(url)`, `chapters(url)`, `pages(url)` returning §1 shapes as JSON.
The host exposes only `kartka.http.get/post(url, {headers, body})`,
`kartka.html.select(html, css)` → `[{text, attrs, html}]`, `kartka.log()`,
`kartka.prefs.get/set`, plus `kartka.html.parse(html)` (sync; a bundled MIT
node-html-parser root, so shims can build a DOM in JS) and `atob`/`btoa`
polyfills. `http.*` and `prefs.*` return Promises. No filesystem, no eval of
fetched code. The Mangayomi
converter wraps a Mangayomi JS extension in a shim that maps its `MProvider`
methods to these six.

## 7. Platform seam (`lib/platform/`)

`KartkaHttp`, `BlobStore` (downloaded pages: files on Android, IndexedDB or
wrapper files on web), `KeyValueStore`, `FilePicker` (CBZ import),
`OAuthRedirect` (Android deep link `kartka://oauth`, web
`http://127.0.0.1:<wrapperPort>/oauth`).

`KartkaPlatform.diagnostics` is a `BlobStore` a PC can pull: the Android
app-specific external files dir (`adb pull`, no root), the wrapper's
`/files` root on web. Every part logs through the one shared
`DiagnosticsLog.of(platform.diagnostics)` (`lib/core/diagnostics/`):
redacted JSON lines, rolling at 1 MB / 2000 entries, at
`diagnostics/kartka-diagnostics.jsonl`. Pull: `tools/phone/pull_diagnostics.sh`.
The same store holds the pre-migration library snapshots
(`backups/kartka-backup-<UTC>.json`, `format: kartka-backup` v1; `adb pull`).

`KartkaPlatform.cache` (optional `BlobStore`) holds disposable blobs worth
keeping across launches: the app cache dir on Android (the OS may clear
it), the wrapper's `/files` root on web. `CoverCache`
(`lib/platform/cover_cache.dart`) keeps covers there under
`cache/covers/<sha1(url)>`, behind a memory LRU; the library registers one
shared instance and Browse uses it (`registry.maybe<CoverCache>()`).

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
Stream<bool>` (tracking-anilist supplies from TrackingService bindings),
`LibraryUpdater` (updates supplies: one shared "update all" run, a
`Listenable` with `progress` and `updateAll() → UpdateSummary`; no
updater hides the Library refresh action and pull).

Updates feed (`lib/updates/`, the Updates tab): browse's `ChapterStore`
tells every `ChapterAdditionSink` (`lib/core/updates/`) the chapters a
fetch added to a list stored before, whichever path fetched (detail open,
`ChapterUpdateChecker`, reader, resolver); a first fetch is a baseline and
reports nothing. The feed is local (KV `updates.feed`, newest 500, 60
days), not synced. Update-all checks ≤ 4 manga at once, ≤ 1 per source,
≤ 2 per server (every `suwayomi:*` source is one server), and logs each
failure as it happens as `updates.check` (source id only, URLs stripped).
A network failure (lookup, reset/abort, timeout) is retried twice (1 s,
2 s); a server still unresolvable is not checked further: one
`updates.offline` entry, counted as "offline: N not checked", not failed.
