package com.marina.marina.data.remote

import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import retrofit2.Call
import retrofit2.Callback
import retrofit2.Response

/** Used by the short startup probe: cancellation also cancels the actual HTTP call. */
internal suspend fun <T> Call<T>.awaitProbeResponse(): Response<T> = suspendCancellableCoroutine { continuation ->
    continuation.invokeOnCancellation { cancel() }
    if (continuation.isActive) enqueue(object : Callback<T> {
        override fun onResponse(call: Call<T>, response: Response<T>) {
            response.errorBody()?.close()
            if (continuation.isActive) continuation.resume(response)
        }
        override fun onFailure(call: Call<T>, error: Throwable) {
            if (continuation.isActive) continuation.resumeWithException(error)
        }
    })
}
