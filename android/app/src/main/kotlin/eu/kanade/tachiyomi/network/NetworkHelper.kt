package eu.kanade.tachiyomi.network

import android.content.Context
import com.kuhy.kartka.ext.KartkaUserAgent
import eu.kanade.tachiyomi.network.interceptor.CloudflareInterceptor
import eu.kanade.tachiyomi.network.interceptor.UncaughtExceptionInterceptor
import eu.kanade.tachiyomi.network.interceptor.UserAgentInterceptor
import okhttp3.Cache
import okhttp3.OkHttpClient
import java.io.File
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds

class NetworkHelper(context: Context) {

    val cookieJar = AndroidCookieJar()

    val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .cookieJar(cookieJar)
            .connectTimeout(30.seconds)
            .readTimeout(30.seconds)
            .callTimeout(2.minutes)
            .cache(Cache(File(context.cacheDir, "ext_network_cache"), 5L * 1024 * 1024))
            // First, as in Mihon: Keiyoushi's lib looks it up by class name
            // and inserts its own interceptors right after it.
            .addInterceptor(UncaughtExceptionInterceptor())
            .addInterceptor(UserAgentInterceptor(::defaultUserAgentProvider))
            // Keiyoushi's lib refuses a client with BrotliInterceptor and
            // needs one named CloudflareInterceptor (Mihon's layout).
            .addInterceptor(CloudflareInterceptor())
            .build()
    }

    @Deprecated("The regular client handles Cloudflare by default")
    @Suppress("UNUSED")
    val cloudflareClient: OkHttpClient get() = client

    fun defaultUserAgentProvider() = KartkaUserAgent.value
}
