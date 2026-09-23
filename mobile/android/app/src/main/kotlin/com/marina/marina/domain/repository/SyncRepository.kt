package com.marina.marina.domain.repository

import com.marina.marina.domain.model.SyncUiState
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow

interface SyncRepository {
    val syncState: StateFlow<SyncUiState>
    fun pendingCount(): Flow<Int>
    suspend fun syncNow(): SyncUiState
    suspend fun pullOnly(): Int

    /** ✅ رفع فقط بدون سحب — يفرّغ outbox إلى السيرفر (نظير sync(push:true, pull:false) في Dart). */
    suspend fun pushOnly(): Int

    /**
     * ✅ السحب الكامل — إعادة ضبط مؤشر السحب + جلب كل البيانات من الصفر
     * (سحب فقط بدون رفع — نظير fullSync(push:false) في Dart).
     */
    suspend fun fullPull(): Int
}
