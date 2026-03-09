import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' show PdfColor, PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../components/app_scaffold.dart';
import '../../providers/auth_provider.dart';
import '../../services/salary_entitlement_service.dart';
import '../../services/local_db.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/enhanced_pdf_utils.dart' show EnhancedPdfUtils, PdfColors;

/// شاشة التقرير التفصيلي للموظف
class EmployeeDetailReportScreen extends StatelessWidget {
  const EmployeeDetailReportScreen({
    super.key,
    required this.entitlement,
  });

  final SalaryEntitlement entitlement;

  @override
  Widget build(BuildContext context) {
    // حساب السحب والخصم
    final totalWithdrawals = entitlement.totalWithdrawals;
    final totalDeductions = entitlement.totalDeductions;
    final totalDeductionsAll = totalWithdrawals + totalDeductions;

    return AppScaffold(
      title: 'تقرير ${entitlement.employee.name}',
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // معلومات الموظف
          _buildInfoCard(totalWithdrawals, totalDeductions),
          const SizedBox(height: 12),
          
          // جدول المعاملات
          const Text(
            'سجل المعاملات:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          
          // عنوان الجدول
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Row(
              children: [
                Expanded(flex: 2, child: Text('التاريخ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('النوع', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('المبلغ', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                Expanded(flex: 3, child: Text('ملاحظات', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
              ],
            ),
          ),
          
          // صفوف المعاملات
          if (entitlement.transactions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('لا توجد معاملات', style: TextStyle(fontSize: 12))),
            )
          else
            ...entitlement.transactions.map(_buildTransactionRow),
          
          const Divider(),
          
          // الإجمالي
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                _summaryRow('إجمالي الاستحقاق', CurrencyFormatter.formatAmount(entitlement.totalEntitlement), Colors.green),
                _summaryRow('إجمالي السحب والخصم', '- ${CurrencyFormatter.formatAmount(totalDeductionsAll)}', Colors.red),
                const Divider(),
                _summaryRow(
                  'المتبقي',
                  CurrencyFormatter.formatAmount(entitlement.netEntitlement),
                  entitlement.netEntitlement >= 0 ? Colors.green : Colors.red,
                  bold: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(double totalWithdrawals, double totalDeductions) {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'الموظف: ${entitlement.employee.name}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _infoRow('المنصب', entitlement.employee.position),
            _infoRow('تاريخ التعيين', entitlement.employee.hireDate),
            _infoRow('الراتب الشهري', CurrencyFormatter.formatAmount(entitlement.basicSalary)),
            _infoRow('مدة العمل', '${entitlement.totalMonthsWorked} شهر'),
            const Divider(),
            _infoRow('سحب من راتب', CurrencyFormatter.formatAmount(totalWithdrawals), Colors.orange),
            _infoRow('خصم من راتب', CurrencyFormatter.formatAmount(totalDeductions), Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, [Color? color]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Text(value, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, Color color, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(fontSize: 12, color: color, fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildTransactionRow(SalaryTransaction tx) {
    Color txColor;
    String txType;
    
    switch (tx.type) {
      case 'سحب راتب':
      case 'رواتب':
        txColor = Colors.orange;
        txType = 'سحب';
      case 'سلفة':
        txColor = Colors.orange.shade700;
        txType = 'سلفة';
      case 'خصم راتب':
      case 'خصم':
        txColor = Colors.red;
        txType = 'خصم';
      case 'غياب':
        txColor = Colors.red.shade700;
        txType = 'غياب';
      default:
        txColor = Colors.grey;
        txType = tx.type;
    }
    
    final dateStr = tx.date.length > 10 ? tx.date.substring(0, 10) : tx.date;
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(dateStr, style: const TextStyle(fontSize: 11))),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: txColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(txType, style: TextStyle(fontSize: 10, color: txColor), textAlign: TextAlign.center),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              CurrencyFormatter.formatAmount(tx.amount),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: txColor),
            ),
          ),
          Expanded(flex: 3, child: Text(tx.note ?? '-', style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('فشل تحميل البيانات: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _canEdit() {
    final auth = ref.watch(authProvider);
    return (auth.currentUser?.isAdmin ?? false) ||
        (auth.currentUser?.permissions.contains('edit_salaries') ?? false) ||
        (auth.currentUser?.permissions.contains('all') ?? false);
  }

  void _openDetailReport(SalaryEntitlement ent) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EmployeeDetailReportScreen(entitlement: ent),
      ),
    );
  }

  /// تصدير تقرير استحقاقات الرواتب إلى PDF
  Future<void> _exportPdf() async {
    if (_entitlements.isEmpty) return;

    final fonts = await EnhancedPdfUtils.loadArabicFonts();
    final doc = pw.Document();
    final currencyFmt = NumberFormat('#,##0', 'en_US');

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
    final dateStr = DateFormat('yyyy/MM/dd').format(now);

    // رأس التقرير
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
                pw.Text(hotelName,
                    style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 18,
                        color: PdfColors.blue900)),
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
                pw.Text('تقرير استحقاقات الرواتب',
                    style: pw.TextStyle(font: fonts.bold, fontSize: 16)),
                pw.SizedBox(height: 4),
                pw.Text('تاريخ التقرير: $dateStr',
                    style: pw.TextStyle(
                        font: fonts.regular,
                        fontSize: 10,
                        color: PdfColors.grey700)),
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

    // بطاقة الملخص
    final summaryCard = pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(8),
        color: PdfColors.blue50,
      ),
      child: pw.Column(
        children: [
          pw.Text('ملخص الاستحقاقات',
              style: pw.TextStyle(
                  font: fonts.bold, fontSize: 14, color: PdfColors.blue800)),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _buildPdfSummaryItem('عدد الموظفين',
                  '${_summary['count'] ?? 0}', PdfColors.grey800, fonts.bold),
              _buildPdfSummaryItem(
                  'إجمالي الاستحقاقات',
                  currencyFmt.format(_summary['totalEntitlements'] ?? 0),
                  PdfColors.green700,
                  fonts.bold),
              _buildPdfSummaryItem(
                  'إجمالي السحبيات',
                  currencyFmt.format(_summary['totalWithdrawals'] ?? 0),
                  PdfColors.orange700,
                  fonts.bold),
              _buildPdfSummaryItem(
                  'صافي المستحقات',
                  currencyFmt.format(_summary['totalNet'] ?? 0),
                  PdfColors.blue700,
                  fonts.bold),
            ],
          ),
        ],
      ),
    );

