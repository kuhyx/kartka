# Research: tracking (AniList + MyAnimeList)

Feeds `lib/tracking/` (done #4) and contracts §4 `trackers/` and §7
`OAuthRedirect`. Researched 2026-10-24.

Primary sources:
- AniList docs repo [`AniList/docs@03281c0a`](https://github.com/AniList/docs/tree/03281c0a4bbf0c7f2097e0c935cddaed1096aa65/docs/guide)
  (docs.anilist.co returns 403 to fetchers, so the repo was read instead)
- MAL [authorization reference](https://myanimelist.net/apiconfig/references/authorization)
  and [API v2 reference](https://myanimelist.net/apiconfig/references/api/v2)
- Mihon's working clients as a behavioural reference (Apache-2.0, not copied):
  [AnilistApi.kt](https://github.com/mihonapp/mihon/blob/d001e6f210e6a077a30dd9a1392573a3225bba2f/app/src/main/java/eu/kanade/tachiyomi/data/track/anilist/AnilistApi.kt),
  [MyAnimeListApi.kt](https://github.com/mihonapp/mihon/blob/d001e6f210e6a077a30dd9a1392573a3225bba2f/app/src/main/java/eu/kanade/tachiyomi/data/track/myanimelist/MyAnimeListApi.kt).
  **Do not reuse mihon's client ids** (`16329`, `c46c9e24…`). They are bound
  to `mihon://` redirects.

## 1. AniList OAuth

- From [auth/index.md](https://github.com/AniList/docs/blob/03281c0a4bbf0c7f2097e0c935cddaed1096aa65/docs/guide/auth/index.md):
  "Scopes are not supported". Tokens "remain valid for 1 year", and
  "Refresh tokens are not currently supported". After a year the user
  re-authenticates. Kartka should decode the JWT `exp` claim and prompt a week before it.
- **Grant: implicit** (the docs recommend it for "websites or mobile apps",
  and mihon uses it). No client secret is shipped.
  `GET https://anilist.co/api/v2/oauth/authorize?client_id=<id>&response_type=token`.
  The token comes back in the **URL fragment** `#access_token=…&token_type=Bearer&expires_in=…`
  ([implicit.md](https://github.com/AniList/docs/blob/03281c0a4bbf0c7f2097e0c935cddaed1096aa65/docs/guide/auth/implicit.md)).
  The code grant would need the secret in the app
  ([authorization-code.md](https://github.com/AniList/docs/blob/03281c0a4bbf0c7f2097e0c935cddaed1096aa65/docs/guide/auth/authorization-code.md)), so do not use it.
- **Redirect URI rules:** a client has a single "Redirect URL" field, which
  "can be any valid URI, including custom URI schemes". The code grant
  "must exactly match". The implicit grant documents only `client_id` and
  `response_type`, and it redirects "to the redirect URI you specified in
  your application settings".
  ⇒ **One client cannot serve both** `kartka://oauth` and
  `http://127.0.0.1:<port>/oauth`. **Register two clients**: "Kartka
  (Android)" and "Kartka (desktop)". Applications "cannot be deleted", which
  is harmless.
- **Fragment trap on web:** the fragment never reaches the wrapper server.
  The `/oauth` route must be served by the Flutter web app itself, which reads
  `Uri.base.fragment`. Alternatively the wrapper serves a static page whose
  JS reads `location.hash` and hands it to the app (same origin, so
  `BroadcastChannel`/`localStorage` work). On Android the deep-link intent
  carries the full URI, fragment included.
- Requests: `POST https://graphql.anilist.co` with
  `Authorization: Bearer <token>`
  ([authenticated-requests.md](https://github.com/AniList/docs/blob/03281c0a4bbf0c7f2097e0c935cddaed1096aa65/docs/guide/auth/authenticated-requests.md)).
  **CORS is open**: a preflight with `Origin: http://127.0.0.1:8787`
  returned `204` with `access-control-allow-origin: *` and allowed
  `Authorization, Content-Type`. The web build can call it directly or
  through `/proxy`. Use `/proxy` for uniformity.
- Rate limit ([rate-limiting.md](https://github.com/AniList/docs/blob/03281c0a4bbf0c7f2097e0c935cddaed1096aa65/docs/guide/rate-limiting.md)):
  the documented limit is 90/min, but it is "currently in a degraded state and
  is limited to **30 requests per minute**". There is also a burst limiter.
  Exceeding it gives `429` plus `Retry-After` (s) and `X-RateLimit-Reset`, with
  a 1-minute timeout. Read `X-RateLimit-Remaining` on each response. Design
  for ≤ 1 req/2 s and batch reads.

### AniList operations Kartka needs

```graphql
query { Viewer { id name mediaListOptions { scoreFormat } } }
# Bulk pull (one call per sync, not per manga):
query ($userId: Int) { MediaListCollection(userId: $userId, type: MANGA) {
  lists { entries { id mediaId status progress updatedAt } } } }
query ($id: Int) { Media(id: $id, type: MANGA) { id chapters
  mediaListEntry { id status progress } } }
mutation ($mediaId: Int, $progress: Int, $status: MediaListStatus) {
  SaveMediaListEntry(mediaId: $mediaId, progress: $progress, status: $status) {
    id status progress } }
```

`SaveMediaListEntry` creates the entry or updates it
([mutations.md](https://github.com/AniList/docs/blob/03281c0a4bbf0c7f2097e0c935cddaed1096aa65/docs/guide/graphql/mutations.md)).
`progress` is an integer chapter count, so use `floor(chapterNumber)`.
Statuses are `CURRENT, PLANNING, COMPLETED, DROPPED, PAUSED, REPEATING`.

## 2. MyAnimeList OAuth2 (code + PKCE)

From the [authorization reference](https://myanimelist.net/apiconfig/references/authorization):
- Authorize: `GET https://myanimelist.net/v1/oauth2/authorize?response_type=code&client_id=…&state=…&redirect_uri=…&code_challenge=…&code_challenge_method=plain`.
  **"Currently, only the `plain` method is supported."** So
  challenge == verifier: 43-128 chars from the unreserved set, fresh per
  login, kept until the exchange. `state` is RECOMMENDED, and the client
  "should verify" it. Kartka uses it to route `kartka://oauth` replies.
  `redirect_uri` is optional when only one is registered. If sent, it "must
  exactly match one of your pre-registered URIs".
- Token: `POST https://myanimelist.net/v1/oauth2/token` (form)
  `grant_type=authorization_code, client_id, code, code_verifier, redirect_uri`.
  Refresh with `grant_type=refresh_token, refresh_token, client_id`.
  The page is inconsistent on access-token lifetime (prose says 1 h, the
  sample `expires_in` is 2415600 s). The refresh token lasts about a month.
  ⇒ Honour `expires_in`, refresh proactively and on any `401 invalid_token`,
  and re-login when the refresh fails.
- Client secret: PKCE "native app" clients have none. Mihon sends only
  `client_id`. Pick the app type on the form that issues **no secret** (see §4).
- **CORS: none.** `api.myanimelist.net` returned no `access-control-*`
  headers, and an `OPTIONS` on the token endpoint returned `405`. Web goes
  **through the wrapper `/proxy`** for both the token exchange and the API.

### MAL operations ([API v2](https://myanimelist.net/apiconfig/references/api/v2))

| Need | Call |
|---|---|
| who am I | `GET /v2/users/@me` |
| bulk pull | `GET /v2/users/@me/mangalist?fields=list_status&limit=1000&nsfw=true` (follow `paging.next`) |
| one entry | `GET /v2/manga/{id}?fields=num_chapters,my_list_status` |
| push progress | `PATCH /v2/manga/{id}/my_list_status` form `num_chapters_read=<n>&status=reading` (it "updates only values specified") |

Base `https://api.myanimelist.net`. Statuses are `reading, completed,
on_hold, dropped, plan_to_read`. **Rate limit: undocumented.** Errors listed
are `401 invalid_token` and "`403` DoS detected". Use ≤ 1 req/s and back off
on 403.

## 3. Mapping and merge (contract §4)

- Ids come from the backup: `BackupTracking.mediaId` (field 100) with
  `syncId 2` gives the AniList media id, and `syncId 1` the MAL id. These
  seed `trackers/<mangaKeyHash>/<service>.remoteId`. In kuhy's backup, 117
  favourites have AniList and 84 have MAL (see DOCS-research-tachibk.md).
- Two-way and never decreasing:
  `local = max(local, remote.progress)`. Push only when
  `floor(local.chapterNumber) > lastPushedChapter`. After a 2xx, set
  `lastPushedChapter`. Never send a lower `progress`, even when the user
  re-reads.
- Queue pushes offline (airplane mode, done #2). Flush with the rate limits
  above. A new `MangaKey` without a remote id gets a search-and-confirm UI,
  never an automatic link.

## 4. What only kuhy can do (no API): client registration

| # | Where | Fields (form order) |
|---|---|---|
| A1 | <https://anilist.co/settings/developer> → "Create New Application" | Name `Kartka (Android)`; Redirect URL `kartka://oauth` |
| A2 | same | Name `Kartka (desktop)`; Redirect URL `http://127.0.0.1:<wrapperPort>/oauth` |
| M1 | <https://myanimelist.net/apiconfig> → "Create ID" | App Name; App Type (a select: choose a no-secret type, `other`/`android`, and confirm on the form); App Description (50-500 chars, per a [third-party guide](https://github.com/ballgoesvroomvroom/AP_MALPorter/tree/main/installation_guide/mal_api), so treat the limit as unverified); App Redirect URL(s) `kartka://oauth` + `http://127.0.0.1:<wrapperPort>/oauth` (if the form takes only one, create a second ID M2); Homepage URL; Commercial/Non-Commercial (select Non-Commercial); Name/Company Name (kuhy's own); Purpose of Use (select Hobbyist); accept the licence |

**Contract flag:** exact redirect matching means `<wrapperPort>` in §7 must
be a **fixed constant**, not a random free port. Pick it once (e.g. in
`lib/platform/oauth_redirect.dart`). The script below reads it from there.

## 5. Gate-2 handoff script (design only, NOT run)

Proposed `tools/oauth_register.sh` (bash, `set -euo pipefail`) plus a typed
helper `tools/oauth_register.py` for the listener and HTTP checks. This
follows `~/.claude/rules/offload-last-resort.instructions.md`.

1. **Preflight:** install `xclip` via pacman if it is missing. Derive the
   redirect URIs from the source of truth by parsing `kKartkaOAuthPort` and
   `kOAuthScheme` from `lib/platform/oauth_redirect.dart`. Never take them
   from a doc. Check that the port is free (the wrapper must not be running).
2. **Per client (A1, A2, M1):** `xdg-open` the page. Then for each text field
   in form order: `printf %s "$value" | xclip -selection clipboard`, then
   print `paste <Field> → Enter`. Values are the fixed name, the derived
   redirect URI, and a pre-written MAL description of about 200 chars kept in
   the script. For a `<select>` (MAL type, commercial, purpose), print a
   single line such as "choose: other". Clipboard cannot do selects.
3. **Capture:** "copy the Client ID, press Enter". Read it with
   `xclip -o -selection clipboard` and validate it (AniList: digits; MAL: 32
   hex). Save it to `~/.config/kartka/oauth.json` (mode 600, **outside the
   repo**) as `{anilist_android, anilist_desktop, mal}`. The build reads it
   with `--dart-define-from-file`. Nothing is committed.
4. **Verify automatically** (the outcome, not the green tile):
   - A2: start a loopback listener on `127.0.0.1:<wrapperPort>`. `/oauth`
     serves a tiny page that POSTs `location.hash` to `/capture`. Then
     `xdg-open` the implicit authorize URL; kuhy clicks "Approve" (the
     irreducible click). Then run `query { Viewer { id name } }` and print the
     name. Expect `kuhy`'s account.
   - M1: same listener, PKCE plain + `state`. Exchange the `code` at the
     token endpoint, `GET /v2/users/@me`, and print the name.
   - A1 (custom scheme): a desktop script cannot complete it. Verification is
     the on-device E2E "link AniList" step. The script only checks that the
     id is saved and numeric.
   - Tokens obtained during verification are discarded, never stored.
5. **`--verify-only`** reruns step 4 with the saved ids, so a failed check
   does not mean registering again. Exit codes: `0` ok, `1` verify failed,
   `2` missing ids.
