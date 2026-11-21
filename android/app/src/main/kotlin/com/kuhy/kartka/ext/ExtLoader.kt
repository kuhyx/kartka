package com.kuhy.kartka.ext

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import dalvik.system.DelegateLastClassLoader
import eu.kanade.tachiyomi.source.CatalogueSource
import eu.kanade.tachiyomi.source.Source
import eu.kanade.tachiyomi.source.SourceFactory
import java.io.File
import java.security.MessageDigest

/** One extension APK loaded in-process: its package and catalogue sources. */
data class LoadedExt(
    val pkg: String,
    val name: String,
    val versionName: String,
    val versionCode: Long,
    val libVersion: Double,
    val nsfw: Boolean,
    val sources: List<CatalogueSource>,
)

/**
 * Loads Keiyoushi extension APKs privately (no system install), as Mihon's
 * ExtensionLoader does: APK -> read-only file -> DelegateLastClassLoader.
 * Only APKs signed by a trusted repo key load.
 */
class ExtLoader(private val context: Context, private val trusted: Set<String>) {
    private val dir = File(context.filesDir, "exts").apply { mkdirs() }

    private fun fileFor(pkg: String) = File(dir, "$pkg.ext")

    /** Verifies [apk] and moves it into place; returns the loaded extension. */
    fun install(apk: File): LoadedExt {
        val info = archiveInfo(apk) ?: throw ExtError("not an APK")
        val pkg = info.packageName
        val target = fileFor(pkg)
        if (target.exists()) {
            target.setWritable(true)
            target.delete()
        }
        if (!apk.renameTo(target)) {
            apk.copyTo(target, overwrite = true)
            apk.delete()
        }
        // Android 14+ refuses to load writable dex.
        target.setReadOnly()
        return load(target)
    }

    fun uninstall(pkg: String): Boolean {
        val f = fileFor(pkg)
        f.setWritable(true)
        return f.delete()
    }

    /** Every installed extension; one broken APK never hides the others. */
    fun loadAll(): Pair<List<LoadedExt>, Map<String, String>> {
        val ok = mutableListOf<LoadedExt>()
        val failed = mutableMapOf<String, String>()
        for (f in dir.listFiles().orEmpty().filter { it.name.endsWith(".ext") }) {
            try {
                ok += load(f)
            } catch (e: Throwable) {
                failed[f.name.removeSuffix(".ext")] = e.message ?: e.javaClass.name
            }
        }
        return ok to failed
    }

    private fun load(file: File): LoadedExt {
        val info = archiveInfo(file) ?: throw ExtError("not an APK: ${file.name}")
        val app = info.applicationInfo ?: throw ExtError("no application info")
        app.sourceDir = file.absolutePath
        app.publicSourceDir = file.absolutePath
        val meta = app.metaData ?: throw ExtError("no extension metadata")
        val features = info.reqFeatures.orEmpty().map { it.name }
        if (EXTENSION_FEATURE !in features) throw ExtError("${info.packageName} is not an extension")
        val lib = libVersion(info.versionName.orEmpty())
        if (lib < LIB_MIN || lib > LIB_MAX) throw ExtError("unsupported extension lib $lib")
        val signers = signatures(info)
        if (signers.none { it in trusted }) throw ExtError("untrusted signer ${signers.firstOrNull()}")
        val loader = DelegateLastClassLoader(file.absolutePath, null, context.classLoader)
        val classes = meta.getString(METADATA_SOURCE_CLASS)?.split(";")?.map { it.trim() }
            ?.filter { it.isNotEmpty() }
            ?.map { if (it.startsWith(".")) info.packageName + it else it }
            ?: throw ExtError("no source class")
        val sources = classes.flatMap { name ->
            when (val obj = Class.forName(name, false, loader).getDeclaredConstructor().newInstance()) {
                is Source -> listOf(obj)
                is SourceFactory -> obj.createSources()
                else -> throw ExtError("unknown source class ${obj.javaClass}")
            }
        }.filterIsInstance<CatalogueSource>()
        @Suppress("DEPRECATION")
        val code = if (android.os.Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
        return LoadedExt(
            pkg = info.packageName,
            name = app.nonLocalizedLabel?.toString()?.removePrefix("Tachiyomi: ") ?: info.packageName,
            versionName = info.versionName.orEmpty(),
            versionCode = code,
            libVersion = lib,
            nsfw = meta.getInt(METADATA_NSFW) == 1,
            sources = sources,
        )
    }

    private fun archiveInfo(file: File): PackageInfo? =
        context.packageManager.getPackageArchiveInfo(file.absolutePath, FLAGS)

    companion object {
        private const val EXTENSION_FEATURE = "tachiyomi.extension"
        private const val METADATA_SOURCE_CLASS = "tachiyomi.extension.class"
        private const val METADATA_NSFW = "tachiyomi.extension.nsfw"
        private const val LIB_MIN = 1.4
        private const val LIB_MAX = 1.6

        @Suppress("DEPRECATION")
        private val FLAGS = PackageManager.GET_CONFIGURATIONS or PackageManager.GET_META_DATA or
            PackageManager.GET_SIGNATURES or PackageManager.GET_SIGNING_CERTIFICATES

        /** `1.6.38` -> 1.6: the lib version is the versionName's first two parts. */
        fun libVersion(versionName: String): Double =
            versionName.split(".").take(2).joinToString(".").toDoubleOrNull() ?: 0.0

        fun signatures(info: PackageInfo): List<String> {
            val s = info.signingInfo ?: return emptyList()
            val certs = if (s.hasMultipleSigners()) s.apkContentsSigners else s.signingCertificateHistory
            return certs.orEmpty().map { sha256(it.toByteArray()) }
        }

        private fun sha256(bytes: ByteArray): String =
            MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    }
}

class ExtError(message: String) : Exception(message)
