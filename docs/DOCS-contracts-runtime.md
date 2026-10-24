# Kartka — contracts, part 2 (runtime and decisions)

Continues [`DOCS-contracts.md`](DOCS-contracts.md) (§1-§9); same rules.

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

## 12. Sync clocks and DownloadState

- Sync (§4 refined): `library/<h>` and `categories/<id>` keep flat fields plus
  `hlc: {<field>: "<crdt_sync Hlc>"}`, merged as per-field LWW on Hlc (device id
  breaks ties). `membership/<h>/<cat>` and `read/<h>/<c>` are
  `{member|read: bool, hlc: "<Hlc>"}`, so every LWW node uses Hlc and no raw ms.
  `updatedAt` = max field Hlc millis. `progress/` and `trackers/` stay
  max-merge (a null chapterNumber sorts lowest). Change detection: tiny
  `revs/<deviceId>: "<counter>"`, polled every 5 s **only while the app is in
  the foreground**. Subtrees are fetched only when it changes. RTDB is reached
  with crdt_sync's own client (RTDB allows CORS, so no /proxy is needed).
- `DownloadState` (in `lib/core/models/download_state.dart`, foundation):
  `sealed class DownloadState` = `NotDownloaded | Queued |
  Downloading(done, total) | Paused(done, total) |
  Downloaded(pageCount, bytes) | DownloadFailed(message)`.

## 13. Decisions log (2026-10-24, coordinator)

- Hashed keys are not reversible, so nodes carry their keys: `read/<h>/<c>` =
  `{read, hlc, url}`, `membership/<h>/<cat>` = `{member, hlc, key}`, and
  `progress/<h>` gains `key`.
- DownloadState: foundation's `lib/core/models/download_state.dart` is the
  source of truth and overrides the §12 sketch. Pause is a queue-level flag.
- The desktop wrapper binds a fixed `127.0.0.1:47391`. OAuth web redirect is
  `http://127.0.0.1:47391/oauth`, Android `kartka://oauth`. AniList and MAL each
  get TWO clients (android + web). Client ids live in ONE file,
  `~/.config/kartka/oauth.json` (keys `KARTKA_{ANILIST,MAL}_CLIENT_ID_{ANDROID,WEB}`),
  passed with `--dart-define-from-file` by run.sh and the APK build.
- `/proxy`: real Kartka User-Agent, never a Via header, proxies images too.
- Tracking pull-forward uses the `ChapterUrlResolver` port (tracking/common,
  browse supplies it). A null result skips the pull.
- MangaDex URLs are Keiyoushi-compatible (`/manga/<uuid>`, `/chapter/<uuid>`),
  so .tachibk MangaDex entries map to `mangadex|/manga/<uuid>` unchanged.
- `dart_test.yaml` skips tag `live` (foundation).
- Sources are dynamic and supplied ONLY as `SourceProvider { Stream<List<MangaSource>> watch(); }`
  (+ `StaticSourceProvider`, lib/core/source/) through `KartkaFeature.services`.
  Browse's SourceRegistry merges them live.
- `ImageHeaders { Map<String,String> forUrl(String url); }` (lib/platform/) is
  merged into every image request by page_image and the cover widget, with
  PageRef headers winning. Credentials never go into synced URLs.
- Suwayomi entries the server has never seen are resolved by searching their
  title on that source and matching the exact url, then retrying. Kartka never
  restores the .tachibk into Suwayomi.
- Credentials (Suwayomi basic auth, OAuth tokens) go in `KartkaPlatform.secrets`:
  the Android Keystore, or on web a wrapper-held 0600 file in ~/.config/kartka/.
- Sync decorates repositories through the `RepositoryDecorator` port
  (lib/library/). Library's accessor applies every decorator lazily, and other
  parts get repos only from that accessor.
- **Suwayomi's future is decided by data (kuhy, 2026-10-24, option d):** keep
  the Suwayomi parts. Once the evaluator's first results are in, drop the Suwayomi
  client from the app if every `keep` source is available natively or as a JS
  plugin. Otherwise keep it, or port the missing source to a JS plugin.
  Building our own extension server is ruled out (it would be the fork again).

## 14. Foundation as built (agent/foundation @ 105b425, authoritative over §1-§3 sketches)

- `lib/app/registry.dart`: `kartkaFeatureFactories` is a `List<KartkaFeatureFactory>`,
  where `KartkaFeatureFactory = KartkaFeature Function(KartkaEnv env)`. `env.platform`
  is a KartkaPlatform; `env.registry` is late and read lazily. Parts export
  `KartkaFeature xFeature(KartkaEnv env) => KartkaFeature(...)` and append `xFeature,`.
- `KartkaFeature{id, routes: List<RouteBase>, tabs: Map<KartkaTab, WidgetBuilder>
  (library/browse/sources/more, first filler wins), settingsTiles, services}`.
  There is no `sources` field. `registry.all<T>()` / `maybe<T>()` live in lib/app/feature.dart.
- Dart 3.13 + very_good_analysis 11: constructors are declared `const new(...)` /
  `factory fromJson(...)`, and callers are unchanged.
