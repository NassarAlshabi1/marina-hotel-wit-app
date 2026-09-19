package com.marina.marina.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

@Entity(tableName = "restore_fix_log",
)
data class RestoreFixLogEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    @SerializedName("fix_id") val fixId: String,
    @SerializedName("executed_at") val executedAt: Long,
    @SerializedName("target_table") val targetTable: String,
    @SerializedName("target_record_id") val targetRecordId: Long,
    @SerializedName("field_name") val fieldName: String,
    @SerializedName("old_value") val oldValue: String? = null,
    @SerializedName("new_value") val newValue: String? = null,
    @SerializedName("reason") val reason: String,
    @SerializedName("fix_type") val fixType: String,
)
