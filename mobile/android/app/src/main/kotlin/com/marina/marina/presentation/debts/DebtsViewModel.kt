package com.marina.marina.presentation.debts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.google.gson.JsonArray
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.model.Debt
import com.marina.marina.domain.repository.BookingsRepository
import com.marina.marina.domain.repository.DebtsRepository
import com.marina.marina.domain.repository.SyncRepository
import com.marina.marina.domain.util.CurrencyFormatter
import com.marina.marina.domain.util.HotelTimeEngine
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

/** Kind mirrors the Dart SnackBar backgroundColor for exact parity. */
enum class DebtsMsgKind { DEFAULT, SUCCESS_GREEN, ERROR_RED, ERROR_RED900, ORANGE, BLUE }

data class DebtsUiMessage(val text: String, val kind: DebtsMsgKind = DebtsMsgKind.DEFAULT)

/** One-shot WhatsApp share request (Android equivalent of whatsappService.sendMessage). */
data class DebtsWhatsAppShare(val phoneE164: String, val message: String, val guestName: String)

data class DebtsUiState(
    val isLoading: Boolean = true,
    val debts: List<Debt> = emptyList(),
    val searchQuery: String = "",
    val statusFilter: String = "all", // all | pending | settled | overdue (Dart _filterStatus)
    val message: DebtsUiMessage? = null,
    val share: DebtsWhatsAppShare? = null,
    val isSendingWhatsApp: Boolean = false,
    val error: String? = null
) {
    /** Dart debts_list l.270-313 — search + status filter + sorting, verbatim. */
    val filtered: List<Debt>
        get() {
            val q = searchQuery.trim()
            val list = debts.filter { debt ->
                val matchesSearch = q.isEmpty() || debt.guestName.lowercase().contains(q.lowercase())
                val matchesFilter = when (statusFilter) {
                    "pending" -> !debt.isSettled && debt.remainingAmount > 0
                    "settled" -> debt.isSettled || debt.remainingAmount <= 0
                    "overdue" -> {
                        val debtDate = overdueBaseDate(debt)
                        debtDate != null && daysPassed(debtDate) > 30 &&
                            !debt.isSettled && debt.remainingAmount > 0
                    }
                    else -> true
                }
                matchesSearch && matchesFilter
            }
            // ترتيب الديون: غير المسددة أولاً، ثم حسب تاريخ الخروج (الأحدث أولاً)
            return list.sortedWith(
                compareBy<Debt> { if (it.isSettled) 1 else 0 }.thenByDescending { it.checkoutDate }
            )
        }

    /** Dart _buildQuickStats — totals computed over ALL debts. */
    val totalDebts: Int get() = debts.size
    val pendingDebts: Int get() = debts.count { !it.isSettled }
    val totalRemaining: Double get() = debts.sumOf { it.remainingAmount }
}

/** Dart: `DateTime.tryParse(dateRecorded.isNotEmpty ? dateRecorded : checkoutDate)`. */
internal fun overdueBaseDate(debt: Debt): Long? =
    HotelTimeEngine.parseDate(debt.dateRecorded.ifEmpty { debt.checkoutDate })

internal fun daysPassed(debtDateMillis: Long): Long =
    java.util.concurrent.TimeUnit.MILLISECONDS.toDays(System.currentTimeMillis() - debtDateMillis)

