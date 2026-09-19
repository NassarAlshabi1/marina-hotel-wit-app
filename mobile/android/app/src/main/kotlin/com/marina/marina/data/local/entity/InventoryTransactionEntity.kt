package com.marina.marina.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import com.google.gson.annotations.SerializedName

/** Mirrors the Flutter `inventory_transactions` Drift table. */
@Entity(
    tableName = "inventory_transactions",
    indices = [
        Index("idx_inv_tx_item", "item_id"),
        Index("idx_inv_tx_time", "transaction_time"),
        Index("idx_inv_tx_type", "transaction_type"),
        Index(value = ["local_uuid"], unique = true)
    ]
)
data class InventoryTransactionEntity(
    @SerializedName("id")
    override val id: Long = 0,

    @SerializedName("item_id")
    val itemId: Long,

    @SerializedName("transaction_type")
    val transactionType: String, // "in" | "out" | "adjustment"

    @SerializedName("quantity")
    val quantity: Double,

    @SerializedName("balance_after")
    val balanceAfter: Double = 0.0,

    @SerializedName("note")
    val note: String? = null,

    @SerializedName("transaction_time")
    val transactionTime: Long,

    @SerializedName("local_uuid")
    override val localUuid: String = "",

    @SerializedName("server_id")
    override val serverId: Int? = null,

    @SerializedName("created_at")
    override val createdAt: Long = 0,

    @SerializedName("updated_at")
    override val updatedAt: Long = 0,

    @SerializedName("deleted_at")
    override val deletedAt: Long? = null,

    @SerializedName("last_modified")
    override val lastModified: Long = 0,

    @SerializedName("created_at_iso")
    override val createdAtIso: String? = null,

    @SerializedName("updated_at_iso")
    override val updatedAtIso: String? = null,

    @SerializedName("deleted_at_iso")
    override val deletedAtIso: String? = null,

    @SerializedName("created_at_epoch")
    override val createdAtEpoch: Long = 0,

    @SerializedName("last_modified_epoch")
    override val lastModifiedEpoch: Long = 0,

    @SerializedName("version")
    override val version: Int = 1,

    @SerializedName("origin")
    override val origin: String = "local",

    @SerializedName("vector_clock")
    override val vectorClock: String = "{}",

    @SerializedName("device_id")
    override val deviceId: String = "",

    @SerializedName("sync_timestamp")
    override val syncTimestamp: Long = 0,

    @SerializedName("idempotency_key")
    override val idempotencyKey: String? = null
) : BaseSyncEntity(
    id = id,
    localUuid = localUuid,
    serverId = serverId,
    createdAt = createdAt,
    updatedAt = updatedAt,
    deletedAt = deletedAt,
    lastModified = lastModified,
    createdAtIso = createdAtIso,
    updatedAtIso = updatedAtIso,
    deletedAtIso = deletedAtIso,
    createdAtEpoch = createdAtEpoch,
    lastModifiedEpoch = lastModifiedEpoch,
    version = version,
    origin = origin,
    vectorClock = vectorClock,
    deviceId = deviceId,
    syncTimestamp = syncTimestamp,
    idempotencyKey = idempotencyKey
)
