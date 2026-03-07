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
import '../../services/daos/expenses_dao.dart';
import '../../services/daos/outbox_dao.dart';
import '../../services/report_cache_service.dart';
import '../../utils/enhanced_pdf_utils.dart';

class ExpensesReportScreen extends ConsumerStatefulWidget {
  const ExpensesReportScreen({
    super.key,
    this.allowedTypes,
    this.initialType,
    this.title = 'تقرير المصروفات',
    this.typeLabel = 'نوع المصروف',
    this.showTypeFilter = true,
    this.includeEmployeeDetails = false,
    this.totalSummaryLabel = 'إجمالي المصروفات',
    this.totalRowLabel = 'الإجمالي',
  });

  final Set<String>? allowedTypes;
  final String? initialType;
  final String title;
  final String typeLabel;
  final bool showTypeFilter;
  final bool includeEmployeeDetails;
  final String totalSummaryLabel;
  final String totalRowLabel;

  @override
  ConsumerState<ExpensesReportScreen> createState() =>
      _ExpensesReportScreenState();
}

class _ExpensesReportScreenState extends ConsumerState<ExpensesReportScreen> {
  final NumberFormat _currencyFmt = NumberFormat('#,##0', 'en_US');
  final DateFormat _dateLabelFormat = DateFormat('yyyy/MM/dd');

  // ignore: unused_element
  String _formatNumber(num value) => _currencyFmt.format(value);

  DateTime? _fromDate;
  DateTime? _toDate;
  bool _loading = false;
  bool _isFromCache = false;

  final List<_ExpenseReportRow> _rows = [];
  final List<String> _availableTypes = [];

