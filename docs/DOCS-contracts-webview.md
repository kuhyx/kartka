# Kartka — contract: browser engine and "Open in WebView"

Continues [`DOCS-contracts.md`](DOCS-contracts.md) and
[`DOCS-contracts-runtime.md`](DOCS-contracts-runtime.md); same rules. Approved
by kuhy 2026-10-25 (spec answers (i) + (ii), challenge policy below).

## 1. What it is

Two capabilities behind one platform service, `KartkaPlatform.browser`
(a `KartkaBrowser`, `lib/platform/browser_engine.dart`; optional, default
`UnavailableBrowser`, so existing constructions keep compiling):

- **(ii) headless engine**: `load(EngineRequest)` renders a page in a real
  browser engine and returns the HTML, the resource URLs the page requested
  and an optional page-supplied response string. Used by plugins
  (`kartka.browser.load`, Mangayomi `evaluateJavascriptViaWebview`) and by
  kartka's own sources.
- **(i) "Open in WebView"**: a user-facing browser on a source's site. kuhy
  logs in or solves a challenge himself; afterwards kartka's HTTP requests to
  that host carry the site's cookies.

## 2. Challenge policy (hard, DOCS-spec "Never")

The engine **never** solves, clicks, waits out or otherwise defeats a
Cloudflare / captcha / DDoS-Guard interstitial. On detection it stops and
throws `ChallengeRequired(url, kind)` (`lib/core/source/challenge.dart`).
The UI turns that into the "Open in WebView" prompt, and only kuhy solves it.
No browser UA is spoofed: the engine sends whatever the platform webview /
headless chromium naturally sends (`HeadlessChrome` included), and kartka's
own HTTP keeps the honest `kartkaUserAgent`.

Known limitation (by design, not a bug): Cloudflare binds `cf_clearance` to
the User-Agent that solved the challenge, and no two of these UAs match:
kartka's HTTP (`kartkaUserAgent`, also every plugin `kartka.http.*` call),
the desktop window (`Chrome/...`), the desktop engine (`HeadlessChrome/...`)
and the Android WebView. So a solved Cloudflare wall is not expected to
carry over, and a CF-walled HTTP plugin will prompt again. Login / session
cookies do carry over. Nothing here may be "fixed" by spoofing the UA.

Detection (`kind` values: `cloudflare`, `captcha`, `ddos-guard`):
- in the engine, on the rendered DOM (`engineProbeJs`): titles "Just a
  moment...", "Attention Required!", "DDoS-Guard"; `#challenge-form`,
  `#cf-challenge-running`, `iframe[src*="challenges.cloudflare.com"]`;
  `.cf-turnstile`, `.g-recaptcha`, `.h-captcha` (and their iframes) only
  on a near-empty page (< 3000 chars of text: a comment form's captcha is
  not a wall);
- on plain HTTP (`challengeKindOf(KartkaResponse)`, plugin `kartka.http.*`):
  a `cf-mitigated: challenge` header, or status 403/429/503 with one of the
  markers above (or `cf_chl_opt` / `/cdn-cgi/challenge-platform/`) in the
  body. A 200 page that merely mentions "captcha" is not a challenge.

## 3. Engine API (`lib/platform/browser_engine.dart`)

```dart
class EngineRequest { Uri url; Map<String, String> headers;
  List<String> scripts; String? waitFor; bool awaitResponse;
  Duration timeout; }                      // default 20 s, max 25 s
class EngineResult { Uri url; int? status; String html;
  List<String> resources; String? response; bool timedOut; }
abstract interface class KartkaBrowser {
  Future<EngineResult> load(EngineRequest request); // ChallengeRequired, EngineUnavailable
  bool get inApp;                     // Android: true; desktop: false
  Widget buildView(Uri url);          // in-app view (inApp only)
  Future<void> openExternal(Uri url); // desktop window (!inApp only)
  Future<void> finish(Uri url);       // user done: cookies now apply
  Widget host(Widget child);          // mounts hidden views (Android)
}
```

`load` semantics, identical on both seams because the loop is one pure-Dart
class (`EngineCore`, `lib/platform/engine_core.dart`) over a dumb per-page
driver (`EnginePage`: `navigate(url, headers)`, `evaluate(js)`, `close()`):

