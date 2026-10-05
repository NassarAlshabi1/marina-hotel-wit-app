package com.marina.marina.presentation.dashboard

import androidx.compose.foundation.background
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CloudDownload
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Hotel
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.WarningAmber
import androidx.compose.material.icons.outlined.CloudDone
import androidx.compose.material.icons.outlined.MoneyOff
import androidx.compose.material.icons.outlined.Payments
import androidx.compose.material.icons.outlined.Savings
import androidx.compose.material.icons.outlined.Groups2
import androidx.compose.material3.AlertDialog
import com.marina.marina.ui.components.MarinaElevatedButton as Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.Scaffold
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.AbsoluteAlignment
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.a.a.BuildConfig
import com.marina.marina.domain.model.Room
import com.marina.marina.domain.model.RoomWithPaymentStatus
import com.marina.marina.domain.util.StatusUtils
import com.marina.marina.ui.components.SyncProgressBanner
import com.marina.marina.ui.components.MarinaSnackbarHost
import com.marina.marina.ui.components.MarinaSnackbarType
import com.marina.marina.ui.components.MarinaSnackbarVisuals
import kotlinx.coroutines.flow.collectLatest
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

import com.marina.marina.ui.theme.AppColors
import com.marina.marina.components.SidebarMenuButton
/**
 * Dashboard — a reference-aligned Compose adaptation of the Flutter `DashboardScreen`
 * (`lib/screens/dashboard_screen.dart`):
 *
 * 1. Header: gradient hotel badge, "فندق مارينا" + "لوحة التحكم",
 *    APK version chip, live sync indicator and sync button.
 * 2. Three financial stat cards: المتبقي/عجز, مدفوعات اليوم, المصروفات
 *    (hotel-day scoped; payments card opens Finance, expenses card opens
 *    the expenses report).
 * 3. Room status board: the fixed 20-room grid (101..504) with the
 *    reserved / 22:00 warning / 23:00 overdue / vacant legend, long-press
 *    maintenance dialog and tap navigation (vacant → new booking,
 *    occupied → payment screen, maintenance → details dialog).
 * 4. "إجمالي استلاماتي خلال النوبة الحالية" session-receipts card.
 * 5. "استلامات المستخدمين الآخرين بحسب اليوم الفندقي" card
 *    (admin / manager / supervisor only, top 12 rows).
 */
