package com.marina.marina.presentation.bookings

import android.Manifest
import android.content.pm.PackageManager
import android.provider.ContactsContract
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.CloudDone
import androidx.compose.material.icons.filled.Contacts
import androidx.compose.material.icons.filled.EventAvailable
import androidx.compose.material.icons.filled.EventBusy
import androidx.compose.material.icons.filled.Gavel
import androidx.compose.material.icons.filled.LockClock
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.outlined.CloudUpload
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Snackbar
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.model.BlacklistEntry
import com.marina.marina.domain.model.Room
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlinx.coroutines.launch

/**
 * أنواع الهوية وطرق الدفع — القوائم الافتراضية في Dart
 * (custom_list_providers.dart: kDefaultIdTypes / kDefaultPaymentMethods).
 * ملاحظة: جدول custom_list_items الديناميكي غير موجود محلياً (فجوة بيانات)
 * فتُستخدم القيم الافتراضية نفسها.
 */
private val ID_TYPES = listOf(
    "بطاقة شخصية", "جواز سفر", "رخصة قيادة", "بطاقة عسكرية", "استبيان", "شهادة ميلاد"
)

private val PAYMENT_METHODS = listOf("نقدي", "تحويل بنكي")

/** Dart l.99 — خيارات حالة الحجز. */
private val STATUS_OPTIONS = listOf("محجوزة", "مؤقت", "شاغرة", "مكتمل", "ملغي")

// ألوان Flutter المستخدمة في الشاشة.
private val FLUTTER_GREEN = Color(0xFF4CAF50)
private val FLUTTER_BLUE = Color(0xFF2196F3)
private val FLUTTER_ORANGE = Color(0xFFFF9800)
private val FLUTTER_GREEN_50 = Color(0xFFE8F5E9)
private val FLUTTER_GREY_50 = Color(0xFFFAFAFA)
private val FLUTTER_RED_900 = Color(0xFFB71C1C)
private val FLUTTER_YELLOW = Color(0xFFFFEB3B)

