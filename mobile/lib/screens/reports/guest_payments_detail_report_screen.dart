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

/// تقرير تفصيلي لمدفوعات النزلاء مع حساب الأيام والمبالغ وتاريخ المغادرة التلقائي
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
  StayBalanceResult _calculateCoverage(Booking b) {
    return StayBalanceCalculator.calculate(b);
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
      title: 'تقرير مدفوعات النزلاء التفصيلي',
      actions: [
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
      padding: const EdgeInsets.all(12),
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
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),
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
          padding: const EdgeInsets.all(16),
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
            padding: const EdgeInsets.all(12),
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
    final nightlyRate = _getAverageNightlyRate(b);
    final isOverdue = _isOverdue(b);
    final overdueDays = _getOverdueDays(b);
    final overdueCost = _getOverdueCost(b);

    // حساب النسبة المئوية لتغطية التكاليف الحالية
    final costSoFar = actualDays * nightlyRate;
    final paidPercent = costSoFar > 0 ? (b.totalPaidCached / costSoFar * 100) : 100.0;

    final remaining = b.remainingBalanceCached;
    final isCredit = remaining < 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          // ─── رأس البطاقة ───
          _buildCardHeader(b, nightlyRate),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── التواريخ: الدخول + المغادرة اليدوية + المغادرة التلقائية ───
                _buildDatesSection(b, coverage),

                const Divider(height: 24),

                // ─── الأيام ───
                _buildDaysSection(b, actualDays, coverage),

                const SizedBox(height: 16),

                // ─── شريط التغطية بالتواريخ (يظهر دائماً عند وجود مدفوعات) ───
                if (coverage.hasPayments) ...[
                  _buildDateDrivenCoverageBar(coverage),
                  const SizedBox(height: 16),
                ],

                // ─── المبالغ والتقدم ───
                _buildFinancialSection(b, nightlyRate, paidPercent, isCredit, remaining),

                // ─── تنبيهات التأخير ───
                if (isOverdue && overdueDays > 0) ...[
                  const SizedBox(height: 12),
                  _buildOverdueAlert(overdueDays, overdueCost),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
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

  // ─── قسم التواريخ: يعرض 3 تواريخ (الدخول / اليدوية / التلقائية) ───

  Widget _buildDatesSection(Booking b, StayBalanceResult coverage) {
    return Column(
      children: [
        // الصف الأول: الدخول + المغادرة المتوقعة اليدوية
        Row(
          children: [
            Expanded(child: _buildInfoItem(Icons.login, 'الدخول', _dateFormatter.format(coverage.checkinDate))),
            Expanded(child: _buildInfoItem(Icons.event, 'المغادرة المتوقعة', coverage.formatDate(coverage.manualCheckoutDate))),
          ],
        ),

        // الصف الثاني: تاريخ المغادرة التلقائي (يظهر فقط عند وجود مدفوعات)
        if (coverage.hasPayments) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: coverage.isAutoExtended ? Colors.green.shade50 : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: coverage.isAutoExtended ? Colors.green.shade200 : Colors.blue.shade200,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  coverage.isAutoExtended ? Icons.autorenew : Icons.calculate_outlined,
                  size: 20,
                  color: coverage.isAutoExtended ? Colors.green.shade700 : Colors.blue.shade700,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'المغادرة التلقائية (محسوبة)',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: coverage.isAutoExtended ? Colors.green.shade700 : Colors.blue.shade700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            _dateFormatter.format(coverage.autoCheckoutDate),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: coverage.isAutoExtended ? Colors.green.shade900 : Colors.blue.shade900,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '(${coverage.totalPaidNights} ليلة مدفوعة)',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (coverage.isAutoExtended)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade700,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '+${coverage.extraNightsBeyondManual} يوم',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ─── قسم الأيام ───

  Widget _buildDaysSection(Booking b, int actualDays, StayBalanceResult coverage) {
    return Row(
      children: [
        Expanded(child: _buildDaysStat('المقضية', '$actualDays', Colors.blue)),
        const SizedBox(width: 8),
        Expanded(child: _buildDaysStat('المتبقية', '${coverage.manualNightsRemaining}', Colors.purple)),
        const SizedBox(width: 8),
        if (coverage.isAutoExtended)
          Expanded(child: _buildDaysStat('إضافية مغطاة', '+${coverage.extraNightsBeyondManual}', Colors.green))
        else if (coverage.hasPayments && coverage.manualNightsRemaining > 0)
          Expanded(child: _buildDaysStat('غير مغطاة', '${coverage.uncoveredDays}', Colors.orange))
        else
          Expanded(child: _buildDaysStat('المخططة', '${b.calculatedNights}', Colors.grey)),
      ],
    );
  }

  // ─── شريط التغطية بالتواريخ الفعلية ───

  Widget _buildDateDrivenCoverageBar(StayBalanceResult coverage) {
    final isExtended = coverage.isAutoExtended;
    final barColor = isExtended ? Colors.green : Colors.teal;
    final bgColor = isExtended ? Colors.green.shade50 : Colors.teal.shade50;

    // بناء النص التوضيحي حسب الحالة
    String titleText;
    String description;
    IconData icon;

    if (isExtended) {
      titleText = 'تغطية كاملة مع تمديد تلقائي';
      icon = Icons.verified;
      description = 'المدفوع التراكمي (${CurrencyFormatter.formatAmount(coverage.totalPaid)} ريال) يغطي ${coverage.totalPaidNights} ليلة '
          'حتى ${coverage.formatDate(coverage.autoCheckoutDate)}';
      if (coverage.surplusAfterAllNights > 0) {
        description += ' | فائض ${CurrencyFormatter.formatAmount(coverage.surplusAfterAllNights)} ريال';
      }
    } else if (coverage.rawRemainingBalance > 0 && coverage.manualNightsRemaining > 0) {
      titleText = 'تغطية جزئية - تحتاج دفع إضافي';
      icon = Icons.info_outline;
      description = 'المدفوع يغطي ${coverage.totalPaidNights} ليلة | '
          '${coverage.uncoveredDays} ليلة متبقية تحتاج ${CurrencyFormatter.formatAmount(coverage.uncoveredCost)} ريال';
    } else if (coverage.rawRemainingBalance <= 0) {
      titleText = 'مغطاة بالكامل';
      icon = Icons.check_circle;
      description = 'المدفوعات تغطي جميع الأيام حتى ${coverage.formatDate(coverage.manualCheckoutDate)}';
      if (coverage.surplusAfterAllNights > 0) {
        description += ' | فائض ${CurrencyFormatter.formatAmount(coverage.surplusAfterAllNights)} ريال';
      }
    } else {
      titleText = 'حالة التغطية';
      icon = Icons.account_balance_wallet;
      description = coverage.isAutoExtended
          ? 'المدفوعات تغطي ${coverage.extraNightsBeyondManual} يوم إضافي حتى ${coverage.formatDate(coverage.autoCheckoutDate)}'
          : 'الرصيد الفعلي: ${CurrencyFormatter.formatAmount(coverage.effectiveBalance)} ريال';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: barColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // العنوان
          Row(
            children: [
              Icon(icon, size: 18, color: barColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(titleText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: barColor.shade900)),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // الخط الزمني المرئي بالتواريخ
          _buildTimelineVisualization(coverage, barColor),

          const SizedBox(height: 8),

          // النص التفصيلي
          Text(description, style: TextStyle(fontSize: 11, color: barColor.shade800, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  /// خط زمني مرئي يعرض الفترة المغطاة والتواريخ الفعلية
  Widget _buildTimelineVisualization(StayBalanceResult coverage, Color barColor) {
    final checkinStr = _dateFormatter.format(coverage.checkinDate);
    final autoStr = _dateFormatter.format(coverage.autoCheckoutDate);
    final manualStr = coverage.formatDate(coverage.manualCheckoutDate);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // صف 1: تاريخ الدخول → تاريخ المغادرة التلقائية
          Row(
            children: [
              Expanded(
                child: _buildTimelineLabel('الدخول', checkinStr, Colors.blue),
              ),
              Expanded(
                child: Center(
                  child: Icon(Icons.arrow_forward, size: 16, color: Colors.grey.shade400),
                ),
              ),
              Expanded(
                child: _buildTimelineLabel('مغطى حتى', autoStr, barColor),
              ),
            ],
          ),

          // شريط التقدم: الفترة المدفوعة
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: coverage.hasPayments ? (coverage.totalPaidNights / (coverage.totalPaidNights + coverage.uncoveredDays).clamp(1, 9999)).clamp(0.0, 1.0) : 0,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),

          // صف 2: يظهر فقط عند وجود تمديد
          if (coverage.isAutoExtended) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildTimelineLabel('متوقع يدوياً', manualStr, Colors.orange),
                ),
                Expanded(
                  child: Center(
                    child: Icon(Icons.arrow_forward, size: 16, color: Colors.green.shade400),
                  ),
                ),
                Expanded(
                  child: _buildTimelineLabel('تمديد تلقائي (+${coverage.extraNightsBeyondManual})', autoStr, Colors.green),
                ),
              ],
            ),
          ],

          // صف 3: يظهر عند وجود أيام غير مغطاة
          if (!coverage.isAutoExtended && coverage.uncoveredDays > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.orange.shade100),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, size: 14, color: Colors.orange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${coverage.uncoveredDays} ليلة غير مغطاة تحتاج ${CurrencyFormatter.formatAmount(coverage.uncoveredCost)} ريال',
                      style: const TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimelineLabel(String label, String date, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label, style: TextStyle(fontSize: 8, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(date, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ─── قسم المبالغ المالية ───

  Widget _buildFinancialSection(Booking b, double nightlyRate, double paidPercent, bool isCredit, double remaining) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
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
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (paidPercent / 100).clamp(0, 1),
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(paidPercent >= 100 ? Colors.green : Colors.orange),
            ),
          ),
          const SizedBox(height: 16),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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

        // ─── قسم تاريخ المغادرة التلقائي (يظهر دائماً عند وجود مدفوعات) ───
        if (coverage.hasPayments) {
          pdfContent.add(pw.SizedBox(height: 16));

          pdfContent.add(
            epdf.EnhancedPdfUtils.buildInfoCard(
              title: coverage.isAutoExtended
                  ? 'تاريخ المغادرة التلقائية - تمديد تلقائي'
                  : 'تاريخ المغادرة التلقائية (محسوب من المدفوعات)',
              fonts: fonts,
              content: [
                _buildPdfInfoRow(fonts, 'إجمالي المدفوع التراكمي:', '${CurrencyFormatter.formatAmount(coverage.totalPaid)} ريال', valueColor: PdfColor(0.0, 0.5, 0.8)),
                _buildPdfInfoRow(fonts, 'عدد الليالي المدفوعة:', '${coverage.totalPaidNights} ليلة'),
                _buildPdfInfoRow(
                  fonts,
                  'تاريخ المغادرة التلقائية:',
                  _dateFormatter.format(coverage.autoCheckoutDate),
                  valueColor: PdfColor(0.0, 0.6, 0.3),
                ),
                if (coverage.surplusAfterAllNights > 0)
                  _buildPdfInfoRow(fonts, 'فائض بعد تغطية الليالي:', '${CurrencyFormatter.formatAmount(coverage.surplusAfterAllNights)} ريال', valueColor: PdfColor(0.0, 0.5, 0.8)),
                if (coverage.isAutoExtended) ...[
                  pw.Divider(color: PdfColor(0.8, 0.8, 0.8), thickness: 0.5),
                  _buildPdfInfoRow(fonts, 'المغادرة المتوقعة (يدوي):', coverage.formatDate(coverage.manualCheckoutDate)),
                  _buildPdfInfoRow(fonts, 'تمديد تلقائي:', '+${coverage.extraNightsBeyondManual} يوم', valueColor: PdfColor(0.0, 0.7, 0.3)),
                  _buildPdfInfoRow(fonts, 'التاريخ بعد التمديد:', _dateFormatter.format(coverage.autoCheckoutDate), valueColor: PdfColor(0.0, 0.7, 0.3)),
                ],
                if (!coverage.isAutoExtended && coverage.uncoveredDays > 0) ...[
                  pw.Divider(color: PdfColor(0.8, 0.8, 0.8), thickness: 0.5),
                  _buildPdfInfoRow(fonts, 'الأيام غير المغطاة:', '${coverage.uncoveredDays} ليلة', valueColor: PdfColor(0.9, 0.3, 0.1)),
                  _buildPdfInfoRow(fonts, 'المبلغ المطلوب:', '${CurrencyFormatter.formatAmount(coverage.uncoveredCost)} ريال', valueColor: PdfColor(0.9, 0.3, 0.1)),
                ],
              ],
            ),
          );
        }

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
}
