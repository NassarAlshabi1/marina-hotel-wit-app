package com.marina.marina.presentation.rooms

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.domain.model.Room
import com.marina.marina.domain.util.StatusUtils
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme

@Composable
fun RoomsListScreen(
    onNewBooking: (roomNumber: String) -> Unit = {},
    onOpenBookingPayment: (bookingId: Long) -> Unit = {},
    viewModel: RoomsViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    var showAddDialog by remember { mutableStateOf(false) }
    var editingRoom by remember { mutableStateOf<Room?>(null) }

    val snackbarHostState = remember { SnackbarHostState() }
    LaunchedEffect(state.message, state.error) {
        val msg = state.error ?: state.message
        if (msg != null) {
            snackbarHostState.showSnackbar(msg)
            viewModel.consumeMessage()
        }
    }

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            snackbarHost = { SnackbarHost(snackbarHostState) },
            topBar = {
                TopAppBar(
                    title = { Text("إدارة الغرف", style = AppTypography.titleLarge) },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = AppColors.SurfaceColor,
                        titleContentColor = AppColors.TextPrimary
                    )
                )
            },
            floatingActionButton = {
                FloatingActionButton(
                    onClick = { showAddDialog = true },
                    containerColor = AppColors.PrimaryColor,
                    contentColor = Color.White
                ) {
                    Text("+", fontSize = 24.sp, fontWeight = FontWeight.Bold)
                }
            }
        ) { padding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(horizontal = 16.dp)
            ) {
                OutlinedTextField(
                    value = state.searchQuery,
                    onValueChange = viewModel::setSearchQuery,
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("بحث برقم الغرفة أو النوع...") },
                    singleLine = true,
                    shape = RoundedCornerShape(12.dp)
                )

                Spacer(modifier = Modifier.height(12.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    RoomStatChip("الإجمالي", state.total.toString(), AppColors.PrimaryColor, Modifier.weight(1f))
                    RoomStatChip("شاغرة", state.availableCount.toString(), AppColors.SuccessColor, Modifier.weight(1f))
                    RoomStatChip("مشغولة", state.occupiedCount.toString(), AppColors.DangerColor, Modifier.weight(1f))
                    RoomStatChip("صيانة", state.maintenanceCount.toString(), AppColors.WarningColor, Modifier.weight(1f))
                }

                Spacer(modifier = Modifier.height(12.dp))

                when {
                    state.isLoading -> LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                    state.error != null -> Text(
                        "تعذر تحميل الغرف: ${state.error}",
                        style = AppTypography.bodyMedium,
                        color = AppColors.DangerColor,
                        modifier = Modifier.padding(16.dp)
                    )
                    state.filtered.isEmpty() -> Box(
                        modifier = Modifier.fillMaxSize().padding(32.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text("لا توجد غرف", style = AppTypography.bodyLarge, color = AppColors.TextSecondary)
                    }
                    else -> RoomFloorsView(
                        state = state,
                        onRoomClick = { room ->
                            // Dart rooms_dashboard l.159-273 — click routing:
                            // maintenance -> details dialog; occupied (active
                            // booking) -> payment screen (or the 'no booking'
                            // snackbar); available -> new booking prefilled.
                            when {
                                StatusUtils.isRoomUnderMaintenance(room.status) -> {
                                    editingRoom = room
                                }
                                room.roomNumber in state.activeBookingRooms -> {
                                    val booking = state.activeBookingByRoom[room.roomNumber]
                                    if (booking != null) {
                                        onOpenBookingPayment(booking.id)
                                    } else {
                                        viewModel.onRoomWithoutBooking(room)
                                    }
                                }
                                else -> onNewBooking(room.roomNumber)
                            }
                        }
                    )
                }
            }
        }
    }

    if (showAddDialog) {
        RoomDialog(
            room = null,
            onDismiss = { showAddDialog = false },
            onSave = { viewModel.saveRoom(it); showAddDialog = false }
        )
    }

    editingRoom?.let { room ->
        RoomDetailsDialog(
            room = room,
            hasActiveBooking = room.roomNumber in state.activeBookingRooms,
            onToggleStatus = { viewModel.toggleStatus(room) },
            onSaveEdit = { edited ->
                // FIX: the edited Room was previously DISCARDED here — the
                // dialog re-opened with the unchanged copy (rooms audit gap #2).
                viewModel.saveRoom(edited)
            },
            onDelete = { viewModel.deleteRoom(room); editingRoom = null }
        )
    }
}

