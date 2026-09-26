import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' hide PdfColors;
import 'package:pdf/widgets.dart' as pw;

import 'enhanced_pdf_utils.dart';

/// ═══════════════════════════════════════════════════════════════════
/// توليد PDF لتقرير الدخل والمصروفات داخل isolate منفصل.
///
/// ✅ إصلاح انهيار «يتوقف التطبيق عند تصدير PDF»:
/// كان بناء المستند الكامل (تخطيط آلاف الصفوف + تشكيل عربي ثقيل
/// + تسلسل وضغط zlib عبر doc.save()) يُنفَّذ على الخيط الرئيسي (UI)
/// فتجمّد الواجهة ثوانٍ طويلة ثم يظهر ANR ويُقتل التطبيق.
/// الآن يُنفَّذ البناء والتسلسل بالكامل في خلفية عبر compute().
///
/// كل البيانات هنا قابلة للإرسال بين isolates (أنماط بدائية،
/// List<Map>، Uint8List، DateTime) — نفس نمط _ReportParams في الشاشة.
/// ═══════════════════════════════════════════════════════════════════

/// بيانات التقرير القابلة للإرسال إلى isolate.
class IncomeExpensePdfParams {
  IncomeExpensePdfParams({
    required this.incomeRows,
    required this.expenseRows,
    required this.fromDate,
    required this.toDate,
    required this.incomeTotal,
    required this.expenseTotal,
    required this.salaryTotal,
    required this.net,
    required this.fontRegularBytes,
    required this.fontBoldBytes,
    this.bookingsCount = 0,
    this.activeBookingsCount = 0,
    this.checkoutBookingsCount = 0,
    this.totalDebtsCount = 0,
    this.unsettledDebtsCount = 0,
    this.unsettledDebtsAmount = 0,
    this.unsettledDebtsInPeriodCount = 0,
    this.unsettledDebtsInPeriodAmount = 0,
    this.activeEmployeesCount = 0,
    this.terminatedEmployeesCount = 0,
    this.totalSalaryObligation = 0,
    this.groupBy = 'daily',
  });

  /// صفوف الإيرادات: {date(ms), roomNumber, guestName, paymentMethod,
  /// revenueType, amount}
  final List<Map<String, Object?>> incomeRows;

  /// صفوف المصروفات: {date(ms), type, description, amount, isSalary}
  final List<Map<String, Object?>> expenseRows;

  final DateTime fromDate;
  final DateTime toDate;
  final double incomeTotal;
  final double expenseTotal;
  final double salaryTotal;
  final double net;
  final int bookingsCount;
  final int activeBookingsCount;
  final int checkoutBookingsCount;
  final int totalDebtsCount;
  final int unsettledDebtsCount;
  final double unsettledDebtsAmount;
  final int unsettledDebtsInPeriodCount;
  final double unsettledDebtsInPeriodAmount;
  final int activeEmployeesCount;
  final int terminatedEmployeesCount;
  final double totalSalaryObligation;

  /// تجميع التقرير التفصيلي: daily | monthly | yearly
  final String groupBy;

  final Uint8List fontRegularBytes;
  final Uint8List fontBoldBytes;
}

/// ════════════════ نقاط الدخول (top-level لتوافق compute) ════════════════

/// بناء تقرير الدورة المالية الشامل وإرجاع بايتات PDF جاهزة للمشاركة.
Future<Uint8List> incomeExpensePdfMainJob(IncomeExpensePdfParams params) {
  return compute(_incomeExpensePdfMainSync, params);
}

/// بناء التقرير التفصيلي المجمّع حسب فترة وإرجاع بايتات PDF جاهزة.
Future<Uint8List> incomeExpensePdfGroupedJob(IncomeExpensePdfParams params) {
  return compute(_incomeExpensePdfGroupedSync, params);
}

Future<Uint8List> _incomeExpensePdfMainSync(IncomeExpensePdfParams p) async {
  final fonts = EnhancedPdfUtils.fontsFromBytes(
    p.fontRegularBytes,
    p.fontBoldBytes,
  );
  final income = p.incomeRows.map(_pdfIncomeFromMap).toList();
  final expenses = p.expenseRows.map(_pdfExpenseFromMap).toList();
  final doc = _buildMainDocument(p, fonts, income, expenses);
  return await doc.save();
}

Future<Uint8List> _incomeExpensePdfGroupedSync(IncomeExpensePdfParams p) async {
  final fonts = EnhancedPdfUtils.fontsFromBytes(
    p.fontRegularBytes,
    p.fontBoldBytes,
  );
  final income = p.incomeRows.map(_pdfIncomeFromMap).toList();
  final expenses = p.expenseRows.map(_pdfExpenseFromMap).toList();
  final doc = _buildGroupedDocument(p, fonts, income, expenses);
  return await doc.save();
}

/// ════════════════ نماذج محلية ════════════════

class _PdfIncomeEntry {
  _PdfIncomeEntry({
    required this.date,
    required this.amount,
    this.roomNumber = '',
    this.guestName = '',
    this.paymentMethod = '',
    this.revenueType = '',
  });
  final DateTime date;
  final double amount;
  final String roomNumber;
  final String guestName;
  final String paymentMethod;
  final String revenueType;
}

