package com.marina.marina.data.remote

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * ✅ (2026-09-24) نقل إعدادات Cloudflare من فرع Flutter (feat/cloudflare-sync-execution
 * — mobile/lib/services/cloudflare_config.dart) إلى تطبيق Kotlin.
 *
 * ما يحمله هذا الملف (نفس عقد Flutter):
 *  • رابط الـ Worker المدمج (workers.dev) — قابل للتبديل عبر [WorkerEndpoints].
 *  • اعتمادات الدخول الافتراضية admin/admin — «دخول تلقائي اتصال تلقائي حتى
 *    بدون الدخول الى الشاشة» (طلب المستخدم 2026-09-11، متحقق حياً ضد الـ worker).
 *  • overrides قابلة للتغطية وقت التشغيل من شاشة الدخول: اسم المستخدم في
 *    SharedPreferences، وكلمة المرور في prefs المشفّرة (EncryptedSharedPreferencesManager)
 *    — نفس فصل Flutter (username في prefs / password في FlutterSecureStorage).
 *  • ثوابت الدفعات: دفع outbox ≤ 100 عملية/دفعة، دلتا 250 صفحة، سحب كامل 500
 *    (نفس أرقام cloudflare_config.dart بعد ترقية 2026-09-15).
 *  • ثوابت اتصال D1 REST المباشر (accountId/databaseId المعروفة من الحساب).
 */
