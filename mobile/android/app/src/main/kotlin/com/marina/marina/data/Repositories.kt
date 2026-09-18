package com.marina.marina.data

import androidx.room.*
import kotlinx.coroutines.flow.Flow
import com.marina.marina.domain.Payment
import com.marina.marina.domain.PaymentMethod
import com.marina.marina.domain.PaymentStatus
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class PaymentsRepository @Inject constructor(
    private val paymentsDao: PaymentsDao
) {
    fun getAll(): Flow<List<com.marina.marina.data.Payment>> = paymentsDao.getAll()

    suspend fun insert(payment: com.marina.marina.data.Payment): Long = paymentsDao.insert(payment)

    suspend fun update(payment: com.marina.marina.data.Payment) = paymentsDao.update(payment)

    suspend fun void(id: Long, voidedBy: String, voidReason: String) {
        paymentsDao.void(id, System.currentTimeMillis(), voidedBy, voidReason, System.currentTimeMillis())
    }

    fun getByBooking(bookingId: Long): Flow<List<com.marina.marina.data.Payment>> =
        paymentsDao.getByBooking(bookingId)
}

@Singleton
class RoomsRepository @Inject constructor(
    private val roomsDao: RoomsDao
) {
    fun getAll(): Flow<List<com.marina.marina.data.Room>> = roomsDao.getAll()

    suspend fun insert(room: com.marina.marina.data.Room): Long = roomsDao.insert(room)

    suspend fun update(room: com.marina.marina.data.Room) = roomsDao.update(room)

    suspend fun softDelete(id: Long) {
        roomsDao.softDelete(id, System.currentTimeMillis(), System.currentTimeMillis(), System.currentTimeMillis())
    }

    fun getByNumber(roomNumber: String): com.marina.marina.data.Room? = roomsDao.getByNumber(roomNumber)
}

@Singleton
class BookingsRepository @Inject constructor(
    private val bookingsDao: BookingsDao
) {
    fun getAll(): Flow<List<com.marina.marina.data.Booking>> = bookingsDao.getAll()

    suspend fun insert(booking: com.marina.marina.data.Booking): Long = bookingsDao.insert(booking)

    suspend fun update(booking: com.marina.marina.data.Booking) = bookingsDao.update(booking)

    suspend fun checkout(id: Long, status: String, actualCheckout: String? = null) {
        bookingsDao.checkout(id, status, actualCheckout, System.currentTimeMillis(), System.currentTimeMillis())
    }

    suspend fun softDelete(id: Long) {
        bookingsDao.softDelete(id, System.currentTimeMillis(), System.currentTimeMillis(), System.currentTimeMillis())
    }
}

@Singleton
class EmployeesRepository @Inject constructor(
    private val employeesDao: EmployeesDao
) {
    fun getAll(): Flow<List<com.marina.marina.data.Employee>> = employeesDao.getAll()

    suspend fun insert(employee: com.marina.marina.data.Employee): Long = employeesDao.insert(employee)

    suspend fun update(employee: com.marina.marina.data.Employee) = employeesDao.update(employee)

    suspend fun terminate(id: Long, reason: String? = null) {
        employeesDao.terminate(id, "terminated", null, reason, System.currentTimeMillis())
    }
}

@Singleton
class ExpensesRepository @Inject constructor(
    private val expensesDao: ExpensesDao
) {
    fun getAll(): Flow<List<com.marina.marina.data.Expense>> = expensesDao.getAll()

    suspend fun insert(expense: com.marina.marina.data.Expense): Long = expensesDao.insert(expense)

    suspend fun update(expense: com.marina.marina.data.Expense) = expensesDao.update(expense)

    suspend fun softDelete(id: Long) {
        expensesDao.softDelete(id, System.currentTimeMillis(), System.currentTimeMillis())
    }
}

@Singleton
class DebtsRepository @Inject constructor(
    private val debtsDao: DebtsDao
) {
    fun getUnsettled(): Flow<List<com.marina.marina.data.Debt>> = debtsDao.getUnsettled()

    suspend fun insert(debt: com.marina.marina.data.Debt): Long = debtsDao.insert(debt)

    suspend fun update(debt: com.marina.marina.data.Debt) = debtsDao.update(debt)

    suspend fun markSettled(id: Long, paidAmount: Double) {
        val remaining = 0.0
        debtsDao.updateSettlement(id, paidAmount, remaining, 1)
    }
}

@Singleton
class OutboxRepository @Inject constructor(
    private val outboxDao: OutboxDao,
    private val syncService: CloudflareSyncService
) {
    fun getPending(): Flow<List<com.marina.marina.data.Outbox>> = outboxDao.getPendingPrimary()

    suspend fun enqueue(entity: String, op: String, localUuid: String, payload: Map<String, Any>): Long {
        val outbox = com.marina.marina.data.Outbox(
            entity = entity,
            op = op,
            localUuid = localUuid,
            payload = com.google.gson.Gson().toJson(payload),
            clientTs = System.currentTimeMillis(),
            idempotencyKey = "${entity}_${op}_${localUuid}"
        )
        return outboxDao.insert(outbox)
    }

    suspend fun processPending() {
        // Implementation: process pending outbox items via CloudflareSyncService.push()
    }

    suspend fun syncOutbox() {
        // Implementation: process pending outbox items via CloudflareSyncService.push()
    }
}