class _PdfExpenseEntry {
  _PdfExpenseEntry({
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

class _PdfGroup {
  _PdfGroup({
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
  final int index;
  final String key;
  final String label;
  final List<_PdfIncomeEntry> incomeEntries;
  final List<_PdfExpenseEntry> expenseEntries;
  final double incomeTotal;
  final double expenseTotal;
  final double salaryTotal;
  final double net;
  final int incomeCount;
  final int expenseCount;
}

_PdfIncomeEntry _pdfIncomeFromMap(Map<String, Object?> m) {
  return _PdfIncomeEntry(
    date: DateTime.fromMillisecondsSinceEpoch(m['date']! as int),
    roomNumber: (m['roomNumber'] ?? '') as String,
    guestName: (m['guestName'] ?? '') as String,
    paymentMethod: (m['paymentMethod'] ?? '') as String,
    revenueType: (m['revenueType'] ?? '') as String,
    amount: (m['amount'] as num).toDouble(),
  );
}

_PdfExpenseEntry _pdfExpenseFromMap(Map<String, Object?> m) {
  return _PdfExpenseEntry(
    date: DateTime.fromMillisecondsSinceEpoch(m['date']! as int),
    type: (m['type'] ?? '') as String,
    description: (m['description'] ?? '') as String,
    amount: (m['amount'] as num).toDouble(),
    isSalary: (m['isSalary'] ?? false) as bool,
  );
}

/// ════════════════ مساعدات مشتركة ════════════════

String _pdfPaymentMethodName(String method) {
  switch (method) {
    case 'cash':
      return 'نقداً';
    case 'card':
      return 'بطاقة';
    case 'transfer':
      return 'تحويل';
    case 'check':
      return 'شيك';
    default:
      return method.isNotEmpty ? method : '-';
  }
}

String _pdfRevenueTypeName(String type) {
  switch (type) {
    case 'room':
      return 'إقامة';
    case 'restaurant':
      return 'مطعم';
    case 'services':
      return 'خدمات';
    case 'other':
      return 'أخرى';
    default:
      return type.isNotEmpty ? type : 'إقامة';
  }
}

const List<String> _pdfArabicDays = [
  'الاثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
];

const List<String> _pdfArabicMonths = [
  '',
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

String _pdfArabicDayName(DateTime date) => _pdfArabicDays[date.weekday - 1];

String _pdfGroupKey(DateTime date, String groupBy) {
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

String _pdfGroupLabel(String key, String groupBy) {
  switch (groupBy) {
    case 'daily':
      final dt = DateTime.parse(key);
      return '${dt.day} ${_pdfArabicMonths[dt.month]} ${dt.year} '
          '(${_pdfArabicDayName(dt)})';
    case 'monthly':
      final parts = key.split('-');
      return '${_pdfArabicMonths[int.parse(parts[1])]} ${parts[0]}';
    case 'yearly':
      return '$key م';
    default:
      return '';
  }
}

String _pdfGroupTypeLabel(String groupBy) {
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

List<_PdfGroup> _pdfGroupedData(
  String groupBy,
  List<_PdfIncomeEntry> income,
  List<_PdfExpenseEntry> expenses,
) {
  final incomeMap = <String, List<_PdfIncomeEntry>>{};
  final expenseMap = <String, List<_PdfExpenseEntry>>{};

  for (final e in income) {
    incomeMap.putIfAbsent(_pdfGroupKey(e.date, groupBy), () => []).add(e);
  }
  for (final e in expenses) {
    expenseMap.putIfAbsent(_pdfGroupKey(e.date, groupBy), () => []).add(e);
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
    final salTotal = exp
        .where((e) => e.isSalary)
        .fold<double>(0, (s, e) => s + e.amount);
    return _PdfGroup(
      index: idx + 1,
      key: key,
      label: _pdfGroupLabel(key, groupBy),
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

/// جدول مصغّر موحّد — يُعاد كقائمة عناصر مباشرة تحت MultiPage.
///
/// ⚠️ قاعدة حرجة من كود حزمة pdf 3.12: أي عمود Column يتجاوز محتواه
/// صفحة واحدة داخل تسلسل امتداد متداخل يدخل حلقة تخطيط لا نهائية
/// (تم إثباته بالتجربة: تجميد > 2 دقيقة). لذلك يجب أن يكون كل جدول
/// وكل عنوان طفلاً مباشراً لـ MultiPage — لا داخل أعمدة متداخلة.
List<pw.Widget> _pdfMiniTableWidgets(
  ArabicPdfFonts fonts,
  String title,
  List<String> headers,
  List<List<String>> rows,
  PdfColor headerColor, {
  int boldColumnIndex = -1,
}) {
  if (rows.isEmpty) {
    return const [];
  }
  return [
    pw.Text(
      title,
      style: pw.TextStyle(font: fonts.bold, fontSize: 10, color: headerColor),
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
            children: headers
                .map((h) => _pdfMiniCell(h, fonts.bold, PdfColors.textDark))
                .toList(),
          ),
          ...rows.asMap().entries.map((entry) {
            final isEven = entry.key.isEven;
            return pw.TableRow(
              decoration: isEven
                  ? const pw.BoxDecoration(color: PdfColors.backgroundLight)
                  : null,
              children: entry.value.asMap().entries.map((cell) {
                final isBold = cell.key == boldColumnIndex;
                return _pdfMiniCell(
                  cell.value,
                  isBold ? fonts.bold : fonts.regular,
                  PdfColors.textDark,
                  align: isBold ? pw.TextAlign.left : pw.TextAlign.center,
                );
              }).toList(),
            );
          }),
        ],
      ),
    ),
  ];
}

pw.Widget _pdfMiniCell(
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

/// تقسيم جدول التفاصيل الكبير إلى كتل صغيرة مع تكرار صف العناوين.
///
/// الجدول الواحد الذي يمتد لأكثر من 20 صفحة متتالية يرمي
/// TooManyPagesException (حد MultiPage.maxPages الافتراضي = 20)
/// وهو سبب فعلي لانهيار التصدير مع الأشهر كثيفة المعاملات.
/// التقسيم كل ~250 صف يبقي كل جدول ضمن بضع صفحات ويحدّ ذاكرة التخطيط.
List<pw.Widget> _pdfChunkedDetailTable({
  required List<String> headers,
  required List<List<String>> rows,
  required ArabicPdfFonts fonts,
  required PdfColor headerColor,
  required PdfColor alternateRowColor,
  int chunkSize = 250,
}) {
  final widgets = <pw.Widget>[];
  for (var start = 0; start < rows.length; start += chunkSize) {
    final end = (start + chunkSize < rows.length)
        ? start + chunkSize
        : rows.length;
    widgets.add(
      EnhancedPdfUtils.buildProfessionalTable(
        headers: headers,
        fonts: fonts,
        headerColor: headerColor,
        alternateRowColor: alternateRowColor,
        data: rows.sublist(start, end),
      ),
    );
    if (end < rows.length) {
      widgets.add(pw.SizedBox(height: 10));
    }
  }
  return widgets;
}

/// ════════════════ التقرير الشامل (الدورة المالية الكاملة) ════════════════

pw.Document _buildMainDocument(
  IncomeExpensePdfParams p,
  ArabicPdfFonts fonts,
  List<_PdfIncomeEntry> income,
  List<_PdfExpenseEntry> expenses,
) {
  final doc = pw.Document();
  final fromLabel = DateFormat('yyyy-MM-dd').format(p.fromDate);
  final toLabel = DateFormat('yyyy-MM-dd').format(p.toDate);
  final nonSalaryExpenses = p.expenseTotal - p.salaryTotal;
  final dateFormat = DateFormat('yyyy-MM-dd');

  // ===== حسابات تحليل أنواع الإيرادات =====
  final roomRevenue = income
      .where((e) => e.revenueType == 'room' || e.revenueType.isEmpty)
      .fold<double>(0, (s, e) => s + e.amount);
  final otherRevenue = p.incomeTotal - roomRevenue;

  // ===== حسابات تحليل أنواع المصروفات =====
  final expenseByType = <String, double>{};
  for (final e in expenses) {
    final key = e.isSalary ? 'رواتب' : e.type;
    expenseByType[key] = (expenseByType[key] ?? 0) + e.amount;
  }
  final sortedExpenseTypes = expenseByType.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  // ===== مؤشرات مالية =====
  final profitMargin = p.incomeTotal > 0 ? (p.net / p.incomeTotal * 100) : 0.0;
  final expenseRatio = p.incomeTotal > 0
      ? (p.expenseTotal / p.incomeTotal * 100)
      : 0.0;
  final salaryExpenseRatio = p.incomeTotal > 0
      ? (p.salaryTotal / p.incomeTotal * 100)
      : 0.0;
  final debtCoverage = p.unsettledDebtsAmount > 0 && p.net > 0
      ? p.net / p.unsettledDebtsAmount
      : 0.0;

  /// صندوق ملخص
  pw.Widget buildSummaryBox(String title, String value, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
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
            style: pw.TextStyle(font: fonts.bold, fontSize: 15, color: color),
          ),
        ],
      ),
    );
  }

  /// عنوان قسم
  pw.Widget buildSectionTitle(String title, PdfColor color) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      margin: const pw.EdgeInsets.only(top: 16, bottom: 8),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          font: fonts.bold,
          fontSize: 13,
          color: PdfColors.textWhite,
        ),
      ),
    );
  }

  doc.addPage(
    pw.MultiPage(
      maxPages: 100000,
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
      footer: (context) => pw.Align(
        child: pw.Text(
          'صفحة ${context.pageNumber} من ${context.pagesCount}',
          style: pw.TextStyle(font: fonts.regular, fontSize: 10),
        ),
      ),
      build: (context) {
        final widgets = <pw.Widget>[];

        // ═════════ القسم 1: رأس التقرير ═════════
        widgets.add(
          pw.Container(
            width: double.infinity,
            decoration: const pw.BoxDecoration(color: PdfColors.primary),
            padding: const pw.EdgeInsets.all(20),
            child: pw.Column(
              children: [
                pw.Text(
                  'تقرير الدورة المالية الشامل',
                  style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: 22,
                    color: PdfColors.textWhite,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'فندق مارينا بلازا',
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 14,
                    color: PdfColors.secondary,
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
                  'تاريخ الإنشاء: '
                  '${EnhancedPdfUtils.formatDateTime(DateTime.now())}',
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 10,
                    color: PdfColors.textWhite,
                  ),
                ),
              ],
            ),
          ),
        );

        // ═════════ القسم 2: الملخص التنفيذي ═════════
        widgets.add(pw.SizedBox(height: 16));
        widgets.add(buildSectionTitle('الملخص التنفيذي', PdfColors.primary));

        widgets.add(
          pw.Row(
            children: [
              pw.Expanded(
                child: buildSummaryBox(
                  'إجمالي الإيرادات',
                  EnhancedPdfUtils.formatNumber(p.incomeTotal),
                  PdfColors.success,
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Expanded(
                child: buildSummaryBox(
                  'إجمالي المصروفات',
                  EnhancedPdfUtils.formatNumber(p.expenseTotal),
                  PdfColors.danger,
                ),
              ),
            ],
          ),
        );
        widgets.add(pw.SizedBox(height: 6));
        widgets.add(
          pw.Row(
            children: [
              pw.Expanded(
                child: buildSummaryBox(
                  'مصروفات الرواتب',
                  EnhancedPdfUtils.formatNumber(p.salaryTotal),
                  PdfColors.warning,
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Expanded(
                child: buildSummaryBox(
                  'مصروفات تشغيلية',
                  EnhancedPdfUtils.formatNumber(nonSalaryExpenses),
                  PdfColors.info,
                ),
              ),
            ],
          ),
        );
        widgets.add(pw.SizedBox(height: 6));
        widgets.add(
          pw.Row(
            children: [
              pw.Expanded(
                child: buildSummaryBox(
                  'صافي الربح / الخسارة',
                  EnhancedPdfUtils.formatNumber(p.net),
                  p.net >= 0 ? PdfColors.success : PdfColors.danger,
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Expanded(
                child: buildSummaryBox(
                  'هامش الربح',
                  '${profitMargin.toStringAsFixed(1)}%',
                  profitMargin > 0 ? PdfColors.success : PdfColors.danger,
                ),
              ),
            ],
          ),
        );

        // ═════════ القسم 3: تفاصيل الإيرادات ═════════
        widgets.add(buildSectionTitle('تفاصيل الإيرادات', PdfColors.success));

        if (income.isNotEmpty) {
          widgets.addAll(
            _pdfChunkedDetailTable(
              headers: [
                '#',
                'التاريخ',
                'الغرفة',
                'النزيل',
                'طريقة الدفع',
                'نوع الإيراد',
                'المبلغ',
              ],
              fonts: fonts,
              headerColor: PdfColors.success,
              alternateRowColor: PdfColors.backgroundLight,
              rows: income.asMap().entries.map((entry) {
                final e = entry.value;
                final i = entry.key + 1;
                return [
                  '$i',
                  dateFormat.format(e.date),
                  if (e.roomNumber.isNotEmpty) e.roomNumber else '-',
                  if (e.guestName.isNotEmpty) e.guestName else '-',
                  _pdfPaymentMethodName(e.paymentMethod),
                  _pdfRevenueTypeName(e.revenueType),
                  EnhancedPdfUtils.formatNumber(e.amount),
                ];
              }).toList(),
            ),
          );
        }

        // ═════════ القسم 4: تحليل طرق الدفع ═════════
        widgets.add(buildSectionTitle('تحليل طرق الدفع', PdfColors.secondary));
        widgets.add(_pdfPaymentMethodsTable(fonts, income, p.incomeTotal));

        // ═════════ القسم 5: تفاصيل المصروفات ═════════
        widgets.add(buildSectionTitle('تفاصيل المصروفات', PdfColors.danger));

        if (expenses.isNotEmpty) {
          widgets.addAll(
            _pdfChunkedDetailTable(
              headers: ['#', 'التاريخ', 'النوع', 'الوصف', 'المبلغ'],
              fonts: fonts,
              headerColor: PdfColors.danger,
              alternateRowColor: PdfColors.backgroundLight,
              rows: expenses.asMap().entries.map((entry) {
                final e = entry.value;
                final i = entry.key + 1;
                return [
                  '$i',
                  dateFormat.format(e.date),
                  if (e.isSalary) 'رواتب' else e.type,
                  if (e.description.isNotEmpty) e.description else '-',
                  EnhancedPdfUtils.formatNumber(e.amount),
                ];
              }).toList(),
            ),
          );
        }

        // ═════════ القسم 6: تحليل المصروفات حسب الفئة ═════════
        if (sortedExpenseTypes.isNotEmpty) {
          widgets.add(
            buildSectionTitle('تحليل المصروفات حسب الفئة', PdfColors.accent),
          );
          widgets.add(
            EnhancedPdfUtils.buildProfessionalTable(
              headers: [
                'الفئة',
                'المبلغ',
                'النسبة من الإيرادات',
                'النسبة من المصروفات',
              ],
              fonts: fonts,
              headerColor: PdfColors.accent,
              alternateRowColor: PdfColors.backgroundLight,
              data: sortedExpenseTypes.map((entry) {
                return [
                  entry.key,
                  EnhancedPdfUtils.formatNumber(entry.value),
                  if (p.incomeTotal > 0)
                    '${(entry.value / p.incomeTotal * 100).toStringAsFixed(1)}%'
                  else
                    '0%',
                  if (p.expenseTotal > 0)
                    '${(entry.value / p.expenseTotal * 100).toStringAsFixed(1)}%'
                  else
                    '0%',
                ];
              }).toList(),
            ),
          );
        }

        // ═════════ القسم 7: تكاليف الموارد البشرية ═════════
        widgets.add(
          buildSectionTitle('تكاليف الموارد البشرية', PdfColors.warning),
        );
        widgets.add(
          EnhancedPdfUtils.buildProfessionalTable(
            headers: ['البيان', 'القيمة'],
            fonts: fonts,
            headerColor: PdfColors.warning,
            alternateRowColor: PdfColors.backgroundLight,
            columnWidths: [200, 130],
            data: [
              ['عدد الموظفين النشطين', '${p.activeEmployeesCount} موظف'],
              [
                'عدد الموظفين المنهية خدمتهم',
                '${p.terminatedEmployeesCount} موظف',
              ],
              [
                'إجمالي الالتزامات الرواتب الشهرية',
                EnhancedPdfUtils.formatNumber(p.totalSalaryObligation),
              ],
              [
                'الرواتب المدفوعة في الفترة',
                EnhancedPdfUtils.formatNumber(p.salaryTotal),
              ],
              [
                'نسبة الرواتب من الإيرادات',
                '${salaryExpenseRatio.toStringAsFixed(1)}%',
              ],
              [
                'نسبة الرواتب من المصروفات',
                if (p.expenseTotal > 0)
                  '${(p.salaryTotal / p.expenseTotal * 100).toStringAsFixed(1)}%'
                else
                  '0%',
              ],
            ],
          ),
        );

        // ═════════ القسم 8: تحليل الديون ═════════
        widgets.add(
          buildSectionTitle('تحليل الديون المستحقة', PdfColors.danger),
        );
        widgets.add(_pdfDebtAnalysisTable(fonts, p, debtCoverage));

        // ═════════ القسم 9: إحصائيات الحجوزات والإشغال ═════════
        widgets.add(
          buildSectionTitle('إحصائيات الحجوزات والإشغال', PdfColors.info),
        );
        widgets.add(
          EnhancedPdfUtils.buildProfessionalTable(
            headers: ['البيان', 'القيمة'],
            fonts: fonts,
            headerColor: PdfColors.info,
            alternateRowColor: PdfColors.backgroundLight,
            columnWidths: [200, 130],
            data: [
              ['إجمالي الحجوزات في الفترة', '${p.bookingsCount} حجز'],
              ['حجوزات نشطة (داخلين)', '${p.activeBookingsCount} حجز'],
              ['حجوزات مغادرة', '${p.checkoutBookingsCount} حجز'],
              [
                'متوسط الإيراد لكل حجز',
                if (p.bookingsCount > 0)
                  EnhancedPdfUtils.formatNumber(p.incomeTotal / p.bookingsCount)
                else
                  '0',
              ],
            ],
          ),
        );

        // ═════════ القسم 10: المؤشرات المالية الرئيسية ═════════
        widgets.add(
          buildSectionTitle('المؤشرات المالية الرئيسية', PdfColors.primary),
        );
        widgets.add(
          _pdfFinancialIndicatorsTable(
            fonts,
            profitMargin,
            expenseRatio,
            salaryExpenseRatio,
            debtCoverage,
          ),
        );

        // ═════════ القسم 11: الملخص المحاسبي الشامل ═════════
        widgets.add(
          buildSectionTitle('الملخص المحاسبي الشامل', PdfColors.primary),
        );
        widgets.add(
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.backgroundCard,
              border: pw.Border.all(color: PdfColors.primary),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Column(
              children: [
                EnhancedPdfUtils.buildProfessionalTable(
                  headers: ['البيان', 'المبلغ'],
                  fonts: fonts,
                  headerColor: PdfColors.primary,
                  alternateRowColor: PdfColors.backgroundLight,
                  columnWidths: [200, 130],
                  data: [
                    [
                      'إيرادات الغرف',
                      EnhancedPdfUtils.formatNumber(roomRevenue),
                    ],
                    [
                      'إيرادات أخرى',
                      EnhancedPdfUtils.formatNumber(otherRevenue),
                    ],
                    [
                      'إجمالي الإيرادات',
                      EnhancedPdfUtils.formatNumber(p.incomeTotal),
                    ],
                    [
                      '(-) مصروفات تشغيلية',
                      EnhancedPdfUtils.formatNumber(nonSalaryExpenses),
                    ],
                    [
                      '(-) رواتب ومخصصات',
                      EnhancedPdfUtils.formatNumber(p.salaryTotal),
                    ],
                    [
                      'إجمالي المصروفات',
                      EnhancedPdfUtils.formatNumber(p.expenseTotal),
                    ],
                    [
                      'صافي الربح / الخسارة',
                      EnhancedPdfUtils.formatNumber(p.net),
                    ],
                    [
                      '(+) ديون مستحقة غير مسددة',
                      EnhancedPdfUtils.formatNumber(p.unsettledDebtsAmount),
                    ],
                    [
                      'الوضع المالي الصافي',
                      EnhancedPdfUtils.formatNumber(
                        p.net - p.unsettledDebtsAmount,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );

        // تذييل
        widgets.add(pw.SizedBox(height: 20));
        widgets.add(pw.Divider(color: PdfColors.textLight));
        widgets.add(pw.SizedBox(height: 8));
        widgets.add(
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'تم إنشاء هذا التقرير تلقائياً - فندق مارينا بلازا',
                style: pw.TextStyle(
                  font: fonts.regular,
                  fontSize: 9,
                  color: PdfColors.textLight,
                ),
              ),
              pw.Text(
                'تقرير الدورة المالية الشامل',
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 9,
                  color: PdfColors.primary,
                ),
              ),
            ],
          ),
        );

        return widgets;
      },
    ),
  );

  return doc;
}

/// جدول تحليل طرق الدفع (مشترك بين PDF العادي والمجمع)
pw.Widget _pdfPaymentMethodsTable(
  ArabicPdfFonts fonts,
  List<_PdfIncomeEntry> income,
  double incomeTotal,
) {
  final cashIncome = income
      .where((e) => e.paymentMethod == 'cash')
      .fold<double>(0, (s, e) => s + e.amount);
  final cardIncome = income
      .where((e) => e.paymentMethod == 'card')
      .fold<double>(0, (s, e) => s + e.amount);
  final transferIncome = income
      .where((e) => e.paymentMethod == 'transfer')
      .fold<double>(0, (s, e) => s + e.amount);
  final otherMethodIncome =
      incomeTotal - cashIncome - cardIncome - transferIncome;

  return EnhancedPdfUtils.buildProfessionalTable(
    headers: ['طريقة الدفع', 'المبلغ', 'العدد', 'النسبة'],
    fonts: fonts,
    headerColor: PdfColors.secondary,
    alternateRowColor: PdfColors.backgroundLight,
    data: [
      [
        'نقداً',
        EnhancedPdfUtils.formatNumber(cashIncome),
        '${income.where((e) => e.paymentMethod == 'cash').length}',
        if (incomeTotal > 0)
          '${(cashIncome / incomeTotal * 100).toStringAsFixed(1)}%'
        else
          '0%',
      ],
      [
        'بطاقة ائتمانية',
        EnhancedPdfUtils.formatNumber(cardIncome),
        '${income.where((e) => e.paymentMethod == 'card').length}',
        if (incomeTotal > 0)
          '${(cardIncome / incomeTotal * 100).toStringAsFixed(1)}%'
        else
          '0%',
      ],
      [
        'تحويل بنكي',
        EnhancedPdfUtils.formatNumber(transferIncome),
        '${income.where((e) => e.paymentMethod == 'transfer').length}',
        if (incomeTotal > 0)
          '${(transferIncome / incomeTotal * 100).toStringAsFixed(1)}%'
        else
          '0%',
      ],
      if (otherMethodIncome > 0)
        [
          'أخرى',
          EnhancedPdfUtils.formatNumber(otherMethodIncome),
          '${income.where((e) => e.paymentMethod != 'cash' && e.paymentMethod != 'card' && e.paymentMethod != 'transfer').length}',
          if (incomeTotal > 0)
            '${(otherMethodIncome / incomeTotal * 100).toStringAsFixed(1)}%'
          else
            '0%',
        ],
      [
        'الإجمالي',
        EnhancedPdfUtils.formatNumber(incomeTotal),
        '${income.length}',
        '100%',
      ],
    ],
  );
}

/// جدول تحليل الديون المستحقة (مشترك بين PDF العادي والمجمع)
pw.Widget _pdfDebtAnalysisTable(
  ArabicPdfFonts fonts,
  IncomeExpensePdfParams p,
  double debtCoverage,
) {
  return EnhancedPdfUtils.buildProfessionalTable(
    headers: ['البيان', 'القيمة'],
    fonts: fonts,
    headerColor: PdfColors.danger,
    alternateRowColor: PdfColors.backgroundLight,
    columnWidths: [200, 130],
    data: [
      ['إجمالي الديون في الفترة', '${p.totalDebtsCount} دين'],
      ['ديون غير مسددة في الفترة', '${p.unsettledDebtsInPeriodCount} دين'],
      [
        'مبلغ الديون غير المسددة في الفترة',
        EnhancedPdfUtils.formatNumber(p.unsettledDebtsInPeriodAmount),
      ],
      [
        'إجمالي الديون غير المسددة (كل الفترات)',
        '${p.unsettledDebtsCount} دين',
      ],
      [
        'مبلغ الديون غير المسددة الكلي',
        EnhancedPdfUtils.formatNumber(p.unsettledDebtsAmount),
      ],
      [
        'نسبة الديون غير المسددة الكلية من الإيرادات',
        if (p.incomeTotal > 0)
          '${(p.unsettledDebtsAmount / p.incomeTotal * 100).toStringAsFixed(1)}%'
        else
          '0%',
      ],
      [
        'قدرة تغطية الديون (صافي / ديون)',
        if (debtCoverage > 0)
          '${debtCoverage.toStringAsFixed(2)}x'
        else
          'غير كافٍ',
      ],
    ],
  );
}

/// جدول المؤشرات المالية الرئيسية (مشترك بين PDF العادي والمجمع)
pw.Widget _pdfFinancialIndicatorsTable(
  ArabicPdfFonts fonts,
  double profitMargin,
  double expenseRatio,
  double salaryExpenseRatio,
  double debtCoverage,
) {
  return EnhancedPdfUtils.buildProfessionalTable(
    headers: ['المؤشر', 'القيمة', 'التقييم'],
    fonts: fonts,
    headerColor: PdfColors.primary,
    alternateRowColor: PdfColors.backgroundLight,
    data: [
      [
        'هامش الربح الصافي',
        '${profitMargin.toStringAsFixed(1)}%',
        if (profitMargin > 20)
          'ممتاز'
        else if (profitMargin > 10)
          'جيد'
        else if (profitMargin > 0)
          'مقبول'
        else
          'خسارة',
      ],
      [
        'نسبة المصروفات إلى الإيرادات',
        '${expenseRatio.toStringAsFixed(1)}%',
        if (expenseRatio < 60)
          'ممتاز'
        else if (expenseRatio < 80)
          'جيد'
        else
          'مرتفع',
      ],
      [
        'نسبة الرواتب إلى الإيرادات',
        '${salaryExpenseRatio.toStringAsFixed(1)}%',
        if (salaryExpenseRatio < 30)
          'ممتاز'
        else if (salaryExpenseRatio < 50)
          'جيد'
        else
          'مرتفع',
      ],
      [
        'معدل تغطية الديون',
        if (debtCoverage > 0)
          '${debtCoverage.toStringAsFixed(2)}x'
        else
          'غير كافٍ',
        if (debtCoverage > 2)
          'ممتاز'
        else if (debtCoverage > 1)
          'جيد'
        else
          'ضعيف',
      ],
    ],
  );
}

/// ════════════════ التقرير التفصيلي المجمّع حسب الفترة ════════════════

pw.Document _buildGroupedDocument(
  IncomeExpensePdfParams p,
  ArabicPdfFonts fonts,
  List<_PdfIncomeEntry> income,
  List<_PdfExpenseEntry> expenses,
) {
  final doc = pw.Document();
  final groupedData = _pdfGroupedData(p.groupBy, income, expenses);
  final groupTypeLabel = _pdfGroupTypeLabel(p.groupBy);
  final fromLabel = DateFormat('yyyy-MM-dd').format(p.fromDate);
  final toLabel = DateFormat('yyyy-MM-dd').format(p.toDate);

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
            style: pw.TextStyle(font: fonts.bold, fontSize: 15, color: color),
          ),
        ],
      ),
    );
  }

  /// عناصر الفترة الواحدة — قائمة عناصر مباشرة تحت MultiPage.
  ///
  /// ⚠️ كان السابق بطاقة Card واحدة (عمود متداخل) تحتوي جداول الفترة؛
  /// عند تجاوز المحتوى صفحة واحدة تدخل حزمة pdf في حلقة تخطيط لا نهائية
  /// (ملف flex.dart لا يقسم أطفاءه، وMultiPage يعيد التخطيط للأبد).
  /// التسطيح: كل عنصر طفل مباشر — امتداد الصفحات يعمل بدقة.
  List<pw.Widget> buildPeriodWidgets(_PdfGroup group) {
    final isProfit = group.net >= 0;
    final borderColor = isProfit ? PdfColors.success : PdfColors.danger;

    final out = <pw.Widget>[];

    // عنوان الفترة المرقم
    out.add(
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: pw.BoxDecoration(
          color: PdfColors.primary,
          border: pw.Border.all(color: borderColor, width: 0.8),
          borderRadius: const pw.BorderRadius.only(
            topLeft: pw.Radius.circular(7),
            topRight: pw.Radius.circular(7),
          ),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              '${group.index}. ${group.label}',
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
                color: borderColor,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
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
    );

    // صناديق الملخص الأربعة
    pw.Widget summaryBox(String title, String value, PdfColor color) {
      return pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(
            color: color,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Column(
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  font: fonts.regular,
                  fontSize: 9,
                  color: PdfColors.textWhite,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                value,
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 12,
                  color: PdfColors.textWhite,
                ),
              ),
            ],
          ),
        ),
      );
    }

    out.add(
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: borderColor, width: 0.4),
        ),
        child: pw.Row(
          children: [
            summaryBox(
              'الدخل',
              EnhancedPdfUtils.formatNumber(group.incomeTotal),
              PdfColors.success,
            ),
            pw.SizedBox(width: 4),
            summaryBox(
              'المصروفات',
              EnhancedPdfUtils.formatNumber(group.expenseTotal),
              PdfColors.danger,
            ),
            pw.SizedBox(width: 4),
            summaryBox(
              'الرواتب',
              EnhancedPdfUtils.formatNumber(group.salaryTotal),
              group.salaryTotal > 0 ? PdfColors.warning : PdfColors.textLight,
            ),
            pw.SizedBox(width: 4),
            summaryBox(
              'الصافي',
              EnhancedPdfUtils.formatNumber(group.net),
              isProfit ? PdfColors.success : PdfColors.danger,
            ),
          ],
        ),
      ),
    );
    out.add(pw.SizedBox(height: 8));

    // جداول الفترة التفصيلية — أطفال مباشرون (امتداد آمن)
    out.addAll(
      _pdfMiniTableWidgets(
        fonts,
        'الدخل',
        const ['التاريخ', 'الغرفة', 'الدفع', 'النوع', 'المبلغ'],
        group.incomeEntries
            .map(
              (e) => [
                DateFormat('dd/MM').format(e.date),
                if (e.roomNumber.isNotEmpty) e.roomNumber else '-',
                _pdfPaymentMethodName(e.paymentMethod),
                _pdfRevenueTypeName(e.revenueType),
                EnhancedPdfUtils.formatNumber(e.amount),
              ],
            )
            .toList(),
        PdfColors.success,
        boldColumnIndex: 4,
      ),
    );
    out.add(pw.SizedBox(height: 4));
    out.addAll(
      _pdfMiniTableWidgets(
        fonts,
        'المصروفات',
        const ['التاريخ', 'الوصف', 'المبلغ'],
        group.expenseEntries
            .map(
              (e) => [
                DateFormat('dd/MM').format(e.date),
                if (e.description.isNotEmpty) e.description else e.type,
                EnhancedPdfUtils.formatNumber(e.amount),
              ],
            )
            .toList(),
        PdfColors.danger,
        boldColumnIndex: 2,
      ),
    );
    out.add(pw.SizedBox(height: 10));

    return out;
  }

  doc.addPage(
    pw.MultiPage(
      maxPages: 100000,
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
      footer: (context) => pw.Align(
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
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.secondary,
                  ),
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
                  EnhancedPdfUtils.formatNumber(p.incomeTotal),
                  PdfColors.success,
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Expanded(
                child: buildSummaryBox(
                  'إجمالي المصروفات',
                  EnhancedPdfUtils.formatNumber(p.expenseTotal),
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
                  EnhancedPdfUtils.formatNumber(p.salaryTotal),
                  PdfColors.warning,
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Expanded(
                child: buildSummaryBox(
                  'صافي الربح / الخسارة',
                  EnhancedPdfUtils.formatNumber(p.net),
                  p.net >= 0 ? PdfColors.success : PdfColors.danger,
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

        // عناصر الفترات — أطفال مباشرون (تسطيح آمن للامتداد)
        for (final group in groupedData) {
          widgets.addAll(buildPeriodWidgets(group));
        }

        // ملخص نهائي شامل
        widgets.add(pw.SizedBox(height: 16));
        widgets.add(_pdfFinalSummarySection(fonts, p, groupedData));

        // ═════════ أقسام الدورة المالية في التقرير المجمع ═════════

        // مؤشرات مالية
        final profitMargin = p.incomeTotal > 0
            ? (p.net / p.incomeTotal * 100)
            : 0.0;
        final expenseRatio = p.incomeTotal > 0
            ? (p.expenseTotal / p.incomeTotal * 100)
            : 0.0;
        final salaryExpenseRatio = p.incomeTotal > 0
            ? (p.salaryTotal / p.incomeTotal * 100)
            : 0.0;
        final debtCoverage = p.unsettledDebtsAmount > 0 && p.net > 0
            ? p.net / p.unsettledDebtsAmount
            : 0.0;

        // تحليل طرق الدفع
        widgets.add(
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            margin: const pw.EdgeInsets.only(top: 16, bottom: 8),
            decoration: const pw.BoxDecoration(
              color: PdfColors.secondary,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Text(
              'تحليل طرق الدفع',
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 13,
                color: PdfColors.textWhite,
              ),
            ),
          ),
        );
        widgets.add(_pdfPaymentMethodsTable(fonts, income, p.incomeTotal));

        // تكاليف الموارد البشرية
        widgets.add(
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            margin: const pw.EdgeInsets.only(top: 16, bottom: 8),
            decoration: const pw.BoxDecoration(
              color: PdfColors.warning,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Text(
              'تكاليف الموارد البشرية',
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 13,
                color: PdfColors.textWhite,
              ),
            ),
          ),
        );
        widgets.add(
          EnhancedPdfUtils.buildProfessionalTable(
            headers: ['البيان', 'القيمة'],
            fonts: fonts,
            headerColor: PdfColors.warning,
            alternateRowColor: PdfColors.backgroundLight,
            columnWidths: [200, 130],
            data: [
              ['عدد الموظفين النشطين', '${p.activeEmployeesCount} موظف'],
              [
                'عدد الموظفين المنهية خدمتهم',
                '${p.terminatedEmployeesCount} موظف',
              ],
              [
                'إجمالي الالتزامات الرواتب الشهرية',
                EnhancedPdfUtils.formatNumber(p.totalSalaryObligation),
              ],
              [
                'الرواتب المدفوعة في الفترة',
                EnhancedPdfUtils.formatNumber(p.salaryTotal),
              ],
              [
                'نسبة الرواتب من الإيرادات',
                '${salaryExpenseRatio.toStringAsFixed(1)}%',
              ],
              [
                'نسبة الرواتب من المصروفات',
                if (p.expenseTotal > 0)
                  '${(p.salaryTotal / p.expenseTotal * 100).toStringAsFixed(1)}%'
                else
                  '0%',
              ],
            ],
          ),
        );

        // تحليل الديون المستحقة
        widgets.add(
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            margin: const pw.EdgeInsets.only(top: 16, bottom: 8),
            decoration: const pw.BoxDecoration(
              color: PdfColors.danger,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Text(
              'تحليل الديون المستحقة',
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 13,
                color: PdfColors.textWhite,
              ),
            ),
          ),
        );
        widgets.add(_pdfDebtAnalysisTable(fonts, p, debtCoverage));

        // إحصائيات الحجوزات والإشغال
        widgets.add(
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            margin: const pw.EdgeInsets.only(top: 16, bottom: 8),
            decoration: const pw.BoxDecoration(
              color: PdfColors.info,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Text(
              'إحصائيات الحجوزات والإشغال',
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 13,
                color: PdfColors.textWhite,
              ),
            ),
          ),
        );
        widgets.add(
          EnhancedPdfUtils.buildProfessionalTable(
            headers: ['البيان', 'القيمة'],
            fonts: fonts,
            headerColor: PdfColors.info,
            alternateRowColor: PdfColors.backgroundLight,
            columnWidths: [200, 130],
            data: [
              ['إجمالي الحجوزات في الفترة', '${p.bookingsCount} حجز'],
              ['حجوزات نشطة (داخلين)', '${p.activeBookingsCount} حجز'],
              ['حجوزات مغادرة', '${p.checkoutBookingsCount} حجز'],
              [
                'متوسط الإيراد لكل حجز',
                if (p.bookingsCount > 0)
                  EnhancedPdfUtils.formatNumber(p.incomeTotal / p.bookingsCount)
                else
                  '0',
              ],
            ],
          ),
        );

        // المؤشرات المالية الرئيسية
        widgets.add(
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            margin: const pw.EdgeInsets.only(top: 16, bottom: 8),
            decoration: const pw.BoxDecoration(
              color: PdfColors.primary,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Text(
              'المؤشرات المالية الرئيسية',
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 13,
                color: PdfColors.textWhite,
              ),
            ),
          ),
        );
        widgets.add(
          _pdfFinancialIndicatorsTable(
            fonts,
            profitMargin,
            expenseRatio,
            salaryExpenseRatio,
            debtCoverage,
          ),
        );

        return widgets;
      },
    ),
  );

  return doc;
}

