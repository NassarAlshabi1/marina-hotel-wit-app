package com.marina.marina.data.mapper

import com.marina.marina.data.local.entity.InventoryItemEntity
import com.marina.marina.data.local.entity.InventoryTransactionEntity
import com.marina.marina.data.local.entity.SalaryWithdrawalEntity
import com.marina.marina.domain.model.InventoryItem
import com.marina.marina.domain.model.InventoryTransaction
import com.marina.marina.domain.model.SalaryWithdrawal

/**
 * Entity <-> domain-model mappers for the tables added after the initial
 * scaffold (inventory + salary withdrawals). Same contract as
 * [EntityMappers]: the only place entity types may convert to domain models.
 */

fun InventoryItemEntity.toDomain(): InventoryItem = InventoryItem(
    id = id,
    name = name,
    unit = unit,
    category = category,
    currentQuantity = currentQuantity,
    minimumQuantity = minimumQuantity,
    localUuid = localUuid,
    serverId = serverId,
    createdAt = createdAt,
    updatedAt = updatedAt,
    deletedAt = deletedAt,
    version = version
)

fun InventoryItem.toEntity(): InventoryItemEntity = InventoryItemEntity(
    id = id,
    name = name,
    unit = unit,
    category = category,
    currentQuantity = currentQuantity,
    minimumQuantity = minimumQuantity,
    localUuid = localUuid,
    serverId = serverId,
    createdAt = createdAt,
    updatedAt = updatedAt,
    deletedAt = deletedAt,
    version = version
)

fun InventoryTransactionEntity.toDomain(): InventoryTransaction = InventoryTransaction(
    id = id,
    itemId = itemId,
    transactionType = transactionType,
    quantity = quantity,
    balanceAfter = balanceAfter,
    note = note,
    transactionTime = transactionTime,
    localUuid = localUuid,
    serverId = serverId,
    createdAt = createdAt,
    updatedAt = updatedAt,
    deletedAt = deletedAt,
    version = version
)

fun InventoryTransaction.toEntity(): InventoryTransactionEntity = InventoryTransactionEntity(
    id = id,
    itemId = itemId,
    transactionType = transactionType,
    quantity = quantity,
    balanceAfter = balanceAfter,
    note = note,
    transactionTime = transactionTime,
    localUuid = localUuid,
    serverId = serverId,
    createdAt = createdAt,
    updatedAt = updatedAt,
    deletedAt = deletedAt,
    version = version
)

fun SalaryWithdrawalEntity.toDomain(): SalaryWithdrawal = SalaryWithdrawal(
    id = id,
    employeeId = employeeId,
    employeeUuid = employeeUuid,
    employeeName = employeeName,
    amount = amount,
    withdrawDate = withdrawDate,
    hotelDayKey = hotelDayKey,
    withdrawalType = withdrawalType,
    reason = reason,
    description = description,
    localUuid = localUuid,
    serverId = serverId,
    createdAt = createdAt,
    updatedAt = updatedAt,
    deletedAt = deletedAt,
    version = version
)

fun SalaryWithdrawal.toEntity(): SalaryWithdrawalEntity = SalaryWithdrawalEntity(
    id = id,
    employeeId = employeeId,
    employeeUuid = employeeUuid,
    employeeName = employeeName,
    amount = amount,
    withdrawDate = withdrawDate,
    hotelDayKey = hotelDayKey,
    withdrawalType = withdrawalType,
    reason = reason,
    description = description,
    localUuid = localUuid,
    serverId = serverId,
    createdAt = createdAt,
    updatedAt = updatedAt,
    deletedAt = deletedAt,
    version = version
)
