package com.marina.marina.presentation.reports

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.ui.theme.AppColors
import java.util.Calendar

/** The preset chips row + custom from/to pickers (Dart l.363-431). */
@Composable
fun ReportDateFilter(
    range: ReportDateRange,
    onChange: (ReportDateRange) -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current

    fun pickDate(isFrom: Boolean) {
        val cal = Calendar.getInstance().apply {
            timeInMillis = if (isFrom) range.from else range.to
        }
        android.app.DatePickerDialog(
            context,
            { _, y, m, d ->
                val picked = Calendar.getInstance().apply { set(y, m, d, 12, 0, 0) }
                if (isFrom) {
                    // From-date snaps to 14:01 (Dart _pickDate).
                    picked.set(Calendar.HOUR_OF_DAY, HotelTimeEngine.BOUNDARY_HOUR)
                    picked.set(Calendar.MINUTE, HotelTimeEngine.BOUNDARY_MINUTE)
                    picked.set(Calendar.SECOND, 0)
                    picked.set(Calendar.MILLISECOND, 0)
                    val newFrom = picked.timeInMillis
                    val newTo = if (newFrom > range.to) {
                        picked.add(Calendar.DAY_OF_YEAR, 1)
                        picked.set(Calendar.HOUR_OF_DAY, HotelTimeEngine.BOUNDARY_HOUR)
                        picked.set(Calendar.MINUTE, HotelTimeEngine.BOUNDARY_MINUTE - 1)
                        picked.set(Calendar.SECOND, 59)
                        picked.timeInMillis
                    } else range.to
                    onChange(ReportDateRange(newFrom, newTo))
                } else {
                    // To-date snaps to 14:00:59.
                    picked.set(Calendar.HOUR_OF_DAY, HotelTimeEngine.BOUNDARY_HOUR)
                    picked.set(Calendar.MINUTE, HotelTimeEngine.BOUNDARY_MINUTE - 1)
                    picked.set(Calendar.SECOND, 59)
                    picked.set(Calendar.MILLISECOND, 999)
                    val newTo = picked.timeInMillis
                    val newFrom = if (newTo < range.from) {
                        picked.add(Calendar.DAY_OF_YEAR, -1)
                        picked.set(Calendar.HOUR_OF_DAY, HotelTimeEngine.BOUNDARY_HOUR)
                        picked.set(Calendar.MINUTE, HotelTimeEngine.BOUNDARY_MINUTE)
                        picked.set(Calendar.SECOND, 0)
                        picked.set(Calendar.MILLISECOND, 0)
                        picked.timeInMillis
                    } else range.from
                    onChange(ReportDateRange(newFrom, newTo))
                }
            },
            cal.get(Calendar.YEAR), cal.get(Calendar.MONTH), cal.get(Calendar.DAY_OF_MONTH)
        ).show()
    }

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            FilterChip(
                selected = range.isCurrentHotelDay,
                onClick = { onChange(ReportDateRange.quick("hotelDay")) },
                label = { Text("اليوم الفندقي", fontSize = 11.sp) }
            )
            FilterChip(
                selected = !range.isCurrentHotelDay && range.from == ReportDateRange.quick("week").from,
                onClick = { onChange(ReportDateRange.quick("week")) },
                label = { Text("الأسبوع", fontSize = 11.sp) }
            )
            FilterChip(
                selected = !range.isCurrentHotelDay && range.from == ReportDateRange.quick("month").from,
                onClick = { onChange(ReportDateRange.quick("month")) },
                label = { Text("الشهر", fontSize = 11.sp) }
            )
            FilterChip(
                selected = !range.isCurrentHotelDay && range.from == ReportDateRange.quick("year").from,
                onClick = { onChange(ReportDateRange.quick("year")) },
                label = { Text("السنة", fontSize = 11.sp) }
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            OutlinedButton(onClick = { pickDate(isFrom = true) }, modifier = Modifier.weight(1f)) {
                Text("من (${HotelTimeEngine.formatDisplayDateOnly(range.from).replace("/", "-")}) 14:01", fontSize = 10.sp)
            }
            OutlinedButton(onClick = { pickDate(isFrom = false) }, modifier = Modifier.weight(1f)) {
                Text("إلى (${HotelTimeEngine.formatDisplayDateOnly(range.to).replace("/", "-")}) 14:00", fontSize = 10.sp)
            }
        }
        Text(range.label, fontSize = 10.sp, color = AppColors.TextSecondary)
    }
}

/** Shared search button (Dart ReportPageScaffold: 'بحث' / 'جارٍ...'). */
@Composable
fun ReportSearchButton(onClick: () -> Unit, loading: Boolean = false, label: String = "بحث") {
    Button(onClick = onClick, enabled = !loading, shape = androidx.compose.foundation.shape.RoundedCornerShape(10.dp)) {
        if (loading) {
            CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
        } else {
            Text(label, fontSize = 12.sp)
        }
    }
}
