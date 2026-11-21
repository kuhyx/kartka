package eu.kanade.tachiyomi.network.interceptor

import okhttp3.Interceptor
import okhttp3.Response
import java.io.IOException

/**
 * Kartka's stand-in for Mihon's Cloudflare solver. Keiyoushi's lib refuses
 * a default client without an interceptor of this simple name, and adds
 * its own interceptors after it.
 *
 * It does not solve challenges (no hidden WebView). It turns a challenge
 * page into a clear error instead: solving it once in kartka's in-app
 * WebView ("Open in WebView") sets the cookie, which the shared
 * [eu.kanade.tachiyomi.network.AndroidCookieJar] then sends.
 */
class CloudflareInterceptor : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val response = chain.proceed(chain.request())
        if (!isChallenge(response)) return response
        response.close()
        throw IOException("Cloudflare challenge: open the source in WebView once")
    }

    private fun isChallenge(response: Response): Boolean =
        response.header("cf-mitigated") == "challenge" ||
            (response.code in CHALLENGE_CODES && response.header("Server") in SERVER_NAMES)

    private companion object {
        val CHALLENGE_CODES = setOf(403, 503)
        val SERVER_NAMES = setOf("cloudflare-nginx", "cloudflare")
    }
}
