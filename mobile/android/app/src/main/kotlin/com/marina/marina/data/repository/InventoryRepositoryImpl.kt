package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.InventoryDao
import com.marina.marina.data.local.entity.InventoryTransactionEntity
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.InventoryItem
import com.marina.marina.domain.model.InventoryTransaction
import com.marina.marina.domain.repository.InventoryRepository
import com.marina.marina.data.sync.SyncEpochs
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class InventoryRepositoryImpl @Inject constructor(
    private val inventoryDao: InventoryDao,
    private val outboxRepository: OutboxRepository
) : InventoryRepository {

    override fun getAllItems(): Flow<List<InventoryItem>> =
        inventoryDao.getAllItems().map { entities -> entities.map { it.toDomain() } }

    override fun getTransactionsForItem(itemId: Long): Flow<List<InventoryTransaction>> =
        inventoryDao.getTransactionsForItem(itemId).map { entities -> entities.map { it.toDomain() } }

    override suspend fun addItem(item: InventoryItem): Long {
        val now = SyncEpochs.nowSeconds()
        val prepared = item.copy(
            localUuid = item.localUuid.ifBlank { UUID.randomUUID().toString() },
            createdAt = if (item.createdAt == 0L) now else item.createdAt,
            updatedAt = now
        )
        val id = inventoryDao.insertItem(prepared.toEntity().copy(lastModified = now, lastModifiedEpoch = now))
        outboxRepository.enqueueObject("inventory_items", "insert", prepared.localUuid, prepared)
        return id
    }

    override suspend fun updateItem(item: InventoryItem) {
        val now = SyncEpochs.nowSeconds()
        val existing = inventoryDao.getItemById(item.id)
        val prepared = item.copy(updatedAt = now)
        inventoryDao.updateItem(
            prepared.toEntity().copy(
                localUuid = prepared.localUuid.ifBlank { existing?.localUuid.orEmpty() },
                createdAt = if (prepared.createdAt == 0L) (existing?.createdAt ?: now) else prepared.createdAt,
                lastModified = now,
                lastModifiedEpoch = now,
                version = (existing?.version ?: prepared.version) + 1
            )
        )
        outboxRepository.enqueueObject("inventory_items", "update", prepared.localUuid, prepared)
    }

    override suspend fun softDeleteItem(id: Long) {
        val now = SyncEpochs.nowSeconds()
        inventoryDao.softDeleteItem(id, deletedAt = now, updatedAt = now, lastModified = now)
    }

    override suspend fun recordMovement(itemId: Long, type: String, quantity: Double, note: String?): Result<InventoryItem> {
        return try {
            val item = inventoryDao.getItemById(itemId)
                ?: return Result.failure(IllegalArgumentException("العنصر غير موجود"))

            val newQuantity = when (type) {
                "in" -> item.currentQuantity + quantity
                "out" -> {
                    val updated = item.currentQuantity - quantity
                    if (updated < 0) {
                        return Result.failure(IllegalArgumentException("الكمية المصروفة أكبر من الرصيد المتوفر"))
                    }
                    updated
                }
                "adjustment" -> quantity // stocktaking: set absolute value
                else -> return Result.failure(IllegalArgumentException("نوع حركة غير معروف"))
            }

            val nowMillis = System.currentTimeMillis()
            val now = SyncEpochs.nowSeconds()
            val txUuid = UUID.randomUUID().toString()
            val tx = InventoryTransactionEntity(
                itemId = itemId,
                transactionType = type,
                quantity = if (type == "adjustment") newQuantity else quantity,
                balanceAfter = newQuantity,
                note = note,
                transactionTime = nowMillis,
                localUuid = txUuid,
                createdAt = now,
                updatedAt = now,
                lastModified = now,
                lastModifiedEpoch = now
            )
            inventoryDao.insertTransactionAndUpdateBalance(tx, newQuantity)

            outboxRepository.enqueueObject("inventory_transactions", "insert", txUuid, tx)

            // نظير Dart (`inventory_repository.dart` l.146-157): الحركة **و**تحديث
            // رصيد الصنف يُرفعان معاً — الحمولة من الصف بعد الكتابة (فيحمل
            // `last_modified`/`version` الجديدين). بلا هذا كان تغيير الرصيد محلياً
            // فقط: لا يصل السحابة، وأي تحديث وارد يطمسه صامتاً.
            val updatedItem = inventoryDao.getItemById(itemId)
                ?: return Result.failure(IllegalStateException("تعذر تحديث الصنف"))
            outboxRepository.enqueueObject("inventory_items", "update", updatedItem.localUuid, updatedItem.toDomain())
            Result.success(updatedItem.toDomain())
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    override suspend fun getMovementCount(itemId: Long): Int = inventoryDao.getMovementCount(itemId)
}
