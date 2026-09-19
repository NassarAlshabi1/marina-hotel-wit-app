package com.marina.marina.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

@Entity(tableName = "ancestor_cache",
)
data class AncestorCacheEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    @SerializedName("entity") val entity: String,
    @SerializedName("local_uuid") val localUuid: String,
    @SerializedName("data_json") val dataJson: String,
    @SerializedName("captured_at") val capturedAt: Long,
)
