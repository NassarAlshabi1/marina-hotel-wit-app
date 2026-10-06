package com.marina.marina.data.backup

import com.google.gson.Gson
import com.google.gson.JsonParseException
import com.google.gson.reflect.TypeToken
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response

/** D1 transport: retry network failures once, never API/JSON failures or cancellation. */
internal class D1HttpClient(
    private val calls: Call.Factory = OkHttpClient.Builder()
        .connectTimeout(CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .readTimeout(READ_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .writeTimeout(WRITE_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .build()
) {
    private val gson = Gson()

    suspend fun call(method: String, path: String, bodyJson: String?, token: String): Map<String, Any> {
        val request = Request.Builder()
            .url("https://api.cloudflare.com/client/v4$path")
            .header("Authorization", "Bearer $token")
            .apply {
                if (method == "GET") get()
                else post((bodyJson ?: "{}").toRequestBody(JSON_MEDIA_TYPE))
            }
            .build()
        repeat(MAX_ATTEMPTS) { attempt ->
            currentCoroutineContext().ensureActive()
            try {
                return calls.newCall(request).awaitDecodedResponse()
            } catch (error: IOException) {
                // A cancelled OkHttp call can report IOException instead of CancellationException.
                currentCoroutineContext().ensureActive()
                if (attempt == MAX_ATTEMPTS - 1) {
                    throw D1BackupException("تعذر الاتصال بـ Cloudflare", cause = error)
                }
            }
        }
        error("D1 retry loop exhausted without returning or throwing")
    }

    private fun decode(response: Response): Map<String, Any> {
        val failure = "فشل نداء Cloudflare (HTTP ${response.code})"
        val decoded = try {
            gson.fromJson<Map<String, Any>>(response.body?.string().orEmpty(), RESPONSE_TYPE)
        } catch (error: JsonParseException) {
            throw D1BackupException(failure, details = "رد JSON غير صالح", cause = error)
        } ?: throw D1BackupException(failure, details = "رد فارغ")
        if (!response.isSuccessful || decoded["success"] != true) {
            throw D1BackupException(failure, details = decoded["errors"]?.toString())
        }
        return decoded
    }

    private suspend fun Call.awaitDecodedResponse(): Map<String, Any> = suspendCancellableCoroutine { continuation ->
        continuation.invokeOnCancellation { cancel() }
        enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                continuation.resumeWithException(e)
            }

            override fun onResponse(call: Call, response: Response) {
                // Read on OkHttp's thread while the cancellation hook is still registered.
                // Close the body before dispatching a value, including the cancellation race.
                val outcome = try {
                    Result.success(response.use { decode(it) })
                } catch (error: IOException) {
                    Result.failure(error)
                } catch (error: D1BackupException) {
                    Result.failure(error)
                }
                continuation.resumeWith(outcome)
            }
        })
    }

    private companion object {
        const val MAX_ATTEMPTS = 2
        const val CONNECT_TIMEOUT_SECONDS = 20L
        const val READ_TIMEOUT_SECONDS = 90L
        const val WRITE_TIMEOUT_SECONDS = 120L
        val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
        val RESPONSE_TYPE = object : TypeToken<Map<String, Any>>() {}.type
    }
}