@Composable
@OptIn(ExperimentalMaterial3Api::class)
fun DashboardScreen(
    onNavigate: (String) -> Unit = {},
    viewModel: DashboardViewModel = hiltViewModel()
) {
    val financialStats by viewModel.financialStats.collectAsStateWithLifecycle()
    val roomsWithStatus by viewModel.roomsWithStatus.collectAsStateWithLifecycle()
    val otherUserSummaries by viewModel.otherUserSummaries.collectAsStateWithLifecycle()
    val currentUser by viewModel.currentUser.collectAsStateWithLifecycle()
    val activeBookingByRoom by viewModel.activeBookingByRoom.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }

    // Snackbar events — Arabic messages identical to the Flutter originals,
    // rendered through the typed Marina snackbar system (color-coded + icon).
    LaunchedEffect(Unit) {
        viewModel.events.collectLatest { event ->
            when (event) {
                is DashboardEvent.AutoPullSucceeded ->
                    snackbarHostState.showSnackbar(
                        MarinaSnackbarVisuals(
                            message = "تم سحب ${event.pulledCount} سجل جديد من Cloudflare تلقائياً",
                            type = MarinaSnackbarType.SUCCESS,
                            icon = Icons.Filled.CloudDownload,
                            requestedDuration = SnackbarDuration.Short
                        )
                    )
                is DashboardEvent.SyncCompleted ->
                    snackbarHostState.showSnackbar(
                        MarinaSnackbarVisuals(
                            message = "تمت المزامنة: دُفع ${event.pushedCount}، سُحب ${event.pulledCount}",
                            type = MarinaSnackbarType.SUCCESS,
                            requestedDuration = SnackbarDuration.Short
                        )
                    )
                is DashboardEvent.SyncFailed ->
                    snackbarHostState.showSnackbar(
                        MarinaSnackbarVisuals(
                            message = event.message,
                            type = MarinaSnackbarType.ERROR,
                            requestedDuration = SnackbarDuration.Long
                        )
                    )
                is DashboardEvent.RoomStatusUpdated ->
                    snackbarHostState.showSnackbar(
                        MarinaSnackbarVisuals(
                            message = "تم تحديث حالة الغرفة ${event.roomNumber} إلى ${event.newStatus}",
                            type = MarinaSnackbarType.INFO,
                            requestedDuration = SnackbarDuration.Short
                        )
                    )
                is DashboardEvent.Error ->
                    snackbarHostState.showSnackbar(
                        MarinaSnackbarVisuals(
                            message = event.message,
                            type = MarinaSnackbarType.ERROR,
                            requestedDuration = SnackbarDuration.Long
                        )
                    )
            }
        }
    }

    // ─── Dialog state ────────────────────────────────────────────────────────
    var roomOptionsDialog by remember { mutableStateOf<Room?>(null) }
    var roomDetailsDialog by remember { mutableStateOf<Room?>(null) }

    Scaffold(
        containerColor = DashboardColors.Background,
        snackbarHost = {
            Column {
                MarinaSnackbarHost(snackbarHostState)
                SyncProgressBanner(viewModel.syncState)
            }
        }
    ) { insets ->
        Column(modifier = Modifier.fillMaxSize().padding(insets)) {
            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp)
            ) {
                DashboardLiveHeader(viewModel)

                // المسافات الدقيقة من Dart: header→stats 16 · stats→rooms 20
                // · rooms→الاستلامات 24 (بطاقة «إجمالي استلاماتي» أُزيلت
                // بالكامل في Dart مع الحفاظ على الفراغ البصري 24).
                Spacer(modifier = Modifier.height(16.dp))

                StatisticsCardsRow(
                    stats = financialStats,
                    onPaymentsClick = { onNavigate("finance") },
                    onExpensesClick = { onNavigate("reports") }
                )

                Spacer(modifier = Modifier.height(20.dp))

                RoomsSection(
                    roomsWithStatus = roomsWithStatus,
                    onRoomTap = { roomNumber, room ->
                        handleRoomTap(
                            roomNumber = roomNumber,
                            room = room,
                            activeBookingByRoom = activeBookingByRoom,
                            onUnregisteredRoom = {
                                /* SnackBar handled by dialog event stream */
                            },
                            onNewBooking = { number ->
                                onNavigate("booking_edit?bookingId=0&roomNumber=$number")
                            },
                            onOpenPayment = { bookingId ->
                                onNavigate("booking_payment/$bookingId")
                            },
                            onShowDetails = { roomDetailsDialog = it }
                        )
                    },
                    onRoomLongPress = { roomOptionsDialog = it }
                )

                // ✅ (2026-09-24) بطاقة «إجمالي استلاماتي خلال النوبة الحالية»
                // أُزيلت في Dart (dashboard_screen.dart l.24-28) مع الحفاظ على
                // نفس الفراغ البصري المرئي 24dp قبل استلامات المستخدمين الآخرين.
                Spacer(modifier = Modifier.height(24.dp))

                if (currentUser?.let { it.isAdmin || it.userType == "manager" || it.userType == "supervisor" } == true) {
                    OtherUsersReceiptsCard(summaries = otherUserSummaries)
                }
            }
        }
    }

    roomOptionsDialog?.let { room ->
        RoomOptionsDialog(
            room = room,
            onDismiss = { roomOptionsDialog = null },
            onMaintenance = {
                roomOptionsDialog = null
                viewModel.setRoomUnderMaintenance(room) { }
            }
        )
    }

    roomDetailsDialog?.let { room ->
        RoomDetailsDialog(
            room = room,
            onDismiss = { roomDetailsDialog = null },
            onNewBooking = {
                roomDetailsDialog = null
                onNavigate("booking_edit?bookingId=0&roomNumber=${room.roomNumber}")
            }
        )
    }
}

// -----------------------------------------------------------------------------
// Header
// -----------------------------------------------------------------------------

