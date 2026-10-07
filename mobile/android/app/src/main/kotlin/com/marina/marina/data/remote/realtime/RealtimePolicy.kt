package com.marina.marina.data.remote.realtime

import java.net.URI
import java.util.Locale
import kotlin.math.min

/**
 * ثوابت وسياسات Realtime النقية — نقل حرفي لأرقام Flutter المثبتة في
 * `cloudflare_realtime_sync.dart` (فرع feat/cloudflare-sync-execution):
 *
 *  • debounce 500ms: دفعة أحداث متتالية = حدث سحب واحد.
 *  • cooldown 15s (`SyncConstants.realtimeEventPullCooldown`): حد أعلى
 *    نظري 4 دورات/دقيقة تحت عاصفة أحداث مستمرة.
 *  • backoff أُسّي 1s→60s، حد أقصى 6 محاولات اتصال ثم إعادة تسليح دورية
 *    كل دقيقتين بدل الموت حتى عودة التطبيق للواجهة (مراجعة #17).
 *  • heartbeat 30s (ping على مستوى البروتوكول) ومهلة إنشاء اتصال 15s —
 *    مقبس شبه مفتوح على شبكة محجوبة كان يعلّق كل محاولات إعادة الاتصال.
 */
internal const val REALTIME_DEBOUNCE_MS = 500L
internal const val REALTIME_PULL_COOLDOWN_MS = 15_000L
internal const val REALTIME_BASE_BACKOFF_MS = 1_000L
internal const val REALTIME_MAX_BACKOFF_MS = 60_000L
internal const val REALTIME_MAX_RECONNECT_ATTEMPTS = 6
internal const val REALTIME_REARM_INTERVAL_MS = 120_000L
internal const val REALTIME_HEARTBEAT_MS = 30_000L
internal const val REALTIME_CONNECT_TIMEOUT_MS = 15_000L
internal const val REALTIME_MAX_ERROR_LENGTH = 160

/** مسار الاشتراك في الـ Worker (index.ts: GET /api/realtime → WebSocket upgrade). */
internal const val REALTIME_PATH = "/api/realtime"

/**
 * تأخير إعادة الاتصال الأُسّي: 1s, 2s, 4s… بسقف 60s (Dart
 * `computeBackoffDelay` — إزاحة محدودة بـ10 كي لا تنفجر القيم).
 */
internal fun realtimeBackoffDelayMs(attempt: Int): Long {
    val shift = attempt.coerceIn(0, 10)
    val seconds = (REALTIME_BASE_BACKOFF_MS / 1000L) shl shift
    return min(seconds * 1000L, REALTIME_MAX_BACKOFF_MS)
}

/**
 * تحويل مخطط نقطة النهاية إلى مخطط WebSocket — جذر فشل الريل-تايم في
 * Dart (Dart 3.12 يرفض `https` حرفياً لـ WebSocket): https→wss وhttp→ws،
 * وغير ذلك يمر كما هو (idempotent).
 */
internal fun toWebSocketBase(baseUrl: String): String {
    val uri = runCatching { URI(baseUrl.trim()) }.getOrNull() ?: return baseUrl.trim()
    val scheme = uri.scheme?.lowercase(Locale.ROOT) ?: return baseUrl.trim()
    val mapped = when (scheme) {
        "https" -> "wss"
        "http" -> "ws"
        else -> scheme
    }
    val port = if (uri.port == -1) "" else ":${uri.port}"
    val host = uri.host ?: return baseUrl.trim()
    return "$mapped://$host$port"
}

/**
 * رابط الاشتراك الفعلي: `wss://host/api/realtime?deviceId=..&entity=*`
 * (نفس استعلام Dart — `entity=*` يعني كل الكيانات).
 */
internal fun buildRealtimeUrl(baseUrl: String, deviceId: String?): String {
    val base = toWebSocketBase(baseUrl).trimEnd('/')
    val device = deviceId?.trim().takeUnless { it.isNullOrEmpty() } ?: "unknown"
    val encoded = java.net.URLEncoder.encode(device, "UTF-8")
    return "$base$REALTIME_PATH?deviceId=$encoded&entity=*"
}

/** تقصير نص الخطأ للتشخيص (Dart: 160 حرفاً كحد أقصى). */
internal fun shortenRealtimeError(detail: String?): String {
    val text = detail?.trim().orEmpty().ifEmpty { "socket closed" }
    return if (text.length > REALTIME_MAX_ERROR_LENGTH) {
        text.substring(0, REALTIME_MAX_ERROR_LENGTH - 3) + "..."
    } else {
        text
    }
}