@Singleton
class CloudflareConfig @Inject constructor(
    @ApplicationContext private val context: Context
) {
    companion object {
        // ─── Worker endpoint (builtin) ───────────────────────────
        /** النطاق المدمج من بيئة البناء (workers.dev) — يغذّي [WorkerEndpoints]. */
        const val BUILTIN_WORKER_URL = "https://marina-hotel-api.adenmarina2.workers.dev"

        // ─── Default credentials (auto-login) ────────────────────
        /** اسم مستخدم حساب المزامنة الافتراضي (دور admin في الـ worker). */
        const val DEFAULT_USERNAME = "admin"

        /** كلمة مرور حساب المزامنة الافتراضي — مُتحقق منها حياً (HTTP 200). */
        const val DEFAULT_PASSWORD = "admin"

        // ─── prefs keys (نفس مفاتيح Flutter للتوافق) ──────────────
        const val USERNAME_OVERRIDE_KEY = "cf_username_override"
        const val PASSWORD_OVERRIDE_SECURE_KEY = "cf_password_override_secure"

        // ─── Sync batch sizes (عقد cloudflare_config.dart) ────────
        /** سقف عمليات الدفع في نداء push واحد — حد الخادم MAX_BATCH_SIZE=100. */
        const val PUSH_BATCH_SIZE = 100

        /** صفحة سحب الدلتا — مستقلة عن سقف الدفع (deltaPullBatchSize). */
        const val DELTA_PULL_BATCH_SIZE = 250

        /** صفحة السحب الكامل = السقف الخادمي MAX_PULL_BATCH_SIZE نفسه. */
        const val FULL_PULL_BATCH_SIZE = 500

        // ─── D1 REST مباشر (نسخة احتياطية — CloudflareD1Service) ──
        /** معرف الحساب (هوية عامة، ليس سراً — نفس account_id في wrangler.toml). */
        const val D1_ACCOUNT_ID = "81a73bba9acc1de5693ff929d0a372ce"

        /** معرف قاعدة D1 (marina-hotel-db — نفس database_id في wrangler.toml). */
        const val D1_DATABASE_ID = "607f1090-83b1-4281-975f-d81b8f6154e7"

        /** مفتاح توكن D1 API في prefs المشفّرة (نفس مفتاح Flutter cf_d1_api_token). */
        const val D1_TOKEN_SECURE_KEY = "cf_d1_api_token"

        /** القاعدة الأساسية لـ REST API المباشر على api.cloudflare.com. */
        const val CF_API_BASE = "https://api.cloudflare.com/client/v4"

        /**
         * الكيانات المتزامنة — أسماء الكيان = اسم الجدول في D1 (خطة D4:
         * snake_case مرآة 1:1 لجداول Drift). النطاق الافتراضي نفس
         * migrationOrder في cloudflare_config.dart (24 كياناً).
         */
        val SYNC_ENTITIES = listOf(
            "rooms", "employees", "salary_cycles", "cash_transactions",
            "bookings", "guest_infos", "booking_notes", "booking_nights",
            "booking_price_adjustments", "payments", "expenses", "debts",
            "salary_payments", "salary_withdrawals", "salary_carry_over_logs",
            "audit_logs", "payment_voids", "shift_notes", "price_adjustments",
            "inventory_items", "inventory_transactions", "app_users",
            "devices", "blacklist"
        )
    }

    // ─── Credential overrides (runtime) ─────────────────────────

    private val plainPrefs by lazy {
        context.getSharedPreferences("marina_cloudflare_prefs", Context.MODE_PRIVATE)
    }

    private val securePrefs by lazy {
        context.getSharedPreferences("marina_secure_prefs", Context.MODE_PRIVATE)
    }

    /** اسم المستخدم الفعّال: override إن وُضع، وإلا الافتراضي المدمج. */
    val username: String
        get() = plainPrefs.getString(USERNAME_OVERRIDE_KEY, null)?.trim()?.takeIf { it.isNotEmpty() }
            ?: DEFAULT_USERNAME

    /** كلمة المرور الفعّالة: override (مشفّر) إن وُضعت، وإلا المدمجة. */
    val password: String
        get() = securePrefs.getString(PASSWORD_OVERRIDE_SECURE_KEY, null)?.takeIf { it.isNotEmpty() }
            ?: DEFAULT_PASSWORD

    /** هل وُضعت اعتمادات مخصّصة من التطبيق (بدل المدمجة)؟ */
    val hasCredentialOverrides: Boolean
        get() = plainPrefs.contains(USERNAME_OVERRIDE_KEY) || securePrefs.contains(PASSWORD_OVERRIDE_SECURE_KEY)

    /**
     * حفظ اعتمادات مخصّصة (من شاشة الدخول). قيمة فارغة = إبقاء المدمجة
     * (نفس عقد Flutter: لا نمسح ما حفظ سابقاً عبثاً).
     */
    fun setCredentialOverrides(username: String?, password: String?) {
        val trimmedUser = username?.trim().orEmpty()
        if (trimmedUser.isNotEmpty()) {
            plainPrefs.edit().putString(USERNAME_OVERRIDE_KEY, trimmedUser).apply()
        }
        if (!password.isNullOrEmpty()) {
            securePrefs.edit().putString(PASSWORD_OVERRIDE_SECURE_KEY, password).apply()
        }
    }

    /** مسح الاعتمادات المخصّصة والرجوع للمدمجة (admin/admin). */
    fun clearCredentialOverrides() {
        plainPrefs.edit().remove(USERNAME_OVERRIDE_KEY).apply()
        securePrefs.edit().remove(PASSWORD_OVERRIDE_SECURE_KEY).apply()
    }

    // ─── D1 direct API token ────────────────────────────────────

    /** توكن D1 REST المباشر (cfut_…) أو null — محفوظ في prefs المشفّرة. */
    val d1ApiToken: String?
        get() = securePrefs.getString(D1_TOKEN_SECURE_KEY, null)?.takeIf { it.isNotBlank() }

    /** حفظ توكن D1 المباشر — يُستخدم من شاشة الإعدادات/الدخول. */
    fun setD1ApiToken(token: String?) {
        if (token.isNullOrBlank()) {
            securePrefs.edit().remove(D1_TOKEN_SECURE_KEY).apply()
        } else {
            securePrefs.edit().putString(D1_TOKEN_SECURE_KEY, token.trim()).apply()
        }
    }
}
