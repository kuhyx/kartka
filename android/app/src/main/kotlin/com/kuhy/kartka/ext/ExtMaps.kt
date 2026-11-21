package com.kuhy.kartka.ext

import eu.kanade.tachiyomi.source.CatalogueSource
import eu.kanade.tachiyomi.source.model.MangasPage
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.model.SManga
import eu.kanade.tachiyomi.source.online.HttpSource

/** Plain maps for the `kartka/ext` channel (StandardMessageCodec types). */
object ExtMaps {
    fun ext(e: LoadedExt): Map<String, Any?> = mapOf(
        "pkg" to e.pkg,
        "name" to e.name,
        "versionName" to e.versionName,
        "versionCode" to e.versionCode,
        "nsfw" to e.nsfw,
        "sources" to e.sources.map(::source),
    )

    fun source(s: CatalogueSource): Map<String, Any?> = mapOf(
        // Ids exceed 2^53: strings end to end, as for Suwayomi.
        "id" to s.id.toString(),
        "name" to s.name,
        "lang" to s.lang,
        "supportsLatest" to s.supportsLatest,
        "baseUrl" to (s as? HttpSource)?.baseUrl,
    )

    fun page(p: MangasPage): Map<String, Any?> = mapOf(
        "mangas" to p.mangas.map(::manga),
        "hasNextPage" to p.hasNextPage,
    )

    fun manga(m: SManga): Map<String, Any?> = mapOf(
        "url" to m.url,
        "title" to m.title,
        "thumbnailUrl" to m.thumbnail_url,
        "author" to m.author,
        "artist" to m.artist,
        "description" to m.description,
        "genre" to m.genre,
        "status" to m.status,
    )

    fun chapter(c: SChapter): Map<String, Any?> = mapOf(
        "url" to c.url,
        "name" to c.name,
        "number" to c.chapter_number.toDouble(),
        "dateUpload" to c.date_upload,
        "scanlator" to c.scanlator,
    )

    fun pageRef(p: Page): Map<String, Any?> = mapOf(
        "index" to p.index,
        "url" to p.url,
        "imageUrl" to p.imageUrl,
    )
}