- Use `hide Category` only on flutter/foundation.dart imports.
- setMembership keeps a positional bool, so implementers add
  `// ignore: avoid_positional_boolean_parameters`.
- `MangaStatus` uses Tachiyomi codes 0-6 in order. `DownloadState{status: DownloadStatus
  none|queued|downloading|done|failed, pagesDone, pagesTotal, error}`.
  `ReadingProgress.chapterNumber` is a non-null double, and `isAheadOf(other)` is THE
  never-decrease ordering. `mangaKeyHash()` also hashes chapterUrl and sourceId.
- `KartkaPlatform{http, blobs, kv, secrets, filePicker, oauth}`.
  `PageImageLoader(http, blobs, imageHeaders)`, `blobPageUrl(key)`, and
  `kartkaUserAgent` (http_client.dart).
- Repos: consumers NEVER use `registry.maybe<LibraryRepository>()`. They use
  library's accessor, which applies `RepositoryDecorator`s (§13).
- Accessors: `env.registry.maybe<LibraryRepositories>()` from
  `package:kartka/library/library_repositories.dart`, with getters `library`,
  `categories` and `progress`, each already decorated. `env.registry.maybe<DownloadRepository>()`
  is supplied only by downloads. `KartkaHttp.send(method, url, {headers, body})`
  covers PATCH/PUT/DELETE/HEAD, and /proxy forwards the method and body unchanged.
- `ProgressRepository.readMarks(key) → Stream<Map<String,bool>>` gives the explicit
  marks, with false as an unread tombstone. A chapter is READ if it is marked true,
  or if number ≤ progress.chapterNumber and it is not marked false (browse helper).
- Test fakes: `lib/platform/memory/memory_platform.dart` provides `memoryPlatform()`,
  `FakeKartkaHttp(handler)` (`.requests`, `.text(body, status:)`), MemoryBlobStore,
  MemoryKeyValueStore, FakeFilePicker and FakeOAuthRedirect (foundation @ 739e162).
  Parts use these and do not write their own.

## 15. Integration (coordinator, 2026-10-24; overrides older sketches)

- **Sync change feed (§12 as built).** Each push writes
  `log/<dev>/r<rev>` = the changed paths joined by `\n` (or `*` for > 500
  paths) in the same PATCH as `revs/<dev>`, and prunes `r<rev-50>`. A peer
  ≤ 50 revs behind fetches only the `r<k>` it needs, then ≤ 200 nodes;
  otherwise it does a full pull. Pushes go out in ≤ 1000-path chunks.
  Progress writes are coalesced for 3 s.
- **Sync node fields.** `read/` carries `key`; `library/` carries
  `mangaUrl`; `categories/` carries `id` (ids are encodeKey-escaped, `/` →
  `~2F`). `trackers/<h>/<service>` = `{key, service, remoteId, removed, hlc,
  pushed: {<remoteId>: n}, lastPushedChapter}`. Sync supplies
  `SyncRepositoryDecorator`, `SyncBindingDecorator` (tracking bindings) and
  `PollingRtdbReader` as `RtdbReader` (source health). Account page
  `/more/sync`: email/password (Google sign-in off).
- **Tracking counts finished chapters only** (`FinishedChapters`, Mihon
  rule): explicit read marks, floor of the highest such number. Opening a
  chapter never pushes.
- **Downloads cancel/delete**: consumers use
  `registry.maybe<DownloadService>()`
  (`package:kartka/downloads/download_service.dart`); §8 stays minimal.
- **Credential trackers** implement `CredentialsLogin { Future<void>
  showLogin(BuildContext) }` (`lib/tracking/common/credentials_login.dart`)
  beside `Tracker`. The track sheet calls `showLogin(context)` when
  `tracker is CredentialsLogin`, else `tracker.login()`. MangaUpdates shows
  its username + password sheet; AniList and MAL stay OAuth (§9 unchanged).
- **Android kv.json writes are coalesced.** `FileKeyValueStore` writes at
  most once per 250 ms window while sets keep coming (bounded latency, not
  a resetting debounce; `CoalescingSaver`, lib/platform/). `createPlatform()`
  wires `flushOnBackground(kv.flush)`, which flushes on every non-resumed
  `AppLifecycleState`, so a clean pause or detach loses nothing.
- **The wrapper never logs a /proxy target.** A query can carry a
  credential (RTDB `?auth=<token>`, forwarded byte-identical). A mid-body
  upstream cut is logged by error type only and no longer kills the
  wrapper; the generic error log scrubs every `?query`.
- **Every `SourceProvider` emits on subscribe**, even when it is
  unconfigured, offline or failing (`[]`, or the last good list), and never
  ends a subscription with only an error. `SourceAvailability` needs one
  emission per provider before any badge can show.
- **Chapter rows follow their `DownloadState`.** They offer download (or
  retry), cancel while queued or downloading, and delete once downloaded.
  Cancel and delete need `registry.maybe<DownloadService>()`.
- **Old MangaDex id `3091964041986261235`** (SY "MangaDex (Revived)") maps
  to native `mangadex` with URLs unchanged, like the current per-language ids.