/// ملخص نهائي شامل في آخر التقرير
pw.Widget _pdfFinalSummarySection(
  ArabicPdfFonts fonts,
  IncomeExpensePdfParams p,
  List<_PdfGroup> groups,
) {
  // أطول فترة ربحية وخاسرة
  _PdfGroup? bestPeriod;
  _PdfGroup? worstPeriod;
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
  final totalTx = p.incomeRows.length + p.expenseRows.length;
  final avgDaily = groups.isEmpty ? 0.0 : p.net / groups.length;

  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      color: PdfColors.backgroundCard,
      border: pw.Border.all(color: PdfColors.primary),
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
            ['متوسط الصافي لكل فترة', EnhancedPdfUtils.formatNumber(avgDaily)],
            ['إجمالي الدخل', EnhancedPdfUtils.formatNumber(p.incomeTotal)],
            ['إجمالي المصروفات', EnhancedPdfUtils.formatNumber(p.expenseTotal)],
            ['مصروفات الرواتب', EnhancedPdfUtils.formatNumber(p.salaryTotal)],
            ['الصافي النهائي', EnhancedPdfUtils.formatNumber(p.net)],
            if (bestPeriod != null)
              [
                'أفضل فترة (أعلى ربح)',
                '${bestPeriod.label} - ${EnhancedPdfUtils.formatNumber(bestPeriod.net)}',
              ],
            if (worstPeriod != null && worstPeriod.net < 0)
              [
                'أسوأ فترة (أعلى خسارة)',
                '${worstPeriod.label} - ${EnhancedPdfUtils.formatNumber(worstPeriod.net)}',
              ],
          ],
        ),
      ],
    ),
  );
}