    // جدول تفاصيل الموظفين
    final headers = ['الموظف', 'المنصب', 'الراتب', 'الاستحقاق', 'السحبيات', 'المتبقي'];
    final dataRows = <List<String>>[];

    for (final ent in _entitlements) {
      dataRows.add([
        ent.employee.name,
        ent.employee.position,
        currencyFmt.format(ent.basicSalary),
        currencyFmt.format(ent.totalEntitlement),
        currencyFmt.format(ent.totalWithdrawals),
        currencyFmt.format(ent.netEntitlement),
      ]);
    }

    // صف الإجمالي
    dataRows.add([
      'الإجمالي',
      '',
      currencyFmt.format(_entitlements.fold<double>(0, (s, e) => s + e.basicSalary)),
      currencyFmt.format(_summary['totalEntitlements'] ?? 0),
      currencyFmt.format(_summary['totalWithdrawals'] ?? 0),
      currencyFmt.format(_summary['totalNet'] ?? 0),
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
            'صفحة ${context.pageNumber} من ${context.pagesCount} - ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}',
            style: pw.TextStyle(
                font: fonts.regular, fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          buildReportHeader(),
          pw.SizedBox(height: 12),
          summaryCard,
          pw.SizedBox(height: 16),
          pw.Text('تفاصيل الموظفين',
              style: pw.TextStyle(font: fonts.bold, fontSize: 14)),
          pw.SizedBox(height: 8),
          EnhancedPdfUtils.buildProfessionalTable(
            headers: headers,
            data: dataRows,
            fonts: fonts,
            headerColor: PdfColors.blue800,
            alternateRowColor: PdfColors.grey100,
          ),
        ],
      ),
    );

    String generateFileName() {
      final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      return 'استحقاقات_الرواتب-$timestamp.pdf';
    }

    final pdfBytes = await doc.save();
    final fileName = generateFileName();

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

