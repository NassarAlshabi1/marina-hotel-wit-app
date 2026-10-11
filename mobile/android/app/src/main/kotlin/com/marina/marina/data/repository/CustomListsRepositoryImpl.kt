package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.CustomListsDao
import com.marina.marina.data.local.entity.CustomListItemEntity
import com.marina.marina.domain.repository.CustomListsRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class CustomListsRepositoryImpl @Inject constructor(
    private val dao: CustomListsDao
) : CustomListsRepository {

    override fun getActiveNames(listKey: String): Flow<List<String>> =
        dao.getActiveByListKey(listKey).map { entities -> entities.map { it.name } }

    override suspend fun getActiveNamesOnce(listKey: String): List<String> =
        dao.getActiveByListKeyOnce(listKey).map { it.name }

    override suspend fun getAllByListKey(listKey: String): List<CustomListItemEntity> =
        dao.getAllByListKey(listKey)

    override suspend fun insert(item: CustomListItemEntity): Long = dao.insert(item)

    override suspend fun insertAll(items: List<CustomListItemEntity>): List<Long> = dao.insertAll(items)

    override suspend fun update(item: CustomListItemEntity): Int = dao.update(item)

    override suspend fun deleteById(id: Long): Int = dao.deleteById(id)

    override suspend fun getByLocalUuid(localUuid: String): CustomListItemEntity? = dao.getByLocalUuid(localUuid)

    override suspend fun getByName(listKey: String, name: String): CustomListItemEntity? = dao.getByName(listKey, name)
}