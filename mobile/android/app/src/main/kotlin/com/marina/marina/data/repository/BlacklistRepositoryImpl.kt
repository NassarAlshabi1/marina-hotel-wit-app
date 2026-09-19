package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.BlacklistEntriesDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.BlacklistEntry
import com.marina.marina.domain.repository.BlacklistRepository
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class BlacklistRepositoryImpl @Inject constructor(
    private val dao: BlacklistEntriesDao,
    private val outboxRepository: OutboxRepository
) : BlacklistRepository {

    override fun getActive(): Flow<List<BlacklistEntry>> =
        dao.getActive().map { list -> list.map { it.toDomain() } }

    override fun searchActive(query: String): Flow<List<BlacklistEntry>> =
        dao.searchActive("%$query%").map { list -> list.map { it.toDomain() } }

    override suspend fun getById(id: Long): BlacklistEntry? = dao.getById(id)?.toDomain()

    override suspend fun insert(entry: BlacklistEntry): Long {
        val now = System.currentTimeMillis()
        val prepared = entry.copy(
            localUuid = entry.localUuid.ifBlank { UUID.randomUUID().toString() },
            createdAt = if (entry.createdAt == 0L) now else entry.createdAt,
            updatedAt = now
        )
        val id = dao.insert(prepared.toEntity())
        outboxRepository.enqueueObject("blacklist_entries", "insert", prepared.localUuid, prepared)
        return id
    }

    override suspend fun update(entry: BlacklistEntry) {
        val prepared = entry.copy(updatedAt = System.currentTimeMillis())
        dao.update(prepared.toEntity())
        outboxRepository.enqueueObject("blacklist_entries", "update", prepared.localUuid, prepared)
    }

    override suspend fun setActive(id: Long, active: Boolean) {
        val current = dao.getById(id) ?: return
        dao.update(current.copy(active = active, updatedAt = System.currentTimeMillis()))
    }

    override suspend fun softDelete(id: Long) {
        val now = System.currentTimeMillis()
        dao.softDelete(id, deletedAt = now, updatedAt = now, lastModified = now)
    }
}
