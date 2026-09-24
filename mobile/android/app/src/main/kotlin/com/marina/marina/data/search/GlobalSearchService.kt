package com.marina.marina.data.search

import com.marina.marina.data.local.dao.BlacklistEntriesDao
import com.marina.marina.data.local.dao.BookingsDao
import com.marina.marina.data.local.dao.DebtsDao
import com.marina.marina.data.local.dao.EmployeesDao
import com.marina.marina.data.local.dao.ExpensesDao
import com.marina.marina.data.local.dao.GuestInfosDao
import com.marina.marina.data.local.dao.InventoryDao
import com.marina.marina.data.local.dao.PaymentsDao
import com.marina.marina.data.local.dao.RoomsDao
import com.marina.marina.data.local.dao.SalaryWithdrawalsDao
import com.marina.marina.domain.util.ArabicQuery
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext

/**
 * خدمة البحث الشامل — محرك موحّد فوق كل كيانات النظام.
 * Port 1:1 من `mobile/lib/services/search/global_search_service.dart`
 * (فرع feat/cloudflare-sync-execution).
 *
 * مبني على عقد طبقة البيانات الفعلية (لا اجتهاد):
 * - كل الجداول متزامنة تحمل `deletedAt` — البحث يستبعدها افتراضياً
 *   ([GlobalSearchQuery.includeDeleted] للمدير تدقيقياً).
 * - المدفوعات تحمل `isVoided`/`isPendingBalance` وتُستبعد من التقارير
 *   المالية — البحث يحترم نفس العقد ويضمها للمدير عند الطلب.
 * - التواريخ الفندقية: `hotelDayKey` هو المفتاح، مع سقوط تاريخي على
 *   عمود التاريخ القديم حين يكون المفتاح NULL (نفس عقد
 *   `PaymentsDao.listFilteredByHotelDay`).
 * - البحث النصي بتطبيع همزي عربي ([ArabicQuery]) — «احمد» تجد «أحمد».
 * - المدخل الرقمي المفرد يطابق المبالغ بالمساواة — «40000» تجد
 *   المصروف والدفعة والسحبية بمبلغها — ويطابق رقم الحجز.
 * - الصلاحيات: كل كيان مربوط بمفتاح صلاحية شاشة موجود — النتائج
 *   تُحجب قبل البناء لا بعده (لا يفتح البحث ما لا يفتحه التنقل).
 *
 * الاستعلامات محدودة دائماً (سقف النتائج لكل نوع) مع عدّاد إجمالي صادق،
 * والواجهة مسؤولة عن الـ debounce — الخدمة صمّاء لا تعرف UI.
 */

/** أنواع الكيانات القابلة للبحث. */
enum class SearchEntityKind {
    booking, guestInfo, payment, expense, withdrawal, debt, employee, room, inventoryItem, blacklist
}

/** نتيجة واحدة موحّدة من أي كيان. */
data class GlobalSearchHit(
    val kind: SearchEntityKind,
    val id: Long,
    val localUuid: String,
    /** السطر الأول في النتيجة (اسم/وصف). */
    val title: String,
    /** السطر الثاني (غرفة/نوع/سبب). */
    val subtitle: String,
    /** الرقم المالي ذو الصلة إن وجد (مبلغ/متبقي). */
    val amount: Double? = null,
    /** مفتاح اليوم الفندقي 'yyyy-MM-dd' المرتبط بالسجل. */
    val dayKey: String? = null,
    /** أسماء الحقول (عربية) التي طابق عليها الاستعلام. */
    val matchedFields: List<String> = emptyList(),
    /** الصف الأصلي بفئته (BookingEntity/PaymentEntity/... — انظر شاشة العرض). */
    val record: Any? = null
)

/** استعلام بحث شامل. */
data class GlobalSearchQuery(
    val text: String,
    /** بداية النطاق (مفتاح يوم 'yyyy-MM-dd'، شامل) — null = بلا حد. */
    val fromDay: String? = null,
    /** نهاية النطاق (مفتاح يوم 'yyyy-MM-dd'، شامل) — null = بلا حد. */
    val toDay: String? = null,
    /** إظهار السجلات المحذوفة ناعماً (تدقيق المدير). */
    val includeDeleted: Boolean = false,
    /** إظهار المدفوعات الملغاة والمعلقة مع السليم. */
    val includeInactivePayments: Boolean = false,
    /** حصر البحث بأنواع محددة — null = كل الأنواع المسموحة. */
    val kinds: Set<SearchEntityKind>? = null
)