@HiltViewModel
class DebtsViewModel @Inject constructor(
    private val debtsRepository: DebtsRepository,
    private val bookingsRepository: BookingsRepository,
    private val syncRepository: SyncRepository
) : ViewModel() {

    private val _state = MutableStateFlow(DebtsUiState())
    val state: StateFlow<DebtsUiState> = _state.asStateFlow()

    init {
        debtsRepository.getAll().onEach { debts ->
            _state.value = _state.value.copy(isLoading = false, debts = debts, error = null)
        }.launchIn(viewModelScope)
    }

    fun setSearchQuery(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
    }

    fun setStatusFilter(filter: String) {
        _state.value = _state.value.copy(statusFilter = filter)
    }

    fun consumeMessage() {
        _state.value = _state.value.copy(message = null)
    }

    fun consumeShare() {
        _state.value = _state.value.copy(share = null, isSendingWhatsApp = false)
    }

    /** Dart _markAsSettled (l.797-846). */
    fun settleDebt(debt: Debt) {
        viewModelScope.launch {
            try {
                val today = HotelTimeEngine.formatIso(System.currentTimeMillis()).take(10)
                debtsRepository.update(
                    debt.copy(
                        isSettled = true,
                        paidAmount = debt.totalAmount,
                        remainingAmount = 0.0,
                        paymentDate = today
                    )
                )
                pushLocalChanges()
                _state.value = _state.value.copy(
                    message = DebtsUiMessage("تم تسجيل سداد دين ${debt.guestName}")
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    message = DebtsUiMessage("فشل تسجيل السداد: ${e.message}", DebtsMsgKind.ERROR_RED900)
                )
            }
        }
    }

    /**
     * Dart partial payment (debts_list l.983-1204): validations, paid/remaining
     * update, JSON payment log appended to the note, and the colored snackbar.
     */
    fun addPartialPayment(debt: Debt, amount: Double, paymentDate: String, note: String) {
        viewModelScope.launch {
            if (amount <= 0) {
                _state.value = _state.value.copy(
                    message = DebtsUiMessage("⚠️ المبلغ غير صالح", DebtsMsgKind.ERROR_RED)
                )
                return@launch
            }
            if (amount > debt.remainingAmount) {
                _state.value = _state.value.copy(
                    message = DebtsUiMessage(
                        "⚠️ المبلغ يتجاوز المتبقي (${CurrencyFormatter.formatAmount(debt.remainingAmount)})",
                        DebtsMsgKind.ERROR_RED
                    )
                )
                return@launch
            }
            try {
                val newPaidAmount = debt.paidAmount + amount
                val newRemaining = (debt.totalAmount - newPaidAmount).coerceAtLeast(0.0)
                val isSettled = newRemaining <= 0

                val payments = parsePaymentHistory(debt.note).toMutableList()
                payments.add(Triple(amount, paymentDate, note.trim()))
                val newNote = buildPaymentHistoryNote(debt.note, payments)

                debtsRepository.update(
                    debt.copy(
                        paidAmount = newPaidAmount,
                        remainingAmount = newRemaining,
                        isSettled = isSettled,
                        paymentDate = paymentDate,
                        note = newNote
                    )
                )
                pushLocalChanges()
                _state.value = _state.value.copy(
                    message = DebtsUiMessage(
                        "✅ تم تسجيل دفعة ${CurrencyFormatter.formatAmount(amount)} بتاريخ $paymentDate" +
                            if (isSettled) " — تمت تسوية الدين بالكامل" else "",
                        DebtsMsgKind.BLUE
                    )
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    message = DebtsUiMessage("فشل تسجيل الدفعة: ${e.message}", DebtsMsgKind.ERROR_RED)
                )
            }
        }
    }

    /** Dart _openDebtForm save branch (l.1508-1571). */
    fun saveDebt(
        existing: Debt?,
        guestName: String,
        checkinDate: String,
        checkoutDate: String,
        totalAmount: Double,
        paidAmount: Double,
        debtReason: String,
        pledge: String?,
        pledgeType: String?,
        note: String?
    ) {
        viewModelScope.launch {
            try {
                val today = HotelTimeEngine.formatIso(System.currentTimeMillis()).take(10)
                val remaining = (totalAmount - paidAmount).coerceAtLeast(0.0)
                if (existing == null) {
                    debtsRepository.insert(
                        Debt(
                            guestName = guestName,
                            checkinDate = checkinDate,
                            checkoutDate = checkoutDate,
                            dateRecorded = today,
                            debtReason = debtReason,
                            totalAmount = totalAmount,
                            paidAmount = paidAmount,
                            remainingAmount = remaining,
                            paymentDate = today,
                            isSettled = remaining <= 0,
                            pledge = pledge,
                            pledgeType = pledgeType,
                            note = note
                        )
                    )
                } else {
                    debtsRepository.update(
                        existing.copy(
                            guestName = guestName,
                            checkinDate = checkinDate,
                            checkoutDate = checkoutDate,
                            debtReason = debtReason,
                            totalAmount = totalAmount,
                            paidAmount = paidAmount,
                            remainingAmount = remaining,
                            paymentDate = today,
                            isSettled = remaining <= 0,
                            pledge = pledge,
                            pledgeType = pledgeType,
                            note = note
                        )
                    )
                }
                pushLocalChanges()
                _state.value = _state.value.copy(
                    message = DebtsUiMessage(
                        if (existing == null) "تم إضافة الدين بنجاح" else "تم تحديث الدين بنجاح"
                    )
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    message = DebtsUiMessage("فشل حفظ الدين: ${e.message}", DebtsMsgKind.ERROR_RED)
                )
            }
        }
    }

    /** Dart _deleteDebt (l.1705-1754). */
    fun deleteDebt(debt: Debt) {
        viewModelScope.launch {
            try {
                debtsRepository.softDelete(debt.id)
                pushLocalChanges()
                _state.value = _state.value.copy(
                    message = DebtsUiMessage("تم حذف دين ${debt.guestName}")
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    message = DebtsUiMessage("فشل حذف الدين: ${e.message}", DebtsMsgKind.ERROR_RED900)
                )
            }
        }
    }

    /**
     * Dart _sendDebtWhatsApp (l.1589-1703): guest phone resolved from the
     * booking (bookingLocalId), cleaned to E.164, message built verbatim.
     * The Android port shares the text via the WhatsApp deep link
     * (PdfExporter.openWhatsAppText) instead of the Cloud WhatsApp API.
     */
    fun sendDebtWhatsApp(debt: Debt) {
        viewModelScope.launch {
            var phone = ""
            try {
                val bookings: List<Booking> = bookingsRepository.getAll().firstOrNull() ?: emptyList()
                phone = bookings.firstOrNull { it.id == debt.bookingLocalId }?.guestPhone ?: ""
            } catch (_: Exception) {
            }

            if (phone.isEmpty()) {
                _state.value = _state.value.copy(
                    message = DebtsUiMessage("لا يوجد رقم هاتف لهذا النزيل", DebtsMsgKind.ORANGE)
                )
                return@launch
            }
            val cleanedPhone = cleanAndFormatPhone(phone)
            if (cleanedPhone.isEmpty()) {
                _state.value = _state.value.copy(
                    message = DebtsUiMessage("رقم الهاتف غير صالح", DebtsMsgKind.ORANGE)
                )
                return@launch
            }

            val debtDate = overdueBaseDate(debt)
            val daysPassed = debtDate?.let { daysPassed(it) } ?: 0L

            val sb = StringBuilder()
            sb.appendLine("عزيزي ${debt.guestName}")
            sb.appendLine()
            sb.appendLine("تذكير بالمبلغ المتبقي عليكم")
            sb.appendLine("إجمالي المبلغ: ${CurrencyFormatter.formatAmount(debt.totalAmount)}")
            sb.appendLine("المدفوع: ${CurrencyFormatter.formatAmount(debt.paidAmount)}")
            sb.appendLine("المتبقي: ${CurrencyFormatter.formatAmount(debt.remainingAmount)}")
            if (debt.debtReason.isNotEmpty()) {
                sb.appendLine("السبب: ${debt.debtReason}")
            }
            if (daysPassed > 0) {
                sb.appendLine("مرت: $daysPassed يوم")
            }
            sb.appendLine()
            sb.appendLine("نرجو منكم تسديد المبلغ المتبقي")
            sb.appendLine()
            sb.appendLine("شكراً لتعاونكم")
            sb.appendLine("فندق مارينا")
            sb.append("للاستفسار: 9677734587456")

            _state.value = _state.value.copy(
                isSendingWhatsApp = true,
                share = DebtsWhatsAppShare(cleanedPhone, sb.toString(), debt.guestName)
            )
        }
    }

    // -------------------------------------------------------------------------
    // Dart JSON payment-log helpers (debts_list l.848-976)
    // -------------------------------------------------------------------------

    /** Entries of the `{"payments":[{amount,date,note}...]}` log stored in note. */
    private fun parsePaymentHistory(rawNote: String?): List<Triple<Double, String, String>> {
        if (rawNote.isNullOrEmpty() || !rawNote.startsWith("{")) return emptyList()
        return try {
            val root = JsonParser.parseString(rawNote).asJsonObject
            val payments = root.getAsJsonArray("payments") ?: return emptyList()
            payments.mapNotNull { el ->
                val obj = el.asJsonObject
                val amount = obj.get("amount")?.asDouble ?: return@mapNotNull null
                Triple(
                    amount,
                    obj.get("date")?.asString ?: "",
                    obj.get("note")?.asString ?: ""
                )
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    /** Dart _buildPaymentHistoryNote — preserves the original free-text note. */
    private fun buildPaymentHistoryNote(rawNote: String?, payments: List<Triple<Double, String, String>>): String {
        val existing = parsePaymentHistory(rawNote)
        var originalNote: String? = null
        if (existing.isNotEmpty()) {
            originalNote = try {
                JsonParser.parseString(rawNote ?: "{}").asJsonObject.get("original_note")?.asString
            } catch (_: Exception) {
                null
            }
        } else if (!rawNote.isNullOrEmpty() && !rawNote.startsWith("{")) {
            originalNote = rawNote
        }

        val root = JsonObject()
        val arr = JsonArray()
        payments.forEach { (amount, date, note) ->
            val entry = JsonObject()
            entry.addProperty("amount", amount)
            entry.addProperty("date", date)
            entry.addProperty("note", note)
            arr.add(entry)
        }
        root.add("payments", arr)
        if (!originalNote.isNullOrEmpty()) {
            root.addProperty("original_note", originalNote)
        }
        return root.toString()
    }

    /** Dart: `unawaited(ref.read(appwriteSyncManagerProvider).pushLocalChanges())` — رفع فوري. */
    private fun pushLocalChanges() {
        viewModelScope.launch {
            try {
                syncRepository.pushOnly()
            } catch (_: Exception) {
            }
        }
    }
}

/** Dart _cleanAndFormatPhone (debts_list l.39-62) — verbatim normalization. */
internal fun cleanAndFormatPhone(phone: String): String {
    var digitsOnly = phone.filter { it.isDigit() }
    if (digitsOnly.isEmpty()) return ""
    if (digitsOnly.startsWith("00")) {
        digitsOnly = digitsOnly.substring(2)
    }
    if (digitsOnly.startsWith("967")) return digitsOnly
    if (digitsOnly.startsWith("07")) {
        digitsOnly = "967${digitsOnly.substring(1)}"
    } else if (digitsOnly.startsWith("7") && digitsOnly.length == 9) {
        digitsOnly = "967$digitsOnly"
    } else if (digitsOnly.startsWith("5") && digitsOnly.length == 9) {
        digitsOnly = "966$digitsOnly"
    } else if (digitsOnly.startsWith("966")) {
        return digitsOnly
    } else if (digitsOnly.length <= 10 && !digitsOnly.startsWith("+")) {
        digitsOnly = "967$digitsOnly"
    }
    return digitsOnly
}
