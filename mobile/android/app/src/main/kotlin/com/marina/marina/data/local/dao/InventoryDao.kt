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

    @Query("UPDATE inventory_items SET deleted_at = :deletedAt, updated_at = :updatedAt, last_modified = :lastModified WHERE id = :id")
    suspend fun softDeleteItem(id: Long, deletedAt: Long, updatedAt: Long, lastModified: Long): Int

    /**
     * كتابة الرصيد بعد حركة — نظير `InventoryItemsCompanion` في Dart
     * (`inventory_repository.dart` l.133-146): `updatedAt/lastModified = now`
     * (ثوانٍ) و`version = item.version + 1`. كان هنا `updated_at` بالميلي بلا
     * `last_modified` ولا رفع نسخة ⇒ تلويث وحدة + صف لا يرى تحديثاته الواردة
     * ولا يظهر تعديله في LWW.
     */
    @Query(
        "UPDATE inventory_items SET current_quantity = :newQuantity, updated_at = :updatedAt, " +
            "last_modified = :lastModified, last_modified_epoch = :lastModified, " +
            "version = version + 1 WHERE id = :id"
    )
    suspend fun updateQuantity(id: Long, newQuantity: Double, updatedAt: Long, lastModified: Long): Int

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
        // الطابع من صف الحركة نفسه (ثوانٍ، يختمه المستودع) — لا ساعة ثانية هنا؛
        // والاحتياطي يحوّل الميلي إلى ثوانٍ بدل كتابته خاماً.
        val stamp = tx.updatedAt.takeIf { it > 0L } ?: (System.currentTimeMillis() / 1_000L)
        updateQuantity(tx.itemId, newQuantity, updatedAt = stamp, lastModified = stamp)
    }

    // ✅ (2026-09-24) سحب المزامنة: إيجاد الصف المحلي بمفتاح local_uuid
    // (توجيه سجلات pull عبر _entity — عقد الـ worker).
    @Query("SELECT * FROM inventory_items WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getItemByLocalUuid(localUuid: String): InventoryItemEntity?

    @Query("SELECT * FROM inventory_items WHERE local_uuid = :localUuid ORDER BY id ASC")
    suspend fun getItemByLocalUuidCandidates(localUuid: String): List<InventoryItemEntity>

    @Query("SELECT * FROM inventory_transactions WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getTransactionByLocalUuid(localUuid: String): InventoryTransactionEntity?

    /** البحث الشامل — كل الصفوف بما فيها المحذوفة ناعمياً (تدقيق المدير). */
    @Query("SELECT * FROM inventory_items")
    suspend fun listAllIncludingDeleted(): List<InventoryItemEntity>

    /**
     * ✅ (2026-09-25) ظلّ هوية الخادم — ترجمة FK عند السحب: item_id
     * على السلك قد يحمل id خادمياً لصنف سُحب سابقاً (رجل serverId
     * في Dart inventory rule).
     */
    @Query("SELECT * FROM inventory_items WHERE server_id = :serverId LIMIT 1")
    suspend fun getItemByServerIdIncludingDeleted(serverId: Long): InventoryItemEntity?

    @Query("SELECT * FROM inventory_items WHERE server_id = :serverId ORDER BY id ASC")
    suspend fun getItemByServerIdCandidates(serverId: Long): List<InventoryItemEntity>
}
