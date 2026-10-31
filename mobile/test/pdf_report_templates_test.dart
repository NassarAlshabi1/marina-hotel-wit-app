// ============================================================================
//  Marina Hotel — اختبارات تصدير تقارير PDF (قوالب التقارير الثمانية)
// ============================================================================
//  الغطاء:
//    1. اختبار انحدار لخلل «Widget won't fit … height (Infinity)» — بطاقة
//       buildInfoCard كانت تستخدم Row + crossAxisAlignment.stretch داخل
//       MultiPage، والحزمة pdf تفرض على الأبناء minHeight = maxHeight
//       الوارد = ∞ → استثناء أثناء بناء المستند (أُصلح 2026-11-01
//       باستبدالها بجدول TableCellVerticalAlignment.full).
//    2. كل قوالب التقارير من طرف إلى طرف: Template.share() ← بناء المستند
//       ← save() ← Printing.sharePdf (قناة net.nfet.printing مُحاكاة) —
//       أي خلل تخطيط (مثل Infinity) يفشل الاختبار مباشرة.
//    3. تنقية أسماء ملفات PDF من الأحرف المحظورة في أنظمة الملفات.
//
//  آلية عمل المحاكاة (بدون جهاز حقيقي):
//    - قناة flutter/assets تُخدَّم من ملفات المشروع الحقيقية حتى يعمل
//      EnhancedPdfUtils.loadArabicFonts() عبر rootBundle كما في الإنتاج.
//    - قناة net.nfet.printing تلتقط (اسم الملف + بايتات PDF) بدل نافذة
//      المشاركة، فنتحقق من صحة الملف المولَّد فعلياً.
//
//  التشغيل:
//    flutter test test/pdf_report_templates_test.dart --reporter=expanded
// ============================================================================

// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert' show utf8;
import 'dart:io' show File;
import 'dart:typed_data' show ByteData, Uint8List;

import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;

import 'package:marina_hotel_mobile/src/pdf/enhanced_pdf_utils.dart';
import 'package:marina_hotel_mobile/src/pdf/report_pdf_builder.dart';
import 'package:marina_hotel_mobile/src/pdf/report_templates/debts_report_pdf.dart';
import 'package:marina_hotel_mobile/src/pdf/report_templates/expenses_report_pdf.dart';
import 'package:marina_hotel_mobile/src/pdf/report_templates/guest_statement_pdf.dart';
import 'package:marina_hotel_mobile/src/pdf/report_templates/income_expense_report_pdf.dart';
import 'package:marina_hotel_mobile/src/pdf/report_templates/inventory_report_pdf.dart';
import 'package:marina_hotel_mobile/src/pdf/report_templates/payments_report_pdf.dart';
import 'package:marina_hotel_mobile/src/pdf/report_templates/salary_withdrawals_report_pdf.dart';

/// التقاطات Printing.sharePdf المُحاكاة.
final List<({String filename, Uint8List bytes})> _sharedPdfs =
    <({String filename, Uint8List bytes})>[];

/// يخدّم قناة flutter/assets من ملفات المشروع الحقيقية — حتى يعمل
/// rootBundle.load (مسار تحميل الخطوط الفعلي في الإنتاج) داخل الاختبارات.
void _serveRealAssets() {
  const assetChannel = 'flutter/assets';
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(assetChannel, (ByteData? message) async {
        final path = utf8.decode(
          message!.buffer.asUint8List(
            message.offsetInBytes,
            message.lengthInBytes,
          ),
        );
        final file = File(path);
        if (!file.existsSync()) {
          throw StateError('الأصل المطلوب غير موجود على القرص: $path');
        }
        final bytes = await file.readAsBytes();
        return ByteData.sublistView(bytes);
      });
}