  pw.Widget _buildPdfSummaryItem(
      String label, String value, PdfColor color, pw.Font font) {
    return pw.Column(
      children: [
        pw.Text(label,
            style: pw.TextStyle(
                font: font, fontSize: 9, color: PdfColors.grey700)),
        pw.SizedBox(height: 2),
        pw.Text(value,
            style: pw.TextStyle(
                font: font, fontSize: 11, color: color, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'استحقاقات الرواتب',
      actions: [
        IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh)),
        if (_entitlements.isNotEmpty)
          IconButton(
            onPressed: _exportPdf,
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'تصدير PDF',
          ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _entitlements.isEmpty
              ? const Center(
                  child: Text(
                    'لا يوجد موظفين نشطين',
                    style: TextStyle(fontSize: 12),
                  ),
                )
              : RefreshIndicator(onRefresh: _loadData, child: _buildContent()),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildSummaryCard(),
        const SizedBox(height: 8),
        const Text(
          'تفاصيل الموظفين:',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ..._entitlements.map(_buildEmployeeCard),
      ],
    );
  }

  Widget _buildSummaryCard() {
    // الحساب المبسط: سحب + خصم = المتبقي
    final totalWithdrawals = _summary['totalWithdrawals'] ?? 0.0;
    final totalDeductions = _summary['totalDeductions'] ?? 0.0;
    
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ملخص الاستحقاقات',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _row('عدد الموظفين', '${_summary['count'] ?? 0}'),
            _row(
              'إجمالي الاستحقاقات',
              CurrencyFormatter.formatAmount(
                _summary['totalEntitlements'] ?? 0,
              ),
              Colors.green,
            ),
            const Divider(height: 16),
            // سحب من راتب (سحب + رواتب + سلفة)
            _row(
              'سحب من راتب',
              '- ${CurrencyFormatter.formatAmount(totalWithdrawals)}',
              Colors.orange,
            ),
            // خصم من راتب (خصم + غياب)
            _row(
              'خصم من راتب',
              '- ${CurrencyFormatter.formatAmount(totalDeductions)}',
              Colors.red,
            ),
            const Divider(),
            _row(
              'المتبقي',
              CurrencyFormatter.formatAmount(_summary['totalNet'] ?? 0),
              Colors.blue.shade700,
              true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, [Color? color, bool bold = false]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeCard(SalaryEntitlement ent) {
    final isPositive = ent.netEntitlement >= 0;
    final canEdit = _canEdit();
    
    // الحساب المبسط: سحب + خصم
    final totalWithdrawals = ent.totalWithdrawals;
    final totalDeductions = ent.totalDeductions;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        dense: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        title: Text(
          ent.employee.name,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'المتبقي: ${CurrencyFormatter.formatAmount(ent.netEntitlement)}',
          style: TextStyle(
            fontSize: 12,
            color: isPositive ? Colors.green : Colors.red,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // زر التقرير التفصيلي
            IconButton(
              icon: const Icon(Icons.receipt_long, color: Colors.green, size: 20),
              onPressed: () => _openDetailReport(ent),
              tooltip: 'تقرير تفصيلي',
            ),
            // زر التعديل
            if (canEdit)
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                onPressed: () => _showEditDialog(ent),
                tooltip: 'تعديل',
              ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _row('تاريخ التعيين', _formatDate(ent.hireDate)),
                _row('مدة العمل', '${ent.totalMonthsWorked} شهر'),
                _row(
                  'الراتب الشهري',
                  CurrencyFormatter.formatAmount(ent.basicSalary),
                ),
                const Divider(),
                _row(
                  'إجمالي الاستحقاق',
                  CurrencyFormatter.formatAmount(ent.totalEntitlement),
                  Colors.green,
                ),
                const SizedBox(height: 4),
                // سحب من راتب
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _row(
                    'سحب من راتب',
                    '- ${CurrencyFormatter.formatAmount(totalWithdrawals)}',
                    Colors.orange,
                  ),
                ),
                const SizedBox(height: 4),
                // خصم من راتب
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _row(
                    'خصم من راتب',
                    '- ${CurrencyFormatter.formatAmount(totalDeductions)}',
                    Colors.red,
                  ),
                ),
                const Divider(),
                _row(
                  'المتبقي',
                  CurrencyFormatter.formatAmount(ent.netEntitlement),
                  isPositive ? Colors.green : Colors.red,
                  true,
                ),
                if (ent.transactions.isNotEmpty) ...[
                  const Divider(),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'آخر المعاملات:',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  ...ent.transactions.take(5).map(_buildTransactionRow),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionRow(SalaryTransaction tx) {
    Color txColor;
    IconData txIcon;
    
    switch (tx.type) {
      case 'سحب راتب':
      case 'رواتب':
        txColor = Colors.orange;
        txIcon = Icons.money_off;
      case 'سلفة':
        txColor = Colors.orange.shade700;
        txIcon = Icons.account_balance_wallet;
      case 'خصم راتب':
      case 'خصم':
        txColor = Colors.red;
        txIcon = Icons.remove_circle;
      case 'غياب':
        txColor = Colors.red.shade700;
        txIcon = Icons.event_busy;
      default:
        txColor = Colors.grey;
        txIcon = Icons.swap_horiz;
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(txIcon, size: 14, color: txColor),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              tx.type,
              style: TextStyle(fontSize: 11, color: txColor),
            ),
          ),
          Text(
            '- ${CurrencyFormatter.formatAmount(tx.amount)}',
            style: const TextStyle(fontSize: 11),
          ),
          const SizedBox(width: 8),
          Text(
            tx.date.length > 10 ? tx.date.substring(0, 10) : tx.date,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditDialog(SalaryEntitlement ent) async {
    final salaryCtrl = TextEditingController(
      text: ent.basicSalary.toString(),
    );
    final nameCtrl = TextEditingController(text: ent.employee.name);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تعديل بيانات ${ent.employee.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'اسم الموظف',
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: salaryCtrl,
              decoration: const InputDecoration(
                labelText: 'الراتب الشهري',
                prefixIcon: Icon(Icons.attach_money),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final newSalary = double.tryParse(salaryCtrl.text) ?? 0;
    if (newSalary <= 0) return;

    // تحديث الراتب في قاعدة البيانات
    final db = DatabaseManager.instance;
    await (db.update(db.employees)..where((t) => t.id.equals(ent.employee.id)))
        .write(
      EmployeesCompanion(
        basicSalary: Value(newSalary.toInt()),  // ⭐ int
        name: Value(nameCtrl.text.trim()),
      ),
    );

    await _loadData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تحديث بيانات الموظف'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
