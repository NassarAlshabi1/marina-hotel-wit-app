import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../utils/arabic_amount_formatter.dart';
import '../utils/enhanced_pdf_utils.dart';
import '../utils/pdf_utils.dart';

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
  });

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

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: json['id'],
      bookingId: json['bookingId'],
      amount: json['amount'],
      method: PaymentMethod.values.byName(json['method']),
      status: PaymentStatus.values.byName(json['status']),
      paymentDate: DateTime.parse(json['paymentDate']),
      notes: json['notes'],
      referenceNumber: json['referenceNumber'],
      cardLastFourDigits: json['cardLastFourDigits'],
      bankName: json['bankName'],
      receivedBy: json['receivedBy'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }
}

/// نموذج ملخص المدفوعات للحجز
class BookingPaymentSummary {
  final String bookingId;
  final double totalAmount;
  final double paidAmount;
  final double remainingAmount;
  final List<Payment> payments;
  final PaymentStatus overallStatus;

  BookingPaymentSummary({
    required this.bookingId,
    required this.totalAmount,
    required this.paidAmount,
    required this.remainingAmount,
    required this.payments,
    required this.overallStatus,
  });

  bool get isFullyPaid => remainingAmount <= 0;
  double get paidPercentage =>
      totalAmount > 0 ? (paidAmount / totalAmount) * 100 : 0;
}

