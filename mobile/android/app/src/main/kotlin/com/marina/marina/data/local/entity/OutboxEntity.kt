package com.marina.marina.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.ColumnInfo
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

/**
 * Queue of local mutations waiting to be pushed to Cloudflare D1. Not a
 * synced business entity itself, so it does not extend [BaseSyncEntity].
 */
@Entity(
    tableName = "outbox",
    indices = [
        Index(value = ["processing_status"], name = "idx_outbox_status"),
        Index(value = ["entity", "op", "processing_status"], name = "idx_outbox_entity_status"),
        Index(value = ["entity", "local_uuid", "processing_status"], name = "idx_outbox_uuid_pending"),
        Index(value = ["client_ts"], name = "idx_outbox_client_ts"),
        Index(value = ["processing_status", "processing_started_at"], name = "idx_outbox_processing_started"),
        Index(value = ["source", "processing_status"], name = "idx_outbox_source_status"),
        Index(value = ["delivered_to_primary", "processing_status"], name = "idx_outbox_delivery_primary"),
        Index(value = ["delivered_to_secondary", "processing_status"], name = "idx_outbox_delivery_secondary"),
        Index(value = ["source", "client_ts"], name = "idx_outbox_pending_primary_source_ts")
    ]
)
data class OutboxEntity(
    @PrimaryKey(autoGenerate = true)
    @SerializedName("id")
    val id: Long = 0,

    @SerializedName("entity")
    val entity: String,

    @SerializedName("op")
    val op: String,

    @SerializedName("local_uuid")
    @ColumnInfo(name = "local_uuid")
    val localUuid: String,

    @SerializedName("server_id")
    @ColumnInfo(name = "server_id")
    val serverId: Int? = null,

    @SerializedName("payload")
    val payload: String,

    @SerializedName("client_ts")
    @ColumnInfo(name = "client_ts")
    val clientTs: Long,

    @SerializedName("attempts")
    val attempts: Int = 0,

    @SerializedName("last_error")
    @ColumnInfo(name = "last_error")
    val lastError: String? = null,

    @SerializedName("idempotency_key")
    @ColumnInfo(name = "idempotency_key")
    val idempotencyKey: String? = null,

    @SerializedName("processing_status")
    @ColumnInfo(name = "processing_status")
    val processingStatus: String = "pending",

    @SerializedName("processing_started_at")
    @ColumnInfo(name = "processing_started_at")
    val processingStartedAt: Long? = null,

    @SerializedName("processing_worker")
    @ColumnInfo(name = "processing_worker")
    val processingWorker: String? = null,

    @SerializedName("source")
    val source: String = "local",

    @SerializedName("delivered_to_primary")
    @ColumnInfo(name = "delivered_to_primary")
    val deliveredToPrimary: Boolean = false,

    @SerializedName("delivered_to_secondary")
    @ColumnInfo(name = "delivered_to_secondary")
    val deliveredToSecondary: Boolean = true,

    @SerializedName("primary_processing_status")
    @ColumnInfo(name = "primary_processing_status")
    val primaryProcessingStatus: String = "pending",

    @SerializedName("primary_attempts")
    @ColumnInfo(name = "primary_attempts")
    val primaryAttempts: Int = 0,

    @SerializedName("primary_last_error")
    @ColumnInfo(name = "primary_last_error")
    val primaryLastError: String? = null,

    @SerializedName("secondary_processing_status")
    @ColumnInfo(name = "secondary_processing_status")
    val secondaryProcessingStatus: String = "pending",

    @SerializedName("secondary_attempts")
    @ColumnInfo(name = "secondary_attempts")
    val secondaryAttempts: Int = 0,

    @SerializedName("secondary_last_error")
    @ColumnInfo(name = "secondary_last_error")
    val secondaryLastError: String? = null,

    @SerializedName("payload_version")
    @ColumnInfo(name = "payload_version")
    val payloadVersion: Int = 1,

    @SerializedName("processing_payload_version")
    @ColumnInfo(name = "processing_payload_version")
    val processingPayloadVersion: Int? = null
)
