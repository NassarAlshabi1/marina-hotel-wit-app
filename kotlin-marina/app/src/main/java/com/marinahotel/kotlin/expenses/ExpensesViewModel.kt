package com.marinahotel.kotlin.expenses

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.marinahotel.kotlin.data.db.HotelDatabase
import com.marinahotel.kotlin.data.entities.ExpenseEntity
import com.marinahotel.kotlin.data.repository.ExpensesRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class ExpensesViewModel(application: Application) : AndroidViewModel(application) {
    private val repo = ExpensesRepository(
        HotelDatabase.getInstance(application).expenseDao(),
        HotelDatabase.getInstance(application).expenseLogDao()
    )

    val expenses: StateFlow<List<ExpenseUi>> = repo.flowAllExpenses()
        .map { list -> list.map { ExpenseUi(description = it.description, type = it.expenseType, date = it.date, amount = it.amount) } }
        .stateIn(viewModelScope, SharingStarted.Lazily, emptyList())

    fun save(description: String, type: String, date: String, amount: Double) {
        viewModelScope.launch(Dispatchers.IO) {
            val now = date.ifBlank { date }
            repo.save(
                ExpenseEntity(
                    expenseType = type,
                    relatedId = null,
                    description = description,
                    amount = amount,
                    date = date,
                    cashTransactionId = null,
                    createdBy = null,
                    createdAt = now
                )
            )
        }
    }
}