package com.marina.marina.domain.repository

import com.marina.marina.data.local.entity.CustomListItemEntity
import kotlinx.coroutines.flow.Flow

interface CustomListsRepository {
    /**
     * Get active item names for a given list key (e.g., "expense_type", "id_type", "payment_method").
     * Mirrors Flutter `customListNamesProvider`.
     */
    fun getActiveNames(listKey: String): Flow<List<String>>

    /** One-shot version for dialogs that need immediate values. */
    suspend fun getActiveNamesOnce(listKey: String): List<String>

    /** Get all items including inactive ones (for admin management). */
    suspend fun getAllByListKey(listKey: String): List<CustomListItemEntity>

    suspend fun insert(item: CustomListItemEntity): Long
    suspend fun insertAll(items: List<CustomListItemEntity>): List<Long>
    suspend fun update(item: CustomListItemEntity): Int
    suspend fun deleteById(id: Long): Int
    suspend fun getByLocalUuid(localUuid: String): CustomListItemEntity?
    suspend fun getByName(listKey: String, name: String): CustomListItemEntity?
}