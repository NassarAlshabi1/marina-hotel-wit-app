package com.marina.marina.data

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

@Entity(
    tableName = "outbox",
    indices = [
        Index("idx_outbox_status", "processing_status"),
        Index("idx_outbox_entity_status", "entity, op, processing_status"),
        Index("idx_outbox_uuid_pending", "entity, local_uuid, processing_status"),
        Index("idx_outbox_client_ts", "client_ts"),
        Index("idx_outbox_processing_started", "processing_status, processing_started_at"),
        Index("idx_outbox_source_status", "source, processing_status"),
        Index("idx_outbox_delivery_primary", "delivered_to_primary, processing_status"),
        Index("idx_outbox_delivery_secondary", "delivered_to_secondary, processing_status"),
        Index("idx_outbox_pending_primary_source_ts", "source, client_ts", "processing_status = 'pending' AND delivered_to_primary = 0")
    ]
)
data class Outbox(
    @PrimaryKey(autoGenerate = true)
    @SerializedName("id")
    val id: Long = 0,

    @SerializedName("entity")
    val entity: String,

    @SerializedName("op")
    val op: String,

    @SerializedName("local_uuid")
    val localUuid: String,

    @SerializedName("server_id")
    val serverId: Int? = null,

    @SerializedName("payload")
    val payload: String,

    @SerializedName("client_ts")
    val clientTs: Long,

    @SerializedName("attempts")
    val attempts: Int = 0,

    @SerializedName("last_error")
    val lastError: String? = null,

    @SerializedName("idempotency_key")
    val idempotencyKey: String? = null,

    @SerializedName("processing_status")
    val processingStatus: String = "pending",

    @SerializedName("processing_started_at")
    val processingStartedAt: Long? = null,

    @SerializedName("processing_worker")
    val processingWorker: String? = null,

    @SerializedName("source")
    val source: String = "local",

    @SerializedName("delivered_to_primary")
    val deliveredToPrimary: Boolean = false,

    @SerializedName("delivered_to_secondary")
    val deliveredToSecondary: Boolean = true,

    @SerializedName("primary_processing_status")
    val primaryProcessingStatus: String = "pending",

    @SerializedName("primary_attempts")
    val primaryAttempts: Int = 0,

    @SerializedName("primary_last_error")
    val primaryLastError: String? = null,

    @SerializedName("secondary_processing_status")
    val secondaryProcessingStatus: String = "pending",

    @SerializedName("secondary_attempts")
    val secondaryAttempts: Int = 0,

    @SerializedName("secondary_last_error")
    val secondaryLastError: String? = null,

    @SerializedName("payload_version")
    val payloadVersion: Int = 1,

    @SerializedName("processing_payload_version")
    val processingPayloadVersion: Int? = null
)