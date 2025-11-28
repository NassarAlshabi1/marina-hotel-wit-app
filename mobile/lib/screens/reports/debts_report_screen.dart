import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
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

  String _formatNumber(num value) => value.toStringAsFixed(0);
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');

  DateTime? _fromDate;
  DateTime? _toDate;
  bool _loading = false;

  List<Debt> _rows = [];
  List<_GuestDebtSummary> _guestSummaries = [];
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
    _fromDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 90));
    _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    await _fetchReport();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? (_fromDate ?? DateTime.now()) : (_toDate ?? DateTime.now());
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
      filtered.sort((a, b) => _parseDateTime(b.paymentDate).compareTo(_parseDateTime(a.paymentDate)));
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
        final monthKey = '${date.year}-${date.month.toString().padLeft(2, '0')}';
        final monthEntry = monthlyMap.putIfAbsent(
          monthKey,
          () => _MonthlyDebtSummary(label: monthKey, month: DateTime(date.year, date.month)),
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
    final fromLabel = _fromDate != null ? _dateFormat.format(_fromDate!) : 'غير محدد';
    final toLabel = _toDate != null ? _dateFormat.format(_toDate!) : 'غير محدد';
    final totalGuests = _guestSummaries.length;

    pw.Widget metaRow(String label, String value) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: pw.TextStyle(font: fonts.bold, fontSize: 11)),
            pw.Text(value, style: pw.TextStyle(font: fonts.regular, fontSize: 11)),
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

    pw.Widget _buildReportHeader() {
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
              style: pw.TextStyle(font: fonts.bold, fontSize: 22, color: PdfColors.textWhite),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'تقرير الديون',
              style: pw.TextStyle(font: fonts.bold, fontSize: 20, color: PdfColors.textWhite),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              periodText,
              style: pw.TextStyle(font: fonts.regular, fontSize: 12, color: PdfColors.textWhite),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      );
    }

    pw.Widget _buildTotalsFooter() {
      pw.Widget buildLine(String title, String value, PdfColor color) {
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text('$title: ', style: pw.TextStyle(font: fonts.bold, fontSize: 11, color: PdfColors.textDark)),
              pw.Text(
                value,
                style: pw.TextStyle(font: fonts.bold, fontSize: 12, color: color),
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
            buildLine('الإجمالي الكلي للديون', EnhancedPdfUtils.formatNumber(_totalDebt), PdfColors.danger),
            buildLine('المبالغ المدفوعة', EnhancedPdfUtils.formatNumber(_totalPaid), PdfColors.success),
            buildLine('المبالغ المتبقية', EnhancedPdfUtils.formatNumber(_totalRemaining), PdfColors.warning),
          ],
        ),
      );
    }

    final guestHeaders = ['النزيل', 'إجمالي الدين', 'المدفوع', 'المتبقي'];
    final guestData = _guestSummaries
        .map((guest) => [
              guest.guestName,
              EnhancedPdfUtils.formatNumber(guest.totalAmount),
              EnhancedPdfUtils.formatNumber(guest.paidAmount),
              EnhancedPdfUtils.formatNumber(guest.remainingAmount),
            ])
        .toList();

    final detailHeaders = ['النزيل', 'تاريخ التسجيل', 'تاريخ الخروج', 'إجمالي', 'المدفوع', 'المتبقي', 'سبب الدين', 'مسدد؟', 'رهون غير مُعادة'];
    final detailData = _rows
        .map((debt) => [
              debt.guestName,
              Time.safeIsoToDateString(debt.dateRecorded.isNotEmpty ? debt.dateRecorded : debt.paymentDate),
              Time.safeIsoToDateString(debt.checkoutDate),
              EnhancedPdfUtils.formatNumber(debt.totalAmount),
              EnhancedPdfUtils.formatNumber(debt.paidAmount),
              EnhancedPdfUtils.formatNumber(debt.remainingAmount),
              debt.debtReason.isNotEmpty ? debt.debtReason : '-',
              debt.isSettled == 1 ? 'نعم' : 'لا',
              (_unreturnedCounts[debt.id] ?? 0).toString(),
            ])
        .toList();

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
          _buildReportHeader(),
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
          _buildTotalsFooter(),
          pw.SizedBox(height: 12),
          EnhancedPdfUtils.buildContactFooter(fonts: fonts),
        ],
      ),
    );

    await Printing.sharePdf(bytes: await doc.save(), filename: 'debts-report.pdf');
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
                _buildDateSelector(label: 'من تاريخ', value: _fromDate, onPressed: () => _pickDate(isFrom: true)),
                _buildDateSelector(label: 'إلى تاريخ', value: _toDate, onPressed: () => _pickDate(isFrom: false)),
                ElevatedButton.icon(
                  onPressed: _loading ? null : _fetchReport,
                  icon: const Icon(Icons.search),
                  label: _loading ? const Text('جارٍ التحديث...') : const Text('تحديث النتائج'),
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
                            _buildChartsSection(),
                            const SizedBox(height: 16),
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
            Expanded(child: _buildSummaryTile('إجمالي الديون', '${_currencyFormat.format(_totalDebt)}')),
            Expanded(child: _buildSummaryTile('المبالغ المدفوعة', '${_currencyFormat.format(_totalPaid)}')),
            Expanded(child: _buildSummaryTile('المبالغ المتبقية', '${_currencyFormat.format(_totalRemaining)}')),
            Expanded(child: _buildSummaryTile('عدد السجلات', _rows.length.toString())),
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

  Widget _buildChartsSection() {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        SizedBox(
          width: min(MediaQuery.of(context).size.width - 64, 480),
          height: 320,
          child: Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('توزيع المبالغ المتبقية حسب النزيل', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _buildGuestPieChart(),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(
          width: min(MediaQuery.of(context).size.width - 64, 560),
          height: 320,
          child: Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('تطور المبلغ المتبقي شهريًا', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Expanded(child: _buildMonthlyBarChart()),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGuestPieChart() {
    if (_guestSummaries.isEmpty || _totalRemaining <= 0) {
      return const Center(child: Text('لا توجد بيانات كافية للعرض'));
    }
    final sorted = List<_GuestDebtSummary>.from(_guestSummaries);
    final topGuests = sorted.take(5).toList();
    double others = 0;
    for (var i = 5; i < sorted.length; i++) {
      others += sorted[i].remainingAmount;
    }
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.grey,
    ];
    final sections = <PieChartSectionData>[];
    for (var i = 0; i < topGuests.length; i++) {
      final guest = topGuests[i];
      sections.add(
        PieChartSectionData(
          color: colors[i % colors.length],
          value: guest.remainingAmount,
          title: '${(guest.remainingAmount / _totalRemaining * 100).toStringAsFixed(1)}%',
          radius: 70,
          titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
        ),
      );
    }
    if (others > 0) {
      sections.add(
        PieChartSectionData(
          color: colors.last,
          value: others,
          title: '${(others / _totalRemaining * 100).toStringAsFixed(1)}%',
          radius: 70,
          titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              sections: sections,
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              borderData: FlBorderData(show: false),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ListView(
            children: [
              for (var i = 0; i < topGuests.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(backgroundColor: colors[i % colors.length]),
                  title: Text(topGuests[i].guestName),
                  subtitle: Text('المتبقي: ${_currencyFormat.format(topGuests[i].remainingAmount)}'),
                ),
              if (others > 0)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(backgroundColor: colors.last),
                  title: const Text('أخرى'),
                  subtitle: Text('المتبقي: ${_currencyFormat.format(others)}'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMonthlyBarChart() {
    if (_monthlySummaries.isEmpty) {
      return const Center(child: Text('لا توجد بيانات كافية للعرض'));
    }
    final groups = <BarChartGroupData>[];
    for (var i = 0; i < _monthlySummaries.length; i++) {
      final month = _monthlySummaries[i];
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: month.remainingAmount,
              gradient: const LinearGradient(colors: [Colors.indigo, Colors.blueAccent]),
              width: 18,
            ),
          ],
        ),
      );
    }
    return BarChart(
      BarChartData(
        barGroups: groups,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(show: false),
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (value, meta) {
            if (value == 0) {
              return const Text('0');
            }
            final amount = value / 1000;
            if (amount >= 1) {
              return Text('${amount.toStringAsFixed(0)}k');
            }
            return Text(value.toStringAsFixed(0));
          })),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= _monthlySummaries.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_monthlySummaries[index].label, style: const TextStyle(fontSize: 12)),
                );
              },
            ),
          ),
        ),
      ),
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
        headers: const ['اسم النزيل', 'تاريخ التسجيل', 'سبب الدين', 'تاريخ الدخول', 'تاريخ الخروج', 'إجمالي الدين', 'المدفوع', 'المتبقي', 'تاريخ الدفع', 'حالة السداد', 'الرهن', 'نوع الرهن'],
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
                Text(debt.pledgeType?.isNotEmpty == true ? debt.pledgeType! : '-'),
              ],
            )
            .toList(),
      ),
    );
  }

  Widget _buildDateSelector({required String label, required DateTime? value, required VoidCallback onPressed}) {
    final text = value != null ? _dateFormat.format(value) : 'غير محدد';
    return SizedBox(
      width: 180,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.date_range),
        label: Text('$label\\n$text', textAlign: TextAlign.center),
      ),
    );
  }

  DateTime _parseDateTime(String value) {
    final normalized = value.contains('T') ? value : value.replaceFirst(' ', 'T');
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