/**
 * شاشة «إضافة/تعديل حجز» — نقل 1:1 لـ booking_edit.dart
 * (فرع feat/cloudflare-sync-execution):
 *
 *  • AppBar: العنوان + مؤشر حالة المزامنة (دوّار أزرق/سحابة رفع برتقالية/
 *    سحابة خضراء — Dart _buildSyncIndicator).
 *  • أربعة أقسام: بيانات النزيل · تفاصيل الحجز (منتقي الغرفة الشاغرة +
 *    منتقيا التاريخ/الوقت + عدد الليالي المحسوب آلياً) · الدفع المقدم
 *    (اختياري) · ملاحظات الحجز — بنفس النصوص والرسائل حرفياً.
 *  • زر الهاتف يفتح جهات الاتصال ويطبّع الرقم لنظام 967 (WhatsApp).
 *  • الحفظ عبر [BookingEditViewModel.save] — نفس عقد Dart (القائمة السوداء
 *    تحذير غير معطِّل، الدفعة المقدمة كـ deposit، مغادرة فعلية عند «مكتمل»).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BookingEditScreen(
    onBack: () -> Unit = {},
    onSaved: () -> Unit = {},
    viewModel: BookingEditViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.saved) {
        if (state.saved) onSaved()
    }

    // ─── السناك-بار ─────────────────────────────────────────────────────
    var blacklistEntry by remember { mutableStateOf<BlacklistEntry?>(null) }
    LaunchedEffect(state.snackbar) {
        val event = state.snackbar ?: return@LaunchedEffect
        blacklistEntry = event.blacklistEntry
        val result = snackbarHostState.showSnackbar(
            message = event.text,
            actionLabel = if (event.blacklistEntry != null) "متابعة الحجز" else null,
            duration = if (event.blacklistEntry != null) SnackbarDuration.Long else SnackbarDuration.Short,
            withDismissAction = true
        )
        if (result == SnackbarResult.ActionPerformed || result == SnackbarResult.Dismissed) {
            blacklistEntry = null
            viewModel.consumeSnackbar()
        }
    }

    // ─── حقول النموذج ───────────────────────────────────────────────────
    val booking = state.booking
    val formKey = booking?.id ?: -1L
    var saveAttempted by remember { mutableStateOf(false) }

    var guestName by remember(formKey) { mutableStateOf(booking?.guestName ?: "") }
    var guestPhone by remember(formKey) { mutableStateOf(booking?.guestPhone ?: "") }
    var idType by remember(formKey) {
        mutableStateOf(booking?.guestIdType?.ifEmpty { ID_TYPES.first() } ?: ID_TYPES.first())
    }
    var idNumber by remember(formKey) { mutableStateOf(booking?.guestIdNumber ?: "") }
    var idIssueDate by remember(formKey) { mutableStateOf(booking?.guestIdIssueDate ?: "") }
    var idIssuePlace by remember(formKey) { mutableStateOf(booking?.guestIdIssuePlace ?: "") }
    var nationality by remember(formKey) {
        mutableStateOf(booking?.guestNationality?.ifEmpty { "يمني" } ?: "يمني")
    }
    var guestAddress by remember(formKey) { mutableStateOf(booking?.guestAddress ?: "") }
    var roomNumber by remember(formKey) {
        mutableStateOf(booking?.roomNumber ?: state.preselectedRoom)
    }
    var checkinDate by remember(formKey) {
        mutableStateOf(booking?.checkinDate ?: formatNowIso())
    }
    var checkoutDate by remember(formKey) { mutableStateOf(booking?.checkoutDate ?: "") }
    var status by remember(formKey) { mutableStateOf(booking?.status ?: state.defaultStatus) }
    var notes by remember(formKey) { mutableStateOf(booking?.notes ?: "") }
    var hasAdvancePayment by remember(formKey) { mutableStateOf(false) }
    var advanceAmount by remember(formKey) { mutableStateOf("") }
    var advanceMethod by remember(formKey) { mutableStateOf(PAYMENT_METHODS.first()) }
    var advanceNotes by remember(formKey) { mutableStateOf("") }

    // Dart l.1108-1117 — اختيار أول غرفة شاغرة تلقائياً للحجز الجديد.
    var roomInitialized by remember(formKey) {
        mutableStateOf(booking != null || state.preselectedRoom.isNotEmpty())
    }
    LaunchedEffect(state.availableRooms, formKey, roomInitialized) {
        if (!roomInitialized && booking == null && state.availableRooms.isNotEmpty()) {
            roomNumber = state.availableRooms.first().roomNumber
            roomInitialized = true
        }
    }

    fun currentForm() = BookingEditForm(
        guestName = guestName, guestPhone = guestPhone,
        guestIdType = idType, guestIdNumber = idNumber,
        guestIdIssueDate = idIssueDate, guestIdIssuePlace = idIssuePlace,
        guestNationality = nationality, guestAddress = guestAddress,
        roomNumber = roomNumber, checkinDate = checkinDate, checkoutDate = checkoutDate,
        status = status, notes = notes,
        hasAdvancePayment = hasAdvancePayment, advanceAmount = advanceAmount,
        advanceMethod = advanceMethod, advanceNotes = advanceNotes
    )

    // ─── منتقي جهات الاتصال (Dart _pickContact l.157-196) ───────────────
    var pendingContactPick by remember { mutableStateOf(false) }
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            pendingContactPick = true
        } else {
            scope.launch {
                snackbarHostState.showSnackbar("يرجى منح صلاحية الوصول لجهات الاتصال")
            }
        }
    }
    val pickContactLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.PickContact()
    ) { uri ->
        if (uri != null) {
            var displayName: String? = null
            var contactId: String? = null
            context.contentResolver.query(
                uri,
                arrayOf(ContactsContract.Contacts._ID, ContactsContract.Contacts.DISPLAY_NAME),
                null, null, null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    contactId = cursor.getString(0)
                    displayName = cursor.getString(1)
                }
            }
            var rawPhone: String? = null
            contactId?.let { id ->
                context.contentResolver.query(
                    ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                    arrayOf(ContactsContract.CommonDataKinds.Phone.NUMBER),
                    "${ContactsContract.CommonDataKinds.Phone.CONTACT_ID} = ?",
                    arrayOf(id), null
                )?.use { cursor ->
                    if (cursor.moveToFirst()) rawPhone = cursor.getString(0)
                }
            }
            if (!rawPhone.isNullOrEmpty()) {
                guestPhone = normalizePhoneForWhatsApp(rawPhone!!)
                if (guestName.isEmpty()) guestName = displayName ?: ""
            }
        }
    }
    LaunchedEffect(pendingContactPick) {
        if (pendingContactPick) {
            pendingContactPick = false
            pickContactLauncher.launch(null)
        }
    }

    // ─── منتقيا التاريخ والوقت (Dart _pickDate l.933-979) ────────────────
    // الهدف: "idIssueDate" (تاريخ فقط) أو "checkin" / "checkout" (تاريخ + وقت).
    var pickerTarget by remember { mutableStateOf<String?>(null) }
    var datePickedMillis by remember { mutableStateOf<Long?>(null) }

    Scaffold(
        containerColor = AppColors.BackgroundColor,
        snackbarHost = {
            SnackbarHost(snackbarHostState) { data ->
                val entry = blacklistEntry
                if (entry != null) {
                    // سناك-بار القائمة السوداء — Dart l.630-710 (خلفية red900،
                    // أبيض/أبيض شفاف، وزر «متابعة الحجز» أصفر).
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(FLUTTER_RED_900, RoundedCornerShape(8.dp))
                            .padding(16.dp)
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                Icons.Filled.Gavel,
                                contentDescription = null,
                                tint = Color.White,
                                modifier = Modifier.size(22.dp)
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(
                                "تحذير أمني — اسم في القائمة السوداء",
                                color = Color.White,
                                fontWeight = FontWeight.Bold,
                                fontSize = 15.sp
                            )
                        }
                        Spacer(Modifier.height(6.dp))
                        Text(
                            entry.name,
                            color = Color.White,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.W600
                        )
                        if (!entry.nationality.isNullOrEmpty()) {
                            Text(
                                "الجنسية: ${entry.nationality}",
                                color = Color(0xB3FFFFFF),
                                fontSize = 13.sp
                            )
                        }
                        if (!entry.nationalId.isNullOrEmpty()) {
                            Text(
                                "الهوية: ${entry.nationalId}",
                                color = Color(0xB3FFFFFF),
                                fontSize = 13.sp
                            )
                        }
                        if (!entry.phone.isNullOrEmpty()) {
                            Text(
                                "الهاتف: ${entry.phone}",
                                color = Color(0xB3FFFFFF),
                                fontSize = 13.sp
                            )
                        }
                        if (!entry.reason.isNullOrEmpty()) {
                            Text(
                                "السبب: ${entry.reason}",
                                color = Color(0xB3FFFFFF),
                                fontSize = 13.sp
                            )
                        }
                        TextButton(onClick = { data.performAction() }) {
                            Text("متابعة الحجز", color = FLUTTER_YELLOW)
                        }
                    }
                } else {
                    Snackbar(data)
                }
            }
        },
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        if (state.isEdit) "تعديل حجز" else "إضافة حجز",
                        style = AppTypography.titleLarge
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "رجوع")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = AppColors.SurfaceColor,
                    titleContentColor = AppColors.TextPrimary
                ),
                actions = {
                    // Dart _buildSyncIndicator (l.875-931):
                    // syncing → دوّار أزرق، queued/pending → سحابة رفع برتقالية،
                    // synced → سحابة خضراء (الحالة الافتراضية هنا).
                    Box(Modifier.padding(8.dp)) {
                        when {
                            state.isSyncing -> CircularProgressIndicator(
                                modifier = Modifier.size(20.dp),
                                strokeWidth = 2.dp,
                                color = FLUTTER_BLUE
                            )
                            state.pendingSyncCount > 0 -> Icon(
                                Icons.Outlined.CloudUpload,
                                contentDescription = "تغييرات غير مزامنة",
                                tint = FLUTTER_ORANGE,
                                modifier = Modifier.size(20.dp)
                            )
                            else -> Icon(
                                Icons.Filled.CloudDone,
                                contentDescription = "مُتزامن",
                                tint = FLUTTER_GREEN,
                                modifier = Modifier.size(20.dp)
                            )
                        }
                    }
                }
            )
        }
    ) { padding ->
        when {
            state.isLoading -> Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentAlignment = Alignment.Center
            ) { CircularProgressIndicator() }

            else -> Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(8.dp)
                    .verticalScroll(rememberScrollState())
            ) {
                // ─── بيانات النزيل ──────────────────────────────────────
                SectionTitle("بيانات النزيل")
                Card(
                    colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
                    shape = RoundedCornerShape(12.dp)
                ) {
                    Column(Modifier.padding(8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        OutlinedTextField(
                            value = guestName,
                            onValueChange = { guestName = it },
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text("اسم النزيل *") },
                            isError = saveAttempted && guestName.trim().isEmpty(),
                            supportingText = {
                                if (saveAttempted && guestName.trim().isEmpty()) Text("مطلوب")
                            },
                            singleLine = true
                        )
                        OutlinedTextField(
                            value = guestPhone,
                            onValueChange = { guestPhone = it.filter { ch -> ch in '0'..'9' } },
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text("رقم الهاتف") },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                            singleLine = true,
                            suffix = {
                                IconButton(
                                    onClick = {
                                        val granted = ContextCompat.checkSelfPermission(
                                            context, Manifest.permission.READ_CONTACTS
                                        ) == PackageManager.PERMISSION_GRANTED
                                        if (granted) pendingContactPick = true
                                        else permissionLauncher.launch(Manifest.permission.READ_CONTACTS)
                                    }
                                ) {
                                    Icon(
                                        Icons.Filled.Contacts,
                                        contentDescription = "اختيار من جهات الاتصال"
                                    )
                                }
                            }
                        )
                        DropdownField(
                            label = "نوع الهوية",
                            value = idType,
                            options = ID_TYPES,
                            onSelect = { idType = it }
                        )
                        OutlinedTextField(
                            value = idNumber,
                            onValueChange = { idNumber = it.filter { ch -> ch in '0'..'9' } },
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text("رقم الهوية *") },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                            isError = saveAttempted && idNumber.trim().isEmpty(),
                            supportingText = {
                                if (saveAttempted && idNumber.trim().isEmpty()) Text("مطلوب")
                            },
                            singleLine = true
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            ReadOnlyPickField(
                                value = idIssueDate,
                                label = "تاريخ إصدار الهوية",
                                textStyle = AppTypography.bodyMedium.copy(
                                    fontSize = 12.sp, fontWeight = FontWeight.Bold
                                ),
                                modifier = Modifier.weight(1f),
                                suffix = {
                                    Icon(Icons.Filled.CalendarToday, contentDescription = null)
                                },
                                onClick = { pickerTarget = "idIssueDate" }
                            )
                            OutlinedTextField(
                                value = idIssuePlace,
                                onValueChange = { idIssuePlace = it },
                                textStyle = AppTypography.bodyMedium.copy(
                                    fontSize = 12.sp, fontWeight = FontWeight.Bold
                                ),
                                modifier = Modifier.weight(1f),
                                label = { Text("جهة الإصدار") },
                                singleLine = true
                            )
                        }
                        OutlinedTextField(
                            value = nationality,
                            onValueChange = { nationality = it },
                            modifier = Modifier.fillMaxWidth(),
                            textStyle = AppTypography.bodyMedium.copy(
                                fontSize = 14.sp, fontWeight = FontWeight.Normal
                            ),
                            label = { Text("الجنسية *") },
                            isError = saveAttempted && nationality.trim().isEmpty(),
                            supportingText = {
                                if (saveAttempted && nationality.trim().isEmpty()) Text("مطلوب")
                            },
                            singleLine = true
                        )
                        OutlinedTextField(
                            value = guestAddress,
                            onValueChange = { guestAddress = it },
                            modifier = Modifier.fillMaxWidth(),
                            textStyle = AppTypography.bodyMedium.copy(
                                fontSize = 12.sp, fontWeight = FontWeight.Bold
                            ),
                            label = { Text("العنوان") },
                            singleLine = true
                        )
                    }
                }
                Spacer(Modifier.height(10.dp))

                // ─── تفاصيل الحجز ───────────────────────────────────────
                SectionTitle("تفاصيل الحجز")
                Card(
                    colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
                    shape = RoundedCornerShape(12.dp)
                ) {
                    Column(Modifier.padding(8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        RoomSelector(
                            rooms = state.availableRooms,
                            currentValue = roomNumber.trim(),
                            isNew = booking == null,
                            onSelect = { roomNumber = it },
                            isError = saveAttempted && roomNumber.trim().isEmpty(),
                            errorMessage = "مطلوب"
                        )
                        ReadOnlyPickField(
                            value = checkinDate,
                            label = "تاريخ الوصول *",
                            textStyle = AppTypography.bodyMedium.copy(
                                fontSize = 12.sp, fontWeight = FontWeight.Bold
                            ),
                            modifier = Modifier.fillMaxWidth(),
                            supportingText = { Text("التنسيق: YYYY-MM-DD HH:MM:SS") },
                            suffix = { Icon(Icons.Filled.EventAvailable, contentDescription = null) },
                            isError = saveAttempted && checkinDate.trim().isEmpty(),
                            onClick = { pickerTarget = "checkin" }
                        )
                        ReadOnlyPickField(
                            value = checkoutDate,
                            label = "تاريخ المغادرة المخطط",
                            textStyle = AppTypography.bodyMedium.copy(
                                fontSize = 12.sp, fontWeight = FontWeight.Bold
                            ),
                            modifier = Modifier.fillMaxWidth(),
                            supportingText = { Text("التنسيق: YYYY-MM-DD HH:MM:SS") },
                            suffix = { Icon(Icons.Filled.EventBusy, contentDescription = null) },
                            onClick = { pickerTarget = "checkout" }
                        )
                        DropdownField(
                            label = "حالة الحجز",
                            value = status,
                            options = STATUS_OPTIONS,
                            onSelect = { status = it }
                        )
                        OutlinedTextField(
                            value = nightsPreview(checkinDate, checkoutDate, booking).toString(),
                            onValueChange = {},
                            readOnly = true,
                            textStyle = AppTypography.bodyMedium.copy(
                                fontSize = 12.sp, fontWeight = FontWeight.Bold
                            ),
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text("عدد الليالي") },
                            singleLine = true
                        )
                        if (booking?.actualCheckout != null) {
                            OutlinedTextField(
                                value = booking.actualCheckout!!,
                                onValueChange = {},
                                readOnly = true,
                                modifier = Modifier.fillMaxWidth(),
                                label = { Text("تاريخ المغادرة الفعلي") },
                                suffix = { Icon(Icons.Filled.LockClock, contentDescription = null) },
                                singleLine = true
                            )
                        }
                    }
                }
                Spacer(Modifier.height(10.dp))

                // ─── الدفع المقدم (اختياري) ─────────────────────────────
                SectionTitle("الدفع المقدم (اختياري)")
                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = if (hasAdvancePayment) FLUTTER_GREEN_50 else FLUTTER_GREY_50
                    ),
                    shape = RoundedCornerShape(12.dp)
                ) {
                    Column(Modifier.padding(6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Checkbox(
                                checked = hasAdvancePayment,
                                onCheckedChange = { hasAdvancePayment = it }
                            )
                            Column(Modifier.weight(1f)) {
                                Text("هل تم استلام دفعة مقدمة؟", style = AppTypography.bodyMedium)
                                Text(
                                    if (hasAdvancePayment) "سيتم تسجيل الدفعة مع الحجز مباشرة"
                                    else "يمكن تسجيل الدفعات لاحقاً من شاشة المدفوعات",
                                    style = AppTypography.bodySmall,
                                    color = AppColors.TextSecondary
                                )
                            }
                        }
                        if (hasAdvancePayment) {
                            OutlinedTextField(
                                value = advanceAmount,
                                onValueChange = { advanceAmount = it.filter { ch -> ch in '0'..'9' } },
                                modifier = Modifier.fillMaxWidth(),
                                label = { Text("مبلغ الدفعة المقدمة *") },
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                                isError = saveAttempted && advanceAmount.trim().isEmpty(),
                                supportingText = {
                                    if (saveAttempted && advanceAmount.trim().isEmpty()) {
                                        Text("مطلوب عند تحديد دفعة مقدمة")
                                    } else {
                                        Text("أدخل المبلغ المستلم من النزيل")
                                    }
                                },
                                singleLine = true
                            )
                            DropdownField(
                                label = "طريقة الدفع",
                                value = advanceMethod,
                                options = PAYMENT_METHODS,
                                onSelect = { advanceMethod = it }
                            )
                            OutlinedTextField(
                                value = advanceNotes,
                                onValueChange = { advanceNotes = it },
                                modifier = Modifier.fillMaxWidth(),
                                label = { Text("ملاحظات الدفعة") },
                                supportingText = { Text("مثال: عربون لثلاث ليالي") },
                                singleLine = true
                            )
                        }
                    }
                }
                Spacer(Modifier.height(6.dp))

                // ─── ملاحظات الحجز ──────────────────────────────────────
                SectionTitle("ملاحظات الحجز")
                Card(
                    colors = CardDefaults.cardColors(containerColor = AppColors.SurfaceColor),
                    shape = RoundedCornerShape(12.dp)
                ) {
                    OutlinedTextField(
                        value = notes,
                        onValueChange = { notes = it },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(8.dp),
                        label = { Text("ملاحظات إضافية") },
                        minLines = 1,
                        maxLines = 5
                    )
                }
                Spacer(Modifier.height(14.dp))

                // ─── زر الحفظ (FilledButton.icon في Dart) ───────────────
                Button(
                    onClick = {
                        saveAttempted = true
                        viewModel.save(currentForm())
                    },
                    enabled = !state.isSaving,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(bottom = 20.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = AppColors.PrimaryColor),
                    shape = RoundedCornerShape(12.dp)
                ) {
                    Icon(Icons.Filled.Save, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("حفظ الحجز", color = Color.White)
                }
            }
        }
    }

    // ─── حوارات التاريخ/الوقت (Dart _pickDate: تاريخ ثم وقت) ─────────────
    pickerTarget?.let { target ->
        val initialMillis = when (target) {
            "checkin" -> HotelTimeEngine.parseDate(checkinDate) ?: System.currentTimeMillis()
            "checkout" -> HotelTimeEngine.parseDate(checkoutDate) ?: System.currentTimeMillis()
            else -> HotelTimeEngine.parseDate(idIssueDate) ?: System.currentTimeMillis()
        }
        val datePicked = datePickedMillis
        if (datePicked == null) {
            val pickerState = rememberDatePickerState(initialSelectedDateMillis = initialMillis)
            DatePickerDialog(
                onDismissRequest = { pickerTarget = null },
                confirmButton = {
                    TextButton(onClick = {
                        datePickedMillis = pickerState.selectedDateMillis ?: initialMillis
                    }) { Text("موافق") }
                },
                dismissButton = {
                    TextButton(onClick = { pickerTarget = null }) { Text("إلغاء") }
                }
            ) {
                DatePicker(state = pickerState)
            }
        } else {
            val initialCal = java.util.Calendar.getInstance().apply { timeInMillis = initialMillis }
            val timeState = rememberTimePickerState(
                initialHour = initialCal.get(java.util.Calendar.HOUR_OF_DAY),
                initialMinute = initialCal.get(java.util.Calendar.MINUTE),
                is24Hour = true
            )
            AlertDialog(
                onDismissRequest = {
                    datePickedMillis = null
                    pickerTarget = null
                },
                confirmButton = {
                    TextButton(onClick = {
                        val cal = java.util.Calendar.getInstance().apply { timeInMillis = datePicked }
                        cal.set(java.util.Calendar.HOUR_OF_DAY, timeState.hour)
                        cal.set(java.util.Calendar.MINUTE, timeState.minute)
                        if (target == "idIssueDate") {
                            // Dart l.965-969 — التاريخ فقط: أول 10 أحرف.
                            idIssueDate = formatIsoSeconds(cal.timeInMillis).substring(0, 10)
                        } else {
                            val value = formatIsoSeconds(cal.timeInMillis)
                            if (target == "checkin") checkinDate = value else checkoutDate = value
                        }
                        datePickedMillis = null
                        pickerTarget = null
                    }) { Text("موافق") }
                },
                dismissButton = {
                    TextButton(onClick = { datePickedMillis = null }) { Text("إلغاء") }
                },
                title = { Text("اختر الوقت") },
                text = { TimePicker(state = timeState) }
            )
        }
    }
}

// ─── مكوّنات مساعدة ─────────────────────────────────────────────────────

/** Dart _buildSectionTitle (l.933-941) — عنوان قسم 12 bold. */
@Composable
private fun SectionTitle(text: String) {
    Text(
        text,
        fontSize = 12.sp,
        fontWeight = FontWeight.Bold,
        color = AppColors.TextPrimary,
        modifier = Modifier.padding(bottom = 4.dp)
    )
}

