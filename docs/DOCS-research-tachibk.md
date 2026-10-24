# Research: `.tachibk` backup format (TachiyomiSY)

Feeds `lib/backup_import/` (done #1). Researched 2026-10-24.

Sources are the Kotlin models, which **are** the schema. Kotlinx-serialization
`@ProtoNumber` fields are used, and no `.proto` file is shipped.

- SY (authoritative for kuhy's file): [`jobobby04/TachiyomiSY@6d4502d2` …/data/backup/models/](https://github.com/jobobby04/TachiyomiSY/tree/6d4502d2b77850b6da8dc82eccf3831a11edb088/app/src/main/java/eu/kanade/tachiyomi/data/backup/models)
- Mihon (upstream): [`mihonapp/mihon@d001e6f2` …/data/backup/models/](https://github.com/mihonapp/mihon/tree/d001e6f210e6a077a30dd9a1392573a3225bba2f/app/src/main/java/eu/kanade/tachiyomi/data/backup/models)
- Decoder: [SY `BackupDecoder.kt`](https://github.com/jobobby04/TachiyomiSY/blob/6d4502d2b77850b6da8dc82eccf3831a11edb088/app/src/main/java/eu/kanade/tachiyomi/data/backup/BackupDecoder.kt).
  It peeks 2 bytes: `0x1f8b` means gzip, a JSON signature is rejected, and
  anything else is read as raw protobuf.

## 1. Container

The file is `gzip( protobuf(Backup) )`, with no header or version field. The
reader must accept both gzip and raw protobuf. SY also streams entries one at
a time (`decodeEntries`) and does not decode the whole message at once. Kuhy's
file is 5.3 MB gzip and 16.6 MB raw, so Dart can decode it in memory, but it
should do so off the UI isolate (`compute`/`Isolate.run`; on web, a worker or
chunked decode).

## 2. Messages and field numbers

Wire types: `Long`/`Int`/`Boolean`/enum are varint, `Float` is fixed32
(wire type 5), and `String`/`ByteArray`/messages are length-delimited.
**Repeated scalars are NOT packed.** In kuhy's file `categories` arrives as
one varint per element (wire type 0). A decoder should accept both forms.

`Backup` ([Backup.kt](https://github.com/jobobby04/TachiyomiSY/blob/6d4502d2b77850b6da8dc82eccf3831a11edb088/app/src/main/java/eu/kanade/tachiyomi/data/backup/models/Backup.kt)):

| # | Field | Type |
|---|---|---|
| 1 | backupManga | repeated BackupManga |
| 2 | backupCategories | repeated BackupCategory |
| 101 | backupSources | repeated BackupSource `{1 name, 2 sourceId}` |
| 104 | backupPreferences | repeated (app prefs, ignore) |
| 105 | backupSourcePreferences | repeated (ignore) |
| 106 | backupExtensionStores | repeated (extension repo URLs) |
| 600 | backupSavedSearches | repeated (**SY only**) |

`BackupManga` ([BackupManga.kt](https://github.com/jobobby04/TachiyomiSY/blob/6d4502d2b77850b6da8dc82eccf3831a11edb088/app/src/main/java/eu/kanade/tachiyomi/data/backup/models/BackupManga.kt)):

| # | Field | Type | Kartka use |
|---|---|---|---|
| 1 | source | int64 | Tachiyomi source id → `SourceRef.id` |
| 2 | url | string | **opaque**, part of `MangaKey` |
| 3 | title | string | |
| 4/5/6 | artist / author / description | string? | |
| 7 | genre | repeated string | |
| 8 | status | int | |
| 9 | thumbnailUrl | string? | `coverUrl` |
| 13 | dateAdded | int64 ms | `addedAt` |
| 16 | chapters | repeated BackupChapter | read marks |
| 17 | categories | repeated int64 | **category `order` values, not ids** |
| 18 | tracking | repeated BackupTracking | trackers |
| 100 | favorite | bool, **default true** | in library? |
| 101 | chapterFlags, 103 viewer_flags, 105 updateStrategy | | ignore |
| 104 | history | repeated BackupHistory | last read time |
| 106/107/109 | lastModifiedAt / favoriteModifiedAt / version | int64 | |
| 108 | excludedScanlators | repeated string | optional |
| 110-113 | notes, initialized, memo, nextUpdate | | ignore |
| 600 | mergedMangaReferences (SY) | repeated | SY merged entries |
| 601 | flatMetadata (SY) | message | ignore |
| 602/603 | customStatus / customThumbnailUrl (SY) | | prefer over 8/9 |
| 800-805 | customTitle/Artist/Author/Description/Genre (SY) | | prefer over 3-7 when set |

Mihon has the same numbers 1-113 and lacks 600-805
([mihon BackupManga.kt](https://github.com/mihonapp/mihon/blob/d001e6f210e6a077a30dd9a1392573a3225bba2f/app/src/main/java/eu/kanade/tachiyomi/data/backup/models/BackupManga.kt)).
Kartka should decode the union and ignore unknown fields.

`BackupChapter` ([BackupChapter.kt](https://github.com/jobobby04/TachiyomiSY/blob/6d4502d2b77850b6da8dc82eccf3831a11edb088/app/src/main/java/eu/kanade/tachiyomi/data/backup/models/BackupChapter.kt)):
`1 url, 2 name, 3 scanlator?, 4 read bool, 5 bookmark bool,
6 lastPageRead int64, 7 dateFetch, 8 dateUpload (ms), 9 chapterNumber float,
10 sourceOrder, 11 lastModifiedAt, 12 version, 13 memo`.

`BackupCategory` ([BackupCategory.kt](https://github.com/jobobby04/TachiyomiSY/blob/6d4502d2b77850b6da8dc82eccf3831a11edb088/app/src/main/java/eu/kanade/tachiyomi/data/backup/models/BackupCategory.kt)):
`1 name, 2 order int64, 3 id int64, 100 flags, (SY) 601 version, 602 uid,
603 lastModifiedAt`.

`BackupHistory` ([BackupHistory.kt](https://github.com/jobobby04/TachiyomiSY/blob/6d4502d2b77850b6da8dc82eccf3831a11edb088/app/src/main/java/eu/kanade/tachiyomi/data/backup/models/BackupHistory.kt)):
`1 url` (a **chapter** url), `2 lastRead` (ms epoch), `3 readDuration` (ms).

`BackupTracking` ([BackupTracking.kt](https://github.com/jobobby04/TachiyomiSY/blob/6d4502d2b77850b6da8dc82eccf3831a11edb088/app/src/main/java/eu/kanade/tachiyomi/data/backup/models/BackupTracking.kt)):
`1 syncId int, 2 libraryId int64, 3 mediaIdInt (deprecated), 4 trackingUrl,
5 title, 6 lastChapterRead float, 7 totalChapters, 8 score float, 9 status,
10 startedReadingDate, 11 finishedReadingDate, 12 private, 100 mediaId int64`.
Use **100**, and fall back to 3 only when 100 is 0.

`syncId` → service, per [SY TrackerManager.kt](https://github.com/jobobby04/TachiyomiSY/blob/6d4502d2b77850b6da8dc82eccf3831a11edb088/app/src/main/java/eu/kanade/tachiyomi/data/track/TrackerManager.kt)
(the same ids as mihon): `1 MyAnimeList, 2 AniList, 3 Kitsu, 4 Shikimori,
5 Bangumi, 6 Komga, 7 MangaUpdates, 8 Kavita, 9 Suwayomi, 10 Hikka,
11 MangaBaka, 12 Comick, 60 MDList (SY only)`.

## 3. Traps that break done #1

1. **Defaults are omitted on the wire.** Kotlinx ProtoBuf does not encode
   default values. In kuhy's file, field 100 is **absent on all 774 library
   entries** and present as `0` on the 1883 non-library entries. A
   proto3-style decoder (default `false`) would import an empty library. If
   you use `package:protobuf`, write the schema as **proto2** with
   `optional bool favorite = 100 [default = true];`. Otherwise use a
   hand-written decoder with an explicit defaults table. Non-zero defaults:
   `favorite = true`, `updateStrategy = ALWAYS_UPDATE (0)`, and
   `memo = JsonObjectEmptyBytes` (an empty JSON object). Everything else is 0,
   empty or null.
2. **Library = `favorite == true`**, not every entry. Non-favourites are
   history-only manga. Kuhy's file has 2657 entries but 774 in the library.
3. **Categories map by `order`.** SY's restorer does
   `backupCategoriesByOrder[order] → name`
   ([MangaRestorer.kt L60-L75](https://github.com/jobobby04/TachiyomiSY/blob/6d4502d2b77850b6da8dc82eccf3831a11edb088/app/src/main/java/eu/kanade/tachiyomi/data/backup/restore/restorers/MangaRestorer.kt#L60-L75)),
   and the creator writes `categories = mangaCategories.map { it.order }`
   ([MangaBackupCreator.kt L101](https://github.com/jobobby04/TachiyomiSY/blob/6d4502d2b77850b6da8dc82eccf3831a11edb088/app/src/main/java/eu/kanade/tachiyomi/data/backup/create/creators/MangaBackupCreator.kt#L101)).
   An empty list means the implicit **Default** category, which is not in
   `backupCategories`. Kartka needs a built-in "Default" category. 770 of
   kuhy's 774 favourites are in it.
4. **URLs are opaque.** Never normalise, trim or re-encode them. Masked
   shapes from kuhy's favourites:

   | Source | manga url | chapter url |
   |---|---|---|
   | MangaDex `2499283573021220255` | `/manga/<uuid>` | `/chapter/<uuid>` |
   | AllManga `4709139914729853090` | `/manga/<slug>/<slug>` | `/read/<slug>/<slug>/<slug>` |
   | MangaDot `5900936305360403385` | `<n>` | **JSON** `{"id":"<n>","source":"scraper","isVolume":false}` |
   | Cyanide & Happiness `491094567635736188` | `<n>` | `/comics/<slug>//…` |
   | E-Hentai `6901` | `/g/<n>/<slug>/?nw=always` | same |

5. **Last-read chapter.** The contract's `progress` record is derived as:
   - `readAt` = max `history.lastRead`
   - `chapterUrl` = that history row's url
   - `chapterNumber` = max `chapterNumber` over chapters with `read = true`,
     or else that history chapter's number
   - `page` = `lastPageRead` of the history chapter when it is not fully read
   - Chapters with `read = true` populate `read/<mangaKeyHash>/<chapterUrlHash>`.
     `chapterNumber` is a float and `-1` means unknown, so do not use it
     alone as identity.
6. **SY custom fields (800-805) override** the source fields for display.
7. Duplicate (source, url) pairs can occur across merged entries (field 600).
   Dedupe by `MangaKey`.

## 4. Kuhy's latest backup (found)

- Phone `23181JEGR08034` was connected over USB (and wireless). SY's
  storage folder is literally **`/sdcard/Tachioymi/`** (misspelled). Its
  autobackups are in `/sdcard/Tachioymi/autobackup/`, rotated 4 files at
  roughly 6 h intervals. There are also manual backups in `/sdcard/Tachioymi/`
  (latest from 2026-09-21). `/sdcard/TachiyomiSY-fork-test (1)/autobackup` is empty.
- Older copies are in `~/data/cloud/gdrive_backups/*/` (newest 2026-01-18).
  There were none in `~/Downloads`.
- **Copied (not committed):**
  `~/data/kartka/backup/eu.kanade.tachiyomi.sy_2026-10-24_08-29.tachibk`.
  It is 5,329,190 bytes (16,591,373 decompressed), modified on the phone at
  2026-10-24 08:30.
- Decoded with a throwaway decoder at
  `~/data/kartka/scratch/decode_tachibk.py` (stdlib only, not in the repo):

| Count | Value |
|---|---|
| manga entries | 2657 (**774 favourites**) |
| categories | 3 (+ implicit Default: 770 favourites) |
| chapters / read | 88,220 / 61,333 |
| entries with history | 2327 |
| sources listed | 24 (7 with favourites) |
| saved searches (SY) | 22 |
| trackers on favourites | MangaUpdates 483, AniList 117, Kitsu 109, Shikimori 85, MAL 84 |

Favourites per source:

| Source | id | Favs | Keiyoushi extension |
|---|---|---|---|
| AllManga | 4709139914729853090 | 381 | `en.allanime` |
| MangaDex | 2499283573021220255 | 258 | `all.mangadex` (also native) |
| MangaDot | 5900936305360403385 | 101 | `en.mangadotnet` |
| Cyanide & Happiness | 491094567635736188 | 20 | `en.explosm` |
| E-Hentai | 6901 | 9 | **none** (SY built-in source) |
| (unnamed) | 7890050626002177109 | 4 | **none** (no name in backup) |
| Gone with the Blastwave | 4006397036545425884 | 1 | `en.gwtb` |

The Keiyoushi lookup used `https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.json`
(`extensionList.extensions[].sources[].id`). The old `index.min.json` there is
now a 2-entry stub saying "Update to Mihon 0.20.1+".

## 5. Flags for the coordinator (not resolved here)

- **E-Hentai (6901/6902) are SY built-in sources, not extensions.**
  Suwayomi cannot serve them, so the contract's `suwayomi:<id>` fallback has
  no backend for those 9 favourites. Options: a native E-Hentai source, or
  accept them as "orphaned" in the import report.
- `7890050626002177109` has no `backupSources` name and no Keiyoushi match,
  so it is probably an uninstalled or removed extension: 4 orphans.
- MangaUpdates (483 favourites) is kuhy's dominant tracker. AniList has only
  117 and MAL 84. If v1 tracking stays AniList + MAL, most tracked
  favourites will not sync. Should MangaUpdates be in scope?
