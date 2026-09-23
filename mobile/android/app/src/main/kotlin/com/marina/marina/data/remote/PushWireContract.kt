package com.marina.marina.data.remote

import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.marina.marina.data.local.entity.OutboxEntity

/**
 * ✅ (2026-09-24) عقد السلك لدفع الـ outbox — تكافؤ sync/payload_normalizer.dart
 * (buildPushOperation + PayloadNormalizer) في Flutter، مستخرج ككائن نقي
 * بلا اعتماديات ليكون قابلاً للاختبار المباشر.
 */
object PushWireContract {

    private val gson = Gson()

    /**
     * يبني عملية دفع واحدة من صف outbox:
     *  • data = الحمولة مطبَّعة (snake_case + bool→int) مع حقن local_uuid
     *    عند غيابه (الحمولات الرقيقة لـ soft-deletes — عقد requireEntityId).
     *  • vectorClock يُقرأ من الحمولة (صف الكيان يحمل vector_clock عبر
     *    BaseSyncEntity) وإلا '{}' — نفس ترتيب buildPushOperation.
     *  • operation: create|update|delete حصراً — "insert" المحلي → "create".
     *  • idempotencyKey احتياطي: entity_op_localUuid.
     */
    fun buildOperation(row: OutboxEntity, deviceId: String): WorkerPushOperation {
        val data = normalizeForWire(decodePayload(row.payload)).toMutableMap()
        val localUuid = data["local_uuid"]?.toString()?.takeIf { it.isNotBlank() } ?: row.localUuid
        data["local_uuid"] = localUuid
        val vectorClock = (data["vector_clock"] as? String)?.takeIf { it.isNotBlank() } ?: "{}"
        data["vector_clock"] = vectorClock
        return WorkerPushOperation(
            idempotencyKey = row.idempotencyKey
                ?: "${row.entity}_${row.op}_${row.localUuid}",
            entity = row.entity,
            operation = mapOperation(row.op),
            data = data,
            vectorClock = vectorClock,
            updatedAt = row.clientTs,
            deviceId = deviceId.ifBlank { "unknown-origin" }
        )
    }

    /** "insert" → "create"؛ الخادم يقبل create|update|delete حصراً. */
    fun mapOperation(op: String): String = when (op.trim().lowercase()) {
        "insert", "create", "upsert" -> "create"
        "update", "edit" -> "update"
        "delete", "soft_delete", "softdelete" -> "delete"
        else -> op.trim().lowercase()
    }

    /**
     * تطبيع الحمولة للسلك (PayloadNormalizer.normalize): **المستوى الأعلى
     * فقط** — camelCase → snake_case للمفاتيح و bool → int للقيم (D1/SQLite
     * INTEGER affinity — Workers D1 يرفض القيم المنطقية).
     *
     * القيم المتداخلة تمر كما هي: JSON strings والقوائم والخرائط المتداخلة
     * **بيانات** (مثل applied_adjustments_json) مفاتيحها الداخلية تُحفظ
     * — تُطبَّع أسماء الأعمدة فقط (نفس تعليق Flutter حرفياً).
     */
    fun normalizeForWire(payload: Map<String, Any>): Map<String, Any> {
        val out = LinkedHashMap<String, Any>(payload.size)
        payload.forEach { (key, value) ->
            out[toSnakeCase(key)] = if (value is Boolean) {
                if (value) 1 else 0
            } else {
                value
            }
        }
        return out
    }

    /**
     * camelCase → snake_case idempotent — الحد يوضع بين صغير/رقم وكبير
     * فقط (نفس RegExp([a-z0-9])([A-Z]) في Flutter): employeeId →
     * employee_id (وليس employee_i_d) و localUUID → local_uuid.
     * المفاتيح snake_case أصلاً تمر كما هي (لا uppercase).
     */
    fun toSnakeCase(key: String): String {
        if (key.none { it.isUpperCase() }) return key
        val builder = StringBuilder(key.length + 4)
        key.forEachIndexed { index, ch ->
            val prev = if (index > 0) key[index - 1] else null
            // الحد فقط بين صغير/رقم وكبير — نفس ([a-z0-9])([A-Z]) في Flutter.
            if (ch.isUpperCase() && prev != null && (prev.isLowerCase() || prev.isDigit())) {
                builder.append('_').append(ch.lowercaseChar())
            } else if (ch.isUpperCase()) {
                builder.append(ch.lowercaseChar())
            } else {
                builder.append(ch)
            }
        }
        return builder.toString()
    }

    private fun decodePayload(json: String): Map<String, Any> {
        if (json.isBlank()) return emptyMap()
        return try {
            val mapType = object : TypeToken<Map<String, Any>>() {}.type
            gson.fromJson(json, mapType) ?: emptyMap()
        } catch (_: Exception) {
            emptyMap()
        }
    }
}
