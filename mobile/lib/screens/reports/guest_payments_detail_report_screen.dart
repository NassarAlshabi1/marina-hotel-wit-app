import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart' hide PdfColors;
import 'package:pdf/widgets.dart' as pw;
import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/status_utils.dart';
import '../../utils/report_pdf_builder.dart';
import '../../utils/enhanced_pdf_utils.dart' as epdf;
import '../../services/booking_derived_fields_service.dart';
import '../../utils/time.dart';

/// نموذج بيانات تغطية الرصيد الزائد للأيام المتبقية حتى المغادرة المتوقعة
/// يحتسب بشكل تلقائي كم يوم من الأيام القادمة يغطيه المبلغ المدفوع زيادة
class _CreditCoverageResult {
  const _CreditCoverageResult({
    required this.creditAmount,
    required this.nightlyRate,
    required this.daysCovered,
    required this.daysUntilCheckout,
    required this.fullyCovered,
    required this.surplusAmount,
  });

  /// مبلغ الرصيد الزائد (المدفوع زيادة)
  final double creditAmount;

  /// متوسط سعر الليلة
  final double nightlyRate;

  /// عدد الأيام التي يغطيها الرصيد الزائد
  final int daysCovered;

  /// إجمالي الأيام المتبقية حتى تاريخ المغادرة المتوقع
  final int daysUntilCheckout;

  /// هل الرصيد الزائد يغطي جميع الأيام المتبقية بالكامل؟
  final bool fullyCovered;

  /// المبلغ المتبقي من الرصيد الزائد بعد تغطية جميع الأيام (إن وجد)
  final double surplusAmount;

  /// هل يوجد رصيد زائد فعلي؟
  bool get hasCredit => creditAmount > 0;

  /// نسبة التغطية من الأيام المتبقية (0.0 - 1.0)
  double get coverageRatio => daysUntilCheckout > 0
      ? (daysCovered / daysUntilCheckout).clamp(0.0, 1.0)
      : (fullyCovered ? 1.0 : 0.0);

  /// الأيام غير المغطاة (يحتاج دفع لها)
  int get uncoveredDays => daysUntilCheckout > 0
      ? (daysUntilCheckout - daysCovered).clamp(0, daysUntilCheckout)
      : 0;

  /// تكلفة الأيام غير المغطاة
  double get uncoveredCost => uncoveredDays * nightlyRate;
}

