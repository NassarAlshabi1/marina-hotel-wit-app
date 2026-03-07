import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
import '../../services/local_db.dart';
import '../../services/report_cache_service.dart';
import '../../utils/enhanced_pdf_utils.dart';

/// ⭐ شاشة تقرير سحبيات الرواتب
class SalaryWithdrawalsReportScreen extends ConsumerStatefulWidget {
  const SalaryWithdrawalsReportScreen({super.key});

  @override
  ConsumerState<SalaryWithdrawalsReportScreen> createState() =>
      _SalaryWithdrawalsReportScreenState();
}

class _SalaryWithdrawalsReportScreenState
    extends ConsumerState<SalaryWithdrawalsReportScreen> {
  final NumberFormat _currencyFmt = NumberFormat('#,##0', 'en_US');
  final DateFormat _dateFormat = DateFormat('yyyy/MM/dd');

  // الفلاتر
  DateTime? _fromDate;
  DateTime? _toDate;
  int? _selectedEmployeeId; // null = الكل

  // البيانات
  List<Employee> _employees = [];
  List<_SalaryWithdrawalRow> _rows = [];
  double _totalAmount = 0;

  bool _loading = false;
  bool _isFromCache = false;

  /// ⭐ أنواع مصروفات الرواتب المدعومة (مطابقة مرنة)
  static const Set<String> _salaryTypes = {
    'salary', 'salaries', 'salary_withdrawal', 'salary-withdrawal',
    'salary_deduction', 'salary-deduction', 'salary payment', 'salary_payment',
    'employee salary', 'employee_salary', 'رواتب', 'راتب',
    'سحب راتب', 'سحب من الراتب', 'خصم راتب', 'خصم من الراتب',
    'صرف راتب', 'سلفة راتب', 'سلفة', 'خصم',
  };

  @override
  void initState() {
    super.initState();
    _initializeDefaults();
  }

  Future<void> _initializeDefaults() async {
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, 1); // بداية الشهر
    _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);

    await _loadEmployees();
    await _fetchReport();
  }

  /// ⭐ تحميل قائمة الموظفين
  Future<void> _loadEmployees() async {
    try {
      final db = ref.read(core_providers.dbProvider);
      final employees = await (db.select(db.employees)
            ..where((t) => t.status.equals('active')))
          .get();
      setState(() {
        _employees = employees;
      });
    } catch (e) {
      debugPrint('Error loading employees: $e');
    }
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom
        ? (_fromDate ?? DateTime.now())
        : (_toDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
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

  /// ⭐ معاملات الـ cache
  Map<String, dynamic> _getCacheParams() {
    return {
      'fromDate': _fromDate?.toIso8601String(),
      'toDate': _toDate?.toIso8601String(),
      'employeeId': _selectedEmployeeId,
    };
  }

  /// ⭐ جلب البيانات
  Future<void> _fetchReport() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _isFromCache = false;
    });

    try {
      final db = ref.read(core_providers.dbProvider);

      // محاولة الحصول على البيانات من الـ cache
      final cachedResult = await ReportCacheService.instance.get<
          _SalaryWithdrawalResult>(
        'salary_withdrawals_report',
        _getCacheParams(),
        _SalaryWithdrawalResult.fromJson,
      );

      if (cachedResult != null) {
        setState(() {
          _rows = cachedResult.rows;
          _totalAmount = cachedResult.totalAmount;
          _isFromCache = true;
        });
        return;
      }

      // بناء الاستعلام
      final fromStr = _fromDate != null
          ? DateFormat('yyyy-MM-dd').format(_fromDate!)
          : null;
      final toStr = _toDate != null
          ? DateFormat('yyyy-MM-dd').format(_toDate!)
          : null;

      // جلب المصروفات
      final expenses = await (db.select(db.expenses)
            ..where((t) => t.deletedAt.isNull()))
          .get();

      // جلب أسماء الموظفين
      final employeeMap = <int, String>{};
      for (final e in _employees) {
        employeeMap[e.id] = e.name;
      }

      // تحويل البيانات للمعالجة
      final expenseMaps = expenses.map((e) => e.toJson()).toList();

      // المعالجة في الخلفية
      final result = await compute(
        _processSalaryData,
        _SalaryProcessParams(
          expenses: expenseMaps,
          employeeMap: employeeMap,
          salaryTypes: _salaryTypes.toList(),
          fromDate: fromStr,
          toDate: toStr,
          selectedEmployeeId: _selectedEmployeeId,
        ),
      );

      // تخزين في cache
      await ReportCacheService.instance.set(
        'salary_withdrawals_report',
        _getCacheParams(),
        result,
        (r) => r.toJson(),
      );

      setState(() {
        _rows = result.rows;
        _totalAmount = result.totalAmount;
      });
    } catch (e) {
      debugPrint('Error fetching salary withdrawals: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  /// ⭐ تصدير PDF
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

    final employeeLabel = _selectedEmployeeId == null
        ? 'الكل'
        : _employees
            .firstWhere((e) => e.id == _selectedEmployeeId,
                orElse: () => _employees.first)
            .name;

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
                pw.Text('تقرير سحبيات الرواتب',
                    style: pw.TextStyle(font: fonts.bold, fontSize: 16)),
                pw.SizedBox(height: 4),
                pw.Text('من $fromLabel إلى $toLabel',
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

    // معلومات الفلترة
    final metaInfo = EnhancedPdfUtils.buildInfoCard(
      title: 'معايير التقرير',
      fonts: fonts,
      content: [
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('الموظف: $employeeLabel',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 10)),
              pw.Text('عدد السجلات: ${_rows.length}',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 10)),
            ],
          ),
        ),
      ],
    );

    // جدول البيانات
    final headers = ['التاريخ', 'الموظف', 'الملاحظات', 'المبلغ'];
    final dataRows = <List<String>>[];

    for (final row in _rows) {
      dataRows.add([
        _dateFormat.format(row.date),
        row.employeeName,
        if (row.notes.isNotEmpty) row.notes else '-',
        _currencyFmt.format(row.amount),
      ]);
    }

    // صف الإجمالي
    dataRows.add([
      'الإجمالي',
      '',
      '',
      _currencyFmt.format(_totalAmount),
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
                        color: PdfColors.red700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    String generateFileName() {
      final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      return 'سحبيات_الرواتب-$timestamp.pdf';
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

  @override
  Widget build(BuildContext context) {
    const double inputsHeight = 42;

    return AppScaffold(
      title: 'تقرير سحبيات الرواتب',
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
          // فلاتر
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2)),
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
                // الصف الثاني: فلتر الموظف
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: inputsHeight,
                        child: DropdownButtonFormField<int?>(
                          initialValue: _selectedEmployeeId,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black),
                          decoration: InputDecoration(
                            labelText: 'الموظف',
                            labelStyle: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                            prefixIcon: const Icon(Icons.person,
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
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('الكل',
                                  style: TextStyle(fontSize: 12)),
                            ),
                            ..._employees.map(
                              (emp) => DropdownMenuItem<int?>(
                                value: emp.id,
                                child: Text(emp.name,
                                    style: const TextStyle(fontSize: 12)),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedEmployeeId = value;
                            });
                            unawaited(_fetchReport());
                          },
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
                          color: Colors.red),
                    ),
                  ],
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
                        title: 'لا توجد سحبيات',
                        message: 'لم يتم العثور على سحبيات رواتب ضمن الفترة المحددة.',
                        icon: Icons.payments_outlined,
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          await ReportCacheService.instance.clearAll();
                          await _fetchReport();
                        },
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _rows.length,
                          itemBuilder: (context, index) {
                            return _buildWithdrawalCard(_rows[index]);
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
                Text(label,
                    style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
                Text(
                  date != null ? DateFormat('yyyy/MM/dd').format(date) : 'غير محدد',
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

  Widget _buildWithdrawalCard(_SalaryWithdrawalRow row) {
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
                        row.employeeName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      if (row.notes.isNotEmpty)
                        Text(
                          row.notes,
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _currencyFmt.format(row.amount),
                  style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
              ],
            ),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  _dateFormat.format(row.date),
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

// ==================== Data Models ====================

class _SalaryWithdrawalRow {
  _SalaryWithdrawalRow({
    required this.date,
    required this.amount,
    required this.employeeName,
    required this.notes,
    required this.expenseType,
  });

  factory _SalaryWithdrawalRow.fromJson(Map<String, dynamic> json) =>
      _SalaryWithdrawalRow(
        date: DateTime.parse(json['date'] as String),
        amount: (json['amount'] as num).toDouble(),
        employeeName: json['employeeName'] as String,
        notes: json['notes'] as String,
        expenseType: json['expenseType'] as String,
      );

  final DateTime date;
  final double amount;
  final String employeeName;
  final String notes;
  final String expenseType;

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'amount': amount,
    'employeeName': employeeName,
    'notes': notes,
    'expenseType': expenseType,
  };
}

class _SalaryWithdrawalResult {
  _SalaryWithdrawalResult({
    required this.rows,
    required this.totalAmount,
  });

  factory _SalaryWithdrawalResult.fromJson(Map<String, dynamic> json) =>
      _SalaryWithdrawalResult(
        rows: (json['rows'] as List)
            .map((r) => _SalaryWithdrawalRow.fromJson(r as Map<String, dynamic>))
            .toList(),
        totalAmount: (json['totalAmount'] as num).toDouble(),
      );

  final List<_SalaryWithdrawalRow> rows;
  final double totalAmount;

  Map<String, dynamic> toJson() => {
    'rows': rows.map((r) => r.toJson()).toList(),
    'totalAmount': totalAmount,
  };
}

class _SalaryProcessParams {
  _SalaryProcessParams({
    required this.expenses,
    required this.employeeMap,
    required this.salaryTypes,
    this.fromDate,
    this.toDate,
    this.selectedEmployeeId,
  });

  final List<Map<String, dynamic>> expenses;
  final Map<int, String> employeeMap;
  final List<String> salaryTypes;
  final String? fromDate;
  final String? toDate;
  final int? selectedEmployeeId;
}

// ==================== Background Processing ====================

_SalaryWithdrawalResult _processSalaryData(_SalaryProcessParams params) {
  final rows = <_SalaryWithdrawalRow>[];
  double totalAmount = 0;

  for (final expense in params.expenses) {
    // استخراج نوع المصروف (دعم camelCase و snake_case)
    final expenseType =
        (expense['expenseType'] ?? expense['expense_type'] ?? expense['type'] ?? '').toString().trim();

    // التحقق من أن المصروف من نوع راتب (مطابقة مرنة)
    bool isSalary = false;
    final expenseTypeLower = expenseType.toLowerCase();
    
    // مطابقة تامة مع الأنواع المعروفة
    for (final salaryType in params.salaryTypes) {
      if (expenseTypeLower == salaryType.toLowerCase()) {
        isSalary = true;
        break;
      }
    }
    
    // مطابقة جزئية بالكلمات المفتاحية (بما في ذلك العربية)
    if (!isSalary) {
      // البحث في النص الأصلي للكلمات العربية
      if (expenseType.contains('راتب') || 
          expenseType.contains('رواتب') || 
          expenseType.contains('سلفة')) {
        isSalary = true;
      }
      // البحث في النص الصغير للكلمات الإنجليزية
      else if (expenseTypeLower.contains('salary')) {
        isSalary = true;
      }
    }
    
    if (!isSalary) continue;

    // استخراج معرف الموظف
    final relatedIdRaw = expense['relatedId'] ?? expense['related_id'];
    final relatedId = relatedIdRaw is int
        ? relatedIdRaw
        : (relatedIdRaw != null ? int.tryParse(relatedIdRaw.toString()) : null);

    // فلترة حسب الموظف المحدد
    if (params.selectedEmployeeId != null &&
        relatedId != params.selectedEmployeeId) {
      continue;
    }

    // التحقق من التاريخ
    final dateStr = (expense['date'] ?? '').toString();
    if (dateStr.isEmpty) continue;

    // فلترة التاريخ
    if (params.fromDate != null && dateStr.compareTo(params.fromDate!) < 0) {
      continue;
    }
    if (params.toDate != null && dateStr.compareTo(params.toDate!) > 0) {
      continue;
    }

    // استخراج البيانات
    DateTime date = DateTime.now();
    try {
      date = DateTime.parse(dateStr.length > 10
          ? dateStr.replaceFirst(' ', 'T')
          : '${dateStr}T00:00:00');
    } catch (_) {}

    final amount = ((expense['amount'] ?? 0) as num).toDouble();
    final description = (expense['description'] ?? '').toString();
    final employeeName = relatedId != null
        ? (params.employeeMap[relatedId] ?? 'غير محدد')
        : 'غير محدد';

    totalAmount += amount;

    rows.add(_SalaryWithdrawalRow(
      date: date,
      amount: amount,
      employeeName: employeeName,
      notes: description,
      expenseType: expenseType,
    ));
  }

  // ترتيب حسب التاريخ تنازلياً
  rows.sort((a, b) => b.date.compareTo(a.date));

  return _SalaryWithdrawalResult(rows: rows, totalAmount: totalAmount);
}
