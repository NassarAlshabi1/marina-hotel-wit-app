package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.InventoryDao
import com.marina.marina.data.local.entity.InventoryTransactionEntity
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.InventoryItem
import com.marina.marina.domain.model.InventoryTransaction
import com.marina.marina.domain.repository.InventoryRepository
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
        val now = System.currentTimeMillis()
        val prepared = item.copy(
            localUuid = item.localUuid.ifBlank { UUID.randomUUID().toString() },
            createdAt = if (item.createdAt == 0L) now else item.createdAt,
            updatedAt = now
        )
        val id = inventoryDao.insertItem(prepared.toEntity())
        outboxRepository.enqueueObject("inventory_items", "insert", prepared.localUuid, prepared)
        return id
    }

    override suspend fun updateItem(item: InventoryItem) {
        val prepared = item.copy(updatedAt = System.currentTimeMillis())
        inventoryDao.updateItem(prepared.toEntity())
        outboxRepository.enqueueObject("inventory_items", "update", prepared.localUuid, prepared)
    }

    override suspend fun softDeleteItem(id: Long) {
        val now = System.currentTimeMillis()
        inventoryDao.softDeleteItem(id, deletedAt = now, updatedAt = now)
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

            val now = System.currentTimeMillis()
            val txUuid = UUID.randomUUID().toString()
            val tx = InventoryTransactionEntity(
                itemId = itemId,
                transactionType = type,
                quantity = if (type == "adjustment") newQuantity else quantity,
                balanceAfter = newQuantity,
                note = note,
                transactionTime = now,
                localUuid = txUuid,
                createdAt = now,
                updatedAt = now
            )
            inventoryDao.insertTransactionAndUpdateBalance(tx, newQuantity)

            outboxRepository.enqueueObject("inventory_transactions", "insert", txUuid, tx)

            val updatedItem = inventoryDao.getItemById(itemId)
            Result.success(updatedItem!!.toDomain())
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    override suspend fun getMovementCount(itemId: Long): Int = inventoryDao.getMovementCount(itemId)
}
