package com.marina.marina.data.repository

import com.marina.marina.data.local.AppDatabase

/** The caller owns a Room transaction. Never change balances optimistically. */
internal object FinancialReversalQueue {
    suspend fun enqueue(db: AppDatabase, outbox: OutboxRepository, entity: String, uuid: String, reason: String) {
        require(uuid.isNotBlank()) { "الحركة بلا UUID" }
        val explanation = reason.trim()
        require(explanation.length in 3..500) { "سبب الإلغاء مطلوب (3–500 حرف)" }
        val prior = db.outboxDao().findReversal(entity, uuid)
        if (prior != null) {
            check(prior.processingStatus != "completed" || prior.deliveredToPrimary) {
                "رُفض طلب الإلغاء؛ راجع خطأ المزامنة: ${prior.primaryLastError.orEmpty()}"
            }
            return // Stable pending command/receipt, including double taps and restarts.
        }
        outbox.enqueue(entity, "reverse", uuid, mapOf("local_uuid" to uuid, "reason" to explanation))
    }
}
