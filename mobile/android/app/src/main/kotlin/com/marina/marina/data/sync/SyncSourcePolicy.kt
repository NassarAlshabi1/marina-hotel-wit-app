package com.marina.marina.data.sync

/**
 * Pure policy for binding an Android installation to the current sync source.
 * The wire fields are provider-neutral; this Cloudflare adapter deliberately
 * accepts only its own provider identifier until another adapter is implemented.
 */
sealed interface SyncSourceDecision {
    data class Accepted(
        val normalizedSourceId: String,
        val shouldPin: Boolean
    ) : SyncSourceDecision

    data class Rejected(
        val reason: Rejection,
        val userMessage: String
    ) : SyncSourceDecision

    enum class Rejection {
        MISSING_IDENTITY,
        UNSUPPORTED_PROVIDER,
        UNSUPPORTED_PROTOCOL,
        SOURCE_CHANGED,
        SOURCE_NOT_CONFIGURED
    }
}

object SyncSourcePolicy {
    const val CURRENT_PROVIDER_ID = "cloudflare-d1"
    const val CURRENT_PROTOCOL_VERSION = 1
    private val sourceIdPattern = Regex("^[a-f0-9]{32}$")

    fun evaluate(
        storedSourceId: String?,
        providerId: String?,
        responseSourceId: String?,
        protocolVersion: Int?,
        expectedSourceId: String? = null
    ): SyncSourceDecision {
        if (providerId?.trim() != CURRENT_PROVIDER_ID) {
            return SyncSourceDecision.Rejected(
                SyncSourceDecision.Rejection.UNSUPPORTED_PROVIDER,
                "مصدر المزامنة غير مدعوم في هذا التطبيق؛ لم يُرفع أو يُسحب أي سجل."
            )
        }
        if (protocolVersion != CURRENT_PROTOCOL_VERSION) {
            return SyncSourceDecision.Rejected(
                SyncSourceDecision.Rejection.UNSUPPORTED_PROTOCOL,
                "إصدار بروتوكول المزامنة غير متوافق؛ حدّث Worker والتطبيق قبل المتابعة."
            )
        }

        val sourceId = responseSourceId?.trim()?.lowercase()
            ?.takeIf { sourceIdPattern.matches(it) }
            ?: return SyncSourceDecision.Rejected(
                SyncSourceDecision.Rejection.MISSING_IDENTITY,
                "الخادم لا يعلن هوية مصدر صالحة (Worker migration 0016 مطلوبة)؛ بقيت البيانات المحلية كما هي."
            )
        val currentSourceId = storedSourceId?.trim()?.lowercase()?.takeIf { it.isNotEmpty() }
        val expected = expectedSourceId?.trim()?.lowercase()?.takeIf { it.isNotEmpty() }
        if (expected != null && expected != sourceId) {
            return SyncSourceDecision.Rejected(
                SyncSourceDecision.Rejection.SOURCE_NOT_CONFIGURED,
                "مصدر المزامنة لا يطابق المصدر المعتمد لهذا الإصدار؛ لم يتم التبديل أو نقل البيانات."
            )
        }

        if (currentSourceId != null && currentSourceId != sourceId) {
            return SyncSourceDecision.Rejected(
                SyncSourceDecision.Rejection.SOURCE_CHANGED,
                "تغيّر مصدر المزامنة. أُوقف الرفع والسحب دون تغيير Outbox أو المؤشر؛ أعد الاتصال بالمصدر المثبّت أو نفّذ نقلاً معتمداً."
            )
        }

        return SyncSourceDecision.Accepted(
            normalizedSourceId = sourceId,
            shouldPin = currentSourceId == null
        )
    }
}
