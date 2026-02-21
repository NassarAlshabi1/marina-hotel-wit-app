import 'package:pdf/pdf.dart' hide PdfColors;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

import '../utils/enhanced_pdf_utils.dart';

/// تقرير دفوعات محسّن
class EnhancedPaymentsReport {

  EnhancedPaymentsReport({
    required this.payments,
    required this.fromDate,
    required this.toDate,
    this.roomFilter,
    required this.generatedBy,
  });
  final List<PaymentReportItem> payments;
  final DateTime fromDate;
  final DateTime toDate;
  final String? roomFilter;
  final String generatedBy;

  double get totalAmount =>
      payments.fold(0, (sum, payment) => sum + payment.amount);
  double get cashPayments => payments
      .where((p) => p.method == 'cash')
      .fold(0, (sum, p) => sum + p.amount);
  double get cardPayments => payments
      .where((p) => p.method == 'card')
      .fold(0, (sum, p) => sum + p.amount);
  int get totalTransactions => payments.length;

  Future<void> generatePDF() async {
    final fonts = await EnhancedPdfUtils.loadArabicFonts();
    final logo = await EnhancedPdfUtils.loadLogoImage();
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        header: (context) => _buildReportHeader(fonts, logo),
        footer: (context) => _buildReportFooter(context, fonts),
        build: (context) => _buildReportContent(fonts),
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename:
          'payments-report-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.pdf',
    );
  }

  pw.Widget _buildReportHeader(ArabicPdfFonts fonts, pw.ImageProvider? logo) {
    return pw.Column(
      children: [
        EnhancedPdfUtils.buildProfessionalHeader(
          fonts: fonts,
          logo: logo,
          title: 'تقرير المدفوعات',
          subtitle: 'Payments Report',
        ),
        pw.SizedBox(height: 20),
      ],
    );
  }

  pw.Widget _buildReportFooter(pw.Context context, ArabicPdfFonts fonts) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 16),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.textLight, width: 1),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'تم إنشاء التقرير بواسطة: $generatedBy',
            style: PdfTextStyles.caption(fonts.regular),
          ),
          pw.Text(
            'صفحة ${context.pageNumber} من ${context.pagesCount}',
            style: PdfTextStyles.caption(fonts.regular),
          ),
        ],
      ),
    );
  }

  List<pw.Widget> _buildReportContent(ArabicPdfFonts fonts) {
    return [
      // معلومات التقرير
      _buildReportInfo(fonts),

      pw.SizedBox(height: 20),

      // إحصائيات سريعة
      _buildQuickStats(fonts),

      pw.SizedBox(height: 20),

      // تحليل طرق الدفع
      _buildPaymentMethodAnalysis(fonts),

      pw.SizedBox(height: 20),

      // جدول تفصيلي للمدفوعات
      _buildDetailedPaymentsTable(fonts),

      pw.SizedBox(height: 20),

      // إحصائيات يومية
      _buildDailySummary(fonts),
    ];
  }

  pw.Widget _buildReportInfo(ArabicPdfFonts fonts) {
    final periodLabel =
        '${EnhancedPdfUtils.formatDateTime(fromDate)} - ${EnhancedPdfUtils.formatDateTime(toDate)}';
    final roomLabel = roomFilter != null ? 'الغرفة: $roomFilter' : 'جميع الغرف';

    return EnhancedPdfUtils.buildInfoCard(
      title: '📊 معلومات التقرير',
      fonts: fonts,
      borderColor: PdfColors.info,
      content: [
        _buildInfoRow('فترة التقرير:', periodLabel, fonts),
        pw.SizedBox(height: 6),
        _buildInfoRow('نطاق البيانات:', roomLabel, fonts),
        pw.SizedBox(height: 6),
        _buildInfoRow(
          'تاريخ الإنشاء:',
          EnhancedPdfUtils.formatDateTime(DateTime.now()),
          fonts,
        ),
        pw.SizedBox(height: 6),
        _buildInfoRow('عدد المعاملات:', '$totalTransactions معاملة', fonts),
      ],
    );
  }

  pw.Widget _buildQuickStats(ArabicPdfFonts fonts) {
    return pw.Row(
      children: [
        pw.Expanded(
          child: EnhancedPdfUtils.buildStatisticsBox(
            title: 'إجمالي المدفوعات',
            value: EnhancedPdfUtils.formatNumber(totalAmount),
            // subtitle: '',
            fonts: fonts,
            color: PdfColors.success,
            icon: '💰',
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: EnhancedPdfUtils.buildStatisticsBox(
            title: 'عدد المعاملات',
            value: totalTransactions.toString(),
            subtitle: 'معاملة',
            fonts: fonts,
            color: PdfColors.info,
            icon: '📊',
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: EnhancedPdfUtils.buildStatisticsBox(
            title: 'متوسط المعاملة',
            value: EnhancedPdfUtils.formatNumber(
              totalTransactions > 0 ? totalAmount / totalTransactions : 0,
            ),
            // subtitle: '',
            fonts: fonts,
            color: PdfColors.accent,
            icon: '📈',
          ),
        ),
      ],
    );
  }

  pw.Widget _buildPaymentMethodAnalysis(ArabicPdfFonts fonts) {
    final transferPayments = payments
        .where((p) => p.method == 'transfer')
        .fold(0.0, (sum, p) => sum + p.amount);
    final checkPayments = payments
        .where((p) => p.method == 'check')
        .fold(0.0, (sum, p) => sum + p.amount);

    return EnhancedPdfUtils.buildInfoCard(
      title: '💳 تحليل طرق الدفع',
      fonts: fonts,
      borderColor: PdfColors.secondary,
      content: [
        EnhancedPdfUtils.buildProfessionalTable(
          headers: [
            'طريقة الدفع',
            'عدد المعاملات',
            'إجمالي المبلغ',
            'النسبة المئوية',
          ],
          data: [
            [
              'نقداً',
              payments.where((p) => p.method == 'cash').length.toString(),
              EnhancedPdfUtils.formatCurrency(cashPayments),
              '${((cashPayments / totalAmount) * 100).toStringAsFixed(1)}%',
            ],
            [
              'بطاقة ائتمانية',
              payments.where((p) => p.method == 'card').length.toString(),
              EnhancedPdfUtils.formatCurrency(cardPayments),
              '${((cardPayments / totalAmount) * 100).toStringAsFixed(1)}%',
            ],
            [
              'تحويل بنكي',
              payments.where((p) => p.method == 'transfer').length.toString(),
              EnhancedPdfUtils.formatCurrency(transferPayments),
              '${((transferPayments / totalAmount) * 100).toStringAsFixed(1)}%',
            ],
            if (checkPayments > 0)
              [
                'شيك',
                payments.where((p) => p.method == 'check').length.toString(),
                EnhancedPdfUtils.formatCurrency(checkPayments),
                '${((checkPayments / totalAmount) * 100).toStringAsFixed(1)}%',
              ],
          ],
          fonts: fonts,
          headerColor: PdfColors.secondary,
        ),
      ],
    );
  }

  pw.Widget _buildDetailedPaymentsTable(ArabicPdfFonts fonts) {
    return EnhancedPdfUtils.buildInfoCard(
      title: '📋 تفاصيل المدفوعات',
      fonts: fonts,
      borderColor: PdfColors.primary,
      content: [
        EnhancedPdfUtils.buildProfessionalTable(
          headers: [
            'التاريخ',
            'النزيل',
            'الغرفة',
            'المبلغ',
            'طريقة الدفع',
            'المحاسب',
          ],
          data: payments
              .map(
                (payment) => [
                  DateFormat('dd/MM/yyyy').format(payment.paymentDate),
                  payment.guestName,
                  payment.roomNumber,
                  EnhancedPdfUtils.formatCurrency(payment.amount),
                  _getPaymentMethodName(payment.method),
                  payment.receivedBy ?? '',
                ],
              )
              .toList(),
          fonts: fonts,
          columnWidths: [0.15, 0.25, 0.1, 0.15, 0.2, 0.15],
        ),
      ],
    );
  }

  pw.Widget _buildDailySummary(ArabicPdfFonts fonts) {
    // تجميع المدفوعات حسب التاريخ
    final Map<String, DailySummary> dailySummaries = {};

    for (final payment in payments) {
      final dateKey = DateFormat('yyyy-MM-dd').format(payment.paymentDate);
      if (!dailySummaries.containsKey(dateKey)) {
        dailySummaries[dateKey] = DailySummary(
          date: payment.paymentDate,
          totalAmount: 0,
          transactionCount: 0,
        );
      }
      dailySummaries[dateKey]!.totalAmount += payment.amount;
      dailySummaries[dateKey]!.transactionCount++;
    }

    final sortedSummaries = dailySummaries.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    return EnhancedPdfUtils.buildInfoCard(
      title: '📅 ملخص يومي',
      fonts: fonts,
      borderColor: PdfColors.accent,
      content: [
        if (sortedSummaries.isNotEmpty)
          EnhancedPdfUtils.buildProfessionalTable(
            headers: [
              'التاريخ',
              'عدد المعاملات',
              'إجمالي المبلغ',
              'متوسط المعاملة',
            ],
            data: sortedSummaries
                .map(
                  (summary) => [
                    DateFormat('dd/MM/yyyy').format(summary.date),
                    summary.transactionCount.toString(),
                    EnhancedPdfUtils.formatCurrency(summary.totalAmount),
                    EnhancedPdfUtils.formatCurrency(
                      summary.totalAmount / summary.transactionCount,
                    ),
                  ],
                )
                .toList(),
            fonts: fonts,
            headerColor: PdfColors.accent,
          )
        else
          pw.Text(
            'لا توجد بيانات للفترة المحددة',
            style: PdfTextStyles.body(fonts.regular),
            textAlign: pw.TextAlign.center,
          ),
      ],
    );
  }

  pw.Widget _buildInfoRow(String label, String value, ArabicPdfFonts fonts) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: PdfTextStyles.bodyBold(fonts.bold)),
        pw.Flexible(
          child: pw.Text(value, style: PdfTextStyles.body(fonts.regular)),
        ),
      ],
    );
  }

  String _getPaymentMethodName(String method) {
    switch (method) {
      case 'cash':
        return 'نقداً';
      case 'card':
        return 'بطاقة ائتمانية';
      case 'transfer':
        return 'تحويل بنكي';
      case 'check':
        return 'شيك';
      default:
        return method;
    }
  }
}

