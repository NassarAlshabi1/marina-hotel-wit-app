package com.marinahotel.kotlin.presentation.dashboard

import androidx.annotation.ColorRes
import androidx.annotation.StringRes
import com.marinahotel.kotlin.domain.model.AlertLevel
import com.marinahotel.kotlin.domain.model.RoomStatus

data class DashboardUiState(
    val alerts: List<AlertUiModel> = emptyList(),
    val rooms: List<RoomUiModel> = emptyList(),
    val isLoading: Boolean = true
)

data class AlertUiModel(
    val id: Int,
    val text: String,
    val meta: String?,
    val level: AlertLevel,
    @ColorRes val accentColorRes: Int
)

data class RoomUiModel(
    val roomNumber: String,
    val floor: Int,
    val status: RoomStatus,
    val occupantName: String?,
    val bookingId: Int?,
    @ColorRes val backgroundColorRes: Int,
    @ColorRes val strokeColorRes: Int,
    @StringRes val statusLabelRes: Int
)