/** Sync progress invalidates only this small header, not the rooms/receipts. */
@Composable
private fun DashboardLiveHeader(viewModel: DashboardViewModel) {
    val syncState by viewModel.syncState.collectAsStateWithLifecycle()
    val pendingChanges by viewModel.pendingChanges.collectAsStateWithLifecycle()
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        DashboardHeader(syncState, pendingChanges)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            DashboardSyncAction(
                text = "سحب التغييرات (Delta)", icon = Icons.Filled.CloudDownload,
                color = Color(0xFF2196F3), enabled = !syncState.isSyncing,
                onClick = viewModel::pullDeltaChanges, modifier = Modifier.weight(1f)
            )
            DashboardSyncAction(
                text = when {
                    pendingChanges < 0 -> "جارٍ الفحص…"
                    pendingChanges == 0 -> "محدّث"
                    else -> "رفع التغييرات ($pendingChanges)"
                },
                icon = Icons.Filled.CloudUpload, color = Color(0xFF9C27B0),
                enabled = !syncState.isSyncing && pendingChanges > 0,
                onClick = viewModel::pushChanges, modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
private fun DashboardHeader(
    syncState: com.marina.marina.domain.model.SyncUiState,
    pendingChanges: Int
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        // Phone layout: hamburger that opens the side-navigation drawer
        // (renders nothing on wide screens where the sidebar is permanent).
        SidebarMenuButton()

        // Gradient hotel badge (Flutter: blue.shade600 → blue.shade400).
        Box(
            modifier = Modifier
                .size(24.dp)
                .background(
                    brush = Brush.linearGradient(
                        listOf(Color(0xFF1E88E5), Color(0xFF42A5F5))
                    ),
                    shape = RoundedCornerShape(9.dp)
                ),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Filled.Hotel,
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.size(14.dp)
            )
        }
        Spacer(modifier = Modifier.width(10.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = "فندق مارينا",
                fontSize = 9.sp,
                lineHeight = 12.sp,
                fontWeight = FontWeight.Bold,
                color = DashboardColors.TextPrimary
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = "لوحة التحكم",
                    fontSize = 10.sp,
                    lineHeight = 14.sp,
                    color = DashboardColors.TextSecondary
                )
                Spacer(modifier = Modifier.width(6.dp))
                // APK version chip (Flutter: package_info_plus "version+build").
                VersionChip(version = DashboardVersion.label)
            }
        }

        // Live sync indicator: animated while syncing, cloud-done otherwise,
        // with the pending-changes count as a badge.
        SyncIndicatorIcon(
            isSyncing = syncState.isSyncing,
            isError = syncState.isError,
            pendingChanges = pendingChanges
        )

    }
}

@Composable
private fun DashboardSyncAction(
    text: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    color: Color,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier
) {
    val fill = if (enabled) color else Color(0xFF757575)
    Row(
        modifier = modifier.heightIn(min = 48.dp).clip(RoundedCornerShape(10.dp))
            .background(Brush.linearGradient(listOf(fill.copy(alpha = 0.85f), fill)))
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(14.dp))
        Spacer(Modifier.width(6.dp))
        Text(text, color = Color.White, fontSize = 11.sp, lineHeight = 16.sp,
            fontWeight = FontWeight.Bold, maxLines = 2)
    }
}

@Composable
private fun VersionChip(version: String) {
    Text(
        text = "v$version",
        fontSize = 9.sp,
        lineHeight = 12.sp,
        fontWeight = FontWeight.W600,
        fontFamily = FontFamily.Monospace,
        color = DashboardColors.PrimaryBlueDark,
        modifier = Modifier
            .background(
                color = DashboardColors.PrimaryBlueLight,
                shape = RoundedCornerShape(6.dp)
            )
            .border(
                width = 0.5.dp,
                color = DashboardColors.PrimaryBlueBorder,
                shape = RoundedCornerShape(6.dp)
            )
            .padding(horizontal = 6.dp, vertical = 1.dp)
    )
}

