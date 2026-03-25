import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat, PdfColors;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart' as drift;

import '../../components/app_scaffold.dart';
import '../../components/widgets/empty_state.dart';
import '../../providers/core_providers.dart' as coreProviders;
import '../../services/local_db.dart';
import '../../utils/enhanced_pdf_utils.dart';

class SalaryWithdrawalsReportScreen extends ConsumerStatefulWidget {
  const SalaryWithdrawalsReportScreen({super.key});

  @override
  ConsumerState<SalaryWithdrawalsReportScreen> createState() =>
      _SalaryWithdrawalsReportScreenState();
}

class _SalaryWithdrawalsReportScreenState
    extends ConsumerState<SalaryWithdrawalsReportScreen> {
  final NumberFormat _currencyFmt = NumberFormat('#,##0', 'en_US');
  final DateFormat _dateLabelFormat = DateFormat('yyyy/MM/dd');

  DateTime? _fromDate;
  DateTime? _toDate;
  bool _loading = false;

  final List<SalaryWithdrawalRow> _rows = [];
  double _totalAmount = 0;
  double _totalWithdrawals = 0;
  double _totalDeductions = 0;

  // قائمة الموظفين
  List<EmployeeItem> _employees = [];
  EmployeeItem? _selectedEmployee;

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _initializeDefaults();
    }
  }

  Future<void> _initializeDefaults() async {
    final now = DateTime.now();
    // من أول الشهر الحالي
    _fromDate = DateTime(now.year, now.month, 1, 0, 0, 0);
    // إلى آخر الشهر الحالي
    _toDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    // جلب قائمة الموظفين
    await _loadEmployees();
    await _fetchReport();
  }

  Future<void> _loadEmployees() async {
    try {
      final db = ref.read(coreProviders.dbProvider);
      final employees = await (db.select(db.employees)
            ..where((t) => t.status.equals('active'))
            ..orderBy([(t) => drift.OrderingTerm.asc(t.name)]))
          .get();

      setState(() {
        _employees = [
          EmployeeItem(id: null, name: 'جميع الموظفين'),
          ...employees.map((e) => EmployeeItem(id: e.id, name: e.name)),
        ];
        _selectedEmployee = _employees.first;
      });
    } catch (e) {
      debugPrint('Error loading employees: $e');
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
      _fetchReport();
    }
  }

  Future<void> _fetchReport() async {
    if (_loading) return;
    setState(() {
      _loading = true;
    });
    try {
      final db = ref.read(coreProviders.dbProvider);

      // جلب جميع سحبيات الرواتب
      final query = db.select(db.salaryWithdrawals);

      // تطبيق فلتر التاريخ
      query.where((t) {
        final conditions = <drift.Expression<bool>>[];

        if (_fromDate != null) {
          final fromStr = DateFormat('yyyy-MM-dd').format(_fromDate!);
          conditions.add(t.date.isBiggerOrEqualValue(fromStr));
        }
        if (_toDate != null) {
          final toStr = DateFormat('yyyy-MM-dd').format(_toDate!);
          conditions.add(t.date.isSmallerOrEqualValue(toStr));
        }

        // فلتر الموظف
        if (_selectedEmployee?.id != null) {
          conditions.add(t.employeeId.equals(_selectedEmployee!.id!));
        }

        if (conditions.isEmpty) {
          return const drift.Constant(true);
        }
        return drift.Expression.combine(conditions, drift.and);
      });

      query.orderBy([(t) => drift.OrderingTerm.desc(t.date)]);

      final withdrawals = await query.get();

      // جلب أسماء الموظفين
      final employeeIds = withdrawals.map((w) => w.employeeId).toSet().toList();
      Map<int, String> employeeNames = {};

      if (employeeIds.isNotEmpty) {
        final employees = await (db.select(db.employees)
              ..where((t) => t.id.isIn(employeeIds)))
            .get();
        employeeNames = {
          for (final e in employees) e.id: e.name,
        };
      }

      // معالجة البيانات
      final rows = <SalaryWithdrawalRow>[];
      double totalAmount = 0;
      double totalWithdrawals = 0;
      double totalDeductions = 0;

      for (final w in withdrawals) {
        final row = SalaryWithdrawalRow(
          employeeId: w.employeeId,
          employeeName: employeeNames[w.employeeId] ?? 'غير معروف',
          action: w.action,
          amount: w.amount,
          date: _parseDate(w.date),
          note: w.note,
        );

        rows.add(row);
        totalAmount += w.amount;

        if (w.action.contains('سحب')) {
          totalWithdrawals += w.amount;
        } else if (w.action.contains('خصم')) {
          totalDeductions += w.amount;
        }
      }

      setState(() {
        _rows
          ..clear()
          ..addAll(rows);
        _totalAmount = totalAmount;
        _totalWithdrawals = totalWithdrawals;
        _totalDeductions = totalDeductions;
      });
    } catch (e) {
      debugPrint('Error loading salary withdrawals report: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  DateTime _parseDate(String dateStr) {
    try {
      String val = dateStr.trim();
      val = val.length > 10 ? val.replaceFirst(' ', 'T') : '${val}T00:00:00';
      return DateTime.parse(val);
    } catch (_) {
      return DateTime.now();
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
    final employeeLabel = _selectedEmployee?.name ?? 'جميع الموظفين';

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
                  'تقرير سحبيات الرواتب',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 16),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'الموظف: $employeeLabel',
                  style: pw.TextStyle(
                      font: fonts.bold, fontSize: 11, color: PdfColors.blue700),
                ),
                pw.SizedBox(height: 2),
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

    final headers = ['التاريخ', 'الموظف', 'النوع', 'المبلغ', 'الملاحظة'];

    final dataRows = <List<String>>[];
    for (final row in _rows) {
      dataRows.add([
        _dateLabelFormat.format(row.date),
        row.employeeName,
        row.action,
        EnhancedPdfUtils.formatNumber(row.amount),
        row.note ?? '-',
      ]);
    }

    // صف الإجمالي
    dataRows.add([
      'الإجمالي',
      '',
      '',
      EnhancedPdfUtils.formatNumber(_totalAmount),
      '',
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
                font: fonts.regular, fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          buildReportHeader(),
          pw.SizedBox(height: 12),
          // ملخص
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
                pw.Column(
                  children: [
                    pw.Text('إجمالي السحوبات',
                        style: pw.TextStyle(font: fonts.regular, fontSize: 10)),
                    pw.Text(EnhancedPdfUtils.formatNumber(_totalWithdrawals),
                        style: pw.TextStyle(
                            font: fonts.bold, fontSize: 12, color: PdfColors.red)),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text('إجمالي الخصومات',
                        style: pw.TextStyle(font: fonts.regular, fontSize: 10)),
                    pw.Text(EnhancedPdfUtils.formatNumber(_totalDeductions),
                        style: pw.TextStyle(
                            font: fonts.bold, fontSize: 12, color: PdfColors.orange)),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text('الإجمالي العام',
                        style: pw.TextStyle(font: fonts.regular, fontSize: 10)),
                    pw.Text(EnhancedPdfUtils.formatNumber(_totalAmount),
                        style: pw.TextStyle(
                            font: fonts.bold, fontSize: 14, color: PdfColors.blue800)),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
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

    final pdfBytes = await doc.save();
    final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final employeeSuffix = _selectedEmployee?.id != null
        ? '-${_selectedEmployee!.name.replaceAll(' ', '-')}'
        : '-all';
    final fileName = 'salary-withdrawals$employeeSuffix-$timestamp.pdf';

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
      debugPrint('Direct save failed: $e');
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
      title: 'تقرير سحبيات الرواتب',
      body: Column(
        children: [
          // فلتر التاريخ والموظف
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
                // صف التاريخ والأزرار
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
                        onPressed: _loading ? null : _fetchReport,
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
                // فلتر الموظف
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: inputsHeight,
                        child: DropdownButtonFormField<EmployeeItem?>(
                          value: _selectedEmployee,
                          decoration: InputDecoration(
                            labelText: 'الموظف',
                            labelStyle: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
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
                          items: _employees.map((emp) {
                            return DropdownMenuItem<EmployeeItem?>(
                              value: emp,
                              child: Text(
                                emp.name,
                                style: const TextStyle(fontSize: 12),
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedEmployee = value;
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
          // ملخص الإحصائيات
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryItem(
                  label: 'السحوبات',
                  value: _currencyFmt.format(_totalWithdrawals),
                  color: Colors.red,
                ),
                _buildSummaryItem(
                  label: 'الخصومات',
                  value: _currencyFmt.format(_totalDeductions),
                  color: Colors.orange,
                ),
                _buildSummaryItem(
                  label: 'الإجمالي',
                  value: _currencyFmt.format(_totalAmount),
                  color: Colors.blue[800]!,
                ),
                _buildSummaryItem(
                  label: 'عدد السجلات',
                  value: '${_rows.length}',
                  color: Colors.grey[700]!,
                ),
              ],
            ),
          ),
          // قائمة البيانات
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? const EmptyState(
                        title: 'لا توجد بيانات',
                        message: 'لم يتم العثور على سحبيات رواتب ضمن النطاق المحدد.',
                        icon: Icons.money_off,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _rows.length,
                        itemBuilder: (context, index) {
                          final row = _rows[index];
                          return _buildWithdrawalCard(row);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: color,
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

  Widget _buildWithdrawalCard(SalaryWithdrawalRow row) {
    final isWithdrawal = row.action.contains('سحب');
    final actionColor = isWithdrawal ? Colors.red : Colors.orange;

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
                        row.employeeName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: actionColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: actionColor.withOpacity(0.3)),
                        ),
                        child: Text(
                          row.action,
                          style: TextStyle(
                            fontSize: 11,
                            color: actionColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _currencyFmt.format(row.amount),
                  style: TextStyle(
                    color: actionColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            if (row.note != null && row.note!.isNotEmpty) ...[
              const Divider(height: 16),
              Row(
                children: [
                  Icon(Icons.note, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      row.note!,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.calendar_today, size: 12, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Text(
                  _dateLabelFormat.format(row.date),
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

/// عنصر الموظف للقائمة المنسدلة
class EmployeeItem {
  EmployeeItem({required this.id, required this.name});

  final int? id;
  final String name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmployeeItem && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class SalaryWithdrawalRow {
  SalaryWithdrawalRow({
    this.employeeId,
    required this.employeeName,
    required this.action,
    required this.amount,
    required this.date,
    this.note,
  });

  final int? employeeId;
  final String employeeName;
  final String action;
  final double amount;
  final DateTime date;
  final String? note;
}
