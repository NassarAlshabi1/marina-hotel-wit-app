import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfColor;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../components/app_scaffold.dart';
import '../../components/widgets/empty_state.dart';
import '../../components/widgets/neu_card.dart';
import '../../providers/repository_providers.dart';
import '../../services/daos/payments_dao.dart';
import '../../services/daos/expenses_dao.dart';
import '../../services/daos/outbox_dao.dart';
import '../../utils/enhanced_pdf_utils.dart';

class IncomeExpenseReportScreen extends ConsumerStatefulWidget {
  const IncomeExpenseReportScreen({super.key});

  @override
  ConsumerState<IncomeExpenseReportScreen> createState() =>
      _IncomeExpenseReportScreenState();
}

class _IncomeExpenseReportScreenState
    extends ConsumerState<IncomeExpenseReportScreen> {
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');
  final NumberFormat _currencyFormat = NumberFormat('#,##0', 'en_US');

  DateTime _toDate = DateTime.now();
  late DateTime _fromDate;

  bool _loading = false;
  bool _detailedMode = false;

  List<_IncomeEntry> _incomeEntries = [];
  List<_ExpenseEntry> _expenseEntries = [];

  double _incomeTotal = 0;
  double _expenseTotal = 0;
  double _salaryTotal = 0;
  double _net = 0;

  @override
  void initState() {
    super.initState();
    _fromDate = DateTime(_toDate.year, _toDate.month, 1);
    _toDate = DateTime(_toDate.year, _toDate.month, _toDate.day, 23, 59, 59);
    _fetchReport();
  }

  Future<void> _fetchReport() async {
    setState(() => _loading = true);
    try {
      final db = ref.read(databaseProvider);
      final outboxDao = OutboxDao(db);
      final paymentsDao = PaymentsDao(db, outboxDao);
      final expensesDao = ExpensesDao(db, outboxDao);

      final fromStr = _dateFormat.format(_fromDate);
      final toStr = _dateFormat.format(_toDate);

      final payments = await paymentsDao.list(from: fromStr, to: toStr);
      final expenses = await expensesDao.list(from: fromStr, to: toStr);

      final result = await compute(
        _processReportData,
        _ReportParams(
          payments: payments
              .map(
                (p) => {
                  'date': p.paymentDate,
                  'roomNumber': p.roomNumber ?? '',
                  'guestName': '',
                  'amount': p.amount,
                },
              )
              .toList(),
          expenses: expenses
              .map(
                (e) => {
                  'date': e.date,
                  'type': e.expenseType,
                  'description': e.description,
                  'amount': e.amount,
                },
              )
              .toList(),
          fromDate: _fromDate,
          toDate: _toDate,
        ),
      );

      if (mounted) {
        setState(() {
          _incomeEntries = result.incomeEntries;
          _expenseEntries = result.expenseEntries;
          _incomeTotal = result.incomeTotal;
          _expenseTotal = result.expenseTotal;
          _salaryTotal = result.salaryTotal;
          _net = result.net;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
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
          if (_fromDate.isAfter(_toDate)) {
            _toDate = DateTime(
              picked.year,
              picked.month,
              picked.day,
              23,
              59,
              59,
            );
          }
        } else {
          _toDate = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
          if (_toDate.isBefore(_fromDate)) {
            _fromDate = DateTime(
              picked.year,
              picked.month,
              picked.day,
              0,
              0,
              0,
            );
          }
        }
      });
      _fetchReport();
    }
  }

  bool _isToday() {
    final now = DateTime.now();
    return _fromDate.year == now.year &&
        _fromDate.month == now.month &&
        _fromDate.day == now.day &&
        _toDate.year == now.year &&
        _toDate.month == now.month &&
        _toDate.day == now.day;
  }

  bool _isThisWeek() {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    return _fromDate.year == weekStart.year &&
        _fromDate.month == weekStart.month &&
        _fromDate.day == weekStart.day;
  }

  bool _isThisMonth() {
    final now = DateTime.now();
    return _fromDate.year == now.year &&
        _fromDate.month == now.month &&
        _fromDate.day == 1;
  }

  bool _isThisYear() {
    final now = DateTime.now();
    return _fromDate.year == now.year &&
        _fromDate.month == 1 &&
        _fromDate.day == 1;
  }

  void _setQuickFilter(String type) {
    final now = DateTime.now();
    setState(() {
      switch (type) {
        case 'today':
          _fromDate = DateTime(now.year, now.month, now.day, 0, 0, 0);
          _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
          break;
        case 'week':
          final weekStart = now.subtract(Duration(days: now.weekday - 1));
          _fromDate = DateTime(
            weekStart.year,
            weekStart.month,
            weekStart.day,
            0,
            0,
            0,
          );
          _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
          break;
        case 'month':
          _fromDate = DateTime(now.year, now.month, 1, 0, 0, 0);
          _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
          break;
        case 'year':
          _fromDate = DateTime(now.year, 1, 1, 0, 0, 0);
          _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
          break;
      }
    });
    _fetchReport();
  }

  // ===== أسماء الأيام والشهور بالعربي =====
  static const _arabicDays = [
    'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس',
    'الجمعة', 'السبت', 'الأحد',
  ];
  static const _arabicMonths = [
    '', 'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

  String _arabicDayName(DateTime date) {
    return _arabicDays[date.weekday - 1];
  }

  // ===== تجميع البيانات =====
  String _getGroupKey(DateTime date, String groupBy) {
    switch (groupBy) {
      case 'daily':
        return DateFormat('yyyy-MM-dd').format(date);
      case 'monthly':
        return DateFormat('yyyy-MM').format(date);
      case 'yearly':
        return DateFormat('yyyy').format(date);
      default:
        return 'all';
    }
  }

  String _getGroupLabel(String key, String groupBy) {
    switch (groupBy) {
      case 'daily':
        final dt = DateTime.parse(key);
        return '${dt.day} ${_arabicMonths[dt.month]} ${dt.year} (${_arabicDayName(dt)})';
      case 'monthly':
        final parts = key.split('-');
        return '${_arabicMonths[int.parse(parts[1])]} ${parts[0]}';
      case 'yearly':
        return '$key م';
      default:
        return '';
    }
  }

  String _getGroupTypeLabel(String groupBy) {
    switch (groupBy) {
      case 'daily':
        return 'يومي';
      case 'monthly':
        return 'شهري';
      case 'yearly':
        return 'سنوي';
      default:
        return 'عام';
    }
  }

  List<_GroupedData> _buildGroupedData(String groupBy) {
    final incomeMap = <String, List<_IncomeEntry>>{};
    final expenseMap = <String, List<_ExpenseEntry>>{};

    for (final e in _incomeEntries) {
      final key = _getGroupKey(e.date, groupBy);
      incomeMap.putIfAbsent(key, () => []).add(e);
    }
    for (final e in _expenseEntries) {
      final key = _getGroupKey(e.date, groupBy);
      expenseMap.putIfAbsent(key, () => []).add(e);
    }

    final allKeys = <String>{...incomeMap.keys, ...expenseMap.keys}.toList()
      ..sort();

    return allKeys.asMap().entries.map((entry) {
      final idx = entry.key;
      final key = entry.value;
      final inc = incomeMap[key] ?? [];
      final exp = expenseMap[key] ?? [];
      final incTotal = inc.fold<double>(0, (s, e) => s + e.amount);
      final expTotal = exp.fold<double>(0, (s, e) => s + e.amount);
      final salTotal =
          exp.where((e) => e.isSalary).fold<double>(0, (s, e) => s + e.amount);
      return _GroupedData(
        index: idx + 1,
        key: key,
        label: _getGroupLabel(key, groupBy),
        incomeEntries: inc,
        expenseEntries: exp,
        incomeTotal: incTotal,
        expenseTotal: expTotal,
        salaryTotal: salTotal,
        net: incTotal - expTotal,
        incomeCount: inc.length,
        expenseCount: exp.length,
      );
    }).toList();
  }

  // ===== بناء PDF التقرير العادي =====
  Future<pw.Document> _buildPdfDocument() async {
    final fonts = await EnhancedPdfUtils.loadArabicFonts();
    final doc = pw.Document();

    pw.Widget buildSummaryBox(String title, String value, PdfColor color) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColors.backgroundLight,
          border: pw.Border.all(color: color, width: 0.6),
        ),
        child: pw.Column(
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                font: fonts.regular,
                fontSize: 11,
                color: PdfColors.textDark,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              value,
              style: pw.TextStyle(font: fonts.bold, fontSize: 16, color: color),
            ),
          ],
        ),
      );
    }

    pw.Widget buildDetailTable(String title, List<List<String>> rows) {
      if (!_detailedMode || rows.isEmpty) return pw.Container();
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(font: fonts.bold, fontSize: 14)),
          pw.SizedBox(height: 6),
          EnhancedPdfUtils.buildProfessionalTable(
            headers: ['التاريخ', 'الوصف', 'المبلغ'],
            data: rows,
            fonts: fonts,
            headerColor: PdfColors.primary,
            alternateRowColor: PdfColors.backgroundLight,
          ),
          pw.SizedBox(height: 12),
        ],
      );
    }

    final incomeRows = _detailedMode
        ? _incomeEntries
              .map(
                (e) => [
                  _dateFormat.format(e.date),
                  e.description,
                  EnhancedPdfUtils.formatNumber(e.amount),
                ],
              )
              .toList()
        : const <List<String>>[];
    final expenseRows = _detailedMode
        ? _expenseEntries
              .map(
                (e) => [
                  _dateFormat.format(e.date),
                  e.description.isNotEmpty ? e.description : e.type,
                  EnhancedPdfUtils.formatNumber(e.amount),
                ],
              )
              .toList()
        : const <List<String>>[];

    final fromLabel = DateFormat('yyyy-MM-dd').format(_fromDate);
    final toLabel = DateFormat('yyyy-MM-dd').format(_toDate);

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
          pw.Container(
            width: double.infinity,
            decoration: const pw.BoxDecoration(color: PdfColors.primary),
            padding: const pw.EdgeInsets.all(20),
            child: pw.Column(
              children: [
                pw.Text(
                  'تقرير الدخل والمصروفات',
                  style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: 20,
                    color: PdfColors.textWhite,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'الفترة من $fromLabel إلى $toLabel',
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 12,
                    color: PdfColors.textWhite,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            children: [
              pw.Expanded(
                child: buildSummaryBox(
                  'إجمالي الدخل',
                  EnhancedPdfUtils.formatNumber(_incomeTotal),
                  PdfColors.success,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: buildSummaryBox(
                  'إجمالي المصروفات',
                  EnhancedPdfUtils.formatNumber(_expenseTotal),
                  PdfColors.danger,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              pw.Expanded(
                child: buildSummaryBox(
                  'مصروفات الرواتب',
                  EnhancedPdfUtils.formatNumber(_salaryTotal),
                  PdfColors.warning,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: buildSummaryBox(
                  'صافي الربح/الخسارة',
                  EnhancedPdfUtils.formatNumber(_net),
                  _net >= 0 ? PdfColors.success : PdfColors.danger,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          buildDetailTable('تفاصيل الدخل', incomeRows),
          buildDetailTable('تفاصيل المصروفات', expenseRows),
        ],
      ),
    );

    return doc;
  }

  // ===== بناء PDF التقرير التفصيلي المجمع =====
  Future<pw.Document> _buildDetailedGroupedPdf(String groupBy) async {
    final fonts = await EnhancedPdfUtils.loadArabicFonts();
    final doc = pw.Document();
    final groupedData = _buildGroupedData(groupBy);
    final groupTypeLabel = _getGroupTypeLabel(groupBy);
    final fromLabel = DateFormat('yyyy-MM-dd').format(_fromDate);
    final toLabel = DateFormat('yyyy-MM-dd').format(_toDate);

    /// بناء صندوق ملخص ملون
    pw.Widget buildSummaryBox(String title, String value, PdfColor color) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: pw.BoxDecoration(
          color: PdfColors.backgroundLight,
          border: pw.Border.all(color: color, width: 0.8),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                font: fonts.regular,
                fontSize: 10,
                color: PdfColors.textLight,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              value,
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 15,
                color: color,
              ),
            ),
          ],
        ),
      );
    }

    /// بناء بطاقة فترة مرقمة
    pw.Widget buildPeriodCard(_GroupedData group) {
      final isProfit = group.net >= 0;
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(
            color: isProfit ? PdfColors.success : PdfColors.danger,
            width: 0.8,
          ),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // عنوان الفترة المرقم
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColors.primary,
                borderRadius: const pw.BorderRadius.only(
                  topLeft: pw.Radius.circular(7),
                  topRight: pw.Radius.circular(7),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '$group.index. ${group.label}',
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 13,
                      color: PdfColors.textWhite,
                    ),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: pw.BoxDecoration(
                      color: isProfit
                          ? PdfColors.success
                          : PdfColors.danger,
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(10),
                      ),
                    ),
                    child: pw.Text(
                      isProfit ? 'ربح' : 'خسارة',
                      style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 9,
                        color: PdfColors.textWhite,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              child: pw.Column(
                children: [
                  // 4 صناديق ملخص مصغرة
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(6),
                          margin: const pw.EdgeInsets.only(left: 4),
                          decoration: pw.BoxDecoration(
                            color: PdfColors.success,
                            borderRadius: const pw.BorderRadius.all(
                              pw.Radius.circular(4),
                            ),
                          ),
                          child: pw.Column(
                            children: [
                              pw.Text(
                                'الدخل',
                                style: pw.TextStyle(
                                  font: fonts.regular,
                                  fontSize: 9,
                                  color: PdfColors.textWhite,
                                ),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                EnhancedPdfUtils.formatNumber(group.incomeTotal),
                                style: pw.TextStyle(
                                  font: fonts.bold,
                                  fontSize: 12,
                                  color: PdfColors.textWhite,
                                ),
                              ),
                              pw.Text(
                                '${group.incomeCount} معاملة',
                                style: pw.TextStyle(
                                  font: fonts.regular,
                                  fontSize: 8,
                                  color: PdfColors.textWhite,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(6),
                          margin: const pw.EdgeInsets.only(left: 4),
                          decoration: pw.BoxDecoration(
                            color: PdfColors.danger,
                            borderRadius: const pw.BorderRadius.all(
                              pw.Radius.circular(4),
                            ),
                          ),
                          child: pw.Column(
                            children: [
                              pw.Text(
                                'المصروفات',
                                style: pw.TextStyle(
                                  font: fonts.regular,
                                  fontSize: 9,
                                  color: PdfColors.textWhite,
                                ),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                EnhancedPdfUtils.formatNumber(group.expenseTotal),
                                style: pw.TextStyle(
                                  font: fonts.bold,
                                  fontSize: 12,
                                  color: PdfColors.textWhite,
                                ),
                              ),
                              pw.Text(
                                '${group.expenseCount} معاملة',
                                style: pw.TextStyle(
                                  font: fonts.regular,
                                  fontSize: 8,
                                  color: PdfColors.textWhite,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(6),
                          decoration: pw.BoxDecoration(
                            color: group.salaryTotal > 0
                                ? PdfColors.warning
                                : PdfColors.backgroundCard,
                            borderRadius: const pw.BorderRadius.all(
                              pw.Radius.circular(4),
                            ),
                          ),
                          child: pw.Column(
                            children: [
                              pw.Text(
                                'الرواتب',
                                style: pw.TextStyle(
                                  font: fonts.regular,
                                  fontSize: 9,
                                  color: group.salaryTotal > 0
                                      ? PdfColors.textWhite
                                      : PdfColors.textLight,
                                ),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                EnhancedPdfUtils.formatNumber(group.salaryTotal),
                                style: pw.TextStyle(
                                  font: fonts.bold,
                                  fontSize: 12,
                                  color: group.salaryTotal > 0
                                      ? PdfColors.textWhite
                                      : PdfColors.textLight,
                                ),
                              ),
                              pw.SizedBox(height: 10),
                            ],
                          ),
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(6),
                          decoration: pw.BoxDecoration(
                            color: isProfit
                                ? PdfColors.success
                                : PdfColors.danger,
                            borderRadius: const pw.BorderRadius.all(
                              pw.Radius.circular(4),
                            ),
                          ),
                          child: pw.Column(
                            children: [
                              pw.Text(
                                'الصافي',
                                style: pw.TextStyle(
                                  font: fonts.regular,
                                  fontSize: 9,
                                  color: PdfColors.textWhite,
                                ),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                EnhancedPdfUtils.formatNumber(group.net),
                                style: pw.TextStyle(
                                  font: fonts.bold,
                                  fontSize: 12,
                                  color: PdfColors.textWhite,
                                ),
                              ),
                              pw.SizedBox(height: 10),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  // جداول تفصيلية مضغوطة
                  pw.SizedBox(height: 8),
                  _buildMiniTable(
                    fonts,
                    'الدخل',
                    group.incomeEntries
                        .map(
                          (e) => [
                            DateFormat('dd/MM').format(e.date),
                            e.description,
                            EnhancedPdfUtils.formatNumber(e.amount),
                          ],
                        )
                        .toList(),
                    PdfColors.success,
                  ),
                  pw.SizedBox(height: 4),
                  _buildMiniTable(
                    fonts,
                    'المصروفات',
                    group.expenseEntries
                        .map(
                          (e) => [
                            DateFormat('dd/MM').format(e.date),
                            e.description.isNotEmpty ? e.description : e.type,
                            EnhancedPdfUtils.formatNumber(e.amount),
                          ],
                        )
                        .toList(),
                    PdfColors.danger,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

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
        build: (context) {
          final widgets = <pw.Widget>[
            // رأس التقرير
            pw.Container(
              width: double.infinity,
              decoration: const pw.BoxDecoration(color: PdfColors.primary),
              padding: const pw.EdgeInsets.all(20),
              child: pw.Column(
                children: [
                  pw.Text(
                    'تقرير الدخل والمصروفات التفصيلي',
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 20,
                      color: PdfColors.textWhite,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: const pw.BoxDecoration(color: PdfColors.secondary),
                    child: pw.Text(
                      'تجميع $groupTypeLabel',
                      style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 12,
                        color: PdfColors.textWhite,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'الفترة من $fromLabel إلى $toLabel',
                    style: pw.TextStyle(
                      font: fonts.regular,
                      fontSize: 12,
                      color: PdfColors.textWhite,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'عدد الفترات: ${groupedData.length}',
                    style: pw.TextStyle(
                      font: fonts.regular,
                      fontSize: 10,
                      color: PdfColors.textWhite,
                    ),
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 16),

            // 4 صناديق الملخص العام
            pw.Row(
              children: [
                pw.Expanded(
                  child: buildSummaryBox(
                    'إجمالي الدخل',
                    EnhancedPdfUtils.formatNumber(_incomeTotal),
                    PdfColors.success,
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: buildSummaryBox(
                    'إجمالي المصروفات',
                    EnhancedPdfUtils.formatNumber(_expenseTotal),
                    PdfColors.danger,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Row(
              children: [
                pw.Expanded(
                  child: buildSummaryBox(
                    'مصروفات الرواتب',
                    EnhancedPdfUtils.formatNumber(_salaryTotal),
                    PdfColors.warning,
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: buildSummaryBox(
                    'صافي الربح / الخسارة',
                    EnhancedPdfUtils.formatNumber(_net),
                    _net >= 0 ? PdfColors.success : PdfColors.danger,
                  ),
                ),
              ],
            ),

            pw.SizedBox(height: 16),

            // عنوان الأقسام
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(vertical: 8),
              decoration: const pw.BoxDecoration(
                color: PdfColors.accent,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Text(
                'التفاصيل حسب الفترة ($groupTypeLabel)',
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 14,
                  color: PdfColors.textWhite,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),

            pw.SizedBox(height: 12),
          ];

          // بطاقات الفترات
          for (final group in groupedData) {
            widgets.add(buildPeriodCard(group));
          }

          // ملخص نهائي شامل
          widgets.add(pw.SizedBox(height: 16));
          widgets.add(_buildFinalSummarySection(fonts, groupedData));

          return widgets;
        },
      ),
    );

    return doc;
  }

  /// جدول مصغر مضغوط
  pw.Widget _buildMiniTable(
    ArabicPdfFonts fonts,
    String title,
    List<List<String>> rows,
    PdfColor headerColor,
  ) {
    if (rows.isEmpty) return pw.Container();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            font: fonts.bold,
            fontSize: 10,
            color: headerColor,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.textLight, width: 0.3),
          ),
          child: pw.Table(
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: headerColor),
                children: [
                  _miniCell('التاريخ', fonts.bold, PdfColors.textWhite),
                  _miniCell('الوصف', fonts.bold, PdfColors.textWhite),
                  _miniCell('المبلغ', fonts.bold, PdfColors.textWhite),
                ],
              ),
              ...rows.asMap().entries.map((entry) {
                final isEven = entry.key % 2 == 0;
                return pw.TableRow(
                  decoration: isEven
                      ? const pw.BoxDecoration(
                          color: PdfColors.backgroundLight,
                        )
                      : null,
                  children: [
                    _miniCell(entry.value[0], fonts.regular, PdfColors.textDark),
                    _miniCell(entry.value[1], fonts.regular, PdfColors.textDark),
                    _miniCell(
                      entry.value[2],
                      fonts.bold,
                      PdfColors.textDark,
                      align: pw.TextAlign.left,
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _miniCell(
    String text,
    pw.Font font,
    PdfColor color, {
    pw.TextAlign align = pw.TextAlign.center,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(font: font, fontSize: 8, color: color),
        textAlign: align,
      ),
    );
  }

  /// ملخص نهائي شامل في آخر التقرير
  pw.Widget _buildFinalSummarySection(
    ArabicPdfFonts fonts,
    List<_GroupedData> groups,
  ) {
    // أطول فترة ربحية وخاسرة
    _GroupedData? bestPeriod;
    _GroupedData? worstPeriod;
    double maxProfit = double.negativeInfinity;
    double maxLoss = double.infinity;

    for (final g in groups) {
      if (g.net > maxProfit) {
        maxProfit = g.net;
        bestPeriod = g;
      }
      if (g.net < maxLoss) {
        maxLoss = g.net;
        worstPeriod = g;
      }
    }

    // إجمالي المعاملات
    final totalTx = _incomeEntries.length + _expenseEntries.length;
    final avgDaily = groups.isEmpty
        ? 0.0
        : _net / groups.length;

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.backgroundCard,
        border: pw.Border.all(color: PdfColors.primary, width: 1),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 6),
            child: pw.Text(
              'الملخص النهائي الشامل',
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 14,
                color: PdfColors.primary,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.SizedBox(height: 8),

          // جدول الملخص النهائي
          EnhancedPdfUtils.buildProfessionalTable(
            headers: ['البيان', 'القيمة'],
            fonts: fonts,
            headerColor: PdfColors.primary,
            alternateRowColor: PdfColors.backgroundLight,
            columnWidths: [180, 150],
            data: [
              ['إجمالي المعاملات', '$totalTx معاملة'],
              ['عدد الفترات', '${groups.length} فترة'],
              ['متوسط الصافي لكل فترة',
                EnhancedPdfUtils.formatNumber(avgDaily)],
              ['إجمالي الدخل',
                EnhancedPdfUtils.formatNumber(_incomeTotal)],
              ['إجمالي المصروفات',
                EnhancedPdfUtils.formatNumber(_expenseTotal)],
              ['مصروفات الرواتب',
                EnhancedPdfUtils.formatNumber(_salaryTotal)],
              ['الصافي النهائي',
                EnhancedPdfUtils.formatNumber(_net)],
              if (bestPeriod != null)
                ['أفضل فترة (أعلى ربح)',
                  '${bestPeriod.label} - ${EnhancedPdfUtils.formatNumber(bestPeriod.net)}'],
              if (worstPeriod != null && worstPeriod.net < 0)
                ['أسوأ فترة (أعلى خسارة)',
                  '${worstPeriod.label} - ${EnhancedPdfUtils.formatNumber(worstPeriod.net)}'],
            ],
          ),
        ],
      ),
    );
  }

  // ===== تصدير =====
  String _getFilename({String suffix = ''}) {
    final s = suffix.isNotEmpty ? '-$suffix' : '';
    return 'تقرير-الدخل-والمصروفات$s-${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';
  }

  Future<void> _exportPdf() async {
    if (_incomeEntries.isEmpty && _expenseEntries.isEmpty) return;
    final doc = await _buildPdfDocument();
    await Printing.sharePdf(bytes: await doc.save(), filename: _getFilename());
  }

  Future<void> _exportDetailedGroupedPdf(String groupBy) async {
    if (_incomeEntries.isEmpty && _expenseEntries.isEmpty) return;
    final doc = await _buildDetailedGroupedPdf(groupBy);
    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: _getFilename(suffix: _getGroupTypeLabel(groupBy)),
    );
  }

  Future<void> _printPdf() async {
    if (_incomeEntries.isEmpty && _expenseEntries.isEmpty) return;
    final doc = await _buildPdfDocument();
    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }

  Future<void> _savePdf() async {
    if (_incomeEntries.isEmpty && _expenseEntries.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final doc = await _buildPdfDocument();
      final bytes = await doc.save();
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${_getFilename()}');
      await file.writeAsBytes(bytes);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('تم حفظ الملف: ${file.path}'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(label: 'إغلاق', onPressed: () {}),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('خطأ في الحفظ: $e'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(label: 'إغلاق', onPressed: () {}),
          ),
        );
      }
    }
  }

  Future<void> _exportCsv() async {
    if (_incomeEntries.isEmpty && _expenseEntries.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final buffer = StringBuffer();
      buffer.writeln('\uFEFF');
      buffer.writeln('النوع,التاريخ,الوصف,المبلغ,التصنيف');

      final allEntries = <Map<String, dynamic>>[];
      for (final e in _incomeEntries) {
        allEntries.add({
          'type': 'دخل',
          'date': _dateFormat.format(e.date),
          'desc': e.description,
          'amount': e.amount,
          'category': 'دفعة',
        });
      }
      for (final e in _expenseEntries) {
        allEntries.add({
          'type': e.isSalary ? 'راتب' : 'مصروف',
          'date': _dateFormat.format(e.date),
          'desc': e.description.isNotEmpty ? e.description : e.type,
          'amount': e.amount,
          'category': e.type,
        });
      }
      allEntries.sort((a, b) =>
          DateTime.parse(a['date']).compareTo(DateTime.parse(b['date'])));

      for (final entry in allEntries) {
        buffer.writeln(
          '${entry["type"]},${entry["date"]},"${entry["desc"]}",${entry["amount"]},${entry["category"]}',
        );
      }

      buffer.writeln();
      buffer.writeln('الملخص');
      buffer.writeln('إجمالي الدخل,$_incomeTotal');
      buffer.writeln('إجمالي المصروفات,$_expenseTotal');
      buffer.writeln('مصروفات الرواتب,$_salaryTotal');
      buffer.writeln('صافي الربح,$_net');

      final csvBytes = buffer.toString().codeUnits;
      final dir = await getTemporaryDirectory();
      final filename =
          'تقرير-${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(csvBytes);

      if (mounted) {
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'تقرير الدخل والمصروفات',
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('خطأ في تصدير CSV: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // ===== نافذة خيارات التصدير =====
  void _showExportOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            controller: scrollController,
            children: [
              // مقبض السحب
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'تصدير التقرير',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // ===== قسم التقرير التفصيلي =====
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.summarize_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'تقرير تفصيلي',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'تقرير PDF مفصل مع تجميع حسب الفترة وملخص نهائي شامل',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 10),
                    _buildExportOption(
                      icon: Icons.calendar_today_rounded,
                      iconColor: Colors.blue,
                      iconBg: Colors.blue.withOpacity(0.1),
                      title: 'تقرير يومي',
                      subtitle: 'تجميع حسب كل يوم (مع اسم اليوم بالعربي)',
                      onTap: () {
                        Navigator.pop(context);
                        _exportDetailedGroupedPdf('daily');
                      },
                    ),
                    _buildExportOption(
                      icon: Icons.calendar_month_rounded,
                      iconColor: Colors.teal,
                      iconBg: Colors.teal.withOpacity(0.1),
                      title: 'تقرير شهري',
                      subtitle: 'تجميع حسب كل شهر (بالأسماء العربية)',
                      onTap: () {
                        Navigator.pop(context);
                        _exportDetailedGroupedPdf('monthly');
                      },
                    ),
                    _buildExportOption(
                      icon: Icons.date_range_rounded,
                      iconColor: Colors.purple,
                      iconBg: Colors.purple.withOpacity(0.1),
                      title: 'تقرير سنوي',
                      subtitle: 'تجميع حسب كل سنة',
                      onTap: () {
                        Navigator.pop(context);
                        _exportDetailedGroupedPdf('yearly');
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ===== قسم التصدير العام =====
              _buildExportOption(
                icon: Icons.share,
                iconColor: Colors.blue,
                iconBg: Colors.blue.withOpacity(0.1),
                title: 'مشاركة PDF',
                subtitle: 'إرسال التقرير العام عبر التطبيقات',
                onTap: () {
                  Navigator.pop(context);
                  _exportPdf();
                },
              ),
              _buildExportOption(
                icon: Icons.print,
                iconColor: Colors.green,
                iconBg: Colors.green.withOpacity(0.1),
                title: 'طباعة',
                subtitle: 'طباعة التقرير مباشرة',
                onTap: () {
                  Navigator.pop(context);
                  _printPdf();
                },
              ),
              _buildExportOption(
                icon: Icons.save_alt,
                iconColor: Colors.orange,
                iconBg: Colors.orange.withOpacity(0.1),
                title: 'حفظ في الجهاز',
                subtitle: 'حفظ كملف PDF',
                onTap: () {
                  Navigator.pop(context);
                  _savePdf();
                },
              ),
              _buildExportOption(
                icon: Icons.table_chart,
                iconColor: Colors.indigo,
                iconBg: Colors.indigo.withOpacity(0.1),
                title: 'تصدير CSV',
                subtitle: 'ملف جدول بيانات لفتحه في Excel',
                onTap: () {
                  Navigator.pop(context);
                  _exportCsv();
                },
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExportOption({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasData = _incomeEntries.isNotEmpty || _expenseEntries.isNotEmpty;
    return AppScaffold(
      title: 'تقرير الدخل والمصروفات',
      actions: [
        IconButton(
          icon: const Icon(Icons.picture_as_pdf),
          tooltip: 'تصدير PDF',
          onPressed: !hasData || _loading ? null : _showExportOptions,
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          children: [
            NeuCard(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.date_range_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'فترة التقرير',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: NeuDateButton(
                          icon: Icons.calendar_month_rounded,
                          label: 'من: ${_dateFormat.format(_fromDate)}',
                          onTap: () => _pickDate(isFrom: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: NeuDateButton(
                          icon: Icons.event_rounded,
                          label: 'إلى: ${_dateFormat.format(_toDate)}',
                          onTap: () => _pickDate(isFrom: false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        NeuQuickFilterChip(
                          label: 'اليوم',
                          selected: _isToday(),
                          onTap: () => _setQuickFilter('today'),
                        ),
                        const SizedBox(width: 6),
                        NeuQuickFilterChip(
                          label: 'الأسبوع',
                          selected: _isThisWeek(),
                          onTap: () => _setQuickFilter('week'),
                        ),
                        const SizedBox(width: 6),
                        NeuQuickFilterChip(
                          label: 'الشهر',
                          selected: _isThisMonth(),
                          onTap: () => _setQuickFilter('month'),
                        ),
                        const SizedBox(width: 6),
                        NeuQuickFilterChip(
                          label: 'السنة',
                          selected: _isThisYear(),
                          onTap: () => _setQuickFilter('year'),
                        ),
                        const SizedBox(width: 10),
                        NeuQuickFilterChip(
                          label: _detailedMode ? 'تفصيلي' : 'ملخص',
                          selected: _detailedMode,
                          onTap: () =>
                              setState(() => _detailedMode = !_detailedMode),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _buildSummaryCards(),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : (_incomeEntries.isEmpty && _expenseEntries.isEmpty)
                  ? const EmptyState(
                      title: 'لا توجد بيانات',
                      message: 'لا يوجد دخل أو مصروفات ضمن الفترة المحددة.',
                      icon: Icons.receipt_long,
                    )
                  : _buildDetails(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        SizedBox(
          width: 140,
          child: NeuStatCard(
            icon: Icons.trending_down_rounded,
            title: 'إجمالي الدخل',
            value: _currencyFormat.format(_incomeTotal),
            iconColor: Colors.green,
            valueColor: Colors.green.shade700,
          ),
        ),
        SizedBox(
          width: 140,
          child: NeuStatCard(
            icon: Icons.trending_up_rounded,
            title: 'إجمالي المصروفات',
            value: _currencyFormat.format(_expenseTotal),
            iconColor: Colors.red,
            valueColor: Colors.red.shade700,
          ),
        ),
        SizedBox(
          width: 140,
          child: NeuStatCard(
            icon: Icons.people_rounded,
            title: 'مصروفات الرواتب',
            value: _currencyFormat.format(_salaryTotal),
            iconColor: Colors.orange,
            valueColor: Colors.orange.shade700,
          ),
        ),
        SizedBox(
          width: 140,
          child: NeuStatCard(
            icon: _net >= 0
                ? Icons.rocket_launch_rounded
                : Icons.warning_rounded,
            title: 'صافي الربح',
            value: _currencyFormat.format(_net),
            iconColor: _net >= 0 ? Colors.teal : Colors.red,
            valueColor: _net >= 0 ? Colors.teal.shade700 : Colors.red.shade700,
            emphasize: true,
          ),
        ),
      ],
    );
  }

  Widget _buildDetails() {
    if (!_detailedMode) {
      return _buildStatsList();
    }
    return _buildCombinedList();
  }

  Widget _buildCombinedList() {
    final List<_CombinedEntry> combined = [];
    for (final e in _incomeEntries) {
      combined.add(
        _CombinedEntry(
          date: e.date,
          description: e.description,
          amount: e.amount,
          isIncome: true,
          isSalary: false,
          type: '',
        ),
      );
    }
    for (final e in _expenseEntries) {
      combined.add(
        _CombinedEntry(
          date: e.date,
          description: e.description.isNotEmpty ? e.description : e.type,
          amount: e.amount,
          isIncome: false,
          isSalary: e.isSalary,
          type: e.type,
        ),
      );
    }
    combined.sort((a, b) => b.date.compareTo(a.date));

    if (combined.isEmpty) {
      return const Center(child: Text('لا توجد بيانات'));
    }

    return ListView.builder(
      cacheExtent: 500,
      itemCount: combined.length,
      itemBuilder: (context, index) {
        final entry = combined[index];
        final color = entry.isIncome
            ? Colors.green
            : (entry.isSalary ? Colors.orange : Colors.red);
        final icon = entry.isIncome
            ? Icons.arrow_downward
            : (entry.isSalary ? Icons.people : Icons.arrow_upward);

        return Card(
          elevation: 0.5,
          margin: const EdgeInsets.symmetric(vertical: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            dense: true,
            leading: CircleAvatar(
              backgroundColor: color.withOpacity(0.1),
              radius: 14,
              child: Icon(icon, color: color, size: 14),
            ),
            title: Text(
              entry.description,
              style: const TextStyle(fontSize: 11),
            ),
            subtitle: Row(
              children: [
                Text(
                  _dateFormat.format(entry.date),
                  style: const TextStyle(fontSize: 9),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    entry.isIncome
                        ? 'دخل'
                        : (entry.isSalary ? 'راتب' : 'مصروف'),
                    style: TextStyle(fontSize: 8, color: color),
                  ),
                ),
              ],
            ),
            trailing: Text(
              '${entry.isIncome ? '+' : '-'}${_currencyFormat.format(entry.amount)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 11,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatsList() {
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            dense: true,
            leading: const Icon(Icons.arrow_downward, color: Colors.green, size: 18),
            title: const Text('عدد معاملات الدخل', style: TextStyle(fontSize: 11)),
            trailing: Text('${_incomeEntries.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: const Icon(Icons.arrow_upward, color: Colors.red, size: 18),
            title: const Text('عدد معاملات المصروفات', style: TextStyle(fontSize: 11)),
            trailing: Text('${_expenseEntries.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: const Icon(Icons.people, color: Colors.orange, size: 18),
            title: const Text('عدد معاملات الرواتب', style: TextStyle(fontSize: 11)),
            trailing: Text(
              '${_expenseEntries.where((e) => e.isSalary).length}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

// ===== نماذج البيانات =====

class _GroupedData {
  final int index;
  final String key;
  final String label;
  final List<_IncomeEntry> incomeEntries;
  final List<_ExpenseEntry> expenseEntries;
  final double incomeTotal;
  final double expenseTotal;
  final double salaryTotal;
  final double net;
  final int incomeCount;
  final int expenseCount;

  _GroupedData({
    required this.index,
    required this.key,
    required this.label,
    required this.incomeEntries,
    required this.expenseEntries,
    required this.incomeTotal,
    required this.expenseTotal,
    required this.salaryTotal,
    required this.net,
    required this.incomeCount,
    required this.expenseCount,
  });
}

class _IncomeEntry {
  _IncomeEntry({
    required this.date,
    required this.description,
    required this.amount,
  });

  final DateTime date;
  final String description;
  final double amount;
}

class _ExpenseEntry {
  _ExpenseEntry({
    required this.date,
    required this.type,
    required this.description,
    required this.amount,
    required this.isSalary,
  });

  final DateTime date;
  final String type;
  final String description;
  final double amount;
  final bool isSalary;
}

class _CombinedEntry {
  _CombinedEntry({
    required this.date,
    required this.description,
    required this.amount,
    required this.isIncome,
    required this.isSalary,
    required this.type,
  });

  final DateTime date;
  final String description;
  final double amount;
  final bool isIncome;
  final bool isSalary;
  final String type;
}

class _ReportParams {
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> expenses;
  final DateTime fromDate;
  final DateTime toDate;

  _ReportParams({
    required this.payments,
    required this.expenses,
    required this.fromDate,
    required this.toDate,
  });
}

class _ReportResult {
  final List<_IncomeEntry> incomeEntries;
  final List<_ExpenseEntry> expenseEntries;
  final double incomeTotal;
  final double expenseTotal;
  final double salaryTotal;
  final double net;

  _ReportResult({
    required this.incomeEntries,
    required this.expenseEntries,
    required this.incomeTotal,
    required this.expenseTotal,
    required this.salaryTotal,
    required this.net,
  });
}

_ReportResult _processReportData(_ReportParams params) {
  bool isWithinRange(DateTime date) {
    final endOfDay = DateTime(
      params.toDate.year,
      params.toDate.month,
      params.toDate.day,
      23,
      59,
      59,
    );
    return !date.isBefore(params.fromDate) && !date.isAfter(endOfDay);
  }

  bool isSalaryExpense(String type) {
    return type.trim().contains('راتب');
  }

  final incomeList = <_IncomeEntry>[];
  for (final p in params.payments) {
    final dateStr = (p['date'] ?? '').toString().trim();
    if (dateStr.isEmpty) continue;
    DateTime? dt;
    try {
      dt = DateTime.parse(
        dateStr.length > 10 ? dateStr.replaceFirst(' ', 'T') : dateStr,
      );
    } catch (_) {
      continue;
    }
    if (!isWithinRange(dt)) continue;
    final room = (p['roomNumber'] ?? '').toString().trim();
    final desc = room.isNotEmpty
        ? 'دفعة من حجز غرفة $room'
        : 'دفعة من حجز';
    incomeList.add(
      _IncomeEntry(
        date: dt,
        description: desc,
        amount: ((p['amount'] ?? 0) as num).toDouble(),
      ),
    );
  }

  final expenseList = <_ExpenseEntry>[];
  for (final e in params.expenses) {
    final dateStr = (e['date'] ?? '').toString().trim();
    if (dateStr.isEmpty) continue;
    DateTime? dt;
    try {
      dt = DateTime.parse(
        dateStr.length > 10 ? dateStr.replaceFirst(' ', 'T') : dateStr,
      );
    } catch (_) {
      continue;
    }
    if (!isWithinRange(dt)) continue;
    final type = (e['type'] ?? '').toString();
    expenseList.add(
      _ExpenseEntry(
        date: dt,
        type: type,
        description: (e['description'] ?? '').toString(),
        amount: ((e['amount'] ?? 0) as num).toDouble(),
        isSalary: isSalaryExpense(type),
      ),
    );
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
    net: incTotal - expTotal,
  );
}
