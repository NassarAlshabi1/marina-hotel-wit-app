package com.marinahotel.kotlin.payments

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.marinahotel.kotlin.data.db.HotelDatabase
import com.marinahotel.kotlin.data.repository.PaymentsRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class PaymentsViewModel(application: Application) : AndroidViewModel(application) {
    private val repo = PaymentsRepository(HotelDatabase.getInstance(application).paymentDao())

    val recentPayments: StateFlow<List<PaymentItem>> = repo.flowRecent()
        .map { list -> list.map { PaymentItem(title = "BKG-${it.bookingId}", method = it.paymentMethod, amount = "${it.amount} ر.س") } }
        .stateIn(viewModelScope, SharingStarted.Lazily, emptyList())

    fun paymentsForBooking(bookingId: Int): StateFlow<List<PaymentTransaction>> = repo.flowByBooking(bookingId)
        .map { list -> list.map { PaymentTransaction(title = "${it.paymentMethod}", method = it.paymentMethod, date = it.paymentDate, amount = "${it.amount} ر.س") } }
        .stateIn(viewModelScope, SharingStarted.Lazily, emptyList())

    fun addPayment(bookingId: Int, amount: Int, method: String, note: String?) {
        viewModelScope.launch(Dispatchers.IO) {
            repo.addPayment(
                com.marinahotel.kotlin.data.entities.PaymentEntity(
                    bookingId = bookingId,
                    amount = amount,
                    paymentDate = java.time.LocalDateTime.now().toString(),
                    notes = note,
                    paymentMethod = method,
                    revenueType = "room",
                    cashTransactionId = null,
                    roomNumber = null
                )
            )
        }
    }
}