package com.marina.marina.data.remote.realtime

import com.google.gson.JsonObject
import com.google.gson.JsonParser

/**
 * مرآة `RealtimeMessage` الخادمية (worker/src/sync-lock.ts) ونظيرها في
 * Flutter (`CloudflareRealtimeMessage` في cloudflare_realtime_sync.dart):
 * `{type, entity, entityId, operation?, deviceId?, timestamp}`.
 *
 * التحليل متسامح عمداً: أي شكل غير متوقع (نص فارغ، JSON مشوّه، نوع/كيان
 * غير نصي) يعيد null فتُتجاهل الرسالة بهدوء — رسالة مشوّهة لا يجوز أن
 * تُسقط اتصالاً سليماً (عقد Dart نفسه).
 */
data class RealtimeMessage(
    val type: String,
    val entity: String,
    val entityId: String = "",
    val operation: String? = null,
    val deviceId: String? = null,
    val timestamp: Long = 0L
) {
    companion object {
        fun tryParse(raw: String?): RealtimeMessage? {
            if (raw.isNullOrEmpty()) return null
            val decoded = runCatching { JsonParser.parseString(raw) }.getOrNull() as? JsonObject ?: return null
            val type = decoded.stringOrNull("type") ?: return null
            val entity = decoded.stringOrNull("entity") ?: return null
            return RealtimeMessage(
                type = type,
                entity = entity,
                entityId = decoded.stringOrNull("entityId").orEmpty(),
                operation = decoded.stringOrNull("operation"),
                deviceId = decoded.stringOrNull("deviceId"),
                timestamp = decoded.get("timestamp")?.let { element ->
                    runCatching { element.asLong }.getOrNull()
                } ?: 0L
            )
        }

        private fun JsonObject.stringOrNull(key: String): String? {
            val element = get(key) ?: return null
            if (element.isJsonNull || !element.isJsonPrimitive) return null
            val primitive = element.asJsonPrimitive
            return if (primitive.isString) primitive.asString else null
        }
    }
}
