package com.marinahotel.kotlin.data.db

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.marinahotel.kotlin.data.entities.BookingEntity
import com.marinahotel.kotlin.data.entities.BookingNoteEntity
import com.marinahotel.kotlin.data.entities.CashRegisterEntity
import com.marinahotel.kotlin.data.entities.CashTransactionEntity
import com.marinahotel.kotlin.data.entities.EmployeeEntity
import com.marinahotel.kotlin.data.entities.ExpenseEntity
import com.marinahotel.kotlin.data.entities.ExpenseLogEntity
import com.marinahotel.kotlin.data.entities.FailedLoginEntity
import com.marinahotel.kotlin.data.entities.InvoiceEntity
import com.marinahotel.kotlin.data.entities.PaymentEntity
import com.marinahotel.kotlin.data.entities.PermissionEntity
import com.marinahotel.kotlin.data.entities.RoomEntity
import com.marinahotel.kotlin.data.entities.SalaryWithdrawalEntity
import com.marinahotel.kotlin.data.entities.SupplierEntity
import com.marinahotel.kotlin.data.entities.UserActivityLogEntity
import com.marinahotel.kotlin.data.entities.UserEntity
import com.marinahotel.kotlin.data.entities.UserPermissionEntity

@Dao
interface RoomDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(room: RoomEntity)

    @Update
    suspend fun update(room: RoomEntity)

    @Query("SELECT * FROM rooms")
    suspend fun getAll(): List<RoomEntity>

    @Query("SELECT * FROM rooms WHERE status = :status")
    suspend fun getByStatus(status: String): List<RoomEntity>
}

@Dao
interface BookingDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(booking: BookingEntity)

    @Update
    suspend fun update(booking: BookingEntity)

    @Query("SELECT * FROM bookings")
    suspend fun getAll(): List<BookingEntity>

    @Query("SELECT * FROM bookings WHERE status = 'محجوزة'")
    suspend fun getActive(): List<BookingEntity>
}

@Dao
interface BookingNoteDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(note: BookingNoteEntity)

    @Query("SELECT * FROM booking_notes WHERE booking_id = :bookingId")
    suspend fun getByBooking(bookingId: Int): List<BookingNoteEntity>
}

@Dao
interface UserDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(user: UserEntity)

    @Query("SELECT * FROM users WHERE username = :username LIMIT 1")
    suspend fun getByUsername(username: String): UserEntity?
}

@Dao
interface PermissionDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(permission: PermissionEntity)

    @Query("SELECT * FROM permissions")
    suspend fun getAll(): List<PermissionEntity>
}

@Dao
interface UserPermissionDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(permission: UserPermissionEntity)

    @Query("SELECT permission_id FROM user_permissions WHERE user_id = :userId")
    suspend fun getPermissionsFor(userId: Int): List<Int>
}

@Dao
interface PaymentDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(payment: PaymentEntity)

    @Query("SELECT * FROM payments WHERE booking_id = :bookingId")
    suspend fun getByBooking(bookingId: Int): List<PaymentEntity>
}

@Dao
interface CashRegisterDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(register: CashRegisterEntity)

    @Query("SELECT * FROM cash_register ORDER BY date DESC LIMIT 1")
    suspend fun getLast(): CashRegisterEntity?
}

@Dao
interface CashTransactionDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(transaction: CashTransactionEntity)

    @Query("SELECT * FROM cash_transactions WHERE register_id = :registerId")
    suspend fun getByRegister(registerId: Int): List<CashTransactionEntity>
}

@Dao
interface ExpenseDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(expense: ExpenseEntity)

    @Query("SELECT * FROM expenses ORDER BY date DESC")
    suspend fun getAll(): List<ExpenseEntity>
}

@Dao
interface ExpenseLogDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(log: ExpenseLogEntity)

    @Query("SELECT * FROM expense_logs WHERE expense_id = :expenseId ORDER BY created_at DESC")
    suspend fun getByExpense(expenseId: Int): List<ExpenseLogEntity>
}

@Dao
interface EmployeeDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(employee: EmployeeEntity)

    @Query("SELECT * FROM employees")
    suspend fun getAll(): List<EmployeeEntity>
}

@Dao
interface SalaryWithdrawalDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(withdrawal: SalaryWithdrawalEntity)

    @Query("SELECT * FROM salary_withdrawals WHERE employee_id = :employeeId ORDER BY date DESC")
    suspend fun getByEmployee(employeeId: Int): List<SalaryWithdrawalEntity>
}

@Dao
interface SupplierDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(supplier: SupplierEntity)

    @Query("SELECT * FROM suppliers")
    suspend fun getAll(): List<SupplierEntity>
}

@Dao
interface InvoiceDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(invoice: InvoiceEntity)

    @Query("SELECT * FROM invoices WHERE booking_id = :bookingId")
    suspend fun getByBooking(bookingId: Int): List<InvoiceEntity>
}

@Dao
interface UserActivityLogDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(log: UserActivityLogEntity)

    @Query("SELECT * FROM user_activity_log ORDER BY created_at DESC LIMIT 50")
    suspend fun getRecent(): List<UserActivityLogEntity>
}

@Dao
interface FailedLoginDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(login: FailedLoginEntity)

    @Query("SELECT * FROM failed_logins WHERE username = :username ORDER BY attempt_time DESC LIMIT 5")
    suspend fun getRecentByUser(username: String): List<FailedLoginEntity>
}
