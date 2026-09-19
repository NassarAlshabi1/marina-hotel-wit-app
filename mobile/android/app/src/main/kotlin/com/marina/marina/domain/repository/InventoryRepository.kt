package com.marina.marina.domain.repository

import com.marina.marina.domain.model.InventoryItem
import com.marina.marina.domain.model.InventoryTransaction
import kotlinx.coroutines.flow.Flow

interface InventoryRepository {
    fun getAllItems(): Flow<List<InventoryItem>>
    fun getTransactionsForItem(itemId: Long): Flow<List<InventoryTransaction>>
    suspend fun addItem(item: InventoryItem): Long
    suspend fun updateItem(item: InventoryItem)
    suspend fun softDeleteItem(id: Long)
    /** Records a movement and updates the item balance atomically. */
    suspend fun recordMovement(itemId: Long, type: String, quantity: Double, note: String?): Result<InventoryItem>
    suspend fun getMovementCount(itemId: Long): Int
}
