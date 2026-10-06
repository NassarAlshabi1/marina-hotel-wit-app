package com.marina.marina.data.remote

import java.lang.reflect.Proxy
import okhttp3.Interceptor
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class WorkerSourceHeaderInterceptorTest {
    private fun runInterceptor(sourceId: String?, token: String? = "worker-jwt"): Request {
        val original = Request.Builder()
            .url("https://worker.example/api/sync/push")
            .post("{}".toRequestBody())
            .build()
        var sent: Request? = null
        val chain = Proxy.newProxyInstance(
            Interceptor.Chain::class.java.classLoader,
            arrayOf(Interceptor.Chain::class.java)
        ) { _, method, args ->
            when (method.name) {
                "request" -> original
                "proceed" -> {
                    sent = args!![0] as Request
                    Response.Builder()
                        .request(sent!!)
                        .protocol(Protocol.HTTP_1_1)
                        .code(200)
                        .message("OK")
                        .body("{}".toResponseBody())
                        .build()
                }
                else -> error("Unexpected chain method ${method.name}")
            }
        } as Interceptor.Chain

        WorkerAuthInterceptor(
            tokenProvider = { token },
            sourceIdProvider = { sourceId }
        ).intercept(chain)
        return sent ?: error("request did not proceed")
    }

    @Test
    fun `pinned source identity accompanies authenticated sync requests`() {
        val request = runInterceptor("0123456789ABCDEF0123456789ABCDEF")

        assertEquals("0123456789abcdef0123456789abcdef", request.header("X-Sync-Source-Id"))
        assertEquals("Bearer worker-jwt", request.header("Authorization"))
    }

    @Test
    fun `unbound or local-auth sessions do not send a source binding`() {
        assertNull(runInterceptor(null).header("X-Sync-Source-Id"))
        assertNull(runInterceptor("0123456789abcdef0123456789abcdef", token = null)
            .header("X-Sync-Source-Id"))
    }
}
