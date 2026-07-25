import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' hide PdfColors;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../utils/arabic_amount_formatter.dart';
import '../utils/enhanced_pdf_utils.dart';

/// أنواع طرق الدفع المتاحة
enum PaymentMethod {
  cash('نقدي', Icons.money, Colors.green),
  card('بطاقة ائتمانية', Icons.credit_card, Colors.blue),
  transfer('تحويل بنكي', Icons.account_balance, Colors.purple),
  check('شيك', Icons.receipt_long, Colors.orange),
  installment('تقسيط', Icons.schedule, Colors.indigo);

  const PaymentMethod(this.displayName, this.icon, this.color);
  final String displayName;
  final IconData icon;
  final Color color;
}

/// حالات المدفوعات
enum PaymentStatus {
  pending('في الانتظار', Colors.orange),
  completed('مكتمل', Colors.green),
  failed('فشل', Colors.red),
  refunded('مسترد', Colors.blue);

  const PaymentStatus(this.displayName, this.color);
  final String displayName;
  final Color color;
}

/// نموذج بيانات الدفعة
class Payment {
<<<<<<< HEAD
  Payment({      required this.id,
      required this.bookingId,
      required this.amount,
      required this.method,
      required this.status,
      required this.paymentDate,
      required this.receivedBy,
      required this.createdAt,
      required this.updatedAt,
      this.notes,
      this.referenceNumber,
      this.cardLastFourDigits,
      this.bankName,
=======
  Payment({
    required this.id,
    required this.bookingId,
    required this.amount,
    required this.method,
    required this.status,
    required this.paymentDate,
    this.notes,
    this.referenceNumber,
    this.cardLastFourDigits,
    this.bankName,
    required this.receivedBy,
    required this.createdAt,
    required this.updatedAt,
>>>>>>> origin/refactor/clean-v2
  });

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: json['id'] as String,
      bookingId: json['bookingId'] as String,
      amount: (json['amount'] as num).toDouble(),
      method: PaymentMethod.values.byName(json['method'] as String),
      status: PaymentStatus.values.byName(json['status'] as String),
      paymentDate: DateTime.parse(json['paymentDate'] as String),
      notes: json['notes'] as String?,
      referenceNumber: json['referenceNumber'] as String?,
      cardLastFourDigits: json['cardLastFourDigits'] as String?,
      bankName: json['bankName'] as String?,
      receivedBy: json['receivedBy'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
  final String id;
  final String bookingId;
  final double amount;
  final PaymentMethod method;
  final PaymentStatus status;
  final DateTime paymentDate;
  final String? notes;
  final String? referenceNumber;
  final String? cardLastFourDigits;
  final String? bankName;
  final String receivedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  Payment copyWith({
    String? id,
    String? bookingId,
    double? amount,
    PaymentMethod? method,
    PaymentStatus? status,
    DateTime? paymentDate,
    String? notes,
    String? referenceNumber,
    String? cardLastFourDigits,
    String? bankName,
    String? receivedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Payment(
      id: id ?? this.id,
      bookingId: bookingId ?? this.bookingId,
      amount: amount ?? this.amount,
      method: method ?? this.method,
      status: status ?? this.status,
      paymentDate: paymentDate ?? this.paymentDate,
      notes: notes ?? this.notes,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      cardLastFourDigits: cardLastFourDigits ?? this.cardLastFourDigits,
      bankName: bankName ?? this.bankName,
      receivedBy: receivedBy ?? this.receivedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bookingId': bookingId,
      'amount': amount,
      'method': method.name,
      'status': status.name,
      'paymentDate': paymentDate.toIso8601String(),
      'notes': notes,
      'referenceNumber': referenceNumber,
      'cardLastFourDigits': cardLastFourDigits,
      'bankName': bankName,
      'receivedBy': receivedBy,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

/// نموذج ملخص المدفوعات للحجز
class BookingPaymentSummary {
  BookingPaymentSummary({
    required this.bookingId,
    required this.totalAmount,
    required this.paidAmount,
    required this.remainingAmount,
    required this.payments,
    required this.overallStatus,
  });
  final String bookingId;
  final double totalAmount;
  final double paidAmount;
  final double remainingAmount;
  final List<Payment> payments;
  final PaymentStatus overallStatus;

  bool get isFullyPaid => remainingAmount <= 0;
  double get paidPercentage => totalAmount > 0 ? (paidAmount / totalAmount) * 100 : 0;
}

/// نموذج الإيصال
class Receipt {
<<<<<<< HEAD
  Receipt({      required this.receiptNumber,
      required this.payment,
      required this.guestName,
      required this.guestPhone,
      required this.roomNumber,
      required this.generatedAt,
      this.hotelName = 'فندق مارينا بلازا',
      this.hotelAddress = 'عدن - اليمن - شارع أحمد قاسم',
      this.hotelPhone = '+967-2-324457',
=======
  Receipt({
    required this.receiptNumber,
    required this.payment,
    required this.guestName,
    required this.guestPhone,
    required this.roomNumber,
    this.hotelName = 'فندق مارينا بلازا',
    this.hotelAddress = 'عدن - اليمن - شارع أحمد قاسم',
    this.hotelPhone = '+967-2-324457',
    required this.generatedAt,
>>>>>>> origin/refactor/clean-v2
  });
  final String receiptNumber;
  final Payment payment;
  final String guestName;
  final String guestPhone;
  final String roomNumber;
  final String hotelName;
  final String hotelAddress;
  final String hotelPhone;
  final DateTime generatedAt;

  /// إنشاء PDF للإيصال
  Future<void> generatePDF() async {
    final fonts = await EnhancedPdfUtils.loadArabicFonts();
    final logo = await EnhancedPdfUtils.loadLogoImage();
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(16),
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        build: (context) => _buildReceiptContent(fonts, logo),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  pw.Widget _buildReceiptContent(ArabicPdfFonts fonts, pw.ImageProvider? logo) {
    final formattedAmount = EnhancedPdfUtils.formatNumber(payment.amount);
    final amountInWords = formatYemeniAmount(payment.amount);
    final formattedGeneratedAt = _formatDateTime(generatedAt);
    final formattedPaymentDate = _formatDateTime(payment.paymentDate);
    final trimmedPhone = guestPhone.trim();
    final trimmedRoom = roomNumber.trim();
    final purpose = payment.notes != null && payment.notes!.trim().isNotEmpty
        ? payment.notes!.trim()
        : 'حجز رقم ${payment.bookingId}';

    return pw.Column(
      children: [
        // === رأس الإيصال ===
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: pw.BoxDecoration(color: PdfColors.primary, borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              // الشعار
              if (logo != null)
                pw.Container(
                  width: 48,
                  height: 48,
                  decoration: pw.BoxDecoration(color: PdfColors.textWhite, borderRadius: pw.BorderRadius.circular(24)),
                  child: pw.Center(child: pw.Image(logo, width: 40, height: 40)),
                )
              else
                pw.Container(
                  width: 48,
                  height: 48,
                  decoration: pw.BoxDecoration(color: PdfColors.textWhite, borderRadius: pw.BorderRadius.circular(24)),
                  child: pw.Center(
                    child: pw.Text(
                      'M',
                      style: pw.TextStyle(font: fonts.bold, fontSize: 22, color: PdfColors.primary),
                    ),
                  ),
                ),
              // اسم الفندق
              pw.Expanded(
                child: pw.Column(
                  children: [
                    pw.Text(
                      hotelName,
                      style: pw.TextStyle(font: fonts.bold, fontSize: 16, color: PdfColors.textWhite),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'MARINA PLAZA HOTEL',
                      style: pw.TextStyle(font: fonts.regular, fontSize: 10, color: const PdfColor(0.7, 0.85, 1.0)),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      hotelAddress,
                      style: pw.TextStyle(font: fonts.regular, fontSize: 9, color: const PdfColor(0.8, 0.9, 1.0)),
                    ),
                    pw.Text(
                      hotelPhone,
                      style: pw.TextStyle(font: fonts.regular, fontSize: 9, color: const PdfColor(0.8, 0.9, 1.0)),
                    ),
                  ],
                ),
              ),
              // أيقونة إيصال
              pw.Container(
                width: 48,
                height: 48,
                decoration: pw.BoxDecoration(color: PdfColors.secondary, borderRadius: pw.BorderRadius.circular(8)),
                child: pw.Center(
                  child: pw.Text(
<<<<<<< HEAD
                    r'$',
=======
                    '\$',
>>>>>>> origin/refactor/clean-v2
                    style: pw.TextStyle(font: fonts.bold, fontSize: 22, color: PdfColors.textWhite),
                  ),
                ),
              ),
            ],
          ),
        ),

        pw.SizedBox(height: 14),

        // === عنوان الإيصال ===
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          decoration: pw.BoxDecoration(
            color: PdfColors.backgroundLight,
            borderRadius: pw.BorderRadius.circular(6),
            border: pw.Border.all(color: const PdfColor(0.9, 0.9, 0.9)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'إيصال استلام نقدي',
                style: pw.TextStyle(font: fonts.bold, fontSize: 13, color: PdfColors.primary),
              ),
              pw.Text(
                'رقم: $receiptNumber',
                style: pw.TextStyle(font: fonts.regular, fontSize: 10, color: PdfColors.textLight),
              ),
            ],
          ),
        ),

        pw.SizedBox(height: 10),

        // === تفاصيل الإيصال ===
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(color: const PdfColor(0.88, 0.88, 0.88)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _receiptDetailRow(fonts, 'رقم الإيصال', receiptNumber),
              _receiptDivider(),
              _receiptDetailRow(fonts, 'التاريخ والوقت', formattedGeneratedAt),
              _receiptDivider(),
              _receiptDetailRow(fonts, 'تاريخ الدفع', formattedPaymentDate),
              _receiptDivider(),
              _receiptDetailRow(fonts, 'استلم من', guestName),
              if (trimmedPhone.isNotEmpty) ...[_receiptDivider(), _receiptDetailRow(fonts, 'رقم الهاتف', trimmedPhone)],
              if (trimmedRoom.isNotEmpty) ...[_receiptDivider(), _receiptDetailRow(fonts, 'رقم الغرفة', trimmedRoom)],
              _receiptDivider(),
              _receiptDetailRow(fonts, 'مقابل', purpose),
              _receiptDivider(),
              _receiptDetailRow(fonts, 'طريقة الدفع', payment.method.displayName),
              if (payment.referenceNumber != null && payment.referenceNumber!.trim().isNotEmpty) ...[
                _receiptDivider(),
                _receiptDetailRow(fonts, 'رقم المرجع', payment.referenceNumber!.trim()),
              ],
              _receiptDivider(),
              _receiptDetailRow(fonts, 'الموظف المسؤول', payment.receivedBy),
            ],
          ),
        ),

        pw.SizedBox(height: 10),

        // === المبلغ البارز ===
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: pw.BoxDecoration(
            gradient: const pw.LinearGradient(
              colors: [PdfColor(0.02, 0.33, 0.66), PdfColor(0.05, 0.45, 0.78)],
              begin: pw.Alignment.centerRight,
              end: pw.Alignment.centerLeft,
            ),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            children: [
              pw.Text(
                'المبلغ المدفوع',
                style: pw.TextStyle(font: fonts.regular, fontSize: 11, color: const PdfColor(0.8, 0.9, 1.0)),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                '$formattedAmount ريال يمني',
                style: pw.TextStyle(font: fonts.bold, fontSize: 22, color: PdfColors.textWhite),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                amountInWords,
                style: pw.TextStyle(font: fonts.regular, fontSize: 9, color: const PdfColor(0.85, 0.92, 1.0)),
              ),
            ],
          ),
        ),

        pw.SizedBox(height: 18),

        // === توقيع وختم ===
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // توقيع النزيل
            pw.Expanded(
              child: pw.Column(
                children: [
                  pw.Text(
                    'توقيع النزيل',
                    style: pw.TextStyle(font: fonts.bold, fontSize: 11, color: PdfColors.textDark),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    guestName,
                    style: pw.TextStyle(font: fonts.regular, fontSize: 10, color: PdfColors.textLight),
                  ),
                  pw.SizedBox(height: 24),
                  pw.Container(height: 1, width: 120, color: PdfColors.textLight),
                ],
              ),
            ),
            // ختم الفندق
            pw.Expanded(
              child: pw.Column(
                children: [
                  pw.Text(
                    'ختم الفندق',
                    style: pw.TextStyle(font: fonts.bold, fontSize: 11, color: PdfColors.textDark),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Container(
                    width: 64,
                    height: 64,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.primary, width: 2),
                      borderRadius: pw.BorderRadius.circular(32),
                    ),
                    child: pw.Center(
                      child: pw.Text(
                        'ختم',
                        style: pw.TextStyle(font: fonts.regular, fontSize: 9, color: PdfColors.textLight),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        pw.SizedBox(height: 14),

        // === تذييل ===
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 6),
          decoration: pw.BoxDecoration(color: PdfColors.backgroundLight, borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Center(
            child: pw.Text(
              'شكراً لتعاملكم معنا - نتطلع لخدمتكم مرة أخرى',
              style: pw.TextStyle(font: fonts.regular, fontSize: 9, color: PdfColors.textLight),
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _receiptDetailRow(ArabicPdfFonts fonts, String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              label,
              style: pw.TextStyle(font: fonts.bold, fontSize: 11, color: PdfColors.textDark),
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            flex: 3,
            child: pw.Text(
              value,
              style: pw.TextStyle(font: fonts.regular, fontSize: 11, color: PdfColors.textDark),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _receiptDivider() {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Divider(color: const PdfColor(0.92, 0.92, 0.92), thickness: 0.5),
    );
  }

  String _formatDateTime(DateTime date) {
    final datePart = DateFormat('dd/MM/yyyy', 'ar').format(date);
    final timePart = DateFormat('hh:mm a', 'ar').format(date);
    return '$datePart $timePart';
  }
}

/// نموذج الفاتورة الشاملة
class Invoice {
  Invoice({
    required this.invoiceNumber,
    required this.bookingId,
    required this.guestName,
    required this.guestPhone,
    required this.roomNumber,
    required this.checkinDate,
    required this.checkoutDate,
    required this.nights,
    required this.roomRate,
    required this.totalAmount,
    required this.payments,
    required this.remainingAmount,
    required this.generatedAt,
  });
  final String invoiceNumber;
  final String bookingId;
  final String guestName;
  final String guestPhone;
  final String roomNumber;
  final DateTime checkinDate;
  final DateTime checkoutDate;
  final int nights;
  final double roomRate;
  final double totalAmount;
  final List<Payment> payments;
  final double remainingAmount;
  final DateTime generatedAt;

  /// إنشاء PDF للفاتورة
  Future<void> generatePDF() async {
    final fonts = await EnhancedPdfUtils.loadArabicFonts();
    final logo = await EnhancedPdfUtils.loadLogoImage();
    final pdf = pw.Document();

    // ✅ MultiPage بدلاً من Page — يُدفق المحتوى عبر صفحات متعددة
    // عند كثرة الدفعات، يلتف الجدول تلقائياً للصفحة التالية بدلاً من قصّه
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        header: (context) => _buildPageHeader(fonts, logo, context),
        footer: (context) => _buildPageFooter(fonts, context),
        build: (context) => _buildInvoiceContent(fonts, logo),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  /// ✅ توليد PDF وإرجاع bytes (للمشاركة عبر واتساب)
  Future<Uint8List> generatePdfBytes() async {
    final fonts = await EnhancedPdfUtils.loadArabicFonts();
    final logo = await EnhancedPdfUtils.loadLogoImage();
    final pdf = pw.Document();

    // ✅ MultiPage — نفس السبب: دفعات كثيرة → صفحات متعددة بدلاً من القص
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        header: (context) => _buildPageHeader(fonts, logo, context),
        footer: (context) => _buildPageFooter(fonts, context),
        build: (context) => _buildInvoiceContent(fonts, logo),
      ),
    );

    return pdf.save();
  }

  // ═══════════════════════════════════════════════════════════════
  //  ألوان احترافية
  // ═══════════════════════════════════════════════════════════════
  static const _cPrimary = PdfColor(0.13, 0.27, 0.45); // أزرق كحلي
  static const _cAccent = PdfColor(0.18, 0.52, 0.74); // أزرق فاتح
  static const _cLight = PdfColor(0.96, 0.97, 0.98); // رمادي فاتح جداً
  static const _cBorder = PdfColor(0.85, 0.87, 0.90); // رمادي الحدود
  static const _cTextDark = PdfColor(0.15, 0.15, 0.18); // نص داكن
  static const _cTextLight = PdfColor(0.55, 0.58, 0.62); // نص فاتح
  static const _cGreen = PdfColor(0.16, 0.60, 0.32); // أخضر
  static const _cRed = PdfColor(0.78, 0.20, 0.20); // أحمر
  static const _cGold = PdfColor(0.75, 0.58, 0.10); // ذهبي

  /// ✅ يُرجع قائمة Widget بدلاً من Column واحد — لأن MultiPage.build يتطلب List<Widget>
  /// هذا يسمح للمحتوى بالتدفق عبر الصفحات بذكاء (جدول الدفعات الطويل يلتف لصفحة جديدة)
  List<pw.Widget> _buildInvoiceContent(ArabicPdfFonts fonts, pw.ImageProvider? logo) {
    final paidAmount = totalAmount - remainingAmount;
    return [
      // ═════════════════════════════════════════════════════════
      //  بطاقة معلومات العميل + الإقامة (صف واحد)
      // (الرأس الكبير أصبح في header لكل صفحة عبر _buildPageHeader)
      // ═════════════════════════════════════════════════════════
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: _buildInfoCard(
              fonts,
              title: 'بيانات العميل',
              titleColor: _cPrimary,
              rows: [('الاسم', guestName), ('الهاتف', guestPhone.isEmpty ? '—' : guestPhone), ('الغرفة', roomNumber)],
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: _buildInfoCard(
              fonts,
              title: 'تفاصيل الإقامة',
              titleColor: _cAccent,
              rows: [
                ('الوصول', _formatDate(checkinDate)),
                ('المغادرة', _formatDate(checkoutDate)),
                ('الليالي', '$nights ليلة'),
                ('سعر الليلة', '${EnhancedPdfUtils.formatNumber(roomRate)} ريال'),
              ],
            ),
          ),
        ],
      ),

      pw.SizedBox(height: 14),

      // ═════════════════════════════════════════════════════════
      //  جدول تفاصيل الفاتورة
      // ═════════════════════════════════════════════════════════
      _buildSectionTitle(fonts, 'تفاصيل الفاتورة'),
      pw.SizedBox(height: 6),
      _buildStyledTable(
        fonts,
        headers: ['البيان', 'الكمية', 'السعر', 'الإجمالي'],
        columnWidths: [3.0, 1.5, 1.5, 1.5],
        rows: [
          [
            'إقامة — غرفة $roomNumber',
            '$nights ليلة',
            '${EnhancedPdfUtils.formatNumber(roomRate)} ريال',
            '${EnhancedPdfUtils.formatNumber(totalAmount)} ريال',
          ],
        ],
      ),

      // ═════════════════════════════════════════════════════════
      //  جدول سجل المدفوعات المفصّل (يلتقط MultiPage الالتواء تلقائياً)
      // ═════════════════════════════════════════════════════════
      if (payments.isNotEmpty) ...[
        pw.SizedBox(height: 14),
        _buildSectionTitle(fonts, 'سجل المدفوعات المفصّل (${payments.length} ${payments.length == 1 ? "دفعة" : "دفعة"})'),
        pw.SizedBox(height: 6),
        _buildPaymentsTable(fonts),
      ],

      pw.SizedBox(height: 14),

      // ═════════════════════════════════════════════════════════
      //  ملخص مالي أنيق
      // ═════════════════════════════════════════════════════════
      _buildFinancialSummary(fonts, paidAmount),

      pw.SizedBox(height: 14),

      // ═════════════════════════════════════════════════════════
      //  التذييل
      // ═════════════════════════════════════════════════════════
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        decoration: pw.BoxDecoration(
          color: _cLight,
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: _cBorder),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'شكراً لاختياركم فندق مارينا بلازا',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 11, color: _cPrimary),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'نتطلع لخدمتكم مرة أخرى',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 9, color: _cTextLight),
                ),
              ],
            ),
            pw.Text(
              'تاريخ الإصدار: ${_formatDate(generatedAt)}',
              style: pw.TextStyle(font: fonts.regular, fontSize: 9, color: _cTextLight),
            ),
          ],
        ),
      ),
    ];
  }

  /// ════════════════════════════════════════════════════════════════════
  ///  رأس صفحة PDF — يظهر في أعلى كل صفحة (يتكرر عبر MultiPage)
  ///  يعرض: شعار الفندق + الاسم + رقم الكشف وتاريخه
  /// ════════════════════════════════════════════════════════════════════
  pw.Widget _buildPageHeader(ArabicPdfFonts fonts, pw.ImageProvider? logo, pw.Context context) {
    // في الصفحة الأولى فقط نعرض الرأس الكبير؛ في الصفحات التالية نعرض رأساً مختصراً
    if (context.pageNumber > 1) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 10),
        padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: pw.BoxDecoration(
          color: _cPrimary,
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Row(
              children: [
                pw.Text(
                  'فندق مارينا بلازا',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 11, color: const PdfColor(1, 1, 1)),
                ),
                pw.SizedBox(width: 8),
                pw.Text(
                  '— كشف حساب (متابعة)',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 9, color: const PdfColor(0.8, 0.88, 0.95)),
                ),
              ],
            ),
            pw.Text(
              'رقم: $invoiceNumber',
              style: pw.TextStyle(font: fonts.regular, fontSize: 9, color: const PdfColor(0.8, 0.88, 0.95)),
            ),
          ],
        ),
      );
    }

    // الرأس الكامل في الصفحة الأولى
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 14),
      decoration: pw.BoxDecoration(color: _cPrimary, borderRadius: pw.BorderRadius.circular(12)),
      child: pw.Padding(
        padding: const pw.EdgeInsets.all(20),
        child: pw.Row(
          children: [
            // الشعار
            pw.Container(
              width: 52,
              height: 52,
              decoration: pw.BoxDecoration(color: const PdfColor(1, 1, 1), borderRadius: pw.BorderRadius.circular(26)),
              child: logo != null
                  ? pw.Center(child: pw.Image(logo, width: 42, height: 42))
                  : pw.Center(
                      child: pw.Text(
                        'M',
                        style: pw.TextStyle(font: fonts.bold, fontSize: 24, color: _cPrimary),
                      ),
                    ),
            ),
            pw.SizedBox(width: 14),
            // اسم الفندق
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'فندق مارينا بلازا',
                    style: pw.TextStyle(font: fonts.bold, fontSize: 20, color: const PdfColor(1, 1, 1)),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'MARINA PLAZA HOTEL',
                    style: pw.TextStyle(
                      font: fonts.regular,
                      fontSize: 9,
                      color: const PdfColor(0.7, 0.82, 0.95),
                    ),
                  ),
                  pw.Text(
                    'عدن - اليمن',
                    style: pw.TextStyle(
                      font: fonts.regular,
                      fontSize: 9,
                      color: const PdfColor(0.75, 0.85, 0.95),
                    ),
                  ),
                ],
              ),
            ),
            // رقم وتاريخ الفاتورة
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 14),
                  decoration: pw.BoxDecoration(color: _cGold, borderRadius: pw.BorderRadius.circular(6)),
                  child: pw.Text(
                    'كشف حساب',
                    style: pw.TextStyle(font: fonts.bold, fontSize: 13, color: const PdfColor(1, 1, 1)),
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'رقم: $invoiceNumber',
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 10,
                    color: const PdfColor(0.75, 0.85, 0.95),
                  ),
                ),
                pw.Text(
                  _formatDate(generatedAt),
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 9,
                    color: const PdfColor(0.65, 0.78, 0.92),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// ════════════════════════════════════════════════════════════════════
  ///  تذييل صفحة PDF — يظهر في أسفل كل صفحة
  ///  يعرض: شكر + رقم الصفحة (مثال: 1/3)
  /// ════════════════════════════════════════════════════════════════════
  pw.Widget _buildPageFooter(ArabicPdfFonts fonts, pw.Context context) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 14),
      decoration: pw.BoxDecoration(
        color: _cLight,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: _cBorder, width: 0.5),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'مارينا هوتل | 9677734587456',
            style: pw.TextStyle(font: fonts.regular, fontSize: 9, color: _cTextLight),
          ),
          pw.Text(
            'صفحة ${context.pageNumber} من ${context.pagesCount}',
            style: pw.TextStyle(font: fonts.bold, fontSize: 9, color: _cPrimary),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  مكونات مساعدة للتصميم الأنيق
  // ═══════════════════════════════════════════════════════════════

  /// بطاقة معلومات بإطار وألوان احترافية
  pw.Widget _buildInfoCard(
    ArabicPdfFonts fonts, {
    required String title,
    required PdfColor titleColor,
    required List<(String, String)> rows,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: const PdfColor(1, 1, 1),
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _cBorder),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 10),
            decoration: pw.BoxDecoration(color: titleColor, borderRadius: pw.BorderRadius.circular(4)),
            child: pw.Text(
              title,
              style: pw.TextStyle(font: fonts.bold, fontSize: 11, color: const PdfColor(1, 1, 1)),
            ),
          ),
          pw.SizedBox(height: 8),
          ...rows.asMap().entries.map(
            (entry) => pw.Padding(
              padding: pw.EdgeInsets.only(bottom: entry.key == rows.length - 1 ? 0 : 5),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    entry.value.$1,
                    style: pw.TextStyle(font: fonts.regular, fontSize: 10, color: _cTextLight),
                  ),
                  pw.Text(
                    entry.value.$2,
                    style: pw.TextStyle(font: fonts.bold, fontSize: 10, color: _cTextDark),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// عنوان قسم بخط أنيق وخط فاصل
  pw.Widget _buildSectionTitle(ArabicPdfFonts fonts, String title) {
    return pw.Row(
      children: [
        pw.Container(
          width: 4,
          height: 16,
          decoration: pw.BoxDecoration(color: _cAccent, borderRadius: pw.BorderRadius.circular(2)),
        ),
        pw.SizedBox(width: 8),
        pw.Text(
          title,
          style: pw.TextStyle(font: fonts.bold, fontSize: 13, color: _cPrimary),
        ),
      ],
    );
  }

  /// جدول منسّق باحترافية
  pw.Widget _buildStyledTable(
    ArabicPdfFonts fonts, {
    required List<String> headers,
    required List<double> columnWidths,
    required List<List<String>> rows,
  }) {
    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _cBorder),
      ),
      child: pw.Table(
        border: pw.TableBorder.all(color: _cBorder, width: 0.5),
        columnWidths: {for (int i = 0; i < columnWidths.length; i++) i: pw.FlexColumnWidth(columnWidths[i])},
        children: [
          // رأس
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _cPrimary),
            children: headers
                .map(
                  (h) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    child: pw.Text(
                      h,
                      style: pw.TextStyle(font: fonts.bold, fontSize: 10, color: const PdfColor(1, 1, 1)),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                )
                .toList(),
          ),
          // صفوف
          ...rows.map(
            (row) => pw.TableRow(
              children: row
                  .map(
                    (cell) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                      child: pw.Text(
                        cell,
                        style: pw.TextStyle(font: fonts.regular, fontSize: 10, color: _cTextDark),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// ════════════════════════════════════════════════════════════════════
  ///  جدول المدفوعات المفصّل — يعرض لكل دفعة:
  ///   - التسلسل
  ///   - التاريخ الكامل + الوقت (yyyy/MM/dd HH:mm)
  ///   - طريقة الدفع + المرجع (آخر 4 أرقام بطاقة / اسم بنك / رقم شيك / رقم تحويل)
  ///   - المبلغ
  ///   - الحالة
  ///  كما يُراعي ترتيب الدفعات زمنياً تصاعدياً (الأقدم أولاً)
  /// ════════════════════════════════════════════════════════════════════
  pw.Widget _buildPaymentsTable(ArabicPdfFonts fonts) {
    // ترتيب الدفعات حسب التاريخ تصاعدياً (الأقدم أولاً)
    final sortedPayments = List<Payment>.from(payments)
      ..sort((a, b) => a.paymentDate.compareTo(b.paymentDate));

    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _cBorder),
      ),
      child: pw.Table(
        border: pw.TableBorder.all(color: _cBorder, width: 0.5),
        columnWidths: const {
          0: pw.FlexColumnWidth(0.6),  // #
          1: pw.FlexColumnWidth(2.4),  // التاريخ (كامل + وقت)
          2: pw.FlexColumnWidth(2.2),  // طريقة الدفع
          3: pw.FlexColumnWidth(2.0),  // المرجع
          4: pw.FlexColumnWidth(1.8),  // المبلغ
          5: pw.FlexColumnWidth(1.4),  // الحالة
        },
        children: [
          // ═══════════════════════════════════════════════════════════════
          //  رأس الجدول
          // ═══════════════════════════════════════════════════════════════
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _cAccent),
            children: [
              _tableCell(fonts, '#', bold: true, color: const PdfColor(1, 1, 1), center: true),
              _tableCell(fonts, 'التاريخ', bold: true, color: const PdfColor(1, 1, 1), center: true),
              _tableCell(fonts, 'طريقة الدفع', bold: true, color: const PdfColor(1, 1, 1), center: true),
              _tableCell(fonts, 'المرجع', bold: true, color: const PdfColor(1, 1, 1), center: true),
              _tableCell(fonts, 'المبلغ', bold: true, color: const PdfColor(1, 1, 1), center: true),
              _tableCell(fonts, 'الحالة', bold: true, color: const PdfColor(1, 1, 1), center: true),
            ],
          ),
          // ═══════════════════════════════════════════════════════════════
          //  صفوف الدفعات المفصّلة
          // ═══════════════════════════════════════════════════════════════
          ...sortedPayments.asMap().entries.map((entry) {
            final i = entry.key + 1;
            final p = entry.value;
            final statusAr = p.status == PaymentStatus.completed
                ? 'مكتمل'
                : p.status == PaymentStatus.pending
                ? 'معلّق'
                : p.status == PaymentStatus.refunded
                ? 'مُسترجع'
                : 'ملغي';
            final statusColor = p.status == PaymentStatus.completed
                ? _cGreen
                : p.status == PaymentStatus.pending
                ? _cGold
                : _cRed;
            final rowColor = entry.key.isEven ? const PdfColor(1, 1, 1) : _cLight;

            // ════════════════════════════════════════════════════════════
            //  بناء نص المرجع: يعتمد على طريقة الدفع
            // ════════════════════════════════════════════════════════════
            String refText;
            if (p.referenceNumber != null && p.referenceNumber!.isNotEmpty) {
              refText = p.referenceNumber!;
            } else if (p.method == PaymentMethod.card && p.cardLastFourDigits != null && p.cardLastFourDigits!.isNotEmpty) {
              refText = '**** ${p.cardLastFourDigits}';
            } else if (p.method == PaymentMethod.transfer && p.bankName != null && p.bankName!.isNotEmpty) {
              refText = p.bankName!;
            } else if (p.notes != null && p.notes!.isNotEmpty) {
              refText = p.notes!;
            } else {
              refText = '—';
            }
            // اقتطاع المرجع إن طال
            if (refText.length > 22) {
              refText = '${refText.substring(0, 21)}…';
            }

            // التاريخ الكامل + الوقت
            final dateStr = _formatDateTimeFull(p.paymentDate);

            return pw.TableRow(
              decoration: pw.BoxDecoration(color: rowColor),
              children: [
                _tableCell(fonts, '$i', center: true),
                _tableCell(fonts, dateStr, center: true),
                _tableCell(fonts, p.method.displayName),
                _tableCell(fonts, refText, center: true),
                _tableCell(fonts, '${EnhancedPdfUtils.formatNumber(p.amount)} ريال', bold: true, center: true),
                _tableCell(fonts, statusAr, color: statusColor, bold: true, center: true),
              ],
            );
          }),
          // ═══════════════════════════════════════════════════════════════
          //  صف الإجمالي المدفوع
          // ═══════════════════════════════════════════════════════════════
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColor(0.90, 0.93, 0.97)),
            children: [
              _tableCell(fonts, ''),
              _tableCell(fonts, ''),
              _tableCell(fonts, ''),
              _tableCell(fonts, 'الإجمالي المدفوع', bold: true),
              _tableCell(
                fonts,
                '${EnhancedPdfUtils.formatNumber(totalAmount - remainingAmount)} ريال',
                bold: true,
                center: true,
              ),
              _tableCell(fonts, ''),
            ],
          ),
        ],
      ),
    );
  }

  /// خلية جدول قابلة للتخصيص
  pw.Widget _tableCell(ArabicPdfFonts fonts, String text, {bool bold = false, PdfColor? color, bool center = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(font: bold ? fonts.bold : fonts.regular, fontSize: 9.5, color: color ?? _cTextDark),
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.start,
      ),
    );
  }

  /// ملخص مالي أنيق بصناديق ملوّنة
  pw.Widget _buildFinancialSummary(ArabicPdfFonts fonts, double paidAmount) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _cLight,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _cBorder),
      ),
      child: pw.Column(
        children: [
          // الإجمالي
          _summaryRow(fonts, 'إجمالي الفاتورة', '${EnhancedPdfUtils.formatNumber(totalAmount)} ريال', _cTextDark),
          pw.Divider(color: _cBorder, height: 14),
          // المدفوع
          _summaryRow(fonts, 'المدفوع', '${EnhancedPdfUtils.formatNumber(paidAmount)} ريال', _cGreen),
          pw.Divider(color: _cBorder, height: 14),
          // المتبقي
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: pw.BoxDecoration(
              color: remainingAmount > 0 ? const PdfColor(1.0, 0.93, 0.93) : const PdfColor(0.92, 0.98, 0.93),
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: remainingAmount > 0 ? _cRed : _cGreen, width: 0.5),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'المتبقي',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 12, color: remainingAmount > 0 ? _cRed : _cGreen),
                ),
                pw.Text(
                  '${EnhancedPdfUtils.formatNumber(remainingAmount)} ريال',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 14, color: remainingAmount > 0 ? _cRed : _cGreen),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// صف ملخص
  pw.Widget _summaryRow(ArabicPdfFonts fonts, String label, String value, PdfColor valueColor) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(font: fonts.regular, fontSize: 11, color: _cTextLight),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(font: fonts.bold, fontSize: 12, color: valueColor),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  /// تنسيق التاريخ الكامل مع الوقت — يستخدم في جدول المدفوعات المفصّل
  /// مثال: 2026/07/17 14:30
  String _formatDateTimeFull(DateTime date) {
    final y = date.year.toString();
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    final h = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    return '$y/$m/$d $h:$min';
  }
}
