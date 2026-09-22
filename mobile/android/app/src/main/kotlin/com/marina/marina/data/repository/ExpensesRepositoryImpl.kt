package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.ExpensesDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.Expense
import com.marina.marina.domain.repository.ExpensesRepository
import com.marina.marina.domain.util.HotelTimeEngine
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class ExpensesRepositoryImpl @Inject constructor(
    private val expensesDao: ExpensesDao,
    private val outboxRepository: OutboxRepository
) : ExpensesRepository {

    override fun getAll(): Flow<List<Expense>> =
        expensesDao.getAll().map { entities -> entities.map { it.toDomain() } }

    override suspend fun insert(expense: Expense): Long {
        val now = System.currentTimeMillis()
        val prepared = expense.copy(
            localUuid = expense.localUuid.ifBlank { UUID.randomUUID().toString() },
            date = expense.date.ifBlank { HotelTimeEngine.formatIso(now) },
            hotelDayKey = expense.hotelDayKey ?: HotelTimeEngine.currentHotelDayKey(),
            createdAt = if (expense.createdAt == 0L) now else expense.createdAt,
            updatedAt = now
        )
        val id = expensesDao.insert(prepared.toEntity())
        outboxRepository.enqueueObject("expenses", "insert", prepared.localUuid, prepared)
        return id
    }

    override suspend fun update(expense: Expense) {
        val prepared = expense.copy(updatedAt = System.currentTimeMillis())
        expensesDao.update(prepared.toEntity())
        outboxRepository.enqueueObject("expenses", "update", prepared.localUuid, prepared)
    }

    override suspend fun softDelete(id: Long) {
        val now = System.currentTimeMillis()
        expensesDao.softDelete(id, deletedAt = now, updatedAt = now)
    }


    override suspend fun getAllOnce(): List<Expense> =
        expensesDao.getAllOnce().map { it.toDomain() }

    private val salaryTypes = setOf("رواتب", "سحب راتب", "سحب من الراتب", "خصم راتب", "خصم من الراتب")

    override suspend fun listFilteredByHotelDay(
        fromHotelDay: String?,
        toHotelDay: String?,
        expenseType: String?
    ): List<Expense> {
        // Dart SqlDateRange.forDay(toHotelDay).endExclusive — next calendar day.
        val toExclusive = toHotelDay?.let { key ->
            HotelTimeEngine.parseDate("$key 00:00:00")?.let { ms ->
                val cal = java.util.Calendar.getInstance()
                cal.timeInMillis = ms
                cal.add(java.util.Calendar.DAY_OF_YEAR, 1)
                HotelTimeEngine.formatIso(cal.timeInMillis).replace("T", " ").substring(0, 10)
            }
        }
        val isSalaryType = expenseType != null && salaryTypes.contains(expenseType)
        return expensesDao.listFilteredByHotelDay(
            fromHotelDay = fromHotelDay,
            toHotelDay = toHotelDay,
            toHotelDayExclusive = toExclusive,
            expenseType = expenseType,
            isSalaryType = isSalaryType
        ).map { it.toDomain() }
    }

    override fun watchTotalByHotelDayKey(hotelDayKey: String): Flow<Double> =
        expensesDao.watchTotalByHotelDayKey(hotelDayKey, "${hotelDayKey}%")
}
