package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marina.marina.data.local.entity.PriceAdjustmentEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface PriceAdjustmentsDao {
    @Query("SELECT * FROM price_adjustments WHERE deleted_at IS NULL ORDER BY id DESC")
    fun getAll(): Flow<List<PriceAdjustmentEntity>>

    @Query("SELECT * FROM price_adjustments WHERE deleted_at IS NULL ORDER BY id DESC")
    suspend fun getAllOnce(): List<PriceAdjustmentEntity>

    @Query("SELECT * FROM price_adjustments WHERE id = :id")
    suspend fun getById(id: Long): PriceAdjustmentEntity?

    @Query("SELECT * FROM price_adjustments WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getByLocalUuid(localUuid: String): PriceAdjustmentEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: PriceAdjustmentEntity): Long

    @Update
    suspend fun update(entity: PriceAdjustmentEntity)

    @Query("UPDATE price_adjustments SET deleted_at = :deletedAt, updated_at = :updatedAt, last_modified = :lastModified WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long, lastModified: Long): Int

    @Query("DELETE FROM price_adjustments WHERE id = :id")
    suspend fun delete(id: Long)
}