@Composable
private fun SyncIndicatorIcon(
    isSyncing: Boolean,
    isError: Boolean,
    pendingChanges: Int
) {
    when {
        isSyncing -> CircularProgressIndicator(
            strokeWidth = 2.5.dp,
            modifier = Modifier.size(20.dp)
        )
        isError -> Icon(
            imageVector = Icons.Filled.CloudUpload,
            contentDescription = "فشلت المزامنة",
            tint = DashboardColors.WarningOrange,
            modifier = Modifier.size(22.dp)
        )
        pendingChanges > 0 -> Box {
            Icon(
                imageVector = Icons.Filled.CloudUpload,
                contentDescription = "$pendingChanges تغييراً معلقاً",
                tint = DashboardColors.PrimaryBlue,
                modifier = Modifier.size(22.dp)
            )
            Text(
                text = "$pendingChanges",
                fontSize = 8.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .background(AppColors.DangerActionColor, RoundedCornerShape(6.dp))
                    .padding(horizontal = 3.dp, vertical = 1.dp)
            )
        }
        else -> Icon(
            imageVector = Icons.Outlined.CloudDone,
            contentDescription = "تمت المزامنة",
            tint = DashboardColors.SuccessGreen,
            modifier = Modifier.size(22.dp)
        )
    }
}

// -----------------------------------------------------------------------------
// Financial stat cards
// -----------------------------------------------------------------------------

@Composable
private fun StatisticsCardsRow(
    stats: FinancialStats?,
    onPaymentsClick: () -> Unit,
    onExpensesClick: () -> Unit
) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        // Card 1: المتبقي / عجز = payments − expenses.
        val balance = stats?.balance
        StatCard(
            title = when {
                stats == null || balance == null -> "المتبقي"
                balance >= 0 -> "المتبقي"
                else -> "عجز"
            },
            value = when {
                stats == null || balance == null -> "…"
                else -> formatCurrency(kotlin.math.abs(balance))
            },
            icon = if (stats != null && stats.isDeficit) {
                Icons.Filled.WarningAmber
            } else {
                Icons.Outlined.Savings
            },
            color = if (stats != null && stats.isDeficit) {
                DashboardColors.WarningOrange
            } else {
                DashboardColors.Indigo
            },
            modifier = Modifier.weight(1f)
        )
        // Card 2: مدفوعات اليوم → Finance screen.
        StatCard(
            title = "مدفوعات اليوم",
            value = stats?.let { formatCurrency(it.todayPayments) } ?: "…",
            icon = Icons.Outlined.Payments,
            color = DashboardColors.SuccessGreen,
            modifier = Modifier.weight(1f),
            onClick = onPaymentsClick
        )
        // Card 3: المصروفات → expenses report screen.
        StatCard(
            title = "المصروفات",
            value = stats?.let { formatCurrency(it.todayExpenses) } ?: "…",
            icon = Icons.Outlined.MoneyOff,
            color = DashboardColors.DangerRed,
            modifier = Modifier.weight(1f),
            onClick = onExpensesClick
        )
    }
}

/** Thousands-separated integer currency — the Dart `NumberFormat('#,##0')`. */
internal fun formatCurrency(amount: Double): String = DashboardFormatters.currency(amount)

