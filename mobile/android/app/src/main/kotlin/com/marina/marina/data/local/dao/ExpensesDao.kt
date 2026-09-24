package com.marina.marina.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marina.marina.data.local.entity.ExpenseEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface ExpensesDao {
    @Query("SELECT * FROM expenses WHERE deleted_at IS NULL ORDER BY date DESC")
    fun getAll(): Flow<List<ExpenseEntity>>

    @Query("SELECT * FROM expenses WHERE deleted_at IS NULL ORDER BY date DESC")
    suspend fun getAllOnce(): List<ExpenseEntity>

    @Query("SELECT * FROM expenses WHERE id = :id AND deleted_at IS NULL")
    suspend fun getById(id: Long): ExpenseEntity?

    @Query("SELECT * FROM expenses WHERE expense_type LIKE :search AND deleted_at IS NULL ORDER BY date DESC")
    fun search(search: String): Flow<List<ExpenseEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(expense: ExpenseEntity): Long

    @Update
    suspend fun update(expense: ExpenseEntity)

    @Query("UPDATE expenses SET deleted_at = :deletedAt, updated_at = :updatedAt WHERE id = :id")
    suspend fun softDelete(id: Long, deletedAt: Long, updatedAt: Long): Int
    @Query("SELECT * FROM expenses WHERE local_uuid = :localUuid LIMIT 1")
    suspend fun getByLocalUuid(localUuid: String): ExpenseEntity?

    /**
     * Live total of expenses for a hotel day, ported 1:1 from the Flutter
     * app's expenses repo. Legacy rows without `hotel_day_key` fall back to
     * matching `date LIKE 'yyyy-MM-dd%'`. Salary-advance cash-outs count as
     * today's expenses (same contract as the Flutter `todayExpensesProvider`).
     */
    @Query(
        """
        SELECT COALESCE(SUM(amount), 0.0) FROM expenses
        WHERE deleted_at IS NULL
          AND (hotel_day_key = :hotelDayKey
               OR (hotel_day_key IS NULL AND date LIKE :hotelDayKeyPrefix))
        """
    )
    fun watchTotalByHotelDayKey(hotelDayKey: String, hotelDayKeyPrefix: String): Flow<Double>

    /**
     * Report query ported from Dart `ExpensesDao.listFilteredByHotelDay`
     * (expenses_dao.dart:111-174): hotel-day range with legacy `date`
     * fallback, optional type filter (salary contract: 'رواتب' also matches
     * the derived salary types), optional search on description/type.
     */
    @Query(
        """
        SELECT * FROM expenses
        WHERE deleted_at IS NULL
          AND (:fromHotelDay IS NULL
               OR hotel_day_key IS NOT NULL AND hotel_day_key >= :fromHotelDay
               OR hotel_day_key IS NULL AND date >= :fromHotelDay)
          AND (:toHotelDay IS NULL
               OR hotel_day_key IS NOT NULL AND hotel_day_key <= :toHotelDay
               OR hotel_day_key IS NULL AND date < :toHotelDayExclusive)
          AND (:expenseType IS NULL
               OR (:isSalaryType = 1 AND expense_type IN ('رواتب','سحب راتب','سحب من الراتب','خصم راتب','خصم من الراتب'))
               OR (:isSalaryType = 0 AND expense_type = :expenseType))
          AND (:excludeAdvance = 0 OR expense_type != 'سلفة')
          AND (:search IS NULL
               OR description LIKE '%' || :search || '%'
               OR expense_type LIKE '%' || :search || '%')
        ORDER BY date DESC
        """
    )
    suspend fun listFilteredByHotelDay(
        fromHotelDay: String?,
        toHotelDay: String?,
        toHotelDayExclusive: String?,
        expenseType: String?,
        isSalaryType: Boolean,
        excludeAdvance: Boolean = false,
        search: String? = null
    ): List<ExpenseEntity>

    /** البحث الشامل — كل الصفوف بما فيها المحذوفة ناعمياً (تدقيق المدير). */
    @Query("SELECT * FROM expenses")
    suspend fun listAllIncludingDeleted(): List<ExpenseEntity>
}
