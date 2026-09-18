package com.marina.marina.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

@Entity(
    tableName = "debts",
    indices = [
        Index("idx_debts_status", "is_settled, is_from_auto_fix"),
        Index("idx_debts_guest", "guest_name"),
        Index("idx_debts_booking", "booking_local_id"),
        Index("idx_debts_payment_date", "payment_date")
    ]
)
data class DebtEntity(
    @PrimaryKey(autoGenerate = true)
    @SerializedName("id")
    override val id: Long = 0,

    @SerializedName("booking_local_id")
    val bookingLocalId: Long? = null,

    @SerializedName("guest_name")
    val guestName: String,

    @SerializedName("checkin_date")
    val checkinDate: String,

    @SerializedName("checkout_date")
    val checkoutDate: String,

    @SerializedName("date_recorded")
    val dateRecorded: String = "",

    @SerializedName("debt_reason")
    val debtReason: String = "",

    @SerializedName("total_amount")
    val totalAmount: Double,

    @SerializedName("paid_amount")
    val paidAmount: Double,

    @SerializedName("remaining_amount")
    val remainingAmount: Double,

    @SerializedName("payment_date")
    val paymentDate: String,

    @SerializedName("is_settled")
    val isSettled: Int = 0,

    @SerializedName("pledge")
    val pledge: String? = null,

    @SerializedName("pledge_type")
    val pledgeType: String? = null,

    @SerializedName("note")
    val note: String? = null,

    @SerializedName("debt_uuid")
    val debtUuid: String? = null,

    @SerializedName("hotel_day_opened")
    val hotelDayOpened: String? = null,

    @SerializedName("hotel_day_closed")
    val hotelDayClosed: String? = null,

    @SerializedName("is_from_auto_fix")
    val isFromAutoFix: Boolean = false,

    @SerializedName("settlement_confirmed")
    val settlementConfirmed: Boolean = false,

    @SerializedName("guest_phone")
    val guestPhone: String? = null,

    @SerializedName("description")
    val description: String? = null,

    @SerializedName("status")
    val status: String? = null,

    @SerializedName("due_date")
    val dueDate: String? = null,

    @SerializedName("booking_uuid_cache")
    val bookingUuidCache: String? = null,

    @SerializedName("debtor_name")
    val debtorName: String? = null,

    @SerializedName("amount")
    val amount: Double? = null,

    @SerializedName("date")
    val date: String? = null,

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
