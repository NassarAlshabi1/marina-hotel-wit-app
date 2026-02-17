import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' show PdfColor;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../components/app_scaffold.dart';
import '../../components/admin_layout.dart';
import '../../components/widgets/empty_state.dart';
import '../../providers/core_providers.dart' as coreProviders;
import '../../services/local_db.dart';
import '../../utils/enhanced_pdf_utils.dart';
import '../../utils/time.dart';

class DebtsReportScreen extends ConsumerStatefulWidget {
  const DebtsReportScreen({super.key});

  @override
  ConsumerState<DebtsReportScreen> createState() => _DebtsReportScreenState();
}

class _DebtsReportScreenState extends ConsumerState<DebtsReportScreen> {
  final NumberFormat _currencyFormat = NumberFormat('#,##0', 'en_US');

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

  final Map<int, int> _unreturnedCounts = {};

  @override
  void initState() {
    super.initState();
    _initializeDefaults();
  }

  Future<void> _initializeDefaults() async {
    final now = DateTime.now();
    _fromDate = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 90));
    _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    await _fetchReport();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial =
        isFrom ? (_fromDate ?? DateTime.now()) : (_toDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = DateTime(picked.year, picked.month, picked.day, 0, 0, 0);
        } else {
          _toDate = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        }
      });
    }
  }

  Future<void> _fetchReport() async {
    if (_loading) return;
    setState(() {
      _loading = true;
    });
    try {
      final db = ref.read(coreProviders.dbProvider);
      final query = db.select(db.debts);
      final allDebts = await query.get();
      final filtered = <Debt>[];
      final fromFilter = _fromDate;
      final toFilter = _toDate;
      for (final debt in allDebts) {
        final paymentDate = _parseDateTime(debt.paymentDate);
        if (fromFilter != null && paymentDate.isBefore(fromFilter)) {
          continue;
        }
        if (toFilter != null && paymentDate.isAfter(toFilter)) {
          continue;
        }
        filtered.add(debt);
      }
      filtered.sort(
        (a, b) => _parseDateTime(
          b.paymentDate,
        ).compareTo(_parseDateTime(a.paymentDate)),
      );
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
      _unreturnedCounts.clear();
      for (final debt in filtered) {
        _unreturnedCounts[debt.id] = 0;
      }
      setState(() {
        _rows = filtered;
        _guestSummaries = guestSummaries;
        _monthlySummaries = monthlySummaries;
        _totalDebt = totalDebt;
        _totalPaid = totalPaid;
        _totalRemaining = totalRemaining;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _exportPdf() async {
    if (_rows.isEmpty) return;
    final fonts = await EnhancedPdfUtils.loadArabicFonts();
    final doc = pw.Document();
    final fromLabel =
        _fromDate != null ? _dateFormat.format(_fromDate!) : 'غير محدد';
    final toLabel = _toDate != null ? _dateFormat.format(_toDate!) : 'غير محدد';
    final totalGuests = _guestSummaries.length;

    pw.Widget metaRow(String label, String value) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: pw.TextStyle(font: fonts.bold, fontSize: 11)),
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
        metaRow('تقرير', 'الديون'),
        metaRow('الفترة', 'من $fromLabel إلى $toLabel'),
        metaRow('عدد السجلات', _rows.length.toString()),
        metaRow('عدد النزلاء', totalGuests.toString()),
      ],
    );

    pw.Widget buildReportHeader() {
      final periodText = 'الفترة من تاريخ $fromLabel إلى تاريخ $toLabel';
      return pw.Container(
        width: double.infinity,
        decoration: const pw.BoxDecoration(color: PdfColors.primary),
        padding: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              'فندق مارينا بلازا',
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 22,
                color: PdfColors.textWhite,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'تقرير الديون',
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 20,
                color: PdfColors.textWhite,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              periodText,
              style: pw.TextStyle(
                font: fonts.regular,
                fontSize: 12,
                color: PdfColors.textWhite,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      );
    }

    pw.Widget buildTotalsFooter() {
      pw.Widget buildLine(String title, String value, PdfColor color) {
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text(
                '$title: ',
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 11,
                  color: PdfColors.textDark,
                ),
              ),
              pw.Text(
                value,
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 12,
                  color: color,
                ),
              ),
            ],
          ),
        );
      }

      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColors.backgroundLight,
          border: pw.Border.all(color: PdfColors.primary, width: 0.4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            buildLine(
              'الإجمالي الكلي للديون',
              EnhancedPdfUtils.formatNumber(_totalDebt),
              PdfColors.danger,
            ),
            buildLine(
              'المبالغ المدفوعة',
              EnhancedPdfUtils.formatNumber(_totalPaid),
              PdfColors.success,
            ),
            buildLine(
              'المبالغ المتبقية',
              EnhancedPdfUtils.formatNumber(_totalRemaining),
              PdfColors.warning,
            ),
          ],
        ),
      );
    }

    final guestHeaders = ['النزيل', 'إجمالي الدين', 'المدفوع', 'المتبقي'];
    final guestData = _guestSummaries
        .map(
          (guest) => [
            guest.guestName,
            EnhancedPdfUtils.formatNumber(guest.totalAmount),
            EnhancedPdfUtils.formatNumber(guest.paidAmount),
            EnhancedPdfUtils.formatNumber(guest.remainingAmount),
          ],
        )
        .toList();

    final detailHeaders = [
      'النزيل',
      'تاريخ التسجيل',
      'تاريخ الخروج',
      'إجمالي',
      'المدفوع',
      'المتبقي',
      'سبب الدين',
      'مسدد؟',
      'رهون غير مُعادة',
    ];
    final detailData = [
      for (final debt in _rows)
        [
          debt.guestName,
          Time.safeIsoToDateString(
            debt.dateRecorded.isNotEmpty ? debt.dateRecorded : debt.paymentDate,
          ),
          Time.safeIsoToDateString(debt.checkoutDate),
          EnhancedPdfUtils.formatNumber(debt.totalAmount),
          EnhancedPdfUtils.formatNumber(debt.paidAmount),
          EnhancedPdfUtils.formatNumber(debt.remainingAmount),
          debt.debtReason.isNotEmpty ? debt.debtReason : '-',
          debt.isSettled == 1 ? 'نعم' : 'لا',
          (_unreturnedCounts[debt.id] ?? 0).toString(),
        ],
      [
        'الإجمالي',
        '',
        '',
        EnhancedPdfUtils.formatNumber(_totalDebt),
        EnhancedPdfUtils.formatNumber(_totalPaid),
        EnhancedPdfUtils.formatNumber(_totalRemaining),
        '',
        '',
        '',
      ],
    ];

    final guestSummaryCard = EnhancedPdfUtils.buildInfoCard(
      title: 'ملخص حسب النزلاء',
      fonts: fonts,
      content: [
        guestData.isEmpty
            ? pw.Text(
                'لا توجد بيانات',
                style: pw.TextStyle(font: fonts.regular, fontSize: 11),
              )
            : EnhancedPdfUtils.buildProfessionalTable(
                headers: guestHeaders,
                data: guestData,
                fonts: fonts,
                headerColor: PdfColors.primary,
                alternateRowColor: PdfColors.backgroundLight,
              ),
      ],
    );

    final detailsTable = EnhancedPdfUtils.buildProfessionalTable(
      headers: detailHeaders,
      data: detailData,
      fonts: fonts,
      headerColor: PdfColors.primary,
      alternateRowColor: PdfColors.backgroundLight,
    );

    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.center,
          child: pw.Text(
            'صفحة ${context.pageNumber} من ${context.pagesCount}',
            style: pw.TextStyle(font: fonts.regular, fontSize: 10),
          ),
        ),
        build: (context) => [
          buildReportHeader(),
          pw.SizedBox(height: 16),
          metaInfoCard,
          pw.SizedBox(height: 12),
          pw.SizedBox(height: 12),
          guestSummaryCard,
          pw.SizedBox(height: 12),
          pw.Text(
            'تفاصيل السجلات',
            style: pw.TextStyle(font: fonts.bold, fontSize: 14),
          ),
          pw.SizedBox(height: 8),
          detailsTable,
          pw.SizedBox(height: 12),
          buildTotalsFooter(),
        ],
      ),
    );

    String generateFileName(String title) {
      final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final sanitizedTitle = title.replaceAll(RegExp(r'\s+'), '-');
      return '$sanitizedTitle-$timestamp.pdf';
    }

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: generateFileName('تقرير الديون'),
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildDateSelector(
                  label: 'من تاريخ',
                  value: _fromDate,
                  onPressed: () => _pickDate(isFrom: true),
                ),
                _buildDateSelector(
                  label: 'إلى تاريخ',
                  value: _toDate,
                  onPressed: () => _pickDate(isFrom: false),
                ),
                ElevatedButton.icon(
                  onPressed: _loading ? null : _fetchReport,
                  icon: const Icon(Icons.search),
                  label: _loading
                      ? const Text('جارٍ التحديث...')
                      : const Text('تحديث النتائج'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSummaryRow(),
            const SizedBox(height: 16),
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
                            const SizedBox(height: 16),
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
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _buildSummaryTile(
                'إجمالي الديون',
                '${_currencyFormat.format(_totalDebt)}',
              ),
            ),
            Expanded(
              child: _buildSummaryTile(
                'المبالغ المدفوعة',
                '${_currencyFormat.format(_totalPaid)}',
              ),
            ),
            Expanded(
              child: _buildSummaryTile(
                'المبالغ المتبقية',
                '${_currencyFormat.format(_totalRemaining)}',
              ),
            ),
            Expanded(
              child: _buildSummaryTile('عدد السجلات', _rows.length.toString()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryTile(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value),
      ],
    );
  }

  Widget _buildGuestsTable() {
    return AdminCard(
      title: 'ملخص الديون حسب النزلاء',
      child: AdminTable(
        headers: const ['اسم النزيل', 'إجمالي الدين', 'المدفوع', 'المتبقي'],
        rows: _guestSummaries
            .map(
              (guest) => [
                Text(guest.guestName),
                Text('${_currencyFormat.format(guest.totalAmount)}'),
                Text('${_currencyFormat.format(guest.paidAmount)}'),
                Text('${_currencyFormat.format(guest.remainingAmount)}'),
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
          'اسم النزيل',
          'تاريخ التسجيل',
          'سبب الدين',
          'تاريخ الدخول',
          'تاريخ الخروج',
          'إجمالي الدين',
          'المدفوع',
          'المتبقي',
          'تاريخ الدفع',
          'حالة السداد',
          'الرهن',
          'نوع الرهن',
        ],
        rows: _rows
            .map(
              (debt) => [
                Text(debt.guestName),
                Text(_formatDisplayDate(debt.dateRecorded)),
                Text(_formatTextFallback(debt.debtReason)),
                Text(Time.safeIsoToDateString(debt.checkinDate)),
                Text(Time.safeIsoToDateString(debt.checkoutDate)),
                Text('${_currencyFormat.format(debt.totalAmount)}'),
                Text('${_currencyFormat.format(debt.paidAmount)}'),
                Text('${_currencyFormat.format(debt.remainingAmount)}'),
                Text(Time.safeIsoToDateString(debt.paymentDate)),
                Text(_formatSettlement(debt.isSettled)),
                Text(debt.pledge?.isNotEmpty == true ? debt.pledge! : '-'),
                Text(
                  debt.pledgeType?.isNotEmpty == true ? debt.pledgeType! : '-',
                ),
              ],
            )
            .toList(),
      ),
    );
  }

  Widget _buildDateSelector({
    required String label,
    required DateTime? value,
    required VoidCallback onPressed,
  }) {
    final text = value != null ? _dateFormat.format(value) : 'غير محدد';
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: Text('$label: $text', style: const TextStyle(fontSize: 12)),
    );
  }

  DateTime _parseDateTime(String value) {
    final normalized =
        value.contains('T') ? value : value.replaceFirst(' ', 'T');
    try {
      return DateTime.parse(normalized);
    } catch (_) {
      final safeDate = Time.safeIsoToDateString(value);
      return DateTime.parse('${safeDate}T00:00:00');
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
