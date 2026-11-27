package com.kuhy.kartka.ext

import kotlinx.coroutines.Job
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap

/**
 * The background calls (downloads, Dart's `runAsBackground`) in flight.
 * A shown page that starts loading cancels them all (`cancelBackground`):
 * downloads in flight made an open's page list and page 1 take 1 s each
 * instead of 0.2 s (kartka, 64f0bd6f). Dart fetches them again after.
 */
class BackgroundCalls {
    private val jobs: MutableSet<Job> = Collections.newSetFromMap(ConcurrentHashMap())

    /** Tracks [job] until it completes. */
    fun add(job: Job) {
        jobs.add(job)
        job.invokeOnCompletion { jobs.remove(job) }
    }

    /** Cancels every tracked job; returns how many. */
    fun cancelAll(): Int {
        val now = jobs.toList()
        now.forEach { it.cancel() }
        return now.size
    }
}
