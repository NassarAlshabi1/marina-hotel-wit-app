import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../components/app_scaffold.dart';
import '../../services/salary_entitlement_service.dart';
import '../../services/local_db.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/enhanced_pdf_utils.dart';

class SalaryEntitlementsScreen extends ConsumerStatefulWidget {
  const SalaryEntitlementsScreen({super.key});

  @override
  ConsumerState<SalaryEntitlementsScreen> createState() =>
      _SalaryEntitlementsScreenState();
}

class _SalaryEntitlementsScreenState
    extends ConsumerState<SalaryEntitlementsScreen> {
  late SalaryEntitlementService _service;
  List<SalaryEntitlement> _entitlements = [];
  Map<String, dynamic> _summary = {};
  bool _isLoading = true;
  
  final NumberFormat _currencyFmt = NumberFormat('#,##0', 'en_US');
  final DateFormat _dateFormat = DateFormat('yyyy/MM/dd');

  @override
  void initState() {
    super.initState();
    _service = SalaryEntitlementService(DatabaseManager.instance);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _summary = await _service.getSummary();
      _entitlements = _summary['entitlements'] as List<SalaryEntitlement>;
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تحميل البيانات: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _exportPdf() async {
    if (_entitlements.isEmpty) return;

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

    final now = DateTime.now();
    final reportDate = _dateFormat.format(now);

    // بناء ترويسة التقرير
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
                  'تقرير استحقاقات الرواتب',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 16),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'تاريخ التقرير: $reportDate',
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 10,
                    color: PdfColors.grey700,
                  ),
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

    // بناء جدول الاستحقاقات
    final headers = [
      '#',
      'الموظف',
      'تاريخ التعيين',
      'أيام العمل',
      'الراتب',
      'المستحق',
      'المسحوب',
      'الخصومات',
      'المتبقي',
    ];

    final dataRows = <List<String>>[];
    for (var i = 0; i < _entitlements.length; i++) {
      final ent = _entitlements[i];
      dataRows.add([
        '${i + 1}',
        ent.employeeName,
        _dateFormat.format(ent.hireDate),
        '${ent.daysWorked}',
        _currencyFmt.format(ent.basicSalary),
        _currencyFmt.format(ent.totalEntitlement),
        _currencyFmt.format(ent.totalWithdrawals),
        _currencyFmt.format(ent.totalDeductions),
        _currencyFmt.format(ent.netEntitlement),
      ]);
    }

    // صف الإجمالي
    dataRows.add([
      '',
      'الإجمالي',
      '',
      '',
      '',
      _currencyFmt.format(_summary['totalEntitlements'] ?? 0),
      _currencyFmt.format(_summary['totalWithdrawals'] ?? 0),
      _currencyFmt.format(_summary['totalDeductions'] ?? 0),
      _currencyFmt.format(_summary['totalNet'] ?? 0),
    ]);

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
              font: fonts.regular,
              fontSize: 8,
              color: PdfColors.grey600,
            ),
          ),
        ),
        build: (context) => [
          buildReportHeader(),
          pw.SizedBox(height: 16),
          // ملخص عام
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: PdfColors.blue200),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _buildPdfSummaryItem(
                  'عدد الموظفين',
                  '${_summary['employeeCount'] ?? 0}',
                  PdfColors.blue800,
                  fonts,
                ),
                _buildPdfSummaryItem(
                  'إجمالي المستحق',
                  _currencyFmt.format(_summary['totalEntitlements'] ?? 0),
                  PdfColors.green,
                  fonts,
                ),
                _buildPdfSummaryItem(
                  'إجمالي المسحوب',
                  _currencyFmt.format(_summary['totalWithdrawals'] ?? 0),
                  PdfColors.orange,
                  fonts,
                ),
                _buildPdfSummaryItem(
                  'صافي المستحق',
                  _currencyFmt.format(_summary['totalNet'] ?? 0),
                  PdfColors.red,
                  fonts,
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          // شرح طريقة الحساب
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'طريقة الحساب:',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 10),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  '• الراتب اليومي = الراتب الأساسي ÷ 30 يوم',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 9),
                ),
                pw.Text(
                  '• المستحق = الراتب اليومي × عدد أيام العمل',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 9),
                ),
                pw.Text(
                  '• المتبقي = المستحق - (المسحوبات + الخصومات)',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 9),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          // جدول البيانات
          EnhancedPdfUtils.buildProfessionalTable(
            headers: headers,
            data: dataRows,
            fonts: fonts,
            headerColor: PdfColors.blue800,
            alternateRowColor: PdfColors.grey100,
            cellAlignment: pw.Alignment.centerRight,
          ),
        ],
      ),
    );

    // إضافة صفحة تفاصيل لكل موظف
    for (final ent in _entitlements) {
      if (ent.transactions.isNotEmpty) {
        doc.addPage(
          pw.Page(
            textDirection: pw.TextDirection.rtl,
            theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(20),
            build: (context) => [
              pw.Text(
                'تفاصيل الموظف: ${ent.employeeName}',
                style: pw.TextStyle(font: fonts.bold, fontSize: 16),
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'تاريخ التعيين: ${_dateFormat.format(ent.hireDate)}',
                    style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                  ),
                  pw.Text(
                    'أيام العمل: ${ent.daysWorked} يوم',
                    style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                  ),
                  pw.Text(
                    'الراتب: ${_currencyFmt.format(ent.basicSalary)}',
                    style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue50,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children: [
                    _buildPdfSummaryItem(
                      'المستحق',
                      _currencyFmt.format(ent.totalEntitlement),
                      PdfColors.green,
                      fonts,
                    ),
                    _buildPdfSummaryItem(
                      'المسحوب',
                      _currencyFmt.format(ent.totalWithdrawals),
                      PdfColors.orange,
                      fonts,
                    ),
                    _buildPdfSummaryItem(
                      'الخصومات',
                      _currencyFmt.format(ent.totalDeductions),
                      PdfColors.red,
                      fonts,
                    ),
                    _buildPdfSummaryItem(
                      'المتبقي',
                      _currencyFmt.format(ent.netEntitlement),
                      ent.netEntitlement >= 0 ? PdfColors.blue : PdfColors.red,
                      fonts,
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Text(
                'سجل المعاملات:',
                style: pw.TextStyle(font: fonts.bold, fontSize: 12),
              ),
              pw.SizedBox(height: 8),
              EnhancedPdfUtils.buildProfessionalTable(
                headers: ['التاريخ', 'النوع', 'الإجراء', 'المبلغ', 'ملاحظة'],
                data: ent.transactions.map((tx) => [
                  tx.date.length > 10 ? tx.date.substring(0, 10) : tx.date,
                  tx.type,
                  tx.action,
                  _currencyFmt.format(tx.amount),
                  tx.note ?? '-',
                ]).toList(),
                fonts: fonts,
                headerColor: PdfColors.indigo,
                alternateRowColor: PdfColors.grey100,
              ),
            ],
          ),
        );
      }
    }

    final pdfBytes = await doc.save();
    final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final fileName = 'salary-entitlements-$timestamp.pdf';

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
                label: 'مشاركة',
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
      debugPrint('Direct save failed: $e');
    }

    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: fileName,
    );
  }

  pw.Widget _buildPdfSummaryItem(
    String label,
    String value,
    PdfColor color,
    ArabicFonts fonts,
  ) {
    return pw.Column(
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(font: fonts.regular, fontSize: 9),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          value,
          style: pw.TextStyle(
            font: fonts.bold,
            fontSize: 11,
            color: color,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'استحقاقات الرواتب',
      actions: [
        IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh)),
        if (!_isLoading && _entitlements.isNotEmpty)
          IconButton(
            onPressed: _exportPdf,
            icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
          ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _entitlements.isEmpty
              ? const Center(
                  child: Text(
                    'لا يوجد موظفين نشطين',
                    style: TextStyle(fontSize: 14),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: _buildContent(),
                ),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildSummaryCard(),
        const SizedBox(height: 12),
        _buildFormulaCard(),
        const SizedBox(height: 12),
        const Text(
          'تفاصيل الموظفين:',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ..._entitlements.map(_buildEmployeeCard),
      ],
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      color: Colors.blue.shade50,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.summarize, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'ملخص الاستحقاقات',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildSummaryItem(
                  'عدد الموظفين',
                  '${_summary['employeeCount'] ?? 0}',
                  Icons.people,
                  Colors.blue,
                ),
                _buildSummaryItem(
                  'إجمالي المستحق',
                  CurrencyFormatter.formatAmount(_summary['totalEntitlements'] ?? 0),
                  Icons.account_balance_wallet,
                  Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildSummaryItem(
                  'إجمالي المسحوبات',
                  CurrencyFormatter.formatAmount(_summary['totalWithdrawals'] ?? 0),
                  Icons.money_off,
                  Colors.orange,
                ),
                _buildSummaryItem(
                  'إجمالي الخصومات',
                  CurrencyFormatter.formatAmount(_summary['totalDeductions'] ?? 0),
                  Icons.remove_circle,
                  Colors.red,
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.calculate, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'صافي المستحقات: ',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
                Text(
                  CurrencyFormatter.formatAmount(_summary['totalNet'] ?? 0),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: (_summary['totalNet'] ?? 0) >= 0
                        ? Colors.green[700]
                        : Colors.red[700],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormulaCard() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'طريقة الحساب:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildFormulaRow('الراتب اليومي', 'الراتب الأساسي ÷ 30 يوم'),
            _buildFormulaRow('المستحق', 'الراتب اليومي × أيام العمل'),
            _buildFormulaRow('المتبقي', 'المستحق - (المسحوبات + الخصومات)'),
          ],
        ),
      ),
    );
  }

  Widget _buildFormulaRow(String label, String formula) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$label = ',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
          Text(
            formula,
            style: TextStyle(fontSize: 11, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeCard(SalaryEntitlement ent) {
    final isPositive = ent.netEntitlement >= 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ExpansionTile(
        dense: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.all(12),
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: isPositive ? Colors.green[100] : Colors.red[100],
              child: Icon(
                isPositive ? Icons.person : Icons.warning,
                size: 18,
                color: isPositive ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ent.employeeName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${ent.totalMonthsWorked} شهر • ${ent.daysWorked} يوم',
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isPositive ? Colors.green[50] : Colors.red[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isPositive ? Colors.green[200]! : Colors.red[200]!,
            ),
          ),
          child: Text(
            CurrencyFormatter.formatAmount(ent.netEntitlement),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isPositive ? Colors.green[700] : Colors.red[700],
            ),
          ),
        ),
        children: [
          Column(
            children: [
              // معلومات أساسية
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildInfoItem(
                      'تاريخ التعيين',
                      _dateFormat.format(ent.hireDate),
                    ),
                    _buildInfoItem(
                      'الراتب الشهري',
                      CurrencyFormatter.formatAmount(ent.basicSalary),
                    ),
                    _buildInfoItem(
                      'اليومي',
                      CurrencyFormatter.formatAmount(ent.dailyRate),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // تفاصيل الحساب
              Row(
                children: [
                  Expanded(
                    child: _buildAmountItem(
                      'المستحق',
                      ent.totalEntitlement,
                      Colors.green,
                      Icons.account_balance_wallet,
                    ),
                  ),
                  Expanded(
                    child: _buildAmountItem(
                      'المسحوب',
                      ent.totalWithdrawals,
                      Colors.orange,
                      Icons.money_off,
                    ),
                  ),
                  Expanded(
                    child: _buildAmountItem(
                      'الخصومات',
                      ent.totalDeductions,
                      Colors.red,
                      Icons.remove_circle,
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),
              // المتبقي
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isPositive ? Colors.green[50] : Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isPositive ? Icons.check_circle : Icons.warning,
                      color: isPositive ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'المتبقي: ${CurrencyFormatter.formatAmount(ent.netEntitlement)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isPositive ? Colors.green[700] : Colors.red[700],
                      ),
                    ),
                  ],
                ),
              ),
              // آخر المعاملات
              if (ent.transactions.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(),
                const Row(
                  children: [
                    Icon(Icons.history, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'آخر المعاملات:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...ent.transactions.take(5).map(
                  (tx) => Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: tx.type == 'سحب'
                          ? Colors.orange[50]
                          : Colors.red[50],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: tx.type == 'سحب'
                                ? Colors.orange[100]
                                : Colors.red[100],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            tx.type,
                            style: TextStyle(
                              fontSize: 10,
                              color: tx.type == 'سحب'
                                  ? Colors.orange[800]
                                  : Colors.red[800],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tx.action,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        Text(
                          CurrencyFormatter.formatAmount(tx.amount),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          tx.date.length > 10 ? tx.date.substring(0, 10) : tx.date,
                          style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 9, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildAmountItem(
    String label,
    double amount,
    Color color,
    IconData icon,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 4),
          Text(
            CurrencyFormatter.formatAmount(amount),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 8, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}
