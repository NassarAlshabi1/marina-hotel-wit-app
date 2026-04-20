import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart' hide PdfColors;
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/status_utils.dart';
import '../../utils/report_pdf_builder.dart';
import '../../utils/enhanced_pdf_utils.dart' as epdf;
import '../../services/booking_derived_fields_service.dart';
import '../../services/stay_balance_calculator.dart';
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

  static final _dateFormatter = DateFormat('yyyy/MM/dd');

  /// حساب الأيام المقضية فعلياً بناءً على قاعدة الساعة 14:00
  int _getActualDaysSpent(Booking b) {
    final checkin = DateTime.tryParse(b.checkinDate) ?? DateTime.now();
    final end = (b.actualCheckout != null && b.actualCheckout!.isNotEmpty)
        ? DateTime.tryParse(b.actualCheckout!)
        : DateTime.now();
    return Time.nightsWithCutoff(checkin, checkout: end);
  }

  /// حساب الأيام المتبقية حتى تاريخ المغادرة المخطط
  int _getDaysUntilCheckout(Booking b) {
    if (b.checkoutDate == null || b.checkoutDate!.isEmpty) return 0;
    final checkout = DateTime.tryParse(b.checkoutDate!);
    if (checkout == null) return 0;
    final now = DateTime.now();
    if (checkout.isBefore(now)) return 0;
    return Time.nightsWithCutoff(now, checkout: checkout);
  }

  /// حساب متوسط سعر الليلة الواحدة للحجز
  double _getAverageNightlyRate(Booking b) {
    final nights = b.calculatedNights > 0 ? b.calculatedNights : 1;
    return b.totalDueCached / nights;
  }

  /// استخدام المحرك الموحد لحساب الرصيد والتاريخ التلقائي
  /// يمرّر تعديلات الأسعار من booking_price_adjustments للمحرك
  StayBalanceResult _calculateCoverage(Booking b) {
    final adjustments = _adjustmentsByBookingId[b.id];
    final filtered = StayBalanceCalculator.filterActiveAdjustments(b, adjustments ?? []);
    return StayBalanceCalculator.calculate(b, priceAdjustments: filtered);
  }

  /// هل الحجز تجاوز تاريخ المغادرة المخطط؟
  bool _isOverdue(Booking b) => b.isOverdue;

  /// حساب عدد أيام التأخير
  int _getOverdueDays(Booking b) {
    if (!_isOverdue(b)) return 0;
    final checkout = DateTime.tryParse(b.checkoutDate ?? '');
    if (checkout == null) return 0;
    return Time.nightsWithCutoff(checkout, checkout: DateTime.now());
  }

  /// تكلفة أيام التأخير
  double _getOverdueCost(Booking b) {
    final days = _getOverdueDays(b);
    if (days <= 0) return 0;
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
      final derivedService = BookingDerivedFieldsService(db);
      await derivedService.refreshAllActiveBookings();

      // جلب جميع تعديلات الأسعار النشطة وتجميعها حسب معرّف الحجز
      final allAdjustments = await (db.select(db.bookingPriceAdjustments)
            ..where((a) => a.isActive.equals(true))
            ..where((a) => a.deletedAt.isNull()))
          .get();

      final grouped = <int, List<BookingPriceAdjustment>>{};
      for (final adj in allAdjustments) {
        if (adj.bookingLocalId == null) continue;
        grouped.putIfAbsent(adj.bookingLocalId!, () => []);
        grouped[adj.bookingLocalId!]!.add(adj);
      }

      if (mounted) {
        setState(() {
          _adjustmentsByBookingId = grouped;
        });
      }
    } catch (e) {
      debugPrint('Error refreshing data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Booking> _filterAndSort(List<Booking> allBookings) {
    var filtered = _showOnlyActive
        ? allBookings.where((b) => StatusUtils.isBookingActive(b)).toList()
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
      filtered = filtered.where((b) => b.totalPaidCached > 0 && b.remainingBalanceCached > 0).toList();
    } else if (_filterStatus == 'unpaid') {
      filtered = filtered.where((b) => b.totalPaidCached <= 0).toList();
    } else if (_filterStatus == 'overpaid') {
      filtered = filtered.where((b) => b.remainingBalanceCached < 0).toList();
    }

    filtered.sort((a, b) {
      if (_sortBy == 'room') return a.roomNumber.compareTo(b.roomNumber);
      if (_sortBy == 'remaining') return b.remainingBalanceCached.compareTo(a.remainingBalanceCached);
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
          onPressed: () => _exportAllBookingsPdf(),
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
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : bookingsAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('خطأ في تحميل البيانات: $e')),
                    data: (bookings) => _buildReport(bookings),
                  ),
          ),
        ],
      ),
    );
  }

  // ───────────────────── الفلاتر والبحث ─────────────────────

  Widget _buildSearchAndFilters() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          TextField(
            style: const TextStyle(fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: 'ابحث باسم النزيل أو رقم الغرفة...',
              hintStyle: TextStyle(fontWeight: FontWeight.normal, color: Colors.grey[500]),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear, size: 20), onPressed: () => setState(() => _searchQuery = ''))
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                const SizedBox(width: 8),
                _buildFilterChip('دفع جزئي', 'partial', Colors.orange),
                const SizedBox(width: 8),
                _buildFilterChip('غير مدفوع', 'unpaid', Colors.red),
                const SizedBox(width: 8),
                _buildFilterChip('مدفوع زيادة', 'overpaid', Colors.green),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _showOnlyActive = !_showOnlyActive),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      color: _showOnlyActive ? Colors.blue.shade50 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _showOnlyActive ? Colors.blue.shade200 : Colors.grey.shade300),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_showOnlyActive ? Icons.check_circle : Icons.circle_outlined, size: 16, color: _showOnlyActive ? Colors.blue : Colors.grey),
                        const SizedBox(width: 8),
                        Text('النزلاء الحاليين فقط', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _showOnlyActive ? Colors.blue.shade700 : Colors.grey.shade700)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _sortBy,
                  isDense: true,
                  decoration: InputDecoration(
                    labelText: 'ترتيب حسب',
                    labelStyle: const TextStyle(fontSize: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  style: const TextStyle(fontSize: 12, color: Colors.black, fontWeight: FontWeight.bold),
                  items: const [
                    DropdownMenuItem(value: 'room', child: Text('رقم الغرفة')),
                    DropdownMenuItem(value: 'name', child: Text('اسم النزيل')),
                    DropdownMenuItem(value: 'remaining', child: Text('المبلغ المتبقي')),
                  ],
                  onChanged: (v) { if (v != null) setState(() => _sortBy = v); },
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
      label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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

  Widget _buildReport(List<Booking> allBookings) {
    final filtered = _filterAndSort(allBookings);

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text('لا توجد بيانات تطابق معايير البحث', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    final totalRemaining = filtered.fold(0.0, (s, b) => s + (b.remainingBalanceCached > 0 ? b.remainingBalanceCached : 0));
    final totalPaid = filtered.fold(0.0, (s, b) => s + b.totalPaidCached);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          color: Colors.blue.shade900,
          child: Row(
            children: [
              _buildSummaryItem('النزلاء', '${filtered.length}', Colors.white),
              const Spacer(),
              _buildSummaryItem('إجمالي المحصل', CurrencyFormatter.formatAmount(totalPaid), Colors.green.shade300),
              const Spacer(),
              _buildSummaryItem('إجمالي المتبقي', CurrencyFormatter.formatAmount(totalRemaining), Colors.orange.shade300),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(6),
            itemCount: filtered.length,
            itemBuilder: (context, index) => _buildBookingCard(filtered[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryItem(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: valueColor, fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  // ───────────────────── بطاقة الحجز ─────────────────────

  Widget _buildBookingCard(Booking b) {
    final actualDays = _getActualDaysSpent(b);
    final coverage = _calculateCoverage(b);
    final nightlyRate = coverage.effectiveNightlyRate > 0 ? coverage.effectiveNightlyRate : _getAverageNightlyRate(b);

    // المغادرة المخططة = المحسوبة من المدفوعات (autoCheckoutDate)
    final plannedCheckout = coverage.autoCheckoutDate;
    final paidNights = coverage.totalPaidNights;
    final isAutoOverdue = DateTime.now().isAfter(plannedCheckout) && coverage.hasPayments;
    final autoOverdueDays = isAutoOverdue ? Time.nightsWithCutoff(plannedCheckout, checkout: DateTime.now()) : 0;
    final autoOverdueCost = autoOverdueDays * nightlyRate;

    // حساب النسبة المئوية لتغطية التكاليف الحالية
    final costSoFar = actualDays * nightlyRate;
    final paidPercent = costSoFar > 0 ? (b.totalPaidCached / costSoFar * 100) : 100.0;

    final remaining = b.remainingBalanceCached;
    final isCredit = remaining < 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 3,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          // ─── رأس البطاقة ───
          _buildCardHeader(b, nightlyRate),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── التواريخ: الدخول + المغادرة المخططة (محسوبة من المدفوعات) ───
                _buildDatesSection(b, coverage),

                const Divider(height: 16),

                // ─── الأيام ───
                _buildDaysSection(b, actualDays, coverage),

                const SizedBox(height: 10),

                // ─── شريط التغطية ───
                _buildDateDrivenCoverageBar(b, coverage),
                const SizedBox(height: 10),

                // ─── المبالغ والتقدم ───
                _buildFinancialSection(b, nightlyRate, paidPercent, isCredit, remaining),

                // ─── تنبيه التمديد التلقائي عند تجاوز المغادرة المحسوبة ───
                if (isAutoOverdue && autoOverdueDays > 0) ...[
                  const SizedBox(height: 12),
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
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Colors.blue.shade700, borderRadius: BorderRadius.circular(8)),
            child: Text('غرفة ${b.roomNumber}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(b.guestName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis),
                Text('سعر الليلة: ${CurrencyFormatter.formatAmount(nightlyRate)} ريال', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
            onPressed: () => _exportGuestStatementPdf(b),
            tooltip: 'كشف حساب PDF',
          ),
        ],
      ),
    );
  }

  // ─── قسم التواريخ: المغادرة المخططة = محسوبة من المدفوعات والتكلفة ───

  Widget _buildDatesSection(Booking b, StayBalanceResult coverage) {
    // المغادرة المخططة محسوبة: المدفوع ÷ سعر الليلة = عدد الليالي المغطاة
    final plannedCheckout = coverage.autoCheckoutDate;
    final paidNights = coverage.totalPaidNights;
    final isAutoOverdue = DateTime.now().isAfter(plannedCheckout) && coverage.hasPayments;
    final autoOverdueDays = isAutoOverdue ? Time.nightsWithCutoff(plannedCheckout, checkout: DateTime.now()) : 0;

    return Column(
      children: [
        // الصف الأول: الدخول + عدد الليالي المدفوعة
        Row(
          children: [
            Expanded(child: _buildInfoItem(Icons.login, 'الدخول', _dateFormatter.format(coverage.checkinDate))),
            Expanded(child: _buildInfoItem(Icons.nights_stay, 'الليالي المدفوعة', '$paidNights ليلة')),
          ],
        ),

        // الصف الثاني: المغادرة المخططة (محسوبة من المدفوعات)
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isAutoOverdue ? Colors.orange.shade50 : Colors.blue.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isAutoOverdue ? Colors.orange.shade200 : Colors.blue.shade200,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isAutoOverdue ? Icons.autorenew : Icons.event_available,
                size: 20,
                color: isAutoOverdue ? Colors.orange.shade700 : Colors.blue.shade700,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAutoOverdue ? 'المغادرة المخططة (مُمدَّدة)' : 'المغادرة المخططة (محسوبة)',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isAutoOverdue ? Colors.orange.shade700 : Colors.blue.shade700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          _dateFormatter.format(plannedCheckout),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isAutoOverdue ? Colors.orange.shade900 : Colors.blue.shade900,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isAutoOverdue && autoOverdueDays > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade700,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '+$autoOverdueDays يوم تمديد',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── قسم الأيام ───

  Widget _buildDaysSection(Booking b, int actualDays, StayBalanceResult coverage) {
    final plannedCheckout = coverage.autoCheckoutDate;
    final isAutoOverdue = DateTime.now().isAfter(plannedCheckout) && coverage.hasPayments;
    final autoOverdueDays = isAutoOverdue ? Time.nightsWithCutoff(plannedCheckout, checkout: DateTime.now()) : 0;
    // الأيام المتبقية حتى المغادرة المخططة المحسوبة
    final nightsUntilPlanned = !isAutoOverdue && plannedCheckout.isAfter(DateTime.now())
        ? Time.nightsWithCutoff(DateTime.now(), checkout: plannedCheckout)
        : 0;

    return Row(
      children: [
        Expanded(child: _buildDaysStat('المقضية', '$actualDays', Colors.blue)),
        const SizedBox(width: 8),
        if (isAutoOverdue && autoOverdueDays > 0)
          Expanded(child: _buildDaysStat('إضافية (تمديد)', '+$autoOverdueDays', Colors.orange))
        else
          Expanded(child: _buildDaysStat('المتبقية', '$nightsUntilPlanned', Colors.purple)),
        const SizedBox(width: 8),
        Expanded(child: _buildDaysStat('المخططة', '${coverage.totalPaidNights}', Colors.grey)),
      ],
    );
  }

  // ─── شريط التغطية: مبني على المدفوعات (المخطط = محسوب من المدفوعات) ───

  Widget _buildDateDrivenCoverageBar(Booking b, StayBalanceResult coverage) {
    final plannedCheckout = coverage.autoCheckoutDate;
    final paidNights = coverage.totalPaidNights;
    final totalPaid = coverage.totalPaid;
    final nightlyRate = coverage.effectiveNightlyRate > 0 ? coverage.effectiveNightlyRate : _getAverageNightlyRate(b);
    final isAutoOverdue = DateTime.now().isAfter(plannedCheckout) && coverage.hasPayments;
    final autoOverdueDays = isAutoOverdue ? Time.nightsWithCutoff(plannedCheckout, checkout: DateTime.now()) : 0;
    final autoOverdueCost = autoOverdueDays * nightlyRate;
    final actualTotal = coverage.consumedCost + autoOverdueCost;
    final actualRemaining = actualTotal - totalPaid;

    Color barColor;
    Color bgColor;
    String titleText;
    String description;
    IconData icon;

    if (isAutoOverdue && autoOverdueDays > 0) {
      // تجاوز المغادرة المخططة المحسوبة → تمديد تلقائي
      barColor = Colors.orange;
      bgColor = Colors.orange.shade50;
      icon = Icons.autorenew;
      titleText = 'تمديد تلقائي (+$autoOverdueDays يوم)';
      description = 'تجاوز المغادرة المخططة | تكلفة التمديد: ${CurrencyFormatter.formatAmount(autoOverdueCost)} ريال'
          ' | إجمالي فعلي: ${CurrencyFormatter.formatAmount(actualTotal)} ريال';
      if (actualRemaining > 0) {
        description += ' | غير مدفوع: ${CurrencyFormatter.formatAmount(actualRemaining)} ريال';
      }
    } else if (coverage.effectiveBalance >= 0) {
      barColor = Colors.green;
      bgColor = Colors.green.shade50;
      icon = Icons.check_circle;
      titleText = 'مغطاة بالكامل';
      description = 'المدفوع (${CurrencyFormatter.formatAmount(totalPaid)} ريال) يغطي $paidNights ليلة'
          ' حتى ${coverage.formatDate(plannedCheckout)}';
      if (coverage.surplusAfterAllNights > 0) {
        description += ' | فائض ${CurrencyFormatter.formatAmount(coverage.surplusAfterAllNights)} ريال';
      }
    } else {
      barColor = Colors.teal;
      bgColor = Colors.teal.shade50;
      icon = Icons.info_outline;
      titleText = 'تغطية جزئية - تحتاج دفع إضافي';
      description = 'المدفوع ${CurrencyFormatter.formatAmount(totalPaid)} ريال يغطي $paidNights ليلة | '
          'التكلفة المستهلكة: ${CurrencyFormatter.formatAmount(coverage.consumedCost)} ريال';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: barColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text('$titleText — $description', style: TextStyle(fontSize: 10, color: barColor.shade800, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── قسم المبالغ المالية ───

  Widget _buildFinancialSection(Booking b, double nightlyRate, double paidPercent, bool isCredit, double remaining) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('تغطية التكاليف الحالية', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
              Text('${paidPercent.toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: paidPercent >= 100 ? Colors.green : Colors.orange)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (paidPercent / 100).clamp(0, 1),
              minHeight: 6,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(paidPercent >= 100 ? Colors.green : Colors.orange),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _buildAmountDetail('إجمالي العقد', b.totalDueCached, Colors.blue.shade900)),
              Expanded(child: _buildAmountDetail('إجمالي المدفوع', b.totalPaidCached, Colors.green.shade800)),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 20, color: Colors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'تجاوز موعد المغادرة بـ $overdueDays يوم (تكلفة إضافية: ${CurrencyFormatter.formatAmount(overdueCost)} ريال)',
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
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
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  Widget _buildDaysStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.8), fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildAmountDetail(String label, double value, Color color) {
    return Column(
      children: [
        Text(CurrencyFormatter.formatAmount(value), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.black54, fontWeight: FontWeight.w500)),
      ],
    );
  }

  // ───────────────────── تصدير PDF ─────────────────────

  Future<void> _exportGuestStatementPdf(Booking b) async {
    final payments = await ref.read(paymentsRepoProvider).paymentsByBooking(b.id).first;
    final actualDays = _getActualDaysSpent(b);
    final nightlyRate = _getAverageNightlyRate(b);
    final costSoFar = actualDays * nightlyRate;
    final coverage = _calculateCoverage(b);

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
              _buildPdfInfoRow(fonts, 'تاريخ الوصول:', _dateFormatter.format(coverage.checkinDate)),
              _buildPdfInfoRow(fonts, 'تاريخ المغادرة المتوقع (يدوي):', coverage.formatDate(coverage.manualCheckoutDate)),
              _buildPdfInfoRow(fonts, 'عدد الأيام المقضية حتى الآن:', '$actualDays يوم'),
              _buildPdfInfoRow(fonts, 'الأيام المتبقية حتى المغادرة:', '${coverage.manualNightsRemaining} يوم'),
              _buildPdfInfoRow(fonts, 'سعر الغرفة لليلة الواحدة:', '${CurrencyFormatter.formatAmount(nightlyRate)} ريال'),
              pw.Divider(color: PdfColor(0.8, 0.8, 0.8), thickness: 0.5),
              _buildPdfInfoRow(fonts, 'إجمالي تكلفة الإقامة حتى الآن:', '${CurrencyFormatter.formatAmount(costSoFar)} ريال'),
              _buildPdfInfoRow(fonts, 'إجمالي المبالغ المدفوعة:', '${CurrencyFormatter.formatAmount(b.totalPaidCached)} ريال'),
              _buildPdfInfoRow(
                fonts,
                b.remainingBalanceCached < 0 ? 'الرصيد المتبقي (له):' : 'الرصيد المتبقي (عليه):',
                '${CurrencyFormatter.formatAmount(b.remainingBalanceCached.abs())} ريال',
                valueColor: b.remainingBalanceCached < 0 ? PdfColor(0.0, 0.7, 0.3) : PdfColor(0.9, 0.2, 0.2),
              ),
            ],
          ),
        ];

        // ─── قسم المغادرة المخططة (محسوبة من المدفوعات) + التمديد عند التجاوز ───
        final plannedCheckout = coverage.autoCheckoutDate;
        final paidNights = coverage.totalPaidNights;
        final isAutoOverdue = DateTime.now().isAfter(plannedCheckout) && coverage.hasPayments;
        final autoOverdueDays = isAutoOverdue ? Time.nightsWithCutoff(plannedCheckout, checkout: DateTime.now()) : 0;
        final nightlyRate = coverage.effectiveNightlyRate > 0 ? coverage.effectiveNightlyRate : _getAverageNightlyRate(b);
        final autoOverdueCost = autoOverdueDays * nightlyRate;

        pdfContent.add(pw.SizedBox(height: 16));

        pdfContent.add(
          epdf.EnhancedPdfUtils.buildInfoCard(
            title: isAutoOverdue
                ? 'المغادرة المخططة (مُمدَّدة تلقائياً)'
                : 'المغادرة المخططة (محسوبة من المدفوعات)',
            fonts: fonts,
            content: [
              _buildPdfInfoRow(fonts, 'إجمالي المدفوع:', '${CurrencyFormatter.formatAmount(b.totalPaidCached)} ريال', valueColor: PdfColor(0.0, 0.5, 0.8)),
              _buildPdfInfoRow(fonts, 'سعر الليلة:', '${CurrencyFormatter.formatAmount(nightlyRate)} ريال'),
              _buildPdfInfoRow(fonts, 'الليالي المدفوعة:', '$paidNights ليلة'),
              _buildPdfInfoRow(
                fonts,
                'المغادرة المخططة:',
                _dateFormatter.format(plannedCheckout),
                valueColor: PdfColor(0.0, 0.6, 0.3),
              ),
              _buildPdfInfoRow(fonts, 'تكلفة الإقامة المستهلكة:', '${CurrencyFormatter.formatAmount(coverage.consumedCost)} ريال'),
              _buildPdfInfoRow(fonts, 'الرصيد الفعلي:', '${CurrencyFormatter.formatAmount(coverage.effectiveBalance)} ريال',
                  valueColor: coverage.effectiveBalance >= 0 ? PdfColor(0.0, 0.7, 0.3) : PdfColor(0.9, 0.3, 0.1)),
              if (isAutoOverdue && autoOverdueDays > 0) ...[
                pw.Divider(color: PdfColor(0.8, 0.8, 0.8), thickness: 0.5),
                _buildPdfInfoRow(fonts, 'تمديد تلقائي:', '+$autoOverdueDays يوم', valueColor: PdfColor(0.9, 0.5, 0.1)),
                _buildPdfInfoRow(fonts, 'تكلفة التمديد:', '${CurrencyFormatter.formatAmount(autoOverdueCost)} ريال', valueColor: PdfColor(0.9, 0.3, 0.1)),
                _buildPdfInfoRow(fonts, 'ملاحظة:', 'المغادرة يدوياً فقط — لا يتم إخراج النزيل تلقائياً', valueColor: PdfColor(0.4, 0.4, 0.4)),
              ],
              if (coverage.surplusAfterAllNights > 0)
                _buildPdfInfoRow(fonts, 'فائض:', '${CurrencyFormatter.formatAmount(coverage.surplusAfterAllNights)} ريال', valueColor: PdfColor(0.0, 0.7, 0.3)),
            ],
          ),
        );

        pdfContent.addAll([
          pw.SizedBox(height: 20),

          // ─── جدول المدفوعات ───
          pw.Text('سجل المدفوعات التفصيلي', style: pw.TextStyle(font: fonts.bold, fontSize: 14, color: PdfColor(0.0, 0.12, 0.36))),
          pw.SizedBox(height: 10),
          epdf.EnhancedPdfUtils.buildProfessionalTable(
            fonts: fonts,
            headers: ['التاريخ', 'المبلغ', 'طريقة الدفع', 'رقم المرجع', 'ملاحظات'],
            data: payments.map((p) => [
              p.paymentDate.split('T').first,
              CurrencyFormatter.formatAmount(p.amount),
              p.paymentMethod,
              p.referenceNumber ?? '---',
              p.notes ?? '',
            ]).toList(),
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
                  pw.Text('ملاحظات:', style: pw.TextStyle(font: fonts.bold, fontSize: 10)),
                  pw.Text('يُحتسب اليوم الفندقي من الساعة 2:00 ظهراً.', style: pw.TextStyle(font: fonts.regular, fontSize: 9)),
                  pw.Text('تاريخ المغادرة التلقائي يُحسب من إجمالي المدفوعات التراكمية مقسومة على سعر الليلة.', style: pw.TextStyle(font: fonts.regular, fontSize: 9)),
                  pw.Text('أي دفعة جديدة تُحدّث تاريخ المغادرة التلقائي فوراً.', style: pw.TextStyle(font: fonts.regular, fontSize: 9)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('ختم وتوقيع الإدارة', style: pw.TextStyle(font: fonts.bold, fontSize: 12)),
                  pw.SizedBox(height: 40),
                  pw.Container(width: 120, height: 1, color: PdfColor(0, 0, 0)),
                ],
              ),
            ],
          ),

          pw.SizedBox(height: 20),
          pw.Center(
            child: pw.Text(
              'شكراً لاختياركم فندق مارينا - نتمنى لكم إقامة سعيدة',
              style: pw.TextStyle(font: fonts.regular, fontSize: 10, color: PdfColor(0.4, 0.4, 0.4), fontStyle: pw.FontStyle.italic),
            ),
          ),
        ]);

        return pdfContent;
      },
    );

    await ReportPdfBuilder.buildAndShare(config);
  }

  pw.Widget _buildPdfInfoRow(epdf.ArabicPdfFonts fonts, String label, String value, {PdfColor? valueColor}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(font: fonts.regular, fontSize: 11, color: PdfColor(0.15, 0.15, 0.15))),
          pw.Text(value, style: pw.TextStyle(font: fonts.bold, fontSize: 11, color: valueColor ?? PdfColor(0, 0, 0))),
        ],
      ),
    );
  }

  // ───────────────────── تصدير التقرير العام PDF ─────────────────────

  Future<void> _exportAllBookingsPdf() async {
    final db = ref.read(databaseProvider);
    final allBookings = await (db.select(db.bookings)
          ..where((b) => b.deletedAt.isNull()))
        .get();

    final filtered = _filterAndSort(allBookings);
    if (filtered.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد بيانات للتصدير')),
        );
      }
      return;
    }

    final totalRemaining = filtered.fold(0.0, (s, b) => s + (b.remainingBalanceCached > 0 ? b.remainingBalanceCached : 0));
    final totalPaid = filtered.fold(0.0, (s, b) => s + b.totalPaidCached);

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
              _buildPdfInfoRow(fonts, 'عدد النزلاء:', '${filtered.length}', valueColor: PdfColor(0.0, 0.4, 0.8)),
              _buildPdfInfoRow(fonts, 'إجمالي المحصل:', '${CurrencyFormatter.formatAmount(totalPaid)} ريال', valueColor: PdfColor(0.0, 0.6, 0.2)),
              _buildPdfInfoRow(fonts, 'إجمالي المتبقي:', '${CurrencyFormatter.formatAmount(totalRemaining)} ريال', valueColor: PdfColor(0.9, 0.3, 0.1)),
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
                _buildPdfInfoRow(fonts, 'تاريخ الوصول:', _dateFormatter.format(coverage.checkinDate)),
                _buildPdfInfoRow(fonts, 'المغادرة المتوقعة:', coverage.formatDate(coverage.manualCheckoutDate)),
                _buildPdfInfoRow(fonts, 'الأيام المقضية:', '$actualDays يوم'),
                _buildPdfInfoRow(fonts, 'سعر الليلة:', '${CurrencyFormatter.formatAmount(nightlyRate)} ريال'),
                _buildPdfInfoRow(fonts, 'إجمالي العقد:', '${CurrencyFormatter.formatAmount(b.totalDueCached)} ريال'),
                _buildPdfInfoRow(fonts, 'إجمالي المدفوع:', '${CurrencyFormatter.formatAmount(b.totalPaidCached)} ريال', valueColor: PdfColor(0.0, 0.5, 0.2)),
                _buildPdfInfoRow(
                  fonts,
                  b.remainingBalanceCached < 0 ? 'رصيد للنزيل:' : 'المتبقي عليه:',
                  '${CurrencyFormatter.formatAmount(b.remainingBalanceCached.abs())} ريال',
                  valueColor: b.remainingBalanceCached < 0 ? PdfColor(0.0, 0.6, 0.3) : PdfColor(0.9, 0.2, 0.2),
                ),
                if (coverage.hasPayments) ...[
                  pw.Divider(color: PdfColor(0.8, 0.8, 0.8), thickness: 0.5),
                  _buildPdfInfoRow(fonts, 'المغادرة التلقائية:', _dateFormatter.format(coverage.autoCheckoutDate), valueColor: PdfColor(0.0, 0.4, 0.7)),
                  _buildPdfInfoRow(fonts, 'الليالي المدفوعة:', '${coverage.totalPaidNights} ليلة'),
                  if (coverage.isAutoExtended)
                    _buildPdfInfoRow(fonts, 'تمديد تلقائي:', '+${coverage.extraNightsBeyondManual} يوم', valueColor: PdfColor(0.0, 0.7, 0.3)),
                  if (coverage.uncoveredDays > 0)
                    _buildPdfInfoRow(fonts, 'أيام غير مغطاة:', '${coverage.uncoveredDays} ليلة', valueColor: PdfColor(0.9, 0.3, 0.1)),
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
