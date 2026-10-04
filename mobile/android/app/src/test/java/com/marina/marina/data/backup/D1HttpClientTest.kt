package com.marina.marina.data.backup

import java.io.IOException
import java.util.ArrayDeque
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody
import okio.Buffer
import okio.BufferedSource
import okio.ForwardingSource
import okio.Timeout
import okio.buffer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Entirely in memory: no DNS, sockets, real tokens or production data. */
@OptIn(ExperimentalCoroutinesApi::class)
class D1HttpClientTest {
    @Test
    fun successUsesExpectedRequestAndClosesBody() = runTest {
        val factory = FakeCalls()
        val body = TrackedBody("""{"success":true,"result":[]}""")
        factory.actions.add { call, callback -> callback.onResponse(call, response(call, 200, body)) }
        val result = D1HttpClient(factory).call("POST", "/test", "{\"sql\":\"SELECT 1\"}", "test-only")
        assertEquals(true, result["success"])
        val request = factory.created.single().request()
        assertEquals("POST", request.method)
        assertEquals("https://api.cloudflare.com/client/v4/test", request.url.toString())
        assertEquals("Bearer test-only", request.header("Authorization"))
        val buffer = Buffer()
        request.body!!.writeTo(buffer)
        assertEquals("{\"sql\":\"SELECT 1\"}", buffer.readUtf8())
        assertTrue(body.closed)
    }

    @Test
    fun transientNetworkFailureRetriesOnce() = runTest {
        val factory = FakeCalls()
        factory.actions.add { call, callback -> callback.onFailure(call, IOException("offline")) }
        factory.actions.add { call, callback ->
            callback.onResponse(call, response(call, 200, TrackedBody("""{"success":true}""")))
        }
        assertEquals(true, D1HttpClient(factory).call("GET", "/test", null, "test-only")["success"])
        assertEquals(2, factory.created.size)
        assertEquals("GET", factory.created.last().request().method)
    }

    @Test
    fun networkRetryIsBoundedAndRetainsCause() = runTest {
        val factory = FakeCalls()
        val cause = IOException("offline")
        repeat(2) { factory.actions.add { call, callback -> callback.onFailure(call, cause) } }
        try {
            D1HttpClient(factory).call("GET", "/test", null, "test-only")
            throw AssertionError("Expected failure")
        } catch (error: D1BackupException) {
            // Coroutine stack-trace recovery may wrap IOException; retain the original in the cause chain.
            assertTrue(generateSequence(error.cause) { it.cause }.any { it === cause })
        }
        assertEquals(2, factory.created.size)
    }

    @Test
    fun malformedEmptyApiAndHttpErrorsNeverRetryAndAlwaysCloseBody() = runTest {
        val cases = listOf(
            200 to "not json", 200 to "", 200 to "null", 200 to "[]",
            200 to """{"success":false,"errors":[{"message":"denied"}]}""",
            503 to """{"success":true}""", 401 to """{"success":false}"""
        )
        for ((code, text) in cases) {
            val factory = FakeCalls()
            val body = TrackedBody(text)
            factory.actions.add { call, callback -> callback.onResponse(call, response(call, code, body)) }
            try {
                D1HttpClient(factory).call("GET", "/test", null, "test-only")
                throw AssertionError("Expected failure for HTTP $code / $text")
            } catch (error: D1BackupException) {
                assertTrue(error.message.orEmpty().contains("HTTP $code"))
            }
            assertEquals(1, factory.created.size)
            assertTrue(body.closed)
        }
    }

    @Test
    fun cancellationCancelsOutstandingCallWithoutRetry() = runTest {
        val factory = FakeCalls()
        var pending: Callback? = null
        factory.actions.add { _, callback -> pending = callback }
        val job = launch { D1HttpClient(factory).call("GET", "/test", null, "test-only") }
        runCurrent()
        job.cancel()
        runCurrent()
        val call = factory.created.single()
        assertTrue(call.isCanceled())
        pending!!.onFailure(call, IOException("Canceled"))
        runCurrent()
        assertTrue(job.isCancelled)
        assertEquals(1, factory.created.size)
    }

    @Test
    fun cancellationBetweenResponseAndDispatchKeepsBodyClosed() = runTest {
        val factory = FakeCalls()
        var pending: Callback? = null
        factory.actions.add { _, callback -> pending = callback }
        val job = launch { D1HttpClient(factory).call("GET", "/test", null, "test-only") }
        runCurrent()
        val call = factory.created.single()
        val body = TrackedBody("""{"success":true}""")
        pending!!.onResponse(call, response(call, 200, body))
        assertTrue(body.closed)
        job.cancel(CancellationException("screen closed"))
        runCurrent()
        assertTrue(body.closed)
        assertTrue(job.isCancelled)
        assertEquals(1, factory.created.size)
    }

    @Test
    fun cancellationDuringBodyReadClosesBodyAndDoesNotRetry() = runTest {
        val factory = FakeCalls()
        lateinit var job: kotlinx.coroutines.Job
        val body = TrackedBody("pending body") {
            job.cancel()
            throw IOException("Canceled during read")
        }
        factory.actions.add { call, callback -> callback.onResponse(call, response(call, 200, body)) }
        job = launch { D1HttpClient(factory).call("GET", "/test", null, "test-only") }
        runCurrent()
        assertTrue(job.isCancelled)
        assertTrue(factory.created.single().isCanceled())
        assertTrue(body.closed)
    }

    private class FakeCalls : Call.Factory {
        val actions = ArrayDeque<(FakeCall, Callback) -> Unit>()
        val created = mutableListOf<FakeCall>()
        override fun newCall(request: Request): Call = FakeCall(request, actions.removeFirst()).also(created::add)
    }

    private class FakeCall(
        private val request: Request,
        private val action: (FakeCall, Callback) -> Unit
    ) : Call {
        private var cancelled = false
        private var executed = false
        override fun request() = request
        override fun execute(): Response = error("Blocking execute must not be used")
        override fun enqueue(responseCallback: Callback) {
            executed = true
            action(this, responseCallback)
        }
        override fun cancel() { cancelled = true }
        override fun isExecuted() = executed
        override fun isCanceled() = cancelled
        override fun timeout() = Timeout.NONE
        override fun clone(): Call = FakeCall(request, action)
    }

    private class TrackedBody(text: String, private val onRead: () -> Unit = {}) : ResponseBody() {
        var closed = false
        private val data = object : ForwardingSource(Buffer().writeUtf8(text)) {
            override fun read(sink: Buffer, byteCount: Long): Long {
                onRead()
                return super.read(sink, byteCount)
            }
            override fun close() {
                closed = true
                super.close()
            }
        }.buffer()
        override fun contentType(): MediaType? = null
        override fun contentLength() = -1L
        override fun source(): BufferedSource = data
    }

    private fun response(call: Call, code: Int, body: ResponseBody): Response = Response.Builder()
        .request(call.request()).protocol(Protocol.HTTP_1_1).code(code).message("test").body(body).build()
}
