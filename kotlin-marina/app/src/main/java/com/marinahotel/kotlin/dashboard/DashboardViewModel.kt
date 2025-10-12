package com.marinahotel.kotlin.dashboard

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.marinahotel.kotlin.data.db.HotelDatabase
import com.marinahotel.kotlin.data.repository.DashboardRepository
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn

class DashboardViewModel(application: Application) : AndroidViewModel(application) {
    private val db = HotelDatabase.getInstance(application)
    private val repo = DashboardRepository(db.roomDao(), db.bookingDao(), db.expenseDao())

    val stats: StateFlow<DashboardRepository.Stats> = repo.stats().stateIn(viewModelScope, SharingStarted.Lazily, DashboardRepository.Stats(0,0,0,0))
}