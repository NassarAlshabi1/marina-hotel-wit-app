package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.GuestInfosDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.GuestInfo
import com.marina.marina.domain.repository.GuestInfosRepository
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class GuestInfosRepositoryImpl @Inject constructor(
    private val dao: GuestInfosDao,
    private val outboxRepository: OutboxRepository
) : GuestInfosRepository {

    override fun getAll(): Flow<List<GuestInfo>> =
        dao.getAll().map { list -> list.map { it.toDomain() } }

    override fun search(query: String): Flow<List<GuestInfo>> =
        dao.search("%$query%").map { list -> list.map { it.toDomain() } }

    override suspend fun getByRoom(roomNumber: String): List<GuestInfo> =
        dao.getByRoom(roomNumber).map { it.toDomain() }

    override suspend fun getById(id: Long): GuestInfo? = dao.getById(id)?.toDomain()

    override suspend fun insert(guest: GuestInfo): Long {
        val now = System.currentTimeMillis()
        val prepared = guest.copy(
            localUuid = guest.localUuid.ifBlank { UUID.randomUUID().toString() },
            createdAt = if (guest.createdAt == 0L) now else guest.createdAt,
            updatedAt = now
        )
        val id = dao.insert(prepared.toEntity())
        outboxRepository.enqueueObject("guest_infos", "insert", prepared.localUuid, prepared)
        return id
    }

    override suspend fun update(guest: GuestInfo) {
        val prepared = guest.copy(updatedAt = System.currentTimeMillis())
        dao.update(prepared.toEntity())
        outboxRepository.enqueueObject("guest_infos", "update", prepared.localUuid, prepared)
    }

    override suspend fun softDelete(id: Long) {
        val now = System.currentTimeMillis()
        dao.softDelete(id, deletedAt = now, updatedAt = now, lastModified = now)
    }
}