/**
 * حقل readOnly قابل للنقر (نظير TextFormField readOnly + onTap في Dart):
 * طبقة شفافة تلتقط النقر فوق الحقل كاملاً.
 */
@Composable
private fun ReadOnlyPickField(
    value: String,
    label: String,
    textStyle: TextStyle,
    modifier: Modifier = Modifier,
    supportingText: (@Composable () -> Unit)? = null,
    suffix: (@Composable () -> Unit)? = null,
    isError: Boolean = false,
    onClick: () -> Unit
) {
    Box(modifier) {
        OutlinedTextField(
            value = value,
            onValueChange = {},
            readOnly = true,
            textStyle = textStyle,
            modifier = Modifier.fillMaxWidth(),
            label = { Text(label) },
            supportingText = { supportingText?.invoke() },
            suffix = suffix,
            isError = isError,
            singleLine = true
        )
        Box(
            Modifier
                .matchParentSize()
                .clickable(onClick = onClick)
        )
    }
}

/**
 * منتقي الغرفة — Dart _buildRoomSelector (l.1090-1160): عنصر «(الحالي)»
 * للقيمة الحالية غير الشاغرة، ثم الغرف الشاغرة «{الرقم} • {النوع}»، وحقل
 * نصي عند عدم وجود غرف شاغرة («لا توجد غرف شاغرة متاحة حالياً»).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RoomSelector(
    rooms: List<Room>,
    currentValue: String,
    isNew: Boolean,
    onSelect: (String) -> Unit,
    isError: Boolean,
    errorMessage: String
) {
    val roomTextStyle = AppTypography.bodyMedium.copy(
        fontSize = 14.sp, fontWeight = FontWeight.Bold, color = AppColors.TextPrimary
    )
    if (rooms.isEmpty()) {
        OutlinedTextField(
            value = currentValue,
            onValueChange = {},
            readOnly = isNew,
            textStyle = roomTextStyle,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("رقم الغرفة *") },
            supportingText = { Text("لا توجد غرف شاغرة متاحة حالياً") },
            isError = isError,
            singleLine = true
        )
        return
    }
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it }
    ) {
        OutlinedTextField(
            value = currentValue,
            onValueChange = {},
            readOnly = true,
            textStyle = roomTextStyle,
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor(),
            label = { Text("رقم الغرفة *") },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            isError = isError,
            supportingText = { if (isError) Text(errorMessage) },
            singleLine = true
        )
        ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false }
        ) {
            if (currentValue.isNotEmpty() && rooms.none { it.roomNumber == currentValue }) {
                DropdownMenuItem(
                    text = { Text("$currentValue (الحالي)", style = roomTextStyle) },
                    onClick = {
                        onSelect(currentValue)
                        expanded = false
                    }
                )
            }
            rooms.forEach { room ->
                DropdownMenuItem(
                    text = { Text("${room.roomNumber} • ${room.type}", style = roomTextStyle) },
                    onClick = {
                        onSelect(room.roomNumber)
                        expanded = false
                    }
                )
            }
        }
    }
}

/** حقل منسدل عام — نظير DropdownButtonFormField في Dart. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DropdownField(label: String, value: String, options: List<String>, onSelect: (String) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it }
    ) {
        OutlinedTextField(
            value = value,
            onValueChange = {},
            readOnly = true,
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor(),
            label = { Text(label) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            singleLine = true
        )
        ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false }
        ) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(option) },
                    onClick = {
                        onSelect(option)
                        expanded = false
                    }
                )
            }
        }
    }
}

/** عدد الليالي الحي — Dart _recalculateExpectedNights (l.981-1000). */
private fun nightsPreview(checkinText: String, checkoutText: String, booking: Booking?): Int {
    val checkin = HotelTimeEngine.parseDate(checkinText.trim()) ?: return booking?.expectedNights ?: 1
    val checkout = HotelTimeEngine.parseDate(checkoutText.trim())
    return HotelTimeEngine.nightsWithCutoff(checkin, checkout)
}

/** Dart _formatDateTime (l.1172-1184) — 'yyyy-MM-dd HH:mm:ss'. */
private fun formatIsoSeconds(millis: Long): String =
    SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date(millis))

private fun formatNowIso(): String = formatIsoSeconds(System.currentTimeMillis())

/**
 * Dart _normalizePhoneForWhatsApp (l.198-213) — تطبيع رقم جهة الاتصال:
 * أرقام فقط، حذف + و00، تحويل 0XXXXXXXXX و XXXXXXXXX إلى 967XXXXXXXXX.
 */
private fun normalizePhoneForWhatsApp(value: String): String {
    var phone = value.filter { it.isDigit() || it == '+' }
    if (phone.startsWith("+")) phone = phone.substring(1)
    if (phone.startsWith("00")) phone = phone.substring(2)
    if (phone.startsWith("0") && phone.length == 10) phone = "967${phone.substring(1)}"
    if (!phone.startsWith("967") && phone.length == 9) phone = "967$phone"
    return phone
}
