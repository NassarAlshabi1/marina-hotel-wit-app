package com.marina.marina.domain.repository

import com.marina.marina.domain.model.BlacklistEntry
import kotlinx.coroutines.flow.Flow

interface BlacklistRepository {
    fun getActive(): Flow<List<BlacklistEntry>>
    fun searchActive(query: String): Flow<List<BlacklistEntry>>
    suspend fun getById(id: Long): BlacklistEntry?

    /**
     * Dart `findBlacklistMatch` (blacklist_repository.dart l.363-389): match by
     * full normalized name OR identical first three name tokens. Used by the
     * booking editor's security warning (تحذير أمني).
     */
    suspend fun findBlacklistMatch(name: String): BlacklistEntry?

    suspend fun insert(entry: BlacklistEntry): Long
    suspend fun update(entry: BlacklistEntry)
    suspend fun setActive(id: Long, active: Boolean)
    suspend fun softDelete(id: Long)
}
