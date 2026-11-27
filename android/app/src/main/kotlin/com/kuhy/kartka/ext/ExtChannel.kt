package com.kuhy.kartka.ext

import android.app.Application
import eu.kanade.tachiyomi.source.CatalogueSource
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.model.SManga
import eu.kanade.tachiyomi.source.model.SMangaUpdate
import eu.kanade.tachiyomi.source.online.HttpSource
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.runInterruptible
import kotlinx.coroutines.withContext
import java.io.File

/**
 * `kartka/ext`: Dart's door to the in-app extension runtime. Every call
 * runs off the main thread; errors come back as `ext_error` with the
 * extension's own message.
 */
class ExtChannel(private val app: Application, messenger: BinaryMessenger) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val channel = MethodChannel(messenger, "kartka/ext")
    private var loader: ExtLoader? = null
    private val exts = linkedMapOf<String, LoadedExt>()
    private val failed = linkedMapOf<String, String>()
    private val background = BackgroundCalls()
    private val inFlight = hashMapOf<String, Deferred<SMangaUpdate>>()

    init {
        channel.setMethodCallHandler { call, result ->
            // On the main thread, so it lands before the reader's next call.
            if (call.method == "cancelBackground") {
                result.success(background.cancelAll())
                return@setMethodCallHandler
            }
            val job = scope.launch(start = CoroutineStart.LAZY) {
                val reply = try {
                    Result.success(handle(call))
                } catch (e: Throwable) {
                    Result.failure(e)
                }
                val cancelled = reply.isFailure && !isActive
                // A cancelled call still answers, or Dart waits forever.
                withContext(NonCancellable + Dispatchers.Main) {
                    if (cancelled) {
                        result.error("cancelled", "cancelled", null)
                        return@withContext
                    }
                    reply.fold(
                        { if (it === NotImplemented) result.notImplemented() else result.success(it) },
                        { result.error("ext_error", it.message ?: it.javaClass.name, it.javaClass.name) },
                    )
                }
            }
            if (call.argument<Boolean>("background") == true) background.add(job)
            job.start()
        }
    }

    private fun source(call: MethodCall): CatalogueSource {
        val id = call.argument<String>("id")!!.toLong()
        return exts.values.flatMap { it.sources }.firstOrNull { it.id == id }
            ?: throw ExtError("source $id is not installed")
    }

    private fun installedMap(): Map<String, Any?> = mapOf(
        "installed" to exts.values.map(ExtMaps::ext),
        "failed" to failed.toMap(),
    )

    private suspend fun handle(call: MethodCall): Any? = when (call.method) {
        "init" -> {
            call.argument<String>("userAgent")?.let { KartkaUserAgent.value = it }
            ExtHost.init(app)
            val l = ExtLoader(app, call.argument<List<String>>("trusted")!!.toSet())
            loader = l
            val (ok, bad) = l.loadAll()
            exts.clear()
            ok.forEach { exts[it.pkg] = it }
            failed.clear()
            failed.putAll(bad)
            installedMap()
        }
        "installed" -> installedMap()
        "install" -> {
            val tmp = File.createTempFile("ext", ".apk", app.cacheDir)
            tmp.writeBytes(call.argument<ByteArray>("apk")!!)
            val e = (loader ?: throw ExtError("call init first")).install(tmp)
            exts[e.pkg] = e
            failed.remove(e.pkg)
            ExtMaps.ext(e)
        }
        "uninstall" -> {
            val pkg = call.argument<String>("pkg")!!
            exts.remove(pkg)
            loader?.uninstall(pkg) ?: false
        }
        "popular" -> ExtMaps.page(source(call).getPopularManga(call.argument<Int>("page")!!))
        "latest" -> ExtMaps.page(source(call).getLatestUpdates(call.argument<Int>("page")!!))
        "search" -> {
            val s = source(call)
            ExtMaps.page(s.getSearchManga(call.argument<Int>("page")!!, call.argument<String>("query")!!, s.getFilterList()))
        }
        "details" -> ExtMaps.manga(update(call).manga)
        "chapters" -> update(call).chapters.map(ExtMaps::chapter)
        "pages" -> {
            val chapter = SChapter.create().apply { url = call.argument<String>("url")!! }
            source(call).getPageList(chapter).map(ExtMaps::pageRef)
        }
        "image" -> image(call)
        else -> NotImplemented
    }

    /**
     * Details and chapters of one manga from ONE getMangaUpdate call.
     * Extensions refuse two concurrent calls for the same manga, and the
     * details screen asks for both at once, so a second request joins the
     * call already in flight.
     */
    private suspend fun update(call: MethodCall): SMangaUpdate {
        val source = source(call)
        val url = call.argument<String>("url")!!
        val key = "${source.id}|$url"
        val job = synchronized(inFlight) {
            inFlight.getOrPut(key) {
                scope.async {
                    try {
                        source.getMangaUpdate(
                            SManga.create().apply {
                                this.url = url
                                title = call.argument<String>("title") ?: ""
                            },
                            emptyList(),
                            fetchDetails = true,
                            fetchChapters = true,
                        )
                    } finally {
                        synchronized(inFlight) { inFlight.remove(key) }
                    }
                }
            }
        }
        return job.await()
    }

    /** Image bytes through the source's own client, so its interceptors run. */
    private suspend fun image(call: MethodCall): ByteArray {
        val s = source(call) as? HttpSource ?: throw ExtError("not an HTTP source")
        val page = Page(call.argument<Int>("index")!!, call.argument<String>("url") ?: "", call.argument<String>("imageUrl"))
        if (page.imageUrl.isNullOrEmpty()) page.imageUrl = s.getImageUrl(page)
        // Interruptible: most of a page's time is its body, read after the
        // call's own cancel hook is gone (cancelBackground).
        return s.getImage(page).use { runInterruptible { it.body.bytes() } }
    }

    private object NotImplemented
}
