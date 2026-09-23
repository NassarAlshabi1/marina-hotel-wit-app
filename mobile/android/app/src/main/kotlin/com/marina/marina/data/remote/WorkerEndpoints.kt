package com.marina.marina.data.remote

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import java.net.URI
import javax.inject.Inject
import javax.inject.Singleton

/**
 * ✅ (2026-09-24) سجل نقاط نهاية الـ Worker مع تبديل تلقائي — نقل مباشر من
 * Flutter (worker_endpoints.dart، فرع feat/cloudflare-sync-execution).
 *
 * السياق الهندسي (نفس تعليق Flutter): شبكات اليمن تحجب *.workers.dev
 * (فلترة SNI/IP/DNS). لا إصلاح برمجي بحت يتجاوز حجب SNI بثبات — الحل
 * الصحيح نطاق مخصّص مربوط بنفس الـ Worker (SNI مسموح). هذا السجل يدير
 * المرشحين:
 *
 *    1. النطاق المخصّص (يضبطه المستخدم من شاشة الدخول) — أولوية دائمة
 *       ما دام موجوداً: وجوده بحد ذاته إشارة أن المدمج محجوب.
 *    2. النطاق المدمج workers.dev (CloudflareConfig.BUILTIN_WORKER_URL).
 *
 * ويثبّت آخر نقطة نجحت (sticky) محفوظة في SharedPreferences — الفشل يُنزّل
 * الفائز مؤقتاً ويمرّر الطلب للمرشح التالي (ينفَّذ فعلياً داخل
 * [WorkerFailoverInterceptor] — نجاح/فشل يرجع هنا عبر reportSuccess/reportFailure).
 */
