/// قالب PDF لتقرير الدخل والمصروفات (الدورة المالية) — نظام قوالب مستقل.
///
/// **عقد التقرير (نقدي خالص):**
/// - الدخل = المدفوعات المستلمة فعلاً (جدول payments فقط).
/// - المصروفات = النقد الخارج فعلاً (مصروفات نقدية + سحوبات رواتب).
/// - لا يشمل الديون المستحقة ولا أي تحليل لها — الديون ليست مدفوعات
///   (لم يخرج منها نقد ولم يدخل منها نقد) ولها تقرير مستقل خاص بها
///   (شاشة تقرير الديون). تعديل أي حد أو خط أو حجم بطاقة يتم من
///   نظام التصميم الموحّد في lib/src/pdf/enhanced_pdf_utils.dart.
library;

import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfColor;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../enhanced_pdf_utils.dart';
import '../report_pdf_builder.dart';

// ═══════════════════════════════════════════════════════════════
// نماذج البيانات — الشاشة تُمرّر بيانات فقط، القالب يتولى التصميم
// ═══════════════════════════════════════════════════════════════

/// قيد دخل (دفعة مستلمة).
class IncomeExpenseIncomeEntry {
  IncomeExpenseIncomeEntry({
    required this.date,
    required this.description,
    required this.amount,
    this.roomNumber = '',
    this.guestName = '',
    this.paymentMethod = '',
    this.revenueType = '',
  });

  final DateTime date;
  final String description;
  final double amount;
  final String roomNumber;
  final String guestName;
  final String paymentMethod;
  final String revenueType;
}