1. Only `http(s)` URLs to a non-loopback host, or `data:` URLs (a page on
   the wrapper's own origin could call its API with `x-kartka`). This holds
   for every document, not just the request: a probe reporting a forbidden
   `href` (an HTTP or JS redirect) fails the load before any script runs,
   and `about:` / `chrome-error:` documents (the pre-navigation page, an
   error page) are never ready. The wrapper also blocks loopback at the
   network level (§6).
2. Navigate with `headers` (no `User-Agent`: it is dropped).
3. Every 250 ms evaluate the probe. A challenge throws `ChallengeRequired`.
   Once `document.readyState == 'complete'` on a document the scripts have
   not run in yet, install the response hooks and run `scripts` in order
   (again after a navigation, like Mangayomi's `onLoadStop`).
4. Done when the scripts ran, `waitFor` (a CSS selector) matches, and, with
   `awaitResponse`, the page has delivered a response through
   `kartka.respond(string)` or Mangayomi's
   `window.flutter_inappwebview.callHandler('setResponse', string)`.
5. Then snapshot: `document.documentElement.outerHTML`, the resource URLs
   (`performance` resource entries ∪ `img[src]`, deduplicated, in order) and
   the navigation entry's `responseStatus`.
6. At the deadline the snapshot is returned with `timedOut: true` (a
   challenge still wins). Script return values are discarded.

## 4. Plugin host call (contracts §6 extension)

```text
kartka.browser.load(url, {headers?, scripts?, waitFor?, awaitResponse?,
                          timeoutMs?})
  -> Promise<{url, status, html, resources: [string], response, timedOut}>
```

Mangayomi shim (`lib/plugins/mangayomi/shim/runtime_js.dart`), matching
kodjodevf/mangayomi `db2f18e5` (`lib/eval/javascript/utils.dart`):

```text
evaluateJavascriptViaWebview(url, headers, scripts, time = 30) -> Promise<string>
```

It loads `url` with `headers`, runs `scripts`, waits up to `time` s (clamped
to 25 s, under the 30 s host-call timeout) for `setResponse`, and resolves
to that string, or `''` on timeout, as Mangayomi does. A challenge rejects.

A `ChallengeRequired` raised by any host call (engine or `kartka.http.*`)
reaches the UI typed: the session records it and the failing plugin call
throws `PluginChallengeException` (a `PluginException` that `implements
ChallengeRequired`), even if the plugin re-wrapped the error message.

## 5. Android (`lib/platform/io/webview_browser.dart`)

- `webview_flutter` (exact pin). `load`: a fresh `WebViewController` per
  call, mounted 1×1 px by `host()` (webview_flutter has no headless mode),
  JS enabled, disposed afterwards.
- `buildView`: the full-screen in-app WebView route, Done in the AppBar.
- Cookies: `finish(url)` adds the host to `WebViewHosts` (kv key
  `webview.hosts`). `CookieKartkaHttp` wraps the direct client; for a
  request to a listed host (or a subdomain) without a caller `Cookie`, it
  asks the WebView `CookieManager.getCookie(url)` (MethodChannel
  `kartka/webview_cookies` in `MainActivity`; raw header string, so values
  containing `=` survive and HttpOnly cookies are included).

## 6. Desktop (wrapper owns the engine)

The web build cannot script other origins, so the wrapper drives a
headless chromium over CDP. The app side is `WrapperBrowser`
(`lib/platform/wrapper_browser.dart`): `EngineCore` over HTTP pages.

| Route (all API: `x-kartka: 1`, Host/Origin checks, no CORS) | Effect |
|---|---|
| `POST /engine/page` | new page (CDP target) → `{"id"}` |
| `POST /engine/page/<id>/navigate` `{url, headers}` | navigate; 204 |
| `POST /engine/page/<id>/evaluate` `{expression}` | `{"value"}` or 422 `{"error"}` |
| `DELETE /engine/page/<id>` | close; 204 |
| `POST /engine/open` `{url}` | visible window; 202, 409 headless-only |
| `POST /engine/finish` `{url}` | close window, register host; 204 |

- Errors: 400 bad URL / body, 404 unknown page, 503 `{"error":
  "no-browser"}` when no chromium is found.
- Chromium: `$KARTKA_ENGINE_BROWSER`, else `/usr/bin/chromium` (the real
  binary, not the `/usr/local/bin` wrapper), else the app's browser list.
  Started lazily with `--headless=new --remote-debugging-port=0`; the port is
  read from `<profile>/DevToolsActivePort`; `DISPLAY` / `WAYLAND_DISPLAY`
  are removed from its environment. The wrapper attaches only when
  `/json/version` reports `HeadlessChrome`. Stopped with the wrapper
  (SIGINT/SIGTERM too). At most 8 pages; the oldest is closed first.
- Loopback block: every page intercepts (CDP `Fetch`, which unlike
  `Network.setBlockedURLs` also stops top-level navigations and redirects)
  and fails requests to the wrapper ports (47391 and its own) and, outside
  tests, to every loopback host.
- `open` holds an "opening" state from the moment it stops the engine:
  `/engine/page` answers 409 `window-open` and `/proxy` adds no cookies
  until `finish`, so nothing relaunches headless on the locked profile.
- Profile: `--engine-profile`, else `<parent of --files-dir>/engine-profile`:
  `~/.local/share/kartka-desktop/engine-profile` for the real app,
  `~/.local/share/kartka-agent/engine-profile` for the agent instance.
- (i): `open` stops the headless engine (the profile is locked by one
  process), then starts a visible `--app=<url>` window on the same profile,
  user-initiated only. With `--no-browser` (headless-only, the agent
  instance) it answers 409 and nothing visible ever starts. `finish` sends
  the window SIGTERM (chromium flushes cookies), waits for it, and registers
  the host in `<data dir>/engine-hosts.json`.
- `/proxy` to a registered host (or subdomain): the wrapper asks the
  headless engine (`Storage.getCookies`, matched to the target by domain,
  path, secure and expiry: `cookieHeaderFor`) and appends that to any
  page-supplied `cookie` header. Cookie values are never logged.
  Session cookies (no expiry) do not survive closing the window; persistent
  ones (most "remember me" logins) do.

## 7. UI

- `ChallengePrompt` (`lib/browse/ui/challenge_prompt.dart`) replaces the
  plain error in the browse grid footer and the detail screen when the error
  `is ChallengeRequired`: "This site wants a browser check", button "Open in
  WebView", then retry.
- `openInWebView(context, browser, url)`: in-app → pushes `buildView`;
  desktop → `openExternal` + a "Finish in the Kartka browser window" dialog.
  Both end with `finish(url)`.
- The source screen's AppBar shows "Open in WebView" when the source
  implements `WebViewTarget` (`lib/core/source/challenge.dart`;
  `PluginSource` does, from `manifest.baseUrl`).
