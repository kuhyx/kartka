# Suwayomi-Server for Kartka

Kartka's `suwayomi` source talks to a self-hosted
[Suwayomi-Server](https://github.com/Suwayomi/Suwayomi-Server). That server runs
Tachiyomi/Keiyoushi extensions on the JVM and serves a GraphQL API. Everything
below was checked against the running server on 2026-10-24 (v2.4.2366).

## Where it runs

| | |
|---|---|
| URL | `https://suwayomi.kuhy.duckdns.org` (GraphQL: `/api/graphql`, web UI: `/`) |
| Host | kuhy's desktop, the same 24/7 box that runs SyncYomi, gitea, endurain and searx |
| Process | systemd **user** unit `suwayomi.service` (linger on), `127.0.0.1:4567` only |
| Edge | the existing Caddy container `gitea-caddy`, snippet `~/services/gitea/sites/suwayomi.caddy` |
| Files | app `~/services/suwayomi/app/<version>` (`current` symlink), data `~/services/suwayomi/data` |
| Credentials | `~/.config/kartka/suwayomi.env` (0600, never committed) |
| Pin | `deploy/suwayomi/lib/common.sh`: `SUWAYOMI_VERSION` + `SUWAYOMI_SHA256` |

DNS comes from the `*.kuhy.duckdns.org` wildcard, the same one anki, endurain
and bot use, so the DuckDNS updater is left alone. TLS is Caddy's automatic
ACME.

## Install, update, verify

```bash
deploy/suwayomi/install.sh                # as kuhy, never under sudo
deploy/suwayomi/install.sh --verify-only  # end-to-end check, exit 0 = good
```

- **No root.** The release tarball bundles its JRE (25.0.4), so pacman is not
  needed. Linger is already on, and 80/443 are already open. The installer
  dies with the exact fix if linger is ever off.
- **Idempotent.** A rerun with nothing to change leaves the snippet and the env
  file byte-identical, does not reload Caddy and does not restart the unit.
- **To update**, bump `SUWAYOMI_VERSION` and `SUWAYOMI_SHA256` (the release's
  `Checksums.sha256`) and rerun. The old version dir stays as a rollback:
  point `current` back at it and `systemctl --user restart suwayomi`.
- **Edge safety.** The new snippet is checked with `caddy validate` before
  `caddy reload`. If validation fails, the old snippet is restored and the
  script stops. This edge serves every public service.
- **Loopback is enforced in the unit.** `-Dsuwayomi.tachidesk.config.server.ip=127.0.0.1`
  overrides `server.conf`. On the host the conf still says `0.0.0.0` and the
  socket is `127.0.0.1:4567`, so the override is what actually applies. The
  same flags also turn off the tray icon, the browser-on-start and KCEF
  (bundled Chromium; Kartka records a challenged source as blocking and never
  solves the challenge).
- `--verify-only` checks these, all live:
  - unit active and enabled, version and settings read back;
  - Keiyoushi store present;
  - `LAN-IP:4567` refused;
  - Caddy returns 401 with no credentials and with a wrong password, and 200
    with the right ones.

  It sends requests to `127.0.0.1:443` through `--resolve`, so it tests Caddy
  itself and not the router's hairpin NAT.

### Sandbox test (vmbox)

```bash
vm share ~/src/kartka-wt/suwayomi             # share BEFORE the guest first boots
vm new suwa
# seed the guest's download cache from the host's (skips a 337 MB download)
vm run suwa 'mkdir -p ~/.cache/kartka/suwayomi'
vm scp suwa ~/.cache/kartka/suwayomi/Suwayomi-Server-v2.4.2366-linux-x64.tar.gz .cache/kartka/suwayomi/
vm run suwa 'sudo pacman -Sy --noconfirm docker && sudo systemctl enable --now docker && sudo chmod 666 /var/run/docker.sock'
vm repo suwa ~/src/kartka-wt/suwayomi --worktree
vm run suwa 'bash ~/suwayomi/deploy/suwayomi/tests/vmbox_guest_edge.sh'
vm run suwa 'cd ~/suwayomi/deploy/suwayomi && SUWAYOMI_HOST=suwayomi.localhost VERIFY_INSECURE=1 ./install.sh && ./install.sh --verify-only'
```

The guest edge mirrors the host: caddy:2.8, host networking, a root Caddyfile
that only imports `sites/*.caddy`, and a neighbour site that has to keep
answering. These passed in vmbox: fresh install, verify, an idempotent rerun,
rollback of an invalid snippet (neighbour unaffected), and verify after a guest
reboot.

## Auth

Auth is a password only: Caddy `basic_auth`, user `kuhy`, and a random
password in `SUWAYOMI_PASSWORD` in the env file. The bcrypt hash lives next to
it as `SUWAYOMI_BCRYPT`. Suwayomi's own `authMode` is `NONE`, so the only gate
is Caddy, and the server is unreachable except through Caddy.

- **Every request needs the header**, GraphQL and images alike:
  `Authorization: Basic base64(kuhy:<password>)`. A missing or wrong password
  gets HTTP 401 with an empty body.
- **Images need it too.** Page and thumbnail URLs in responses are
  server-relative (`/api/v1/manga/4/chapter/1/page/0`,
  `/api/v1/manga/4/thumbnail`). Build them as `SUWAYOMI_URL + path`, and put
  the same `Authorization` header in `PageRef.headers`.
- **Cost.** Caddy caches the bcrypt check. 20 authorised requests in a row
  took 0.27 s, so per-image auth adds no meaningful time.
- **Kartka stores** the URL, user and password in its own settings. Do not
  ship the password in the APK or the repo.

## GraphQL operations the client needs

All are `POST /api/graphql` with `{"query": ..., "variables": ...}`. The
documents and the real responses are in `test/fixtures/suwayomi/`.
`deploy/suwayomi/gql.sh <file.graphql> '<vars>'` replays any of them with the
stored credentials.

| Need | Document | Response fixture |
|---|---|---|
| health/version | `about_server.graphql` | `about_server.json` |
| refresh store list | `fetch_extensions.graphql` (mutation `fetchExtensions`) | `fetch_extensions.json` (truncated) |
| find an extension | `extensions.graphql` `{name}` | `extensions.json` |
| install extension | `install_extension.graphql` `{pkgName}` (mutation `updateExtension`, `patch.install`) | `install_extension.json` |
| list sources | `sources.graphql` | `sources.json` (181 sources) |
| popular / latest / search | `fetch_source_manga.graphql` `{source, type: POPULAR\|LATEST\|SEARCH, query, page}` | `fetch_source_manga_search.json` |
| manga details | `fetch_manga.graphql` `{id}` (mutation `fetchMangaAndChapters`, `fetchManga: true`) | `fetch_manga.json` |
| chapter list | `fetch_chapters.graphql` `{id}` (`fetchChapters: true`) | `fetch_chapters.json` |
| pages | `fetch_chapter_pages.graphql` `{chapterId}` | `fetch_chapter_pages.json` |
| manga by MangaKey | `manga_by_url.graphql` `{sourceId, url}` | `manga_by_url.json`, `manga_by_url_unknown.json` |
| error shape | (unknown chapter id) | `error_unknown_chapter.json` |
| full schema | `introspection.graphql` | `schema.json` |

Facts the Dart client depends on (all observed, not assumed):

- **v2.4 names.** There is no `fetchManga` or `fetchChapters` mutation; both
  are `fetchMangaAndChapters` with flags. The store list setting is
  `extensionStores`, and `addExtensionStore(input: {indexUrl})` adds to it.
  Keiyoushi's URL is stored as `https://github.com/keiyoushi/extensions/raw/repo/index.pb`
  (Suwayomi rewrites the old `index.min.json` URL to that).
- **Types.** Source ids are `LongString`, a JSON string such as
  `"2499283573021220255"`. Never parse them into a JS/Dart-web `double`.
  `uploadDate` is a string of epoch milliseconds. `chapterNumber` is a float.
  `pageCount` is `-1` until `fetchChapterPages` has run.
- **Server ids are local.** `manga.id` and `chapter.id` are Suwayomi database
  ids, so never sync them. The stable identity is `sourceId` + `url`. These
  match the `.tachibk` fields exactly: MangaDex is `/manga/<uuid>` in both, and
  AllManga uses a bare id in both.
- **Unknown manga.** For a MangaKey the server has never seen, `manga_by_url`
  returns no nodes. Reach the manga once through `fetchSourceManga` SEARCH, or
  load the SY backup into Suwayomi with the `restoreBackup` mutation.
- **Errors.** GraphQL errors come back as HTTP 200 with `errors[]`, and
  `data.<field>` set to `null`. Only auth failures are non-200.
- **Pages.** `fetchChapterPages.pages` is a list of relative URLs. Each GET
  returns `image/jpeg` (or the source's format) with
  `cache-control: max-age=86400`.

## Source ids: does Suwayomi keep Tachiyomi's numeric ids? Yes, verified

The check: decode the `backupSources` from the newest SY backup
(`~/services/syncyomi/snapshots/syncyomi_2026-10-24T12-00-00Z.tachibk`,
`zcat | protoc --decode_raw`). Install the Keiyoushi extensions behind them
(MangaDex, AllManga, MangaDot, Mangakakalot, MANGA Plus), then intersect the
backup ids with `sources { nodes { id } }`.

**Result:** 7 of 7 backup sources whose extension was installed came back with
the identical 64-bit id, including the per-language ones (MangaDex en
`2499283573021220255` and pl `8033579885162383068`, MangaDot en and pl). Those
7 sources hold 2349 of the backup's library entries. The evidence is in
`test/fixtures/suwayomi/source_id_crosscheck.json`.

The 21 ids that did not match are of two kinds:
- extensions that were not installed for this check;
- `6901`/`6902`, SY's built-in E-Hentai and ExHentai (109 + 103 entries).
  These are not extensions and do not exist in Suwayomi, so the backup mapper
  has to treat them as unavailable unless a native or plugin source claims
  them.

So `suwayomi:<backupSourceId>` (contracts §1) holds.
