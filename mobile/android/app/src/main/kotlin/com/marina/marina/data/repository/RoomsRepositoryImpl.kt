package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.RoomsDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.Room
import com.marina.marina.domain.repository.RoomsRepository
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class RoomsRepositoryImpl @Inject constructor(
    private val roomsDao: RoomsDao
) : RoomsRepository {

    override fun getAll(): Flow<List<Room>> =
        roomsDao.getAll().map { entities -> entities.map { it.toDomain() } }

    override suspend fun insert(room: Room): Long = roomsDao.insert(room.toEntity())

    override suspend fun update(room: Room) = roomsDao.update(room.toEntity())

    override suspend fun softDelete(id: Long) {
        val now = System.currentTimeMillis()
        roomsDao.softDelete(id, deletedAt = now, updatedAt = now, lastModified = now)
    }

    override suspend fun getByNumber(roomNumber: String): Room? =
        roomsDao.getByNumber(roomNumber)?.toDomain()
}