/// يحاكي البرنامج المساعد printing: يلتقط استدعاءات sharePdf بدل فتح
/// نافذة المشاركة، ويعيد 1 (نجاح) كما تتوقعه طبقة Dart.
void _mockPrintingPlugin() {
  const channel = MethodChannel('net.nfet.printing');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'sharePdf') {
          final args = call.arguments as Map<dynamic, dynamic>;
          _sharedPdfs.add((
            filename: args['name'] as String? ?? '',
            bytes: args['doc'] as Uint8List,
          ));
          return 1;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    _serveRealAssets();
    _mockPrintingPlugin();
  });

  setUp(() => _sharedPdfs.clear());

  /// تحقق موحّد: نتيجة واحدة صالحة تبدأ بـ %PDF وحجم معقول.
  void expectOneValidPdf({int minBytes = 2000}) {
    expect(_sharedPdfs, hasLength(1), reason: 'يجب إنتاج ملف PDF واحد');
    final pdf = _sharedPdfs.single;
    expect(
      String.fromCharCodes(pdf.bytes.take(5)),
      '%PDF-',
      reason: 'الملف يجب أن يبدأ بتوقيع %PDF',
    );
    expect(
      pdf.bytes.length,
      greaterThan(minBytes),
      reason: 'حجم PDF صغير جداً — المحتوى غير مولَّد',
    );
    expect(pdf.filename, isNotEmpty);
    expect(pdf.filename.endsWith('.pdf'), isTrue);
  }

  final from = DateTime(2026, 10, 1);
  final to = DateTime(2026, 10, 31);

  // ═══════════════════════════════════════════════════════════════════════
  //  1. اختبار الانحدار — الخلل الأصلي (Infinity height)
  // ═══════════════════════════════════════════════════════════════════════
  group('🔧 اختبار انحدار: بطاقة buildInfoCard داخل MultiPage', () {
    test(
      'لا تنتج ارتفاعاً لا نهائياً (كانت ترمي Widget won\'t fit Infinity)',
      () async {
        final fonts = await EnhancedPdfUtils.loadArabicFonts();
        final doc = pw.Document();
        doc.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            textDirection: pw.TextDirection.rtl,
            theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
            build: (context) => [
              // قبل الإصلاح (Row + stretch) كان هذا السطر بالضبط يرمي:
              // Exception: Widget won't fit into the page as its height
              //   (Infinity) exceed a page height (751.8897637795275)
              EnhancedPdfUtils.buildInfoCard(
                title: 'بطاقة معلومات تجريبية',
                fonts: fonts,
                content: [
                  EnhancedPdfUtils.buildKeyValueRow(
                    fonts: fonts,
                    label: 'الفترة',
                    value: 'من 2026-10-01 إلى 2026-10-31',
                  ),
                  EnhancedPdfUtils.buildKeyValueRow(
                    fonts: fonts,
                    label: 'الموظف',
                    value: 'الكل',
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
            ],
          ),
        );
        final bytes = await doc.save();
        expect(bytes.length, greaterThan(1500));
      },
    );

    test('مربع الإحصاءات وبطاقة القيم تعملان معاً في نفس المستند', () async {
      final fonts = await EnhancedPdfUtils.loadArabicFonts();
      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (context) => [
            EnhancedPdfUtils.buildStatisticsGrid(
              items: [
                EnhancedPdfUtils.buildStatisticsBox(
                  title: 'إجمالي',
                  value: '12,500',
                  fonts: fonts,
                ),
                EnhancedPdfUtils.buildStatisticsBox(
                  title: 'عدد',
                  value: '3',
                  fonts: fonts,
                  color: PdfColors.accent,
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            EnhancedPdfUtils.buildInfoCard(
              title: 'ملخص',
              fonts: fonts,
              content: [
                EnhancedPdfUtils.buildKeyValueRow(
                  fonts: fonts,
                  label: 'عدد السجلات',
                  value: '3',
                ),
              ],
            ),
          ],
        ),
      );
      final bytes = await doc.save();
      expect(bytes.length, greaterThan(1500));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  2. تقرير سحبيات الرواتب — التقرير المُبلَّغ عنه
  // ═══════════════════════════════════════════════════════════════════════
  group('🧾 تقرير سحبيات الرواتب', () {
    test('التصدير بفلتر «الكل» ينجح وينتج PDF صالحاً', () async {
      await SalaryWithdrawalsReportPdf.share(
        SalaryWithdrawalsReportData(
          rows: [
            SalaryWithdrawalsReportRow(
              date: DateTime(2026, 10, 15),
              amount: 12500,
              withdrawalType: 'سحب راتب',
              displayReason: 'سلفة على الراتب',
              description: '-',
              employeeName: 'موظف 1',
            ),
            SalaryWithdrawalsReportRow(
              date: DateTime(2026, 10, 20),
              amount: 3000,
              withdrawalType: 'خصم من الراتب',
              displayReason: 'غياب',
              description: 'خصم يومين',
              employeeName: 'موظف 2',
            ),
          ],
          fromDate: from,
          toDate: to,
        ),
      );
      expectOneValidPdf();
    });

    test('التصدير لموظف واحد (عمود الموظف مخفي) ينجح', () async {
      await SalaryWithdrawalsReportPdf.share(
        SalaryWithdrawalsReportData(
          rows: [
            SalaryWithdrawalsReportRow(
              date: DateTime(2026, 10, 15),
              amount: 12500,
              withdrawalType: 'سحب راتب',
              displayReason: '-',
              description: '-',
            ),
          ],
          fromDate: from,
          toDate: to,
          selectedEmployeeName: 'موظف 1',
        ),
      );
      expectOneValidPdf(minBytes: 1000);
    });

    test('230 صفاً تنقسم على عدة صفحات دون فقدان (اختبار التقطيع)', () async {
      await SalaryWithdrawalsReportPdf.share(
        SalaryWithdrawalsReportData(
          rows: [
            for (var i = 1; i <= 230; i++)
              SalaryWithdrawalsReportRow(
                date: DateTime(2026, 10, 1 + (i % 28)),
                amount: 5000.0 * (i % 7) + 500,
                withdrawalType: i % 3 == 0 ? 'خصم من الراتب' : 'سحب راتب',
                displayReason: i % 2 == 0 ? 'سلفة' : '-',
                description: '-',
                employeeName: 'موظف ${i % 4}',
              ),
          ],
          fromDate: from,
          toDate: to,
        ),
      );
      expectOneValidPdf(minBytes: 20000);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  3. بقية قوالب التقارير
  // ═══════════════════════════════════════════════════════════════════════
  group('💰 تقرير مدفوعات النزلاء', () {
    test('التصدير ينجح مع بطاقة الإجماليات المضغوطة', () async {
      await PaymentsReportPdf.share(
        PaymentsReportData(
          rows: [
            for (var i = 1; i <= 12; i++)
              PaymentsReportRow(
                paymentDate: DateTime(2026, 10, i + 5, 14, 30),
                amount: 4500.0 + i * 100,
                roomNumber: '${100 + i % 5}',
                payerName: 'نزيل تجريبي $i',
                bookingCode: '00012$i',
                paymentMethod: i % 2 == 0 ? 'نقداً' : 'تحويل بنكي',
              ),
          ],
          totalRoomPaid: 62000,
          totalOtherPaid: 8000,
          totalRemaining: 3500,
          totalDue: 3500,
          fromDate: from,
          toDate: to,
        ),
      );
      expectOneValidPdf();
    });
  });

  group('💸 تقرير المصروفات', () {
    test('التصدير ينجح مع بيانات رواتب (عمود الموظف)', () async {
      await ExpensesReportPdf.share(
        ExpensesReportData(
          rows: [
            ExpensesReportRow(
              date: DateTime(2026, 10, 5),
              amount: 15000,
              type: 'رواتب',
              description: 'سحب راتب أكتوبر',
              employeeName: 'موظف 1',
              isSalaryWithdrawal: true,
            ),
            ExpensesReportRow(
              date: DateTime(2026, 10, 12),
              amount: 3200,
              type: 'كهرباء',
              description: 'فاتورة كهرباء',
            ),
          ],
          totalAmount: 18200,
          hasSalaryData: true,
          labels: const ExpensesReportLabels(),
          fromDate: from,
          toDate: to,
        ),
      );
      expectOneValidPdf();
    });
  });

  group('🧮 تقرير الديون', () {
    test('التصدير ينجح مع الملخصات والتفاصيل', () async {
      await DebtsReportPdf.share(
        DebtsReportData(
          guestSummaries: [
            DebtsReportGuestSummary(
              guestName: 'نزيل أول',
              totalAmount: 5000,
              paidAmount: 2000,
              remainingAmount: 3000,
            ),
          ],
          detailRows: [
            DebtsReportDetailRow(
              guestName: 'نزيل أول',
              recordedDate: '05/10/2026',
              roomPrice: 500,
              totalAmount: 5000,
              paidAmount: 2000,
              remainingAmount: 3000,
              reason: 'إقامة 10 ليالٍ',
              isSettled: false,
            ),
          ],
          totalDebt: 5000,
          totalPaid: 2000,
          totalRemaining: 3000,
          settledCount: 0,
          unsettledCount: 1,
          fromDate: from,
          toDate: to,
        ),
      );
      expectOneValidPdf();
    });
  });

  group('📦 التقرير المخزني', () {
    test('التصدير ينجح مع الملخص والأصناف', () async {
      await InventoryReportPdf.share(
        InventoryReportData(
          rows: [
            for (var i = 1; i <= 8; i++)
              InventoryReportRow(
                name: 'صنف مخزني $i',
                unit: 'قطعة',
                category: 'أدوات',
                quantity: 40 - i,
                minimumQuantity: 10,
                totalIn: 100,
                totalOut: 60 + i,
                totalAdjustment: i % 2,
                movementCount: 5,
              ),
          ],
          summary: InventoryReportSummary(
            itemCount: 8,
            lowStockCount: 1,
            totalIn: 800,
            totalOut: 500,
            totalAdjustment: 4,
            movementCount: 40,
          ),
          fromDate: from,
          toDate: to,
        ),
      );
      expectOneValidPdf();
    });
  });

  group('🏨 كشف حساب النزيل', () {
    test('التصدير ينجح مع سجل المدفوعات', () async {
      await GuestStatementPdf.share(
        GuestStatementData(
          guestName: 'نزيل تجريبي',
          roomNumber: '101',
          checkinDate: DateTime(2026, 9, 15),
          manualCheckoutDate: DateTime(2026, 9, 20),
          actualDays: 46,
          nightsRemaining: 2,
          nightlyRate: 500,
          consumedCost: 22000,
          remainingBalance: 2000,
          totalPaid: 20000,
          plannedCheckout: DateTime(2026, 10, 30),
          totalPaidNights: 40,
          effectiveBalance: 2000,
          hasPayments: true,
          surplusAfterAllNights: 0,
          payments: [
            GuestStatementPayment(
              dateText: '2026-09-15T10:30',
              amount: 5000,
              method: 'نقداً',
              reference: 'R-001',
              notes: 'دفعة أولى',
            ),
            GuestStatementPayment(
              dateText: '2026-10-01T09:00',
              amount: 15000,
              method: 'تحويل بنكي',
              reference: 'R-002',
              notes: '',
            ),
          ],
        ),
      );
      expectOneValidPdf();
    });
  });

  group('📋 تقرير أرصدة النزلاء (كل الحجوزات)', () {
    test('التصدير ينجح مع بطاقة لكل نزيل', () async {
      await GuestsBalancesPdf.share(
        GuestsBalancesData(
          rows: [
            GuestBalanceRow(
              roomNumber: '101',
              guestName: 'نزيل أول',
              checkinDate: DateTime(2026, 9, 15),
              expectedCheckoutText: '2026-09-20',
              actualDays: 46,
              nightlyRate: 500,
              contractTotal: 2500,
              remainingBalance: 2000,
              totalPaid: 20000,
              hasPayments: true,
              autoCheckoutText: '2026-10-30',
              totalPaidNights: 40,
              isAutoExtended: true,
              extraNightsBeyondManual: 40,
              uncoveredDays: 6,
            ),
          ],
          totalDue: 2500,
          totalPaid: 20000,
          totalRemaining: 2000,
          totalCredit: 500,
          reportDateText: '2026-10-31',
        ),
      );
      expectOneValidPdf();
    });
  });

  group('📊 تقرير الدخل والمصروفات', () {
    IncomeExpenseReportData buildData() => IncomeExpenseReportData(
      incomeEntries: [
        IncomeExpenseIncomeEntry(
          date: DateTime(2026, 10, 5),
          description: 'دفعة إقامة',
          amount: 5000,
          roomNumber: '101',
          guestName: 'نزيل أول',
          paymentMethod: 'نقداً',
          revenueType: 'room',
        ),
      ],
      expenseEntries: [
        IncomeExpenseExpenseEntry(
          date: DateTime(2026, 10, 5),
          type: 'رواتب',
          description: 'سحب راتب',
          amount: 3000,
          isSalary: true,
        ),
        IncomeExpenseExpenseEntry(
          date: DateTime(2026, 10, 20),
          type: 'كهرباء',
          description: 'فاتورة',
          amount: 1200,
          isSalary: false,
        ),
      ],
      fromDate: from,
      toDate: to,
      activeEmployeesCount: 4,
      terminatedEmployeesCount: 1,
      totalSalaryObligation: 20000,
      bookingsCount: 10,
      activeBookingsCount: 6,
      checkoutBookingsCount: 4,
    );

    test('التقرير العام (share) ينجح', () async {
      await IncomeExpenseReportPdf.share(buildData());
      expectOneValidPdf(minBytes: 5000);
    });

    test('التقرير التفصيلي المجمّع يومياً (shareGrouped) ينجح', () async {
      await IncomeExpenseReportPdf.shareGrouped(
        buildData(),
        mode: IncomeExpenseGroupMode.daily,
      );
      expectOneValidPdf(minBytes: 5000);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  4. تنقية أسماء ملفات PDF
  // ═══════════════════════════════════════════════════════════════════════
  group('🏷️ generateFileName — تنقية الأحرف المحظورة', () {
    test('عنوان نظيف يبقى كما هو مع الطابع الزمني', () {
      final name = ReportPdfBuilder.generateFileName('تقرير سحبيات الرواتب');
      expect(name, matches(r'^تقرير-سحبيات-الرواتب-\d{8}_\d{4}\.pdf$'));
    });

    test('اسم موظف يحوي / لا يكسر المسار', () {
      final name = ReportPdfBuilder.generateFileName('سحبيات راتب محمد/علي');
      expect(name, isNot(contains('/')));
      expect(name, isNot(contains('\\')));
    });

    test('كل الأحرف المحظورة في أنظمة الملفات تُنقّى', () {
      const hostile = r'a\b:c*d?e"f<g>h|i';
      final name = ReportPdfBuilder.generateFileName(hostile);
      for (final ch in r'\/:*?"<>|'.split('')) {
        expect(name, isNot(contains(ch)), reason: 'الحرف $ch يجب أن يُنقّى');
      }
    });

    test('اسم بأحرف عدائية فقط يسقط إلى اسم آمن', () {
      final name = ReportPdfBuilder.generateFileName('/');
      expect(name, matches(r'^report-\d{8}_\d{4}\.pdf$'));
    });

    test('اسم الملف المولَّد من القالب يخلو من الأحرف المحظورة', () async {
      await SalaryWithdrawalsReportPdf.share(
        SalaryWithdrawalsReportData(
          rows: [
            SalaryWithdrawalsReportRow(
              date: DateTime(2026, 10, 15),
              amount: 1000,
              withdrawalType: 'سحب',
              displayReason: '-',
              description: '-',
            ),
          ],
          fromDate: from,
          toDate: to,
          selectedEmployeeName: 'موظف/تجريبي: "الخاص"',
        ),
      );
      expectOneValidPdf(minBytes: 1000);
      final filename = _sharedPdfs.single.filename;
      for (final ch in r'\/:*?"<>|'.split('')) {
        expect(
          filename,
          isNot(contains(ch)),
          reason: 'اسم الملف $filename يجب ألا يحتوي $ch',
        );
      }
    });
  });
}