@Singleton
class WorkerEndpoints @Inject constructor(
    @ApplicationContext private val context: Context
) {
    companion object {
        /** مفتاح النطاق المخصّص في SharedPreferences (نفس مفتاح Flutter). */
        const val CUSTOM_URL_KEY = "cf_custom_worker_url"

        /** مفتاح آخر نقطة نهاية نجحت (sticky) — يُستعاد عند الإطلاق. */
        const val ACTIVE_URL_KEY = "cf_worker_active_url"

        @Volatile private var initialized = false
        @Volatile private var customUrl: String? = null
        @Volatile private var activeOverride: String? = null
        private val lock = Any()

        /** Test-only: تفريغ الحالة الساكنة (توازي resetForTests في Flutter). */
        fun resetForTests() {
            synchronized(lock) {
                initialized = false
                customUrl = null
                activeOverride = null
            }
        }
    }

    private val prefs by lazy {
        context.getSharedPreferences("marina_cloudflare_prefs", Context.MODE_PRIVATE)
    }

    /** النقطة المدمجة من بيئة البناء (workers.dev). */
    val builtin: String get() = CloudflareConfig.BUILTIN_WORKER_URL

    /** تحميل الحالة المحفوظة — يستدعى مرة واحدة مبكراً (fail-open للمدمج). */
    fun loadIfNeeded() {
        synchronized(lock) {
            if (initialized) return
            val custom = sanitize(prefs.getString(CUSTOM_URL_KEY, null))
            val sticky = sanitize(prefs.getString(ACTIVE_URL_KEY, null))
            customUrl = custom
            // نطاق مخصّص موجود = إشارة أن المدمج غير موثوق (سبب وضعه أصلاً).
            // ابدأ الجلسة عليه؛ الفشل يصحّح التثبيت تلقائياً عبر التدوير.
            activeOverride = if (custom != null && sticky == builtin) custom else sticky
            initialized = true
        }
    }

    /** العنوان الفعّال الذي تُبنى عليه كل روابط الـ Worker. */
    val active: String
        get() {
            loadIfNeeded()
            val sticky = sanitize(activeOverride)
            if (sticky != null && isRegisteredBase(sticky)) return sticky
            return customUrl ?: builtin
        }

    /** النطاق المخصّص الحالي (null = غير مضبوط). */
    val custom: String?
        get() {
            loadIfNeeded()
            return customUrl
        }

    val hasCustom: Boolean get() = custom != null

    /**
     * تطبيع إدخال المستخدم: «mydomain.com» أو «https://mydomain.com/» →
     * URL نظيف https://host[:port] بلا مسار/استعلام. يعيد null عند إدخال
     * فارغ، ويرمي [IllegalArgumentException] عند إدخال فاسد (نفس عقود
     * normalizeCustomUrl في Flutter: FormatException).
     */
    fun normalizeCustomUrl(raw: String?): String? {
        val trimmed = raw?.trim().orEmpty()
        if (trimmed.isEmpty()) return null
        var text = trimmed
        if (!text.contains("://")) text = "https://$text"
        val uri = try {
            URI(text)
        } catch (e: Exception) {
            throw IllegalArgumentException("رابط غير صالح: $trimmed")
        }
        val host = (uri.host ?: "").lowercase()
        if (host.isEmpty() || host.contains(' ') || !host.contains('.')) {
            throw IllegalArgumentException("اسم نطاق غير صالح: $trimmed")
        }
        if (uri.scheme != "https") {
            throw IllegalArgumentException("يجب أن يكون الرابط https: $trimmed")
        }
        val path = uri.path ?: ""
        if (uri.userInfo != null || (path.isNotEmpty() && path != "/") || uri.rawQuery != null) {
            throw IllegalArgumentException("أدخل النطاق الجذر فقط بدون مسار: $trimmed")
        }
        return if (uri.port == 443 || uri.port == -1) "https://$host" else "https://$host:${uri.port}"
    }

    /**
     * ضبط/مسح النطاق المخصّص من شاشة الدخول. يعيد الرابط المُطبَّع المحفوظ
     * (null عند المسح). يرمي [IllegalArgumentException] على إدخال فاسد
     * (لا يلمس الحالة المحفوظة).
     */
    fun setCustomUrl(raw: String?): String? {
        loadIfNeeded()
        val normalized = normalizeCustomUrl(raw)
        synchronized(lock) {
            if (normalized == null) {
                prefs.edit().putString(CUSTOM_URL_KEY, "").apply()
            } else {
                prefs.edit().putString(CUSTOM_URL_KEY, normalized).apply()
            }
            customUrl = normalized
            // المخصّص الجديد يتقدم فوراً (المستخدم وضعه لسبب) — والمسح يعيد
            // للمدمج. يُحفظ sticky الجديد ليُستعاد عند الإطلاق القادم.
            activeOverride = normalized ?: builtin
            prefs.edit().putString(ACTIVE_URL_KEY, activeOverride!!).apply()
        }
        return normalized
    }

    /** مرشحو نقاط النهاية لطلب نحو [requestUrl]: الطلب نفسه أولاً ثم بقية المرشحين. */
    fun candidatesFor(requestUrl: URI): List<URI> {
        loadIfNeeded()
        if (!isWorkerEndpoint(requestUrl)) return listOf(requestUrl)
        val result = mutableListOf<URI>()
        fun add(base: String) {
            val u = runCatching { URI(base) }.getOrNull() ?: return
            if (result.none { hostKey(it) == hostKey(u) }) result.add(u)
        }
        add(toBaseUrl(requestUrl).toString())
        customUrl?.let { add(it) }
        add(builtin)
        return result
    }

    /** نجاح طلب على [base] — يثبّته للطلبات اللاحقة (sticky). */
    fun reportSuccess(base: URI) {
        loadIfNeeded()
        val normalized = sanitize(toBaseUrl(base).toString()) ?: return
        if (!isRegisteredBase(normalized)) return
        synchronized(lock) {
            if (sanitize(activeOverride) == normalized) return
            activeOverride = normalized
            prefs.edit().putString(ACTIVE_URL_KEY, normalized).apply()
        }
    }

    /** فشل طلب على [base] — يُنزّله من الصدارة مؤقتاً (in-memory فقط). */
    fun reportFailure(base: URI) {
        loadIfNeeded()
        val normalized = sanitize(toBaseUrl(base).toString()) ?: return
        synchronized(lock) {
            if (sanitize(activeOverride) != normalized) return
            // انتقل للمرشح التالي: فشل المخصّص → المدمج، وفشل المدمج → المخصّص.
            activeOverride = if (customUrl != null && normalized == builtin) {
                customUrl
            } else if (normalized == customUrl) {
                builtin
            } else {
                null
            }
            if (sanitize(activeOverride) == normalized) activeOverride = null
        }
    }

    /** هل [uri] يشير إلى إحدى نقاط الـ worker المسجلة؟ */
    fun isWorkerEndpoint(uri: URI): Boolean {
        loadIfNeeded()
        val key = hostKey(uri)
        return orderedBases().any { hostKey(URI(it)) == key }
    }

    // ─── internals ───────────────────────────────────────────────

    private fun orderedBases(): List<String> = listOfNotNull(customUrl, builtin)

    private fun isRegisteredBase(base: String): Boolean {
        val bu = runCatching { URI(base) }.getOrNull() ?: return false
        return orderedBases().any { hostKey(URI(it)) == hostKey(bu) }
    }

    private fun sanitize(raw: String?): String? {
        if (raw == null) return null
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null
        val uri = runCatching { URI(trimmed) }.getOrNull() ?: return null
        if (uri.host.isNullOrEmpty()) return null
        return trimmed
    }

    /** قاعدة نقية scheme://host[:port] — تقص أي مسار/استعلام عابر. */
    private fun toBaseUrl(u: URI): URI {
        val port = if (u.port == -1) -1 else u.port
        return URI(u.scheme, u.userInfo, u.host.lowercase(), port, null, null, null)
    }

    /** هوية مضيف مستقرة: host:port مع افتراض المنفذ من المخطط. */
    private fun hostKey(u: URI): String {
        val port = if (u.port == -1) if (u.scheme == "https") 443 else 80 else u.port
        return "${u.host.lowercase()}:$port"
    }
}
