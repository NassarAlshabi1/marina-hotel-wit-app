import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat, PdfColor;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../components/app_scaffold.dart';
import '../../components/widgets/empty_state.dart';
import '../../providers/core_providers.dart' as core_providers;
import '../../services/daos/expenses_dao.dart';
import '../../services/daos/outbox_dao.dart';
import '../../services/daos/payments_dao.dart';
import '../../services/report_cache_service.dart';
import '../../utils/enhanced_pdf_utils.dart';

class IncomeExpenseReportScreen extends ConsumerStatefulWidget {
  const IncomeExpenseReportScreen({super.key});

  @override
  ConsumerState<IncomeExpenseReportScreen> createState() =>
      _IncomeExpenseReportScreenState();
}

class _IncomeExpenseReportScreenState
    extends ConsumerState<IncomeExpenseReportScreen> {
  final NumberFormat _currencyFormat = NumberFormat('#,##0', 'en_US');
  final DateFormat _dateFormat = DateFormat('yyyy/MM/dd');

  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();
  bool _loading = false;
  bool _detailedMode = false;
  bool _isFromCache = false;

  // Data
  List<_IncomeEntry> _incomeEntries = [];
  List<_ExpenseEntry> _expenseEntries = [];
  double _incomeTotal = 0;
  double _expenseTotal = 0;
  double _salaryTotal = 0;
  double _net = 0;

  @override
  void initState() {
    super.initState();
    _setQuickFilter('month'); // الافتراضي: الشهر الحالي
  }

  void _setQuickFilter(String period) {
    final now = DateTime.now();
    DateTime start;
    DateTime end;

    switch (period) {
      case 'today':
        start = DateTime(now.year, now.month, now.day);
        end = DateTime(now.year, now.month, now.day, 23, 59, 59);
      case 'week':
        final today = DateTime(now.year, now.month, now.day);
        int daysToSubtract = (now.weekday == 7) ? 1 : (now.weekday + 1) % 7;
        if (now.weekday == 6) {
          daysToSubtract = 0;
        } else if (now.weekday == 7) {
          daysToSubtract = 1;
        } else {
          daysToSubtract = now.weekday + 1;
        }

        start = today.subtract(Duration(days: daysToSubtract));
        end = DateTime(now.year, now.month, now.day, 23, 59, 59);
      case 'month':
        start = DateTime(now.year, now.month, 1);
        final lastDay = DateTime(now.year, now.month + 1, 0);
        end = DateTime(lastDay.year, lastDay.month, lastDay.day, 23, 59, 59);
      case 'year':
        start = DateTime(now.year, 1, 1);
        end = DateTime(now.year, 12, 31, 23, 59, 59);
      default:
        return;
    }

    setState(() {
      _fromDate = start;
      _toDate = end;
    });
    _fetchReport();
  }

  bool _isToday() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
    return _fromDate.year == todayStart.year &&
        _fromDate.month == todayStart.month &&
        _fromDate.day == todayStart.day &&
        _toDate.year == todayEnd.year &&
        _toDate.month == todayEnd.month &&
        _toDate.day == todayEnd.day;
  }

  bool _isThisMonth() {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final lastDay = DateTime(now.year, now.month + 1, 0);
    final monthEnd = DateTime(lastDay.year, lastDay.month, lastDay.day, 23, 59, 59);
    return _fromDate.year == monthStart.year &&
        _fromDate.month == monthStart.month &&
        _fromDate.day == monthStart.day &&
        _toDate.year == monthEnd.year &&
        _toDate.month == monthEnd.month &&
        _toDate.day == monthEnd.day;
  }

  bool _isThisWeek() {
    final now = DateTime.now();
    // حساب بداية الأسبوع (السبت في التقويم العربي)
    final today = DateTime(now.year, now.month, now.day);
    int daysToSubtract;
    if (now.weekday == DateTime.saturday) {
      daysToSubtract = 0;
    } else if (now.weekday == DateTime.sunday) {
      daysToSubtract = 1;
    } else {
      daysToSubtract = now.weekday + 1;
    }
    final weekStart = today.subtract(Duration(days: daysToSubtract));
    final weekEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
    return _fromDate.year == weekStart.year &&
        _fromDate.month == weekStart.month &&
        _fromDate.day == weekStart.day &&
        _toDate.year == weekEnd.year &&
        _toDate.month == weekEnd.month &&
        _toDate.day == weekEnd.day;
  }

  bool _isThisYear() {
    final now = DateTime.now();
    final yearStart = DateTime(now.year, 1, 1);
    final yearEnd = DateTime(now.year, 12, 31, 23, 59, 59);
    return _fromDate.year == yearStart.year &&
        _fromDate.month == yearStart.month &&
        _fromDate.day == yearStart.day &&
        _toDate.year == yearEnd.year &&
        _toDate.month == yearEnd.month &&
        _toDate.day == yearEnd.day;
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _fromDate : _toDate;
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
      unawaited(_fetchReport());
    }
  }

  /// ⭐ إنشاء معاملات الـ cache
  Map<String, dynamic> _getCacheParams() {
    return {
      'fromDate': _fromDate.toIso8601String(),
      'toDate': _toDate.toIso8601String(),
    };
  }

  Future<void> _fetchReport() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _isFromCache = false;
    });

    try {
      // ⭐ محاولة الحصول على البيانات من الـ cache أولاً
      final cachedResult = await ReportCacheService.instance.get<
          _ReportResult>(
        ReportCacheKeys.incomeExpense,
        _getCacheParams(),
        (json) => _ReportResult.fromJson(json),
      );

      if (cachedResult != null) {
        setState(() {
          _incomeEntries = cachedResult.incomeEntries;
          _expenseEntries = cachedResult.expenseEntries;
          _incomeTotal = cachedResult.incomeTotal;
          _expenseTotal = cachedResult.expenseTotal;
          _salaryTotal = cachedResult.salaryTotal;
          _net = cachedResult.net;
          _isFromCache = true;
        });
        return;
      }

      final db = ref.read(core_providers.dbProvider);
      final outboxDao = OutboxDao(db);
      final paymentsDao = PaymentsDao(db, outboxDao);
      final expensesDao = ExpensesDao(db, outboxDao);

      final fromStr = DateFormat('yyyy-MM-dd').format(_fromDate);
      final toStr = DateFormat('yyyy-MM-dd').format(_toDate);

      // Fetch payments (Income)
      final payments =
          await paymentsDao.listForReport(from: fromStr, to: toStr);
      final payList = payments
          .map((p) => {
                'date': p.paymentDate,
                'amount': p.amount,
                'guestName': p.revenueType,
              })
          .toList();

      // Fetch expenses
      final expenses = await expensesDao.listFiltered(from: fromStr, to: toStr);
      final expList = expenses
          .map((e) => {
                'date': e.date,
                'amount': e.amount,
                'type': e.expenseType,
                'description': e.description,
              })
          .toList();

      // Process in isolate
      final result = await compute(
          _processReportData,
          _ReportParams(
            payments: payList,
            expenses: expList,
            fromDate: _fromDate,
            toDate: _toDate,
          ));

      // ⭐ تخزين النتيجة في الـ cache
      await ReportCacheService.instance.set(
        ReportCacheKeys.incomeExpense,
        _getCacheParams(),
        result,
        (r) => r.toJson(),
      );

      if (mounted) {
        setState(() {
          _incomeEntries = result.incomeEntries;
          _expenseEntries = result.expenseEntries;
          _incomeTotal = result.incomeTotal;
          _expenseTotal = result.expenseTotal;
          _salaryTotal = result.salaryTotal;
          _net = result.net;
        });
      }
    } catch (e) {
      debugPrint('Error fetching report: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showExportOptions() async {
    if (_incomeEntries.isEmpty && _expenseEntries.isEmpty) return;

    final fonts = await EnhancedPdfUtils.loadArabicFonts();
    final doc = pw.Document();

    final prefs = await SharedPreferences.getInstance();
    final hotelName = prefs.getString('hotel_name') ?? 'فندق مارينا بلازا';
    final hotelPhone = prefs.getString('hotel_phone') ?? '';
    final hotelAddress = prefs.getString('hotel_address') ?? '';
    final hotelLogoPath = prefs.getString('hotel_logo');

    pw.ImageProvider? logoImage;
    if (hotelLogoPath != null && File(hotelLogoPath).existsSync()) {
      final logoBytes = File(hotelLogoPath).readAsBytesSync();
      logoImage = pw.MemoryImage(logoBytes);
    }

    final fromLabel = DateFormat('yyyy-MM-dd').format(_fromDate);
    final toLabel = DateFormat('yyyy-MM-dd').format(_toDate);

    pw.Widget buildReportHeader() {
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(vertical: 20, horizontal: 20),
        decoration: const pw.BoxDecoration(
          color: PdfColors.white,
          border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey300, width: 1)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(hotelName,
                    style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 18,
                        color: PdfColors.blue900)),
                if (hotelPhone.isNotEmpty)
                  pw.Text('هاتف: $hotelPhone',
                      style: pw.TextStyle(font: fonts.regular, fontSize: 10)),
                if (hotelAddress.isNotEmpty)
                  pw.Text('عنوان: $hotelAddress',
                      style: pw.TextStyle(font: fonts.regular, fontSize: 10)),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text('تقرير الدخل والمصروفات',
                    style: pw.TextStyle(font: fonts.bold, fontSize: 16)),
                pw.SizedBox(height: 4),
                pw.Text('من $fromLabel إلى $toLabel',
                    style: pw.TextStyle(
                        font: fonts.regular,
                        fontSize: 10,
                        color: PdfColors.grey700)),
              ],
            ),
            if (logoImage != null)
              pw.Container(height: 50, width: 50, child: pw.Image(logoImage))
            else
              pw.SizedBox(width: 50),
          ],
        ),
      );
    }

    final summaryCard = pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _buildPdfSummaryItem(
                'إجمالي الدخل', _incomeTotal, PdfColors.green700, fonts.bold),
            _buildPdfSummaryItem('إجمالي المصروفات', _expenseTotal,
                PdfColors.red700, fonts.bold),
            _buildPdfSummaryItem('صافي الربح', _net,
                _net >= 0 ? PdfColors.blue700 : PdfColors.red700, fonts.bold),
          ],
        ));

    final headers = ['التاريخ', 'النوع', 'الوصف', 'المبلغ'];

    // Combined list for PDF
    final combined = <_CombinedEntry>[];
    for (final e in _incomeEntries) {
      combined.add(_CombinedEntry(
          date: e.date,
          description: e.description,
          amount: e.amount,
          isIncome: true,
          isSalary: false,
          type: 'دخل'));
    }
    for (final e in _expenseEntries) {
      combined.add(_CombinedEntry(
          date: e.date,
          description: e.description,
          amount: e.amount,
          isIncome: false,
          isSalary: e.isSalary,
          type: e.type));
    }
    combined.sort((a, b) => b.date.compareTo(a.date));

    final dataRows = <List<String>>[];
    for (final row in combined) {
      dataRows.add([
        _dateFormat.format(row.date),
        if (row.isIncome) 'دخل' else row.type,
        row.description,
        (row.isIncome ? '+' : '-') + _currencyFormat.format(row.amount),
      ]);
    }

    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.center,
          child: pw.Text(
            'صفحة ${context.pageNumber} من ${context.pagesCount} - ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}',
            style: pw.TextStyle(
                font: fonts.regular, fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          buildReportHeader(),
          pw.SizedBox(height: 12),
          summaryCard,
          pw.SizedBox(height: 12),
          EnhancedPdfUtils.buildProfessionalTable(
            headers: headers,
            data: dataRows,
            fonts: fonts,
            headerColor: PdfColors.blue800,
            alternateRowColor: PdfColors.grey100,
          ),
        ],
      ),
    );

    String generateFileName() {
      final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      return 'IncomeExpense-$timestamp.pdf';
    }

    final pdfBytes = await doc.save();
    final fileName = generateFileName();

    try {
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (await downloadDir.exists()) {
        final file = File('${downloadDir.path}/$fileName');
        await file.writeAsBytes(pdfBytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم حفظ التقرير في: ${file.path}'),
              backgroundColor: Colors.green,
              action: SnackBarAction(
                label: 'فتح',
                textColor: Colors.white,
                onPressed: () =>
                    Printing.sharePdf(bytes: pdfBytes, filename: fileName),
              ),
            ),
          );
        }
        return;
      }
    } catch (e) {
      debugPrint('Direct save failed: $e');
    }

    await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
  }

  pw.Widget _buildPdfSummaryItem(
      String label, double value, PdfColor color, pw.Font font) {
    return pw.Column(
      children: [
        pw.Text(label,
            style: pw.TextStyle(
                font: font, fontSize: 10, color: PdfColors.grey700)),
        pw.Text(_currencyFormat.format(value),
            style: pw.TextStyle(
                font: font,
                fontSize: 12,
                color: color,
                fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const double inputsHeight = 42;

    return AppScaffold(
      title: 'تقرير الدخل والمصروفات',
      actions: [
        if (_isFromCache)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Tooltip(
              message: 'البيانات من الذاكرة المؤقتة',
              child: Icon(Icons.cached, color: Colors.green[600], size: 20),
            ),
          ),
      ],
      body: Column(
        children: [
          // فلاتر
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: _buildDateFilterButton(
                        label: 'من',
                        date: _fromDate,
                        height: inputsHeight,
                        onTap: () => _pickDate(isFrom: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: _buildDateFilterButton(
                        label: 'إلى',
                        date: _toDate,
                        height: inputsHeight,
                        onTap: () => _pickDate(isFrom: false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: inputsHeight,
                      width: inputsHeight,
                      child: ElevatedButton(
                        onPressed: _fetchReport,
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          elevation: 0,
                          backgroundColor: Theme.of(context).primaryColor,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Icon(Icons.search, size: 20),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: inputsHeight,
                      width: inputsHeight,
                      child: ElevatedButton(
                        onPressed:
                            (_incomeEntries.isEmpty && _expenseEntries.isEmpty)
                                ? null
                                : _showExportOptions,
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          elevation: 0,
                          backgroundColor: Colors.red[700],
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Icon(Icons.picture_as_pdf, size: 20),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildQuickChip(
                          'اليوم', _isToday(), () => _setQuickFilter('today')),
                      const SizedBox(width: 8),
                      _buildQuickChip('الأسبوع', _isThisWeek(),
                          () => _setQuickFilter('week')),
                      const SizedBox(width: 8),
                      _buildQuickChip('الشهر', _isThisMonth(),
                          () => _setQuickFilter('month')),
                      const SizedBox(width: 8),
                      _buildQuickChip('السنة', _isThisYear(),
                          () => _setQuickFilter('year')),
                      const SizedBox(width: 12),
                      FilterChip(
                        label: Text(_detailedMode ? 'عرض مفصل' : 'عرض ملخص',
                            style: const TextStyle(fontSize: 11)),
                        selected: _detailedMode,
                        onSelected: (v) => setState(() => _detailedMode = v),
                        selectedColor: Colors.blue.withValues(alpha: 0.2),
                        checkmarkColor: Colors.blue,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // الملخص
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    _buildSummaryItem('الدخل', _incomeTotal, Colors.green),
                    const SizedBox(width: 16),
                    _buildSummaryItem('المصروفات', _expenseTotal, Colors.red),
                    const SizedBox(width: 16),
                    _buildSummaryItem(
                        'الصافي', _net, _net >= 0 ? Colors.blue : Colors.red),
                  ],
                ),
                if (_isFromCache)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'محفوظ مؤقتاً',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.green[700],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // القائمة
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_incomeEntries.isEmpty && _expenseEntries.isEmpty)
                    ? const EmptyState(
                        title: 'لا توجد بيانات',
                        message: 'لم يتم العثور على سجلات ضمن الفترة.',
                        icon: Icons.bar_chart,
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          await ReportCacheService.instance.clearAll();
                          await _fetchReport();
                        },
                        child: _buildDetailsList(),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsList() {
    if (!_detailedMode) {
      // Summary mode: Just show stats
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildStatCard('عدد الدفعات', _incomeEntries.length.toString(),
                Icons.arrow_downward, Colors.green),
            const SizedBox(height: 10),
            _buildStatCard('عدد المصروفات', _expenseEntries.length.toString(),
                Icons.arrow_upward, Colors.red),
            const SizedBox(height: 10),
            _buildStatCard(
                'عدد الرواتب',
                _expenseEntries.where((e) => e.isSalary).length.toString(),
                Icons.people,
                Colors.orange),
          ],
        ),
      );
    }

    // Detailed mode: Combined list
    final combined = <_CombinedEntry>[];
    for (final e in _incomeEntries) {
      combined.add(_CombinedEntry(
          date: e.date,
          description: e.description,
          amount: e.amount,
          isIncome: true,
          isSalary: false,
          type: 'دخل'));
    }
    for (final e in _expenseEntries) {
      combined.add(_CombinedEntry(
          date: e.date,
          description: e.description,
          amount: e.amount,
          isIncome: false,
          isSalary: e.isSalary,
          type: e.type));
    }
    combined.sort((a, b) => b.date.compareTo(a.date));

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: combined.length,
      itemBuilder: (context, index) {
        return _buildEntryCard(combined[index]);
      },
    );
  }

  Widget _buildSummaryItem(String label, double value, Color color) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
        Text(
          _currencyFormat.format(value),
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 1,
      child: ListTile(
        leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.1),
            child: Icon(icon, color: color, size: 20)),
        title: Text(title, style: const TextStyle(fontSize: 13)),
        trailing: Text(value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      ),
    );
  }

  Widget _buildEntryCard(_CombinedEntry entry) {
    final color = entry.isIncome ? Colors.green : Colors.red;
    final icon = entry.isIncome ? Icons.arrow_downward : Icons.arrow_upward;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.1),
              radius: 18,
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.description.isNotEmpty
                        ? entry.description
                        : entry.type,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Text(
                    _dateFormat.format(entry.date),
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Text(
              '${entry.isIncome ? '+' : '-'}${_currencyFormat.format(entry.amount)}',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateFilterButton({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
    required double height,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
                Text(date != null ? _dateFormat.format(date) : '-',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w500)),
              ],
            ),
            const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickChip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(
              fontSize: 11, color: selected ? Colors.white : Colors.black)),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: Theme.of(context).primaryColor,
      backgroundColor: Colors.grey[200],
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20), side: BorderSide.none),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _IncomeEntry {
  _IncomeEntry(
      {required this.date, required this.description, required this.amount});
  final DateTime date;
  final String description;
  final double amount;

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'description': description,
    'amount': amount,
  };

  factory _IncomeEntry.fromJson(Map<String, dynamic> json) => _IncomeEntry(
    date: DateTime.parse(json['date'] as String),
    description: json['description'] as String,
    amount: (json['amount'] as num).toDouble(),
  );
}

class _ExpenseEntry {
  _ExpenseEntry(
      {required this.date,
      required this.type,
      required this.description,
      required this.amount,
      required this.isSalary});
  final DateTime date;
  final String type;
  final String description;
  final double amount;
  final bool isSalary;

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'type': type,
    'description': description,
    'amount': amount,
    'isSalary': isSalary,
  };

  factory _ExpenseEntry.fromJson(Map<String, dynamic> json) => _ExpenseEntry(
    date: DateTime.parse(json['date'] as String),
    type: json['type'] as String,
    description: json['description'] as String,
    amount: (json['amount'] as num).toDouble(),
    isSalary: json['isSalary'] as bool,
  );
}

class _CombinedEntry {
  _CombinedEntry(
      {required this.date,
      required this.description,
      required this.amount,
      required this.isIncome,
      required this.isSalary,
      required this.type});
  final DateTime date;
  final String description;
  final double amount;
  final bool isIncome;
  final bool isSalary;
  final String type;
}

class _ReportParams {
  _ReportParams(
      {required this.payments,
      required this.expenses,
      required this.fromDate,
      required this.toDate});
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> expenses;
  final DateTime fromDate;
  final DateTime toDate;
}

class _ReportResult {
  _ReportResult(
      {required this.incomeEntries,
      required this.expenseEntries,
      required this.incomeTotal,
      required this.expenseTotal,
      required this.salaryTotal,
      required this.net});

  final List<_IncomeEntry> incomeEntries;
  final List<_ExpenseEntry> expenseEntries;
  final double incomeTotal;
  final double expenseTotal;
  final double salaryTotal;
  final double net;

  Map<String, dynamic> toJson() => {
    'incomeEntries': incomeEntries.map((e) => e.toJson()).toList(),
    'expenseEntries': expenseEntries.map((e) => e.toJson()).toList(),
    'incomeTotal': incomeTotal,
    'expenseTotal': expenseTotal,
    'salaryTotal': salaryTotal,
    'net': net,
  };

  factory _ReportResult.fromJson(Map<String, dynamic> json) => _ReportResult(
    incomeEntries: (json['incomeEntries'] as List)
        .map((e) => _IncomeEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
    expenseEntries: (json['expenseEntries'] as List)
        .map((e) => _ExpenseEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
    incomeTotal: (json['incomeTotal'] as num).toDouble(),
    expenseTotal: (json['expenseTotal'] as num).toDouble(),
    salaryTotal: (json['salaryTotal'] as num).toDouble(),
    net: (json['net'] as num).toDouble(),
  );
}

_ReportResult _processReportData(_ReportParams params) {
  bool isWithinRange(DateTime date) {
    final endOfDay = DateTime(
        params.toDate.year, params.toDate.month, params.toDate.day, 23, 59, 59);
    return !date.isBefore(params.fromDate) && !date.isAfter(endOfDay);
  }

  bool isSalaryExpense(String type) => type.trim().contains('راتب');

  final incomeList = <_IncomeEntry>[];
  for (final p in params.payments) {
    final dateStr = (p['date'] ?? '').toString().trim();
    if (dateStr.isEmpty) continue;
    DateTime? dt;
    try {
      dt = DateTime.parse(
          dateStr.length > 10 ? dateStr.replaceFirst(' ', 'T') : dateStr);
    } catch (_) {
      continue;
    }
    if (!isWithinRange(dt)) continue;
    incomeList.add(_IncomeEntry(
        date: dt,
        description: 'دفعة حجز - ${p['guestName'] ?? ''}',
        amount: ((p['amount'] ?? 0) as num).toDouble()));
  }

  final expenseList = <_ExpenseEntry>[];
  for (final e in params.expenses) {
    final dateStr = (e['date'] ?? '').toString().trim();
    if (dateStr.isEmpty) continue;
    DateTime? dt;
    try {
      dt = DateTime.parse(
          dateStr.length > 10 ? dateStr.replaceFirst(' ', 'T') : dateStr);
    } catch (_) {
      continue;
    }
    if (!isWithinRange(dt)) continue;
    final type = (e['type'] ?? '').toString();
    expenseList.add(_ExpenseEntry(
        date: dt,
        type: type,
        description: (e['description'] ?? '').toString(),
        amount: ((e['amount'] ?? 0) as num).toDouble(),
        isSalary: isSalaryExpense(type)));
  }

  incomeList.sort((a, b) => a.date.compareTo(b.date));
  expenseList.sort((a, b) => a.date.compareTo(b.date));

  final incTotal = incomeList.fold<double>(0, (s, e) => s + e.amount);
  final expTotal = expenseList.fold<double>(0, (s, e) => s + e.amount);
  final salTotal = expenseList
      .where((e) => e.isSalary)
      .fold<double>(0, (s, e) => s + e.amount);

  return _ReportResult(
      incomeEntries: incomeList,
      expenseEntries: expenseList,
      incomeTotal: incTotal,
      expenseTotal: expTotal,
      salaryTotal: salTotal,
      net: incTotal - expTotal);
}
