package com.kuhy.kartka.ext

import android.app.Application
import android.content.Context
import eu.kanade.tachiyomi.network.NetworkHelper
import kotlinx.serialization.json.Json
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.addSingleton
import uy.kohesive.injekt.api.addSingletonFactory
import uy.kohesive.injekt.api.fullType

/**
 * The services a loaded Tachiyomi/Keiyoushi extension pulls from Injekt:
 * the app context, the shared HTTP client and a lenient Json.
 */
object ExtHost {
    @Volatile
    private var ready = false

    var versionCode: Int = 0
        private set
    var versionName: String = ""
        private set

    @Synchronized
    fun init(app: Application) {
        if (ready) return
        val info = app.packageManager.getPackageInfo(app.packageName, 0)
        @Suppress("DEPRECATION")
        versionCode = info.versionCode
        versionName = info.versionName.orEmpty()
        Injekt.addSingleton(fullType<Application>(), app)
        Injekt.addSingleton(fullType<Context>(), app)
        Injekt.addSingletonFactory { NetworkHelper(app) }
        Injekt.addSingletonFactory {
            Json {
                ignoreUnknownKeys = true
                explicitNulls = false
            }
        }
        ready = true
    }
}
