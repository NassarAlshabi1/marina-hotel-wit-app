/// قوالب PDF لشاشة مدفوعات النزلاء التفصيلية — نظام قوالب مستقل.
///
/// قالبان:
/// 1. [GuestStatementPdf] كشف حساب نزيل واحد تفصيلي (مع سجل المدفوعات).
/// 2. [GuestsBalancesPdf] تقرير أرصدة كل النزلاء (بطاقة لكل نزيل).
///
/// الشاشة تُمرّر بيانات فقط، والقالب يتولى التصميم كاملاً من نظام
/// التصميم الموحّد في lib/src/pdf/enhanced_pdf_utils.dart.
library;

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' show PdfColor;
import 'package:pdf/widgets.dart' as pw;

import '../enhanced_pdf_utils.dart';
import '../report_pdf_builder.dart';

// ═══════════════════════════════════════════════════════════════
// القالب 1: كشف حساب نزيل تفصيلي
// ═══════════════════════════════════════════════════════════════

/// دفعة واحدة داخل سجل مدفوعات كشف الحساب.
class GuestStatementPayment {
  GuestStatementPayment({
    required this.dateText,
    required this.amount,
    required this.method,
    required this.reference,
    required this.notes,
  });

  /// نص تاريخ الدفعة كما هو مخزّن (yyyy-MM-dd ...).
  final String dateText;
  final double amount;
  final String method;
  final String reference;
  final String notes;
}

/// بيانات كشف حساب النزيل.
class GuestStatementData {
  GuestStatementData({
    required this.guestName,
    required this.roomNumber,
    required this.checkinDate,
    required this.manualCheckoutDate,
    required this.actualDays,
    required this.nightsRemaining,
    required this.nightlyRate,
    required this.consumedCost,
    required this.remainingBalance,
    required this.totalPaid,
    required this.plannedCheckout,
    required this.totalPaidNights,
    required this.effectiveBalance,
    required this.hasPayments,
    required this.surplusAfterAllNights,
    required this.payments,
    this.autoOverdueDays = 0,
    this.autoOverdueCost = 0,
  });

  final String guestName;
  final String roomNumber;
  final DateTime checkinDate;

  /// المغادرة المتوقعة المحددة يدوياً (nullable في بيانات الحجز).
  final DateTime? manualCheckoutDate;
  final int actualDays;
  final int nightsRemaining;
  final double nightlyRate;
  final double consumedCost;

  /// رصيد الحجز المتبقي (سالب = للنزيل، موجب = عليه).
  final double remainingBalance;
  final double totalPaid;

  /// المغادرة المخططة المحسوبة من المدفوعات.
  final DateTime plannedCheckout;
  final int totalPaidNights;
  final double effectiveBalance;
  final bool hasPayments;
  final double surplusAfterAllNights;

  /// أيام التمديد التلقائي بعد المغادرة المخططة (0 = لا تمديد).
  final int autoOverdueDays;
  final double autoOverdueCost;

  final List<GuestStatementPayment> payments;

  bool get isAutoOverdue =>
      DateTime.now().isAfter(plannedCheckout) && hasPayments;
}

/// قالب كشف حساب النزيل التفصيلي.
class GuestStatementPdf {
  GuestStatementPdf._();

  /// مشاركة كشف حساب النزيل.
  static Future<void> share(GuestStatementData data) async {
    await ReportPdfBuilder.buildAndShare(
      ReportPdfConfig(
        title: 'كشف حساب نزيل تفصيلي',
        fileName: ReportPdfBuilder.generateFileName(
          'كشف-حساب-${data.guestName}',
        ),
        extraHeaderLine: 'النزيل: ${data.guestName} | غرفة: ${data.roomNumber}',
        buildContent: (fonts) {
          return [
            ..._accountSummaryCard(fonts, data),
            pw.SizedBox(height: 16),
            _plannedCheckoutCard(fonts, data),
            pw.SizedBox(height: 20),
            pw.Text(
              'سجل المدفوعات التفصيلي',
              style: PdfTextStyles.sectionTitle(fonts),
            ),
            pw.SizedBox(height: 10),
            ...EnhancedPdfUtils.buildChunkedTable(
              fonts: fonts,
              headers: [
                'التاريخ',
                'المبلغ',
                'طريقة الدفع',
                'رقم المرجع',
                'ملاحظات',
              ],
              data: data.payments
                  .map(
                    (p) => [
                      p.dateText.split('T').first,
                      EnhancedPdfUtils.formatNumber(p.amount),
                      p.method,
                      p.reference,
                      p.notes,
                    ],
                  )
                  .toList(),
              columnFlex: const [80, 80, 70, 70, 120],
            ),
            pw.SizedBox(height: 30),
            _signatureRow(fonts),
          ];
        },
      ),
    );
  }

