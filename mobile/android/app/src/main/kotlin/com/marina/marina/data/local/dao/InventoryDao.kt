package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Update
import com.marina.marina.data.local.entity.InventoryItemEntity
import com.marina.marina.data.local.entity.InventoryTransactionEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface InventoryDao {

    // -- Items ----------------------------------------------------------------

    @Query("SELECT * FROM inventory_items WHERE deleted_at IS NULL ORDER BY name ASC")
    fun getAllItems(): Flow<List<InventoryItemEntity>>

    @Query("SELECT * FROM inventory_items WHERE deleted_at IS NULL ORDER BY name ASC")
    suspend fun getAllItemsOnce(): List<InventoryItemEntity>

    @Query("SELECT * FROM inventory_items WHERE id = :id AND deleted_at IS NULL")
    suspend fun getItemById(id: Long): InventoryItemEntity?

    @Query("SELECT * FROM inventory_items WHERE name = :name AND deleted_at IS NULL LIMIT 1")
    suspend fun getItemByName(name: String): InventoryItemEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertItem(item: InventoryItemEntity): Long

    @Update
    suspend fun updateItem(item: InventoryItemEntity)

    @Query("UPDATE inventory_items SET deleted_at = :deletedAt, updated_at = :updatedAt WHERE id = :id")
    suspend fun softDeleteItem(id: Long, deletedAt: Long, updatedAt: Long): Int

    @Query("UPDATE inventory_items SET current_quantity = :newQuantity, updated_at = :updatedAt WHERE id = :id")
    suspend fun updateQuantity(id: Long, newQuantity: Double, updatedAt: Long): Int

    // -- Transactions ---------------------------------------------------------

    @Query("SELECT * FROM inventory_transactions WHERE deleted_at IS NULL AND item_id = :itemId ORDER BY transaction_time DESC")
    fun getTransactionsForItem(itemId: Long): Flow<List<InventoryTransactionEntity>>

    @Query("SELECT * FROM inventory_transactions WHERE deleted_at IS NULL ORDER BY transaction_time DESC LIMIT :limit")
    fun getRecentTransactions(limit: Int = 50): Flow<List<InventoryTransactionEntity>>

    @Query("SELECT COUNT(*) FROM inventory_transactions WHERE deleted_at IS NULL AND item_id = :itemId")
    suspend fun getMovementCount(itemId: Long): Int

    @Query("SELECT COALESCE(SUM(quantity), 0) FROM inventory_transactions WHERE deleted_at IS NULL AND item_id = :itemId AND transaction_type = :type")
    suspend fun getTotalQuantityByType(itemId: Long, type: String): Double

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertTransaction(tx: InventoryTransactionEntity): Long

    @Transaction
    suspend fun insertTransactionAndUpdateBalance(tx: InventoryTransactionEntity, newQuantity: Double) {
        insertTransaction(tx)
        updateQuantity(tx.itemId, newQuantity, System.currentTimeMillis())
    }

    // ✅ (2026-09-24) سحب المزامنة: إيجاد الصف المحلي بمفتاح local_uuid
    // (توجيه سجلات pull عبر _entity — عقد الـ worker).
    @Query("SELECT * FROM inventory_items WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getItemByLocalUuid(localUuid: String): InventoryItemEntity?

    @Query("SELECT * FROM inventory_transactions WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getTransactionByLocalUuid(localUuid: String): InventoryTransactionEntity?
}