@Composable
private fun StatCard(
    title: String,
    value: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    color: Color,
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null
) {
    Box(
        modifier = modifier
            .shadow(2.dp, MaterialTheme.shapes.medium)
            .clip(MaterialTheme.shapes.medium)
            .background(MaterialTheme.colorScheme.surface)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 10.dp, vertical = 10.dp)
    ) {
        Column(horizontalAlignment = androidx.compose.ui.Alignment.Start) {
            Icon(imageVector = icon, contentDescription = null, tint = color, modifier = Modifier.size(14.dp))
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                text = value,
                fontSize = 11.sp, lineHeight = 14.sp,
                fontWeight = FontWeight.Bold,
                color = color,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(modifier = Modifier.height(1.dp))
            Text(
                text = title,
                fontSize = 9.sp, lineHeight = 12.sp,
                color = DashboardColors.TextSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

// -----------------------------------------------------------------------------
// Room status board
// -----------------------------------------------------------------------------

/** The fixed 20-room board (101..504) — identical to the Dart constant. */
private val DashboardRoomNumbers: List<String> = listOf(
    "101", "102", "103", "104",
    "201", "202", "203", "204",
    "301", "302", "303", "304",
    "401", "402", "403", "404",
    "501", "502", "503", "504"
)

@Composable
@OptIn(ExperimentalLayoutApi::class)
private fun RoomsSection(
    roomsWithStatus: List<RoomWithPaymentStatus>,
    onRoomTap: (String, Room?) -> Unit,
    onRoomLongPress: (Room) -> Unit
) {
    Surface(
        color = MaterialTheme.colorScheme.surface,
        shape = MaterialTheme.shapes.large,
        shadowElevation = 2.dp,
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    text = "حالة الغرف",
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = DashboardColors.TextPrimary
                )
                LegendItem(label = "محجوزة", color = RoomWithPaymentStatus.OccupiedColor)
                LegendSplitItem(
                    label = "تنبيه 22:00",
                    leftColor = RoomWithPaymentStatus.LatePaymentColor,
                    rightColor = RoomWithPaymentStatus.OccupiedColor
                )
                LegendItem(label = "متأخر 23:00", color = RoomWithPaymentStatus.OverdueColor)
                LegendItem(label = "شاغرة", color = RoomWithPaymentStatus.VacantColor)
            }
            Spacer(modifier = Modifier.height(16.dp))
            // 4-column fixed grid, aspect ratio 1.2 — same as the Dart layout.
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                DashboardRoomNumbers.chunked(4).forEach { rowRooms ->
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        rowRooms.forEach { roomNumber ->
                            val rws = roomsWithStatus.firstOrNull { it.room.roomNumber == roomNumber }
                            RoomTile(
                                roomNumber = roomNumber,
                                rws = rws,
                                modifier = Modifier.weight(1f),
                                onTap = { onRoomTap(roomNumber, rws?.room) },
                                onLongPress = { rws?.room?.let(onRoomLongPress) }
                            )
                        }
                        // Pad incomplete rows (grid stays visually aligned).
                        repeat(4 - rowRooms.size) {
                            Spacer(modifier = Modifier.weight(1f))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LegendItem(label: String, color: Color) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            modifier = Modifier
                .size(width = 10.dp, height = 10.dp)
                .background(color, RoundedCornerShape(3.dp))
        )
        Spacer(modifier = Modifier.width(4.dp))
        Text(text = label, fontSize = 10.sp, lineHeight = 13.sp, color = DashboardColors.TextSecondary)
    }
}

/** Dual-color legend chip for the 22:00 early-warning split state. */
@Composable
private fun LegendSplitItem(label: String, leftColor: Color, rightColor: Color) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            modifier = Modifier
                .size(width = 12.dp, height = 10.dp)
                .background(
                    brush = Brush.horizontalGradient(
                        colorStops = arrayOf(
                            0.45f to leftColor,
                            0.45f to rightColor
                        )
                    ),
                    shape = RoundedCornerShape(3.dp)
                )
        )
        Spacer(modifier = Modifier.width(4.dp))
        Text(text = label, fontSize = 10.sp, lineHeight = 13.sp, color = DashboardColors.TextSecondary)
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun RoomTile(
    roomNumber: String,
    rws: RoomWithPaymentStatus?,
    modifier: Modifier = Modifier,
    onTap: () -> Unit,
    onLongPress: () -> Unit
) {
    val isOverdue = rws?.isPaymentOverdue == true
    val isLatePayment = rws?.isLatePayment == true

    val decoration: (Modifier) -> Modifier = when {
        isOverdue -> { m ->
            m.border(width = 2.dp, color = RoomWithPaymentStatus.OverdueDark, shape = RoundedCornerShape(10.dp))
                .background(
                    brush = Brush.horizontalGradient(
                        listOf(Color(0xFFEF5350), RoomWithPaymentStatus.OccupiedColor,
                            RoomWithPaymentStatus.OverdueColor)
                    ),
                    shape = RoundedCornerShape(10.dp)
                )
        }
        isLatePayment -> { m ->
            m.border(width = 1.5.dp, color = DashboardColors.WarningOrangeDark, shape = RoundedCornerShape(10.dp))
                .background(
                    // RTL split: 55% red on the right, 45% orange on the left.
                    brush = Brush.horizontalGradient(
                        colorStops = arrayOf(
                            0f to RoomWithPaymentStatus.LatePaymentColor,
                            0.45f to RoomWithPaymentStatus.LatePaymentColor,
                            0.45f to RoomWithPaymentStatus.OccupiedColor,
                            1f to RoomWithPaymentStatus.OccupiedColor
                        )
                    ),
                    shape = RoundedCornerShape(10.dp)
                )
        }
        else -> { m -> m.background(rws?.roomColor ?: RoomWithPaymentStatus.UnregisteredColor, RoundedCornerShape(10.dp)) }
    }

    Box(
        modifier = modifier
            .aspectRatio(1.2f)
            .let(decoration)
            .clip(RoundedCornerShape(10.dp))
            .semantics {
                stateDescription = when {
                    isOverdue -> "متأخر في السداد"
                    isLatePayment -> "تنبيه مبكر للسداد"
                    else -> rws?.displayStatus ?: "غير مسجلة"
                }
            }
            .combinedClickable(onClick = onTap, onLongClick = if (rws != null) onLongPress else null),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = roomNumber,
            color = Color.White,
            fontWeight = FontWeight.Bold,
            fontSize = 14.sp
        )
        // Early-warning (22:00) corner icon.
        if (isLatePayment && !isOverdue) {
            Icon(
                imageVector = Icons.Filled.WarningAmber,
                contentDescription = null,
                tint = Color.White.copy(alpha = 0.9f),
                modifier = Modifier
                    .align(AbsoluteAlignment.TopLeft)
                    .padding(2.dp)
                    .size(10.dp)
            )
        }
        // Actual-overdue (23:00+) corner icon.
        if (isOverdue) {
            Icon(
                imageVector = Icons.Filled.ErrorOutline,
                contentDescription = null,
                tint = Color.White.copy(alpha = 0.95f),
                modifier = Modifier
                    .align(AbsoluteAlignment.TopLeft)
                    .padding(2.dp)
                    .size(11.dp)
            )
        }
    }
}

