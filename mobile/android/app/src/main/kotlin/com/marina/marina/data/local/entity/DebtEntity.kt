package com.marina.marina.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.ColumnInfo
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

@Entity(
    tableName = "debts",
    indices = [
        Index(value = ["is_settled", "is_from_auto_fix"], name = "idx_debts_status"),
        Index(value = ["guest_name"], name = "idx_debts_guest"),
        Index(value = ["booking_local_id"], name = "idx_debts_booking"),
        Index(value = ["payment_date"], name = "idx_debts_payment_date")
    ]
)
data class DebtEntity(
    @PrimaryKey(autoGenerate = true)
    @SerializedName("id")
    override val id: Long = 0,

    @SerializedName("booking_local_id")
    @ColumnInfo(name = "booking_local_id")
    val bookingLocalId: Long? = null,

    @SerializedName("guest_name")
    @ColumnInfo(name = "guest_name")
    val guestName: String,

    @SerializedName("checkin_date")
    @ColumnInfo(name = "checkin_date")
    val checkinDate: String,

    @SerializedName("checkout_date")
    @ColumnInfo(name = "checkout_date")
    val checkoutDate: String,

    @SerializedName("date_recorded")
    @ColumnInfo(name = "date_recorded")
    val dateRecorded: String = "",

    @SerializedName("debt_reason")
    @ColumnInfo(name = "debt_reason")
    val debtReason: String = "",

    @SerializedName("total_amount")
    @ColumnInfo(name = "total_amount")
    val totalAmount: Double,

    @SerializedName("paid_amount")
    @ColumnInfo(name = "paid_amount")
    val paidAmount: Double,

    @SerializedName("remaining_amount")
    @ColumnInfo(name = "remaining_amount")
    val remainingAmount: Double,

    @SerializedName("payment_date")
    @ColumnInfo(name = "payment_date")
    val paymentDate: String,

    @SerializedName("is_settled")
    @ColumnInfo(name = "is_settled")
    val isSettled: Int = 0,

    @SerializedName("pledge")
    val pledge: String? = null,

    @SerializedName("pledge_type")
    @ColumnInfo(name = "pledge_type")
    val pledgeType: String? = null,

    @SerializedName("note")
    val note: String? = null,

    @SerializedName("debt_uuid")
    @ColumnInfo(name = "debt_uuid")
    val debtUuid: String? = null,

    @SerializedName("hotel_day_opened")
    @ColumnInfo(name = "hotel_day_opened")
    val hotelDayOpened: String? = null,

    @SerializedName("hotel_day_closed")
    @ColumnInfo(name = "hotel_day_closed")
    val hotelDayClosed: String? = null,

    @SerializedName("is_from_auto_fix")
    @ColumnInfo(name = "is_from_auto_fix")
    val isFromAutoFix: Boolean = false,

    @SerializedName("settlement_confirmed")
    @ColumnInfo(name = "settlement_confirmed")
    val settlementConfirmed: Boolean = false,

    @SerializedName("guest_phone")
    @ColumnInfo(name = "guest_phone")
    val guestPhone: String? = null,

    @SerializedName("description")
    val description: String? = null,

    @SerializedName("status")
    val status: String? = null,

    @SerializedName("due_date")
    @ColumnInfo(name = "due_date")
    val dueDate: String? = null,

    @SerializedName("booking_uuid_cache")
    @ColumnInfo(name = "booking_uuid_cache")
    val bookingUuidCache: String? = null,

    @SerializedName("debtor_name")
    @ColumnInfo(name = "debtor_name")
    val debtorName: String? = null,

    @SerializedName("amount")
    val amount: Double? = null,

    @SerializedName("date")
    val date: String? = null,

    @SerializedName("local_uuid")
    @ColumnInfo(name = "local_uuid")
    override val localUuid: String = "",

    @SerializedName("server_id")
    @ColumnInfo(name = "server_id")
    override val serverId: Int? = null,

    @SerializedName("created_at")
    @ColumnInfo(name = "created_at")
    override val createdAt: Long = 0,

    @SerializedName("updated_at")
    @ColumnInfo(name = "updated_at")
    override val updatedAt: Long = 0,

    @SerializedName("deleted_at")
    @ColumnInfo(name = "deleted_at")
    override val deletedAt: Long? = null,

    @SerializedName("last_modified")
    @ColumnInfo(name = "last_modified")
    override val lastModified: Long = 0,

    @SerializedName("created_at_iso")
    @ColumnInfo(name = "created_at_iso")
    override val createdAtIso: String? = null,

    @SerializedName("updated_at_iso")
    @ColumnInfo(name = "updated_at_iso")
    override val updatedAtIso: String? = null,

    @SerializedName("deleted_at_iso")
    @ColumnInfo(name = "deleted_at_iso")
    override val deletedAtIso: String? = null,

    @SerializedName("created_at_epoch")
    @ColumnInfo(name = "created_at_epoch")
    override val createdAtEpoch: Long = 0,

    @SerializedName("last_modified_epoch")
    @ColumnInfo(name = "last_modified_epoch")
    override val lastModifiedEpoch: Long = 0,

    @SerializedName("version")
    override val version: Int = 1,

    @SerializedName("origin")
    override val origin: String = "local",

    @SerializedName("vector_clock")
    @ColumnInfo(name = "vector_clock")
    override val vectorClock: String = "{}",

    @SerializedName("device_id")
    @ColumnInfo(name = "device_id")
    override val deviceId: String = "",

    @SerializedName("sync_timestamp")
    @ColumnInfo(name = "sync_timestamp")
    override val syncTimestamp: Long = 0,

    @SerializedName("idempotency_key")
    @ColumnInfo(name = "idempotency_key")
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
