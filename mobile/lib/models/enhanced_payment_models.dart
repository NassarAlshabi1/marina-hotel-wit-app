import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart' hide PdfColors;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../utils/enhanced_pdf_utils.dart';
import '../utils/time.dart';
import '../services/local_db.dart';

/// نموذج إيصال دفع احترافي محسّن
class EnhancedPaymentReceipt {
  final String receiptNumber;
  final String guestName;
  final String guestPhone;
  final String roomNumber;
  final Payment payment;
  final String hotelName;
  final String hotelAddress;
  final String receivedBy;
  final DateTime issuedAt;
  final String? notes;

  EnhancedPaymentReceipt({
    required this.receiptNumber,
    required this.guestName,
    required this.guestPhone,
    required this.roomNumber,
    required this.payment,
    required this.hotelName,
    required this.hotelAddress,
    required this.receivedBy,
    required this.issuedAt,
    this.notes,
  });

  /// إنشاء PDF احترافي للإيصال
  Future<void> generatePDF() async {
    final fonts = await EnhancedPdfUtils.loadArabicFonts();
    final logo = await EnhancedPdfUtils.loadLogoImage();
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(
          base: fonts.regular,
          bold: fonts.bold,
        ),
        build: (context) => _buildReceiptContent(fonts, logo),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  pw.Widget _buildReceiptContent(ArabicPdfFonts fonts, pw.ImageProvider? logo) {
    return pw.Column(
      children: [
        // رأس الصفحة الاحترافي
        EnhancedPdfUtils.buildProfessionalHeader(
          fonts: fonts,
          logo: logo,
          title: 'إيصال دفع',
          subtitle: 'Receipt #$receiptNumber',
        ),

        pw.SizedBox(height: 30),

        // معلومات الإيصال الأساسية
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _buildReceiptInfo(fonts),
            _buildPaymentStatusBadge(fonts),
          ],
        ),

        pw.SizedBox(height: 20),

        // معلومات العميل
        EnhancedPdfUtils.buildInfoCard(
          title: '🏨 بيانات النزيل',
          fonts: fonts,
          borderColor: PdfColors.accent,
          content: [
            _buildInfoRow('الاسم الكامل:', guestName, fonts),
            pw.SizedBox(height: 8),
            _buildInfoRow('رقم الهاتف:', guestPhone, fonts),
            pw.SizedBox(height: 8),
            _buildInfoRow('رقم الغرفة:', roomNumber, fonts),
          ],
        ),

        // تفاصيل الدفعة
        EnhancedPdfUtils.buildInfoCard(
          title: '💰 تفاصيل الدفعة',
          fonts: fonts,
          borderColor: PdfColors.secondary,
          content: [
            _buildPaymentDetails(fonts),
          ],
        ),

        // ملاحظات (إذا وجدت)
        if (notes != null && notes!.isNotEmpty) ...[
          EnhancedPdfUtils.buildInfoCard(
            title: '📝 ملاحظات إضافية',
            fonts: fonts,
            borderColor: PdfColors.info,
            content: [
              pw.Text(
                notes!,
                style: PdfTextStyles.body(fonts.regular),
              ),
            ],
          ),
        ],

        // إحصائيات وتفاصيل الدفع
        pw.Row(
          children: [
            pw.Expanded(
              child: EnhancedPdfUtils.buildStatisticsBox(
                title: 'المبلغ المدفوع',
                value: EnhancedPdfUtils.formatCurrency(payment.amount),
                // subtitle: '',
                fonts: fonts,
                color: PdfColors.success,
                icon: '💵',
              ),
            ),
            pw.SizedBox(width: 16),
            pw.Expanded(
              child: EnhancedPdfUtils.buildStatisticsBox(
                title: 'طريقة الدفع',
                value: _getPaymentMethodName(),
                subtitle: 'Payment Method',
                fonts: fonts,
                color: PdfColors.info,
                icon: '💳',
              ),
            ),
          ],
        ),

        pw.SizedBox(height: 20),

        // التوقيع والختم
        _buildSignatureSection(fonts),

        pw.Spacer(),

        // تذييل الصفحة مع معلومات الاتصال
        EnhancedPdfUtils.buildContactFooter(fonts: fonts),
      ],
    );
  }

  pw.Widget _buildReceiptInfo(ArabicPdfFonts fonts) {
    final paymentDate = DateTime.tryParse(payment.paymentDate) ?? DateTime.now();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'رقم الإيصال: $receiptNumber',
          style: PdfTextStyles.heading3(fonts.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'تاريخ الإصدار: ${EnhancedPdfUtils.formatDateTime(issuedAt)}',
          style: PdfTextStyles.bodySmall(fonts.regular),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'تاريخ الدفع: ${EnhancedPdfUtils.formatDateTime(paymentDate)}',
          style: PdfTextStyles.bodySmall(fonts.regular),
        ),
      ],
    );
  }

  pw.Widget _buildPaymentStatusBadge(ArabicPdfFonts fonts) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.success,
        borderRadius: pw.BorderRadius.circular(20),
      ),
      child: pw.Text(
        '✅ مدفوع',
        style: pw.TextStyle(
          font: fonts.bold,
          fontSize: 12,
          color: PdfColors.textWhite,
        ),
      ),
    );
  }

  pw.Widget _buildInfoRow(String label, String value, ArabicPdfFonts fonts) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: PdfTextStyles.bodyBold(fonts.bold),
        ),
        pw.Text(
          value,
          style: PdfTextStyles.body(fonts.regular),
        ),
      ],
    );
  }

  pw.Widget _buildPaymentDetails(ArabicPdfFonts fonts) {
    return pw.Column(
      children: [
        _buildInfoRow('المبلغ الأساسي:', EnhancedPdfUtils.formatCurrency(payment.amount), fonts),
        
        pw.SizedBox(height: 12),
        pw.Divider(color: PdfColors.textLight),
        pw.SizedBox(height: 12),
        
        // إجمالي المبلغ مع تمييز بصري
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: PdfColors.secondary,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'إجمالي المبلغ:',
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 14,
                  color: PdfColors.textWhite,
                ),
              ),
              pw.Text(
                EnhancedPdfUtils.formatCurrency(payment.amount),
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 16,
                  color: PdfColors.textWhite,
                ),
              ),
            ],
          ),
        ),
        
        pw.SizedBox(height: 12),
        
        _buildInfoRow('طريقة الدفع:', _getPaymentMethodName(), fonts),
        pw.SizedBox(height: 8),
        
      ],
    );
  }

  pw.Widget _buildSignatureSection(ArabicPdfFonts fonts) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.textLight),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          // توقيع المحاسب
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'المحاسب:',
                style: PdfTextStyles.bodySmall(fonts.regular),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                receivedBy,
                style: PdfTextStyles.bodyBold(fonts.bold),
              ),
              pw.SizedBox(height: 16),
              pw.Container(
                width: 120,
                height: 1,
                color: PdfColors.textLight,
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'التوقيع',
                style: PdfTextStyles.caption(fonts.regular),
              ),
            ],
          ),
          
          // QR Code للتحقق
          pw.Column(
            children: [
              EnhancedPdfUtils.buildQRCodePlaceholder(
                data: 'receipt:$receiptNumber',
                fonts: fonts,
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'كود التحقق',
                style: PdfTextStyles.caption(fonts.regular),
              ),
            ],
          ),
          
          // ختم الفندق
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'ختم الفندق:',
                style: PdfTextStyles.bodySmall(fonts.regular),
              ),
              pw.SizedBox(height: 20),
              pw.Container(
                width: 60,
                height: 60,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.primary, width: 2),
                  shape: pw.BoxShape.circle,
                ),
                child: pw.Center(
                  child: pw.Text(
                    'ختم',
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 10,
                      color: PdfColors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getPaymentMethodName() {
    switch (payment.paymentMethod) {
      case 'cash':
        return 'نقداً';
      case 'card':
        return 'بطاقة ائتمانية';
      case 'transfer':
        return 'تحويل بنكي';
      case 'check':
        return 'شيك';
      default:
        return payment.paymentMethod;
    }
  }
}

/// نموذج فاتورة محسّنة
class EnhancedInvoice {
  final String invoiceNumber;
  final String guestName;
  final String guestPhone;
  final String roomNumber;
  final List<InvoiceItem> items;
  final List<Payment> payments;
  final String hotelName;
  final String hotelAddress;
  final DateTime checkIn;
  final DateTime checkOut;
  final DateTime issuedAt;
  final String? notes;

  EnhancedInvoice({
    required this.invoiceNumber,
    required this.guestName,
    required this.guestPhone,
    required this.roomNumber,
    required this.items,
    required this.payments,
    required this.hotelName,
    required this.hotelAddress,
    required this.checkIn,
    required this.checkOut,
    required this.issuedAt,
    this.notes,
  });

  double get totalAmount => items.fold(0, (sum, item) => sum + item.total);
  double get totalPaid => payments.fold(0, (sum, payment) => sum + payment.amount);
  double get remainingBalance => totalAmount - totalPaid;

  /// إنشاء PDF احترافي للفاتورة
  Future<void> generatePDF() async {
    final fonts = await EnhancedPdfUtils.loadArabicFonts();
    final logo = await EnhancedPdfUtils.loadLogoImage();
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(
          base: fonts.regular,
          bold: fonts.bold,
        ),
        header: (context) => _buildInvoiceHeader(fonts, logo),
        footer: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'صفحة ${context.pageNumber} من ${context.pagesCount}',
            style: PdfTextStyles.caption(fonts.regular),
            textAlign: pw.TextAlign.center,
          ),
        ),
        build: (context) => _buildInvoiceContent(fonts),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  pw.Widget _buildInvoiceHeader(ArabicPdfFonts fonts, pw.ImageProvider? logo) {
    return pw.Column(
      children: [
        EnhancedPdfUtils.buildProfessionalHeader(
          fonts: fonts,
          logo: logo,
          title: 'فاتورة ضريبية',
          subtitle: 'Tax Invoice #$invoiceNumber',
        ),
        pw.SizedBox(height: 20),
      ],
    );
  }

  List<pw.Widget> _buildInvoiceContent(ArabicPdfFonts fonts) {
    return [
      // معلومات الفاتورة والعميل
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: _buildCustomerInfo(fonts),
          ),
          pw.SizedBox(width: 20),
          pw.Expanded(
            child: _buildInvoiceInfo(fonts),
          ),
        ],
      ),

      pw.SizedBox(height: 20),

      // جدول العناصر
      _buildItemsTable(fonts),

      pw.SizedBox(height: 20),

      // ملخص المالي
      _buildFinancialSummary(fonts),

      pw.SizedBox(height: 20),

      // تاريخ المدفوعات
      if (payments.isNotEmpty) _buildPaymentHistory(fonts),

      pw.SizedBox(height: 20),

      // ملاحظات
      if (notes != null && notes!.isNotEmpty) _buildNotesSection(fonts),

      pw.SizedBox(height: 30),

      // تذييل مع الشروط والأحكام
      _buildTermsAndConditions(fonts),
    ];
  }

  pw.Widget _buildCustomerInfo(ArabicPdfFonts fonts) {
    return EnhancedPdfUtils.buildInfoCard(
      title: '👤 بيانات العميل',
      fonts: fonts,
      borderColor: PdfColors.accent,
      content: [
        _buildInfoRow('اسم العميل:', guestName, fonts),
        pw.SizedBox(height: 6),
        _buildInfoRow('رقم الهاتف:', guestPhone, fonts),
        pw.SizedBox(height: 6),
        _buildInfoRow('رقم الغرفة:', roomNumber, fonts),
        pw.SizedBox(height: 6),
        _buildInfoRow('تاريخ الوصول:', EnhancedPdfUtils.formatDateTime(checkIn), fonts),
        pw.SizedBox(height: 6),
        _buildInfoRow('تاريخ المغادرة:', EnhancedPdfUtils.formatDateTime(checkOut), fonts),
      ],
    );
  }

  pw.Widget _buildInvoiceInfo(ArabicPdfFonts fonts) {
    final duration = Time.nightsWithCutoff(checkIn, checkout: checkOut);
    
    return EnhancedPdfUtils.buildInfoCard(
      title: '📋 بيانات الفاتورة',
      fonts: fonts,
      borderColor: PdfColors.secondary,
      content: [
        _buildInfoRow('رقم الفاتورة:', invoiceNumber, fonts),
        pw.SizedBox(height: 6),
        _buildInfoRow('تاريخ الإصدار:', EnhancedPdfUtils.formatDateTime(issuedAt), fonts),
        pw.SizedBox(height: 6),
        _buildInfoRow('مدة الإقامة:', '$duration ${duration == 1 ? "يوم" : "أيام"}', fonts),
        pw.SizedBox(height: 6),
        _buildInfoRow('حالة الدفع:', remainingBalance == 0 ? 'مسددة بالكامل' : 'لم تسدد بالكامل', fonts),
      ],
    );
  }

  pw.Widget _buildItemsTable(ArabicPdfFonts fonts) {
    return EnhancedPdfUtils.buildProfessionalTable(
      headers: ['البند', 'الكمية', 'السعر', 'المجموع'],
      data: items.map((item) => [
        item.description,
        item.quantity.toString(),
        EnhancedPdfUtils.formatCurrency(item.unitPrice),
        EnhancedPdfUtils.formatCurrency(item.total),
      ]).toList(),
      fonts: fonts,
      columnWidths: [0.4, 0.15, 0.2, 0.25],
    );
  }

  pw.Widget _buildFinancialSummary(ArabicPdfFonts fonts) {
    return pw.Row(
      children: [
        pw.Expanded(child: pw.Container()),
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.primary),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              children: [
                _buildSummaryRow('المجموع الفرعي:', totalAmount, fonts),
                pw.Divider(color: PdfColors.textLight),
                _buildSummaryRow('ضريبة القيمة المضافة:', totalAmount * 0.15, fonts, isSmall: true),
                pw.Divider(color: PdfColors.textLight),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 8),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.primary,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'المجموع الكلي:',
                        style: pw.TextStyle(
                          font: fonts.bold,
                          fontSize: 14,
                          color: PdfColors.textWhite,
                        ),
                      ),
                      pw.Text(
                        EnhancedPdfUtils.formatCurrency(totalAmount * 1.15),
                        style: pw.TextStyle(
                          font: fonts.bold,
                          fontSize: 16,
                          color: PdfColors.textWhite,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 8),
                _buildSummaryRow('المدفوع:', totalPaid, fonts, color: PdfColors.success),
                _buildSummaryRow('المتبقي:', remainingBalance, fonts, 
                  color: remainingBalance > 0 ? PdfColors.danger : PdfColors.success),
              ],
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _buildSummaryRow(String label, double amount, ArabicPdfFonts fonts, {
    bool isSmall = false,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: isSmall ? 10 : 12,
              color: color ?? PdfColors.textDark,
            ),
          ),
          pw.Text(
            EnhancedPdfUtils.formatCurrency(amount),
            style: pw.TextStyle(
              font: fonts.bold,
              fontSize: isSmall ? 10 : 12,
              color: color ?? PdfColors.textDark,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPaymentHistory(ArabicPdfFonts fonts) {
    return EnhancedPdfUtils.buildInfoCard(
      title: '💰 تاريخ المدفوعات',
      fonts: fonts,
      borderColor: PdfColors.success,
      content: [
        EnhancedPdfUtils.buildProfessionalTable(
          headers: ['التاريخ', 'المبلغ', 'طريقة الدفع', 'المحاسب'],
          data: payments.map((payment) {
            final date = DateTime.tryParse(payment.paymentDate) ?? DateTime.now();
            return [
              EnhancedPdfUtils.formatDateTime(date),
              EnhancedPdfUtils.formatCurrency(payment.amount),
              _getPaymentMethodName(payment.paymentMethod),
              'غير متوفر',
            ];
          }).toList(),
          fonts: fonts,
          headerColor: PdfColors.success,
        ),
      ],
    );
  }

  pw.Widget _buildNotesSection(ArabicPdfFonts fonts) {
    return EnhancedPdfUtils.buildInfoCard(
      title: '📝 ملاحظات',
      fonts: fonts,
      borderColor: PdfColors.info,
      content: [
        pw.Text(
          notes!,
          style: PdfTextStyles.body(fonts.regular),
        ),
      ],
    );
  }

  pw.Widget _buildTermsAndConditions(ArabicPdfFonts fonts) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.backgroundCard,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'الشروط والأحكام:',
            style: PdfTextStyles.bodyBold(fonts.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            '• يجب سداد الفاتورة خلال 30 يوماً من تاريخ الإصدار\n• في حالة التأخير في السداد، يُطبق غرامة 2% شهرياً\n• جميع الأسعار تشمل ضريبة القيمة المضافة\n• للاستفسارات يرجى الاتصال بالمحاسبة',
            style: PdfTextStyles.bodySmall(fonts.regular),
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
        pw.Text(value, style: PdfTextStyles.body(fonts.regular)),
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

/// عنصر في الفاتورة
class InvoiceItem {
  final String description;
  final int quantity;
  final double unitPrice;

  InvoiceItem({
    required this.description,
    required this.quantity,
    required this.unitPrice,
  });

  double get total => quantity * unitPrice;
}