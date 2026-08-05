// TODO(phase-2): remove this ignore and fix violations (discarded_futures)
// ignore_for_file: discarded_futures
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' show PdfColor;
import 'package:pdf/widgets.dart' as pw;

import '../../components/admin_layout.dart';
import '../../components/app_scaffold.dart';
import '../../components/widgets/empty_state.dart';
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart';
import '../../utils/enhanced_pdf_utils.dart';
import '../../utils/report_pdf_builder.dart';
import '../../utils/time.dart';
import '../../widgets/report_date_filter.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class DebtsReportScreen extends ConsumerStatefulWidget {
  const DebtsReportScreen({super.key});

  @override
  ConsumerState<DebtsReportScreen> createState() => _DebtsReportScreenState();
}

class _DebtsReportScreenState extends ConsumerState<DebtsReportScreen> {
  final NumberFormat _currencyFormat = NumberFormat('#,##0', 'en_US');
  final _filterController = DateFilterController();

  // ignore: unused_element
  String _formatNumber(num value) => _currencyFormat.format(value);
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');

  DateTime? _fromDate;
  DateTime? _toDate;
  bool _loading = false;

  List<Debt> _rows = [];
  List<_GuestDebtSummary> _guestSummaries = [];
  // ignore: unused_field
  List<_MonthlyDebtSummary> _monthlySummaries = [];

  double _totalDebt = 0;
  double _totalPaid = 0;
  double _totalRemaining = 0;

  /// خريطة سعر الغرفة (سعر الليلة) لكل حجز: bookingLocalId → nightlyRate
  final Map<int?, double> _roomPriceMap = {};

  final Map<int, int> _unreturnedCounts = {};

  @override
  void initState() {
    super.initState();
    _initializeDefaults();
  }

  Future<void> _initializeDefaults() async {
    // الافتراضي: اليوم الفندقي الحالي (14:01 → 14:00)
    final range = DateFilterController.getDefaultHotelDayRange();
    _fromDate = range.from;
    _toDate = range.to;
    await _fetchReport();
  }