/// قيد مصروف (نقد خارج فعلاً).
class IncomeExpenseExpenseEntry {
  IncomeExpenseExpenseEntry({
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

/// نمط تجميع الفترات في التقرير التفصيلي.
enum IncomeExpenseGroupMode { daily, monthly, yearly }

extension IncomeExpenseGroupModeLabel on IncomeExpenseGroupMode {
  String get label => switch (this) {
    IncomeExpenseGroupMode.daily => 'يومي',
    IncomeExpenseGroupMode.monthly => 'شهري',
    IncomeExpenseGroupMode.yearly => 'سنوي',
  };
}

/// فترة مجمّعة (يوم/شهر/سنة) داخل التقرير التفصيلي.
class IncomeExpensePeriodGroup {
  IncomeExpensePeriodGroup({
    required this.index,
    required this.label,
    required this.incomeEntries,
    required this.expenseEntries,
    required this.incomeTotal,
    required this.expenseTotal,
    required this.salaryTotal,
  });

  final int index;
  final String label;
  final List<IncomeExpenseIncomeEntry> incomeEntries;
  final List<IncomeExpenseExpenseEntry> expenseEntries;
  final double incomeTotal;
  final double expenseTotal;
  final double salaryTotal;

  double get net => incomeTotal - expenseTotal;
  int get incomeCount => incomeEntries.length;
  int get expenseCount => expenseEntries.length;
}

/// بيانات تقرير الدخل والمصروفات — كل ما يحتاجه القالب بلا أي منطق قاعدة بيانات.
class IncomeExpenseReportData {
  IncomeExpenseReportData({
    required this.incomeEntries,
    required this.expenseEntries,
    this.fromDate,
    this.toDate,
    this.activeEmployeesCount = 0,
    this.terminatedEmployeesCount = 0,
    this.totalSalaryObligation = 0,
    this.bookingsCount = 0,
    this.activeBookingsCount = 0,
    this.checkoutBookingsCount = 0,
  });

  final DateTime? fromDate;
  final DateTime? toDate;
  final List<IncomeExpenseIncomeEntry> incomeEntries;
  final List<IncomeExpenseExpenseEntry> expenseEntries;

  final int activeEmployeesCount;
  final int terminatedEmployeesCount;
  final double totalSalaryObligation;

  final int bookingsCount;
  final int activeBookingsCount;
  final int checkoutBookingsCount;

  double get incomeTotal =>
      incomeEntries.fold<double>(0, (s, e) => s + e.amount);
  double get expenseTotal =>
      expenseEntries.fold<double>(0, (s, e) => s + e.amount);
  double get salaryTotal => expenseEntries
      .where((e) => e.isSalary)
      .fold<double>(0, (s, e) => s + e.amount);
  double get nonSalaryTotal => expenseTotal - salaryTotal;
  double get net => incomeTotal - expenseTotal;
  double get profitMargin => incomeTotal > 0 ? (net / incomeTotal * 100) : 0.0;
  double get expenseRatio =>
      incomeTotal > 0 ? (expenseTotal / incomeTotal * 100) : 0.0;
  double get salaryRatio =>
      incomeTotal > 0 ? (salaryTotal / incomeTotal * 100) : 0.0;
}

// ═══════════════════════════════════════════════════════════════
// القالب
// ═══════════════════════════════════════════════════════════════

class IncomeExpenseReportPdf {
  IncomeExpenseReportPdf._();

  /// مشاركة التقرير العام (الدورة المالية الشاملة).
  static Future<void> share(IncomeExpenseReportData data) async {
    await ReportPdfBuilder.buildAndShare(
      ReportPdfConfig(
        title: 'تقرير الدورة المالية الشامل',
        fromDate: data.fromDate,
        toDate: data.toDate,
        fileName: _fileName(),
        buildContent: (fonts) => _buildContent(fonts, data),
      ),
    );
  }

  /// طباعة التقرير العام مباشرة.
  static Future<void> print(IncomeExpenseReportData data) async {
    final doc = await ReportPdfBuilder.buildDocument(
      ReportPdfConfig(
        title: 'تقرير الدورة المالية الشامل',
        fromDate: data.fromDate,
        toDate: data.toDate,
        fileName: _fileName(),
        buildContent: (fonts) => _buildContent(fonts, data),
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }

  /// حفظ التقرير العام كملف داخل مجلد مستندات التطبيق، ويعيد مسار الملف.
  static Future<String> save(IncomeExpenseReportData data) async {
    final doc = await ReportPdfBuilder.buildDocument(
      ReportPdfConfig(
        title: 'تقرير الدورة المالية الشامل',
        fromDate: data.fromDate,
        toDate: data.toDate,
        fileName: _fileName(),
        buildContent: (fonts) => _buildContent(fonts, data),
      ),
    );
    final fileName = _fileName();
    final bytes = await doc.save();
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// مشاركة التقرير التفصيلي المجمّع حسب الفترة (يومي/شهري/سنوي).
  static Future<void> shareGrouped(
    IncomeExpenseReportData data, {
    required IncomeExpenseGroupMode mode,
  }) async {
    await ReportPdfBuilder.buildAndShare(
      ReportPdfConfig(
        title: 'تقرير الدخل والمصروفات التفصيلي',
        fromDate: data.fromDate,
        toDate: data.toDate,
        fileName: _fileName(suffix: mode.label),
        buildContent: (fonts) => _buildGroupedContent(fonts, data, mode),
      ),
    );
  }

  /// بناء التجميعات الزمنية (يومي/شهري/سنوي).
  static List<IncomeExpensePeriodGroup> buildGroups(
    IncomeExpenseReportData data,
    IncomeExpenseGroupMode mode,
  ) {
    final incomeMap = <String, List<IncomeExpenseIncomeEntry>>{};
    final expenseMap = <String, List<IncomeExpenseExpenseEntry>>{};

    for (final e in data.incomeEntries) {
      incomeMap.putIfAbsent(_groupKey(e.date, mode), () => []).add(e);
    }
    for (final e in data.expenseEntries) {
      expenseMap.putIfAbsent(_groupKey(e.date, mode), () => []).add(e);
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
      return IncomeExpensePeriodGroup(
        index: idx + 1,
        label: _groupLabel(key, mode),
        incomeEntries: inc,
        expenseEntries: exp,
        incomeTotal: incTotal,
        expenseTotal: expTotal,
        salaryTotal: salTotal,
      );
    }).toList();
  }

  // ─────────────── أسماء الملفات ───────────────

  static String _fileName({String suffix = ''}) {
    final s = suffix.isNotEmpty ? '-$suffix' : '';
    return 'تقرير-الدورة-المالية-الشامل$s-'
        '${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';
  }

  // ─────────────── المحتوى العام ───────────────

  static List<pw.Widget> _buildContent(
    ArabicPdfFonts fonts,
    IncomeExpenseReportData data,
  ) {
    final widgets = <pw.Widget>[];

    // 1) الملخص التنفيذي
    widgets.add(_sectionTitle(fonts, 'الملخص التنفيذي'));
    widgets.add(pw.SizedBox(height: 6));
    widgets.add(
      EnhancedPdfUtils.buildStatisticsGrid(
        items: [
          EnhancedPdfUtils.buildStatisticsBox(
            title: 'إجمالي الإيرادات',
            value: EnhancedPdfUtils.formatNumber(data.incomeTotal),
            fonts: fonts,
            color: PdfColors.success,
          ),
          EnhancedPdfUtils.buildStatisticsBox(
            title: 'إجمالي المصروفات',
            value: EnhancedPdfUtils.formatNumber(data.expenseTotal),
            fonts: fonts,
            color: PdfColors.danger,
          ),
          EnhancedPdfUtils.buildStatisticsBox(
            title: 'مصروفات الرواتب',
            value: EnhancedPdfUtils.formatNumber(data.salaryTotal),
            fonts: fonts,
            color: PdfColors.warning,
          ),
          EnhancedPdfUtils.buildStatisticsBox(
            title: 'مصروفات تشغيلية',
            value: EnhancedPdfUtils.formatNumber(data.nonSalaryTotal),
            fonts: fonts,
            color: PdfColors.info,
          ),
          EnhancedPdfUtils.buildStatisticsBox(
            title: 'صافي الربح / الخسارة',
            value: EnhancedPdfUtils.formatNumber(data.net),
            fonts: fonts,
            color: data.net >= 0 ? PdfColors.success : PdfColors.danger,
          ),
          EnhancedPdfUtils.buildStatisticsBox(
            title: 'هامش الربح',
            value: '${data.profitMargin.toStringAsFixed(1)}%',
            fonts: fonts,
            color: data.profitMargin > 0 ? PdfColors.success : PdfColors.danger,
          ),
        ],
      ),
    );

    // 2) تفاصيل الإيرادات
    widgets.add(_sectionTitle(fonts, 'تفاصيل الإيرادات'));
    widgets.add(pw.SizedBox(height: 6));
    if (data.incomeEntries.isEmpty) {
      widgets.add(_emptyNote(fonts, 'لا توجد إيرادات في الفترة'));
    } else {
      widgets.addAll(
        EnhancedPdfUtils.buildChunkedTable(
          headers: const [
            '#',
            'التاريخ',
            'الغرفة',
            'النزيل',
            'طريقة الدفع',
            'نوع الإيراد',
            'المبلغ',
          ],
          fonts: fonts,
          columnFlex: const [0.55, 1.15, 0.8, 1.5, 1.0, 1.0, 1.05],
          alignments: const [
            pw.TextAlign.center,
            pw.TextAlign.center,
            pw.TextAlign.center,
            pw.TextAlign.right,
            pw.TextAlign.center,
            pw.TextAlign.center,
            pw.TextAlign.center,
          ],
          data: _incomeRows(data.incomeEntries),
        ),
      );
    }

    // 3) تحليل طرق الدفع
    widgets.add(_sectionTitle(fonts, 'تحليل طرق الدفع'));
    widgets.add(pw.SizedBox(height: 6));
    widgets.add(_buildPaymentMethodsTable(fonts, data));

    // 4) تفاصيل المصروفات
    widgets.add(_sectionTitle(fonts, 'تفاصيل المصروفات'));
    widgets.add(pw.SizedBox(height: 6));
    if (data.expenseEntries.isEmpty) {
      widgets.add(_emptyNote(fonts, 'لا توجد مصروفات في الفترة'));
    } else {
      widgets.addAll(
        EnhancedPdfUtils.buildChunkedTable(
          headers: const ['#', 'التاريخ', 'النوع', 'الوصف', 'المبلغ'],
          fonts: fonts,
          columnFlex: const [0.55, 1.15, 1.35, 2.35, 1.05],
          alignments: const [
            pw.TextAlign.center,
            pw.TextAlign.center,
            pw.TextAlign.right,
            pw.TextAlign.right,
            pw.TextAlign.center,
          ],
          data: _expenseRows(data.expenseEntries),
        ),
      );
    }

    // 5) تحليل المصروفات حسب الفئة
    final expenseByType = _expenseByType(data);
    if (expenseByType.isNotEmpty) {
      widgets.add(_sectionTitle(fonts, 'تحليل المصروفات حسب الفئة'));
      widgets.add(pw.SizedBox(height: 6));
      widgets.add(
        EnhancedPdfUtils.buildProfessionalTable(
          headers: const [
            'الفئة',
            'المبلغ',
            'النسبة من الإيرادات',
            'النسبة من المصروفات',
          ],
          fonts: fonts,
          columnFlex: const [1.7, 1.0, 1.15, 1.15],
          alignments: const [
            pw.TextAlign.right,
            pw.TextAlign.center,
            pw.TextAlign.center,
            pw.TextAlign.center,
          ],
          data: expenseByType.entries
              .map(
                (entry) => [
                  entry.key,
                  EnhancedPdfUtils.formatNumber(entry.value),
                  if (data.incomeTotal > 0)
                    '${(entry.value / data.incomeTotal * 100).toStringAsFixed(1)}%'
                  else
                    '0%',
                  if (data.expenseTotal > 0)
                    '${(entry.value / data.expenseTotal * 100).toStringAsFixed(1)}%'
                  else
                    '0%',
                ],
              )
              .toList(),
        ),
      );
    }

    // 6) تكاليف الموارد البشرية
    widgets.add(_sectionTitle(fonts, 'تكاليف الموارد البشرية'));
    widgets.add(pw.SizedBox(height: 6));
    widgets.add(
      EnhancedPdfUtils.buildProfessionalTable(
        headers: const ['البيان', 'القيمة'],
        fonts: fonts,
        columnFlex: const [2.0, 1.3],
        data: [
          ['عدد الموظفين النشطين', '${data.activeEmployeesCount} موظف'],
          [
            'عدد الموظفين المنهية خدمتهم',
            '${data.terminatedEmployeesCount} موظف',
          ],
          [
            'إجمالي الالتزامات الرواتب الشهرية',
            EnhancedPdfUtils.formatNumber(data.totalSalaryObligation),
          ],
          [
            'الرواتب المدفوعة في الفترة',
            EnhancedPdfUtils.formatNumber(data.salaryTotal),
          ],
          [
            'نسبة الرواتب من الإيرادات',
            '${data.salaryRatio.toStringAsFixed(1)}%',
          ],
          [
            'نسبة الرواتب من المصروفات',
            if (data.expenseTotal > 0)
              '${(data.salaryTotal / data.expenseTotal * 100).toStringAsFixed(1)}%'
            else
              '0%',
          ],
        ],
      ),
    );

    // 7) إحصائيات الحجوزات والإشغال
    widgets.add(_sectionTitle(fonts, 'إحصائيات الحجوزات والإشغال'));
    widgets.add(pw.SizedBox(height: 6));
    widgets.add(
      EnhancedPdfUtils.buildProfessionalTable(
        headers: const ['البيان', 'القيمة'],
        fonts: fonts,
        columnFlex: const [2.0, 1.3],
        data: [
          ['إجمالي الحجوزات في الفترة', '${data.bookingsCount} حجز'],
          ['حجوزات نشطة (داخلين)', '${data.activeBookingsCount} حجز'],
          ['حجوزات مغادرة', '${data.checkoutBookingsCount} حجز'],
          [
            'متوسط الإيراد لكل حجز',
            if (data.bookingsCount > 0)
              EnhancedPdfUtils.formatNumber(
                data.incomeTotal / data.bookingsCount,
              )
            else
              '0',
          ],
        ],
      ),
    );

    // 8) المؤشرات المالية الرئيسية — تقرير نقدي بلا مؤشرات ديون
    widgets.add(_sectionTitle(fonts, 'المؤشرات المالية الرئيسية'));
    widgets.add(pw.SizedBox(height: 6));
    widgets.add(_buildFinancialIndicatorsTable(fonts, data));

    // 9) الملخص المحاسبي الشامل — قائمة أرباح وخسائر نقدية خالصة
    //    (لا يشمل الديون المستحقة — الديون ليست مدفوعات).
    widgets.add(_sectionTitle(fonts, 'الملخص المحاسبي الشامل'));
    widgets.add(pw.SizedBox(height: 6));
    final roomRevenue = data.incomeEntries
        .where((e) => e.revenueType == 'room' || e.revenueType.isEmpty)
        .fold<double>(0, (s, e) => s + e.amount);
    final otherRevenue = data.incomeTotal - roomRevenue;
    widgets.add(
      EnhancedPdfUtils.buildProfessionalTable(
        headers: const ['البيان', 'المبلغ'],
        fonts: fonts,
        columnFlex: const [2.0, 1.3],
        data: [
          ['إيرادات الغرف', EnhancedPdfUtils.formatNumber(roomRevenue)],
          ['إيرادات أخرى', EnhancedPdfUtils.formatNumber(otherRevenue)],
          [
            'إجمالي الإيرادات',
            EnhancedPdfUtils.formatNumber(data.incomeTotal),
          ],
          [
            '(-) مصروفات تشغيلية',
            EnhancedPdfUtils.formatNumber(data.nonSalaryTotal),
          ],
          [
            '(-) رواتب ومخصصات',
            EnhancedPdfUtils.formatNumber(data.salaryTotal),
          ],
          [
            'إجمالي المصروفات',
            EnhancedPdfUtils.formatNumber(data.expenseTotal),
          ],
          ['صافي الربح / الخسارة', EnhancedPdfUtils.formatNumber(data.net)],
        ],
      ),
    );

    return widgets;
  }

  // ─────────────── المحتوى التفصيلي المجمّع ───────────────

  static List<pw.Widget> _buildGroupedContent(
    ArabicPdfFonts fonts,
    IncomeExpenseReportData data,
    IncomeExpenseGroupMode mode,
  ) {
    final groups = buildGroups(data, mode);
    final widgets = <pw.Widget>[];

    // صناديق الملخص العام
    widgets.add(pw.SizedBox(height: 4));
    widgets.add(
      EnhancedPdfUtils.buildStatisticsGrid(
        items: [
          EnhancedPdfUtils.buildStatisticsBox(
            title: 'إجمالي الدخل',
            value: EnhancedPdfUtils.formatNumber(data.incomeTotal),
            fonts: fonts,
            color: PdfColors.success,
          ),
          EnhancedPdfUtils.buildStatisticsBox(
            title: 'إجمالي المصروفات',
            value: EnhancedPdfUtils.formatNumber(data.expenseTotal),
            fonts: fonts,
            color: PdfColors.danger,
          ),
          EnhancedPdfUtils.buildStatisticsBox(
            title: 'مصروفات الرواتب',
            value: EnhancedPdfUtils.formatNumber(data.salaryTotal),
            fonts: fonts,
            color: PdfColors.warning,
          ),
          EnhancedPdfUtils.buildStatisticsBox(
            title: 'صافي الربح / الخسارة',
            value: EnhancedPdfUtils.formatNumber(data.net),
            fonts: fonts,
            color: data.net >= 0 ? PdfColors.success : PdfColors.danger,
          ),
        ],
      ),
    );

    widgets.add(pw.SizedBox(height: 12));
    widgets.add(_sectionTitle(fonts, 'التفاصيل حسب الفترة (${mode.label})'));
    widgets.add(pw.SizedBox(height: 6));

    if (groups.isEmpty) {
      widgets.add(_emptyNote(fonts, 'لا توجد فترات ضمن النطاق المحدد'));
    }
    for (final group in groups) {
      widgets.add(_periodCard(fonts, group));
    }

    // الملخص النهائي الشامل
    widgets.add(pw.SizedBox(height: 12));
    widgets.add(_finalSummarySection(fonts, data, groups));

    // تحليل طرق الدفع
    widgets.add(_sectionTitle(fonts, 'تحليل طرق الدفع'));
    widgets.add(pw.SizedBox(height: 6));
    widgets.add(_buildPaymentMethodsTable(fonts, data));

    // تكاليف الموارد البشرية
    widgets.add(_sectionTitle(fonts, 'تكاليف الموارد البشرية'));
    widgets.add(pw.SizedBox(height: 6));
    widgets.add(
      EnhancedPdfUtils.buildProfessionalTable(
        headers: const ['البيان', 'القيمة'],
        fonts: fonts,
        columnFlex: const [2.0, 1.3],
        data: [
          ['عدد الموظفين النشطين', '${data.activeEmployeesCount} موظف'],
          [
            'عدد الموظفين المنهية خدمتهم',
            '${data.terminatedEmployeesCount} موظف',
          ],
          [
            'إجمالي الالتزامات الرواتب الشهرية',
            EnhancedPdfUtils.formatNumber(data.totalSalaryObligation),
          ],
          [
            'الرواتب المدفوعة في الفترة',
            EnhancedPdfUtils.formatNumber(data.salaryTotal),
          ],
          [
            'نسبة الرواتب من الإيرادات',
            '${data.salaryRatio.toStringAsFixed(1)}%',
          ],
        ],
      ),
    );

    // إحصائيات الحجوزات والإشغال
    widgets.add(_sectionTitle(fonts, 'إحصائيات الحجوزات والإشغال'));
    widgets.add(pw.SizedBox(height: 6));
    widgets.add(
      EnhancedPdfUtils.buildProfessionalTable(
        headers: const ['البيان', 'القيمة'],
        fonts: fonts,
        columnFlex: const [2.0, 1.3],
        data: [
          ['إجمالي الحجوزات في الفترة', '${data.bookingsCount} حجز'],
          ['حجوزات نشطة (داخلين)', '${data.activeBookingsCount} حجز'],
          ['حجوزات مغادرة', '${data.checkoutBookingsCount} حجز'],
          [
            'متوسط الإيراد لكل حجز',
            if (data.bookingsCount > 0)
              EnhancedPdfUtils.formatNumber(
                data.incomeTotal / data.bookingsCount,
              )
            else
              '0',
          ],
        ],
      ),
    );

    // المؤشرات المالية الرئيسية
    widgets.add(_sectionTitle(fonts, 'المؤشرات المالية الرئيسية'));
    widgets.add(pw.SizedBox(height: 6));
    widgets.add(_buildFinancialIndicatorsTable(fonts, data));

    return widgets;
  }

  /// بطاقة فترة واحدة (تقرير تفصيلي مجمّع).
  static pw.Widget _periodCard(
    ArabicPdfFonts fonts,
    IncomeExpensePeriodGroup group,
  ) {
    final isProfit = group.net >= 0;
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: isProfit ? PdfColors.success : PdfColors.danger,
          width: 0.8,
        ),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // عنوان الفترة المرقمة
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: pw.BoxDecoration(
              color: isProfit ? PdfColors.success : PdfColors.danger,
              borderRadius: const pw.BorderRadius.only(
                topLeft: pw.Radius.circular(3),
                topRight: pw.Radius.circular(3),
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
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.textWhite,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(10)),
                  ),
                  child: pw.Text(
                    isProfit ? 'ربح' : 'خسارة',
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 9,
                      color: isProfit ? PdfColors.success : PdfColors.danger,
                    ),
                  ),
                ),
              ],
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(10),
            child: pw.Column(
              children: [
                // 4 صناديق ملخص مصغرة
                pw.Row(
                  children: [
                    _periodMiniBox(
                      fonts,
                      'الدخل',
                      EnhancedPdfUtils.formatNumber(group.incomeTotal),
                      '${group.incomeCount} معاملة',
                      PdfColors.success,
                    ),
                    pw.SizedBox(width: 4),
                    _periodMiniBox(
                      fonts,
                      'المصروفات',
                      EnhancedPdfUtils.formatNumber(group.expenseTotal),
                      '${group.expenseCount} معاملة',
                      PdfColors.danger,
                    ),
                    pw.SizedBox(width: 4),
                    _periodMiniBox(
                      fonts,
                      'الرواتب',
                      EnhancedPdfUtils.formatNumber(group.salaryTotal),
                      '',
                      PdfColors.warning,
                    ),
                    pw.SizedBox(width: 4),
                    _periodMiniBox(
                      fonts,
                      'الصافي',
                      EnhancedPdfUtils.formatNumber(group.net),
                      '',
                      isProfit ? PdfColors.success : PdfColors.danger,
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                // جدول الدخل المصغر
                _miniTable(
                  fonts,
                  'الدخل',
                  const ['التاريخ', 'الغرفة', 'النزيل', 'النوع', 'المبلغ'],
                  group.incomeEntries
                      .map(
                        (e) => [
                          DateFormat('dd/MM/yyyy').format(e.date),
                          if (e.roomNumber.isNotEmpty) e.roomNumber else '-',
                          if (e.guestName.isNotEmpty) e.guestName else '-',
                          _revenueTypeName(e.revenueType),
                          EnhancedPdfUtils.formatNumber(e.amount),
                        ],
                      )
                      .toList(),
                  PdfColors.success,
                ),
                pw.SizedBox(height: 4),
                // جدول المصروفات المصغر
                _miniTable(
                  fonts,
                  'المصروفات',
                  const ['التاريخ', 'النوع', 'الوصف', 'المبلغ'],
                  group.expenseEntries
                      .map(
                        (e) => [
                          DateFormat('dd/MM/yyyy').format(e.date),
                          if (e.isSalary) 'رواتب' else e.type,
                          if (e.description.isNotEmpty) e.description else '-',
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

  static pw.Widget _periodMiniBox(
    ArabicPdfFonts fonts,
    String title,
    String value,
    String subtitle,
    PdfColor color,
  ) {
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
            if (subtitle.isNotEmpty)
              pw.Text(
                subtitle,
                style: pw.TextStyle(
                  font: fonts.regular,
                  fontSize: 8,
                  color: PdfColors.textWhite,
                ),
              )
            else
              pw.SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  /// جدول مصغر مقسّم لعدة جداول لتفادي تجمّد مكتبة pdf مع آلاف الصفوف.
  static pw.Widget _miniTable(
    ArabicPdfFonts fonts,
    String title,
    List<String> headers,
    List<List<String>> rows,
    PdfColor headerColor, {
    int chunkSize = 200,
  }) {
    if (rows.isEmpty) {
      return pw.Container();
    }
    final chunks = <List<List<String>>>[];
    for (var start = 0; start < rows.length; start += chunkSize) {
      final end = (start + chunkSize < rows.length)
          ? start + chunkSize
          : rows.length;
      chunks.add(rows.sublist(start, end));
    }
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
        for (final chunk in chunks) ...[
          if (chunk != chunks.first) pw.SizedBox(height: 3),
          _miniTableBlock(fonts, headers, chunk, headerColor),
        ],
      ],
    );
  }

  static pw.Widget _miniTableBlock(
    ArabicPdfFonts fonts,
    List<String> headers,
    List<List<String>> rows,
    PdfColor headerColor,
  ) {
    return pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.textLight, width: 0.3),
        ),
        child: pw.Table(
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: headerColor),
              children: headers
                  .map(
                    (h) => _miniCell(h, fonts.bold, PdfColors.textWhite),
                  )
                  .toList(),
            ),
            ...rows.asMap().entries.map((entry) {
              final isEven = entry.key.isEven;
              return pw.TableRow(
                decoration: isEven
                    ? const pw.BoxDecoration(color: PdfColors.tableStripe)
                    : const pw.BoxDecoration(
                        color: PdfColors.cardBackground,
                      ),
                children: entry.value
                    .map(
                      (cell) =>
                          _miniCell(cell, fonts.regular, PdfColors.textDark),
                    )
                    .toList(),
              );
            }),
          ],
        ),
      ),
    );
  }

  static pw.Widget _miniCell(String text, pw.Font font, PdfColor color) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(font: font, fontSize: 8, color: color),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  /// الملخص النهائي الشامل للتقرير التفصيلي.
  static pw.Widget _finalSummarySection(
    ArabicPdfFonts fonts,
    IncomeExpenseReportData data,
    List<IncomeExpensePeriodGroup> groups,
  ) {
    IncomeExpensePeriodGroup? bestPeriod;
    IncomeExpensePeriodGroup? worstPeriod;
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

    final totalTx = data.incomeEntries.length + data.expenseEntries.length;
    final avgNet = groups.isEmpty ? 0.0 : data.net / groups.length;

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.cardBackground,
        border: pw.Border.all(color: PdfColors.primary),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
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
          EnhancedPdfUtils.buildProfessionalTable(
            headers: const ['البيان', 'القيمة'],
            fonts: fonts,
            columnFlex: const [1.8, 1.5],
            data: [
              ['إجمالي المعاملات', '$totalTx معاملة'],
              ['عدد الفترات', '${groups.length} فترة'],
              ['متوسط الصافي لكل فترة', EnhancedPdfUtils.formatNumber(avgNet)],
              ['إجمالي الدخل', EnhancedPdfUtils.formatNumber(data.incomeTotal)],
              [
                'إجمالي المصروفات',
                EnhancedPdfUtils.formatNumber(data.expenseTotal),
              ],
              [
                'مصروفات الرواتب',
                EnhancedPdfUtils.formatNumber(data.salaryTotal),
              ],
              ['الصافي النهائي', EnhancedPdfUtils.formatNumber(data.net)],
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

  // ─────────────── جداول مشتركة ───────────────

  static List<List<String>> _incomeRows(
    List<IncomeExpenseIncomeEntry> entries,
  ) {
    return entries.asMap().entries.map((entry) {
      final e = entry.value;
      final i = entry.key + 1;
      return [
        '$i',
        EnhancedPdfUtils.formatDateShort(e.date),
        if (e.roomNumber.isNotEmpty) e.roomNumber else '-',
        if (e.guestName.isNotEmpty) e.guestName else '-',
        _paymentMethodName(e.paymentMethod),
        _revenueTypeName(e.revenueType),
        EnhancedPdfUtils.formatNumber(e.amount),
      ];
    }).toList();
  }

  static List<List<String>> _expenseRows(
    List<IncomeExpenseExpenseEntry> entries,
  ) {
    return entries.asMap().entries.map((entry) {
      final e = entry.value;
      final i = entry.key + 1;
      return [
        '$i',
        EnhancedPdfUtils.formatDateShort(e.date),
        if (e.isSalary) 'رواتب' else e.type,
        if (e.description.isNotEmpty) e.description else '-',
        EnhancedPdfUtils.formatNumber(e.amount),
      ];
    }).toList();
  }

  static pw.Widget _buildPaymentMethodsTable(
    ArabicPdfFonts fonts,
    IncomeExpenseReportData data,
  ) {
    final cashIncome = data.incomeEntries
        .where((e) => e.paymentMethod == 'cash')
        .fold<double>(0, (s, e) => s + e.amount);
    final cardIncome = data.incomeEntries
        .where((e) => e.paymentMethod == 'card')
        .fold<double>(0, (s, e) => s + e.amount);
    final transferIncome = data.incomeEntries
        .where((e) => e.paymentMethod == 'transfer')
        .fold<double>(0, (s, e) => s + e.amount);
    final otherMethodIncome =
        data.incomeTotal - cashIncome - cardIncome - transferIncome;

    String pct(double v) => data.incomeTotal > 0
        ? '${(v / data.incomeTotal * 100).toStringAsFixed(1)}%'
        : '0%';

    return EnhancedPdfUtils.buildProfessionalTable(
      headers: const ['طريقة الدفع', 'المبلغ', 'العدد', 'النسبة'],
      fonts: fonts,
      columnFlex: const [1.6, 1.2, 0.8, 0.9],
      alignments: const [
        pw.TextAlign.right,
        pw.TextAlign.center,
        pw.TextAlign.center,
        pw.TextAlign.center,
      ],
      data: [
        [
          'نقداً',
          EnhancedPdfUtils.formatNumber(cashIncome),
          '${data.incomeEntries.where((e) => e.paymentMethod == 'cash').length}',
          pct(cashIncome),
        ],
        [
          'بطاقة ائتمانية',
          EnhancedPdfUtils.formatNumber(cardIncome),
          '${data.incomeEntries.where((e) => e.paymentMethod == 'card').length}',
          pct(cardIncome),
        ],
        [
          'تحويل بنكي',
          EnhancedPdfUtils.formatNumber(transferIncome),
          '${data.incomeEntries.where((e) => e.paymentMethod == 'transfer').length}',
          pct(transferIncome),
        ],
        if (otherMethodIncome > 0)
          [
            'أخرى',
            EnhancedPdfUtils.formatNumber(otherMethodIncome),
            '${data.incomeEntries.where((e) => e.paymentMethod != 'cash' && e.paymentMethod != 'card' && e.paymentMethod != 'transfer').length}',
            pct(otherMethodIncome),
          ],
        [
          'الإجمالي',
          EnhancedPdfUtils.formatNumber(data.incomeTotal),
          '${data.incomeEntries.length}',
          '100%',
        ],
      ],
    );
  }

  /// المؤشرات المالية — تقرير نقدي خالص: لا مؤشرات ديون.
  static pw.Widget _buildFinancialIndicatorsTable(
    ArabicPdfFonts fonts,
    IncomeExpenseReportData data,
  ) {
    final profitMargin = data.profitMargin;
    final expenseRatio = data.expenseRatio;
    final salaryRatio = data.salaryRatio;

    return EnhancedPdfUtils.buildProfessionalTable(
      headers: const ['المؤشر', 'القيمة', 'التقييم'],
      fonts: fonts,
      columnFlex: const [1.8, 0.9, 0.9],
      alignments: const [
        pw.TextAlign.right,
        pw.TextAlign.center,
        pw.TextAlign.center,
      ],
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
          '${salaryRatio.toStringAsFixed(1)}%',
          if (salaryRatio < 30)
            'ممتاز'
          else if (salaryRatio < 50)
            'جيد'
          else
            'مرتفع',
        ],
      ],
    );
  }

  // ─────────────── أدوات مشتركة ───────────────

  static pw.Widget _sectionTitle(ArabicPdfFonts fonts, String title) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      margin: const pw.EdgeInsets.only(top: 16),
      decoration: const pw.BoxDecoration(
        color: PdfColors.primary,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
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

  static pw.Widget _emptyNote(ArabicPdfFonts fonts, String text) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.cardBackground,
        border: pw.Border.all(color: PdfColors.border, width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Text(
        text,
        style: PdfTextStyles.body(fonts),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  static Map<String, double> _expenseByType(IncomeExpenseReportData data) {
    final map = <String, double>{};
    for (final e in data.expenseEntries) {
      final key = e.isSalary ? 'رواتب' : e.type;
      map[key] = (map[key] ?? 0) + e.amount;
    }
    final sortedEntries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sortedEntries);
  }

  static String _groupKey(DateTime date, IncomeExpenseGroupMode mode) {
    switch (mode) {
      case IncomeExpenseGroupMode.daily:
        return DateFormat('yyyy-MM-dd').format(date);
      case IncomeExpenseGroupMode.monthly:
        return DateFormat('yyyy-MM').format(date);
      case IncomeExpenseGroupMode.yearly:
        return DateFormat('yyyy').format(date);
    }
  }

  static const List<String> _arabicDays = [
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
    'الأحد',
  ];

  static const List<String> _arabicMonths = [
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

  static String _groupLabel(String key, IncomeExpenseGroupMode mode) {
    switch (mode) {
      case IncomeExpenseGroupMode.daily:
        final dt = DateTime.parse(key);
        final dayName = _arabicDays[dt.weekday - 1];
        return '${dt.day} ${_arabicMonths[dt.month]} ${dt.year} ($dayName)';
      case IncomeExpenseGroupMode.monthly:
        final parts = key.split('-');
        return '${_arabicMonths[int.parse(parts[1])]} ${parts[0]}';
      case IncomeExpenseGroupMode.yearly:
        return '$key م';
    }
  }

  /// ترجمة طريقة الدفع.
  static String _paymentMethodName(String method) {
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

  /// ترجمة نوع الإيراد.
  static String _revenueTypeName(String type) {
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
}
