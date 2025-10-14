package com.marinahotel.kotlin.presentation.common

import androidx.fragment.app.Fragment
import com.marinahotel.kotlin.HotelApplication
import com.marinahotel.kotlin.data.repository.HotelRepository

fun Fragment.hotelRepository(): HotelRepository {
    val app = requireActivity().application as HotelApplication
    return app.repository
}
