package eu.kanade.tachiyomi.util

import kotlinx.coroutines.suspendCancellableCoroutine
import rx.Observable
import rx.Subscriber
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

suspend fun <T> Observable<T>.awaitSingle(): T = suspendCancellableCoroutine { cont ->
    val sub = first().subscribe(
        object : Subscriber<T>() {
            override fun onNext(t: T) {
                if (cont.isActive) cont.resume(t)
            }

            override fun onError(e: Throwable) {
                if (cont.isActive) cont.resumeWithException(e)
            }

            override fun onCompleted() = Unit
        },
    )
    cont.invokeOnCancellation { sub.unsubscribe() }
}
