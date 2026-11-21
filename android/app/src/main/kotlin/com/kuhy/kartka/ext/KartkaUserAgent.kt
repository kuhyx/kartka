package com.kuhy.kartka.ext

/** Kartka's honest User-Agent, mirrored from `kartkaUserAgent` in Dart. */
object KartkaUserAgent {
    /** Set by Dart on `init`; the fallback matches lib/platform/http_client.dart. */
    @Volatile
    var value: String = "Kartka/0.1 (+https://github.com/kuhyx/kartka)"
}
