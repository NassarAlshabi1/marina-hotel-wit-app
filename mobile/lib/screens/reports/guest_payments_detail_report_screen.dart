import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' hide PdfColors;
import 'package:pdf/widgets.dart' as pw;

import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart';
import '../../services/stay_balance_calculator.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/enhanced_pdf_utils.dart' as epdf;
import '../../utils/hotel_time_engine.dart';
import '../../utils/report_pdf_builder.dart';
import '../../utils/status_utils.dart';
import '../../utils/time.dart';

// ─────────────────────────────────────────────────────────────────
// يستخدم StayBalanceCalculator المحرك الموحد لحساب الرصيد والتواريخ
// التعريفات في: services/stay_balance_calculator.dart
// ─────────────────────────────────────────────────────────────────

/// تقرير تفصيلي لمدفوعات النزلاء مع حساب الأيام والمبالغ والمغادرة المخططة
class GuestPaymentsDetailReportScreen extends ConsumerStatefulWidget {
  const GuestPaymentsDetailReportScreen({super.key});

  @override
  ConsumerState<GuestPaymentsDetailReportScreen> createState() =>
      _GuestPaymentsDetailReportScreenState();
}

class _GuestPaymentsDetailReportScreenState
    extends ConsumerState<GuestPaymentsDetailReportScreen> {
  String _searchQuery = '';
  String _filterStatus = 'all'; // all, partial, unpaid, overpaid
  String _sortBy = 'room'; // room, name, remaining
  bool _showOnlyActive = true;
  bool _isLoading = true;

  /// خريطة تعديلات الأسعار النشطة مجمّعة حسب معرّف الحجز
  /// تُحدّث عند كل استدعاء لـ _refreshData()
  Map<int, List<BookingPriceAdjustment>> _adjustmentsByBookingId = const {};

  /// ✅ إصلاح: تخزين مؤقت لنتائج _calculateCoverage لتجنب إعادة الحساب
  /// لكل بطاقة عدة مرات. المفتاح = معرّف الحجز.
  Map<int, StayBalanceResult> _coverageCache = {};

  /// ✅ إصلاح: نسخة احتياطية آمنة من StayBalanceResult للاستخدام عند الخطأ
  /// عند فشل تحليل تاريخ الدخول، نستخدم تاريخ اليوم الفندقي بدلاً من DateTime.now()
  /// الذي يُنتج نتائج خاطئة (0 أيام، تاريخ خروج خاطئ)
  static StayBalanceResult _safeFallback(Booking b) {
    final checkin = DateTime.tryParse(b.checkinDate);
    final checkout = (b.checkoutDate != null && b.checkoutDate!.isNotEmpty)
        ? DateTime.tryParse(b.checkoutDate!)
        : null;
    // ✅ إصلاح: إذا فشل تحليل تاريخ الدخول، نستخدم بداية اليوم الفندقي الحالي
    // بدلاً من DateTime.now() الذي يُسبب حسابات خاطئة
    final hotelDay = HotelTimeEngine.getHotelDay(DateTime.now());
    final safeCheckin =
        checkin ??
        DateTime(
          hotelDay.year,
          hotelDay.month,
          hotelDay.day,
          HotelTimeEngine.boundaryHour,
          HotelTimeEngine.boundaryMinute,
        );
    return StayBalanceResult(
      checkinDate: safeCheckin,
      manualCheckoutDate: checkout,
      autoCheckoutDate: checkout ?? safeCheckin.add(const Duration(days: 1)),
      totalPaid: b.totalPaidCached,
      nightlyRate: 0,
      effectiveNightlyRate: 0,
      actualNightsSpent: 0,
      totalPaidNights: 0,
      consumedCost: 0,
      effectiveBalance: b.remainingBalanceCached,
      manualNightsRemaining: 0,
      isAutoExtended: false,
      extraNightsBeyondManual: 0,
      surplusAfterAllNights: 0,
      rawRemainingBalance: b.remainingBalanceCached,
      coveredDates: const [],
    );
  }

  static final _dateFormatter = DateFormat('yyyy/MM/dd');

  /// حساب الأيام المقضية فعلياً بناءً على قاعدة الساعة 14:00
  /// ✅ إصلاح: عند فشل تحليل تاريخ الدخول، نستخدم اليوم الفندقي بدلاً من DateTime.now()
  int _getActualDaysSpent(Booking b) {
    final checkin = DateTime.tryParse(b.checkinDate);
    if (checkin == null) return 0; // لا يمكن حساب بدون تاريخ دخول صالح
    final end = (b.actualCheckout != null && b.actualCheckout!.isNotEmpty)
        ? DateTime.tryParse(b.actualCheckout!)
        : DateTime.now();
    return Time.nightsWithCutoff(checkin, checkout: end);
  }

  /// حساب الأيام المتبقية حتى تاريخ المغادرة المخطط
  // ignore: unused_element
  int _getDaysUntilCheckout(Booking b) {
    if (b.checkoutDate == null || b.checkoutDate!.isEmpty) {
      return 0;
    }
    final checkout = DateTime.tryParse(b.checkoutDate!);
    if (checkout == null) {
      return 0;
    }
    final now = DateTime.now();
    if (checkout.isBefore(now)) {
      return 0;
    }
    return Time.nightsWithCutoff(now, checkout: checkout);
  }

  /// حساب متوسط سعر الليلة الواحدة للحجز
  /// يُفضّل السعر الفعلي من الغرفة، وإلا يُحسب من إجمالي العقد
  double _getAverageNightlyRate(Booking b) {
    final nights = b.calculatedNights > 0 ? b.calculatedNights : 1;
    // استخدام السعر الأساسي من الغرفة بدلاً من المتوسط الذي قد يتضمن خصومات
    // المتوسط يُستخدم فقط كاحتياطي عندما لا يتوفر سعر الغرفة
    return b.totalDueCached > 0 ? (b.totalDueCached / nights) : 0;
  }

  /// حساب التكلفة الفعلية حتى الآن (مع مراعاة تعديلات الأسعار)
  /// يُستخدم consumedCost من StayBalanceCalculator بدلاً من حساب بسيط
  // ignore: unused_element
  double _getConsumedCost(Booking b) {
    final coverage = _calculateCoverage(b);
    return coverage.consumedCost;
  }

  /// استخدام المحرك الموحد لحساب الرصيد والتاريخ التلقائي
  /// يمرّر تعديلات الأسعار من booking_price_adjustments للمحرك
  /// ✅ إصلاح: تخزين مؤقت + try-catch لمنع انهيار التطبيق
  StayBalanceResult _calculateCoverage(Booking b) {
    // التحقق من التخزين المؤقت أولاً
    final cached = _coverageCache[b.id];
    if (cached != null) {
      return cached;
    }

    try {
      final adjustments = _adjustmentsByBookingId[b.id];
      final filtered = StayBalanceCalculator.filterActiveAdjustments(
        b,
        adjustments ?? [],
      );
      final result = StayBalanceCalculator.calculate(
        b,
        priceAdjustments: filtered,
      );
      // حفظ في التخزين المؤقت
      _coverageCache[b.id] = result;
      return result;
    } catch (e) {
      debugPrint('⚠️ خطأ في حساب تغطية الحجز ${b.id}: $e');
      final fallback = _safeFallback(b);
      _coverageCache[b.id] = fallback;
      return fallback;
    }
  }

  /// هل الحجز تجاوز تاريخ المغادرة المخطط؟
  bool _isOverdue(Booking b) => b.isOverdue;

  /// حساب عدد أيام التأخير
  int _getOverdueDays(Booking b) {
    if (!_isOverdue(b)) {
      return 0;
    }
    final checkout = DateTime.tryParse(b.checkoutDate ?? '');
    if (checkout == null) {
      return 0;
    }
    return Time.nightsWithCutoff(checkout, checkout: DateTime.now());
  }

  /// تكلفة أيام التأخير
  // ignore: unused_element
  double _getOverdueCost(Booking b) {
    final days = _getOverdueDays(b);
    if (days <= 0) {
      return 0;
    }
    return _getAverageNightlyRate(b) * days;
  }

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  Future<void> _refreshData() async {
    setState(() => _isLoading = true);
    try {
      final db = ref.read(databaseProvider);

      // ✅ إصلاح حرج: إزالة refreshAllActiveBookings(forceRebuild: true)
      // الذي يُعيد بناء سجلات الليالي لجميع الحجوزات النشطة بالتوازي
      // مما يسبب تجميد/انهيار التطبيق (OOM / ANR).
      // بدلاً من ذلك، نستخدم القيم المخزنة مسبقاً (cached) من قاعدة البيانات
      // التي تم تحديثها آخر مرة تم فيها فتح الشاشة أو إجراء عملية.

      // جلب جميع تعديلات الأسعار النشطة وتجميعها حسب معرّف الحجز فقط
      final allAdjustments =
          await (db.select(db.bookingPriceAdjustments)
                ..where((a) => a.isActive.equals(true))
                ..where((a) => a.deletedAt.isNull()))
              .get();

      final grouped = <int, List<BookingPriceAdjustment>>{};
      for (final adj in allAdjustments) {
        if (adj.bookingLocalId == null) {
          continue;
        }
        grouped.putIfAbsent(adj.bookingLocalId!, () => []);
        grouped[adj.bookingLocalId!]!.add(adj);
      }

      // ✅ إصلاح حرج: حساب مسبق لكل التغطيات هنا بدلاً من أثناء build
      // السبب: _calculateCoverage يستدعي StayBalanceCalculator.calculate الذي
      // يُنفّذ حلقات محاكاة يومية (حتى 3650 تكرار) — تشغيلها على الخيط
      // الرئيسي أثناء build يُسبب تجميد/انهيار التطبيق (ANR)
      final bookings = await ref.read(bookingsRepoProvider).watch().first;
      final newCache = <int, StayBalanceResult>{};
      for (final b in bookings) {
        try {
          final adjustments = grouped[b.id];
          final filtered = StayBalanceCalculator.filterActiveAdjustments(
            b,
            adjustments ?? [],
          );
          newCache[b.id] = StayBalanceCalculator.calculate(
            b,
            priceAdjustments: filtered,
          );
        } catch (e) {
          debugPrint('⚠️ خطأ في حساب تغطية الحجز ${b.id}: $e');
          newCache[b.id] = _safeFallback(b);
        }
        // ✅ السماح بتحديث UI كل 10 حجوزات لمنع تجميد الشاشة
        if (newCache.length % 10 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      if (mounted) {
        setState(() {
          _adjustmentsByBookingId = grouped;
          _coverageCache = newCache;
        });
      }
    } catch (e) {
      debugPrint('Error refreshing data: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Booking> _filterAndSort(List<Booking> allBookings) {
    var filtered = _showOnlyActive
        ? allBookings.where(StatusUtils.isBookingActive).toList()
        : allBookings.where((b) => b.deletedAt == null).toList();

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((b) {
        return b.guestName.toLowerCase().contains(q) ||
            b.roomNumber.toLowerCase().contains(q) ||
            b.guestPhone.toLowerCase().contains(q);
      }).toList();
    }

    if (_filterStatus == 'partial') {
      filtered = filtered
          .where((b) => b.totalPaidCached > 0 && b.remainingBalanceCached > 0)
          .toList();
    } else if (_filterStatus == 'unpaid') {
      filtered = filtered.where((b) => b.totalPaidCached <= 0).toList();
    } else if (_filterStatus == 'overpaid') {
      filtered = filtered.where((b) => b.remainingBalanceCached < 0).toList();
    }

    filtered.sort((a, b) {
      if (_sortBy == 'room') {
        return a.roomNumber.compareTo(b.roomNumber);
      }
      if (_sortBy == 'remaining') {
        return b.remainingBalanceCached.compareTo(a.remainingBalanceCached);
      }
      return a.guestName.compareTo(b.guestName);
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(bookingsListProvider);

    return AppScaffold(
      title: 'مارينا هوتيل',
      subtitle: 'تقرير مدفوعات النزلاء التفصيلي',
      titleAlign: TextAlign.end,
      appBarBackgroundColor: Colors.white,
      titleColor: Colors.black,
      subtitleColor: Colors.black,
      actions: [
        IconButton(
          icon: const Icon(Icons.print_outlined),
          onPressed: _exportAllBookingsPdf,
          tooltip: 'طباعة التقرير',
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _refreshData,
          tooltip: 'تحديث البيانات',
        ),
      ],
      body: Column(
        children: [
          _buildSearchAndFilters(),
          Expanded(
            // ✅ إصلاح: انتظار اكتمال الحسابات قبل عرض البطاقات
            // _isLoading = true حتى تنتهي _refreshData من حساب كل التغطيات
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text(
                          'جاري حساب البيانات...',
                          style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                : bookingsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 48,
                              color: Colors.red,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'خطأ في تحميل البيانات',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$e',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: _refreshData,
                              child: const Text('إعادة المحاولة'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    data: _buildReportSafe,
                  ),
          ),
        ],
      ),
    );
  }

  // ───────────────────── الفلاتر والبحث ─────────────────────

  Widget _buildSearchAndFilters() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          TextField(
            style: const TextStyle(fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: 'ابحث باسم النزيل أو رقم الغرفة...',
              hintStyle: TextStyle(
                fontWeight: FontWeight.normal,
                color: Colors.grey[500],
              ),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () => setState(() => _searchQuery = ''),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              isDense: true,
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('الكل', 'all', Colors.blue),
                const SizedBox(width: 6),
                _buildFilterChip('دفع جزئي', 'partial', Colors.orange),
                const SizedBox(width: 6),
                _buildFilterChip('غير مدفوع', 'unpaid', Colors.red),
                const SizedBox(width: 6),
                _buildFilterChip('مدفوع زيادة', 'overpaid', Colors.green),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () =>
                      setState(() => _showOnlyActive = !_showOnlyActive),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      color: _showOnlyActive
                          ? Colors.blue.shade50
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _showOnlyActive
                            ? Colors.blue.shade200
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _showOnlyActive
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          size: 16,
                          color: _showOnlyActive ? Colors.blue : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'النزلاء الحاليين فقط',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _showOnlyActive
                                ? Colors.blue.shade700
                                : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _sortBy,
                  decoration: InputDecoration(
                    labelText: 'ترتيب حسب',
                    labelStyle: const TextStyle(fontSize: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'room', child: Text('رقم الغرفة')),
                    DropdownMenuItem(value: 'name', child: Text('اسم النزيل')),
                    DropdownMenuItem(
                      value: 'remaining',
                      child: Text('المبلغ المتبقي'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _sortBy = v);
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, Color color) {
    final isSelected = _filterStatus == value;
    return FilterChip(
      label: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
      selected: isSelected,
      onSelected: (_) => setState(() => _filterStatus = value),
      selectedColor: color.withValues(alpha: 0.2),
      checkmarkColor: color,
      backgroundColor: Colors.grey.shade100,
      labelStyle: TextStyle(color: isSelected ? color : Colors.grey.shade700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }

  // ───────────────────── بناء التقرير ─────────────────────

  /// ✅ إصلاح: غلاف آمن لمنع انهيار التطبيق عند حدوث أي خطأ في بناء التقرير
  Widget _buildReportSafe(List<Booking> allBookings) {
    try {
      return _buildReport(allBookings);
    } catch (e) {
      debugPrint('⚠️ خطأ في بناء تقرير المدفوعات: $e');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.orange),
              const SizedBox(height: 12),
              const Text(
                'حدث خطأ أثناء عرض التقرير',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$e',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                textAlign: TextAlign.center,
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _refreshData,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildReport(List<Booking> allBookings) {
    final filtered = _filterAndSort(allBookings);

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            const Text(
              'لا توجد بيانات تطابق معايير البحث',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    final totalDue = filtered.fold(0.0, (s, b) => s + b.totalDueCached);
    final totalPaid = filtered.fold(0.0, (s, b) => s + b.totalPaidCached);
    final totalRemaining = filtered.fold(
      0.0,
      (s, b) =>
          s + (b.remainingBalanceCached > 0 ? b.remainingBalanceCached : 0),
    );
    final totalCredit = filtered.fold(
      0.0,
      (s, b) =>
          s + (b.remainingBalanceCached < 0 ? -b.remainingBalanceCached : 0),
    );

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          color: Colors.blue.shade900,
          child: Row(
            children: [
              _buildSummaryItem('النزلاء', '${filtered.length}', Colors.white),
              const Spacer(),
              _buildSummaryItem(
                'المستحق',
                CurrencyFormatter.formatAmount(totalDue),
                Colors.amber.shade300,
              ),
              const Spacer(),
              _buildSummaryItem(
                'المحصل',
                CurrencyFormatter.formatAmount(totalPaid),
                Colors.green.shade300,
              ),
              const Spacer(),
              _buildSummaryItem(
                'المتبقي',
                CurrencyFormatter.formatAmount(totalRemaining),
                Colors.orange.shade300,
              ),
              if (totalCredit > 0) ...[
                const Spacer(),
                _buildSummaryItem(
                  'زيادة',
                  CurrencyFormatter.formatAmount(totalCredit),
                  Colors.teal.shade300,
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            itemCount: filtered.length,
            itemBuilder: (context, index) =>
                RepaintBoundary(child: _buildBookingCard(filtered[index])),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryItem(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 9)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  // ───────────────────── بطاقة الحجز ─────────────────────

  Widget _buildBookingCard(Booking b) {
    final actualDays = _getActualDaysSpent(b);
    final coverage = _calculateCoverage(b);
    final nightlyRate = coverage.effectiveNightlyRate > 0
        ? coverage.effectiveNightlyRate
        : _getAverageNightlyRate(b);
    final plannedCheckout = coverage.autoCheckoutDate;
    final isAutoOverdue =
        DateTime.now().isAfter(plannedCheckout) && coverage.hasPayments;
    final autoOverdueDays = isAutoOverdue
        ? Time.nightsWithCutoff(plannedCheckout, checkout: DateTime.now())
        : 0;
    final autoOverdueCost = autoOverdueDays * nightlyRate;

    final consumedCost = coverage.consumedCost;
    final paidPercent = consumedCost > 0
        ? (b.totalPaidCached / consumedCost * 100)
        : 100.0;
    final remaining = b.remainingBalanceCached;
    final isCredit = remaining < 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      elevation: 2,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          _buildCardHeader(b, nightlyRate),
          Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDatesSection(b, coverage),
                const Divider(height: 8),
                _buildDaysSection(b, actualDays, coverage),
                const SizedBox(height: 5),
                _buildFinancialSection(
                  b,
                  nightlyRate,
                  paidPercent,
                  isCredit,
                  remaining,
                ),
                if (isAutoOverdue && autoOverdueDays > 0) ...[
                  const SizedBox(height: 5),
                  _buildOverdueAlert(autoOverdueDays, autoOverdueCost),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardHeader(Booking b, double nightlyRate) {
    final remaining = b.remainingBalanceCached;
    final isCredit = remaining < 0;
    final displayRemaining = isCredit ? -remaining : remaining;
    final remainingLabel = isCredit ? 'رصيد للنزيل' : 'متبقي';
    final remainingColor = isCredit
        ? Colors.green.shade700
        : Colors.red.shade700;
    final remainingBgColor = isCredit
        ? Colors.green.shade50
        : Colors.red.shade50;
    final remainingBorderColor = isCredit
        ? Colors.green.shade200
        : Colors.red.shade200;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue.shade700,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'غرفة ${b.roomNumber}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  b.guestName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'سعر الليلة: ${CurrencyFormatter.formatAmount(nightlyRate)} ريال',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          // ✅ عرض المبلغ المتبقي بجانب الإجمالي في رأس البطاقة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: remainingBgColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: remainingBorderColor),
            ),
            child: Column(
              children: [
                Text(
                  remainingLabel,
                  style: TextStyle(
                    fontSize: 8,
                    color: remainingColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  CurrencyFormatter.formatAmount(displayRemaining),
                  style: TextStyle(
                    fontSize: 12,
                    color: remainingColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.red, size: 18),
            onPressed: () => _exportGuestStatementPdf(b),
            tooltip: 'كشف حساب PDF',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  // ─── قسم التواريخ: المغادرة المخططة = محسوبة من المدفوعات والتكلفة ───

  Widget _buildDatesSection(Booking b, StayBalanceResult coverage) {
    final plannedCheckout = coverage.autoCheckoutDate;
    final isAutoOverdue =
        DateTime.now().isAfter(plannedCheckout) && coverage.hasPayments;
    final autoOverdueDays = isAutoOverdue
        ? Time.nightsWithCutoff(plannedCheckout, checkout: DateTime.now())
        : 0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildInfoItem(
                Icons.login,
                'الدخول',
                _dateFormatter.format(coverage.checkinDate),
              ),
            ),
            Expanded(
              child: _buildInfoItem(
                Icons.nights_stay,
                'الليالي المدفوعة',
                '${coverage.totalPaidNights} ليلة',
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isAutoOverdue ? Colors.orange.shade50 : Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isAutoOverdue
                  ? Colors.orange.shade200
                  : Colors.blue.shade200,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isAutoOverdue ? Icons.autorenew : Icons.event_available,
                size: 18,
                color: isAutoOverdue
                    ? Colors.orange.shade700
                    : Colors.blue.shade700,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAutoOverdue
                          ? 'المغادرة المخططة (مُمدَّدة)'
                          : 'المغادرة المخططة (محسوبة)',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: isAutoOverdue
                            ? Colors.orange.shade700
                            : Colors.blue.shade700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        Text(
                          _dateFormatter.format(plannedCheckout),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isAutoOverdue
                                ? Colors.orange.shade900
                                : Colors.blue.shade900,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isAutoOverdue && autoOverdueDays > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade700,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '+$autoOverdueDays يوم تمديد',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── قسم الأيام ───

  Widget _buildDaysSection(
    Booking b,
    int actualDays,
    StayBalanceResult coverage,
  ) {
    final plannedCheckout = coverage.autoCheckoutDate;
    final isAutoOverdue =
        DateTime.now().isAfter(plannedCheckout) && coverage.hasPayments;
    final autoOverdueDays = isAutoOverdue
        ? Time.nightsWithCutoff(plannedCheckout, checkout: DateTime.now())
        : 0;
    final nightsUntilPlanned =
        !isAutoOverdue && plannedCheckout.isAfter(DateTime.now())
        ? Time.nightsWithCutoff(DateTime.now(), checkout: plannedCheckout)
        : 0;

    return Row(
      children: [
        Expanded(child: _buildDaysStat('المقضية', '$actualDays', Colors.blue)),
        const SizedBox(width: 4),
        if (isAutoOverdue && autoOverdueDays > 0)
          Expanded(
            child: _buildDaysStat(
              'إضافية (تمديد)',
              '+$autoOverdueDays',
              Colors.orange,
            ),
          )
        else
          Expanded(
            child: _buildDaysStat(
              'المتبقية',
              '$nightsUntilPlanned',
              Colors.purple,
            ),
          ),
        const SizedBox(width: 4),
        Expanded(
          child: _buildDaysStat(
            'المخططة',
            '${coverage.totalPaidNights}',
            Colors.grey,
          ),
        ),
      ],
    );
  }

  // ─── قسم المبالغ المالية ───

  Widget _buildFinancialSection(
    Booking b,
    double nightlyRate,
    double paidPercent,
    bool isCredit,
    double remaining,
  ) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'تغطية التكاليف الحالية',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
              Text(
                '${paidPercent.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: paidPercent >= 100 ? Colors.green : Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (paidPercent / 100).clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                paidPercent >= 100 ? Colors.green : Colors.orange,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _buildAmountDetail(
                  'إجمالي العقد',
                  b.totalDueCached,
                  Colors.blue.shade900,
                ),
              ),
              Expanded(
                child: _buildAmountDetail(
                  'إجمالي المدفوع',
                  b.totalPaidCached,
                  Colors.green.shade800,
                ),
              ),
              Expanded(
                child: _buildAmountDetail(
                  isCredit ? 'رصيد للنزيل' : 'متبقي عليه',
                  isCredit ? -remaining : remaining,
                  isCredit ? Colors.green.shade800 : Colors.red.shade800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── تنبيه التأخير ───

  Widget _buildOverdueAlert(int overdueDays, double overdueCost) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'تجاوز موعد المغادرة بـ $overdueDays يوم (تكلفة إضافية: ${CurrencyFormatter.formatAmount(overdueCost)} ريال)',
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────── عناصر واجهة المستخدم المساعدة ─────────────────────

  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 9, color: Colors.grey),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDaysStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: color.withValues(alpha: 0.8),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountDetail(String label, double value, Color color) {
    return Column(
      children: [
        Text(
          CurrencyFormatter.formatAmount(value),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: const TextStyle(
            fontSize: 8,
            color: Colors.black54,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ───────────────────── تصدير PDF ─────────────────────

  Future<void> _exportGuestStatementPdf(Booking b) async {
    final payments = await ref
        .read(paymentsRepoProvider)
        .paymentsByBooking(b.id)
        .first;
    final actualDays = _getActualDaysSpent(b);
    final coverage = _calculateCoverage(b);
    final consumedCost = coverage.consumedCost;
    final nightlyRate = coverage.effectiveNightlyRate > 0
        ? coverage.effectiveNightlyRate
        : _getAverageNightlyRate(b);

    final config = ReportPdfConfig(
      title: 'كشف حساب نزيل تفصيلي',
      fileName: ReportPdfBuilder.generateFileName('كشف-حساب-${b.guestName}'),
      extraHeaderLine: 'النزيل: ${b.guestName} | غرفة: ${b.roomNumber}',
      buildContent: (fonts) {
        final List<pw.Widget> pdfContent = [
          // ─── ملخص الحساب والمدة ───
          epdf.EnhancedPdfUtils.buildInfoCard(
            title: 'ملخص الحساب والمدة الزمانية',
            fonts: fonts,
            content: [
              _buildPdfInfoRow(
                fonts,
                'تاريخ الوصول:',
                _dateFormatter.format(coverage.checkinDate),
              ),
              _buildPdfInfoRow(
                fonts,
                'تاريخ المغادرة المتوقع (يدوي):',
                coverage.formatDate(coverage.manualCheckoutDate),
              ),
              _buildPdfInfoRow(
                fonts,
                'عدد الأيام المقضية حتى الآن:',
                '$actualDays يوم',
              ),
              _buildPdfInfoRow(
                fonts,
                'الأيام المتبقية حتى المغادرة:',
                '${coverage.manualNightsRemaining} يوم',
              ),
              _buildPdfInfoRow(
                fonts,
                'سعر الغرفة لليلة الواحدة:',
                '${CurrencyFormatter.formatAmount(nightlyRate)} ريال',
              ),
              pw.Divider(color: const PdfColor(0.8, 0.8, 0.8), thickness: 0.5),
              // ✅ عرض الإجمالي والمبلغ المتبقي في سطر واحد
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'إجمالي تكلفة الإقامة:',
                          style: pw.TextStyle(
                            font: fonts.regular,
                            fontSize: 11,
                            color: const PdfColor(0.15, 0.15, 0.15),
                          ),
                        ),
                        pw.Text(
                          '${CurrencyFormatter.formatAmount(consumedCost)} ريال',
                          style: pw.TextStyle(
                            font: fonts.bold,
                            fontSize: 11,
                            color: const PdfColor(0, 0, 0),
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 16),
                  pw.Expanded(
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          b.remainingBalanceCached < 0
                              ? 'المتبقي (له):'
                              : 'المتبقي (عليه):',
                          style: pw.TextStyle(
                            font: fonts.bold,
                            fontSize: 11,
                            color: b.remainingBalanceCached < 0
                                ? const PdfColor(0.0, 0.7, 0.3)
                                : const PdfColor(0.9, 0.2, 0.2),
                          ),
                        ),
                        pw.Text(
                          '${CurrencyFormatter.formatAmount(b.remainingBalanceCached.abs())} ريال',
                          style: pw.TextStyle(
                            font: fonts.bold,
                            fontSize: 11,
                            color: b.remainingBalanceCached < 0
                                ? const PdfColor(0.0, 0.7, 0.3)
                                : const PdfColor(0.9, 0.2, 0.2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.Divider(
                color: const PdfColor(0.85, 0.85, 0.85),
                thickness: 0.3,
              ),
              _buildPdfInfoRow(
                fonts,
                'إجمالي المبالغ المدفوعة:',
                '${CurrencyFormatter.formatAmount(b.totalPaidCached)} ريال',
                valueColor: const PdfColor(0.0, 0.5, 0.2),
              ),
            ],
          ),
        ];

        // ─── قسم المغادرة المخططة (محسوبة من المدفوعات) + التمديد عند التجاوز ───
        final plannedCheckout = coverage.autoCheckoutDate;
        final isAutoOverdue =
            DateTime.now().isAfter(plannedCheckout) && coverage.hasPayments;
        final autoOverdueDays = isAutoOverdue
            ? Time.nightsWithCutoff(plannedCheckout, checkout: DateTime.now())
            : 0;
        final autoOverdueCost = autoOverdueDays * nightlyRate;

        pdfContent.add(pw.SizedBox(height: 16));

        pdfContent.add(
          epdf.EnhancedPdfUtils.buildInfoCard(
            title: isAutoOverdue
                ? 'المغادرة المخططة (مُمدَّدة تلقائياً)'
                : 'المغادرة المخططة (محسوبة من المدفوعات)',
            fonts: fonts,
            content: [
              _buildPdfInfoRow(
                fonts,
                'إجمالي المدفوع:',
                '${CurrencyFormatter.formatAmount(b.totalPaidCached)} ريال',
                valueColor: const PdfColor(0.0, 0.5, 0.8),
              ),
              _buildPdfInfoRow(
                fonts,
                'سعر الليلة:',
                '${CurrencyFormatter.formatAmount(nightlyRate)} ريال',
              ),
              _buildPdfInfoRow(
                fonts,
                'الليالي المدفوعة:',
                '${coverage.totalPaidNights} ليلة',
              ),
              _buildPdfInfoRow(
                fonts,
                'المغادرة المخططة:',
                _dateFormatter.format(plannedCheckout),
                valueColor: const PdfColor(0.0, 0.6, 0.3),
              ),
              _buildPdfInfoRow(
                fonts,
                'تكلفة الإقامة المستهلكة:',
                '${CurrencyFormatter.formatAmount(coverage.consumedCost)} ريال',
              ),
              _buildPdfInfoRow(
                fonts,
                'الرصيد الفعلي:',
                '${CurrencyFormatter.formatAmount(coverage.effectiveBalance)} ريال',
                valueColor: coverage.effectiveBalance >= 0
                    ? const PdfColor(0.0, 0.7, 0.3)
                    : const PdfColor(0.9, 0.3, 0.1),
              ),
              if (isAutoOverdue && autoOverdueDays > 0) ...[
                pw.Divider(
                  color: const PdfColor(0.8, 0.8, 0.8),
                  thickness: 0.5,
                ),
                _buildPdfInfoRow(
                  fonts,
                  'تمديد تلقائي:',
                  '+$autoOverdueDays يوم',
                  valueColor: const PdfColor(0.9, 0.5, 0.1),
                ),
                _buildPdfInfoRow(
                  fonts,
                  'تكلفة التمديد:',
                  '${CurrencyFormatter.formatAmount(autoOverdueCost)} ريال',
                  valueColor: const PdfColor(0.9, 0.3, 0.1),
                ),
                _buildPdfInfoRow(
                  fonts,
                  'ملاحظة:',
                  'المغادرة يدوياً فقط — لا يتم إخراج النزيل تلقائياً',
                  valueColor: const PdfColor(0.4, 0.4, 0.4),
                ),
              ],
              if (coverage.surplusAfterAllNights > 0)
                _buildPdfInfoRow(
                  fonts,
                  'فائض:',
                  '${CurrencyFormatter.formatAmount(coverage.surplusAfterAllNights)} ريال',
                  valueColor: const PdfColor(0.0, 0.7, 0.3),
                ),
            ],
          ),
        );

        pdfContent.addAll([
          pw.SizedBox(height: 20),

          // ─── جدول المدفوعات ───
          pw.Text(
            'سجل المدفوعات التفصيلي',
            style: pw.TextStyle(
              font: fonts.bold,
              fontSize: 14,
              color: const PdfColor(0.0, 0.12, 0.36),
            ),
          ),
          pw.SizedBox(height: 10),
          epdf.EnhancedPdfUtils.buildProfessionalTable(
            fonts: fonts,
            headers: [
              'التاريخ',
              'المبلغ',
              'طريقة الدفع',
              'رقم المرجع',
              'ملاحظات',
            ],
            data: payments
                .map(
                  (p) => [
                    p.paymentDate.split('T').first,
                    CurrencyFormatter.formatAmount(p.amount),
                    p.paymentMethod,
                    p.referenceNumber ?? '---',
                    p.notes ?? '',
                  ],
                )
                .toList(),
            columnWidths: [80, 80, 70, 70, -1],
          ),

          pw.SizedBox(height: 30),

          // ─── التذييل ───
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'ملاحظات:',
                    style: pw.TextStyle(font: fonts.bold, fontSize: 10),
                  ),
                  pw.Text(
                    'يُحتسب اليوم الفندقي من الساعة 2:00 ظهراً.',
                    style: pw.TextStyle(font: fonts.regular, fontSize: 9),
                  ),
                  pw.Text(
                    'تاريخ المغادرة التلقائي يُحسب من إجمالي المدفوعات التراكمية مقسومة على سعر الليلة.',
                    style: pw.TextStyle(font: fonts.regular, fontSize: 9),
                  ),
                  pw.Text(
                    'أي دفعة جديدة تُحدّث تاريخ المغادرة التلقائي فوراً.',
                    style: pw.TextStyle(font: fonts.regular, fontSize: 9),
                  ),
                ],
              ),
              pw.Column(
                children: [
                  pw.Text(
                    'ختم وتوقيع الإدارة',
                    style: pw.TextStyle(font: fonts.bold, fontSize: 12),
                  ),
                  pw.SizedBox(height: 40),
                  pw.Container(
                    width: 120,
                    height: 1,
                    color: const PdfColor(0, 0, 0),
                  ),
                ],
              ),
            ],
          ),

          pw.SizedBox(height: 20),
          pw.Center(
            child: pw.Text(
              'شكراً لاختياركم فندق مارينا - نتمنى لكم إقامة سعيدة',
              style: pw.TextStyle(
                font: fonts.regular,
                fontSize: 10,
                color: const PdfColor(0.4, 0.4, 0.4),
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          ),
        ]);

        return pdfContent;
      },
    );

    await ReportPdfBuilder.buildAndShare(config);
  }

  pw.Widget _buildPdfInfoRow(
    epdf.ArabicPdfFonts fonts,
    String label,
    String value, {
    PdfColor? valueColor,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 11,
              color: const PdfColor(0.15, 0.15, 0.15),
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              font: fonts.bold,
              fontSize: 11,
              color: valueColor ?? const PdfColor(0, 0, 0),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────── تصدير التقرير العام PDF ─────────────────────

  Future<void> _exportAllBookingsPdf() async {
    final db = ref.read(databaseProvider);
    final allBookings = await (db.select(
      db.bookings,
    )..where((b) => b.deletedAt.isNull())).get();

    final filtered = _filterAndSort(allBookings);
    if (filtered.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('لا توجد بيانات للتصدير')));
      }
      return;
    }

    final totalDue = filtered.fold(0.0, (s, b) => s + b.totalDueCached);
    final totalPaid = filtered.fold(0.0, (s, b) => s + b.totalPaidCached);
    final totalRemaining = filtered.fold(
      0.0,
      (s, b) =>
          s + (b.remainingBalanceCached > 0 ? b.remainingBalanceCached : 0),
    );
    final totalCredit = filtered.fold(
      0.0,
      (s, b) =>
          s + (b.remainingBalanceCached < 0 ? -b.remainingBalanceCached : 0),
    );

    final now = DateTime.now();
    final dateStr = DateFormat('yyyy/MM/dd HH:mm').format(now);

    final config = ReportPdfConfig(
      title: 'تقرير مدفوعات النزلاء التفصيلي',
      fileName: ReportPdfBuilder.generateFileName('تقرير-مدفوعات-النزلاء'),
      extraHeaderLine: 'مارينا هوتيل | $dateStr',
      buildContent: (fonts) {
        final List<pw.Widget> pdfContent = [
          // ─── ملخص عام ───
          epdf.EnhancedPdfUtils.buildInfoCard(
            title: 'ملخص التقرير',
            fonts: fonts,
            content: [
              _buildPdfInfoRow(fonts, 'تاريخ التقرير:', dateStr),
              _buildPdfInfoRow(
                fonts,
                'عدد النزلاء:',
                '${filtered.length}',
                valueColor: const PdfColor(0.0, 0.4, 0.8),
              ),
              _buildPdfInfoRow(
                fonts,
                'إجمالي المستحق:',
                '${CurrencyFormatter.formatAmount(totalDue)} ريال',
                valueColor: const PdfColor(0.6, 0.4, 0.0),
              ),
              _buildPdfInfoRow(
                fonts,
                'إجمالي المحصل:',
                '${CurrencyFormatter.formatAmount(totalPaid)} ريال',
                valueColor: const PdfColor(0.0, 0.6, 0.2),
              ),
              _buildPdfInfoRow(
                fonts,
                'إجمالي المتبقي:',
                '${CurrencyFormatter.formatAmount(totalRemaining)} ريال',
                valueColor: const PdfColor(0.9, 0.3, 0.1),
              ),
              if (totalCredit > 0)
                _buildPdfInfoRow(
                  fonts,
                  'إجمالي الزيادة:',
                  '${CurrencyFormatter.formatAmount(totalCredit)} ريال',
                  valueColor: const PdfColor(0.0, 0.6, 0.6),
                ),
            ],
          ),
        ];

        // ─── بطاقة لكل نزيل ───
        for (final b in filtered) {
          final actualDays = _getActualDaysSpent(b);
          final coverage = _calculateCoverage(b);
          final nightlyRate = _getAverageNightlyRate(b);

          pdfContent.add(pw.SizedBox(height: 12));
          pdfContent.add(
            epdf.EnhancedPdfUtils.buildInfoCard(
              title: 'غرفة ${b.roomNumber} — ${b.guestName}',
              fonts: fonts,
              content: [
                _buildPdfInfoRow(
                  fonts,
                  'تاريخ الوصول:',
                  _dateFormatter.format(coverage.checkinDate),
                ),
                _buildPdfInfoRow(
                  fonts,
                  'المغادرة المتوقعة:',
                  coverage.formatDate(coverage.manualCheckoutDate),
                ),
                _buildPdfInfoRow(fonts, 'الأيام المقضية:', '$actualDays يوم'),
                _buildPdfInfoRow(
                  fonts,
                  'سعر الليلة:',
                  '${CurrencyFormatter.formatAmount(nightlyRate)} ريال',
                ),
                // ✅ عرض الإجمالي والمبلغ المتبقي في سطر واحد
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'إجمالي العقد:',
                            style: pw.TextStyle(
                              font: fonts.regular,
                              fontSize: 10,
                              color: const PdfColor(0.15, 0.15, 0.15),
                            ),
                          ),
                          pw.Text(
                            '${CurrencyFormatter.formatAmount(b.totalDueCached)} ريال',
                            style: pw.TextStyle(
                              font: fonts.bold,
                              fontSize: 10,
                              color: const PdfColor(0, 0, 0),
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 12),
                    pw.Expanded(
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            b.remainingBalanceCached < 0
                                ? 'المتبقي (له):'
                                : 'المتبقي (عليه):',
                            style: pw.TextStyle(
                              font: fonts.bold,
                              fontSize: 10,
                              color: b.remainingBalanceCached < 0
                                  ? const PdfColor(0.0, 0.6, 0.3)
                                  : const PdfColor(0.9, 0.2, 0.2),
                            ),
                          ),
                          pw.Text(
                            '${CurrencyFormatter.formatAmount(b.remainingBalanceCached.abs())} ريال',
                            style: pw.TextStyle(
                              font: fonts.bold,
                              fontSize: 10,
                              color: b.remainingBalanceCached < 0
                                  ? const PdfColor(0.0, 0.6, 0.3)
                                  : const PdfColor(0.9, 0.2, 0.2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.Divider(
                  color: const PdfColor(0.85, 0.85, 0.85),
                  thickness: 0.3,
                ),
                _buildPdfInfoRow(
                  fonts,
                  'إجمالي المدفوع:',
                  '${CurrencyFormatter.formatAmount(b.totalPaidCached)} ريال',
                  valueColor: const PdfColor(0.0, 0.5, 0.2),
                ),
                if (coverage.hasPayments) ...[
                  pw.Divider(
                    color: const PdfColor(0.8, 0.8, 0.8),
                    thickness: 0.5,
                  ),
                  _buildPdfInfoRow(
                    fonts,
                    'المغادرة التلقائية:',
                    _dateFormatter.format(coverage.autoCheckoutDate),
                    valueColor: const PdfColor(0.0, 0.4, 0.7),
                  ),
                  _buildPdfInfoRow(
                    fonts,
                    'الليالي المدفوعة:',
                    '${coverage.totalPaidNights} ليلة',
                  ),
                  if (coverage.isAutoExtended)
                    _buildPdfInfoRow(
                      fonts,
                      'تمديد تلقائي:',
                      '+${coverage.extraNightsBeyondManual} يوم',
                      valueColor: const PdfColor(0.0, 0.7, 0.3),
                    ),
                  if (coverage.uncoveredDays > 0)
                    _buildPdfInfoRow(
                      fonts,
                      'أيام غير مغطاة:',
                      '${coverage.uncoveredDays} ليلة',
                      valueColor: const PdfColor(0.9, 0.3, 0.1),
                    ),
                ],
              ],
            ),
          );
        }

        return pdfContent;
      },
    );

    await ReportPdfBuilder.buildAndShare(config);
  }
}
