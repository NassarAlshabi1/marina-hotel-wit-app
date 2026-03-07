import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart'; // للوصول لـ compute
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../components/app_scaffold.dart';
import '../../components/widgets/empty_state.dart';
import '../../providers/core_providers.dart' as core_providers;
import '../../services/daos/outbox_dao.dart';
import '../../services/daos/payments_dao.dart';
import '../../services/local_db.dart';
import '../../services/report_cache_service.dart';
import '../../utils/enhanced_pdf_utils.dart';

class PaymentsReportScreen extends ConsumerStatefulWidget {
  const PaymentsReportScreen({super.key});

  @override
  ConsumerState<PaymentsReportScreen> createState() =>
      _PaymentsReportScreenState();
}

class _PaymentsReportScreenState extends ConsumerState<PaymentsReportScreen> {
  final DateFormat _dateLabelFormat = DateFormat('yyyy/MM/dd HH:mm');
  final NumberFormat _currencyFmt = NumberFormat('#,##0', 'en_US');

  // فلاتر
  DateTime? _fromDate;
  DateTime? _toDate;
  final TextEditingController _roomSearchController = TextEditingController();

  // ⭐ فلتر طريقة الدفع
  String? _selectedPaymentMethod;
  List<String> _availablePaymentMethods = [];

  bool _loading = false;
  bool _isFromCache = false;

  final List<_PaymentReportRow> _rows = [];
  double _totalAmount = 0;

  @override
  void initState() {
    super.initState();
    _initializeDefaults();
  }

  @override
  void dispose() {
    _roomSearchController.dispose();
    super.dispose();
  }