/// تقرير تفصيلي لمدفوعات النزلاء مع حساب عدد الأيام والرصيد المتبقي للأيام القادمة
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

  /// حساب الأيام المقضية فعلياً بناءً على قاعدة الساعة 14:00
  int _getActualDaysSpent(Booking b) {
    final checkin = DateTime.tryParse(b.checkinDate) ?? DateTime.now();
    // إذا غادر بالفعل نستخدم تاريخ المغادرة الفعلي، وإلا نستخدم الوقت الحالي
    final end = (b.actualCheckout != null && b.actualCheckout!.isNotEmpty)
        ? DateTime.tryParse(b.actualCheckout!)
        : DateTime.now();
    
    return Time.nightsWithCutoff(checkin, checkout: end);
  }

  /// حساب الأيام المتبقية حتى تاريخ المغادرة المخطط (أو المتوقع)
  int _getDaysUntilCheckout(Booking b) {
    if (b.checkoutDate == null || b.checkoutDate!.isEmpty) return 0;
    final checkout = DateTime.tryParse(b.checkoutDate!);
    if (checkout == null) return 0;
    
    final now = DateTime.now();
    if (checkout.isBefore(now)) return 0; // انتهت المدة المخططة
    
    // حساب الأيام من الآن حتى موعد المغادرة المخطط
    return Time.nightsWithCutoff(now, checkout: checkout);
  }

  /// حساب متوسط سعر الليلة الواحدة للحجز
  double _getAverageNightlyRate(Booking b) {
    final nights = b.calculatedNights > 0 ? b.calculatedNights : 1;
    return b.totalDueCached / nights;
  }

  /// حساب عدد الأيام التي يغطيها الرصيد المتبقي (المدفوع زيادة)
  /// يربط تلقائياً المبلغ الزائد بالأيام المتبقية حتى تاريخ المغادرة المتوقع
  _CreditCoverageResult _getCreditCoverage(Booking b) {
    // إذا كان الرصيد المتبقي سالباً، فهذا يعني وجود مبلغ مدفوع زيادة (Credit)
    final credit = -b.remainingBalanceCached;
    if (credit <= 0) {
      return const _CreditCoverageResult(
        creditAmount: 0,
        nightlyRate: 0,
        daysCovered: 0,
        daysUntilCheckout: 0,
        fullyCovered: false,
        surplusAmount: 0,
      );
    }

    final nightlyRate = _getAverageNightlyRate(b);
    if (nightlyRate <= 0) {
      return const _CreditCoverageResult(
        creditAmount: 0,
        nightlyRate: 0,
        daysCovered: 0,
        daysUntilCheckout: 0,
        fullyCovered: false,
        surplusAmount: 0,
      );
    }

    final daysUntilCheckout = _getDaysUntilCheckout(b);
    final daysCovered = (credit / nightlyRate).floor();
    final fullyCovered = daysUntilCheckout > 0 && daysCovered >= daysUntilCheckout;
    final double surplusAmount = fullyCovered
        ? credit - (daysUntilCheckout * nightlyRate)
        : 0.0;

    return _CreditCoverageResult(
      creditAmount: credit,
      nightlyRate: nightlyRate,
      daysCovered: daysCovered,
      daysUntilCheckout: daysUntilCheckout,
      fullyCovered: fullyCovered,
      surplusAmount: surplusAmount,
    );
  }

  /// هل الحجز تجاوز تاريخ المغادرة المخطط؟
  bool _isOverdue(Booking b) {
    return b.isOverdue;
  }

  /// حساب عدد أيام التأخير (بعد موعد المغادرة المخطط)
  int _getOverdueDays(Booking b) {
    if (!_isOverdue(b)) return 0;
    final checkout = DateTime.tryParse(b.checkoutDate ?? '');
    if (checkout == null) return 0;
    
    final now = DateTime.now();
    return Time.nightsWithCutoff(checkout, checkout: now);
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
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Booking> _filterAndSort(List<Booking> allBookings) {
    // فلترة حسب النشاط
    var filtered = _showOnlyActive
        ? allBookings.where((b) => StatusUtils.isBookingActive(b)).toList()
        : allBookings.where((b) => b.deletedAt == null).toList();

    // بحث
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((b) {
        return b.guestName.toLowerCase().contains(q) ||
            b.roomNumber.toLowerCase().contains(q) ||
            b.guestPhone.toLowerCase().contains(q);
      }).toList();
    }

    // فلترة حسب حالة الدفع
    if (_filterStatus == 'partial') {
      filtered = filtered.where((b) => b.totalPaidCached > 0 && b.remainingBalanceCached > 0).toList();
    } else if (_filterStatus == 'unpaid') {
      filtered = filtered.where((b) => b.totalPaidCached <= 0).toList();
    } else if (_filterStatus == 'overpaid') {
      filtered = filtered.where((b) => b.remainingBalanceCached < 0).toList();
    }

    // ترتيب
    filtered.sort((a, b) {
      if (_sortBy == 'room') {
        return a.roomNumber.compareTo(b.roomNumber);
      } else if (_sortBy == 'remaining') {
        return b.remainingBalanceCached.compareTo(a.remainingBalanceCached);
      } else {
        return a.guestName.compareTo(b.guestName);
      }
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

  Widget _buildSearchAndFilters() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          // بحث
          TextField(
            style: const TextStyle(fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: 'ابحث باسم النزيل أو رقم الغرفة...',
              hintStyle: TextStyle(fontWeight: FontWeight.normal, color: Colors.grey[500]),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () => setState(() => _searchQuery = ''),
                    )
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

          // فلتر الحالة
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

          // خيارات إضافية
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
                        Icon(
                          _showOnlyActive ? Icons.check_circle : Icons.circle_outlined,
                          size: 16,
                          color: _showOnlyActive ? Colors.blue : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'النزلاء الحاليين فقط',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _showOnlyActive ? Colors.blue.shade700 : Colors.grey.shade700,
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
                  onChanged: (v) {
                    if (v != null) setState(() => _sortBy = v);
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
      label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      selected: isSelected,
      onSelected: (_) => setState(() => _filterStatus = value),
      selectedColor: color.withOpacity(0.2),
      checkmarkColor: color,
      backgroundColor: Colors.grey.shade100,
      labelStyle: TextStyle(color: isSelected ? color : Colors.grey.shade700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }

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

  Widget _buildBookingCard(Booking b) {
    final actualDays = _getActualDaysSpent(b);
    final daysLeft = _getDaysUntilCheckout(b);
    final nightlyRate = _getAverageNightlyRate(b);
    final coverage = _getCreditCoverage(b);
    final isOverdue = _isOverdue(b);
    final overdueDays = _getOverdueDays(b);
    final overdueCost = _getOverdueCost(b);
    
    // حساب النسبة المئوية للدفع بناءً على المبلغ المستحق حتى الآن (الأيام المقضية)
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
          Container(
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
                  decoration: BoxDecoration(
                    color: Colors.blue.shade700,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'غرفة ${b.roomNumber}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.guestName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'سعر الليلة: ${CurrencyFormatter.formatAmount(nightlyRate)} ريال',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
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
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── التواريخ ───
                Row(
                  children: [
                    Expanded(child: _buildInfoItem(Icons.login, 'الدخول', b.checkinDate.split(' ').first)),
                    Expanded(child: _buildInfoItem(Icons.logout, 'المغادرة المتوقعة', b.checkoutDate?.split(' ').first ?? '---')),
                  ],
                ),
                const Divider(height: 24),

                // ─── الأيام ───
                Row(
                  children: [
                    Expanded(child: _buildDaysStat('المقضية', '$actualDays', Colors.blue)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildDaysStat('المتبقية', '$daysLeft', Colors.purple)),
                    const SizedBox(width: 8),
                    if (isCredit && coverage.hasCredit && coverage.daysUntilCheckout > 0)
                      Expanded(child: _buildDaysStat('مغطاة بالرصيد', '${coverage.daysCovered}/${coverage.daysUntilCheckout}', Colors.green))
                    else if (isCredit && coverage.hasCredit)
                      Expanded(child: _buildDaysStat('مغطاة بالرصيد', '${coverage.daysCovered}', Colors.green))
                    else
                      Expanded(child: _buildDaysStat('المخططة', '${b.calculatedNights}', Colors.grey)),
                  ],
                ),
                const SizedBox(height: 16),

                // ─── شريط تغطية الرصيد الزائد للأيام المتبقية (يظهر فقط عند وجود رصيد زائد وأيام متبقية) ───
                if (coverage.hasCredit && coverage.daysUntilCheckout > 0) ...[
                  _buildCreditCoverageBar(coverage),
                  const SizedBox(height: 16),
                ],

                // ─── المبالغ والتقدم ───
                Container(
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
                              isCredit ? Colors.green.shade800 : Colors.red.shade800
                            )
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ─── تنبيهات التأخير ───
                if (isOverdue && overdueDays > 0) ...[
                  const SizedBox(height: 12),
                  Container(
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
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

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
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 10, color: color.withOpacity(0.8), fontWeight: FontWeight.bold)),
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

  /// شريط تغطية الرصيد الزائد - يعرض بشكل مرئي كم يوم من الأيام المتبقية مغطى بالرصيد
  Widget _buildCreditCoverageBar(_CreditCoverageResult coverage) {
    final isFull = coverage.fullyCovered;
    final ratio = coverage.coverageRatio;
    final totalDays = coverage.daysUntilCheckout;
    final barColor = isFull ? Colors.green : Colors.teal;
    final bgColor = isFull ? Colors.green.shade100 : Colors.teal.shade50;

    // بناء النص التوضيحي حسب الحالة
    String description;
    IconData icon;
    if (isFull) {
      description = 'الرصيد الزائد يغطي جميع الأيام المتبقية (${coverage.daysUntilCheckout} يوم)';
      icon = Icons.verified;
      if (coverage.surplusAmount > 0) {
        description += ' + رصيد فائض ${CurrencyFormatter.formatAmount(coverage.surplusAmount)} ريال';
      }
    } else if (coverage.uncoveredDays > 0) {
      description = 'يغطي ${coverage.daysCovered} يوم من ${coverage.daysUntilCheckout} متبقي | '
          '${coverage.uncoveredDays} يوم غير مغطاة (تحتاج ${CurrencyFormatter.formatAmount(coverage.uncoveredCost)} ريال)';
      icon = Icons.info_outline;
    } else {
      description = 'يغطي ${coverage.daysCovered} يوم إضافي بالكامل';
      icon = Icons.check_circle_outline;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: barColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // العنوان مع الأيقونة
          Row(
            children: [
              Icon(icon, size: 18, color: barColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تغطية الرصيد الزائد للأيام القادمة',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: barColor.shade900),
                ),
              ),
              Text(
                '${(ratio * 100).toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: barColor),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // شريط التقدم المرئي - يمثل كل قسم يوماً
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: List.generate(totalDays, (index) {
                final isCovered = index < coverage.daysCovered;
                return Expanded(
                  flex: 1,
                  child: Container(
                    height: 10,
                    margin: EdgeInsets.only(
                      left: index < totalDays - 1 ? 2 : 0,
                      right: index > 0 ? 2 : 0,
                    ),
                    decoration: BoxDecoration(
                      color: isCovered ? barColor : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 6),

          // تفسير مرئي: أيام مغطاة / أيام غير مغطاة
          if (totalDays > 0 && !isFull)
            Row(
              children: [
                Container(width: 12, height: 10, decoration: BoxDecoration(color: barColor, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 4),
                Text('مغطاة (${coverage.daysCovered})', style: TextStyle(fontSize: 9, color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                Container(width: 12, height: 10, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 4),
                Text('غير مغطاة (${coverage.uncoveredDays})', style: TextStyle(fontSize: 9, color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
              ],
            ),

          const SizedBox(height: 6),

          // النص التفصيلي
          Text(
            description,
            style: TextStyle(fontSize: 11, color: barColor.shade800, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  /// تصدير كشف حساب النزيل بصيغة PDF احترافية
  Future<void> _exportGuestStatementPdf(Booking b) async {
    final payments = await ref.read(paymentsRepoProvider).paymentsByBooking(b.id).first;
    final actualDays = _getActualDaysSpent(b);
    final nightlyRate = _getAverageNightlyRate(b);
    final costSoFar = actualDays * nightlyRate;
    final coverage = _getCreditCoverage(b);
    final daysLeft = _getDaysUntilCheckout(b);
    
    final config = ReportPdfConfig(
      title: 'كشف حساب نزيل تفصيلي',
      fileName: ReportPdfBuilder.generateFileName('كشف-حساب-${b.guestName}'),
      extraHeaderLine: 'النزيل: ${b.guestName} | غرفة: ${b.roomNumber}',
      buildContent: (fonts) {
        // بناء محتوى PDF ديناميكي حسب وجود رصيد زائد
        final List<pw.Widget> pdfContent = [
          // ملخص الحساب والمدة
          epdf.EnhancedPdfUtils.buildInfoCard(
            title: 'ملخص الحساب والمدة الزمانية',
            fonts: fonts,
            content: [
              _buildPdfInfoRow(fonts, 'تاريخ الوصول:', b.checkinDate.split(' ').first),
              _buildPdfInfoRow(fonts, 'تاريخ المغادرة المتوقع:', b.checkoutDate?.split(' ').first ?? '---'),
              _buildPdfInfoRow(fonts, 'عدد الأيام المقضية حتى الآن:', '$actualDays يوم'),
              _buildPdfInfoRow(fonts, 'الأيام المتبقية حتى المغادرة:', '$daysLeft يوم'),
              _buildPdfInfoRow(fonts, 'سعر الغرفة لليلة الواحدة:', '${CurrencyFormatter.formatAmount(nightlyRate)} ريال'),
              pw.Divider(color: PdfColor(0.8, 0.8, 0.8), thickness: 0.5),
              _buildPdfInfoRow(fonts, 'إجمالي تكلفة الإقامة حتى الآن:', '${CurrencyFormatter.formatAmount(costSoFar)} ريال'),
              _buildPdfInfoRow(fonts, 'إجمالي المبالغ المدفوعة:', '${CurrencyFormatter.formatAmount(b.totalPaidCached)} ريال'),
              _buildPdfInfoRow(
                fonts, 
                b.remainingBalanceCached < 0 ? 'الرصيد المتبقي (له):' : 'الرصيد المتبقي (عليه):', 
                '${CurrencyFormatter.formatAmount(b.remainingBalanceCached.abs())} ريال',
                valueColor: b.remainingBalanceCached < 0 ? PdfColor(0.0, 0.7, 0.3) : PdfColor(0.9, 0.2, 0.2)
              ),
            ],
          ),
        ];

        // إضافة قسم تغطية الرصيد الزائد فقط إذا وُجد رصيد زائد وأيام متبقية
        if (coverage.hasCredit && coverage.daysUntilCheckout > 0) {
          pdfContent.add(pw.SizedBox(height: 16));
          
          final coveragePercent = (coverage.coverageRatio * 100).toStringAsFixed(0);
          String coverageText;
          if (coverage.fullyCovered) {
            coverageText = 'الرصيد الزائد (${CurrencyFormatter.formatAmount(coverage.creditAmount)} ريال) يغطي جميع الأيام المتبقية بالكامل (${coverage.daysUntilCheckout} يوم)';
            if (coverage.surplusAmount > 0) {
              coverageText += ' مع رصيد فائض قدره ${CurrencyFormatter.formatAmount(coverage.surplusAmount)} ريال';
            }
          } else {
            coverageText = 'يغطي ${coverage.daysCovered} يوم من ${coverage.daysUntilCheckout} يوم متبقي ($coveragePercent%)'
                ' | ${coverage.uncoveredDays} يوم غير مغطاة تحتاج ${CurrencyFormatter.formatAmount(coverage.uncoveredCost)} ريال';
          }
          
          pdfContent.add(
            epdf.EnhancedPdfUtils.buildInfoCard(
              title: 'تغطية الرصيد الزائد للأيام القادمة',
              fonts: fonts,
              content: [
                _buildPdfInfoRow(fonts, 'مبلغ الرصيد الزائد:', '${CurrencyFormatter.formatAmount(coverage.creditAmount)} ريال', valueColor: PdfColor(0.0, 0.6, 0.3)),
                _buildPdfInfoRow(fonts, 'الأيام التي يغطيها:', '${coverage.daysCovered} يوم'),
                _buildPdfInfoRow(fonts, 'الأيام المتبقية حتى المغادرة:', '${coverage.daysUntilCheckout} يوم'),
                _buildPdfInfoRow(fonts, 'نسبة التغطية:', '$coveragePercent%'),
                if (!coverage.fullyCovered) ...[
                  pw.Divider(color: PdfColor(0.8, 0.8, 0.8), thickness: 0.5),
                  _buildPdfInfoRow(fonts, 'الأيام غير المغطاة:', '${coverage.uncoveredDays} يوم', valueColor: PdfColor(0.9, 0.3, 0.1)),
                  _buildPdfInfoRow(fonts, 'المبلغ المطلوب للأيام غير المغطاة:', '${CurrencyFormatter.formatAmount(coverage.uncoveredCost)} ريال', valueColor: PdfColor(0.9, 0.3, 0.1)),
                ],
                if (coverage.fullyCovered && coverage.surplusAmount > 0) ...[
                  pw.Divider(color: PdfColor(0.8, 0.8, 0.8), thickness: 0.5),
                  _buildPdfInfoRow(fonts, 'رصيد فائض بعد التغطية الكاملة:', '${CurrencyFormatter.formatAmount(coverage.surplusAmount)} ريال', valueColor: PdfColor(0.0, 0.5, 0.8)),
                ],
                pw.SizedBox(height: 4),
                pw.Text(coverageText, style: pw.TextStyle(font: fonts.regular, fontSize: 9, color: PdfColor(0.2, 0.4, 0.2))),
              ],
            ),
          );
        }

        pdfContent.addAll([
          pw.SizedBox(height: 20),
          
          // جدول المدفوعات
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
          
          // التذييل والختم
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('ملاحظات:', style: pw.TextStyle(font: fonts.bold, fontSize: 10)),
                  pw.Text('يُحتسب اليوم الفندقي من الساعة 2:00 ظهراً.', style: pw.TextStyle(font: fonts.regular, fontSize: 9)),
                  pw.Text('أي تأخير في المغادرة بعد هذا الوقت يُحتسب يوماً إضافياً.', style: pw.TextStyle(font: fonts.regular, fontSize: 9)),
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
              style: pw.TextStyle(font: fonts.regular, fontSize: 10, color: PdfColor(0.4, 0.4, 0.4), fontStyle: pw.FontStyle.italic)
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
