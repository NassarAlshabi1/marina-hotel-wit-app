import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' hide PdfColors;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/enhanced_payment_models.dart';
import '../models/enhanced_reports.dart';
import '../services/local_db.dart';
import 'enhanced_pdf_utils.dart';

DateTime _safeParseDateTime(String? dateStr, {DateTime? fallback}) {
  if (dateStr == null || dateStr.trim().isEmpty) {
    return fallback ?? DateTime.now();
  }
  final normalized = dateStr.contains('T')
      ? dateStr
      : dateStr.replaceFirst(' ', 'T');
  try {
    return DateTime.parse(normalized);
  } catch (_) {
    return fallback ?? DateTime.now();
  }
}

/// مساعد لإنشاء PDF محسّنة من البيانات الموجودة
class EnhancedPdfHelper {
  /// إنشاء إيصال دفع محسّن من Payment موجود
  static Future<void> generateEnhancedReceipt({
    required Payment payment,
    required Booking booking,
    required String receivedBy,
  }) async {
    final receipt = EnhancedPaymentReceipt(
      receiptNumber: 'REC-${DateTime.now().millisecondsSinceEpoch}',
      guestName: booking.guestName,
      guestPhone: booking.guestPhone,
      roomNumber: booking.roomNumber,
      payment: payment,
      hotelName: 'فندق مارينا بلازا',
      hotelAddress: 'القاهرة - شارع احمد قاسم',
      receivedBy: receivedBy,
      issuedAt: DateTime.now(),
      notes: payment.notes,
    );

    await receipt.generatePDF();
  }

  /// إنشاء فاتورة محسّنة من Booking مع المدفوعات
  static Future<void> generateEnhancedInvoice({
    required Booking booking,
    required List<Payment> payments,
    required double roomPrice,
    int? extraNights,
    List<InvoiceItem>? additionalServices,
  }) async {
    // حساب عناصر الفاتورة
    final nights = booking.calculatedNights;
    final baseItems = [
      InvoiceItem(
        description:
            'إقامة $nights ${nights == 1 ? "ليلة" : "ليالي"} - غرفة ${booking.roomNumber}',
        quantity: nights,
        unitPrice: roomPrice,
      ),
    ];

    // إضافة خدمات إضافية
    if (additionalServices != null) {
      baseItems.addAll(additionalServices);
    }

    final invoice = EnhancedInvoice(
      invoiceNumber:
          'INV-${booking.id}-${DateTime.now().millisecondsSinceEpoch}',
      guestName: booking.guestName,
      guestPhone: booking.guestPhone,
      roomNumber: booking.roomNumber,
      items: baseItems,
      payments: payments,
      hotelName: 'فندق مارينا بلازا',
      hotelAddress: 'القاهرة - شارع احمد قاسم',
      checkIn: _safeParseDateTime(booking.checkinDate),
      checkOut: booking.checkoutDate != null && booking.checkoutDate!.isNotEmpty
          ? _safeParseDateTime(booking.checkoutDate)
          : _safeParseDateTime(booking.checkinDate).add(Duration(days: nights)),
      issuedAt: DateTime.now(),
      notes: booking.notes,
      discount: booking.discount,
    );

    await invoice.generatePDF();
  }

  /// إنشاء تقرير مدفوعات محسّن
  static Future<void> generateEnhancedPaymentsReport({
    required List<Payment> payments,
    required List<Booking> relatedBookings,
    required DateTime fromDate,
    required DateTime toDate,
    String? roomFilter,
    required String generatedBy,
  }) async {
    // تحويل البيانات لتقرير
    final reportItems = payments.map((payment) {
      final booking = relatedBookings.firstWhere(
        (b) => b.id == payment.bookingLocalId,
        orElse: () {
          final now = DateTime.now();
          final nowMillis = now.millisecondsSinceEpoch;
          final nowIso = now.toIso8601String();
          return Booking(
            localUuid: 'fallback-${payment.id}',
            serverId: null,
            createdAt: nowMillis,
            updatedAt: nowMillis,
            deletedAt: null,
            lastModified: nowMillis,
            createdAtIso: nowIso,
            updatedAtIso: nowIso,
            deletedAtIso: null,
            createdAtEpoch: nowMillis,
            lastModifiedEpoch: nowMillis,
            version: 1,
            origin: 'local',
            id: -1,
            serverBookingId: null,
            roomNumber: 'غير محدد',
            guestName: 'غير محدد',
            guestPhone: '',
            guestIdType: 'غير محدد',
            guestIdNumber: '',
            guestIdIssueDate: null,
            guestIdIssuePlace: null,
            guestNationality: '',
            guestEmail: null,
            guestAddress: null,
            checkinDate: '',
            checkoutDate: '',
            actualCheckout: null,
            status: '',
            notes: null,
            expectedNights: 1,
            calculatedNights: 1,
            totalNightsCached: 0,
            stayDurationIso: null,
            lastNightEpoch: null,
            isOverdue: false,
            needsCheckoutReview: false,
            totalDueCached: 0,
            totalPaidCached: 0,
            remainingBalanceCached: 0,
            isFullyPaid: false,
            discount: 0,
            discountType: 'per_night',
            discountStartDate: null,
            hotelDayCheckin: null,
            hotelDayCheckout: null,
            vectorClock: {},
          );
        },
      );

      return PaymentReportItem(
        guestName: booking.guestName,
        roomNumber: booking.roomNumber,
        amount: payment.amount,
        method: payment.paymentMethod,
        paymentDate: _safeParseDateTime(payment.paymentDate),
        receivedBy: 'النظام',
        notes: payment.notes,
      );
    }).toList();

    final report = EnhancedPaymentsReport(
      payments: reportItems,
      fromDate: fromDate,
      toDate: toDate,
      roomFilter: roomFilter,
      generatedBy: generatedBy,
    );

    await report.generatePDF();
  }

