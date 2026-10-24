# Research: MangaDex API (native source `lib/sources/mangadex/`)

Researched 2026-10-24. The API is **v5.13.1**: OpenAPI at
`https://api.mangadex.org/docs/static/api.yaml`, servers
`https://api.mangadex.org` (prod) and `https://api.mangadex.dev` (dev, with
separate limits). The docs source is
[`mangadex-pub/mangadex-api-docs@0fad71d0`](https://gitlab.com/mangadex-pub/mangadex-api-docs/-/tree/0fad71d05ecac235253ed3bdd0cc3288effddc11),
rendered at <https://api.mangadex.org/docs/>. Public reads need **no auth**.

## 1. Usage policy and request rules

From [docs index](https://api.mangadex.org/docs/), Acceptable Usage Policy:
"You MUST credit MangaDex", "You MUST credit scanlation groups (and honor
their content removal requests)", and "You CANNOT run ads or paid services".
⇒ Show the scanlator on every chapter row and the reader's chapter header
(`ChapterInfo.scanlator`), and show "MangaDex" as the source name.

From [2-limitations.md](https://gitlab.com/mangadex-pub/mangadex-api-docs/-/blob/0fad71d05ecac235253ed3bdd0cc3288effddc11/2-limitations.md):
- "The request MUST have a User-Agent header, and it must not be spoofed."
  Send `User-Agent: Kartka/<version> (+https://github.com/kuhyx/kartka)`.
  Put no personal email in it.
- "The request CANNOT have a Via header". The wrapper `/proxy` must **not
  add `Via`** (many proxy libs do by default) and must forward or set a real
  UA. Browsers cannot set UA, so `/proxy` sets it.
- "We do not send CORS responses for other websites than ours" and clients
  "MUST proxy". Verified: a request with `Origin: http://127.0.0.1:8787`
  got `200` with **no** `access-control-allow-origin`. Web goes through
  `/proxy` for both API and images.
- "We will serve the wrong response for any image hotlinked from our
  domains." Do not forward the app's own `Referer`/`Origin` to image hosts.
  Fetching images through `/proxy` (web) or directly (Android) without a
  foreign Referer is fine.

### Rate limits

| Scope | Limit |
|---|---|
| global, per IP | ~**5 req/s** ("minimum guaranteed allowance", shared NAT counts) |
| `GET /at-home/server/{id}` | **40 / min** |
| `POST /chapter/{id}/read` | 300 / 10 min (only if we ever sync read marks to MD) |
| `GET /manga/random` | 60 / min |

Response headers (on specially-limited endpoints): `X-RateLimit-Limit`,
`X-RateLimit-Remaining`, `X-RateLimit-Retry-After` (a UNIX timestamp).
Escalation: `429` for all `*.mangadex.org`, then a temporary IP ban (`403`),
then silence. ⇒ Use a per-host token bucket in `KartkaHttp` (≤ 4 req/s for
`api.mangadex.org`), cache `/at-home` results for their 15-min lifetime, and
stop retrying on 429/403. The SPEC evaluator rule "≤1 req / 2 s per host" is
stricter and also fine.

## 2. Endpoints for the six `MangaSource` methods

The common envelope is `{result, response, data, limit, offset, total}`. An
entity is `{id, type, attributes, relationships:[{id, type, attributes?}]}`.
Array parameters use bracket syntax (`includes[]=cover_art`). Objects use
`order[field]=desc`.

| Method | Call |
|---|---|
| `popular(p)` | `GET /manga?order[followedCount]=desc&limit=20&offset=(p-1)*20&includes[]=cover_art&availableTranslatedLanguage[]=<lang>&contentRating[]=safe&contentRating[]=suggestive&hasAvailableChapters=true` |
| `latest(p)` | `GET /manga?order[latestUploadedChapter]=desc&…same filters…` (this is also the API default order) |
| `search(q,p)` | `GET /manga?title=<q>&order[relevance]=desc&…same filters…` |
| `details(url)` | `GET /manga/{uuid}?includes[]=cover_art&includes[]=author&includes[]=artist` |
| `chapters(url)` | `GET /manga/{uuid}/feed?translatedLanguage[]=<lang>&order[volume]=desc&order[chapter]=desc&limit=500&offset=…&includes[]=scanlation_group&includeExternalUrl=0&contentRating[]=…` (page until `offset+limit ≥ total`) |
| `pages(url)` | `GET /at-home/server/{chapterUuid}` → build URLs (§3) |

Parameter facts from the OpenAPI spec:
- `/manga`: `limit` 0-100 (default 10). The `order` keys are `title, year,
  createdAt, updatedAt, latestUploadedChapter, followedCount, relevance,
  rating`. Default order is `{latestUploadedChapter: desc}`.
  `hasAvailableChapters` is a filter. `includes[]` expands relationships.
- `/manga/{id}/feed`: `limit` 1-**500** (default 100). The `order` keys are
  `createdAt, updatedAt, publishAt, readableAt, volume, chapter`. There are
  also `includeExternalUrl`, `includeUnavailable`, `includeEmptyPages`,
  `excludedGroups[]` and `excludedUploaders[]`.
- **Pagination cap:** `offset + limit ≤ 10000`. Verified live:
  `GET /manga?limit=20&offset=9990` → `400 "Result window is too large, from
  + size must be less than or equal to: [10000]"`, while `limit=100&offset=9900`
  → `200` (total 95,212). Popular, latest and search stop at page
  `10000/limit`. Feeds over 10k chapters need `order` + `publishAtSince`
  windows.
- Content rating: "Pornographic titles are hidden by default"
  ([search.md](https://gitlab.com/mangadex-pub/mangadex-api-docs/-/blob/0fad71d05ecac235253ed3bdd0cc3288effddc11/03-manga/search.md)).
  Always pass `contentRating[]` explicitly from a Kartka setting rather than
  relying on server defaults.
- External chapters (e.g. MangaPlus links) carry a non-null
  `attributes.externalUrl` and are not hosted on MD@Home (`pages` count not
  verified here). Exclude them (`includeExternalUrl=0`) or show them as
  "opens externally". They cannot be read offline.

### Mapping to contract §1

- **URLs must match Tachiyomi's shapes** so that imported backup keys line
  up. In kuhy's backup, all MangaDex favourites use manga url
  `/manga/<uuid>` and chapter url `/chapter/<uuid>` (see
  DOCS-research-tachibk.md §3.4).
  ⇒ `MangaSummary.url = '/manga/' + id` and `ChapterInfo.url = '/chapter/' + id`.
  `MangaKey = 'mangadex|/manga/<uuid>'`.
- The native source must **claim** the Tachiyomi MangaDex source ids from
  the backup. Kuhy uses `2499283573021220255` (the `en` variant of Keiyoushi
  `all.mangadex`). Map that id to `mangadex`, not `suwayomi:<id>`. Every
  language variant has its own Tachiyomi id. Take the list from the
  Keiyoushi index (`extensionList.extensions[].sources[]` where
  `packageName == eu.kanade.tachiyomi.extension.all.mangadex`).
- Title: use `attributes.title[lang]`, else `title.en`, else the first
  `altTitles` match, else the first value. Do the same for `description`.
- `status`: `ongoing | completed | hiatus | cancelled` → `MangaStatus`.
- Authors come from `relationships[type=author|artist].attributes.name` when
  `includes[]` is set.
- `trackerIds`: `attributes.links` has `al` (AniList id) and `mal` (MAL id).
  Verified live: the keys seen were `al, ap, kt, mal, mu, raw`.
  Seed `MangaDetails.trackerIds` from it. This is free tracker linking.
- `ChapterInfo`: `number = double.tryParse(attributes.chapter)` (a string
  that may be null for oneshots), `name = "Vol.{volume} Ch.{chapter} {title}"`,
  `uploadedAt = publishAt`, `scanlator` = the `scanlation_group`
  relationship name (or the uploader if there is no group).

## 3. Pages (MangaDex@Home)

From [retrieving-chapter.md](https://gitlab.com/mangadex-pub/mangadex-api-docs/-/blob/0fad71d05ecac235253ed3bdd0cc3288effddc11/04-chapter/retrieving-chapter.md):
`GET /at-home/server/{chapterId}` returns
`{baseUrl, chapter: {hash, data[], dataSaver[]}}`. Page URLs are
`{baseUrl}/{data|data-saver}/{hash}/{filename}`, in array order. "Do NOT
assume any format" (png/jpg/webp/gif all occur).

- **Quality modes:** `data` is "Original quality, pixel-for-pixel".
  `data-saver` is "Compressed quality, large size savings". Every page has
  both. Kartka should default to `data` and make `data-saver` a setting
  (metered or low storage). Downloads should store whichever mode was chosen.
- `baseUrl` lifetime: "We guarantee 15 minutes". After that the images may
  return `403`, so call `/at-home` again. That is one call per chapter open
  or download (a 40/min budget). The downloader must not prefetch more than
  about 30 chapters per minute.
- `forcePort443=true` restricts to MD@H nodes on port 443, for restrictive
  networks. The default is `false`.
- **Report** every image fetched from a `baseUrl` that does not contain
  `mangadex.org`. Send `POST https://api.mangadex.network/report` with
  `Content-Type: application/json` and
  `{url, success, cached (X-Cache starts with HIT), bytes, duration (ms, full download)}`.
  On failure, report, then re-request `/at-home` for a new node.
- Image requests need no auth and no special headers. `PageRef.headers` can
  stay empty, apart from the UA set by `KartkaHttp`/`/proxy`.

## 4. Covers

From [covers.md](https://gitlab.com/mangadex-pub/mangadex-api-docs/-/blob/0fad71d05ecac235253ed3bdd0cc3288effddc11/03-manga/covers.md):
`https://uploads.mangadex.org/covers/{mangaId}/{fileName}` gives the
original, and `…/{fileName}.256.jpg` / `.512.jpg` give thumbnails. The
**full filename including its extension** is kept before `.256.jpg`. The file
name is `relationships[type=cover_art].attributes.fileName`
(needs `includes[]=cover_art`). Use `.256.jpg` in lists and `.512.jpg` on
the details page.

## 5. Language filtering

Codes are ISO 639-1, plus `$language-$region` for `pt-br`, `es-la`, `zh-hk`
and `ja-ro` (romanized)
([3-enumerations.md](https://gitlab.com/mangadex-pub/mangadex-api-docs/-/blob/0fad71d05ecac235253ed3bdd0cc3288effddc11/3-enumerations.md)).
- Browse lists: `availableTranslatedLanguage[]=<lang>` (the title has at
  least one chapter in that language).
- Chapter feed: `translatedLanguage[]=<lang>` (repeatable for multiple languages).
- `SourceRef.lang` for the native source is a user setting (default `en`).
  Do not create one `MangaSource` per language as Tachiyomi does, because
  `MangaKey` is language-independent (`mangadex|/manga/<uuid>`).

## 6. Test fixtures (SPEC: no live network in unit tests)

Record one response each for `/manga` list, `/manga/{id}`, the feed (two
pages), and `/at-home/server/{id}` into `test/fixtures/mangadex/`. Also record
the 400 "Result window is too large" body above as a fixture for the
pagination-cap path. The one `@Tags(['live'])` smoke test should hit the
`.dev` server or a single prod call, inside the rate budget.
