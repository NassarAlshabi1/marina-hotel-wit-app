package com.marina.marina.data.remote

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.net.URI

/**
 * ✅ (2026-09-24) اختبارات سجل نقاط النهاية — تحرس نقل worker_endpoints.dart:
 * أولوية النطاق المخصّص، sticky الناجح، تنزيل الفاشل، وتطبيع الإدخال.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class WorkerEndpointsTest {

    private lateinit var endpoints: WorkerEndpoints

    @Before
    fun setUp() {
        WorkerEndpoints.resetForTests()
        val context = ApplicationProvider.getApplicationContext<Context>()
        // عزل prefs بين الاختبارات (نفس اسم ملف السجل).
        context.getSharedPreferences("marina_cloudflare_prefs", Context.MODE_PRIVATE)
            .edit().clear().commit()
        endpoints = WorkerEndpoints(context)
    }

    @After
    fun tearDown() {
        WorkerEndpoints.resetForTests()
    }

    @Test
    fun `active falls back to builtin without custom url`() {
        assertEquals(CloudflareConfig.BUILTIN_WORKER_URL, endpoints.active)
        assertNull(endpoints.custom)
        assertFalse(endpoints.hasCustom)
    }

    @Test
    fun `custom url takes priority over builtin`() {
        endpoints.setCustomUrl("sync.natak.com")
        assertEquals("https://sync.natak.com", endpoints.active)
        assertTrue(endpoints.hasCustom)
    }

    @Test
    fun `normalizeCustomUrl accepts bare domain and adds https`() {
        assertEquals("https://mydomain.com", endpoints.normalizeCustomUrl("mydomain.com"))
        assertEquals(
            "https://mydomain.com",
            endpoints.normalizeCustomUrl("https://mydomain.com/")
        )
        assertEquals(
            "https://mydomain.com:8443",
            endpoints.normalizeCustomUrl("https://mydomain.com:8443")
        )
    }

    @Test
    fun `normalizeCustomUrl rejects invalid input`() {
        assertNull(endpoints.normalizeCustomUrl(null))
        assertNull(endpoints.normalizeCustomUrl("  "))
        // أسماء فاسدة ترمي (شاشة الدخول تعرض الرسالة للمستخدم).
        assertThrows<IllegalArgumentException> { endpoints.normalizeCustomUrl("not a url") }
        assertThrows<IllegalArgumentException> { endpoints.normalizeCustomUrl("http://insecure.com") }
        assertThrows<IllegalArgumentException> { endpoints.normalizeCustomUrl("https://x.com/path") }
        assertThrows<IllegalArgumentException> { endpoints.normalizeCustomUrl("localhost") }
    }

    @Test
    fun `clearing custom url returns to builtin`() {
        endpoints.setCustomUrl("sync.natak.com")
        assertEquals("https://sync.natak.com", endpoints.active)
        endpoints.setCustomUrl(null)
        assertEquals(CloudflareConfig.BUILTIN_WORKER_URL, endpoints.active)
    }

    @Test
    fun `success pins sticky endpoint for the session`() {
        endpoints.setCustomUrl("sync.natak.com")
        // نجاح على المدمج يثبّته sticky (رغم وجود المخصّص) خلال الجلسة.
        endpoints.reportSuccess(URI(CloudflareConfig.BUILTIN_WORKER_URL))
        assertEquals(CloudflareConfig.BUILTIN_WORKER_URL, endpoints.active)
    }

    @Test
    fun `session restart prefers custom when one exists`() {
        // عقد Flutter load(): نطاق مخصّص موجود = إشارة أن المدمج محجوب —
        // الجلسة الجديدة تبدأ عليه حتى لو كان sticky السابق المدمج؛ الفشل
        // يصحّح التدوير تلقائياً والنجاح يعيد التثبيت خلال الجلسة.
        endpoints.setCustomUrl("sync.natak.com")
        endpoints.reportSuccess(URI(CloudflareConfig.BUILTIN_WORKER_URL))
        WorkerEndpoints.resetForTests()
        assertEquals("https://sync.natak.com", endpoints.active)
    }

    @Test
    fun `failure demotes endpoint and rotates to the other candidate`() {
        endpoints.setCustomUrl("sync.natak.com")
        // فشل المخصّص → التدوير للمدمج.
        endpoints.reportFailure(URI("https://sync.natak.com"))
        assertEquals(CloudflareConfig.BUILTIN_WORKER_URL, endpoints.active)
        // فشل المدمج → العودة للمخصّص.
        endpoints.reportFailure(URI(CloudflareConfig.BUILTIN_WORKER_URL))
        assertEquals("https://sync.natak.com", endpoints.active)
    }

    @Test
    fun `candidates order follows active endpoint first`() {
        // العميل يبني الطلب على النقطة الفعّالة (المخصّص عند وجوده) —
        // المرشح الأول هو الفعّالة ثم المدمج (نفس candidatesFor(active)
        // في WorkerFailoverInterceptor).
        endpoints.setCustomUrl("sync.natak.com")
        val candidates = endpoints.candidatesFor(URI(endpoints.active))
        assertEquals(2, candidates.size)
        assertEquals("sync.natak.com", candidates[0].host)
        assertEquals("marina-hotel-api.adenmarina2.workers.dev", candidates[1].host)
    }

    @Test
    fun `non worker urls are fully isolated`() {
        val external = URI("https://api.cloudflare.com/client/v4")
        val candidates = endpoints.candidatesFor(external)
        assertEquals(1, candidates.size)
        assertEquals("api.cloudflare.com", candidates[0].host)
        assertFalse(endpoints.isWorkerEndpoint(external))
    }

    @Test
    fun `prefs restore prefers custom when sticky equals builtin`() {
        // نطاق مخصّص موجود = إشارة أن المدمج محجوب — الجلسة الجديدة تبدأ
        // عليه حتى لو كان sticky السابق المدمج (نفس منطق load في Flutter).
        val context = ApplicationProvider.getApplicationContext<Context>()
        val prefs = context.getSharedPreferences("marina_cloudflare_prefs", Context.MODE_PRIVATE)
        prefs.edit()
            .putString(WorkerEndpoints.CUSTOM_URL_KEY, "https://sync.natak.com")
            .putString(WorkerEndpoints.ACTIVE_URL_KEY, CloudflareConfig.BUILTIN_WORKER_URL)
            .commit()
        WorkerEndpoints.resetForTests()
        assertEquals("https://sync.natak.com", endpoints.active)
        assertNotNull(endpoints.custom)
    }

    private inline fun <reified T : Throwable> assertThrows(block: () -> Unit) {
        try {
            block()
            error("Expected ${T::class.java.simpleName} to be thrown")
        } catch (expected: Throwable) {
            if (!T::class.java.isInstance(expected)) throw expected
        }
    }
}
