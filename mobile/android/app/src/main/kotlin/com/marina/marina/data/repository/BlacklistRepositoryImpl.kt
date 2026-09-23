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
import kotlinx.coroutines.flow.firstOrNull
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

    /**
     * Dart findBlacklistMatch (l.363-389) — the matcher normalizes Arabic
     * (strips tashkeel/tatweel, unifies alef/hamza/yaa variants), then matches
     * either the full normalized name or the first three name tokens.
     */
    override suspend fun findBlacklistMatch(name: String): BlacklistEntry? {
        if (name.isBlank()) return null
        val nNorm = normalizeArabic(name)
        val nTokens = nNorm.split(Regex("\\s+")).filter { it.isNotEmpty() }
        val entries = dao.getActive().firstOrNull() ?: emptyList()
        for (row in entries) {
            val rNorm = normalizeArabic(row.name)
            val rTokens = rNorm.split(Regex("\\s+")).filter { it.isNotEmpty() }
            val fullEq = rNorm == nNorm
            val tripleEq = rTokens.size >= 3 && nTokens.size >= 3 &&
                rTokens[0] == nTokens[0] && rTokens[1] == nTokens[1] && rTokens[2] == nTokens[2]
            if (fullEq || tripleEq) {
                val domain = row.toDomain()
                if (domain.active) return domain
            }
        }
        return null
    }

    /** Dart _normalizeArabic (l.11-29). */
    private fun normalizeArabic(input: String): String {
        var s = input.trim()
        s = Regex("[\u0617-\u061A\u064B-\u0652\u0670\u0653-\u065F\u06D6-\u06ED]").replace(s, "") // tashkeel
        s = s.replace("\u0640", "") // tatweel
        s = s.replace(Regex("[إأٱآ]"), "ا")
        s = s.replace("ؤ", "و")
        s = s.replace("ئ", "ي")
        s = s.replace("ى", "ي")
        s = Regex("[^\u0621-\u064A0-9 ]+").replace(s, " ")
        s = Regex(" +").replace(s, " ").trim()
        return s.lowercase()
    }

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
