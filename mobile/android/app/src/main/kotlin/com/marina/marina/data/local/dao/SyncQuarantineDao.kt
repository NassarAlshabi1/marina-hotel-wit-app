package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.marina.marina.data.local.entity.SyncQuarantineEntity

@Dao
interface SyncQuarantineDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun put(row: SyncQuarantineEntity)

    @Query("SELECT * FROM sync_quarantine ORDER BY entity, recordKey")
    suspend fun getAll(): List<SyncQuarantineEntity>

    @Query("DELETE FROM sync_quarantine WHERE entity = :entity AND recordKey = :recordKey")
    suspend fun remove(entity: String, recordKey: String)
}
