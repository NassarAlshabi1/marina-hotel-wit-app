package com.marina.marina.data.backup

import com.marina.marina.data.local.AppDatabase
import com.marina.marina.data.local.entity.AutoFixRunEntity
import com.marina.marina.domain.util.HotelTimeEngine
import dagger.hilt.android.qualifiers.ApplicationContext
import android.content.Context
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/**
 * خدمة الإصلاح التلقائي بعد الاستعادة — نقل RestoreFixService من فرع
 * Flutter (mobile/lib/services/restore_fix_service.dart) بنفس العقد:
 *
 *  1. الحجوزات النشطة (بلا مغادرة فعلية) → إعادة حساب الليالي بقاعدة
 *     الساعة 14:00 وتحديث calculated_nights/expected_nights عند التغيير.
 *  2. إعادة حساب الماليات: مجموع المدفوع الفعلي مقابل المتوقع من ليل الحجز
 *     (أو سعر الغرفة × الليالي مع الخصم) وتحديث paid/remaining عند التغيير.
 *  3. تحديث حالات الغرف من الحجوزات النشطة.
 *  4. تسجيل كل تغيير في restore_fix_log + سجل تشغيل في auto_fix_runs.
 */
@Singleton
class RestoreFixService @Inject constructor(
    @ApplicationContext private val context: Context,
    private val db: AppDatabase
) {
    suspend fun runAutoFixAfterRestore(): RestoreFixReport {
        val startTime = System.currentTimeMillis()
        var bookingsFixed = 0
        var roomsUpdated = 0
        var paymentsChecked = 0
        val fixId = UUID.randomUUID().toString()
        val logDao = db.restoreFixLogDao()

        try {
            val sq = db.openHelper.writableDatabase

            // ── 1) الحجوزات النشطة (نظير _getBookingsNeedingFix) ──
            data class BookingRow(
                val id: Long,
                val localUuid: String,
                val roomNumber: String,
                val status: String,
                val checkinDate: String,
                val checkoutDate: String?,
                val actualCheckout: String?,
                val calculatedNights: Int,
                val expectedNights: Int,
                val discount: Double,
                val discountType: String
            )
            val bookings = mutableListOf<BookingRow>()
            sq.query(
                "SELECT id, local_uuid, room_number, status, checkin_date, checkout_date, " +
                    "actual_checkout, calculated_nights, expected_nights, discount, discount_type " +
                    "FROM bookings WHERE deleted_at IS NULL AND actual_checkout IS NULL " +
                    "AND checkin_date IS NOT NULL AND checkin_date != ''"
            ).use { c ->
                while (c.moveToNext()) {
                    val status = c.getString(3) ?: ""
                    if (!isActiveBooking(status)) continue
                    bookings.add(
                        BookingRow(
                            id = c.getLong(0),
                            localUuid = c.getString(1) ?: "",
                            roomNumber = c.getString(2) ?: "",
                            status = status,
                            checkinDate = c.getString(4),
                            checkoutDate = c.getString(5),
                            actualCheckout = c.getString(6),
                            calculatedNights = c.getInt(7),
                            expectedNights = c.getInt(8),
                            discount = c.getDouble(9),
                            discountType = c.getString(10) ?: "per_night"
                        )
                    )
                }
            }

            val nowMillis = System.currentTimeMillis()
            for (b in bookings) {
                // ── إعادة حساب الليالي بقاعدة 14:00 ──
                val checkin = HotelTimeEngine.parseDate(b.checkinDate) ?: continue
                val checkout = when {
                    !b.actualCheckout.isNullOrEmpty() ->
                        HotelTimeEngine.parseDate(b.actualCheckout)
                    !b.checkoutDate.isNullOrEmpty() ->
                        HotelTimeEngine.parseDate(b.checkoutDate)
                    else -> nowMillis
                } ?: nowMillis
                val nights = HotelTimeEngine.nightsWithCutoff(checkin, checkout)
                if (nights != b.calculatedNights || nights != b.expectedNights) {
                    logChange(
                        logDao, fixId, startTime, "bookings", b.id,
                        "calculated_nights", b.calculatedNights.toString(), nights.toString(),
                        "إعادة حساب الليالي بناءً على تاريخ الدخول والخروج مع قاعدة 14:00",
                        "nights_recalc"
                    )
                    sq.execSQL(
                        "UPDATE bookings SET calculated_nights = ?, expected_nights = ?, " +
                            "updated_at = ?, last_modified = ? WHERE id = ?",
                        arrayOf(nights, nights, nowMillis, nowMillis, b.id)
                    )
                    bookingsFixed++
                }

                // ── إعادة حساب الماليات (نظير _recalculateBookingFinancials) ──
                var totalPaid = 0.0
                sq.query(
                    "SELECT COALESCE(SUM(amount), 0) FROM payments WHERE deleted_at IS NULL " +
                        "AND (booking_local_id = ? OR booking_uuid_cache = ?)",
                    arrayOf(b.id, b.localUuid)
                ).use { c -> if (c.moveToFirst()) totalPaid = c.getDouble(0) }

                val nightsTotal = queryNightsTotal(b.id)
                val expectedTotal: Double? = if (nightsTotal != null) {
                    nightsTotal
                } else {
                    val roomPrice = queryRoomPrice(b.roomNumber)
                    if (roomPrice == null) {
                        null
                    } else if (b.discountType == "total") {
                        val raw = roomPrice * nights - b.discount
                        raw.coerceIn(0.0, roomPrice * nights)
                    } else if (b.discount > 0) {
                        val discountedRate = (roomPrice - b.discount).coerceIn(0.0, roomPrice)
                        discountedRate * nights
                    } else {
                        roomPrice * nights
                    }
                }
                if (expectedTotal != null) {
                    val remaining = (expectedTotal - totalPaid).coerceAtLeast(0.0)
                    sq.execSQL(
                        "UPDATE bookings SET total_due_cached = ?, total_paid_cached = ?, " +
                            "remaining_balance_cached = ? WHERE id = ? AND (" +
                            "ABS(total_due_cached - ?) > 0.01 OR ABS(total_paid_cached - ?) > 0.01 " +
                            "OR ABS(remaining_balance_cached - ?) > 0.01)",
                        arrayOf(expectedTotal, totalPaid, remaining, b.id, expectedTotal, totalPaid, remaining)
                    )
                    paymentsChecked++
                }
            }

            // ── تحديث حالات الغرف من الحجوزات النشطة (نظير _updateRoomStatusesFromBookings) ──
            val todayIso = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(nowMillis))
            val activeCondition = "SELECT room_number FROM bookings WHERE deleted_at IS NULL " +
                "AND actual_checkout IS NULL AND checkin_date <= ? " +
                "AND (checkout_date IS NULL OR checkout_date > ?) " +
                "AND status IN ('محجوزة','محجوز','نشط','active','confirmed','قيد الحجز','in_progress','مؤقت','provisional')"
            val updated = updateCount(
                "UPDATE rooms SET status = 'محجوزة' WHERE status NOT IN ('صيانة','maintenance','under_maintenance','under maintenance') " +
                    "AND room_number IN (" + activeCondition + ")",
                listOf(todayIso, todayIso)
            )
            val freed = updateCount(
                "UPDATE rooms SET status = 'شاغرة' WHERE status NOT IN ('صيانة','maintenance','under_maintenance','under maintenance') " +
                    "AND room_number NOT IN (" + activeCondition + ")",
                listOf(todayIso, todayIso)
            )
            roomsUpdated = updated + freed

            val duration = System.currentTimeMillis() - startTime
            insertAutoFixRun(fixId, startTime, duration, success = true,
                fixes = bookingsFixed + roomsUpdated, error = null)
            return RestoreFixReport(
                success = true,
                bookingsFixed = bookingsFixed,
                roomsUpdated = roomsUpdated,
                paymentsRecalculated = paymentsChecked
            )
        } catch (e: Exception) {
            val duration = System.currentTimeMillis() - startTime
            insertAutoFixRun(fixId, startTime, duration, success = false,
                fixes = bookingsFixed + roomsUpdated, error = e.toString())
            return RestoreFixReport(
                success = false,
                bookingsFixed = bookingsFixed,
                roomsUpdated = roomsUpdated,
                paymentsRecalculated = paymentsChecked,
                error = e.toString()
            )
        }
    }

    /** تسجيل تشغيل الإصلاح في auto_fix_runs (نظير سجل Dart). */
    private suspend fun insertAutoFixRun(
        fixId: String,
        startedAt: Long,
        durationMs: Long,
        success: Boolean,
        fixes: Int,
        error: String?
    ) {
        val iso = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US)
        db.autoFixRunsDao().insert(
            AutoFixRunEntity(
                runUuid = fixId,
                source = "after_restore",
                status = if (success) "completed" else "failed",
                startedAtEpoch = startedAt,
                startedAtIso = iso.format(Date(startedAt)),
                completedAtEpoch = startedAt + durationMs,
                completedAtIso = iso.format(Date(startedAt + durationMs)),
                fixesApplied = fixes.toLong(),
                errorMessage = error
            )
        )
    }

    /** نظير StatusUtils.isActiveBooking — الحجوزات غير المنتهية/الملغاة. */
    private fun isActiveBooking(status: String): Boolean =
        com.marina.marina.domain.util.StatusUtils.isBookingActive(status)

    private fun queryNightsTotal(bookingId: Long): Double? {
        db.openHelper.writableDatabase.query(
            "SELECT COALESCE(SUM(nightly_rate), 0) FROM booking_nights " +
                "WHERE deleted_at IS NULL AND booking_local_id = ?",
            arrayOf(bookingId)
        ).use { c ->
            if (c.moveToFirst()) {
                val v = c.getDouble(0)
                return if (v > 0) v else null
            }
        }
        return null
    }

    private fun queryRoomPrice(roomNumber: String): Double? {
        db.openHelper.writableDatabase.query(
            "SELECT price FROM rooms WHERE room_number = ? LIMIT 1",
            arrayOf(roomNumber)
        ).use { c -> if (c.moveToFirst()) return c.getDouble(0) }
        return null
    }

    private suspend fun logChange(
        logDao: com.marina.marina.data.local.dao.RestoreFixLogDao,
        fixId: String,
        executedAt: Long,
        table: String,
        recordId: Long,
        field: String,
        oldValue: String,
        newValue: String,
        reason: String,
        fixType: String
    ) {
        logDao.insert(
            com.marina.marina.data.local.entity.RestoreFixLogEntity(
                fixId = fixId,
                executedAt = executedAt,
                targetTable = table,
                targetRecordId = recordId,
                fieldName = field,
                oldValue = oldValue,
                newValue = newValue,
                reason = reason,
                fixType = fixType
            )
        )
    }

    /** عدّ الصفوف المتأثرة بعبارة UPDATE عبر executeUpdateDelete. */
    private fun updateCount(
        sql: String,
        args: List<Any?>
    ): Int {
        val sq = db.openHelper.writableDatabase
        val stmt = sq.compileStatement(sql)
        try {
            args.forEachIndexed { i, v ->
                when (v) {
                    null -> stmt.bindNull(i + 1)
                    is Long -> stmt.bindLong(i + 1, v)
                    is Int -> stmt.bindLong(i + 1, v.toLong())
                    is Double -> stmt.bindDouble(i + 1, v)
                    is Boolean -> stmt.bindLong(i + 1, if (v) 1L else 0L)
                    else -> stmt.bindString(i + 1, v.toString())
                }
            }
            return stmt.executeUpdateDelete()
        } finally {
            stmt.close()
        }
    }
}
