package com.marina.marina.domain.util

/**
 * Business-rule source of truth for the free-text status strings stored on
 * rooms/bookings/employees (Arabic + English, mixed casing/whitespace in the
 * data). Ported 1:1 from the Flutter app's `lib/utils/status_utils.dart` so
 * both clients agree on what "occupied"/"active"/"terminated" mean.
 */
object StatusUtils {

    private fun normalize(status: String): String = status.trim().lowercase()

    private val availableRoomStatuses = setOf(
        "شاغرة", "شاغره", "متاحة", "متاح", "available", "vacant", "empty"
    ).map(::normalize).toSet()

    private val occupiedRoomStatuses = setOf(
        "محجوزة", "محجوز", "مشغولة", "occupied", "محجوز temporarily", "نشط", "active", "مؤقت", "provisional"
    ).map(::normalize).toSet()

    private val maintenanceRoomStatuses = setOf(
        "صيانة", "maintenance", "under_maintenance", "under maintenance"
    ).map(::normalize).toSet()

    private val activeBookingStatuses = setOf(
        "محجوزة", "محجوز", "نشط", "active", "confirmed", "قيد الحجز", "in_progress", "مؤقت", "provisional"
    ).map(::normalize).toSet()

    private val activeEmployeeStatuses = setOf("نشط", "active").map(::normalize).toSet()

    private val terminatedEmployeeStatuses = setOf(
        "مفصول", "terminated", "استقالة", "resigned", "استغناء", "laid_off"
    ).map(::normalize).toSet()

    fun isRoomAvailable(status: String): Boolean = availableRoomStatuses.contains(normalize(status))
    fun isRoomOccupied(status: String): Boolean = occupiedRoomStatuses.contains(normalize(status))
    fun isRoomUnderMaintenance(status: String): Boolean = maintenanceRoomStatuses.contains(normalize(status))
    fun isBookingActive(status: String): Boolean = activeBookingStatuses.contains(normalize(status))
    fun isEmployeeActive(status: String): Boolean = activeEmployeeStatuses.contains(normalize(status))
    fun isEmployeeTerminated(status: String): Boolean = terminatedEmployeeStatuses.contains(normalize(status))
}
