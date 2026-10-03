package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.marina.marina.data.local.entity.PendingSyncLinkEntity

@Dao
interface PendingSyncLinksDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun put(row: PendingSyncLinkEntity)

    @Query("SELECT * FROM pending_sync_links")
    suspend fun getAll(): List<PendingSyncLinkEntity>

    @Query("DELETE FROM pending_sync_links WHERE entity = :entity AND localUuid = :localUuid")
    suspend fun remove(entity: String, localUuid: String)

    @Query("DELETE FROM pending_sync_links")
    suspend fun clear()
}
