package com.marina.marina.domain.repository

import com.marina.marina.domain.model.BookingNight
import com.marina.marina.domain.model.BookingPriceAdjustment
import com.marina.marina.domain.model.HotelDayLedger
import kotlinx.coroutines.flow.Flow

interface BookingNightsRepository {
    suspend fun getByBooking(bookingId: Long): List<BookingNight>
    suspend fun replaceNights(bookingId: Long, nights: List<BookingNight>)
    suspend fun getActiveAdjustments(bookingUuid: String): List<BookingPriceAdjustment>
    suspend fun upsertAdjustment(adjustment: BookingPriceAdjustment): Long
    suspend fun deactivateAdjustment(id: Long)
    fun watchLedger(): Flow<List<HotelDayLedger>>
    suspend fun upsertLedger(entry: HotelDayLedger)
}
