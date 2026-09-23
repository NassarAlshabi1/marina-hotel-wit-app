package com.marina.marina.data.remote

import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

/**
 * ✅ (2026-09-24) اتصال D1 REST مباشر — جوهر نقل CloudflareD1Service من
 * Flutter (mobile/lib/services/cloudflare_d1_service.dart).
 *
 * المسار مستقل تماماً عن الـ Worker: نداءات api.cloudflare.com/client/v4
 * بتوكن API بصلاحية D1 (cfut_…). القيود المُثبتة تجريبياً على الحساب
 * (مسبارات 2026-09-04، نفس تعليق Flutter):
 *  • حد المعاملات 100 لكل استعلام (99 ✓ 100 ✓ 101 ✗) — هامش 96.
 *  • /query يقبل عبارات متعددة لكن **بدون** params معها.
 *  • الكتابة تتطلب توكناً بصلاحية D1 Edit وإلا رُفضت بـ SQLITE_AUTH.
 *
 * الاستخدام الأساسي: النسخ الاحتياطي المباشر + تشخيص القاعدة من شاشة
 * الدخول (فحص التوكن/القاعدة/صلاحية الكتابة عبر [probe]).
 */
@Singleton
class CloudflareD1Service @Inject constructor(
    private val config: CloudflareConfig
) {
    companion object {
        private val JSON = "application/json; charset=utf-8".toMediaType()

        /** حد المعاملات المُثبت تجريبياً على الحساب. */
        const val MAX_PARAMS_PER_QUERY = 100
        private const val PARAM_SAFETY_MARGIN = 4

        /** الميزانية الفعلية للمعاملات في نداء واحد. */
        const val PARAMS_BUDGET = MAX_PARAMS_PER_QUERY - PARAM_SAFETY_MARGIN
    }

    private val gson = Gson()
    private val client = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(90, TimeUnit.SECONDS)
        .writeTimeout(120, TimeUnit.SECONDS)
        .build()

    /** إعدادات الاتصال (الحساب/القاعدة/التوكن) — قيم ثابتة + توكن قابل للتبديل. */
    val accountId: String get() = CloudflareConfig.D1_ACCOUNT_ID
    val databaseId: String get() = CloudflareConfig.D1_DATABASE_ID
    val apiToken: String? get() = config.d1ApiToken

    /** هل التكوين المباشر مكتمل (توكن موجود)؟ */
    val isConfigured: Boolean get() = !apiToken.isNullOrBlank()

    // ─── HTTP core ───────────────────────────────────────────────

    /**
     * نداء REST واحد — إعادة محاولة واحدة عند أعطال الشبكة (آمنة لأن كل
     * الكتابات INSERT OR REPLACE idempotent — نفس عقد Flutter).
     */
    private suspend fun call(
        method: String,
        path: String,
        body: Map<String, Any>? = null
    ): Result<Map<String, Any>> = withContext(Dispatchers.IO) {
        val token = apiToken
            ?: return@withContext Result.failure(IllegalStateException("لا يوجد توكن D1 API — اضبطه من شاشة الدخول"))
        var lastError: Exception? = null
        repeat(2) {
            try {
                val builder = Request.Builder()
                    .url("${CloudflareConfig.CF_API_BASE}$path")
                    .header("Authorization", "Bearer $token")
                when (method) {
                    "GET" -> builder.get()
                    else -> builder.post(
                        (body?.let { gson.toJson(it) } ?: "{}").toRequestBody(JSON)
                    )
                }
                client.newCall(builder.build()).execute().use { resp ->
                    val decoded = gson.fromJson<Map<String, Any>>(
                        resp.body?.string() ?: "{}",
                        object : TypeToken<Map<String, Any>>() {}.type
                    ) ?: emptyMap()
                    // عقد Cloudflare: {success, errors, result} دائماً.
                    if (decoded["success"] == true) {
                        return@withContext Result.success(decoded)
                    }
                    return@withContext Result.failure(
                        CloudflareD1Exception(
                            "فشل نداء Cloudflare (HTTP ${resp.code})",
                            decoded["errors"]?.toString()
                        )
                    )
                }
            } catch (e: Exception) {
                lastError = e
            }
        }
        Result.failure(CloudflareD1Exception("تعذر الاتصال بـ Cloudflare", lastError?.toString()))
    }

    // ─── Query / exec ────────────────────────────────────────────

    /**
     * تنفيذ SQL مع معاملات وإرجاع الصفوف. نداء واحد بعبارة واحدة
     * (العبارات المتعددة لا تقبل params — عقد المسبارات).
     */
    suspend fun query(
        sql: String,
        params: List<Any>? = null
    ): Result<List<Map<String, Any>>> {
        val body = buildMap<String, Any> {
            put("sql", sql)
            if (params != null) put("params", params)
        }
        return call(
            "POST",
            "/accounts/$accountId/d1/database/$databaseId/query",
            body
        ).mapCatching { decoded ->
            val result = decoded["result"]
            @Suppress("UNCHECKED_CAST")
            (result as? List<Map<String, Any>>)?.flatMap { r ->
                @Suppress("UNCHECKED_CAST")
                (r["results"] as? List<Map<String, Any>>).orEmpty()
            } ?: emptyList()
        }
    }

    /** تنفيذ SQL بلا نتائج متوقعة (DDL/كتابات مجمّعة بلا params). */
    suspend fun exec(sql: String): Result<Int> {
        val body = mapOf<String, Any>("sql" to sql)
        return call(
            "POST",
            "/accounts/$accountId/d1/database/$databaseId/query",
            body
        ).mapCatching { decoded ->
            val result = decoded["result"]
            @Suppress("UNCHECKED_CAST")
            (result as? List<Map<String, Any>>)?.firstOrNull()
                ?.get("meta")?.let { gson.toJson(it) }?.let { 1 } ?: 1
        }
    }

    // ─── Probe ───────────────────────────────────────────────────

    /**
     * فحص شامل للاتصال المباشر: صلاحية التوكن + الوصول للقاعدة + صلاحية
     * الكتابة (DML) — نفس فيلسوفية probe() في Flutter: DML كافية للنسخ
     * الاحتياطي ما دام المخطط موجوداً في D1 (وهو موجود).
     */
    suspend fun probe(): Result<D1ProbeResult> {
        var tokenValid = false
        var databaseReachable = false
        var dmlAllowed = false
        var fatalError: String? = null

        // 1) توكن صالح؟ (نقطة التحقق للتوكنات الحسابية)
        val verify = call("GET", "/accounts/$accountId/tokens/verify")
        if (verify.isSuccess) {
            @Suppress("UNCHECKED_CAST")
            val result = verify.getOrNull()?.get("result") as? Map<String, Any>
            tokenValid = result?.get("status") == "active"
        }
        if (!tokenValid) {
            // توكنات المستخدم (cfut_) تُفحص عبر نقطة /user/tokens/verify.
            val userVerify = call("GET", "/user/tokens/verify")
            if (userVerify.isSuccess) {
                @Suppress("UNCHECKED_CAST")
                val result = userVerify.getOrNull()?.get("result") as? Map<String, Any>
                tokenValid = result?.get("status") == "active"
            }
        }
        if (!tokenValid) {
            fatalError = "التوكن غير صالح أو منتهي"
            return Result.success(D1ProbeResult(tokenValid, false, false, fatalError))
        }

        // 2) القاعدة قابلة للوصول؟ (SELECT رخيص)
        val dbCheck = query("SELECT COUNT(*) AS c FROM sqlite_master WHERE type='table'")
        if (dbCheck.isSuccess) {
            databaseReachable = dbCheck.getOrNull()?.firstOrNull()
                ?.get("c")?.toString()?.toDouble()?.let { it > 0 } == true
        } else {
            fatalError = dbCheck.exceptionOrNull()?.message
        }

        // 3) صلاحية الكتابة (DML)؟ — CREATE TEMP TABLE رخيص وآمن.
        if (databaseReachable) {
            val dml = query(
                "CREATE TEMP TABLE _marina_probe (id INTEGER)"
            )
            dmlAllowed = dml.isSuccess
            if (dmlAllowed) {
                query("DROP TABLE _marina_probe")
            }
        }

        return Result.success(
            D1ProbeResult(tokenValid, databaseReachable, dmlAllowed, fatalError)
        )
    }
}

/** نتيجة الفحص المباشر — تُعرض في شاشة الدخول/الإعدادات. */
data class D1ProbeResult(
    val tokenValid: Boolean,
    val databaseReachable: Boolean,
    val dmlAllowed: Boolean,
    val fatalError: String?
)

/** خطأ D1 مع تفاصيل استجابة Cloudflare الخام. */
class CloudflareD1Exception(
    message: String,
    val details: String? = null
) : Exception(if (details != null) "$message — $details" else message)