  Future<void> _fetchReport() async {
    if (_loading) {
      return;
    }
    setState(() {
      _loading = true;
    });
    try {
      final db = ref.read(databaseProvider);
      final query = db.select(db.debts);
      final allDebts = await query.get();
      final filtered = <Debt>[];
      final fromFilter = _fromDate;
      final toFilter = _toDate;
      for (final debt in allDebts) {
        final paymentDate = _parseDateTime(debt.paymentDate);
        if (paymentDate == null) continue;
        if (fromFilter != null && paymentDate.isBefore(fromFilter)) {
          continue;
        }
        if (toFilter != null && paymentDate.isAfter(toFilter)) {
          continue;
        }
        filtered.add(debt);
      }
      filtered.sort((a, b) {
        final dateA = _parseDateTime(a.paymentDate);
        final dateB = _parseDateTime(b.paymentDate);
        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        return dateB.compareTo(dateA);
      });
      final guestMap = <String, _GuestDebtSummary>{};
      final monthlyMap = <String, _MonthlyDebtSummary>{};
      double totalDebt = 0;
      double totalPaid = 0;
      double totalRemaining = 0;
      for (final debt in filtered) {
        totalDebt += debt.totalAmount;
        totalPaid += debt.paidAmount;
        totalRemaining += debt.remainingAmount;
        final guestEntry = guestMap.putIfAbsent(
          debt.guestName,
          () => _GuestDebtSummary(guestName: debt.guestName),
        );
        guestEntry.totalAmount += debt.totalAmount;
        guestEntry.paidAmount += debt.paidAmount;
        guestEntry.remainingAmount += debt.remainingAmount;
        final date = _parseDateTime(debt.paymentDate);
        if (date == null) continue;
        final monthKey =
            '${date.year}-${date.month.toString().padLeft(2, '0')}';
        final monthEntry = monthlyMap.putIfAbsent(
          monthKey,
          () => _MonthlyDebtSummary(
            label: monthKey,
            month: DateTime(date.year, date.month),
          ),
        );
        monthEntry.totalAmount += debt.totalAmount;
        monthEntry.paidAmount += debt.paidAmount;
        monthEntry.remainingAmount += debt.remainingAmount;
      }
      final guestSummaries = guestMap.values.toList()
        ..sort((a, b) => b.remainingAmount.compareTo(a.remainingAmount));
      final monthlySummaries = monthlyMap.values.toList()
        ..sort((a, b) => a.month.compareTo(b.month));
      // جلب بيانات الحجوزات لحساب سعر الغرفة لكل دين
      final bookingsQuery = db.select(db.bookings);
      final allBookings = await bookingsQuery.get();
      _roomPriceMap.clear();
      for (final booking in allBookings) {
        final price = booking.totalNightsCached > 0
            ? booking.totalDueCached / booking.totalNightsCached
            : 0.0;
        _roomPriceMap[booking.id] = price;
      }

      _unreturnedCounts.clear();
      for (final debt in filtered) {
        _unreturnedCounts[debt.id] = 0;
      }
      if (mounted) {
        setState(() {
          _rows = filtered;
          _guestSummaries = guestSummaries;
          _monthlySummaries = monthlySummaries;
          _totalDebt = totalDebt;
          _totalPaid = totalPaid;
          _totalRemaining = totalRemaining;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _exportPdf() async {
    if (_rows.isEmpty) {
      return;
    }
    final fromLabel = _fromDate != null
        ? _dateFormat.format(_fromDate!)
        : 'غير محدد';
    final toLabel = _toDate != null ? _dateFormat.format(_toDate!) : 'غير محدد';
    final totalGuests = _guestSummaries.length;
    final settledCount = _rows.where((d) => d.isSettled == 1).length;
    final unsettledCount = _rows.length - settledCount;

    // ═══════════════════════════════════════════════════════
    // دالة تنسيق الأرقام بدون كسور عشرية
    // ═══════════════════════════════════════════════════════
    String fmt(double v) => EnhancedPdfUtils.formatNumber(v);

    // ═══════════════════════════════════════════════════════
    // ملخص حسب النزلاء
    // ═══════════════════════════════════════════════════════
    final guestHeaders = ['النزيل', 'إجمالي الدين', 'المدفوع', 'المتبقي'];
    final guestData = _guestSummaries
        .map(
          (guest) => [
            guest.guestName,
            fmt(guest.totalAmount),
            fmt(guest.paidAmount),
            fmt(guest.remainingAmount),
          ],
        )
        .toList();

    // ═══════════════════════════════════════════════════════
    // تفاصيل السجلات — أعمدة مختصرة لتناسب عرض الصفحة
    // ═══════════════════════════════════════════════════════
    final detailHeaders = [
      '#',
      'النزيل',
      'التسجيل',
      'سعر الغرفة',
      'الإجمالي',
      'المدفوع',
      'المتبقي',
      'السبب',
      'الحالة',
    ];
    final detailData = <List<String>>[];
    for (var i = 0; i < _rows.length; i++) {
      final debt = _rows[i];
      final roomPrice = _roomPriceMap[debt.bookingLocalId] ?? 0.0;
      detailData.add([
        (i + 1).toString(),
        debt.guestName,
        Time.safeIsoToDateString(
          debt.dateRecorded.isNotEmpty ? debt.dateRecorded : debt.paymentDate,
        ),
        fmt(roomPrice),
        fmt(debt.totalAmount),
        fmt(debt.paidAmount),
        fmt(debt.remainingAmount),
        if (debt.debtReason.isNotEmpty) debt.debtReason else '-',
        if (debt.isSettled == 1) 'مسدد' else 'غير مسدد',
      ]);
    }
    // صف الإجمالي
    detailData.add([
      '',
      'الإجمالي',
      '',
      '',
      fmt(_totalDebt),
      fmt(_totalPaid),
      fmt(_totalRemaining),
      '',
      '',
    ]);

    // ═══════════════════════════════════════════════════════
    // عرض الأعمدة لكل جدول
    // ═══════════════════════════════════════════════════════
    final guestColWidths = [140.0, 100.0, 100.0, 100.0];
    final detailColWidths = [
      25.0,
      80.0,
      60.0,
      55.0,
      60.0,
      60.0,
      60.0,
      75.0,
      55.0,
    ];

    await ReportPdfBuilder.buildAndShare(
      ReportPdfConfig(
        title: 'تقرير الديون',
        fromDate: _fromDate,
        toDate: _toDate,
        buildContent: (fonts) {
          // ═════════════════════════════════════════════
          // 1) بطاقات الإحصائيات العلوية
          // ═════════════════════════════════════════════
          final statsRow = pw.Row(
            children: [
              pw.Expanded(
                child: EnhancedPdfUtils.buildStatisticsBox(
                  title: 'إجمالي الديون',
                  value: fmt(_totalDebt),
                  subtitle: '$totalGuests نزيل',
                  fonts: fonts,
                  color: PdfColors.danger,
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Expanded(
                child: EnhancedPdfUtils.buildStatisticsBox(
                  title: 'المدفوع',
                  value: fmt(_totalPaid),
                  subtitle: _totalDebt > 0
                      ? '${(_totalPaid / _totalDebt * 100).toStringAsFixed(0)}%'
                      : '0%',
                  fonts: fonts,
                  color: PdfColors.success,
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Expanded(
                child: EnhancedPdfUtils.buildStatisticsBox(
                  title: 'المتبقي',
                  value: fmt(_totalRemaining),
                  subtitle: '$unsettledCount غير مسدد',
                  fonts: fonts,
                  color: PdfColors.warning,
                ),
              ),
            ],
          );

          // ═════════════════════════════════════════════
          // 2) بطاقة معلومات التقرير
          // ═════════════════════════════════════════════
          pw.Widget metaRow(String label, String value) {
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    label,
                    style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                  ),
                  pw.Text(
                    value,
                    style: pw.TextStyle(font: fonts.regular, fontSize: 11),
                  ),
                ],
              ),
            );
          }

          final metaInfoCard = EnhancedPdfUtils.buildInfoCard(
            title: 'تفاصيل التقرير',
            fonts: fonts,
            content: [
              metaRow('التقرير', 'الديون'),
              metaRow('الفترة', 'من $fromLabel إلى $toLabel'),
              metaRow('عدد السجلات', _rows.length.toString()),
              metaRow('عدد النزلاء', totalGuests.toString()),
              metaRow('مسدد', '$settledCount سجل'),
              metaRow('غير مسدد', '$unsettledCount سجل'),
            ],
          );

          // ═════════════════════════════════════════════
          // 3) ملخص حسب النزلاء
          // ═════════════════════════════════════════════
          final guestSummaryCard = EnhancedPdfUtils.buildInfoCard(
            title: 'ملخص حسب النزلاء',
            fonts: fonts,
            content: [
              if (guestData.isEmpty)
                pw.Text(
                  'لا توجد بيانات',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 11),
                )
              else
                EnhancedPdfUtils.buildProfessionalTable(
                  headers: guestHeaders,
                  data: guestData,
                  fonts: fonts,
                  columnWidths: guestColWidths,
                  headerColor: PdfColors.primary,
                  alternateRowColor: PdfColors.backgroundLight,
                ),
            ],
          );

          // ═════════════════════════════════════════════
          // 4) ملخص الإجماليات
          // ═════════════════════════════════════════════
          pw.Widget buildTotalLine(String title, String value, PdfColor color) {
            return pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 4),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    title,
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 12,
                      color: color,
                    ),
                  ),
                  pw.Text(
                    value,
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 13,
                      color: color,
                    ),
                  ),
                ],
              ),
            );
          }

          final totalsCard = pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PdfColors.backgroundLight,
              border: pw.Border.all(color: PdfColors.primary, width: 0.5),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(
              children: [
                buildTotalLine(
                  'إجمالي الديون',
                  fmt(_totalDebt),
                  PdfColors.danger,
                ),
                pw.Divider(color: PdfColors.textLight),
                buildTotalLine('المدفوع', fmt(_totalPaid), PdfColors.success),
                pw.Divider(color: PdfColors.textLight),
                buildTotalLine(
                  'المتبقي',
                  fmt(_totalRemaining),
                  PdfColors.warning,
                ),
              ],
            ),
          );