/** حصيلة بحث شامل. */
data class GlobalSearchResults(
    val hits: Map<SearchEntityKind, List<GlobalSearchHit>>,
    val totals: Map<SearchEntityKind, Int>,
    val elapsedMs: Long
) {
    val totalHits: Int get() = hits.values.sumOf { it.size }
    val isEmpty: Boolean get() = totals.values.all { it == 0 }

    companion object {
        val EMPTY = GlobalSearchResults(emptyMap(), emptyMap(), 0)
    }
}

/** نتيجة باحث واحد. */
private data class KindResult(val hits: List<GlobalSearchHit>, val total: Int)

/** مفتاح صلاحية الشاشة الذي يحرس بيانات كل كيان (عقد مسارات Dart). */
val searchPermissionKeyByKind: Map<SearchEntityKind, String> = mapOf(
    SearchEntityKind.booking to "bookings",
    SearchEntityKind.guestInfo to "bookings",
    SearchEntityKind.payment to "payments",
    SearchEntityKind.expense to "expenses",
    SearchEntityKind.withdrawal to "employees",
    SearchEntityKind.debt to "debts",
    SearchEntityKind.employee to "employees",
    SearchEntityKind.room to "rooms",
    SearchEntityKind.inventoryItem to "settings",
    SearchEntityKind.blacklist to "blacklist"
)

/** قيم مشتقة من الاستعلام يشترك فيها كل الباحثين. */
private data class SharedMatchers(
    val words: List<String>,
    val amount: Double?,
    val bookingId: Long?
)

