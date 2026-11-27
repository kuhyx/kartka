# In-app extensions (Android, contracts-runtime §18)

Kuhy's decision (2026-11-21, todo ff807202): the phone app is
self-sufficient. It installs and runs Keiyoushi (Tachiyomi) extensions
itself and never talks to a Suwayomi server. The desktop is a web build,
which cannot load APKs, so it keeps Suwayomi on its own machine
(`docs/DOCS-suwayomi.md`).

## Who decides which part runs

`suwayomiFeature` (`lib/sources/suwayomi/suwayomi_feature.dart`) checks
`KartkaPlatform.extensions`:

- **Android** (`ChannelExtensionRuntime`): `buildDeviceExtFeature`. The
  Suwayomi server URL setting is neither read nor contacted, and it no
  longer syncs (`settings_catalog.dart`), so the desktop's URL stays there.
- **Web** (null): `buildSuwayomiFeature`, as before.

Both register under feature id `source-suwayomi` and use the same source
ids `suwayomi:<Tachiyomi id>` and the same Tachiyomi manga and chapter
URLs. Library entries, history, tracking and `.tachibk` imports therefore
move between phone and desktop unchanged.

## Pieces

| Layer | Where | Does |
|---|---|---|
| Kotlin host API | `android/app/src/main/kotlin/eu/kanade/tachiyomi/` | Mihon's `source-api` + network (Apache-2.0, see `NOTICE`), KDoc stripped; what extension-lib 1.4-1.6 APKs link against |
| Loader | `.../com/kuhy/kartka/ext/ExtLoader.kt` | APK -> `filesDir/exts/<pkg>.ext`, read-only, `DelegateLastClassLoader`; refuses non-extensions, lib outside 1.4-1.6, and any signer but the trusted key |
| Injekt | `ExtHost.kt` | registers `Application`, `Context`, `NetworkHelper`, `Json` |
| Channel | `ExtChannel.kt`, `kartka/ext` | calls below, off the main thread; errors become `ext_error` |
| Dart seam | `lib/platform/extension_runtime.dart` | `ExtensionRuntime.invoke` / `image`; fake in `lib/platform/memory/` |
| Store | `lib/sources/device_ext/device_ext_api.dart` | Keiyoushi `index.pb` + APK download over `KartkaHttp`; implements the Install / Keep / auto-update ports and the extensions screen's `ExtensionCatalog` |
| Sources | `device_ext_source.dart`, `device_ext_feature.dart` | `MangaSource` per loaded source; provider re-lists after every change |

## Channel calls

| Method | Args | Result |
|---|---|---|
| `init` | `userAgent`, `trusted` (cert SHA-256 list) | `{installed: [ext], failed: {pkg: message}}`; loads every saved APK |
| `installed` | none | same as `init` |
| `install` | `apk` (bytes) | `ext` |
| `uninstall` | `pkg` | bool |
| `popular` / `latest` | `id`, `page` | `{mangas: [manga], hasNextPage}` |
| `search` | `id`, `page`, `query` | same; the source's default filters |
| `details` | `id`, `url`, `title?` | `manga` (`getMangaUpdate`, details only) |
| `chapters` | `id`, `url` | `[chapter]` (`getMangaUpdate`, chapters only) |
| `pages` | `id`, `url` | `[{index, url, imageUrl?}]` |
| `image` | `id`, `index`, `url`, `imageUrl?` | bytes, fetched with `HttpSource.getImage` |
| `cancelBackground` | none | count; cancels every call sent with `background: true` |

Downloads run inside `runAsBackground`, so each of their calls carries
`background: true`. A shown page that starts loading sends
`cancelBackground`; each cancelled call fails with code `cancelled`
(`ExtensionCallCancelled`), and the download engine runs it again after
the shown page is in, without spending a retry. Downloads in flight made
an open's page list and page 1 take about 1 s each instead of 0.2 s
(64f0bd6f).

`ext` = `{pkg, name, versionName, versionCode, nsfw, sources: [{id, name,
lang, supportsLatest, baseUrl}]}`. Source ids are strings: they exceed
2^53. `manga` = `{url, title, thumbnailUrl, author, artist, description,
genre, status}` (Tachiyomi status codes = `MangaStatus` order). `chapter`
= `{url, name, number, dateUpload, scanlator}`.

## Images

Covers and pages are `kartka-ext://source/<id>?i=<index>&u=<page url>&img=<image url>`
(`extImageUrl`). `PageImageLoader` sends them to `ExtensionRuntime.image`,
so the bytes come through the extension's own OkHttp client, with its
headers and interceptors (MangaFire descrambles images there). A loader
with no runtime (web) rejects the scheme.

## Store and trust

- Index: `https://github.com/keiyoushi/extensions/raw/repo/index.pb`, a
  gzipped protobuf (Mihon `NetworkExtensionStore`: field 101 list,
  extension fields 1 name, 2 package, 3 `{1 apkUrl, 2 iconUrl}`, 4 lib,
  5 versionCode, 6 versionName, 7 content warning, 8 sources
  `{1 id, 2 name, 3 lang}`). Read by `parseKeiyoushiIndex`. The legacy
  `index.min.json` lists only "update your app" stubs.
- Trust: the Kotlin loader takes the certificate SHA-256 list from Dart
  (`keiyoushiSigningKey`, from Keiyoushi's `repo.json`). An APK signed by
  anything else is refused before any of its code loads.
- Installed APKs stay in app-private storage. `adb install -r` keeps them;
  a `pm clear` would lose them (never done, see CLAUDE.md).

## Limits (known, 2026-11-21)

- No `JavaScriptEngine` (QuickJS) yet. An extension that needs it fails
  to load and is listed under `failed`.
- The host client mirrors Mihon's interceptor layout, because Keiyoushi's
  lib checks it by class name: `UncaughtExceptionInterceptor`,
  `UserAgentInterceptor`, `CloudflareInterceptor`; no `BrotliInterceptor`.
  It also calls `okhttp3.zstd.Zstd` (`okhttp-zstd`).
- `details` and `chapters` for one manga share one `getMangaUpdate` call
  (`ExtChannel.update`); extensions refuse two at once.
- Release builds: `scripts/check_ext_api_open.py` (build step `extapi`)
  fails when R8 made a host-API class or method final.
- No Cloudflare WebView solver: `CloudflareInterceptor` turns a challenge
  page into a clear error. Cookies are shared with
  the WebView cookie store, so a challenge solved in kartka's in-app
  WebView ("Open in WebView") applies to the extensions too.
- `NetworkHelper` sends kartka's honest User-Agent by default (CLAUDE.md).
  Extensions that set their own header keep it.
- Search uses the source's default filters. The type filters the Suwayomi
  part offers are not wired yet.
- Release builds: `android/app/proguard-rules.pro` keeps the public API of
  every library extensions call into. R8 cannot see those calls. Without
  the rules a release APK loads the extension and then fails with
  `NoSuchMethodError`.
