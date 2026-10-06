package com.marina.marina.data.remote

import com.google.gson.Gson
import org.junit.Assert.assertEquals
import org.junit.Test
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory

class CloudflareDeltaContractTest {
    @Test
    fun retrofitSendsBooleanTrueForFullReplayFlags() {
        val api = Retrofit.Builder().baseUrl("https://example.com/")
            .addConverterFactory(GsonConverterFactory.create()).build()
            .create(CloudflareWorkerApi::class.java)
        val url = api.pull(123L, 250, null, true, true).request().url
        assertEquals("123", url.queryParameter("cursor"))
        assertEquals("true", url.queryParameter("include_remaining"))
        assertEquals("true", url.queryParameter("normalize_timestamps"))
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