  /// بطاقة ملخص الحساب والمدة الزمانية.
  static List<pw.Widget> _accountSummaryCard(
    ArabicPdfFonts fonts,
    GuestStatementData data,
  ) {
    final isCredit = data.remainingBalance < 0;
    final balanceColor = isCredit ? PdfColors.success : PdfColors.danger;

    return [
      EnhancedPdfUtils.buildInfoCard(
        title: 'ملخص الحساب والمدة الزمانية',
        fonts: fonts,
        content: [
          EnhancedPdfUtils.buildKeyValueRow(
            fonts: fonts,
            label: 'تاريخ الوصول',
            value: _fmtDate(data.checkinDate),
          ),
          EnhancedPdfUtils.buildKeyValueRow(
            fonts: fonts,
            label: 'المغادرة المتوقعة (يدوي)',
            value: data.manualCheckoutDate != null
                ? _fmtDate(data.manualCheckoutDate!)
                : 'غير محدد',
          ),
          EnhancedPdfUtils.buildKeyValueRow(
            fonts: fonts,
            label: 'الأيام المقضية',
            value: '${data.actualDays} يوم',
          ),
          EnhancedPdfUtils.buildKeyValueRow(
            fonts: fonts,
            label: 'الأيام المتبقية',
            value: '${data.nightsRemaining} يوم',
          ),
          EnhancedPdfUtils.buildKeyValueRow(
            fonts: fonts,
            label: 'سعر الليلة',
            value: '${EnhancedPdfUtils.formatNumber(data.nightlyRate)} ريال',
          ),
          pw.Divider(color: PdfColors.border, thickness: 0.5),
          _amountLine(
            fonts,
            'إجمالي تكلفة الإقامة',
            EnhancedPdfUtils.formatNumber(data.consumedCost),
            color: PdfColors.textDark,
          ),
          _amountLine(
            fonts,
            isCredit ? 'المتبقي (له)' : 'المتبقي (عليه)',
            EnhancedPdfUtils.formatNumber(data.remainingBalance.abs()),
            color: balanceColor,
          ),
          pw.Divider(color: PdfColors.border, thickness: 0.3),
          _amountLine(
            fonts,
            'إجمالي المبالغ المدفوعة',
            EnhancedPdfUtils.formatNumber(data.totalPaid),
            color: PdfColors.success,
          ),
        ],
      ),
    ];
  }

  /// بطاقة المغادرة المخططة (محسوبة من المدفوعات) والتمديد التلقائي.
  static pw.Widget _plannedCheckoutCard(
    ArabicPdfFonts fonts,
    GuestStatementData data,
  ) {
    final isAutoOverdue = data.isAutoOverdue;

    return EnhancedPdfUtils.buildInfoCard(
      title: isAutoOverdue
          ? 'المغادرة المخططة (مُمدَّدة تلقائياً)'
          : 'المغادرة المخططة (محسوبة من المدفوعات)',
      fonts: fonts,
      content: [
        _amountLine(
          fonts,
          'إجمالي المدفوع',
          EnhancedPdfUtils.formatNumber(data.totalPaid),
          color: PdfColors.info,
        ),
        _amountLine(
          fonts,
          'سعر الليلة',
          EnhancedPdfUtils.formatNumber(data.nightlyRate),
          color: PdfColors.textDark,
        ),
        _amountLine(
          fonts,
          'الليالي المدفوعة',
          '${data.totalPaidNights} ليلة',
          color: PdfColors.textDark,
        ),
        _amountLine(
          fonts,
          'المغادرة المخططة',
          _fmtDate(data.plannedCheckout),
          color: PdfColors.success,
        ),
        _amountLine(
          fonts,
          'تكلفة الإقامة المستهلكة',
          EnhancedPdfUtils.formatNumber(data.consumedCost),
          color: PdfColors.textDark,
        ),
        _amountLine(
          fonts,
          'الرصيد الفعلي',
          EnhancedPdfUtils.formatNumber(data.effectiveBalance),
          color: data.effectiveBalance >= 0
              ? PdfColors.success
              : PdfColors.danger,
        ),
        if (isAutoOverdue && data.autoOverdueDays > 0) ...[
          pw.Divider(color: PdfColors.border, thickness: 0.5),
          _amountLine(
            fonts,
            'تمديد تلقائي',
            '+${data.autoOverdueDays} يوم',
            color: PdfColors.warning,
          ),
          _amountLine(
            fonts,
            'تكلفة التمديد',
            EnhancedPdfUtils.formatNumber(data.autoOverdueCost),
            color: PdfColors.danger,
          ),
          _amountLine(
            fonts,
            'ملاحظة',
            'المغادرة يدوياً فقط — لا يتم إخراج النزيل تلقائياً',
            color: PdfColors.textMuted,
          ),
        ],
        if (data.surplusAfterAllNights > 0)
          _amountLine(
            fonts,
            'فائض',
            EnhancedPdfUtils.formatNumber(data.surplusAfterAllNights),
            color: PdfColors.success,
          ),
      ],
    );
  }