/// عنصر تقرير الدفعة
class PaymentReportItem {

  PaymentReportItem({
    required this.guestName,
    required this.roomNumber,
    required this.amount,
    required this.method,
    required this.paymentDate,
    this.receivedBy,
    this.notes,
  });
  final String guestName;
  final String roomNumber;
  final double amount;
  final String method;
  final DateTime paymentDate;
  final String? receivedBy;
  final String? notes;
}

/// ملخص يومي
class DailySummary {

  DailySummary({
    required this.date,
    required this.totalAmount,
    required this.transactionCount,
  });
  final DateTime date;
  double totalAmount;
  int transactionCount;
}

/// تقرير المصروفات المحسّن
class EnhancedExpensesReport {

  EnhancedExpensesReport({
    required this.expenses,
    required this.fromDate,
    required this.toDate,
    this.categoryFilter,
    required this.generatedBy,
  });
  final List<ExpenseReportItem> expenses;
  final DateTime fromDate;
  final DateTime toDate;
  final String? categoryFilter;
  final String generatedBy;

  double get totalAmount =>
      expenses.fold(0, (sum, expense) => sum + expense.amount);
  int get totalTransactions => expenses.length;

  Future<void> generatePDF() async {
    final fonts = await EnhancedPdfUtils.loadArabicFonts();
    final logo = await EnhancedPdfUtils.loadLogoImage();
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        header: (context) => EnhancedPdfUtils.buildProfessionalHeader(
          fonts: fonts,
          logo: logo,
          title: 'تقرير المصروفات',
          subtitle: 'Expenses Report',
        ),
        footer: (context) => _buildReportFooter(context, fonts),
        build: (context) => _buildExpensesContent(fonts),
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename:
          'expenses-report-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.pdf',
    );
  }

  List<pw.Widget> _buildExpensesContent(ArabicPdfFonts fonts) {
    return [
      pw.SizedBox(height: 20),

      // معلومات التقرير
      _buildExpenseReportInfo(fonts),

      pw.SizedBox(height: 20),

      // إحصائيات سريعة
      _buildExpenseQuickStats(fonts),

      pw.SizedBox(height: 20),

      // تحليل الفئات
      _buildCategoryAnalysis(fonts),

      pw.SizedBox(height: 20),

      // جدول تفصيلي
      _buildDetailedExpensesTable(fonts),
    ];
  }

  pw.Widget _buildExpenseReportInfo(ArabicPdfFonts fonts) {
    final periodLabel =
        '${EnhancedPdfUtils.formatDateTime(fromDate)} - ${EnhancedPdfUtils.formatDateTime(toDate)}';
    final categoryLabel = categoryFilter != null
        ? 'الفئة: $categoryFilter'
        : 'جميع الفئات';

    return EnhancedPdfUtils.buildInfoCard(
      title: '📊 معلومات التقرير',
      fonts: fonts,
      borderColor: PdfColors.warning,
      content: [
        _buildInfoRow('فترة التقرير:', periodLabel, fonts),
        pw.SizedBox(height: 6),
        _buildInfoRow('نطاق البيانات:', categoryLabel, fonts),
        pw.SizedBox(height: 6),
        _buildInfoRow(
          'تاريخ الإنشاء:',
          EnhancedPdfUtils.formatDateTime(DateTime.now()),
          fonts,
        ),
        pw.SizedBox(height: 6),
        _buildInfoRow('عدد المصروفات:', '$totalTransactions مصروف', fonts),
      ],
    );
  }

  pw.Widget _buildExpenseQuickStats(ArabicPdfFonts fonts) {
    final highestExpense = expenses.isNotEmpty
        ? expenses.reduce((a, b) => a.amount > b.amount ? a : b).amount
        : 0.0;

    return pw.Row(
      children: [
        pw.Expanded(
          child: EnhancedPdfUtils.buildStatisticsBox(
            title: 'إجمالي المصروفات',
            value: EnhancedPdfUtils.formatNumber(totalAmount),
            // subtitle: '',
            fonts: fonts,
            color: PdfColors.danger,
            icon: '💸',
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: EnhancedPdfUtils.buildStatisticsBox(
            title: 'عدد المصروفات',
            value: totalTransactions.toString(),
            subtitle: 'مصروف',
            fonts: fonts,
            color: PdfColors.warning,
            icon: '📝',
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: EnhancedPdfUtils.buildStatisticsBox(
            title: 'أعلى مصروف',
            value: EnhancedPdfUtils.formatNumber(highestExpense),
            // subtitle: '',
            fonts: fonts,
            color: PdfColors.info,
            icon: '⬆️',
          ),
        ),
      ],
    );
  }

  pw.Widget _buildCategoryAnalysis(ArabicPdfFonts fonts) {
    // تجميع المصروفات حسب الفئة
    final Map<String, CategorySummary> categories = {};

    for (final expense in expenses) {
      if (!categories.containsKey(expense.category)) {
        categories[expense.category] = CategorySummary(
          category: expense.category,
          totalAmount: 0,
          count: 0,
        );
      }
      categories[expense.category]!.totalAmount += expense.amount;
      categories[expense.category]!.count++;
    }

    final sortedCategories = categories.values.toList()
      ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

    return EnhancedPdfUtils.buildInfoCard(
      title: '🏷️ تحليل الفئات',
      fonts: fonts,
      borderColor: PdfColors.secondary,
      content: [
        if (sortedCategories.isNotEmpty)
          EnhancedPdfUtils.buildProfessionalTable(
            headers: [
              'الفئة',
              'عدد المصروفات',
              'إجمالي المبلغ',
              'النسبة المئوية',
            ],
            data: sortedCategories
                .map(
                  (cat) => [
                    cat.category,
                    cat.count.toString(),
                    EnhancedPdfUtils.formatCurrency(cat.totalAmount),
                    '${((cat.totalAmount / totalAmount) * 100).toStringAsFixed(1)}%',
                  ],
                )
                .toList(),
            fonts: fonts,
            headerColor: PdfColors.secondary,
          )
        else
          pw.Text(
            'لا توجد بيانات للفترة المحددة',
            style: PdfTextStyles.body(fonts.regular),
            textAlign: pw.TextAlign.center,
          ),
      ],
    );
  }

  pw.Widget _buildDetailedExpensesTable(ArabicPdfFonts fonts) {
    return EnhancedPdfUtils.buildInfoCard(
      title: '📋 تفاصيل المصروفات',
      fonts: fonts,
      borderColor: PdfColors.primary,
      content: [
        if (expenses.isNotEmpty)
          EnhancedPdfUtils.buildProfessionalTable(
            headers: ['التاريخ', 'الوصف', 'الفئة', 'المبلغ', 'ملاحظات'],
            data: expenses
                .map(
                  (expense) => [
                    DateFormat('dd/MM/yyyy').format(expense.date),
                    expense.description,
                    expense.category,
                    EnhancedPdfUtils.formatCurrency(expense.amount),
                    expense.notes ?? '-',
                  ],
                )
                .toList(),
            fonts: fonts,
            columnWidths: [0.15, 0.3, 0.2, 0.15, 0.2],
          )
        else
          pw.Text(
            'لا توجد مصروفات للفترة المحددة',
            style: PdfTextStyles.body(fonts.regular),
            textAlign: pw.TextAlign.center,
          ),
      ],
    );
  }

  pw.Widget _buildReportFooter(pw.Context context, ArabicPdfFonts fonts) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 16),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.textLight, width: 1),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'تم إنشاء التقرير بواسطة: $generatedBy',
            style: PdfTextStyles.caption(fonts.regular),
          ),
          pw.Text(
            'صفحة ${context.pageNumber} من ${context.pagesCount}',
            style: PdfTextStyles.caption(fonts.regular),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildInfoRow(String label, String value, ArabicPdfFonts fonts) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: PdfTextStyles.bodyBold(fonts.bold)),
        pw.Flexible(
          child: pw.Text(value, style: PdfTextStyles.body(fonts.regular)),
        ),
      ],
    );
  }
}

/// عنصر تقرير المصروف
class ExpenseReportItem {

  ExpenseReportItem({
    required this.description,
    required this.category,
    required this.amount,
    required this.date,
    this.notes,
  });
  final String description;
  final String category;
  final double amount;
  final DateTime date;
  final String? notes;
}

/// ملخص الفئة
class CategorySummary {

  CategorySummary({
    required this.category,
    required this.totalAmount,
    required this.count,
  });
  final String category;
  double totalAmount;
  int count;
}
