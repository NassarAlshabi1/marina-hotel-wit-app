package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.ShiftNotesDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.ShiftNote
import com.marina.marina.domain.repository.ShiftNotesRepository
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class ShiftNotesRepositoryImpl @Inject constructor(
    private val shiftNotesDao: ShiftNotesDao,
    private val outboxRepository: OutboxRepository
) : ShiftNotesRepository {

    override fun getAll(): Flow<List<ShiftNote>> =
        shiftNotesDao.getAll().map { entities -> entities.map { it.toDomain() } }

    override fun getUnread(): Flow<List<ShiftNote>> =
        shiftNotesDao.getUnread().map { entities -> entities.map { it.toDomain() } }

    override suspend fun insert(note: ShiftNote): Long {
        val now = System.currentTimeMillis()
        val prepared = note.copy(
            localUuid = note.localUuid.ifBlank { UUID.randomUUID().toString() },
            createdAt = if (note.createdAt == 0L) now else note.createdAt
        )
        val id = shiftNotesDao.insert(prepared.toEntity())
        outboxRepository.enqueueObject("shift_notes", "insert", prepared.localUuid, prepared)
        return id
    }

    override suspend fun update(note: ShiftNote) {
        shiftNotesDao.update(note.toEntity())
        outboxRepository.enqueueObject("shift_notes", "update", note.localUuid, note)
    }

    /**
     * Dart markAsRead (shift_notes_dao l.172-217): flips the flag, bumps the
     * OCC version, and enqueues an outbox update so read-state syncs across
     * devices.
     */
    override suspend fun markRead(id: Long) {
        val now = System.currentTimeMillis()
        val entity = shiftNotesDao.getById(id) ?: return
        shiftNotesDao.markRead(id, updatedAt = now)
        val read = entity.toDomain().copy(isRead = true, version = entity.version + 1, updatedAt = now)
        outboxRepository.enqueueObject("shift_notes", "update", read.localUuid, read)
    }

    /**
     * Dart delete (l.252-313): a confirmed SOFT delete that propagates to the
     * cloud — never a local-only hard DELETE.
     */
    override suspend fun delete(id: Long) {
        val now = System.currentTimeMillis()
        val entity = shiftNotesDao.getById(id) ?: return
        shiftNotesDao.softDelete(id, deletedAt = now, updatedAt = now)
        val deleted = entity.toDomain().copy(deletedAt = now, updatedAt = now)
        outboxRepository.enqueueObject("shift_notes", "delete", deleted.localUuid, deleted)
    }
}
