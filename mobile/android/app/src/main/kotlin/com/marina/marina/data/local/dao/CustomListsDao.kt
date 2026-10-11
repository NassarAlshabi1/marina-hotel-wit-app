package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marina.marina.data.local.entity.CustomListItemEntity
import kotlinx.coroutines.flow.Flow

/**
 * DAO for dynamic custom lists (expense_type, id_type, payment_method, etc.).
 * Mirrors Flutter `custom_list_names_provider.dart` and the server `custom_list_items` table.
 */
@Dao
interface CustomListsDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(item: CustomListItemEntity): Long

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(items: List<CustomListItemEntity>): List<Long>

    @Update
    suspend fun update(item: CustomListItemEntity): Int

    @Query("DELETE FROM custom_list_items WHERE id = :id")
    suspend fun deleteById(id: Long): Int

    @Query("SELECT * FROM custom_list_items WHERE list_key = :listKey AND is_active = 1 ORDER BY sort_order, name")
    fun getActiveByListKey(listKey: String): Flow<List<CustomListItemEntity>>

    @Query("SELECT * FROM custom_list_items WHERE list_key = :listKey AND is_active = 1 ORDER BY sort_order, name")
    suspend fun getActiveByListKeyOnce(listKey: String): List<CustomListItemEntity>

    @Query("SELECT * FROM custom_list_items WHERE list_key = :listKey ORDER BY sort_order, name")
    suspend fun getAllByListKey(listKey: String): List<CustomListItemEntity>

    @Query("SELECT * FROM custom_list_items WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getByLocalUuid(localUuid: String): CustomListItemEntity?

    @Query("SELECT * FROM custom_list_items WHERE list_key = :listKey AND name = :name LIMIT 1")
    suspend fun getByName(listKey: String, name: String): CustomListItemEntity?
}