/// نموذج الإيصال
class Receipt {
  final String receiptNumber;
  final Payment payment;
  final String guestName;
  final String guestPhone;
  final String roomNumber;
  final String hotelName;
  final String hotelAddress;
  final String hotelPhone;
  final DateTime generatedAt;

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
  });

  /// إنشاء PDF للإيصال
  Future<void> generatePDF() async {
    final fonts = await PdfUtils.loadArabicFonts();
    final logo = await PdfUtils.loadLogoImage();
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(16),
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: fonts.base, bold: fonts.bold),
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
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        // === رأس الإيصال ===
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: pw.BoxDecoration(
            color: PdfColors.primary,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // الشعار
              if (logo != null)
                pw.Container(
                  width: 48,
                  height: 48,
                  decoration: pw.BoxDecoration(
                    color: PdfColors.textWhite,
                    borderRadius: pw.BorderRadius.circular(24),
                  ),
                  child: pw.Center(child: pw.Image(logo, width: 40, height: 40)),
                )
              else
                pw.Container(
                  width: 48,
                  height: 48,
                  decoration: pw.BoxDecoration(
                    color: PdfColors.textWhite,
                    borderRadius: pw.BorderRadius.circular(24),
                  ),
                  child: pw.Center(
                    child: pw.Text(
                      'M',
                      style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 22,
                        color: PdfColors.primary,
                      ),
                    ),
                  ),
                ),
              // اسم الفندق
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      hotelName,
                      style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 16,
                        color: PdfColors.textWhite,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'MARINA PLAZA HOTEL',
                      style: pw.TextStyle(
                        font: fonts.base,
                        fontSize: 10,
                        color: PdfColor(0.7, 0.85, 1.0),
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      hotelAddress,
                      style: pw.TextStyle(
                        font: fonts.base,
                        fontSize: 9,
                        color: PdfColor(0.8, 0.9, 1.0),
                      ),
                    ),
                    pw.Text(
                      hotelPhone,
                      style: pw.TextStyle(
                        font: fonts.base,
                        fontSize: 9,
                        color: PdfColor(0.8, 0.9, 1.0),
                      ),
                    ),
                  ],
                ),
              ),
              // أيقونة إيصال
              pw.Container(
                width: 48,
                height: 48,
                decoration: pw.BoxDecoration(
                  color: PdfColors.secondary,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Center(
                  child: pw.Text(
                    '\$',
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 22,
                      color: PdfColors.textWhite,
                    ),
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
            border: pw.Border.all(color: PdfColor(0.9, 0.9, 0.9)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'إيصال استلام نقدي',
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 13,
                  color: PdfColors.primary,
                ),
              ),
              pw.Text(
                'رقم: $receiptNumber',
                style: pw.TextStyle(
                  font: fonts.base,
                  fontSize: 10,
                  color: PdfColors.textLight,
                ),
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
            border: pw.Border.all(color: PdfColor(0.88, 0.88, 0.88)),
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
              if (trimmedPhone.isNotEmpty) ...[
                _receiptDivider(),
                _receiptDetailRow(fonts, 'رقم الهاتف', trimmedPhone),
              ],
              if (trimmedRoom.isNotEmpty) ...[
                _receiptDivider(),
                _receiptDetailRow(fonts, 'رقم الغرفة', trimmedRoom),
              ],
              _receiptDivider(),
              _receiptDetailRow(fonts, 'مقابل', purpose),
              _receiptDivider(),
              _receiptDetailRow(fonts, 'طريقة الدفع', payment.method.displayName),
              if (payment.referenceNumber != null &&
                  payment.referenceNumber!.trim().isNotEmpty) ...[
                _receiptDivider(),
                _receiptDetailRow(
                  fonts,
                  'رقم المرجع',
                  payment.referenceNumber!.trim(),
                ),
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
            gradient: pw.LinearGradient(
              colors: [
                PdfColor(0.02, 0.33, 0.66),
                PdfColor(0.05, 0.45, 0.78),
              ],
              begin: pw.Alignment.centerRight,
              end: pw.Alignment.centerLeft,
            ),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                'المبلغ المدفوع',
                style: pw.TextStyle(
                  font: fonts.base,
                  fontSize: 11,
                  color: PdfColor(0.8, 0.9, 1.0),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                '$formattedAmount ريال يمني',
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 22,
                  color: PdfColors.textWhite,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                amountInWords,
                style: pw.TextStyle(
                  font: fonts.base,
                  fontSize: 9,
                  color: PdfColor(0.85, 0.92, 1.0),
                ),
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
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 11,
                      color: PdfColors.textDark,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    guestName,
                    style: pw.TextStyle(
                      font: fonts.base,
                      fontSize: 10,
                      color: PdfColors.textLight,
                    ),
                  ),
                  pw.SizedBox(height: 24),
                  pw.Container(
                    height: 1,
                    width: 120,
                    color: PdfColors.textLight,
                  ),
                ],
              ),
            ),
            // ختم الفندق
            pw.Expanded(
              child: pw.Column(
                children: [
                  pw.Text(
                    'ختم الفندق',
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 11,
                      color: PdfColors.textDark,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Container(
                    width: 64,
                    height: 64,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: PdfColors.primary,
                        width: 2,
                      ),
                      borderRadius: pw.BorderRadius.circular(32),
                    ),
                    child: pw.Center(
                      child: pw.Text(
                        'ختم',
                        style: pw.TextStyle(
                          font: fonts.base,
                          fontSize: 9,
                          color: PdfColors.textLight,
                        ),
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
          decoration: pw.BoxDecoration(
            color: PdfColors.backgroundLight,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Center(
            child: pw.Text(
              'شكراً لتعاملكم معنا - نتطلع لخدمتكم مرة أخرى',
              style: pw.TextStyle(
                font: fonts.base,
                fontSize: 9,
                color: PdfColors.textLight,
              ),
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
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 11,
                color: PdfColors.textDark,
              ),
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            flex: 3,
            child: pw.Text(
              value,
              style: pw.TextStyle(
                font: fonts.base,
                fontSize: 11,
                color: PdfColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _receiptDivider() {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Divider(
        color: PdfColor(0.92, 0.92, 0.92),
        thickness: 0.5,
      ),
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

  /// إنشاء PDF للفاتورة
  Future<void> generatePDF() async {
    final fonts = await PdfUtils.loadArabicFonts();
    final logo = await PdfUtils.loadLogoImage();
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: fonts.base, bold: fonts.bold),
        build: (context) => _buildInvoiceContent(fonts, logo),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  pw.Widget _buildInvoiceContent(ArabicPdfFonts fonts, pw.ImageProvider? logo) {
    final paidAmount = totalAmount - remainingAmount;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // === رأس الفاتورة ===
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(20),
          decoration: pw.BoxDecoration(
            color: PdfColors.primary,
            borderRadius: pw.BorderRadius.circular(10),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // الشعار
              if (logo != null)
                pw.Container(
                  width: 56,
                  height: 56,
                  decoration: pw.BoxDecoration(
                    color: PdfColors.textWhite,
                    borderRadius: pw.BorderRadius.circular(28),
                  ),
                  child: pw.Center(child: pw.Image(logo, width: 48, height: 48)),
                )
              else
                pw.Container(
                  width: 56,
                  height: 56,
                  decoration: pw.BoxDecoration(
                    color: PdfColors.textWhite,
                    borderRadius: pw.BorderRadius.circular(28),
                  ),
                  child: pw.Center(
                    child: pw.Text(
                      'M',
                      style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 26,
                        color: PdfColors.primary,
                      ),
                    ),
                  ),
                ),
              // اسم الفندق
              pw.Expanded(
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
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'MARINA PLAZA HOTEL',
                      style: pw.TextStyle(
                        font: fonts.base,
                        fontSize: 11,
                        color: PdfColor(0.7, 0.85, 1.0),
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'عدن - اليمن - شارع أحمد قاسم',
                      style: pw.TextStyle(
                        font: fonts.base,
                        fontSize: 10,
                        color: PdfColor(0.8, 0.9, 1.0),
                      ),
                    ),
                  ],
                ),
              ),
              // معلومات الفاتورة
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 12,
                    ),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.secondary,
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Text(
                      'فاتورة',
                      style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 16,
                        color: PdfColors.textWhite,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'رقم: $invoiceNumber',
                    style: pw.TextStyle(
                      font: fonts.base,
                      fontSize: 11,
                      color: PdfColor(0.8, 0.9, 1.0),
                    ),
                  ),
                  pw.Text(
                    _formatDate(generatedAt),
                    style: pw.TextStyle(
                      font: fonts.base,
                      fontSize: 10,
                      color: PdfColor(0.7, 0.85, 1.0),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        pw.SizedBox(height: 16),

        // === بطاقات معلومات العميل والإقامة ===
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // بيانات العميل
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: PdfColor(0.88, 0.88, 0.88)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 10,
                      ),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.primary,
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: pw.Text(
                        'بيانات العميل',
                        style: pw.TextStyle(
                          font: fonts.bold,
                          fontSize: 12,
                          color: PdfColors.textWhite,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 10),
                    _invoiceInfoRow(fonts, 'الاسم', guestName),
                    pw.SizedBox(height: 6),
                    _invoiceInfoRow(fonts, 'الهاتف', guestPhone),
                    pw.SizedBox(height: 6),
                    _invoiceInfoRow(fonts, 'رقم الغرفة', roomNumber),
                  ],
                ),
              ),
            ),
            pw.SizedBox(width: 12),
            // تفاصيل الإقامة
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: PdfColor(0.88, 0.88, 0.88)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 10,
                      ),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.accent,
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: pw.Text(
                        'تفاصيل الإقامة',
                        style: pw.TextStyle(
                          font: fonts.bold,
                          fontSize: 12,
                          color: PdfColors.textWhite,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 10),
                    _invoiceInfoRow(
                      fonts,
                      'تاريخ الوصول',
                      _formatDate(checkinDate),
                    ),
                    pw.SizedBox(height: 6),
                    _invoiceInfoRow(
                      fonts,
                      'تاريخ المغادرة',
                      _formatDate(checkoutDate),
                    ),
                    pw.SizedBox(height: 6),
                    _invoiceInfoRow(fonts, 'عدد الليالي', '$nights'),
                    pw.SizedBox(height: 6),
                    _invoiceInfoRow(
                      fonts,
                      'سعر الليلة',
                      '${EnhancedPdfUtils.formatNumber(roomRate)} ريال',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        pw.SizedBox(height: 16),

        // === جدول تفاصيل الفاتورة ===
        pw.Container(
          width: double.infinity,
          decoration: pw.BoxDecoration(
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(color: PdfColor(0.88, 0.88, 0.88)),
          ),
          child: pw.ClipRRect(
            borderRadius: pw.BorderRadius.circular(8),
            child: pw.Table(
              border: pw.TableBorder(
                horizontalInside: pw.BorderSide(color: PdfColor(0.92, 0.92, 0.92)),
                verticalInside: pw.BorderSide(color: PdfColor(0.92, 0.92, 0.92)),
              ),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(2),
                3: const pw.FlexColumnWidth(2),
              },
              children: [
                // رأس الجدول
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: PdfColors.primary),
                  children: [
                    _invoiceHeaderCell(fonts, 'البيان'),
                    _invoiceHeaderCell(fonts, 'الكمية'),
                    _invoiceHeaderCell(fonts, 'السعر'),
                    _invoiceHeaderCell(fonts, 'الإجمالي'),
                  ],
                ),
                // بيانات الإقامة
                pw.TableRow(
                  children: [
                    _invoiceDataCell(fonts, 'إقامة - غرفة $roomNumber'),
                    _invoiceDataCell(fonts, '$nights ليلة'),
                    _invoiceDataCell(
                      fonts,
                      '${EnhancedPdfUtils.formatNumber(roomRate)} ريال',
                    ),
                    _invoiceDataCell(
                      fonts,
                      '${EnhancedPdfUtils.formatNumber(totalAmount)} ريال',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // === سجل المدفوعات ===
        if (payments.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          pw.Text(
            'سجل المدفوعات',
            style: pw.TextStyle(
              font: fonts.bold,
              fontSize: 14,
              color: PdfColors.textDark,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            width: double.infinity,
            decoration: pw.BoxDecoration(
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: PdfColor(0.88, 0.88, 0.88)),
            ),
            child: pw.ClipRRect(
              borderRadius: pw.BorderRadius.circular(8),
              child: pw.Table(
                border: pw.TableBorder(
                  horizontalInside:
                      pw.BorderSide(color: PdfColor(0.92, 0.92, 0.92)),
                  verticalInside:
                      pw.BorderSide(color: PdfColor(0.92, 0.92, 0.92)),
                ),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(3),
                  2: const pw.FlexColumnWidth(3),
                },
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColors.accent),
                    children: [
                      _invoiceHeaderCell(fonts, 'التاريخ'),
                      _invoiceHeaderCell(fonts, 'طريقة الدفع'),
                      _invoiceHeaderCell(fonts, 'المبلغ'),
                    ],
                  ),
                  ...payments.map(
                    (payment) => pw.TableRow(
                      children: [
                        _invoiceDataCell(
                          fonts,
                          _formatDate(payment.paymentDate),
                        ),
                        _invoiceDataCell(fonts, payment.method.displayName),
                        _invoiceDataCell(
                          fonts,
                          '${EnhancedPdfUtils.formatNumber(payment.amount)} ريال',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        pw.SizedBox(height: 16),

        // === ملخص المبالغ ===
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            borderRadius: pw.BorderRadius.circular(8),
            color: PdfColors.backgroundLight,
            border: pw.Border.all(color: PdfColor(0.88, 0.88, 0.88)),
          ),
          child: pw.Column(
            children: [
              _invoiceSummaryRow(
                fonts,
                'إجمالي الفاتورة',
                '${EnhancedPdfUtils.formatNumber(totalAmount)} ريال',
                isBold: false,
              ),
              pw.Divider(color: PdfColor(0.92, 0.92, 0.92)),
              _invoiceSummaryRow(
                fonts,
                'المدفوع',
                '${EnhancedPdfUtils.formatNumber(paidAmount)} ريال',
                isBold: false,
              ),
              pw.Divider(color: PdfColor(0.92, 0.92, 0.92)),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 6),
                decoration: pw.BoxDecoration(
                  color: remainingAmount > 0
                      ? PdfColor(1.0, 0.95, 0.95)
                      : PdfColor(0.95, 1.0, 0.95),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: _invoiceSummaryRow(
                  fonts,
                  'المتبقي',
                  '${EnhancedPdfUtils.formatNumber(remainingAmount)} ريال',
                  isBold: true,
                  valueColor: remainingAmount > 0
                      ? PdfColors.danger
                      : PdfColors.success,
                ),
              ),
            ],
          ),
        ),

        pw.Spacer(flex: 1),

        pw.SizedBox(height: 20),

        // === تذييل ===
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'شكراً لاختياركم فندق مارينا بلازا',
                  style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: 12,
                    color: PdfColors.primary,
                  ),
                ),
                pw.Text(
                  'نتطلع لخدمتكم مرة أخرى',
                  style: pw.TextStyle(
                    font: fonts.base,
                    fontSize: 10,
                    color: PdfColors.textLight,
                  ),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'تاريخ الإصدار: ${_formatDate(generatedAt)}',
                  style: pw.TextStyle(
                    font: fonts.base,
                    fontSize: 10,
                    color: PdfColors.textLight,
                  ),
                ),
                pw.SizedBox(height: 20),
                pw.Container(
                  height: 1,
                  width: 120,
                  color: PdfColors.textLight,
                ),
                pw.Text(
                  'ختم وتوقيع الفندق',
                  style: pw.TextStyle(
                    font: fonts.base,
                    fontSize: 9,
                    color: PdfColors.textLight,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _invoiceHeaderCell(ArabicPdfFonts fonts, String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: fonts.bold,
          fontSize: 11,
          color: PdfColors.textWhite,
        ),
      ),
    );
  }

  pw.Widget _invoiceDataCell(ArabicPdfFonts fonts, String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: fonts.base,
          fontSize: 10,
          color: PdfColors.textDark,
        ),
      ),
    );
  }

  pw.Widget _invoiceInfoRow(
    ArabicPdfFonts fonts,
    String label,
    String value,
  ) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 2,
          child: pw.Text(
            label,
            style: pw.TextStyle(
              font: fonts.bold,
              fontSize: 10,
              color: PdfColors.textLight,
            ),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          flex: 3,
          child: pw.Text(
            value,
            style: pw.TextStyle(
              font: fonts.base,
              fontSize: 11,
              color: PdfColors.textDark,
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _invoiceSummaryRow(
    ArabicPdfFonts fonts,
    String label,
    String value, {
    bool isBold = false,
    PdfColor? valueColor,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            font: isBold ? fonts.bold : fonts.base,
            fontSize: isBold ? 15 : 13,
            color: PdfColors.textDark,
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            font: isBold ? fonts.bold : fonts.base,
            fontSize: isBold ? 16 : 13,
            color: valueColor ?? PdfColors.textDark,
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
