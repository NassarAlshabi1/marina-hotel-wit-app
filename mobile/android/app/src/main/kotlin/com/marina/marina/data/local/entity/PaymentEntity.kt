package com.marina.marina.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

@Entity(
    tableName = "payments",
    indices = [
        Index("idx_payments_booking", "booking_local_id, hotel_day_key"),
        Index("idx_payments_room_day", "room_number, hotel_day_key"),
        Index("idx_payments_date", "payment_date"),
        Index("idx_payments_revenue", "revenue_type, hotel_day_key"),
        Index("idx_payments_void", "is_voided"),
        Index("idx_payments_method", "payment_method"),
        Index("idx_payments_active_hotel_day", "hotel_day_key, revenue_type, payment_date", "deleted_at IS NULL AND is_voided = 0"),
        Index("idx_payments_legacy_active_date", "payment_date", "hotel_day_key IS NULL AND deleted_at IS NULL AND is_voided = 0"),
        Index("idx_payments_active_report_date", "payment_date DESC", "deleted_at IS NULL AND is_voided = 0 AND is_pending_balance = 0"),
        Index("idx_payments_active_receiver_session", "received_by_user_id, received_session_uuid, hotel_day_key", "deleted_at IS NULL AND is_voided = 0 AND is_pending_balance = 0")
    ]
)
data class PaymentEntity(
    @PrimaryKey(autoGenerate = true)
    @SerializedName("id")
    override val id: Long = 0,

    @SerializedName("server_payment_id")
    val serverPaymentId: Int? = null,

    @SerializedName("booking_local_id")
    val bookingLocalId: Long? = null,

    @SerializedName("server_booking_id")
    val serverBookingId: Int? = null,

    @SerializedName("room_number")
    val roomNumber: String? = null,

    @SerializedName("amount")
    val amount: Double,

    @SerializedName("payment_date")
    val paymentDate: String,

    @SerializedName("notes")
    val notes: String? = null,

    @SerializedName("payment_method")
    val paymentMethod: String,

    @SerializedName("revenue_type")
    val revenueType: String,

    @SerializedName("cash_transaction_local_id")
    val cashTransactionLocalId: Long? = null,

    @SerializedName("cash_transaction_server_id")
    val cashTransactionServerId: Int? = null,

    @SerializedName("reference_number")
    val referenceNumber: String? = null,

    @SerializedName("hotel_day_key")
    val hotelDayKey: String? = null,

    @SerializedName("is_pending_balance")
    val isPendingBalance: Boolean = false,

    @SerializedName("linked_debt_uuid")
    val linkedDebtUuid: String? = null,

    @SerializedName("booking_uuid_cache")
    val bookingUuidCache: String? = null,

    @SerializedName("discount_amount")
    val discountAmount: Double? = null,

    @SerializedName("discount_start_date")
    val discountStartDate: String? = null,

    @SerializedName("is_voided")
    val isVoided: Boolean = false,

    @SerializedName("voided_at")
    val voidedAt: Long? = null,

    @SerializedName("voided_by")
    val voidedBy: String? = null,

    @SerializedName("void_reason")
    val voidReason: String? = null,

    @SerializedName("is_immutable")
    val isImmutable: Boolean = false,

    @SerializedName("received_by_user_id")
    val receivedByUserId: Long? = null,

    @SerializedName("received_by_name")
    val receivedByName: String? = null,

    @SerializedName("received_session_uuid")
    val receivedSessionUuid: String? = null,

    @SerializedName("received_by_cloud_id")
    val receivedByCloudId: String? = null,

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
