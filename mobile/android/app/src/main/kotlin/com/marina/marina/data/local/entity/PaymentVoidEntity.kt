package com.marina.marina.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

@Entity(tableName = "payment_voids",
    indices = [Index(value = ["booking_uuid"], name = "idx_void_booking"), Index(value = ["hotel_day_key"], name = "idx_void_day")],
)
data class PaymentVoidEntity(
    @PrimaryKey(autoGenerate = true) @SerializedName("id") override val id: Long = 0,

    @SerializedName("original_payment_uuid") @ColumnInfo(name = "original_payment_uuid") val originalPaymentUuid: String,
    @SerializedName("original_payment_id") @ColumnInfo(name = "original_payment_id") val originalPaymentId: Long,
    @SerializedName("booking_uuid") @ColumnInfo(name = "booking_uuid") val bookingUuid: String,
    @SerializedName("voided_amount") @ColumnInfo(name = "voided_amount") val voidedAmount: Long,
    @SerializedName("void_reason") @ColumnInfo(name = "void_reason") val voidReason: String,
    @SerializedName("voided_by") @ColumnInfo(name = "voided_by") val voidedBy: String,
    @SerializedName("voided_at") @ColumnInfo(name = "voided_at") val voidedAt: Long,
    @SerializedName("voided_at_iso") @ColumnInfo(name = "voided_at_iso") val voidedAtIso: String,
    @SerializedName("hotel_day_key") @ColumnInfo(name = "hotel_day_key") val hotelDayKey: String,
    @SerializedName("reversal_payment_uuid") @ColumnInfo(name = "reversal_payment_uuid") val reversalPaymentUuid: String? = null,
    @SerializedName("approved_by") @ColumnInfo(name = "approved_by") val approvedBy: String? = null,
    @SerializedName("note") val note: String? = null,
    @SerializedName("original_amount") @ColumnInfo(name = "original_amount") val originalAmount: Double? = null,
    @SerializedName("payment_uuid") @ColumnInfo(name = "payment_uuid") val paymentUuid: String? = null,

    @SerializedName("local_uuid") @ColumnInfo(name = "local_uuid") override val localUuid: String = "",
    @SerializedName("server_id") @ColumnInfo(name = "server_id") override val serverId: Int? = null,
    @SerializedName("created_at") @ColumnInfo(name = "created_at") override val createdAt: Long = 0,
    @SerializedName("updated_at") @ColumnInfo(name = "updated_at") override val updatedAt: Long = 0,
    @SerializedName("deleted_at") @ColumnInfo(name = "deleted_at") override val deletedAt: Long? = null,
    @SerializedName("last_modified") @ColumnInfo(name = "last_modified") override val lastModified: Long = 0,
    @SerializedName("created_at_iso") @ColumnInfo(name = "created_at_iso") override val createdAtIso: String? = null,
    @SerializedName("updated_at_iso") @ColumnInfo(name = "updated_at_iso") override val updatedAtIso: String? = null,
    @SerializedName("deleted_at_iso") @ColumnInfo(name = "deleted_at_iso") override val deletedAtIso: String? = null,
    @SerializedName("created_at_epoch") @ColumnInfo(name = "created_at_epoch") override val createdAtEpoch: Long = 0,
    @SerializedName("last_modified_epoch") @ColumnInfo(name = "last_modified_epoch") override val lastModifiedEpoch: Long = 0,
    @SerializedName("version") override val version: Int = 1,
    @SerializedName("origin") override val origin: String = "local",
    @SerializedName("vector_clock") @ColumnInfo(name = "vector_clock") override val vectorClock: String = "{}",
    @SerializedName("device_id") @ColumnInfo(name = "device_id") override val deviceId: String = "",
    @SerializedName("sync_timestamp") @ColumnInfo(name = "sync_timestamp") override val syncTimestamp: Long = 0,
    @SerializedName("idempotency_key") @ColumnInfo(name = "idempotency_key") override val idempotencyKey: String? = null
) : BaseSyncEntity(id = id, localUuid = localUuid, serverId = serverId, createdAt = createdAt, updatedAt = updatedAt, deletedAt = deletedAt, lastModified = lastModified, createdAtIso = createdAtIso, updatedAtIso = updatedAtIso, deletedAtIso = deletedAtIso, createdAtEpoch = createdAtEpoch, lastModifiedEpoch = lastModifiedEpoch, version = version, origin = origin, vectorClock = vectorClock, deviceId = deviceId, syncTimestamp = syncTimestamp, idempotencyKey = idempotencyKey)