  Future<void> _initializeDefaults() async {
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, now.day, 0, 0, 0);
    _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);

    await _loadPaymentMethods();
    await _fetchReport();
  }

  /// ⭐ تحميل طرق الدفع المتاحة
  Future<void> _loadPaymentMethods() async {
    try {
      final db = ref.read(core_providers.dbProvider);
      final query = await db
          .customSelect("SELECT DISTINCT payment_method FROM payments WHERE payment_method IS NOT NULL AND payment_method != ''")
          .get();
      
      final methods = query
          .map((row) => row.data['payment_method'] as String)
          .where((m) => m.isNotEmpty)
          .toList()
        ..sort();

      setState(() {
        _availablePaymentMethods = methods;
      });
    } catch (e) {
      debugPrint('Error loading payment methods: $e');
    }
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initialDate =
        isFrom ? (_fromDate ?? DateTime.now()) : (_toDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = DateTime(picked.year, picked.month, picked.day, 0, 0, 0);
        } else {
          _toDate = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        }
      });
      unawaited(_fetchReport());
    }
  }

  /// ⭐ إنشاء معاملات الـ cache
  Map<String, dynamic> _getCacheParams() {
    return {
      'fromDate': _fromDate?.toIso8601String(),
      'toDate': _toDate?.toIso8601String(),
      'roomNumber': _roomSearchController.text.trim(),
      'paymentMethod': _selectedPaymentMethod,
    };
  }

  Future<void> _fetchReport() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _isFromCache = false;
    });

    try {
      final db = ref.read(core_providers.dbProvider);

      // ⭐ محاولة الحصول على البيانات من الـ cache أولاً
      final cachedResult = await ReportCacheService.instance.get<
          _PaymentsReportResult>(
        ReportCacheKeys.payments,
        _getCacheParams(),
        (json) => _PaymentsReportResult.fromJson(json),
      );

      if (cachedResult != null) {
        setState(() {
          _rows
            ..clear()
            ..addAll(cachedResult.rows);
          _totalAmount = cachedResult.totalPaid;
          _isFromCache = true;
        });
        return;
      }

      final outboxDao = OutboxDao(db);
      final paymentsDao = PaymentsDao(db, outboxDao);

      final fromStr = _fromDate != null
          ? DateFormat('yyyy-MM-dd').format(_fromDate!)
          : null;
      final toStr =
          _toDate != null ? DateFormat('yyyy-MM-dd').format(_toDate!) : null;

      final roomQuery = _roomSearchController.text.trim();

      // 1. جلب البيانات الخام من قاعدة البيانات (سريع)
      final payments = await paymentsDao.listForReport(
        from: fromStr,
        to: toStr,
        roomNumber: roomQuery.isNotEmpty ? roomQuery : null,
      );

      // ⭐ فلترة بطريقة الدفع
      final filteredPayments = _selectedPaymentMethod != null
          ? payments.where((p) => p.paymentMethod == _selectedPaymentMethod).toList()
          : payments;

      final bookingIds =
          filteredPayments.map((p) => p.bookingLocalId).whereType<int>().toSet();

      final bookings = bookingIds.isEmpty
          ? <Booking>[]
          : await (db.select(db.bookings)
                ..where((tbl) => tbl.id.isIn(bookingIds.toList())))
              .get();

      // تجهيز البيانات للنقل للخلفية (Isolate)
      final paymentMaps = filteredPayments.map((p) => p.toJson()).toList();
      final bookingMaps = bookings.map((b) => b.toJson()).toList();

      // 2. المعالجة الثقيلة في الخلفية
      final result = await compute(
          _processPaymentsData,
          _PaymentProcessParams(
            payments: paymentMaps,
            bookings: bookingMaps,
          ));

      // ⭐ تخزين النتيجة في الـ cache
      await ReportCacheService.instance.set(
        ReportCacheKeys.payments,
        _getCacheParams(),
        result,
        (r) => r.toJson(),
      );

      setState(() {
        _rows
          ..clear()
          ..addAll(result.rows);
        _totalAmount = result.totalPaid;
      });
    } catch (e) {
      debugPrint('Error loading payments report: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _exportPdf() async {
    if (_rows.isEmpty) return;
    final fonts = await EnhancedPdfUtils.loadArabicFonts();
    final doc = pw.Document();

    final prefs = await SharedPreferences.getInstance();
    final hotelName = prefs.getString('hotel_name') ?? 'فندق مارينا بلازا';
    final hotelPhone = prefs.getString('hotel_phone') ?? '';
    final hotelAddress = prefs.getString('hotel_address') ?? '';
    final hotelLogoPath = prefs.getString('hotel_logo');

    pw.ImageProvider? logoImage;
    if (hotelLogoPath != null && File(hotelLogoPath).existsSync()) {
      final logoBytes = File(hotelLogoPath).readAsBytesSync();
      logoImage = pw.MemoryImage(logoBytes);
    }

    final fromLabel = _fromDate != null
        ? DateFormat('yyyy-MM-dd').format(_fromDate!)
        : 'غير محدد';
    final toLabel = _toDate != null
        ? DateFormat('yyyy-MM-dd').format(_toDate!)
        : 'غير محدد';

    final roomLabel = _roomSearchController.text.isNotEmpty
        ? _roomSearchController.text
        : 'الكل';

    final paymentMethodLabel = _selectedPaymentMethod ?? 'الكل';

    pw.Widget buildReportHeader() {
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(vertical: 20, horizontal: 20),
        decoration: const pw.BoxDecoration(
          color: PdfColors.white,
          border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey300, width: 1)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  hotelName,
                  style: pw.TextStyle(
                      font: fonts.bold, fontSize: 18, color: PdfColors.blue900),
                ),
                if (hotelPhone.isNotEmpty)
                  pw.Text('هاتف: $hotelPhone',
                      style: pw.TextStyle(font: fonts.regular, fontSize: 10)),
                if (hotelAddress.isNotEmpty)
                  pw.Text('عنوان: $hotelAddress',
                      style: pw.TextStyle(font: fonts.regular, fontSize: 10)),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  'تقرير مدفوعات النزلاء',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 16),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'من $fromLabel إلى $toLabel',
                  style: pw.TextStyle(
                      font: fonts.regular,
                      fontSize: 10,
                      color: PdfColors.grey700),
                ),
              ],
            ),
            if (logoImage != null)
              pw.Container(
                height: 50,
                width: 50,
                child: pw.Image(logoImage),
              )
            else
              pw.SizedBox(width: 50),
          ],
        ),
      );
    }

    final metaInfo = EnhancedPdfUtils.buildInfoCard(
      title: 'معايير التقرير',
      fonts: fonts,
      content: [
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('رقم الغرفة: $roomLabel',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 10)),
              pw.Text('طريقة الدفع: $paymentMethodLabel',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 10)),
            ],
          ),
        ),
      ],
    );

    final headers = ['التاريخ', 'الغرفة', 'النزيل', 'طريقة الدفع', 'المبلغ'];

    final dataRows = <List<String>>[];
    for (final row in _rows) {
      dataRows.add([
        _dateLabelFormat.format(row.paymentDate),
        row.roomNumber,
        row.payerName,
        row.paymentMethod,
        _currencyFmt.format(row.amount),
      ]);
    }

    final totalRow = [
      'الإجمالي',
      '',
      '',
      '',
      _currencyFmt.format(_totalAmount),
    ];
    dataRows.add(totalRow);

    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.center,
          child: pw.Text(
            'صفحة ${context.pageNumber} من ${context.pagesCount} - تاريخ الطباعة: ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}',
            style: pw.TextStyle(
                font: fonts.regular, fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          buildReportHeader(),
          pw.SizedBox(height: 12),
          metaInfo,
          pw.SizedBox(height: 12),
          EnhancedPdfUtils.buildProfessionalTable(
            headers: headers,
            data: dataRows,
            fonts: fonts,
            headerColor: PdfColors.blue800,
            alternateRowColor: PdfColors.grey100,
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            alignment: pw.Alignment.centerLeft,
            child: pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.blue800, width: 1),
                borderRadius: pw.BorderRadius.circular(4),
                color: PdfColors.blue50,
              ),
              child: pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text('المجموع الكلي: ',
                      style: pw.TextStyle(font: fonts.bold, fontSize: 12)),
                  pw.Text(
                    _currencyFmt.format(_totalAmount),
                    style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 14,
                        color: PdfColors.green700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    String generateFileName(String title) {
      final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final sanitizedTitle = title.replaceAll(RegExp(r'\s+'), '-');
      return '$sanitizedTitle-$timestamp.pdf';
    }

    final pdfBytes = await doc.save();
    final fileName = generateFileName('مدفوعات النزلاء');

    try {
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (await downloadDir.exists()) {
        final file = File('${downloadDir.path}/$fileName');
        await file.writeAsBytes(pdfBytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم حفظ التقرير في: ${file.path}'),
              backgroundColor: Colors.green,
              action: SnackBarAction(
                label: 'فتح',
                textColor: Colors.white,
                onPressed: () =>
                    Printing.sharePdf(bytes: pdfBytes, filename: fileName),
              ),
            ),
          );
        }
        return;
      }
    } catch (e) {
      debugPrint('تعذر الحفظ المباشر في التنزيلات: $e');
    }

    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: fileName,
    );
  }

  @override
  Widget build(BuildContext context) {
    const double inputsHeight = 42;

    return AppScaffold(
      title: 'تقرير مدفوعات النزلاء',
      actions: [
        if (_isFromCache)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Tooltip(
              message: 'البيانات من الذاكرة المؤقتة',
              child: Icon(Icons.cached, color: Colors.green[600], size: 20),
            ),
          ),
      ],
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                // الصف الأول: التواريخ والأزرار
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: _buildDateFilterButton(
                        label: 'من',
                        date: _fromDate,
                        height: inputsHeight,
                        onTap: () => _pickDate(isFrom: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: _buildDateFilterButton(
                        label: 'إلى',
                        date: _toDate,
                        height: inputsHeight,
                        onTap: () => _pickDate(isFrom: false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: inputsHeight,
                      width: inputsHeight,
                      child: ElevatedButton(
                        onPressed: _fetchReport,
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          elevation: 0,
                          backgroundColor: Theme.of(context).primaryColor,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Icon(Icons.search, size: 20),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: inputsHeight,
                      width: inputsHeight,
                      child: ElevatedButton(
                        onPressed: _rows.isEmpty ? null : _exportPdf,
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          elevation: 0,
                          backgroundColor: Colors.red[700],
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Icon(Icons.picture_as_pdf, size: 20),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // الصف الثاني: الفلاتر
                Row(
                  children: [
                    // فلتر رقم الغرفة
                    Expanded(
                      flex: 3,
                      child: SizedBox(
                        height: inputsHeight,
                        child: TextField(
                          controller: _roomSearchController,
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            labelText: 'رقم الغرفة',
                            labelStyle: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                            prefixIcon: const Icon(Icons.meeting_room,
                                size: 16, color: Colors.grey),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade400),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade400),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 0),
                          ),
                          onSubmitted: (_) => _fetchReport(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // ⭐ فلتر طريقة الدفع
                    Expanded(
                      flex: 3,
                      child: SizedBox(
                        height: inputsHeight,
                        child: DropdownButtonFormField<String?>(
                          initialValue: _selectedPaymentMethod,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black),
                          decoration: InputDecoration(
                            labelText: 'طريقة الدفع',
                            labelStyle: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                            prefixIcon: const Icon(Icons.payment,
                                size: 16, color: Colors.grey),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 0),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade400),
                            ),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('الكل',
                                  style: TextStyle(fontSize: 12)),
                            ),
                            ..._availablePaymentMethods.map(
                              (method) => DropdownMenuItem<String?>(
                                value: method,
                                child: Text(method,
                                    style: const TextStyle(fontSize: 12)),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedPaymentMethod = value;
                            });
                            _fetchReport();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'عدد السجلات: ${_rows.length}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.grey.shade600),
                    ),
                    if (_isFromCache) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'محفوظ مؤقتاً',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.green[700],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Row(
                  children: [
                    const Text('الإجمالي: ',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    Text(
                      _currencyFmt.format(_totalAmount),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.green),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? const EmptyState(
                        title: 'لا توجد بيانات',
                        message: 'لم يتم العثور على نتائج تطابق الفلاتر.',
                        icon: Icons.receipt_long_outlined,
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          // مسح الـ cache وإعادة التحميل
                          await ReportCacheService.instance.clearAll();
                          await _fetchReport();
                        },
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _rows.length,
                          itemBuilder: (context, index) {
                            final row = _rows[index];
                            return _buildPaymentCard(row);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateFilterButton({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
    required double height,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                ),
                Text(
                  date != null
                      ? DateFormat('yyyy/MM/dd').format(date)
                      : 'غير محدد',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentCard(_PaymentReportRow row) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${row.payerName} - غرفة ${row.roomNumber}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        row.paymentMethod,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _currencyFmt.format(row.amount),
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  _dateLabelFormat.format(row.paymentDate),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentProcessParams {
  _PaymentProcessParams({required this.payments, required this.bookings});
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> bookings;

  Map<String, dynamic> toJson() => {
    'payments': payments,
    'bookings': bookings,
  };

  factory _PaymentProcessParams.fromJson(Map<String, dynamic> json) =>
      _PaymentProcessParams(
        payments: (json['payments'] as List).cast<Map<String, dynamic>>(),
        bookings: (json['bookings'] as List).cast<Map<String, dynamic>>(),
      );
}

class _PaymentReportRow {
  _PaymentReportRow({
    required this.paymentDate,
    required this.amount,
    required this.roomNumber,
    required this.payerName,
    required this.paymentMethod,
  });

  final DateTime paymentDate;
  final double amount;
  final String roomNumber;
  final String payerName;
  final String paymentMethod;

  Map<String, dynamic> toJson() => {
    'paymentDate': paymentDate.toIso8601String(),
    'amount': amount,
    'roomNumber': roomNumber,
    'payerName': payerName,
    'paymentMethod': paymentMethod,
  };

  factory _PaymentReportRow.fromJson(Map<String, dynamic> json) =>
      _PaymentReportRow(
        paymentDate: DateTime.parse(json['paymentDate'] as String),
        amount: (json['amount'] as num).toDouble(),
        roomNumber: json['roomNumber'] as String,
        payerName: json['payerName'] as String,
        paymentMethod: json['paymentMethod'] as String,
      );
}

class _PaymentsReportResult {
  _PaymentsReportResult({
    required this.rows,
    required this.totalPaid,
  });

  final List<_PaymentReportRow> rows;
  final double totalPaid;

  Map<String, dynamic> toJson() => {
    'rows': rows.map((r) => r.toJson()).toList(),
    'totalPaid': totalPaid,
  };

  factory _PaymentsReportResult.fromJson(Map<String, dynamic> json) =>
      _PaymentsReportResult(
        rows: (json['rows'] as List)
            .map((r) => _PaymentReportRow.fromJson(r as Map<String, dynamic>))
            .toList(),
        totalPaid: (json['totalPaid'] as num).toDouble(),
      );
}

// دالة منفصلة top-level للمعالجة في الخلفية
_PaymentsReportResult _processPaymentsData(_PaymentProcessParams params) {
  // ⭐ إنشاء خريطة الحجوزات بعدة مفاتيح للبحث السريع
  final bookingByIdMap = {for (final b in params.bookings) b['id']: b};
  final bookingByUuidMap = {
    for (final b in params.bookings) 
      if (b['localUuid'] != null) b['localUuid']: b
  };

  final rows = <_PaymentReportRow>[];
  double totalPaid = 0;

  for (final p in params.payments) {
    // ⭐ البحث عن الحجز بعدة طرق (استخدام camelCase من toJson)
    final bookingId = p['bookingLocalId'];
    final bookingUuid = p['bookingUuidCache'];
    
    Map<String, dynamic>? booking;
    if (bookingId != null) {
      booking = bookingByIdMap[bookingId];
    }
    if (booking == null && bookingUuid != null) {
      booking = bookingByUuidMap[bookingUuid];
    }

    // ⭐ استخراج اسم الضيف من مصادر متعددة
    String payerName = 'غير محدد';
    // 1. من الحجز المرتبط
    if (booking != null && booking['guestName'] != null && 
        (booking['guestName'] as String).isNotEmpty) {
      payerName = booking['guestName'];
    }
    // 2. من revenue_type كبديل (دائماً موجود)
    else if (p['revenueType'] != null && (p['revenueType'] as String).isNotEmpty) {
      payerName = p['revenueType'];
    }
    // 3. من ملاحظات الدفعة
    else if (p['notes'] != null && (p['notes'] as String).isNotEmpty) {
      payerName = p['notes'];
    }

    // ⭐ استخراج رقم الغرفة من مصادر متعددة
    String roomNumber = '-';
    // 1. من حقل roomNumber في الدفعة
    if (p['roomNumber'] != null && (p['roomNumber'] as String).isNotEmpty) {
      roomNumber = p['roomNumber'];
    }
    // 2. من الحجز المرتبط
    else if (booking != null && booking['roomNumber'] != null && 
        (booking['roomNumber'] as String).isNotEmpty) {
      roomNumber = booking['roomNumber'];
    }

    // التاريخ
    DateTime paymentDate = DateTime.now();
    if (p['paymentDate'] != null) {
      try {
        final String val = p['paymentDate'].toString();
        paymentDate = DateTime.parse(
            val.contains('T') ? val : val.replaceFirst(' ', 'T'));
      } catch (_) {}
    }

    final amount = ((p['amount'] ?? 0) as num).toDouble();
    final paymentMethod = (p['paymentMethod'] ?? 'غير محدد').toString();

    totalPaid += amount;

    rows.add(
      _PaymentReportRow(
        paymentDate: paymentDate,
        amount: amount,
        roomNumber: roomNumber,
        payerName: payerName,
        paymentMethod: paymentMethod,
      ),
    );
  }

  // ترتيب حسب التاريخ تنازلياً
  rows.sort((a, b) => b.paymentDate.compareTo(a.paymentDate));

  return _PaymentsReportResult(rows: rows, totalPaid: totalPaid);
}