  /// إنشاء تقرير مصروفات محسّن
  static Future<void> generateEnhancedExpensesReport({
    required List<Expense> expenses,
    required DateTime fromDate,
    required DateTime toDate,
    String? categoryFilter,
    required String generatedBy,
  }) async {
    final reportItems = expenses
        .map(
          (expense) => ExpenseReportItem(
            description: expense.description,
            category: expense.expenseType,
            amount: expense.amount,
            date: _safeParseDateTime(expense.date),
            notes: null,
          ),
        )
        .toList();

    final report = EnhancedExpensesReport(
      expenses: reportItems,
      fromDate: fromDate,
      toDate: toDate,
      categoryFilter: categoryFilter,
      generatedBy: generatedBy,
    );

    await report.generatePDF();
  }

  /// إنشاء تقرير شامل للفندق
  static Future<void> generateHotelSummaryReport({
    required DateTime fromDate,
    required DateTime toDate,
    required List<Booking> bookings,
    required List<Payment> payments,
    required List<Expense> expenses,
    required String generatedBy,
  }) async {
    final fonts = await EnhancedPdfUtils.loadArabicFonts();
    final logo = await EnhancedPdfUtils.loadLogoImage();
    final pdf = pw.Document();

    // حساب الإحصائيات
    final totalRevenue = payments.fold(0.0, (sum, p) => sum + p.amount);
    final totalExpenses = expenses.fold(0.0, (sum, e) => sum + e.amount);
    final netProfit = totalRevenue - totalExpenses;
    final totalBookings = bookings.length;
    final checkedInGuests = bookings
        .where((b) => b.status == 'checked_in')
        .length;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        header: (context) => pw.Column(
          children: [
            EnhancedPdfUtils.buildProfessionalHeader(
              fonts: fonts,
              logo: logo,
              title: 'التقرير الشامل للفندق',
              subtitle: 'Hotel Summary Report',
            ),
            pw.SizedBox(height: 20),
          ],
        ),
        build: (context) => [
          // معلومات الفترة
          EnhancedPdfUtils.buildInfoCard(
            title: '📊 معلومات التقرير',
            fonts: fonts,
            content: [
              pw.Text(
                'فترة التقرير: ${EnhancedPdfUtils.formatDateTime(fromDate)} - ${EnhancedPdfUtils.formatDateTime(toDate)}',
                style: PdfTextStyles.body(fonts.regular),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'تاريخ الإنشاء: ${EnhancedPdfUtils.formatDateTime(DateTime.now())}',
                style: PdfTextStyles.body(fonts.regular),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'أُنشئ بواسطة: $generatedBy',
                style: PdfTextStyles.body(fonts.regular),
              ),
            ],
          ),

          pw.SizedBox(height: 20),

          // إحصائيات رئيسية
          pw.Text(
            'الإحصائيات الرئيسية',
            style: PdfTextStyles.heading2(fonts.bold),
          ),
          pw.SizedBox(height: 12),

          // صف الإحصائيات الأول
          pw.Row(
            children: [
              pw.Expanded(
                child: EnhancedPdfUtils.buildStatisticsBox(
                  title: 'إجمالي الإيرادات',
                  value: EnhancedPdfUtils.formatNumber(totalRevenue),
                  fonts: fonts,
                  color: PdfColors.success,
                  icon: '💰',
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: EnhancedPdfUtils.buildStatisticsBox(
                  title: 'إجمالي المصروفات',
                  value: EnhancedPdfUtils.formatNumber(totalExpenses),
                  fonts: fonts,
                  color: PdfColors.danger,
                  icon: '💸',
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 12),

          // صف الإحصائيات الثاني
          pw.Row(
            children: [
              pw.Expanded(
                child: EnhancedPdfUtils.buildStatisticsBox(
                  title: 'صافي الربح',
                  value: EnhancedPdfUtils.formatNumber(netProfit),
                  subtitle: netProfit >= 0 ? 'ربح' : 'خسارة',
                  fonts: fonts,
                  color: netProfit >= 0 ? PdfColors.success : PdfColors.danger,
                  icon: netProfit >= 0 ? '📈' : '📉',
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: EnhancedPdfUtils.buildStatisticsBox(
                  title: 'عدد الحجوزات',
                  value: totalBookings.toString(),
                  subtitle: 'حجز',
                  fonts: fonts,
                  color: PdfColors.info,
                  icon: '🏨',
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 20),

          // معدل الإشغال
          EnhancedPdfUtils.buildInfoCard(
            title: '🏨 معلومات الإشغال',
            fonts: fonts,
            borderColor: PdfColors.accent,
            content: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'إجمالي الحجوزات:',
                    style: PdfTextStyles.bodyBold(fonts.bold),
                  ),
                  pw.Text(
                    '$totalBookings حجز',
                    style: PdfTextStyles.body(fonts.regular),
                  ),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'النزلاء الحاليون:',
                    style: PdfTextStyles.bodyBold(fonts.bold),
                  ),
                  pw.Text(
                    '$checkedInGuests نزيل',
                    style: PdfTextStyles.body(fonts.regular),
                  ),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'متوسط الإيراد لكل حجز:',
                    style: PdfTextStyles.bodyBold(fonts.bold),
                  ),
                  pw.Text(
                    totalBookings > 0
                        ? EnhancedPdfUtils.formatCurrency(
                            totalRevenue / totalBookings,
                          )
                        : '0',
                    style: PdfTextStyles.body(fonts.regular),
                  ),
                ],
              ),
            ],
          ),

          pw.SizedBox(height: 20),

          // خاتمة التقرير
          EnhancedPdfUtils.buildContactFooter(fonts: fonts),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename:
          'hotel-summary-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.pdf',
    );
  }
}

/// Widget لعرض معاينة PDF محسّنة
class EnhancedPdfPreviewScreen extends ConsumerWidget {
  const EnhancedPdfPreviewScreen({
    super.key,
    required this.title,
    required this.pdfGenerator,
  });
  final String title;
  final Future<Uint8List> Function() pdfGenerator;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () async {
              final bytes = await pdfGenerator();
              await Printing.sharePdf(
                bytes: bytes,
                filename: '${title.replaceAll(' ', '-').toLowerCase()}.pdf',
              );
            },
            tooltip: 'مشاركة PDF',
          ),
        ],
      ),
      body: FutureBuilder<Uint8List>(
        future: pdfGenerator(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('جارِ إنشاء PDF...'),
                ],
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('حدث خطأ في إنشاء PDF: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('رجوع'),
                  ),
                ],
              ),
            );
          }

          return PdfPreview(
            build: (format) => snapshot.data!,
            allowSharing: true,
            allowPrinting: true,
            canChangePageFormat: false,
            canChangeOrientation: false,
          );
        },
      ),
    );
  }
}

/// مساعد لفتح معاينة PDF محسّنة
class PdfPreviewHelper {
  static void openEnhancedPaymentReceiptPreview(
    BuildContext context, {
    required Payment payment,
    required Booking booking,
    required String receivedBy,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EnhancedPdfPreviewScreen(
          title: 'إيصال دفع محسّن',
          pdfGenerator: () async {
            final receipt = EnhancedPaymentReceipt(
              receiptNumber: 'REC-${DateTime.now().millisecondsSinceEpoch}',
              guestName: booking.guestName,
              guestPhone: booking.guestPhone,
              roomNumber: booking.roomNumber,
              payment: payment,
              hotelName: 'فندق مارينا بلازا',
              hotelAddress: 'القاهرة - شارع احمد قاسم',
              receivedBy: receivedBy,
              issuedAt: DateTime.now(),
              notes: payment.notes,
            );

            return receipt.generatePdfBytes();
          },
        ),
      ),
    );
  }
}
