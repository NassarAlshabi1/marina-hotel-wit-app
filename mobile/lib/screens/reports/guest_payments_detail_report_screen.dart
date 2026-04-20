import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/status_utils.dart';
import '../../utils/report_pdf_builder.dart';
import '../../utils/enhanced_pdf_utils.dart' as epdf;
import '../../services/booking_derived_fields_service.dart';

/// تقرير تفصيلي لمدفوعات النزلاء مع حساب عدد الأيام والرصيد المتبقي للأيام القادمة
class GuestPaymentsDetailReportScreen extends ConsumerStatefulWidget {
  const GuestPaymentsDetailReportScreen({super.key});

  @override
  ConsumerState<GuestPaymentsDetailReportScreen> createState() =>
      _GuestPaymentsDetailReportScreenState();
}

class _GuestPaymentsDetailReportScreenState
    extends ConsumerState<GuestPaymentsDetailReportScreen> {
  final DateFormat _dateFmt = DateFormat('yyyy/MM/dd');
  String _searchQuery = '';
  String _filterStatus = 'all'; // all, partial, unpaid, overpaid
  String _sortBy = 'room'; // room, name, remaining
  bool _showOnlyActive = true;
  bool _isLoading = true;

  /// حساب الأيام المقضية فعلياً (من تاريخ الوصول إلى اليوم أو المغادرة)
  int _getActualDaysSpent(Booking b) {
    return b.calculatedNights;
  }

  /// حساب الأيام المتبقية حتى تاريخ المغادرة المخطط
  int _getDaysUntilCheckout(Booking b) {
    if (b.checkoutDate == null || b.checkoutDate!.isEmpty) return 0;
    final checkout = DateTime.tryParse(b.checkoutDate!);
    if (checkout == null) return 0;
    final now = DateTime.now();
    if (checkout.isBefore(now)) return 0; // انتهت المدة
    return checkout.difference(now).inDays;
  }

  /// حساب متوسط سعر الليلة الواحدة
  double _getAverageNightlyRate(Booking b) {
    if (b.calculatedNights <= 0) {
      // إذا لم يكمل ليلة بعد، نستخدم سعر الغرفة الافتراضي
      return b.totalDueCached; 
    }
    return b.totalDueCached / b.calculatedNights;
  }

  /// حساب عدد الأيام الممكنة بالرصيد المتبقي
  int _getDaysCoveredByRemaining(Booking b) {
    final remaining = b.remainingBalanceCached;
    if (remaining <= 0) return 0;
    final nightlyRate = _getAverageNightlyRate(b);
    if (nightlyRate <= 0) return 0;
    return (remaining / nightlyRate).floor();
  }

  /// حساب تكلفة الأيام المتبقية حتى تاريخ المغادرة
  double _getUpcomingDaysCost(Booking b) {
    final daysLeft = _getDaysUntilCheckout(b);
    if (daysLeft <= 0) return 0;
    final nightlyRate = _getAverageNightlyRate(b);
    return nightlyRate * daysLeft;
  }

  /// هل الحجز تجاوز تاريخ المغادرة؟
  bool _isOverdue(Booking b) {
    return b.isOverdue;
  }

  /// حساب عدد أيام التأخير
  int _getOverdueDays(Booking b) {
    if (!_isOverdue(b)) return 0;
    // إذا كان الحجز نشطاً وتجاوز تاريخ المغادرة
    if (b.actualCheckout == null || b.actualCheckout!.isEmpty) {
        final checkout = DateTime.tryParse(b.checkoutDate ?? '');
        if (checkout != null) {
            final now = DateTime.now();
            return now.difference(checkout).inDays;
        }
    }
    return 0;
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
    final db = ref.read(databaseProvider);
    final derivedService = BookingDerivedFieldsService(db);
    await derivedService.refreshAllActiveBookings();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  List<Booking> _filterAndSort(List<Booking> allBookings) {
    // فلترة حسب النشاط
    var filtered = _showOnlyActive
        ? allBookings.where((b) => StatusUtils.isBookingActive(b.status)).toList()
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
      filtered = filtered.where((b) => b.totalPaidCached >= b.totalDueCached && b.remainingBalanceCached <= 0).toList();
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
      title: 'تقرير مدفوعات النزلاء',
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
                  error: (e, _) => Center(child: Text('خطأ: $e')),
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
      color: Colors.grey.shade50,
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
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(25)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          const SizedBox(height: 8),

          // فلتر الحالة
          Row(
            children: [
              Expanded(child: _buildFilterChip('الكل', 'all', Colors.blue)),
              const SizedBox(width: 6),
              Expanded(child: _buildFilterChip('جزئي', 'partial', Colors.orange)),
              const SizedBox(width: 6),
              Expanded(child: _buildFilterChip('لم يدفع', 'unpaid', Colors.red)),
              const SizedBox(width: 6),
              Expanded(child: _buildFilterChip('مسدد', 'overpaid', Colors.green)),
            ],
          ),
          const SizedBox(height: 8),

          // خيارات إضافية
          Row(
            children: [
              Expanded(
                child: FilterChip(
                  label: const Text('النشطة فقط', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  selected: _showOnlyActive,
                  onSelected: (v) => setState(() => _showOnlyActive = v),
                  selectedColor: Colors.blue.withOpacity(0.15),
                  checkmarkColor: Colors.blue,
                  labelStyle: TextStyle(color: _showOnlyActive ? Colors.blue : null, fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _sortBy,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'ترتيب',
                    labelStyle: TextStyle(fontSize: 11),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  style: const TextStyle(fontSize: 11),
                  items: const [
                    DropdownMenuItem(value: 'room', child: Text('الغرفة', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 'name', child: Text('الاسم', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 'remaining', child: Text('المتبقي', style: TextStyle(fontSize: 11))),
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
      label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      selected: isSelected,
      onSelected: (_) => setState(() => _filterStatus = value),
      selectedColor: color.withOpacity(0.15),
      checkmarkColor: color,
      labelStyle: TextStyle(color: isSelected ? color : null, fontSize: 11),
    );
  }

  Widget _buildReport(List<Booking> allBookings) {
    final filtered = _filterAndSort(allBookings);

    if (filtered.isEmpty) {
      return const Center(child: Text('لا توجد بيانات تطابق البحث'));
    }

    final totalRemaining = filtered.fold(0.0, (s, b) => s + b.remainingBalanceCached);

    return Column(
      children: [
        // ملخص سريع
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.blue.shade50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('العدد: ${filtered.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(
                'إجمالي المتبقي: ${CurrencyFormatter.formatAmount(totalRemaining)} ريال',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: filtered.length,
            itemBuilder: (context, index) => _buildBookingCard(filtered[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildBookingCard(Booking b) {
    final actualDays = _getActualDaysSpent(b);
    final daysLeft = _getDaysUntilCheckout(b);
    final nightlyRate = _getAverageNightlyRate(b);
    final daysCovered = _getDaysCoveredByRemaining(b);
    final isOverdue = _isOverdue(b);
    final overdueDays = _getOverdueDays(b);
    final overdueCost = _getOverdueCost(b);
    final paidPercent = b.totalDueCached > 0 ? (b.totalPaidCached / b.totalDueCached * 100) : 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── الرأس ───
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade700,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'غرفة ${b.roomNumber}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    b.guestName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                  onPressed: () => _exportGuestStatementPdf(b),
                  tooltip: 'تصدير كشف حساب PDF',
                ),
              ],
            ),

            const SizedBox(height: 10),

            // ─── التواريخ ───
            _buildInfoRow(Icons.calendar_today, 'الوصول: ${b.checkinDate.split(' ').first}',
                Icons.event, 'المغادرة: ${b.checkoutDate?.split(' ').first ?? '---'}'),
            const SizedBox(height: 8),

            // ─── الأيام ───
            Row(
              children: [
                Expanded(child: _buildDaysCard('الأيام المقضية', '$actualDays', Colors.blue)),
                const SizedBox(width: 6),
                Expanded(child: _buildDaysCard('الأيام المخططة', '${b.calculatedNights}', Colors.purple)),
                const SizedBox(width: 6),
                Expanded(child: _buildDaysCard('الأيام المتبقية', '$daysLeft', Colors.orange)),
              ],
            ),
            const SizedBox(height: 8),

            // ─── المبالغ ───
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('تقدم الدفع', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                      Text('${paidPercent.toStringAsFixed(0)}%', 
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: paidPercent >= 100 ? Colors.green : Colors.orange)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: (paidPercent / 100).clamp(0, 1),
                    backgroundColor: Colors.grey.shade200,
                    color: paidPercent >= 100 ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _buildAmountCol('الإجمالي', b.totalDueCached, Colors.blue.shade800)),
                      Expanded(child: _buildAmountCol('المدفوع', b.totalPaidCached, Colors.green.shade800)),
                      Expanded(child: _buildAmountCol('المتبقي', b.remainingBalanceCached, Colors.red.shade800)),
                    ],
                  ),
                ],
              ),
            ),

            if (isOverdue && overdueDays > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
                child: Row(
                  children: [
                    const Icon(Icons.warning, size: 16, color: Colors.red),
                    const SizedBox(width: 6),
                    Text('تأخير $overdueDays يوم - التكلفة: ${CurrencyFormatter.formatAmount(overdueCost)} ريال',
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon1, String text1, IconData icon2, String text2) {
    return Row(
      children: [
        Icon(icon1, size: 14, color: Colors.grey),
        const SizedBox(width: 4),
        Expanded(child: Text(text1, style: const TextStyle(fontSize: 11))),
        Icon(icon2, size: 14, color: Colors.grey),
        const SizedBox(width: 4),
        Expanded(child: Text(text2, style: const TextStyle(fontSize: 11))),
      ],
    );
  }

  Widget _buildDaysCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 9, color: Colors.black54)),
        ],
      ),
    );
  }

  Widget _buildAmountCol(String label, double value, Color color) {
    return Column(
      children: [
        Text(CurrencyFormatter.formatAmount(value), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.black54)),
      ],
    );
  }

  /// تصدير كشف حساب النزيل بصيغة PDF
  Future<void> _exportGuestStatementPdf(Booking b) async {
    final payments = await ref.read(paymentsRepoProvider).paymentsByBooking(b.id).first;
    
    final config = ReportPdfConfig(
      title: 'كشف حساب نزيل',
      fileName: ReportPdfBuilder.generateFileName('كشف-حساب-${b.guestName}'),
      extraHeaderLine: 'النزيل: ${b.guestName} | غرفة: ${b.roomNumber}',
      buildContent: (fonts) {
        return [
          // ملخص الحساب
          epdf.EnhancedPdfUtils.buildInfoCard(
            title: 'ملخص الحساب والمدة',
            fonts: fonts,
            content: [
              _buildPdfInfoRow(fonts, 'تاريخ الوصول:', b.checkinDate.split(' ').first),
              _buildPdfInfoRow(fonts, 'تاريخ المغادرة:', b.checkoutDate?.split(' ').first ?? '---'),
              _buildPdfInfoRow(fonts, 'الأيام المقضية:', '${b.calculatedNights} يوم'),
              _buildPdfInfoRow(fonts, 'إجمالي المبلغ:', '${CurrencyFormatter.formatAmount(b.totalDueCached)} ريال'),
              _buildPdfInfoRow(fonts, 'إجمالي المدفوع:', '${CurrencyFormatter.formatAmount(b.totalPaidCached)} ريال'),
              _buildPdfInfoRow(fonts, 'الرصيد المتبقي:', '${CurrencyFormatter.formatAmount(b.remainingBalanceCached)} ريال'),
            ],
          ),
          pw.SizedBox(height: 20),
          
          // جدول المدفوعات
          pw.Text('تفاصيل المدفوعات', style: pw.TextStyle(font: fonts.bold, fontSize: 14)),
          pw.SizedBox(height: 10),
          epdf.EnhancedPdfUtils.buildProfessionalTable(
            fonts: fonts,
            headers: ['التاريخ', 'المبلغ', 'الطريقة', 'ملاحظات'],
            data: payments.map((p) => [
              p.paymentDate.split('T').first,
              CurrencyFormatter.formatAmount(p.amount),
              p.paymentMethod,
              p.notes ?? '',
            ]).toList(),
            columnWidths: {
              0: const pw.FixedColumnWidth(80),
              1: const pw.FixedColumnWidth(70),
              2: const pw.FixedColumnWidth(70),
              3: const pw.FlexColumnWidth(),
            },
          ),
          
          pw.SizedBox(height: 30),
          pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text('ختم الفندق', style: pw.TextStyle(font: fonts.bold, fontSize: 12)),
                pw.SizedBox(height: 40),
                pw.Container(width: 100, height: 1, color: pw.PdfColors.black),
              ],
            ),
          ),
        ];
      },
    );

    await ReportPdfBuilder.buildAndShare(config);
  }

  pw.Widget _buildPdfInfoRow(epdf.ArabicPdfFonts fonts, String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(font: fonts.regular, fontSize: 11)),
          pw.Text(value, style: pw.TextStyle(font: fonts.bold, fontSize: 11)),
        ],
      ),
    );
  }
}