// -----------------------------------------------------------------------------
// Receipts cards
// -----------------------------------------------------------------------------

@Composable
private fun OtherUsersReceiptsCard(
    summaries: List<com.marina.marina.domain.model.PaymentUserHotelDaySummary>
) {
    Surface(
        color = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(12.dp),
        border = androidx.compose.foundation.BorderStroke(1.dp, Color(0xFFBBDEFB)),
        shadowElevation = 2.dp,
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Outlined.Groups2,
                    contentDescription = null,
                    tint = DashboardColors.PrimaryBlueDark,
                    modifier = Modifier.size(19.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "استلامات المستخدمين",
                    fontSize = 9.sp, lineHeight = 12.sp,
                    fontWeight = FontWeight.Bold,
                    color = DashboardColors.TextPrimary,
                    modifier = Modifier.weight(1f)
                )
                Text(
                    text = "إجمالي اليوم الفندقي الحالي مهما كان عدد الجلسات",
                    fontSize = 9.sp, lineHeight = 12.sp,
                    color = DashboardColors.TextSecondary
                )
            }
            Spacer(modifier = Modifier.height(8.dp))
            when {
                summaries.isEmpty() -> Text(
                    text = "لا توجد استلامات في اليوم الفندقي الحالي بعد",
                    fontSize = 11.sp, lineHeight = 14.sp,
                    color = DashboardColors.TextSecondary
                )
                else -> summaries.take(12).forEach { summary ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.padding(bottom = 6.dp)
                    ) {
                        Text(
                            text = summary.userName,
                            fontSize = 11.sp, lineHeight = 14.sp,
                            fontWeight = FontWeight.W600,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f)
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = "${summary.paymentCount} دفعة",
                            fontSize = 9.sp, lineHeight = 12.sp,
                            color = DashboardColors.TextSecondary
                        )
                        Spacer(modifier = Modifier.width(10.dp))
                        Text(
                            text = formatCurrency(summary.totalAmount),
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold,
                            color = DashboardColors.PrimaryBlueDark
                        )
                    }
                }
            }
        }
    }
}