  // ⭐ دعم اختيار أنواع متعددة
  final Set<String> _selectedTypes = {};
  double _totalAmount = 0;

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
    _fromDate = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 30));
    _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);

    if (widget.allowedTypes != null && widget.allowedTypes!.isNotEmpty) {
      setState(() {
        _availableTypes
          ..clear()
          ..addAll(widget.allowedTypes!.toList());
        if (widget.showTypeFilter && widget.initialType != null) {
          _selectedTypes.add(widget.initialType!);
        }
      });
    } else {
      await _loadExpenseTypes();
      if (widget.initialType != null &&
          _availableTypes.contains(widget.initialType)) {
        _selectedTypes.add(widget.initialType!);
      }
    }
    await _fetchReport();
  }

  Future<void> _loadExpenseTypes() async {
    final db = ref.read(core_providers.dbProvider);
    final query = await db
        .customSelect("SELECT DISTINCT expense_type FROM expenses WHERE expense_type IS NOT NULL AND expense_type != ''")
        .get();
    final types =
        query.map((row) => row.data['expense_type'] as String).toList()..sort();
    setState(() {
      _availableTypes
        ..clear()
        ..addAll(types);
    });
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
      'selectedTypes': _selectedTypes.toList(),
      'allowedTypes': widget.allowedTypes?.toList(),
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
          _ExpensesReportResult>(
        ReportCacheKeys.expenses,
        _getCacheParams(),
        (json) => _ExpensesReportResult.fromJson(json),
      );

      if (cachedResult != null) {
        setState(() {
          _rows
            ..clear()
            ..addAll(cachedResult.rows);
          _totalAmount = cachedResult.totalAmount;
          _isFromCache = true;
        });
        return;
      }

      final outboxDao = OutboxDao(db);
      final expensesDao = ExpensesDao(db, outboxDao);

      final fromStr = _fromDate != null
          ? DateFormat('yyyy-MM-dd').format(_fromDate!)
          : null;
      final toStr =
          _toDate != null ? DateFormat('yyyy-MM-dd').format(_toDate!) : null;

      // ⭐ فلترة بأنواع متعددة
      final selectedType = widget.showTypeFilter &&
              _selectedTypes.isNotEmpty &&
              _selectedTypes.length == 1
          ? _selectedTypes.first
          : null;

      // 1. جلب البيانات من DB
      final expenses = await expensesDao.listFiltered(
        from: fromStr,
        to: toStr,
        expenseType: selectedType,
      );

      List<Map<String, dynamic>> employeeMaps = [];
      if (widget.includeEmployeeDetails) {
        final employeeIds =
            expenses.map((e) => e.relatedId).whereType<int>().toSet();
        if (employeeIds.isNotEmpty) {
          final employees = await (db.select(
            db.employees,
          )..where((tbl) => tbl.id.isIn(employeeIds.toList())))
              .get();
          employeeMaps = employees.map((e) => e.toJson()).toList();
        }
      }

      // تحويل المصروفات إلى Maps للنقل
      final expenseMaps = expenses.map((e) => e.toJson()).toList();

      // 2. معالجة في الخلفية
      final result = await compute(
          _processExpensesData,
          _ExpenseProcessParams(
            expenses: expenseMaps,
            employees: employeeMaps,
            allowedTypes: widget.allowedTypes?.toList(),
            selectedTypes: _selectedTypes.toList(),
          ));

      // ⭐ تخزين النتيجة في الـ cache
      await ReportCacheService.instance.set(
        ReportCacheKeys.expenses,
        _getCacheParams(),
        result,
        (r) => r.toJson(),
      );

      setState(() {
        _rows
          ..clear()
          ..addAll(result.rows);
        _totalAmount = result.totalAmount;
      });
    } catch (e) {
      debugPrint('Error loading expenses report: $e');
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
    
    // ⭐ عرض الأنواع المحددة
    final selectedTypeLabel = _selectedTypes.isEmpty 
        ? 'الكل' 
        : _selectedTypes.length == 1 
            ? _selectedTypes.first 
            : '${_selectedTypes.length} أنواع محددة';

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
                  widget.title,
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
              pw.Text('${widget.typeLabel}: $selectedTypeLabel',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 10)),
            ],
          ),
        ),
      ],
    );

    final headers = <String>['التاريخ', 'النوع', 'الوصف', 'المبلغ'];
    if (widget.includeEmployeeDetails) {
      headers.insert(3, 'الموظف');
    }

    final dataRows = <List<String>>[];
    for (final row in _rows) {
      final cells = [
        _dateLabelFormat.format(row.date),
        row.type,
        if (row.description.isNotEmpty) row.description else '-',
        EnhancedPdfUtils.formatNumber(row.amount),
      ];
      if (widget.includeEmployeeDetails) {
        cells.insert(3, row.employeeName ?? 'غير محدد');
      }
      dataRows.add(cells);
    }

    final totalRow = [
      widget.totalRowLabel,
      '',
      '',
      EnhancedPdfUtils.formatNumber(_totalAmount),
    ];
    if (widget.includeEmployeeDetails) {
      totalRow.insert(3, '');
    }
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
                  pw.Text('${widget.totalSummaryLabel}: ',
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

    String generateFileName(String title) {
      final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final sanitizedTitle = title.replaceAll(RegExp(r'\s+'), '-');
      return '$sanitizedTitle-$timestamp.pdf';
    }

    final pdfBytes = await doc.save();
    final fileName = generateFileName(widget.title);

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

  /// ⭐ عرض نافذة اختيار الأنواع المتعددة
  Future<void> _showTypesSelector() async {
    final tempSelected = Set<String>.from(_selectedTypes);
    
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('اختر ${widget.typeLabel}'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView(
              children: [
                // خيار "الكل"
                CheckboxListTile(
                  title: const Text('الكل'),
                  value: tempSelected.isEmpty,
                  onChanged: (v) {
                    setDialogState(() {
                      tempSelected.clear();
                    });
                  },
                ),
                const Divider(),
                // الأنواع المتاحة
                ..._availableTypes.map((type) => CheckboxListTile(
                  title: Text(type),
                  value: tempSelected.contains(type),
                  onChanged: (v) {
                    setDialogState(() {
                      if (v == true) {
                        tempSelected.add(type);
                      } else {
                        tempSelected.remove(type);
                      }
                    });
                  },
                )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _selectedTypes.clear();
                  _selectedTypes.addAll(tempSelected);
                });
                Navigator.pop(context);
                _fetchReport();
              },
              child: const Text('تطبيق'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const double inputsHeight = 42;

    return AppScaffold(
      title: widget.title,
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
                if (widget.showTypeFilter) ...[
                  const SizedBox(height: 10),
                  // ⭐ فلتر النوع محسن مع اختيار متعدد
                  InkWell(
                    onTap: _showTypesSelector,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: inputsHeight,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.filter_list, size: 16, color: Colors.grey[600]),
                              const SizedBox(width: 8),
                              Text(
                                _selectedTypes.isEmpty 
                                    ? 'الكل' 
                                    : _selectedTypes.length == 1 
                                        ? _selectedTypes.first 
                                        : '${_selectedTypes.length} أنواع محددة',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              if (_selectedTypes.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).primaryColor,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${_selectedTypes.length}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_drop_down, color: Colors.grey),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
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
                    Text('${widget.totalSummaryLabel}: ',
                        style: const TextStyle(
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
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? const EmptyState(
                        title: 'لا توجد بيانات',
                        message: 'لم يتم العثور على مصروفات ضمن النطاق المحدد.',
                        icon: Icons.receipt_long,
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
                            return _buildExpenseCard(row);
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

  Widget _buildExpenseCard(_ExpenseReportRow row) {
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
                        row.description.isNotEmpty ? row.description : row.type,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${row.type}${row.employeeName != null ? ' - ${row.employeeName}' : ''}',
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
                    color: Colors.red,
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

class _ExpenseProcessParams {
  _ExpenseProcessParams({
    required this.expenses,
    required this.employees,
    this.allowedTypes,
    this.selectedTypes,
  });

  final List<Map<String, dynamic>> expenses;
  final List<Map<String, dynamic>> employees;
  final List<String>? allowedTypes;
  final List<String>? selectedTypes;

  Map<String, dynamic> toJson() => {
    'expenses': expenses,
    'employees': employees,
    'allowedTypes': allowedTypes,
    'selectedTypes': selectedTypes,
  };

  factory _ExpenseProcessParams.fromJson(Map<String, dynamic> json) =>
      _ExpenseProcessParams(
        expenses: (json['expenses'] as List).cast<Map<String, dynamic>>(),
        employees: (json['employees'] as List).cast<Map<String, dynamic>>(),
        allowedTypes: (json['allowedTypes'] as List?)?.cast<String>(),
        selectedTypes: (json['selectedTypes'] as List?)?.cast<String>(),
      );
}

class _ExpenseReportRow {
  _ExpenseReportRow({
    required this.date,
    required this.amount,
    required this.type,
    required this.description,
    required this.employeeName,
  });

  final DateTime date;
  final double amount;
  final String type;
  final String description;
  final String? employeeName;

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'amount': amount,
    'type': type,
    'description': description,
    'employeeName': employeeName,
  };

  factory _ExpenseReportRow.fromJson(Map<String, dynamic> json) =>
      _ExpenseReportRow(
        date: DateTime.parse(json['date'] as String),
        amount: (json['amount'] as num).toDouble(),
        type: json['type'] as String,
        description: json['description'] as String,
        employeeName: json['employeeName'] as String?,
      );
}

class _ExpensesReportResult {
  _ExpensesReportResult({required this.rows, required this.totalAmount});

  final List<_ExpenseReportRow> rows;
  final double totalAmount;

  Map<String, dynamic> toJson() => {
    'rows': rows.map((r) => r.toJson()).toList(),
    'totalAmount': totalAmount,
  };

  factory _ExpensesReportResult.fromJson(Map<String, dynamic> json) =>
      _ExpensesReportResult(
        rows: (json['rows'] as List)
            .map((r) => _ExpenseReportRow.fromJson(r as Map<String, dynamic>))
            .toList(),
        totalAmount: (json['totalAmount'] as num).toDouble(),
      );
}

_ExpensesReportResult _processExpensesData(_ExpenseProcessParams params) {
  // ⭐ إنشاء خريطة الموظفين مع التحقق من نوع الـ id
  final employeeMap = <int, String>{};
  for (final e in params.employees) {
    final id = e['id'];
    final name = e['name'] as String?;
    if (id != null && name != null) {
      employeeMap[id is int ? id : int.tryParse(id.toString()) ?? 0] = name;
    }
  }

  // ⭐ تحويل الأنواع المحددة لـ Set للفلترة السريعة
  final selectedTypesSet = params.selectedTypes?.toSet();

  final rows = <_ExpenseReportRow>[];
  double totalAmount = 0;

  for (final expense in params.expenses) {
    // ⭐ استخدام camelCase من toJson
    final expenseType =
        (expense['expenseType'] ?? expense['expense_type'] ?? expense['type'] ?? '').toString();

    // ⭐ فلترة الأنواع المسموحة - مع دعم المطابقة الجزئية
    if (params.allowedTypes != null && params.allowedTypes!.isNotEmpty) {
      bool matches = false;
      for (final allowed in params.allowedTypes!) {
        // مطابقة تامة أو جزئية
        if (expenseType.toLowerCase() == allowed.toLowerCase() ||
            expenseType.toLowerCase().contains(allowed.toLowerCase()) ||
            allowed.toLowerCase().contains(expenseType.toLowerCase())) {
          matches = true;
          break;
        }
      }
      if (!matches) continue;
    }

    // ⭐ فلترة الأنواع المحددة
    if (selectedTypesSet != null && selectedTypesSet.isNotEmpty) {
      if (!selectedTypesSet.contains(expenseType)) continue;
    }

    // ⭐ استخدام camelCase من toJson
    final relatedIdRaw = expense['relatedId'] ?? expense['related_id'];
    final relatedId = relatedIdRaw is int ? relatedIdRaw : (relatedIdRaw != null ? int.tryParse(relatedIdRaw.toString()) : null);
    final employeeName = relatedId != null ? employeeMap[relatedId] : null;

    DateTime date = DateTime.now();
    if (expense['date'] != null) {
      String val = expense['date'].toString().trim();
      val = val.length > 10 ? val.replaceFirst(' ', 'T') : '${val}T00:00:00';
      try {
        date = DateTime.parse(val);
      } catch (_) {}
    }

    final amount = ((expense['amount'] ?? 0) as num).toDouble();
    final description = (expense['description'] ?? '').toString();

    totalAmount += amount;

    rows.add(
      _ExpenseReportRow(
        date: date,
        amount: amount,
        type: expenseType,
        description: description,
        employeeName: employeeName,
      ),
    );
  }

  // ترتيب
  rows.sort((a, b) => b.date.compareTo(a.date));

  return _ExpensesReportResult(rows: rows, totalAmount: totalAmount);
}
