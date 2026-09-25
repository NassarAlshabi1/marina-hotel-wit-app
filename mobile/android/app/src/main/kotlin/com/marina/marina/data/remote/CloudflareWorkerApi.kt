package com.marina.marina.data.remote

import com.google.gson.annotations.SerializedName
import retrofit2.Call
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Query

// ═══════════════════════════════════════════════════════════════
//  CloudflareWorkerApi — عقد السلك الحقيقي للـ Worker المنشور
//
//  ✅ (2026-09-24) أُعيدت كتابة الواجهة لتطابق worker/src (فرع
//  feat/cloudflare-sync-execution) بدل العقد التخيّلي السابق:
//   • login: POST /api/auth/login {username, password, device_id}
//       → {token, user:{id, username, role}} — لا حقل success إطلاقاً.
//   • pull: GET /api/sync/pull?cursor=&limit=&exclude_device=
//       → {changes:[{_entity, ...row}], cursor:"N", has_more,
//          remaining, errors, server_time} — GET وليس POST.
//   • push: POST /api/sync/push {operations:[PushOperation]} (≤100)
//       → {results:[{idempotencyKey, success, entityId?, error?,
//          skipped?, status?}], summary, server_time}.
//   • health/stats: نقاط فحص حيّة موجودة فعلاً على الخادم.
//   • حُذفت /api/d1/query و /api/d1/exec — لا وجود لهما على الـ worker؛
//     الوصول المباشر لـ D1 عبر REST يتم في [CloudflareD1Service].
// ═══════════════════════════════════════════════════════════════

// ─── Auth DTOs ────────────────────────────────────────────────

data class WorkerLoginRequest(
    @SerializedName("username") val username: String,
    @SerializedName("password") val password: String,
    @SerializedName("device_id") val deviceId: String = ""
)

data class WorkerLoginResponse(
    @SerializedName("token") val token: String?,
    @SerializedName("user") val user: WorkerLoginUser?
)

data class WorkerLoginUser(
    @SerializedName("id") val id: String?,
    @SerializedName("username") val username: String?,
    @SerializedName("role") val role: String?
)

data class WorkerHealthResponse(
    @SerializedName("status") val status: String?,
    @SerializedName("version") val version: String?
)

data class WorkerStatsResponse(
    @SerializedName("tables") val tables: Map<String, Double>?
)

/** ✅ (2026-09-24) استجابة /api/ping — فحص شبكة خفيف (نفس عقد worker/src/index.ts). */
data class WorkerPingResponse(
    @SerializedName("status") val status: String?,
    @SerializedName("timestamp") val timestamp: Long?,
    @SerializedName("server_time") val serverTime: Long?
)

// ─── Pull DTOs (GET /api/sync/pull) ───────────────────────────

/**
 * صفحة سحب — changes قائمة سجلات مفتوحة: كل سجل يحمل كل أعمدة صف D1
 * (snake_case) + حقل `_entity` الذي يضيفه الخادم لكل سجل (database.ts
 * pullChanges) ليتمكن العميل من توجيه السجل للجدول الصحيح بلا تخمين.
 */
data class WorkerPullResponse(
    @SerializedName("changes") val changes: List<Map<String, Any>>?,
    /** المؤشر التالي كسلسلة (الخادم يرسله toString). */
    @SerializedName("cursor") val cursor: String?,
    @SerializedName("has_more") val hasMore: Boolean?,
    /** عدد الصفوف الباقية بعد cursor — null ما لم يُطلب include_remaining. */
    @SerializedName("remaining") val remaining: Double?,
    /** جداول فشلت هذه الجولة — غير فارغة = دورة فاشلة (لا نقدّم المؤشر). */
    @SerializedName("errors") val errors: List<WorkerPullError>?,
    @SerializedName("server_time") val serverTime: Double?
)

data class WorkerPullError(
    @SerializedName("entity") val entity: String?,
    @SerializedName("error") val error: String?
)

// ─── Push DTOs (POST /api/sync/push) ──────────────────────────

/**
 * عملية دفع واحدة — عقد PushOperation في worker/src/database.ts:
 * idempotencyKey + entity + operation(create|update|delete) + data
 * + vectorClock + updatedAt + deviceId اختياري.
 */
data class WorkerPushOperation(
    @SerializedName("idempotencyKey") val idempotencyKey: String,
    @SerializedName("entity") val entity: String,
    @SerializedName("operation") val operation: String,
    @SerializedName("data") val data: Map<String, Any>,
    @SerializedName("vectorClock") val vectorClock: String,
    @SerializedName("updatedAt") val updatedAt: Long,
    @SerializedName("deviceId") val deviceId: String? = null
)

data class WorkerPushRequest(
    @SerializedName("operations") val operations: List<WorkerPushOperation>
)

data class WorkerPushResponse(
    @SerializedName("results") val results: List<WorkerPushResult>?,
    @SerializedName("summary") val summary: WorkerPushSummary?
)

data class WorkerPushResult(
    @SerializedName("idempotencyKey") val idempotencyKey: String?,
    @SerializedName("success") val success: Boolean?,
    @SerializedName("entity") val entity: String?,
    @SerializedName("entityId") val entityId: String?,
    @SerializedName("error") val error: String?,
    /** إعادة إرسال بنفس المفتاح — نجاح شكلي. */
    @SerializedName("skipped") val skipped: Boolean?,
    /**
     * تصنيف الرفض (fix M4): validation_error | conflict | internal_error
     * | deleted (F1: التعديل خسر لصالح tombstone — نجاح شكلي بلا تطبيق).
     */
    @SerializedName("status") val status: String?
)

data class WorkerPushSummary(
    @SerializedName("total") val total: Int?,
    @SerializedName("success") val success: Int?,
    @SerializedName("failed") val failed: Int?,
    @SerializedName("skipped") val skipped: Int?
)

// ─── API interface ────────────────────────────────────────────

interface CloudflareWorkerApi {

    @POST("/api/auth/login")
    fun login(@Body request: WorkerLoginRequest): Call<WorkerLoginResponse>

    /**
     * سحب دلتا عبر كل الجداول — مؤشر الخادم updated_at هو المرجع دائماً.
     * ✅ (2026-09-25) معاملات اختيارية بعقد sync.ts:
     *  • include_remaining=1 — COUNT خادمي للمتبقي (السحب الكامل فقط،
     *    يُعيّن كل 5 صفحات كما في Dart — تخفيف الحمل الخادمي ~80%).
     *  • normalize_timestamps=1 — شفاء خادمي لطوابع المللي القديمة
     *    (الصفحة الأولى من السحب الكامل مرة واحدة فقط).
     */
    @GET("/api/sync/pull")
    fun pull(
        @Query("cursor") cursor: Long,
        @Query("limit") limit: Int,
        @Query("exclude_device") excludeDevice: String? = null,
        @Query("include_remaining") includeRemaining: Boolean? = null,
        @Query("normalize_timestamps") normalizeTimestamps: Boolean? = null
    ): Call<WorkerPullResponse>

    /** دفع دفعة عمليات outbox — سقف 100 عملية/نداء (حد الخادم). */
    @POST("/api/sync/push")
    fun push(@Body request: WorkerPushRequest): Call<WorkerPushResponse>

    @GET("/health")
    fun health(): Call<WorkerHealthResponse>

    /** ✅ فحص شبكة خفيف بلا مصادقة ولا rate-limit — لقياس النطاق المخصّص. */
    @GET("/api/ping")
    fun ping(): Call<WorkerPingResponse>

    @GET("/api/stats")
    fun stats(): Call<WorkerStatsResponse>
}
