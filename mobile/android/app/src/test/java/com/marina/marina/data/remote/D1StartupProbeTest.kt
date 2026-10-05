package com.marina.marina.data.remote

import android.app.Application
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.marina.marina.di.EncryptedSharedPreferencesManager
import java.lang.reflect.Proxy
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.runBlocking
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import retrofit2.Call
import retrofit2.Callback
import retrofit2.Response

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class D1StartupProbeTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val prefs: SyncPreferences get() = SyncPreferences(EncryptedSharedPreferencesManager(context))

    @Suppress("UNCHECKED_CAST")
    private fun call(response: Response<*>): Call<Any> = Proxy.newProxyInstance(
        Call::class.java.classLoader, arrayOf(Call::class.java)
    ) { proxy, method, args ->
        when (method.name) {
            "enqueue" -> { (args!![0] as Callback<Any>).onResponse(proxy as Call<Any>, response as Response<Any>); null }
            "cancel" -> null
            else -> error("Unexpected call: ${method.name}")
        }
    } as Call<Any>

    private fun service(handler: (String) -> Call<*>): CloudflareSyncService {
        prefs.saveAuthToken("synthetic-worker-jwt")
        prefs.saveLastPullCursor(123)
        prefs.saveLastPullTs(456)
        val api = Proxy.newProxyInstance(CloudflareWorkerApi::class.java.classLoader,
            arrayOf(CloudflareWorkerApi::class.java)) { _, method, _ -> handler(method.name) } as CloudflareWorkerApi
        return CloudflareSyncService(api, CloudflareConfig(context), prefs)
    }

    @Test fun onlyAuthenticatedD1OkCountsAsConnectionWithoutChangingCursor() = runBlocking {
        for (body in listOf(WorkerD1HealthResponse("ok", "ok"), WorkerD1HealthResponse("ok", null),
            WorkerD1HealthResponse("error", "unreachable"))) {
            val service = service { method ->
                assertEquals("d1Health", method) // Worker /health and stats are not sufficient.
                call(Response.success(body))
            }
            assertEquals(body.d1 == "ok", service.checkD1Connection())
            assertEquals(123L, prefs.getLastPullCursor()); assertEquals(456L, prefs.getLastPullTs())
        }
    }

    @Test fun expiredTokenReauthenticatesOnceThenRequiresD1Success() = runBlocking {
        var health = 0
        var login = 0
        val service = service { method ->
            when (method) {
                "d1Health" -> if (++health == 1) call(Response.error<WorkerD1HealthResponse>(401, "{}".toResponseBody()))
                    else call(Response.success(WorkerD1HealthResponse("ok", "ok")))
                "login" -> { login++; call(Response.success(WorkerLoginResponse(token = "renewed-fixture-token", user = null))) }
                else -> error("Unexpected mutation $method")
            }
        }
        assertTrue(service.checkD1Connection())
        assertEquals(2, health); assertEquals(1, login)
        assertEquals("renewed-fixture-token", prefs.getAuthToken())
    }

    @Test fun unavailableD1AndRepeatedUnauthorizedNeverAdvanceCheckpoint() = runBlocking {
        var logins = 0
        val service = service { method ->
            if (method == "login") {
                logins++
                call(Response.success(WorkerLoginResponse("new-but-rejected", null)))
            } else {
                assertEquals("d1Health", method)
                call(Response.error<WorkerD1HealthResponse>(401, "{}".toResponseBody()))
            }
        }
        assertFalse(service.checkD1Connection())
        assertEquals(1, logins)
        val unavailable = service { call(Response.error<WorkerD1HealthResponse>(503, "{}".toResponseBody())) }
        assertFalse(unavailable.checkD1Connection())
        assertEquals(123L, prefs.getLastPullCursor()); assertEquals(456L, prefs.getLastPullTs())
    }

    @Test fun unresponsiveD1HitsTheEightSecondDeadlineAndCancelsItsCall() = runBlocking {
        var cancelled = false
        val service = service {
            Proxy.newProxyInstance(Call::class.java.classLoader, arrayOf(Call::class.java)) { _, method, _ ->
                when (method.name) {
                    "enqueue" -> null // Never completes: timeout must cancel the request.
                    "cancel" -> { cancelled = true; null }
                    else -> error(method.name)
                }
            } as Call<*>
        }
        assertFalse(kotlinx.coroutines.withTimeout(15_000L) { service.checkD1Connection() })
        assertTrue(cancelled)
        assertEquals(123L, prefs.getLastPullCursor()); assertEquals(456L, prefs.getLastPullTs())
    }

    @Test fun cancellationCancelsRealCallAndDoesNotStampSuccess() = runBlocking {
        val enqueued = CompletableDeferred<Unit>()
        var cancelled = false
        val service = service {
            Proxy.newProxyInstance(Call::class.java.classLoader, arrayOf(Call::class.java)) { _, method, _ ->
                when (method.name) {
                    "enqueue" -> { enqueued.complete(Unit); null }
                    "cancel" -> { cancelled = true; null }
                    else -> error(method.name)
                }
            } as Call<*>
        }
        val job = async(start = CoroutineStart.UNDISPATCHED) { service.checkD1Connection() }
        enqueued.await(); job.cancelAndJoin()
        assertTrue(cancelled)
        assertEquals(123L, prefs.getLastPullCursor()); assertEquals(456L, prefs.getLastPullTs())
    }
}