          // ═════════════════════════════════════════════
          // 5) تجميع المحتوى النهائي
          // ═════════════════════════════════════════════
          return [
            pw.SizedBox(height: 12),
            statsRow,
            pw.SizedBox(height: 12),
            metaInfoCard,
            pw.SizedBox(height: 12),
            guestSummaryCard,
            pw.SizedBox(height: 12),
            totalsCard,
            pw.SizedBox(height: 16),
            pw.Text(
              'تفاصيل السجلات',
              style: pw.TextStyle(font: fonts.bold, fontSize: 14),
            ),
            pw.SizedBox(height: 8),
            EnhancedPdfUtils.buildProfessionalTable(
              headers: detailHeaders,
              data: detailData,
              fonts: fonts,
              columnWidths: detailColWidths,
              headerColor: PdfColors.primary,
              alternateRowColor: PdfColors.backgroundLight,
            ),
          ];
        },
        fileName: ReportPdfBuilder.generateFileName('تقرير الديون'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'تقرير الديون',
      actions: [
        IconButton(
          icon: const Icon(Icons.picture_as_pdf),
          tooltip: 'تصدير PDF',
          onPressed: _rows.isEmpty || _loading ? null : _exportPdf,
        ),
        IconButton(
          onPressed: _loading ? null : _fetchReport,
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // فلتر التاريخ المشترك
            ReportDateFilterWidget(
              controller: _filterController,
              onDateRangeChanged: (range) {
                setState(() {
                  _fromDate = range.from;
                  _toDate = range.to;
                });
                _fetchReport();
              },
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  onPressed: _loading ? null : _fetchReport,
                  icon: const Icon(Icons.search, size: 16),
                  label: Text(_loading ? 'جارٍ...' : 'تحديث'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildSummaryRow(),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                  ? const EmptyState(
                      title: 'لا توجد بيانات',
                      message: 'لم يتم العثور على ديون ضمن النطاق المحدد.',
                      icon: Icons.assessment_outlined,
                    )
                  : ListView(
                      children: [
                        _buildGuestsTable(),
                        const SizedBox(height: 10),
                        _buildDebtsTable(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow() {
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: _buildSummaryChip(
                'إجمالي الديون',
                _currencyFormat.format(_totalDebt),
                Colors.red,
              ),
            ),
            Container(width: 1, height: 22, color: Colors.grey.shade200),
            Expanded(
              child: _buildSummaryChip(
                'المدفوعة',
                _currencyFormat.format(_totalPaid),
                Colors.green,
              ),
            ),
            Container(width: 1, height: 22, color: Colors.grey.shade200),
            Expanded(
              child: _buildSummaryChip(
                'المتبقية',
                _currencyFormat.format(_totalRemaining),
                Colors.orange,
              ),
            ),
            Container(width: 1, height: 22, color: Colors.grey.shade200),
            Expanded(
              child: _buildSummaryChip(
                'سجلات',
                _rows.length.toString(),
                Colors.blue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryChip(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11,
            color: color,
          ),
        ),
        const SizedBox(height: 1),
        Text(label, style: const TextStyle(fontSize: 8, color: Colors.grey)),
      ],
    );
  }

  Widget _buildGuestsTable() {
    return AdminCard(
      title: 'ملخص حسب النزلاء',
      child: AdminTable(
        headers: const ['النزيل', 'الدين', 'المدفوع', 'المتبقي'],
        rows: _guestSummaries
            .map(
              (guest) => [
                Text(guest.guestName, style: const TextStyle(fontSize: 10)),
                Text(
                  _currencyFormat.format(guest.totalAmount),
                  style: const TextStyle(fontSize: 10),
                ),
                Text(
                  _currencyFormat.format(guest.paidAmount),
                  style: const TextStyle(fontSize: 10),
                ),
                Text(
                  _currencyFormat.format(guest.remainingAmount),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
            .toList(),
      ),
    );
  }

  Widget _buildDebtsTable() {
    return AdminCard(
      title: 'تفاصيل السجلات',
      child: AdminTable(
        headers: const [
          'النزيل',
          'التسجيل',
          'السبب',
          'الدخول',
          'الخروج',
          'سعر الغرفة',
          'الدين',
          'المدفوع',
          'المتبقي',
          'الدفع',
          'الحالة',
          'الرهن',
          'نوع الرهن',
        ],
        rows: _rows.map((debt) {
          final roomPrice = _roomPriceMap[debt.bookingLocalId] ?? 0.0;
          return [
            Text(debt.guestName, style: const TextStyle(fontSize: 9)),
            Text(
              _formatDisplayDate(debt.dateRecorded),
              style: const TextStyle(fontSize: 9),
            ),
            Text(
              _formatTextFallback(debt.debtReason),
              style: const TextStyle(fontSize: 9),
            ),
            Text(
              Time.safeIsoToDateString(debt.checkinDate),
              style: const TextStyle(fontSize: 9),
            ),
            Text(
              Time.safeIsoToDateString(debt.checkoutDate),
              style: const TextStyle(fontSize: 9),
            ),
            Text(
              _currencyFormat.format(roomPrice),
              style: const TextStyle(fontSize: 9),
            ),
            Text(
              _currencyFormat.format(debt.totalAmount),
              style: const TextStyle(fontSize: 9),
            ),
            Text(
              _currencyFormat.format(debt.paidAmount),
              style: const TextStyle(fontSize: 9),
            ),
            Text(
              _currencyFormat.format(debt.remainingAmount),
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
            ),
            Text(
              Time.safeIsoToDateString(debt.paymentDate),
              style: const TextStyle(fontSize: 9),
            ),
            Text(
              _formatSettlement(debt.isSettled),
              style: const TextStyle(fontSize: 9),
            ),
            Text(
              debt.pledge?.isNotEmpty ?? false ? debt.pledge! : '-',
              style: const TextStyle(fontSize: 9),
            ),
            Text(
              debt.pledgeType?.isNotEmpty ?? false ? debt.pledgeType! : '-',
              style: const TextStyle(fontSize: 9),
            ),
          ];
        }).toList(),
      ),
    );
  }

  /// ✅ إصلاح حرج: إرجاع null عند فشل تحليل التاريخ بدلاً من epoch(1970)
  /// السلوك السابق كان يُرجع DateTime.fromMillisecondsSinceEpoch(0) عند الفشل
  /// مما يُدخل سجلات فاسدة في ملخصات 1970 ويُفسد المجاميع الشهرية
  DateTime? _parseDateTime(String value) {
    if (value.isEmpty) return null;
    final normalized = value.contains('T')
        ? value
        : value.replaceFirst(' ', 'T');
    try {
      return DateTime.parse(normalized);
    } catch (e) {
      debugPrint('⚠️ Swallowed error in debts_report_screen.dart: ');
      try {
        final safeDate = Time.safeIsoToDateString(value);
        return DateTime.parse('${safeDate}T00:00:00');
      } catch (e) {
      debugPrint('⚠️ Swallowed error in debts_report_screen.dart: ');
        // بيانات تاريخ فاسدة — إرجاع null لتجاهل السجل في التجميع
        return null;
      }
    }
  }

  String _formatDisplayDate(String value) {
    if (value.isEmpty) {
      return '-';
    }
    return Time.safeIsoToDateString(value);
  }

  String _formatTextFallback(String value) {
    if (value.trim().isEmpty) {
      return '-';
    }
    return value;
  }

  String _formatSettlement(int value) {
    return value == 1 ? 'مسدد' : 'غير مسدد';
  }
}

class _GuestDebtSummary {
  _GuestDebtSummary({required this.guestName});

  final String guestName;
  double totalAmount = 0;
  double paidAmount = 0;
  double remainingAmount = 0;
}

class _MonthlyDebtSummary {
  _MonthlyDebtSummary({required this.label, required this.month});

  final String label;
  final DateTime month;
  double totalAmount = 0;
  double paidAmount = 0;
  double remainingAmount = 0;
}
