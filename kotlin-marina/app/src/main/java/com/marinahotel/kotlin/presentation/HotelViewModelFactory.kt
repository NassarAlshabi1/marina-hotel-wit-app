package com.marinahotel.kotlin.presentation

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider

class HotelViewModelFactory<T : ViewModel>(
    private val creator: () -> T
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = creator() as T
}