  /// صف التوقيع والملاحظات الختامية.
  static pw.Widget _signatureRow(ArabicPdfFonts fonts) {
    return pw.Column(
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'ملاحظات:',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 10),
                ),
                pw.Text(
                  'يُحتسب اليوم الفندقي من الساعة 2:00 ظهراً.',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 9),
                ),
                pw.Text(
                  'تاريخ المغادرة التلقائي يُحسب من إجمالي المدفوعات التراكمية '
                  'مقسومة على سعر الليلة.',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 9),
                ),
                pw.Text(
                  'أي دفعة جديدة تُحدّث تاريخ المغادرة التلقائي فوراً.',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 9),
                ),
              ],
            ),
            pw.Column(
              children: [
                pw.Text(
                  'ختم وتوقيع الإدارة',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 12),
                ),
                pw.SizedBox(height: 40),
                pw.Container(width: 120, height: 1, color: PdfColors.textDark),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 20),
        pw.Center(
          child: pw.Text(
            'شكراً لاختياركم فندق مارينا - نتمنى لكم إقامة سعيدة',
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 10,
              color: PdfColors.textMuted,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }

  /// صف مبلغ label/value محاذاة بين الطرفين.
  static pw.Widget _amountLine(
    ArabicPdfFonts fonts,
    String label,
    String value, {
    required PdfColor color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            '$label:',
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 11,
              color: PdfColors.textDark,
            ),
          ),
          pw.Text(
            '$value ريال',
            style: pw.TextStyle(font: fonts.bold, fontSize: 11, color: color),
          ),
        ],
      ),
    );
  }

  static String _fmtDate(DateTime d) => DateFormat('yyyy/MM/dd').format(d);
}

// ═══════════════════════════════════════════════════════════════
// القالب 2: تقرير أرصدة كل النزلاء
// ═══════════════════════════════════════════════════════════════

/// صف نزيل واحد داخل تقرير الأرصدة.
class GuestBalanceRow {
  GuestBalanceRow({
    required this.roomNumber,
    required this.guestName,
    required this.checkinDate,
    required this.expectedCheckoutText,
    required this.actualDays,
    required this.nightlyRate,
    required this.contractTotal,
    required this.remainingBalance,
    required this.totalPaid,
    required this.hasPayments,
    required this.autoCheckoutText,
    required this.totalPaidNights,
    required this.isAutoExtended,
    required this.extraNightsBeyondManual,
    required this.uncoveredDays,
  });

  final String roomNumber;
  final String guestName;
  final DateTime checkinDate;

  /// المغادرة المتوقعة (يدوي) منسّقة نصياً.
  final String expectedCheckoutText;
  final int actualDays;
  final double nightlyRate;
  final double contractTotal;

  /// سالب = للنزيل، موجب = عليه.
  final double remainingBalance;
  final double totalPaid;
  final bool hasPayments;

  /// المغادرة التلقائية المحسوبة منسّقة نصياً.
  final String autoCheckoutText;
  final int totalPaidNights;
  final bool isAutoExtended;
  final int extraNightsBeyondManual;
  final int uncoveredDays;
}

/// بيانات تقرير أرصدة النزلاء.
class GuestsBalancesData {
  GuestsBalancesData({
    required this.rows,
    required this.totalDue,
    required this.totalPaid,
    required this.totalRemaining,
    required this.totalCredit,
    required this.reportDateText,
  });

  final List<GuestBalanceRow> rows;
  final double totalDue;
  final double totalPaid;
  final double totalRemaining;
  final double totalCredit;
  final String reportDateText;

  int get guestCount => rows.length;
}

/// قالب تقرير أرصدة النزلاء (بطاقة لكل نزيل).
class GuestsBalancesPdf {
  GuestsBalancesPdf._();