// -----------------------------------------------------------------------------
// Dialogs
// -----------------------------------------------------------------------------

@Composable
private fun RoomOptionsDialog(
    room: Room,
    onDismiss: () -> Unit,
    onMaintenance: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {},
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء") }
        },
        title = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Filled.Settings,
                    contentDescription = null,
                    tint = DashboardColors.PrimaryBlue,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(text = "غرفة ${room.roomNumber}", fontWeight = FontWeight.Bold)
            }
        },
        text = {
            Column {
                Text(text = "الحالة الحالية: ${room.status}")
                Spacer(modifier = Modifier.height(16.dp))
                if (room.status != "صيانة") {
                    Button(
                        onClick = onMaintenance,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = AppColors.WarningActionColor,
                            contentColor = Color.White
                        ),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "تحويل إلى صيانة", color = Color.White)
                    }
                }
            }
        }
    )
}

@Composable
private fun RoomDetailsDialog(
    room: Room,
    onDismiss: () -> Unit,
    onNewBooking: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            if (!StatusUtils.isRoomOccupied(room.status)) {
                Button(onClick = onNewBooking) { Text("حجز جديد") }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إغلاق") }
        },
        title = { Text(text = "غرفة ${room.roomNumber}", fontWeight = FontWeight.Bold) },
        text = {
            Column {
                DetailRow("الحالة", room.status)
                DetailRow("النوع", room.type)
                DetailRow("السعر", "${room.price.toInt()} ريال")
            }
        }
    )
}

@Composable
private fun DetailRow(label: String, value: String) {
    Row(
        modifier = Modifier.padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Text(text = "$label: ", fontWeight = FontWeight.Bold)
        Text(text = value)
    }
}

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

/** Room tap routing — identical semantics to the Dart `_handleRoomTap`. */
private fun handleRoomTap(
    roomNumber: String,
    room: Room?,
    activeBookingByRoom: Map<String, com.marina.marina.domain.model.Booking>,
    onUnregisteredRoom: (String) -> Unit,
    onNewBooking: (String) -> Unit,
    onOpenPayment: (Long) -> Unit,
    onShowDetails: (Room) -> Unit
) {
    if (room == null) {
        onUnregisteredRoom(roomNumber)
        return
    }
    when {
        StatusUtils.isRoomAvailable(room.status) -> onNewBooking(roomNumber)
        StatusUtils.isRoomOccupied(room.status) -> {
            val activeBooking = activeBookingByRoom[roomNumber]
            if (activeBooking != null) {
                onOpenPayment(activeBooking.id)
            }
            // No active booking → nothing to open (parity with the Dart
            // "لا يوجد حجز محجوز للغرفة" snackbar path).
        }
        else -> onShowDetails(room)
    }
}

/** "HH:mm" — the Dart `DateFormat('HH:mm')`. */
internal fun formatHourMinute(epochMillis: Long): String = DashboardFormatters.hourMinute(epochMillis)

/** Dashboard aliases follow the active Material color scheme. */
internal object DashboardColors {
    val Background: Color
        @Composable get() = if (AppColors.BackgroundColor == Color(0xFFF8F8FC)) Color(0xFFF5F5F5) else AppColors.BackgroundColor
    val TextPrimary: Color
        @Composable get() = AppColors.TextPrimary
    val TextSecondary: Color
        @Composable get() = AppColors.TextSecondary
    val Indigo = Color(0xFF3F51B5)
    val SuccessGreen = Color(0xFF43A047)
    val DangerRed = Color(0xFFE53935)
    val WarningOrange = Color(0xFFFF9800)
    val WarningOrangeDark = Color(0xFFF57C00)
    val PrimaryBlue = Color(0xFF2196F3)
    val PrimaryBlueDark = Color(0xFF1976D2)
    val PrimaryBlueLight = Color(0xFFE3F2FD)
    val PrimaryBlueBorder = Color(0xFF90CAF9)
    val InfoBlue = Color(0xFF2196F3)
}

/** App version label — BuildConfig-driven, parity with package_info_plus. */
internal object DashboardVersion {
    val label: String get() = "${BuildConfig.VERSION_NAME}+${BuildConfig.VERSION_CODE}"
}
