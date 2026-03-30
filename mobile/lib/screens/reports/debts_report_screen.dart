import 'dart:io';
import 'package:flutter/foundation.dart'; // import compute
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../components/app_scaffold.dart';
import '../../components/widgets/empty_state.dart';
import '../../providers/core_providers.dart' as coreProviders;
import '../../utils/enhanced_pdf_utils.dart';
import '../../services/daos/debts_dao.dart';
import '../../services/daos/outbox_dao.dart';

class DebtsReportScreen extends ConsumerStatefulWidget {
  const DebtsReportScreen({super.key});

  @override
  ConsumerState<DebtsReportScreen> createState() => _DebtsReportScreenState();
}

class _DebtsReportScreenState extends ConsumerState<DebtsReportScreen> {
  final NumberFormat _currencyFmt = NumberFormat('#,##0', 'en_US');
  final DateFormat _dateLabelFormat = DateFormat('yyyy/MM/dd');

  DateTime? _fromDate;
  DateTime? _toDate;
  final TextEditingController _searchController = TextEditingController();

  bool _loading = false;

  final List<_DebtReportRow> _rows = [];
  double _totalDebt = 0;
  double _totalPaid = 0;
  double _totalRemaining = 0;

  @override
  void initState() {
    super.initState();
    _initializeDefaults();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeDefaults() async {
    final now = DateTime.now();
    _fromDate = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 30));
    _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);

    // ❌ تم إزالة التحميل التلقائي - المستخدم يضغط زر البحث
    // await _fetchReport();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initialDate = isFrom
        ? (_fromDate ?? DateTime.now())
        : (_toDate ?? DateTime.now());
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
      _fetchReport();
    }
  }

  Future<void> _fetchReport() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final db = ref.read(coreProviders.dbProvider);
      final outboxDao = OutboxDao(db);
      final debtDao = DebtsDao(db, outboxDao);

      // جلب البيانات الخام من DB (عملية سريعة نسبياً)
      final debts = await debtDao.list(includeDeleted: false);

      // تحويل لـ Maps للنقل للخلفية
      final rawDebts = debts.map((d) => d.toJson()).toList();

      // المعالجة الثقيلة في الخلفية
      final result = await compute(
        _processDebtsData,
        _DebtProcessParams(
          debts: rawDebts,
          fromDate: _fromDate,
          toDate: _toDate,
          searchQuery: _searchController.text.trim().toLowerCase(),
        ),
      );

      setState(() {
        _rows
          ..clear()
          ..addAll(result.rows);
        _totalDebt = result.totalDebt;
        _totalPaid = result.totalPaid;
        _totalRemaining = result.totalRemaining;
      });
    } catch (e) {
      debugPrint('Error loading debts report: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportPdf() async {
    // ... (نفس كود التصدير السابق بدون تغيير)
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
    final searchLabel = _searchController.text.isNotEmpty
        ? _searchController.text
        : 'الكل';

    pw.Widget buildReportHeader() {
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(vertical: 20, horizontal: 20),
        decoration: const pw.BoxDecoration(
          color: PdfColors.white,
          border: pw.Border(
            bottom: pw.BorderSide(color: PdfColors.grey300, width: 1),
          ),
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
                    font: fonts.bold,
                    fontSize: 18,
                    color: PdfColors.blue900,
                  ),
                ),
                if (hotelPhone.isNotEmpty)
                  pw.Text(
                    'هاتف: $hotelPhone',
                    style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                  ),
                if (hotelAddress.isNotEmpty)
                  pw.Text(
                    'عنوان: $hotelAddress',
                    style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                  ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  'تقرير الديون',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 16),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'من $fromLabel إلى $toLabel',
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 10,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
            if (logoImage != null)
              pw.Container(height: 50, width: 50, child: pw.Image(logoImage))
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
              pw.Text(
                'بحث عن: $searchLabel',
                style: pw.TextStyle(font: fonts.regular, fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    );

    final headers = [
      'التاريخ',
      'النزيل',
      'السبب',
      'الدين',
      'المدفوع',
      'المتبقي',
      'الحالة',
    ];

    final dataRows = <List<String>>[];
    for (final row in _rows) {
      dataRows.add([
        _dateLabelFormat.format(row.dateRecorded),
        row.guestName,
        row.reason,
        _currencyFmt.format(row.totalAmount),
        _currencyFmt.format(row.paidAmount),
        _currencyFmt.format(row.remainingAmount),
        if (row.isSettled) 'مسدد' else 'متبقي',
      ]);
    }

    final totalRow = [
      'الإجمالي',
      '',
      '',
      _currencyFmt.format(_totalDebt),
      _currencyFmt.format(_totalPaid),
      _currencyFmt.format(_totalRemaining),
      '',
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
            'صفحة ${context.pageNumber} من ${context.pagesCount} - ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}',
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 8,
              color: PdfColors.grey600,
            ),
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
              padding: const pw.EdgeInsets.symmetric(
                vertical: 8,
                horizontal: 16,
              ),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.blue800, width: 1),
                borderRadius: pw.BorderRadius.circular(4),
                color: PdfColors.blue50,
              ),
              child: pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text(
                    'المتبقي الإجمالي: ',
                    style: pw.TextStyle(font: fonts.bold, fontSize: 12),
                  ),
                  pw.Text(
                    _currencyFmt.format(_totalRemaining),
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 14,
                      color: PdfColors.red700,
                    ),
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
    final fileName = generateFileName('تقرير الديون');

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
      debugPrint('تعذر الحفظ المباشر: $e');
    }

    await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
  }

  @override
  Widget build(BuildContext context) {
    const double inputsHeight = 42;

    return AppScaffold(
      title: 'تقرير الديون',
      actions: const [],
      body: Column(
        children: [
          // فلاتر
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
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
                    // زر البحث
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
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Icon(Icons.search, size: 20),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // زر الطباعة
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
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Icon(Icons.picture_as_pdf, size: 20),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // الصف الثاني: بحث بالاسم
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: inputsHeight,
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            labelText: 'بحث باسم النزيل أو السبب',
                            labelStyle: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                            prefixIcon: const Icon(
                              Icons.search,
                              size: 16,
                              color: Colors.grey,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 0,
                            ),
                          ),
                          onSubmitted: (_) => _fetchReport(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // الملخص
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
                Expanded(
                  child: _buildSummaryItem(
                    'إجمالي الدين',
                    _totalDebt,
                    Colors.black,
                  ),
                ),
                Expanded(
                  child: _buildSummaryItem('المدفوع', _totalPaid, Colors.green),
                ),
                Expanded(
                  child: _buildSummaryItem(
                    'المتبقي',
                    _totalRemaining,
                    Colors.red,
                  ),
                ),
              ],
            ),
          ),

          // القائمة
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                ? const EmptyState(
                    title: 'لا توجد ديون',
                    message: 'لم يتم العثور على ديون تطابق الفلاتر.',
                    icon: Icons.check_circle_outline,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _rows.length,
                    itemBuilder: (context, index) {
                      return _buildDebtCard(_rows[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, double value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        Text(
          _currencyFmt.format(value),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
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
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildDebtCard(_DebtReportRow row) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                        row.guestName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${row.reason} ${row.bookingCode != '-' ? '(حجز: ${row.bookingCode})' : ''}',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _currencyFmt.format(row.totalAmount),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    if (row.remainingAmount > 0)
                      Text(
                        'متبقي: ${_currencyFmt.format(row.remainingAmount)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    else
                      const Text(
                        'مسدد بالكامل',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  row.isSettled ? 'الحالة: مسدد' : 'الحالة: غير مسدد',
                  style: TextStyle(
                    fontSize: 11,
                    color: row.isSettled ? Colors.green : Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _dateLabelFormat.format(row.dateRecorded),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DebtProcessParams {
  _DebtProcessParams({
    required this.debts,
    this.fromDate,
    this.toDate,
    required this.searchQuery,
  });
  final List<Map<String, dynamic>> debts;
  final DateTime? fromDate;
  final DateTime? toDate;
  final String searchQuery;
}

class _DebtsReportResult {
  _DebtsReportResult({
    required this.rows,
    required this.totalDebt,
    required this.totalPaid,
    required this.totalRemaining,
  });
  final List<_DebtReportRow> rows;
  final double totalDebt;
  final double totalPaid;
  final double totalRemaining;
}

class _DebtReportRow {
  _DebtReportRow({
    required this.dateRecorded,
    required this.guestName,
    required this.reason,
    required this.totalAmount,
    required this.paidAmount,
    required this.remainingAmount,
    required this.isSettled,
    required this.bookingCode,
  });

  final DateTime dateRecorded;
  final String guestName;
  final String reason;
  final double totalAmount;
  final double paidAmount;
  final double remainingAmount;
  final bool isSettled;
  final String bookingCode;
}

_DebtsReportResult _processDebtsData(_DebtProcessParams params) {
  final filteredRows = <_DebtReportRow>[];
  double tDebt = 0;
  double tPaid = 0;
  double tRemaining = 0;

  for (final data in params.debts) {
    // Parse fields
    DateTime dateRecorded = DateTime.now();
    if (data['dateRecorded'] != null) {
      try {
        dateRecorded = DateTime.parse(data['dateRecorded'].toString());
      } catch (_) {}
    } else if (data['date_recorded'] != null) {
      try {
        dateRecorded = DateTime.parse(data['date_recorded'].toString());
      } catch (_) {}
    }

    // Filter Date
    if (params.fromDate != null) {
      // ignore time for 'from' comparison (start of day)
      final start = DateTime(
        params.fromDate!.year,
        params.fromDate!.month,
        params.fromDate!.day,
      );
      if (dateRecorded.isBefore(start)) continue;
    }
    if (params.toDate != null) {
      if (dateRecorded.isAfter(params.toDate!)) continue;
    }

    final guestName = (data['guestName'] ?? data['guest_name'] ?? 'غير معروف')
        .toString();
    final debtReason = (data['debtReason'] ?? data['debt_reason'] ?? '-')
        .toString();

    // Filter Search
    if (params.searchQuery.isNotEmpty) {
      final matchesName = guestName.toLowerCase().contains(params.searchQuery);
      final matchesReason = debtReason.toLowerCase().contains(
        params.searchQuery,
      );
      if (!matchesName && !matchesReason) continue;
    }

    final amount = ((data['amount'] ?? 0) as num).toDouble();
    final paidAmount = ((data['paidAmount'] ?? data['paid_amount'] ?? 0) as num)
        .toDouble();
    final remaining = amount - paidAmount;
    final isSettled =
        (data['isSettled'] ?? data['is_settled']) == true ||
        (data['isSettled'] == 1);

    // Booking handling
    final bookingIdVal = data['bookingId'] ?? data['booking_id'];
    final String bookingCode = bookingIdVal != null
        ? bookingIdVal.toString()
        : '-';

    tDebt += amount;
    tPaid += paidAmount;
    tRemaining += remaining;

    filteredRows.add(
      _DebtReportRow(
        dateRecorded: dateRecorded,
        guestName: guestName,
        reason: debtReason,
        totalAmount: amount,
        paidAmount: paidAmount,
        remainingAmount: remaining,
        isSettled: isSettled,
        bookingCode: bookingCode,
      ),
    );
  }

  // Sort
  filteredRows.sort((a, b) => b.dateRecorded.compareTo(a.dateRecorded));

  return _DebtsReportResult(
    rows: filteredRows,
    totalDebt: tDebt,
    totalPaid: tPaid,
    totalRemaining: tRemaining,
  );
}
