package com.marina.marina.domain.repository

import com.marina.marina.domain.model.RealtimeSyncState
import kotlinx.coroutines.flow.StateFlow

/**
 * واجهة قراءة حالة المزامنة الفورية للواجهات (Settings/Dashboard) —
 * التنفيذ في طبقة data (عميل WebSocket) والتزام قواعد المعمارية:
 * presentation لا تلمس `data.*` مباشرة.
 */
interface RealtimeSyncRepository {
    val realtimeState: StateFlow<RealtimeSyncState>
}
