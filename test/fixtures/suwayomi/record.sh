#!/bin/bash
# Re-record the Suwayomi GraphQL fixtures from a local Suwayomi-Server.
#
# Usage: SUWAYOMI_URL=http://127.0.0.1:4599 SUWAYOMI_AUTH=user:pass ./record.sh
# The server needs the Keiyoushi store and the MangaDex extension installed.
# Each fixture is {request, status, response}; the documents below must stay
# byte-identical to lib/sources/suwayomi/suwayomi_queries.dart, and
# test/sources/suwayomi/fixture_queries_test.dart fails when they drift.
# The documents are single-quoted on purpose: their $vars belong to GraphQL.
# shellcheck disable=SC2016
set -euo pipefail

readonly URL="${SUWAYOMI_URL:-http://127.0.0.1:4599}"
AUTH="${SUWAYOMI_AUTH:-kartka:fixture}"
OUT="$(cd "$(dirname "$0")" && pwd)"
readonly OUT
readonly MANGADEX_EN='2499283573021220255'
readonly MANGADEX_PKG='eu.kanade.tachiyomi.extension.all.mangadex'
# Must not be on the server yet when recording (use a fresh server root).
readonly UNSEEN_URL='/manga/b0b721ff-c388-4486-aa0f-c2b0bb321512'
readonly UNSEEN_TITLE='Sousou no Frieren'
readonly SPARE_PKG='eu.kanade.tachiyomi.extension.en.weebcentral'
readonly EXT_FIELDS='pkgName name lang versionName iconUrl isInstalled hasUpdate isObsolete'

readonly Q_ABOUT='query KartkaAbout { aboutServer { name version } }'
readonly Q_SOURCES='query KartkaSources { sources { nodes { id name lang displayName supportsLatest } } }'
readonly Q_SOURCE_MANGA='mutation KartkaSourceManga($source: LongString!, $type: FetchSourceMangaType!, $page: Int!, $query: String) { fetchSourceManga(input: {source: $source, type: $type, page: $page, query: $query}) { hasNextPage mangas { id url title thumbnailUrl } } }'
readonly Q_MANGA_ID='query KartkaMangaId($source: LongString!, $url: String!) { mangas(condition: {sourceId: $source, url: $url}, first: 1) { nodes { id } } }'
readonly Q_DETAILS='mutation KartkaDetails($id: Int!) { fetchMangaAndChapters(input: {id: $id, fetchManga: true, fetchChapters: false}) { manga { id url title thumbnailUrl author artist description genre status } } }'
readonly Q_CHAPTERS='mutation KartkaChapters($id: Int!) { fetchMangaAndChapters(input: {id: $id, fetchManga: false, fetchChapters: true}) { chapters { id url name chapterNumber uploadDate scanlator sourceOrder } } }'
readonly Q_CHAPTER_ID='query KartkaChapterId($url: String!) { chapters(condition: {url: $url}) { nodes { id manga { sourceId } } } }'
readonly Q_PAGES='mutation KartkaPages($id: Int!) { fetchChapterPages(input: {chapterId: $id}) { pages } }'
readonly Q_EXTENSIONS="mutation KartkaExtensions { fetchExtensions(input: {}) { extensions { ${EXT_FIELDS} } } }"
readonly Q_UPDATE_EXT="mutation KartkaUpdateExtension(\$id: String!, \$patch: UpdateExtensionPatchInput!) { updateExtension(input: {id: \$id, patch: \$patch}) { extension { ${EXT_FIELDS} } } }"

# post <query> <variables-json> -> writes {status, body} JSON to stdout
post() {
  local body status tmp
  tmp="$(mktemp)"
  body="$(jq -nc --arg q "$1" --argjson v "$2" \
    '{operationName: ($q | capture("^\\w+ (?<n>\\w+)").n), query: $q, variables: $v}')"
  status="$(curl -s -o "$tmp" -w '%{http_code}' -u "$AUTH" -X POST "$URL/api/graphql" \
    -H 'Content-Type: application/json' -d "$body")"
  jq -n --argjson req "$body" --argjson s "$status" --rawfile r "$tmp" \
    '{request: $req, status: $s, response: ($r | try fromjson catch $r)}'
  rm -f "$tmp"
}

