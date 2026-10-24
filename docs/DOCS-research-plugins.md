# Research: JS plugins (Mangayomi format + Flutter JS engines)

Feeds `lib/plugins/runtime/` and `lib/plugins/mangayomi/` (contracts §6).
Researched 2026-10-24. Every claim links a file at a fixed commit.

Pinned commits used below:

| Repo | Commit | Licence |
|---|---|---|
| [kodjodevf/mangayomi](https://github.com/kodjodevf/mangayomi) (app) | `144961a6` (2026-10-23) | Apache-2.0 |
| [kodjodevf/mangayomi-extensions](https://github.com/kodjodevf/mangayomi-extensions) | `6004f1f8` (**archived** 2025-10-01) | Apache-2.0 |
| [entityJY/mangayomi-extensions-eJ](https://github.com/entityJY/mangayomi-extensions-eJ) (hosts every JS manga source) | `f21a60bf` (last push 2026-01-08) | Apache-2.0 |

## 1. Repo index

- Manga index: `https://kodjodevf.github.io/mangayomi-extensions/index.json`
  (novel: `novel_index.json`; anime index is commented out in the
  [README](https://github.com/kodjodevf/mangayomi-extensions/blob/6004f1f8d1a56f882dadb734ce26f50c626a3850/README.md)).
  Still served even though the repo is archived.
- Shape: a JSON **array** of source objects, one per (source, lang):
  `name, id (int), baseUrl, lang, typeSource, iconUrl, dateFormat,
  dateFormatLocale, isNsfw, hasCloudflare, sourceCodeUrl, apiUrl, version,
  isManga, itemType (0 manga), isFullData, appMinVerReq, additionalParams,
  sourceCodeLanguage (0 = Dart/dart_eval, 1 = JavaScript), notes`.
- Snapshot 2026-10-24: 363 entries. 249 are Dart (cannot be converted) and
  114 are JS. The 114 JS entries come from only **19 distinct `.js` files**,
  because MangaDex alone has 45 language entries. Two index URLs are dead
  (`en/mangapill.js` and `en/readcomiconline.js` return 404). All JS
  `sourceCodeUrl`s point at entityJY's fork, `raw.githubusercontent.com/.../main/...`.
  That is an unpinned branch, so the converter should record the sha256 of
  the fetched file.
- **Overlap with kuhy's library**: the SY backup's favourite sources are
  AllManga, MangaDex, MangaDot, Cyanide & Happiness, E-Hentai, Gone with the
  Blastwave and one unnamed source. Of these, **only MangaDex** has a JS
  Mangayomi source, and MangaDex is a native Kartka source anyway. Done #5
  ("install a converted plugin and read with it") can therefore be shown
  with any working JS source (e.g. `en/weebcentral.js`), but it does not
  serve any kept library source. AllManga (381 favourites) needs Suwayomi
  (Keiyoushi `en.allanime`).

## 2. Extension file structure

An example is
[`weebcentral.js`](https://github.com/entityJY/mangayomi-extensions-eJ/blob/f21a60bf026dd122f9b80042e1c3d220a38aa07a/javascript/manga/src/en/weebcentral.js):

```js
const mangayomiSources = [{ "id": 693275080, "name": "Weeb Central", "lang": "en",
  "baseUrl": "https://weebcentral.com", "apiUrl": "", "iconUrl": "...",
  "typeSource": "single", "itemType": 0, "version": "0.1.0",
  "pkgPath": "manga/src/en/weebcentral.js" }];
class DefaultExtension extends MProvider { /* methods below */ }
```

- The file is a script, not a module. The host evaluates it, then runs
  `var extention = new DefaultExtension();` (sic). See
  [`service.dart` L92-L96](https://github.com/kodjodevf/mangayomi/blob/144961a633f4040083ff3e39fdec0131164b1edc/lib/eval/javascript/service.dart#L92-L96).
- `this.source` is a getter the host injects into `MProvider`. It returns
  the index entry as JSON (`baseUrl`, `apiUrl`, `lang`, `id`, ...).
- `mangayomiSources` is metadata for the index generator. The runtime
  ignores it. The converter should read it to build the Kartka manifest
  (`id → plugin:<id>`, name, lang, baseUrl, version).

## 3. `MProvider` methods (the host's base class)

The stub is defined in
[`service.dart` L40-L86](https://github.com/kodjodevf/mangayomi/blob/144961a633f4040083ff3e39fdec0131164b1edc/lib/eval/javascript/service.dart#L40-L86),
and its semantics are in
[CONTRIBUTING-JS.md](https://github.com/kodjodevf/mangayomi-extensions/blob/6004f1f8d1a56f882dadb734ce26f50c626a3850/CONTRIBUTING-JS.md).

| Mangayomi method | Returns | Kartka §6 mapping |
|---|---|---|
| `async getPopular(page)` (page from 1) | `{list:[{name,imageUrl,link}], hasNextPage}` | `popular(page)` → `SearchPage` |
| `async getLatestUpdates(page)` | same | `latest(page)` |
| `async search(query, page, filters)` | same | `search(q, page)`, passing `getFilterList()` defaults as `filters` |
| `async getDetail(url)` | `{title?, imageUrl?, description, author, artist?, genre[], status 0-5, chapters:[{name,url,dateUpload(ms string),scanlator}]}` | **both** `details(url)` and `chapters(url)`. Cache one call per url. |
| `async getPageList(url)` | `string[]` or `[{url, headers}]` | `pages(url)` → `PageRef` |
| `getHeaders(url)` (sync) | header map | merged into every `PageRef.headers` and image fetch |
| `supportsLatest` (getter) | bool | hides "Latest" when false |
| `getFilterList()` (sync) | filter descriptors | default state only (no filter UI in v1) |
| `getSourcePreferences()` (sync) | preference descriptors | defaults seeded into `kartka.prefs` |
| `getVideoList`, `getHtmlContent`, `cleanHtmlContent` | anime/novel only | not mapped |

Status ints are `0 ongoing, 1 complete, 2 hiatus, 3 canceled,
4 publishingFinished, 5 unknown`. CONTRIBUTING-JS documents list items as
`{url, name, link}`, but every real source emits `{name, imageUrl, link}`,
with `link` as the manga url and `imageUrl` as the cover. The converter
should accept both forms.

## 4. Host APIs a Mangayomi extension calls

These are installed by the files in
[`lib/eval/javascript/`](https://github.com/kodjodevf/mangayomi/tree/144961a633f4040083ff3e39fdec0131164b1edc/lib/eval/javascript):

- **`Client`** ([http.dart](https://github.com/kodjodevf/mangayomi/blob/144961a633f4040083ff3e39fdec0131164b1edc/lib/eval/javascript/http.dart)):
  `new Client(reqcopyWith?)`, then `await get|head(url, headers)` or
  `await post|put|delete|patch(url, headers, body)`. The response is
  `{body, statusCode, headers, isRedirect, reasonPhrase, request:{url,...}}`
  ([http_response_extensions.dart](https://github.com/kodjodevf/mangayomi/blob/144961a633f4040083ff3e39fdec0131164b1edc/lib/eval/http_response_extensions.dart)).
  A JSON body is sent only when `Content-Type` contains `application/json`.
  This maps onto `kartka.http.get/post`. `put/patch/delete/head` need either
  a §6 extension or the `post` path with a method field.
- **`Document` / `Element`** ([dom_selector.dart](https://github.com/kodjodevf/mangayomi/blob/144961a633f4040083ff3e39fdec0131164b1edc/lib/eval/javascript/dom_selector.dart)):
  stateful handles with **synchronous** calls: `selectFirst, select, xpath,
  xpathFirst, attr, hasAttr, getElementsByTagName/ClassName/Id` plus the getters
  `text, innerHtml, outerHtml, children, parent, nextElementSibling,
  previousElementSibling, className, localName, getSrc, getHref, getImg,
  getDataSrc, body, head, documentElement`.
- **`SharedPreferences`** ([preferences.dart](https://github.com/kodjodevf/mangayomi/blob/144961a633f4040083ff3e39fdec0131164b1edc/lib/eval/javascript/preferences.dart)):
  sync `get(key)`, `getString(key, def)`, `setString(key, val)`. These map onto
  `kartka.prefs`.
- **Utils** ([js_common.dart](https://github.com/kodjodevf/mangayomi/blob/144961a633f4040083ff3e39fdec0131164b1edc/lib/eval/javascript/js_common.dart),
  [utils.dart](https://github.com/kodjodevf/mangayomi/blob/144961a633f4040083ff3e39fdec0131164b1edc/lib/eval/javascript/utils.dart)):
  `console.log/warn/error`; `String.prototype.substringAfter/AfterLast/Before/
  BeforeLast/Between`; `cryptoHandler, encryptAESCryptoJS, decryptAESCryptoJS,
  decryptAESGCM, deobfuscateJsPassword, unpackJs, unpackJsAndCombine,
  parseDates, evaluateJavascriptViaWebview, createHlsProxyUrl, parseEpub*`.

Measured usage across all 19 JS manga files (`grep -l`, entityJY `f21a60bf`):

| Feature | Files | Shim plan |
|---|---|---|
| `new Document` | 14 | In-JS HTML parser (§6 below) |
| `getFilterList` | 17 | Call it in JS, pass defaults |
| `SharedPreferences` | 13 | Snapshot prefs into JS at load; `setString` writes through async |
| `substringAfter/Before/Between` | 2 | Pure JS polyfill (trivial, write fresh) |
| `atob/btoa` | 2 | Polyfill (QuickJS has none) |
| AES helpers | 1 | Out of v1: that plugin is unsupported |
| sibling/parent/children navigation | 1 | Supported only with the in-JS DOM |
| `xpath`, `unpackJs`, `parseDates`, webview eval | 0 | Out of v1 |

**Gap against contract §6:** `kartka.html.select(html, css)` is stateless and
returns `[{text, attrs, html}]`. That is enough for `select` and `selectFirst`
by re-selecting on each element's `html`, but not for `parent` or siblings,
and every nested select costs a host round trip. On the web worker it **cannot
be synchronous** at all (see §6). Recommendation for the coordinator: ship a
small MIT HTML parser + CSS selector bundle (`node-html-parser` 9.0.5, MIT,
deps `css-select` BSD-2 + `entities` BSD-2) in the plugin prelude. Then
implement both `kartka.html.select` and the Mangayomi `Document` shim in JS,
with identical behaviour on QuickJS and in the browser. This would be a §6
contract change (html becomes an in-runtime JS lib, not a host call).

## 5. Licence verdict

- All three repos are **Apache-2.0** (GitHub licence API + LICENSE files). None
  has a NOTICE file (`gh api .../contents/NOTICE` returns 404 for all three).
- **A compatible shim written from the documented interface is fine.** That
  means CONTRIBUTING-JS plus the method and field names above. Interface
  names and JSON shapes are not the copyrighted expression. Write the shim's
  JS fresh. Do not paste the bootstrap strings from `service.dart`,
  `http.dart`, `dom_selector.dart` or `js_common.dart`.
- If code *is* copied (any of those strings, or a whole extension file),
  Apache-2.0 §4 applies. Ship a copy of the licence, keep the copyright
  notices, and mark modified files as changed. Apache-2.0 is compatible with a
  private MIT/Apache Kartka repo. It is not compatible with GPLv2-only, which
  Kartka does not use.
- Converting a downloaded extension on the user's device is not
  redistribution. **Publishing** a repo of converted plugins is
  redistribution. Each file then needs its original header/attribution, the
  Apache licence text, and a "converted by Kartka" change note. This is
  ⚠️ ask-first per SPEC anyway (publishing).
- Not legal advice. This is the reading the SPEC's 🚫 "check licence before
  vendoring" rule asked for.

## 6. Engines

Pub data from `pub.dev/api/packages/<p>` and `/score` (2026-10-24). "Resolves"
means `flutter pub get` succeeded with the exact pin under Flutter **3.47.7**
/ Dart 3.13.5 in a scratch app (`~/data/kartka/scratch/engines/`). **No APK
was built** because of the 60 s action cap, so build compatibility is
unverified for every row.

| Package | Latest | Engine / build | Android ABIs | Async + host fns | Web | Notes |
|---|---|---|---|---|---|---|
| [`fjs`](https://github.com/fluttercandies/fjs) (MIT) | **3.3.2**, 2026-09-30 | QuickJS via Rust (rquickjs + flutter_rust_bridge, Cargokit). Builds from source when `rustup` is present (it is: `/usr/bin/rustup`), otherwise downloads signed prebuilt binaries | follows Flutter target platforms (arm, arm64, x64) | `await fjs.bridge_call(v)` → async Dart handler; ES modules; `evalWithOptions(withPromise)`; memory/stack limits; `close()` cancels in-flight work | no | Resolves. Builtins (`fetch`, `fs`, `process`, ...) are opt-in flags. README: "not a hostile-code sandbox". |
| [`flutter_js`](https://github.com/abner/flutter_js) (MIT) | 0.8.7, 2026-01-27 | QuickJS on Android, pulled as a **prebuilt `.so` from JitPack** (`fastdev-jsruntimes-quickjs:0.3.6`, runtime repo last pushed 2025-09) | armeabi-v7a, arm64-v8a, x86, x86_64 | sync `sendMessage`/`onMessage`, `evaluateAsync` + `handlePromise`, built-in fetch/xhr | no | Resolves. Synchronous FFI on the calling isolate. Old QuickJS. Adds a JitPack Maven dep. |
| [`kodjodevf/flutter_qjs`](https://github.com/kodjodevf/flutter_qjs) (MIT, git only, `version: 0.0.1`) | commit `b64d2e3a` 2026-10-08 | QuickJS (ES2023) compiled from C by **native-assets hooks** (`hooks`, `native_toolchain_c`) | whatever the NDK hook builds | flutter_js-compatible API (sync `onMessage`, `evaluateAsync`, `handlePromise`) | no | **What Mangayomi actually ships** ([pubspec L71-L74](https://github.com/kodjodevf/mangayomi/blob/144961a633f4040083ff3e39fdec0131164b1edc/pubspec.yaml#L71-L74)). The freshness gate would need a commit pin (gitcommit ecosystem). |
| [`flutter_qjs`](https://github.com/ekibun/flutter_qjs) on pub (MIT) | 0.3.7, **2022-05-19** | QuickJS FFI | - | `IsolateQjs` | no | Resolves, but 4 years stale on pub. Do not confuse it with the kodjodevf fork. |
| [`js_interpreter`](https://github.com/kodjodevf/js_interpreter) (MIT) | 0.0.5, 2026-05-15 | **pure Dart** tree-walking interpreter | n/a | `sendMessage` sync + `sendMessageAsync` | **yes** | Resolves. One engine everywhere, but 66 downloads/30 d, unproven speed and conformance. Fallback only. |

**Recommendation: `fjs` 3.3.2 (exact pin) on Android**, behind a thin
`PluginEngine` interface:

1. It is the only pub-pinned, actively released QuickJS binding (newest
   stable, so the freshness gate is easy).
2. Its async-only bridge is not a drawback once HTML parsing lives in the JS
   prelude. `kartka.http`, `kartka.prefs.set` and `kartka.log` are naturally
   async. `prefs.get` is served from a snapshot injected at load.
3. Builtins can be switched off (`JsBuiltinOptions` with `fetch:false,
   fs:false, process:false`), so a plugin cannot bypass `kartka.http`. It
   has memory and stack limits, and `close()` gives cancellation.
4. Fallback if the arm64 build fails: the `kodjodevf/flutter_qjs` commit pin
   (same engine family, battle-tested on exactly these extensions).

**First red check for the implementer:** in a probe app, run
`~/.claude/scripts/capped.sh fvm flutter build apk --debug --target-platform android-arm64`
with `fjs: 3.3.2`. That proves the Cargokit/NDK path works on this machine.
Then evaluate `await fjs.bridge_call(...)` from a plugin on the Pixel 6a.

## 7. Web: plugin JS in a worker

- **No DOM in workers.** `DOMParser` is `[Exposed=Window]` in the
  [HTML spec](https://html.spec.whatwg.org/multipage/dynamic-markup-insertion.html#domparser),
  and MDN: "you can't directly manipulate the DOM from inside a worker"
  ([Using web workers](https://developer.mozilla.org/en-US/docs/Web/API/Web_Workers_API/Using_web_workers)).
  So the worker needs the bundled JS HTML parser (§4), the same one QuickJS uses.
- **Workers have `fetch`, XHR, WebSocket, IndexedDB and `importScripts`**
  ([MDN list](https://developer.mozilla.org/en-US/docs/Web/API/Web_Workers_API/Functions_and_classes_available_to_workers)).
  A same-origin worker can therefore read Kartka's IndexedDB, which is where
  web OAuth tokens live. Shadowing globals (`self.fetch = undefined`) is
  **not** a security boundary.
- **CSP**: a worker loaded from a URL gets the CSP of *its own* response
  headers. A `blob:`/`data:` worker inherits its creator's CSP
  ([MDN, CSP section](https://developer.mozilla.org/en-US/docs/Web/API/Web_Workers_API/Using_web_workers#content_security_policy)).
- **Proposed sandbox** (to verify with a red check: a plugin calling `fetch()`
  or `indexedDB.open()` must fail):
  1. The desktop wrapper serves `/plugin-host.html` with
     `Content-Security-Policy: default-src 'none'; script-src 'self' 'unsafe-eval' blob:; worker-src blob:; connect-src 'none'`.
  2. The app embeds it as a hidden `<iframe sandbox="allow-scripts">`
     appended to `document.body` via `package:web`. There is no
     `allow-same-origin`, so the frame has an **opaque origin** with no
     access to the app's storage or cookies.
  3. The iframe spawns a `blob:` worker (it inherits `connect-src 'none'`),
     loads prelude + plugin with `new Function`, and relays messages.
  4. The bridge is a `MessageChannel`. Dart side: `dart:js_interop` +
     `package:web` (`HTMLIFrameElement`, `MessagePort.postMessage(jsify)`),
     with each request `{id, op, args}` answered by `{id, ok|err}`. Host
     ops (`http`, `prefs`, `log`) run in Dart and go through `KartkaHttp`
     → wrapper `/proxy`.
  5. Timeout: `worker.terminate()` after N s per call, which is the hard
     kill QuickJS-side `close()` mirrors.
  - Alternative if opaque-origin workers misbehave: serve the plugin host
    from a **second origin** (`http://localhost:<port>` vs the app's
    `http://127.0.0.1:<port>`: same server, different origin, separate
    storage).
