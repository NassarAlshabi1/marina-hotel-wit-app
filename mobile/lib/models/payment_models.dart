import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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
  double get paidPercentage => totalAmount > 0 ? (paidAmount / totalAmount) * 100 : 0;
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
    this.hotelAddress = 'اليمن - صنعاء',
    this.hotelPhone = '+967-1-234567',
    required this.generatedAt,
  });

  /// إنشاء PDF للإيصال
  Future<void> generatePDF() async {
    final pdf = pw.Document();
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        textDirection: pw.TextDirection.rtl,
        build: (context) => _buildReceiptContent(),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  pw.Widget _buildReceiptContent() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // رأس الإيصال
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(16),
          color: PdfColors.blue,
          child: pw.Column(
            children: [
              pw.Text(
                hotelName,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                hotelAddress,
                style: const pw.TextStyle(
                  fontSize: 12,
                  color: PdfColors.white,
                ),
              ),
            ],
          ),
        ),
        
        pw.SizedBox(height: 20),
        
        // معلومات الإيصال
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('رقم الإيصال: $receiptNumber'),
            pw.Text('التاريخ: ${_formatDate(generatedAt)}'),
          ],
        ),
        
        pw.SizedBox(height: 16),
        
        // معلومات العميل
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('بيانات العميل:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Text('الاسم: $guestName'),
              pw.Text('الهاتف: $guestPhone'),
              pw.Text('رقم الغرفة: $roomNumber'),
            ],
          ),
        ),
        
        pw.SizedBox(height: 16),
        
        // تفاصيل الدفعة
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('تفاصيل الدفعة:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('المبلغ:'),
                  pw.Text('${payment.amount.toStringAsFixed(2)} ر.س'),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('طريقة الدفع:'),
                  pw.Text(payment.method.displayName),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('تاريخ الدفع:'),
                  pw.Text(_formatDate(payment.paymentDate)),
                ],
              ),
              if (payment.referenceNumber != null)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('رقم المرجع:'),
                    pw.Text(payment.referenceNumber!),
                  ],
                ),
              if (payment.notes != null && payment.notes!.isNotEmpty)
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.SizedBox(height: 8),
                    pw.Text('ملاحظات:'),
                    pw.Text(payment.notes!),
                  ],
                ),
            ],
          ),
        ),
        
        pw.Spacer(),
        
        // التوقيع والختم
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              children: [
                pw.Text('المحاسب: ${payment.receivedBy}'),
                pw.SizedBox(height: 20),
                pw.Container(
                  height: 1,
                  width: 100,
                  color: PdfColors.black,
                ),
                pw.Text('التوقيع'),
              ],
            ),
            pw.Column(
              children: [
                pw.Text('ختم الفندق'),
                pw.SizedBox(height: 30),
                pw.Container(
                  height: 40,
                  width: 40,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 2),
                    shape: pw.BoxShape.circle,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
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
    final pdf = pw.Document();
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (context) => _buildInvoiceContent(),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  pw.Widget _buildInvoiceContent() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // رأس الفاتورة
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(20),
          color: PdfColors.blue,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'فندق مارينا بلازا',
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                  pw.Text(
                    'اليمن - صنعاء',
                    style: const pw.TextStyle(
                      fontSize: 14,
                      color: PdfColors.white,
                    ),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'فاتورة',
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                  pw.Text(
                    'رقم: $invoiceNumber',
                    style: const pw.TextStyle(
                      fontSize: 14,
                      color: PdfColors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        pw.SizedBox(height: 30),
        
        // معلومات العميل والحجز
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('بيانات العميل', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
                    pw.SizedBox(height: 10),
                    pw.Text('الاسم: $guestName'),
                    pw.Text('الهاتف: $guestPhone'),
                    pw.Text('رقم الغرفة: $roomNumber'),
                  ],
                ),
              ),
            ),
            pw.SizedBox(width: 20),
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('تفاصيل الإقامة', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
                    pw.SizedBox(height: 10),
                    pw.Text('تاريخ الوصول: ${_formatDate(checkinDate)}'),
                    pw.Text('تاريخ المغادرة: ${_formatDate(checkoutDate)}'),
                    pw.Text('عدد الليالي: $nights'),
                    pw.Text('سعر الليلة: ${roomRate.toStringAsFixed(2)} ر.س'),
                  ],
                ),
              ),
            ),
          ],
        ),
        
        pw.SizedBox(height: 30),
        
        // تفاصيل الفاتورة
        pw.Container(
          width: double.infinity,
          child: pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            children: [
              // رأس الجدول
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('البيان', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('الكمية', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('السعر', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('الإجمالي', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                ],
              ),
              // بيانات الإقامة
              pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('إقامة - غرفة $roomNumber'),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('$nights ليلة'),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('${roomRate.toStringAsFixed(2)} ر.س'),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('${totalAmount.toStringAsFixed(2)} ر.س'),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        pw.SizedBox(height: 20),
        
        // ملخص المدفوعات
        if (payments.isNotEmpty) ...[
          pw.Text('سجل المدفوعات:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
          pw.SizedBox(height: 10),
          pw.Container(
            width: double.infinity,
            child: pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('التاريخ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('طريقة الدفع', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('المبلغ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),
                ...payments.map((payment) => pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(_formatDate(payment.paymentDate), style: const pw.TextStyle(fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(payment.method.displayName, style: const pw.TextStyle(fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('${payment.amount.toStringAsFixed(2)} ر.س', style: const pw.TextStyle(fontSize: 10)),
                    ),
                  ],
                )),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
        ],
        
        // الإجمالي النهائي
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            border: pw.Border.all(color: PdfColors.grey300),
          ),
          child: pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('إجمالي الفاتورة:', style: pw.TextStyle(fontSize: 14)),
                  pw.Text('${totalAmount.toStringAsFixed(2)} ر.س', style: pw.TextStyle(fontSize: 14)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('المدفوع:', style: pw.TextStyle(fontSize: 14)),
                  pw.Text('${(totalAmount - remainingAmount).toStringAsFixed(2)} ر.س', style: pw.TextStyle(fontSize: 14)),
                ],
              ),
              pw.Divider(color: PdfColors.grey300),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('المتبقي:', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  pw.Text('${remainingAmount.toStringAsFixed(2)} ر.س', 
                    style: pw.TextStyle(
                      fontSize: 16, 
                      fontWeight: pw.FontWeight.bold,
                      color: remainingAmount > 0 ? PdfColors.red : PdfColors.green,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        pw.Spacer(),
        
        // ملاحظة وتوقيع
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('شكراً لاختياركم فندق مارينا بلازا'),
                pw.Text('نتطلع لخدمتكم مرة أخرى'),
              ],
            ),
            pw.Column(
              children: [
                pw.Text('تاريخ الإصدار: ${_formatDate(generatedAt)}'),
                pw.SizedBox(height: 20),
                pw.Container(
                  height: 1,
                  width: 120,
                  color: PdfColors.black,
                ),
                pw.Text('ختم وتوقيع الفندق'),
              ],
            ),
          ],
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}