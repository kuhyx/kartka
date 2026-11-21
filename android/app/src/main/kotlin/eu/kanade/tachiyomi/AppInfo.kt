package eu.kanade.tachiyomi

import com.kuhy.kartka.ext.ExtHost

@Suppress("UNUSED")
object AppInfo {
    fun getVersionCode(): Int = ExtHost.versionCode

    fun getVersionName(): String = ExtHost.versionName

    fun getSupportedImageMimeTypes(): List<String> =
        listOf("image/jpeg", "image/png", "image/gif", "image/webp", "image/avif")
}