@Singleton
class GlobalSearchService @Inject constructor(
    private val bookingsDao: BookingsDao,
    private val guestInfosDao: GuestInfosDao,
    private val paymentsDao: PaymentsDao,
    private val expensesDao: ExpensesDao,
    private val salaryWithdrawalsDao: SalaryWithdrawalsDao,
    private val debtsDao: DebtsDao,
    private val employeesDao: EmployeesDao,
    private val roomsDao: RoomsDao,
    private val inventoryDao: InventoryDao,
    private val blacklistDao: BlacklistEntriesDao
) {

    /** سقف النتائج المعروضة لكل نوع — الواجهة تعرض «N من الإجمالي». */
    val maxHitsPerKind: Int get() = MAX_HITS_PER_KIND

    private val dayFormat: SimpleDateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)

    companion object {
        /** سقف النتائج المعروضة لكل نوع (عقد Dart). */
        const val MAX_HITS_PER_KIND = 15
    }

    /** null = بلا قيد (المدير يرى كل الأنواع). */
    private var allowedPermissionKeys: Set<String>? = null

    fun configure(allowedPermissionKeys: Set<String>?) {
        this.allowedPermissionKeys = allowedPermissionKeys
    }

    /** الأنواع التي يُسمح لهذه الخدمة بالبحث فيها. */
    val allowedKinds: Set<SearchEntityKind>
        get() = SearchEntityKind.entries.filter { isKindAllowed(it) }.toSet()

    fun isKindAllowed(kind: SearchEntityKind): Boolean {
        val keys = allowedPermissionKeys ?: return true
        return keys.contains(searchPermissionKeyByKind[kind])
    }

    /** بحث شامل — يُرجع نتائج كل الأنواع المطلوبة المسموحة. */
    suspend fun search(query: GlobalSearchQuery): GlobalSearchResults = withContext(Dispatchers.IO) {
        val started = System.currentTimeMillis()
        val words = ArabicQuery.tokenizeQuery(query.text)
        if (words.isEmpty()) {
            GlobalSearchResults.EMPTY
        } else {
            runSearch(query, words, started)
        }
    }

    private suspend fun runSearch(query: GlobalSearchQuery, words: List<String>, started: Long): GlobalSearchResults =
        withContext(Dispatchers.IO) {
        val single = words.singleOrNull()
        val matchers = SharedMatchers(
            words = words,
            amount = single?.let { ArabicQuery.tryParseAmount(it) },
            bookingId = single?.removePrefix("#")?.toLongOrNull()
        )

        val requestedKinds = query.kinds ?: SearchEntityKind.entries.toSet()
        val searchers: Map<SearchEntityKind, suspend () -> KindResult> = mapOf(
            SearchEntityKind.booking to { searchBookings(query, matchers) },
            SearchEntityKind.guestInfo to { searchGuestInfos(query, matchers) },
            SearchEntityKind.payment to { searchPayments(query, matchers) },
            SearchEntityKind.expense to { searchExpenses(query, matchers) },
            SearchEntityKind.withdrawal to { searchWithdrawals(query, matchers) },
            SearchEntityKind.debt to { searchDebts(query, matchers) },
            SearchEntityKind.employee to { searchEmployees(query, matchers) },
            SearchEntityKind.room to { searchRooms(query, matchers) },
            SearchEntityKind.inventoryItem to { searchInventoryItems(query, matchers) },
            SearchEntityKind.blacklist to { searchBlacklist(query, matchers) }
        )

        coroutineScope {
            val jobs = searchers.entries
                .filter { requestedKinds.contains(it.key) && isKindAllowed(it.key) }
                .map { entry ->
                    async {
                        // حصن كل باحث: فشل نوع لا يُسقط البحث كله — يُرجع صفراً لذلك النوع.
                        val result = try { entry.value() } catch (_: Exception) { KindResult(emptyList(), 0) }
                        entry.key to result
                    }
                }
            val entries = jobs.awaitAll()
            val hits = linkedMapOf<SearchEntityKind, List<GlobalSearchHit>>()
            val totals = linkedMapOf<SearchEntityKind, Int>()
            for ((kind, result) in entries) {
                if (result.total > 0) {
                    hits[kind] = result.hits
                    totals[kind] = result.total
                }
            }
            GlobalSearchResults(hits, totals, System.currentTimeMillis() - started)
        }
    }

    // ══════════════════════════ باحثو الكيانات ══════════════════════════
    private suspend fun searchBookings(query: GlobalSearchQuery, m: SharedMatchers): KindResult {
        val rows = bookingsDao.listAllIncludingDeleted()
            .filter { alive(it.deletedAt, query.includeDeleted) }
            .filter { b ->
                var match = textMatchAny(
                    listOf(b.guestName, b.guestPhone, b.guestIdNumber, b.guestNationality, b.roomNumber, b.notes),
                    m
                )
                if (!match && m.bookingId != null && b.id == m.bookingId) match = true
                match && plainDayRange(b.checkinDate, query.fromDay, query.toDay)
            }
            .sortedWith(compareByDescending<com.marina.marina.data.local.entity.BookingEntity> { it.checkinDate }.thenByDescending { it.id })
        val hits = rows.take(MAX_HITS_PER_KIND).map { b ->
            GlobalSearchHit(
                kind = SearchEntityKind.booking,
                id = b.id,
                localUuid = b.localUuid,
                title = b.guestName,
                subtitle = "غرفة ${b.roomNumber} • ${b.status}",
                amount = b.remainingBalanceCached,
                dayKey = dayOf(b.checkinDate),
                matchedFields = matchedFields(
                    linkedMapOf(
                        "اسم النزيل" to b.guestName,
                        "الهاتف" to b.guestPhone,
                        "رقم الهوية" to b.guestIdNumber,
                        "الجنسية" to b.guestNationality,
                        "الغرفة" to b.roomNumber,
                        "ملاحظات" to b.notes
                    ),
                    m,
                    idHit = if (m.bookingId != null && b.id == m.bookingId) "رقم الحجز" else null
                ),
                record = b
            )
        }
        return KindResult(hits, rows.size)
    }

    private suspend fun searchGuestInfos(query: GlobalSearchQuery, m: SharedMatchers): KindResult {
        val rows = guestInfosDao.listAllIncludingDeleted()
            .filter { alive(it.deletedAt, query.includeDeleted) }
            .filter { g ->
                textMatchAny(
                    listOf(g.guestName, g.idNumber, g.guestPhone, g.nationality, g.roomNumber, g.governorate, g.notes),
                    m
                )
            }
            .sortedByDescending { it.id }
        val hits = rows.take(MAX_HITS_PER_KIND).map { g ->
            GlobalSearchHit(
                kind = SearchEntityKind.guestInfo,
                id = g.id,
                localUuid = g.localUuid,
                title = g.guestName,
                subtitle = "غرفة ${g.roomNumber} • ${g.nationality}",
                matchedFields = matchedFields(
                    linkedMapOf(
                        "اسم الضيف" to g.guestName,
                        "رقم الهوية" to g.idNumber,
                        "الهاتف" to g.guestPhone,
                        "الجنسية" to g.nationality,
                        "الغرفة" to g.roomNumber,
                        "المحافظة" to g.governorate,
                        "ملاحظات" to g.notes
                    ),
                    m
                ),
                record = g
            )
        }
        return KindResult(hits, rows.size)
    }

    private suspend fun searchPayments(query: GlobalSearchQuery, m: SharedMatchers): KindResult {
        val rows = paymentsDao.listAllIncludingDeleted()
            .filter { alive(it.deletedAt, query.includeDeleted) }
            .filter { p ->
                if (!query.includeInactivePayments && (p.isVoided || p.isPendingBalance)) return@filter false
                var match = textMatchAny(
                    listOf(p.roomNumber, p.notes, p.referenceNumber, p.receivedByName, p.revenueType, p.paymentMethod),
                    m
                )
                if (!match && m.amount != null && p.amount == m.amount) match = true
                match && hotelDayRange(p.hotelDayKey, p.paymentDate, query.fromDay, query.toDay, legacyIsIso = true)
            }
            .sortedWith(compareByDescending<com.marina.marina.data.local.entity.PaymentEntity> { it.paymentDate }.thenByDescending { it.id })
        val hits = rows.take(MAX_HITS_PER_KIND).map { p ->
            GlobalSearchHit(
                kind = SearchEntityKind.payment,
                id = p.id,
                localUuid = p.localUuid,
                title = if (!p.roomNumber.isNullOrBlank()) "دفعة — غرفة ${p.roomNumber}" else "دفعة — ${p.revenueType}",
                subtitle = listOfNotNull(
                    p.receivedByName?.takeIf { it.isNotBlank() },
                    p.paymentMethod
                ).joinToString(" • "),
                amount = p.amount,
                dayKey = p.hotelDayKey ?: dayOf(p.paymentDate),
                matchedFields = matchedFields(
                    linkedMapOf(
                        "الغرفة" to p.roomNumber,
                        "ملاحظات" to p.notes,
                        "رقم المرجع" to p.referenceNumber,
                        "المستلم" to p.receivedByName,
                        "نوع الإيراد" to p.revenueType,
                        "طريقة الدفع" to p.paymentMethod
                    ),
                    m,
                    amountHit = if (m.amount != null && p.amount == m.amount) "المبلغ" else null
                ),
                record = p
            )
        }
        return KindResult(hits, rows.size)
    }

    private suspend fun searchExpenses(query: GlobalSearchQuery, m: SharedMatchers): KindResult {
        val rows = expensesDao.listAllIncludingDeleted()
            .filter { alive(it.deletedAt, query.includeDeleted) }
            .filter { e ->
                var match = textMatchAny(listOf(e.description, e.expenseType), m)
                if (!match && m.amount != null && e.amount == m.amount) match = true
                match && hotelDayRange(e.hotelDayKey, e.date, query.fromDay, query.toDay, legacyIsIso = false)
            }
            .sortedWith(compareByDescending<com.marina.marina.data.local.entity.ExpenseEntity> { it.date }.thenByDescending { it.id })
        val hits = rows.take(MAX_HITS_PER_KIND).map { e ->
            GlobalSearchHit(
                kind = SearchEntityKind.expense,
                id = e.id,
                localUuid = e.localUuid,
                title = e.description,
                subtitle = e.expenseType,
                amount = e.amount,
                dayKey = e.hotelDayKey ?: dayOf(e.date),
                matchedFields = matchedFields(
                    linkedMapOf("الوصف" to e.description, "النوع" to e.expenseType),
                    m,
                    amountHit = if (m.amount != null && e.amount == m.amount) "المبلغ" else null
                ),
                record = e
            )
        }
        return KindResult(hits, rows.size)
    }

    private suspend fun searchWithdrawals(query: GlobalSearchQuery, m: SharedMatchers): KindResult {
        // مطابقة اسم الموظف: أسماء الموظفين تُجلب أولاً — المحذوف ناعمياً
        // يظل اسمه يطابق سحبياته (نفس عقد Dart).
        val employeeRows = employeesDao.listAllIncludingDeleted()
        val nameById = employeeRows.associate { it.id to it.name }
        val fmt = dayFormat()
        val rows = salaryWithdrawalsDao.listAllIncludingDeleted()
            .filter { alive(it.deletedAt, query.includeDeleted) }
            .filter { w ->
                val legacyDay = fmt.format(Date(w.withdrawDate))
                var match = textMatchAny(listOf(w.reason, w.description, w.withdrawalType), m)
                if (!match) {
                    val empName = w.employeeName.ifBlank { nameById[w.employeeId] }
                    if (!empName.isNullOrBlank() && textMatchAny(listOf(empName), m)) match = true
                }
                if (!match && m.amount != null && w.amount == m.amount) match = true
                match && hotelDayRange(w.hotelDayKey, legacyDay, query.fromDay, query.toDay, legacyIsIso = false)
            }
            .sortedWith(compareByDescending<com.marina.marina.data.local.entity.SalaryWithdrawalEntity> { it.withdrawDate }.thenByDescending { it.id })
        val hits = rows.take(MAX_HITS_PER_KIND).map { w ->
            val empName = w.employeeName.ifBlank { nameById[w.employeeId] }
            GlobalSearchHit(
                kind = SearchEntityKind.withdrawal,
                id = w.id,
                localUuid = w.localUuid,
                title = empName ?: "موظف محذوف",
                subtitle = listOfNotNull(
                    w.reason?.takeIf { it.isNotBlank() },
                    w.withdrawalType.takeIf { it.isNotBlank() }
                ).joinToString(" • "),
                amount = w.amount,
                dayKey = w.hotelDayKey ?: fmt.format(Date(w.withdrawDate)),
                matchedFields = matchedFields(
                    linkedMapOf(
                        "السبب" to w.reason,
                        "الوصف" to w.description,
                        "النوع" to w.withdrawalType,
                        "اسم الموظف" to empName
                    ),
                    m,
                    amountHit = if (m.amount != null && w.amount == m.amount) "المبلغ" else null
                ),
                record = w
            )
        }
        return KindResult(hits, rows.size)
    }

    private suspend fun searchDebts(query: GlobalSearchQuery, m: SharedMatchers): KindResult {
        val rows = debtsDao.listAllIncludingDeleted()
            .filter { alive(it.deletedAt, query.includeDeleted) }
            .filter { d ->
                var match = textMatchAny(
                    listOf(d.guestName, d.debtorName, d.debtReason, d.note, d.pledge, d.guestPhone),
                    m
                )
                if (!match && m.amount != null &&
                    (d.totalAmount == m.amount || d.paidAmount == m.amount || d.remainingAmount == m.amount)
                ) match = true
                match && plainDayRange(d.paymentDate, query.fromDay, query.toDay)
            }
            .sortedWith(compareByDescending<com.marina.marina.data.local.entity.DebtEntity> { it.paymentDate }.thenByDescending { it.id })
        val hits = rows.take(MAX_HITS_PER_KIND).map { d ->
            val amountHit = m.amount != null &&
                (d.totalAmount == m.amount || d.paidAmount == m.amount || d.remainingAmount == m.amount)
            GlobalSearchHit(
                kind = SearchEntityKind.debt,
                id = d.id,
                localUuid = d.localUuid,
                title = d.guestName,
                subtitle = listOfNotNull(
                    d.debtReason.takeIf { it.isNotEmpty() },
                    if (d.isSettled == 1) "مسدد" else "قائم"
                ).joinToString(" • "),
                amount = d.remainingAmount,
                dayKey = dayOf(d.paymentDate),
                matchedFields = matchedFields(
                    linkedMapOf(
                        "اسم المدين" to d.guestName,
                        "المدين (تفصيلي)" to d.debtorName,
                        "السبب" to d.debtReason,
                        "ملاحظات" to d.note,
                        "الرهان" to d.pledge,
                        "الهاتف" to d.guestPhone
                    ),
                    m,
                    amountHit = if (amountHit) "المبلغ" else null
                ),
                record = d
            )
        }
        return KindResult(hits, rows.size)
    }

    private suspend fun searchEmployees(query: GlobalSearchQuery, m: SharedMatchers): KindResult {
        val rows = employeesDao.listAllIncludingDeleted()
            .filter { alive(it.deletedAt, query.includeDeleted) }
            .filter { e -> textMatchAny(listOf(e.name, e.position, e.phone, e.employeeID), m) }
            .sortedBy { it.name }
        val hits = rows.take(MAX_HITS_PER_KIND).map { e ->
            GlobalSearchHit(
                kind = SearchEntityKind.employee,
                id = e.id,
                localUuid = e.localUuid,
                title = e.name,
                subtitle = "${e.position} • ${e.status}",
                matchedFields = matchedFields(
                    linkedMapOf(
                        "الاسم" to e.name,
                        "الوظيفة" to e.position,
                        "الهاتف" to e.phone,
                        "الرقم الوظيفي" to e.employeeID
                    ),
                    m
                ),
                record = e
            )
        }
        return KindResult(hits, rows.size)
    }

    private suspend fun searchRooms(query: GlobalSearchQuery, m: SharedMatchers): KindResult {
        val rows = roomsDao.listAllIncludingDeleted()
            .filter { alive(it.deletedAt, query.includeDeleted) }
            .filter { r -> textMatchAny(listOf(r.roomNumber, r.type, r.status), m) }
            .sortedBy { it.roomNumber }
        val hits = rows.take(MAX_HITS_PER_KIND).map { r ->
            GlobalSearchHit(
                kind = SearchEntityKind.room,
                id = r.id,
                localUuid = r.localUuid,
                title = "غرفة ${r.roomNumber}",
                subtitle = "${r.type} • ${r.status}",
                matchedFields = matchedFields(
                    linkedMapOf(
                        "رقم الغرفة" to r.roomNumber,
                        "النوع" to r.type,
                        "الحالة" to r.status
                    ),
                    m
                ),
                record = r
            )
        }
        return KindResult(hits, rows.size)
    }

    private suspend fun searchInventoryItems(query: GlobalSearchQuery, m: SharedMatchers): KindResult {
        val rows = inventoryDao.listAllIncludingDeleted()
            .filter { alive(it.deletedAt, query.includeDeleted) }
            .filter { i -> textMatchAny(listOf(i.name, i.category, i.unit), m) }
            .sortedBy { it.name }
        val hits = rows.take(MAX_HITS_PER_KIND).map { i ->
            GlobalSearchHit(
                kind = SearchEntityKind.inventoryItem,
                id = i.id,
                localUuid = i.localUuid,
                title = i.name,
                subtitle = listOfNotNull(
                    i.category?.takeIf { it.isNotBlank() },
                    "الكمية: ${i.currentQuantity.toInt()}"
                ).joinToString(" • "),
                matchedFields = matchedFields(
                    linkedMapOf(
                        "الاسم" to i.name,
                        "التصنيف" to i.category,
                        "الوحدة" to i.unit
                    ),
                    m
                ),
                record = i
            )
        }
        return KindResult(hits, rows.size)
    }

    private suspend fun searchBlacklist(query: GlobalSearchQuery, m: SharedMatchers): KindResult {
        // القائمة السوداء صغيرة وتُقرأ عبر DAO المعتمد — الفلترة هنا عمداً:
        // السجلات المحذوفة ناعمياً لا تظهر (عقد getAllOnce الثابت).
        val entries = blacklistDao.getAllOnce()
        val fmt = dayFormat()
        val matched = entries.filter { entry ->
            val textHit = listOf(entry.name, entry.nationality, entry.nationalId, entry.phone, entry.reason, entry.notes)
                .any { value -> !value.isNullOrEmpty() && wordHitsAny(value, m.words) }
            val day = fmt.format(Date(entry.createdAt))
            val afterFrom = query.fromDay == null || day >= query.fromDay!!
            val beforeTo = query.toDay == null || day <= query.toDay!!
            textHit && afterFrom && beforeTo
        }
        val hits = matched.take(MAX_HITS_PER_KIND).map { entry ->
            GlobalSearchHit(
                kind = SearchEntityKind.blacklist,
                id = entry.id,
                localUuid = entry.localUuid,
                title = entry.name,
                subtitle = listOfNotNull(
                    entry.reason?.takeIf { it.isNotBlank() },
                    if (entry.active) "نشط" else "موقوف"
                ).joinToString(" • "),
                dayKey = fmt.format(Date(entry.createdAt)),
                record = entry
            )
        }
        return KindResult(hits, matched.size)
    }

    // ══════════════════════════ مساعدات البناء ══════════════════════════

    /** شرط الحياة: deletedAt IS NULL ما لم يطلب المدير إظهار المحذوف. */
    private fun alive(deletedAt: Long?, includeDeleted: Boolean): Boolean =
        includeDeleted || deletedAt == null

    /** هل تطابق قيمة نصية أي كلمة من الاستعلام (بالتطبيع)؟ */
    private fun wordHitsAny(value: String, words: List<String>): Boolean {
        val normalized = ArabicQuery.normalizeArabicForSearch(value)
        return words.any { normalized.contains(it) }
    }

    /**
     * مطابقة نصية: كلمات AND، الأعمدة OR — نظيف SQL-LIKE بتوسيع همزي:
     * التطبيع هنا يغطي نفس متغيرات Dart (عائلة الألف/الياء/الواو/الهاء).
     */
    private fun textMatchAny(columns: List<String?>, m: SharedMatchers): Boolean {
        if (m.words.isEmpty()) return false
        // كل كلمة يجب أن تطابق أي عمود (AND عبر الكلمات، OR عبر الأعمدة)
        return m.words.all { word ->
            columns.any { col -> col != null && col.isNotEmpty() && ArabicQuery.normalizeArabicForSearch(col).contains(word) }
        }
    }

    /** نطاق يوم فندقي على عمود مفتاح + سقوط تاريخي (عقد listFilteredByHotelDay). */
    private fun hotelDayRange(
        hotelDayKey: String?,
        legacyDate: String,
        fromDay: String?,
        toDay: String?,
        legacyIsIso: Boolean
    ): Boolean {
        if (fromDay != null) {
            val ok = (hotelDayKey != null && hotelDayKey >= fromDay) ||
                (hotelDayKey == null && legacyDate >= fromDay)
            if (!ok) return false
        }
        if (toDay != null) {
            val upper = (hotelDayKey != null && hotelDayKey <= toDay) ||
                (hotelDayKey == null && if (legacyIsIso) legacyDate < nextDay(toDay) else legacyDate <= toDay)
            if (!upper) return false
        }
        return true
    }

    /** نطاق على عمود تاريخ نصي (مقارنة نصية كاملة كما في Dart drift). */
    private fun plainDayRange(dateValue: String, fromDay: String?, toDay: String?): Boolean {
        if (fromDay != null && dateValue < fromDay) return false
        if (toDay != null && dateValue > toDay) return false
        return true
    }

    /** أسماء الحقول التي طابقت — مقارنة مطبَّعة على الصفوف المرجعة فقط. */
    private fun matchedFields(
        fieldsByLabel: Map<String, String?>,
        m: SharedMatchers,
        idHit: String? = null,
        amountHit: String? = null
    ): List<String> {
        val labels = mutableListOf<String>()
        for ((label, value) in fieldsByLabel) {
            if (value.isNullOrEmpty()) continue
            if (wordHitsAny(value, m.words)) labels.add(label)
        }
        idHit?.let { labels.add(it) }
        amountHit?.let { labels.add(it) }
        return labels
    }

    private fun dayOf(value: String): String = if (value.length >= 10) value.substring(0, 10) else value

    private fun nextDay(day: String): String {
        return try {
            val df = SimpleDateFormat("yyyy-MM-dd", Locale.US)
            val parsed = df.parse(day) ?: return day
            df.format(Date(parsed.time + 24L * 60 * 60 * 1000))
        } catch (_: Exception) {
            day
        }
    }

    private fun dayFormat(): SimpleDateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)
}
