package com.marina.marina.data.remote

import com.google.gson.Gson
import org.junit.Assert.assertEquals
import org.junit.Test
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory

class CloudflareDeltaContractTest {
    /**
     * ✅ القيم نصية `"1"` — لا `"true"`.
     *
     * الـ Worker يفحص الأعلام بـ `=== '1'` حرفياً في مساري
     * `include_remaining`/`normalize_timestamps` (و`tombstones_only`
     * كذلك في كلا الفرعين: worker/src/sync.ts l.220-231 هنا وl.335-354 في
     * فرع Flutter)، وتطبيق Flutter يرسل `'1'` صراحةً
     * (cloudflare_sync_manager.dart l.2633/2634/3679). تمرير `Boolean` عبر
     * Retrofit كان يُنتج `"true"` فتُهمل الأعلام صامتة — أي أن
     * `tombstones_only` لم يكن ليُفعّل مسح الحذفيات إطلاقاً.
     */
    @Test
    fun retrofitSendsLiteralOneForServerFlags() {
        val api = Retrofit.Builder().baseUrl("https://example.com/")
            .addConverterFactory(GsonConverterFactory.create()).build()
            .create(CloudflareWorkerApi::class.java)
        val url = api.pull(123L, 250, null, "1", "1", "1").request().url
        assertEquals("123", url.queryParameter("cursor"))
        assertEquals("1", url.queryParameter("include_remaining"))
        assertEquals("1", url.queryParameter("normalize_timestamps"))
        assertEquals("1", url.queryParameter("tombstones_only"))

        // بلا طلب: المعاملات تغيب كلياً (نفس عقد Dart).
        val bare = api.pull(123L, 250, null, null, null, null).request().url
        assertEquals(null, bare.queryParameter("include_remaining"))
        assertEquals(null, bare.queryParameter("normalize_timestamps"))
        assertEquals(null, bare.queryParameter("tombstones_only"))
    }

    @Test
    fun gsonReadsExplicitRepairAndNormalizationAcknowledgements() {
        val page = Gson().fromJson("""{
            "cursor":"123", "changes":[], "has_more":true, "repair_pending":true,
            "normalization":{"complete":true,"remaining":0}
        }""", WorkerPullResponse::class.java)
        assertEquals(true, page.repairPending)
        assertEquals(true, page.normalization?.complete)
        assertEquals(0.0, page.normalization?.remaining)
    }
}
