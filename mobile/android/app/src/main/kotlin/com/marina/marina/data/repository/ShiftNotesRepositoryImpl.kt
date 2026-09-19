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

    override suspend fun markRead(id: Long) {
        shiftNotesDao.markRead(id)
    }

    override suspend fun delete(id: Long) {
        shiftNotesDao.delete(id)
    }
}