@Composable
private fun RoomFloorsView(
    state: RoomsUiState,
    onRoomClick: (Room) -> Unit
) {
    val activeBookingRooms = state.activeBookingRooms
    LazyVerticalGrid(
        columns = GridCells.Fixed(4),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        contentPadding = PaddingValues(bottom = 88.dp)
    ) {
        state.floors.forEach { (floorKey, roomsOnFloor) ->
            item(key = "floor_$floorKey") {
                // Dart floor header chips (room_widgets l.199-273): per-floor
                // occupied / available / total counts.
                val occupied = roomsOnFloor.count { it.roomNumber in activeBookingRooms }
                val available = roomsOnFloor.count {
                    it.roomNumber !in activeBookingRooms && !StatusUtils.isRoomUnderMaintenance(it.status)
                }
                Column(modifier = Modifier.fillMaxWidth()) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text(
                            "الطابق $floorKey",
                            style = AppTypography.titleSmall,
                            color = AppColors.PrimaryColor
                        )
                        Text(
                            "محجوزة: $occupied",
                            style = AppTypography.labelSmall,
                            color = AppColors.DangerColor
                        )
                        Text(
                            "شاغرة: $available",
                            style = AppTypography.labelSmall,
                            color = AppColors.SuccessColor
                        )
                        Text(
                            "المجموع: ${roomsOnFloor.size}",
                            style = AppTypography.labelSmall,
                            color = AppColors.InfoColor
                        )
                    }
                    Spacer(modifier = Modifier.height(6.dp))
                    HorizontalDivider(color = AppColors.DividerColor)
                    Spacer(modifier = Modifier.height(8.dp))
                }
            }
            items(roomsOnFloor, key = { it.id }) { room ->
                RoomTile(room = room, hasActiveBooking = room.roomNumber in activeBookingRooms, onClick = { onRoomClick(room) })
            }
        }
    }
}

@Composable
private fun RoomTile(room: Room, hasActiveBooking: Boolean, onClick: () -> Unit) {
    // Dart room_payment_status_provider l.59-89 — priority: maintenance (orange)
    // FIRST, then active-booking occupancy (red), else available (green). A
    // stale stored 'محجوزة' with no active booking shows GREEN.
    val backgroundColor = when {
        StatusUtils.isRoomUnderMaintenance(room.status) -> AppColors.WarningColor
        hasActiveBooking -> AppColors.DangerColor
        else -> AppColors.SuccessColor
    }
    val displayStatus = when {
        StatusUtils.isRoomUnderMaintenance(room.status) -> "صيانة"
        hasActiveBooking -> "محجوزة"
        else -> "شاغرة"
    }
    Box(
        modifier = Modifier
            .aspectRatio(1f)
            .background(backgroundColor, RoundedCornerShape(10.dp))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                room.roomNumber,
                color = Color.White,
                fontWeight = FontWeight.Bold,
                fontSize = 18.sp
            )
            Text(
                displayStatus,
                color = Color.White.copy(alpha = 0.9f),
                fontSize = 10.sp
            )
            if (room.price > 0) {
                Text(
                    "${room.price.toInt()}",
                    color = Color.White.copy(alpha = 0.85f),
                    fontSize = 11.sp
                )
            }
        }
    }
}

@Composable
private fun RoomStatChip(label: String, value: String, color: Color, modifier: Modifier = Modifier) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        shape = RoundedCornerShape(10.dp)
    ) {
        Column(
            modifier = Modifier.padding(vertical = 10.dp).fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(value, style = AppTypography.titleMedium, color = color, fontWeight = FontWeight.Bold)
            Text(label, style = AppTypography.labelSmall, color = AppColors.TextSecondary, textAlign = TextAlign.Center)
        }
    }
}

