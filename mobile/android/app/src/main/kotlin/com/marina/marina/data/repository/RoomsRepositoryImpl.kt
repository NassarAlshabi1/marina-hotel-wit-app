package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.RoomsDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.Room
import com.marina.marina.domain.repository.RoomsRepository
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class RoomsRepositoryImpl @Inject constructor(
    private val roomsDao: RoomsDao,
    private val outboxRepository: OutboxRepository
) : RoomsRepository {

    override fun getAll(): Flow<List<Room>> =
        roomsDao.getAll().map { entities -> entities.map { it.toDomain() } }

    override suspend fun insert(room: Room): Long {
        val now = System.currentTimeMillis()
        val prepared = room.copy(
            localUuid = room.localUuid.ifBlank { UUID.randomUUID().toString() },
            createdAt = if (room.createdAt == 0L) now else room.createdAt,
            updatedAt = now
        )
        val id = roomsDao.insert(prepared.toEntity())
        outboxRepository.enqueueObject("rooms", "insert", prepared.localUuid, prepared)
        return id
    }

    override suspend fun update(room: Room) {
        val prepared = room.copy(updatedAt = System.currentTimeMillis())
        roomsDao.update(prepared.toEntity())
        outboxRepository.enqueueObject("rooms", "update", prepared.localUuid, prepared)
    }

    override suspend fun softDelete(id: Long) {
        val now = System.currentTimeMillis()
        roomsDao.softDelete(id, deletedAt = now, updatedAt = now, lastModified = now)
    }

    override suspend fun getByNumber(roomNumber: String): Room? =
        roomsDao.getByNumber(roomNumber)?.toDomain()
}