  static Future<void> share(GuestsBalancesData data) async {
    await ReportPdfBuilder.buildAndShare(
      ReportPdfConfig(
        title: 'تقرير مدفوعات النزلاء التفصيلي',
        fileName: ReportPdfBuilder.generateFileName('تقرير-مدفوعات-النزلاء'),
        extraHeaderLine: 'مارينا هوتيل | ${data.reportDateText}',
        buildContent: (fonts) {
          final widgets = <pw.Widget>[
            EnhancedPdfUtils.buildInfoCard(
              title: 'ملخص التقرير',
              fonts: fonts,
              content: [
                EnhancedPdfUtils.buildKeyValueRow(
                  fonts: fonts,
                  label: 'تاريخ التقرير',
                  value: data.reportDateText,
                ),
                EnhancedPdfUtils.buildKeyValueRow(
                  fonts: fonts,
                  label: 'عدد النزلاء',
                  value: '${data.guestCount}',
                ),
                _amountRow(
                  fonts,
                  'إجمالي المستحق',
                  EnhancedPdfUtils.formatNumber(data.totalDue),
                  color: PdfColors.warning,
                ),
                _amountRow(
                  fonts,
                  'إجمالي المحصل',
                  EnhancedPdfUtils.formatNumber(data.totalPaid),
                  color: PdfColors.success,
                ),
                _amountRow(
                  fonts,
                  'إجمالي المتبقي',
                  EnhancedPdfUtils.formatNumber(data.totalRemaining),
                  color: PdfColors.danger,
                ),
                if (data.totalCredit > 0)
                  _amountRow(
                    fonts,
                    'إجمالي الزيادة',
                    EnhancedPdfUtils.formatNumber(data.totalCredit),
                    color: PdfColors.info,
                  ),
              ],
            ),
          ];

          // بطاقة لكل نزيل
          for (final b in data.rows) {
            widgets.add(pw.SizedBox(height: 12));
            widgets.add(_guestCard(fonts, b));
          }

          return widgets;
        },
      ),
    );
  }

  static pw.Widget _guestCard(ArabicPdfFonts fonts, GuestBalanceRow b) {
    final isCredit = b.remainingBalance < 0;
    final balanceColor = isCredit ? PdfColors.success : PdfColors.danger;

    return EnhancedPdfUtils.buildInfoCard(
      title: 'غرفة ${b.roomNumber} — ${b.guestName}',
      fonts: fonts,
      content: [
        EnhancedPdfUtils.buildKeyValueRow(
          fonts: fonts,
          label: 'تاريخ الوصول',
          value: EnhancedPdfUtils.formatDateShort(b.checkinDate),
        ),
        EnhancedPdfUtils.buildKeyValueRow(
          fonts: fonts,
          label: 'المغادرة المتوقعة',
          value: b.expectedCheckoutText,
        ),
        EnhancedPdfUtils.buildKeyValueRow(
          fonts: fonts,
          label: 'الأيام المقضية',
          value: '${b.actualDays} يوم',
        ),
        EnhancedPdfUtils.buildKeyValueRow(
          fonts: fonts,
          label: 'سعر الليلة',
          value: '${EnhancedPdfUtils.formatNumber(b.nightlyRate)} ريال',
        ),
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                'إجمالي العقد: ${EnhancedPdfUtils.formatNumber(b.contractTotal)} ريال',
                style: pw.TextStyle(font: fonts.bold, fontSize: 10),
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Text(
                '${isCredit ? 'المتبقي (له)' : 'المتبقي (عليه)'}: '
                '${EnhancedPdfUtils.formatNumber(b.remainingBalance.abs())} ريال',
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 10,
                  color: balanceColor,
                ),
                textAlign: pw.TextAlign.left,
              ),
            ),
          ],
        ),
        pw.Divider(color: PdfColors.border, thickness: 0.3),
        EnhancedPdfUtils.buildKeyValueRow(
          fonts: fonts,
          label: 'إجمالي المدفوع',
          value: '${EnhancedPdfUtils.formatNumber(b.totalPaid)} ريال',
        ),
        if (b.hasPayments) ...[
          pw.Divider(color: PdfColors.border, thickness: 0.5),
          EnhancedPdfUtils.buildKeyValueRow(
            fonts: fonts,
            label: 'المغادرة التلقائية',
            value: b.autoCheckoutText,
          ),
          EnhancedPdfUtils.buildKeyValueRow(
            fonts: fonts,
            label: 'الليالي المدفوعة',
            value: '${b.totalPaidNights} ليلة',
          ),
          if (b.isAutoExtended)
            EnhancedPdfUtils.buildKeyValueRow(
              fonts: fonts,
              label: 'تمديد تلقائي',
              value: '+${b.extraNightsBeyondManual} يوم',
            ),
          if (b.uncoveredDays > 0)
            EnhancedPdfUtils.buildKeyValueRow(
              fonts: fonts,
              label: 'أيام غير مغطاة',
              value: '${b.uncoveredDays} ليلة',
            ),
        ],
      ],
    );
  }

  static pw.Widget _amountRow(
    ArabicPdfFonts fonts,
    String label,
    String value, {
    required PdfColor color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            '$label:',
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 9.5,
              color: PdfColors.textDark,
            ),
          ),
          pw.Text(
            '$value ريال',
            style: pw.TextStyle(font: fonts.bold, fontSize: 9.5, color: color),
          ),
        ],
      ),
    );
  }
}