# rec <name> <query> <variables-json> [jq-trim] -> test/fixtures/suwayomi/<name>.json
# ONLY="a b" re-records just those fixtures (the unseen-manga ones need a fresh root).
rec() {
  if [[ -n "${ONLY:-}" && " ${ONLY} " != *" $1 "* ]]; then return 0; fi
  post "$2" "$3" | jq "${4:-.}" > "$OUT/$1.json"
  echo "recorded $1 ($(jq -r .status "$OUT/$1.json"))"
}

main() {
  rec about "$Q_ABOUT" '{}'
  rec sources "$Q_SOURCES" '{}' \
    '.response.data.sources.nodes |= map(select(.id == "0" or .lang == "en" or .lang == "ja"))'
  rec popular "$Q_SOURCE_MANGA" "{\"source\":\"$MANGADEX_EN\",\"type\":\"POPULAR\",\"page\":1}"
  rec latest "$Q_SOURCE_MANGA" "{\"source\":\"$MANGADEX_EN\",\"type\":\"LATEST\",\"page\":1}"
  # Unseen manga: the id lookup misses, a title search registers it server-side.
  rec manga_id_unseen "$Q_MANGA_ID" "{\"source\":\"$MANGADEX_EN\",\"url\":\"$UNSEEN_URL\"}"
  rec search "$Q_SOURCE_MANGA" \
    "{\"source\":\"$MANGADEX_EN\",\"type\":\"SEARCH\",\"page\":1,\"query\":\"$UNSEEN_TITLE\"}"
  local unseen_id
  unseen_id="$(jq -r --arg u "$UNSEEN_URL" \
    '.response.data.fetchSourceManga.mangas[] | select(.url == $u) | .id' "$OUT/search.json")"
  rec details_unseen "$Q_DETAILS" "{\"id\":$unseen_id}"
  rec source_error "$Q_SOURCE_MANGA" '{"source":"1","type":"POPULAR","page":1}'

  local manga_url manga_id chapter_url chapter_id
  manga_url="$(jq -r '.response.data.fetchSourceManga.mangas[0].url' "$OUT/popular.json")"
  rec manga_id "$Q_MANGA_ID" "$(jq -nc --arg s "$MANGADEX_EN" --arg u "$manga_url" '{source: $s, url: $u}')"
  rec manga_id_miss "$Q_MANGA_ID" "{\"source\":\"$MANGADEX_EN\",\"url\":\"/manga/not-on-server\"}"
  manga_id="$(jq -r '.response.data.mangas.nodes[0].id' "$OUT/manga_id.json")"
  rec details "$Q_DETAILS" "{\"id\":$manga_id}"
  rec chapters "$Q_CHAPTERS" "{\"id\":$manga_id}"
  chapter_url="$(jq -r '.response.data.fetchMangaAndChapters.chapters[0].url' "$OUT/chapters.json")"
  rec chapter_id "$Q_CHAPTER_ID" "$(jq -nc --arg u "$chapter_url" '{url: $u}')"
  chapter_id="$(jq -r '.response.data.chapters.nodes[0].id' "$OUT/chapter_id.json")"
  rec pages "$Q_PAGES" "{\"id\":$chapter_id}"

  # 1400+ extensions upstream; keep the installed ones plus a few known ones.
  rec extensions "$Q_EXTENSIONS" '{}' \
    '.response.data.fetchExtensions.extensions |= map(select(.isInstalled or (.pkgName | test("weebcentral|comickfan|mangaplus|asurascans"))))'
  rec ext_install "$Q_UPDATE_EXT" "{\"id\":\"$SPARE_PKG\",\"patch\":{\"install\":true}}"
  rec ext_update "$Q_UPDATE_EXT" "{\"id\":\"$MANGADEX_PKG\",\"patch\":{\"update\":true}}"
  rec ext_uninstall "$Q_UPDATE_EXT" "{\"id\":\"$SPARE_PKG\",\"patch\":{\"uninstall\":true}}"

  AUTH='wrong:creds'
  rec unauthorized "$Q_ABOUT" '{}'
}

main "$@"