@Composable
private fun RoomDetailsDialog(
    room: Room,
    hasActiveBooking: Boolean,
    onToggleStatus: () -> Unit,
    onSaveEdit: (Room) -> Unit,
    onDelete: () -> Unit
) {
    var showEdit by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }

    if (showEdit) {
        RoomDialog(
            room = room,
            onDismiss = { showEdit = false },
            onSave = { edited ->
                onSaveEdit(edited)
                showEdit = false
            }
        )
        return
    }

    AlertDialog(
        onDismissRequest = {},
        title = { Text("غرفة ${room.roomNumber}", style = AppTypography.titleLarge) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                DetailRow("النوع", room.type)
                DetailRow("السعر / الليلة", if (room.price > 0) "${room.price.toInt()} ريال" else "—")
                DetailRow("الحالة", room.status)
                if (hasActiveBooking) {
                    Text(
                        "⚠ يوجد حجز نشط على هذه الغرفة",
                        style = AppTypography.bodySmall,
                        color = AppColors.WarningColor
                    )
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onToggleStatus) {
                Text(if (StatusUtils.isRoomAvailable(room.status)) "تعيين كمحجوزة" else "تعيين كشاغرة", color = AppColors.PrimaryColor)
            }
        },
        dismissButton = {
            Row {
                TextButton(onClick = { showEdit = true }) { Text("تعديل", color = AppColors.InfoColor) }
                TextButton(onClick = { confirmDelete = true }) { Text("حذف", color = AppColors.DangerColor) }
            }
        }
    )

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("تأكيد الحذف") },
            text = { Text("هل أنت متأكد من حذف الغرفة ${room.roomNumber}؟") },
            confirmButton = {
                TextButton(onClick = { onDelete() }) { Text("حذف", color = AppColors.DangerColor) }
            },
            dismissButton = {
                TextButton(onClick = { confirmDelete = false }) { Text("إلغاء") }
            }
        )
    }
}

@Composable
private fun DetailRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(label, style = AppTypography.bodyMedium, color = AppColors.TextSecondary)
        Text(value, style = AppTypography.bodyMedium, fontWeight = FontWeight.SemiBold, color = AppColors.TextPrimary)
    }
}

@Composable
private fun RoomDialog(
    room: Room?,
    onDismiss: () -> Unit,
    onSave: (Room) -> Unit
) {
    val isEdit = room != null
    var number by remember { mutableStateOf(room?.roomNumber ?: "") }
    var type by remember { mutableStateOf(room?.type ?: "غرفة عادية") }
    var price by remember { mutableStateOf(if ((room?.price ?: 0.0) > 0) room!!.price.toInt().toString() else "") }
    var status by remember { mutableStateOf(room?.status ?: "شاغرة") }

    val roomTypes = listOf("غرفة عادية", "غرفة مزدوجة", "غرفة كبيرة", "جناح")
    val statuses = listOf("شاغرة", "محجوزة", "صيانة")

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (isEdit) "تعديل الغرفة" else "إضافة غرفة جديدة", style = AppTypography.titleLarge) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(
                    value = number,
                    onValueChange = { if (!isEdit) number = it },
                    label = { Text("رقم الغرفة") },
                    enabled = !isEdit,
                    singleLine = true
                )
                OutlinedTextField(
                    value = type,
                    onValueChange = { type = it },
                    label = { Text("النوع") },
                    singleLine = true
                )
                OutlinedTextField(
                    value = price,
                    onValueChange = { price = it.filter { ch -> ch.isDigit() } },
                    label = { Text("السعر / الليلة (ريال)") },
                    singleLine = true
                )
                Text("الحالة", style = AppTypography.labelLarge)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    statuses.forEach { s ->
                        FilterChip(
                            selected = status == s,
                            onClick = { status = s },
                            label = { Text(s) }
                        )
                    }
                }
                Text("النوع:", style = AppTypography.labelLarge)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    roomTypes.forEach { t ->
                        FilterChip(
                            selected = type == t,
                            onClick = { type = t },
                            label = { Text(t) }
                        )
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    val priceValue = price.toDoubleOrNull() ?: 0.0
                    if (number.isBlank()) return@TextButton
                    onSave(
                        (room ?: Room()).copy(
                            roomNumber = number.trim(),
                            type = type.trim(),
                            price = priceValue,
                            status = status
                        )
                    )
                }
            ) { Text("حفظ", color = AppColors.PrimaryColor) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("إلغاء") }
        }
    )
}
