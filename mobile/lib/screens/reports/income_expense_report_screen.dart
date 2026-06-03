import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfColor;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../components/app_scaffold.dart';
import '../../components/widgets/empty_state.dart';
import '../../components/widgets/neu_card.dart';
import '../../providers/repository_providers.dart';
import '../../services/daos/bookings_dao.dart';
import '../../services/daos/debts_dao.dart';
import '../../services/local_db.dart';
import '../../services/daos/employees_dao.dart';
import '../../services/daos/expenses_dao.dart';
import '../../services/daos/outbox_dao.dart';
import '../../services/daos/payments_dao.dart';
import '../../utils/enhanced_pdf_utils.dart';
import '../../utils/hotel_time_engine.dart';
import '../../utils/status_utils.dart';
import '../../utils/time.dart';
import '../../widgets/report_date_filter.dart';

class IncomeExpenseReportScreen extends ConsumerStatefulWidget {
  const IncomeExpenseReportScreen({super.key});

  @override
  ConsumerState<IncomeExpenseReportScreen> createState() =>
      _IncomeExpenseReportScreenState();
}

class _IncomeExpenseReportScreenState
    extends ConsumerState<IncomeExpenseReportScreen> {
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');
  final NumberFormat _currencyFormat = NumberFormat('#,##0', 'en_US');
  final _filterController = DateFilterController();

  late DateTime _fromDate;
  late DateTime _toDate;

  bool _loading = false;
  bool _detailedMode = false;

  List<_IncomeEntry> _incomeEntries = [];
  List<_ExpenseEntry> _expenseEntries = [];

  double _incomeTotal = 0;
  double _expenseTotal = 0;
  double _salaryTotal = 0;
  double _net = 0;

  int _bookingsCount = 0;
  int _activeBookingsCount = 0;
  int _checkoutBookingsCount = 0;
  int _totalDebtsCount = 0;
  int _unsettledDebtsCount = 0;
  double _unsettledDebtsAmount = 0;
  int _activeEmployeesCount = 0;
  int _terminatedEmployeesCount = 0;
  double _totalSalaryObligation = 0;
  int _unsettledDebtsInPeriodCount = 0;
  double _unsettledDebtsInPeriodAmount = 0;

  @override
  void initState() {
    super.initState();
    final range = DateFilterController.getDefaultHotelDayRange();
    _fromDate = range.from ?? HotelTimeEngine.getHotelDayRange(DateTime.now())['start']!;
    _toDate = range.to ?? HotelTimeEngine.getHotelDayRange(DateTime.now())['end']!;
    _fetchReport();
  }

  // ------------------------------------------------
  // جلب البيانات
  // ------------------------------------------------
  Future<void> _fetchReport() async {
    setState(() => _loading = true);
    try {
      final db = ref.read(databaseProvider);
      final outboxDao = OutboxDao(db);
      final paymentsDao = PaymentsDao(db, outboxDao);
      final expensesDao = ExpensesDao(db, outboxDao);

      final fromDate = _fromDate;
      final toDate = _toDate;

      // المدفوعات: فلترة كاملة بالوقت
      final fromStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(fromDate);
      final toStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(toDate);
      final payments = await paymentsDao.list(
        from: fromStr,
        to: toStr,
        excludeVoided: true,
        excludePendingBalance: true,
      );

      // المصروفات: فلترة بالمفتاح الفندقي (تم تعديل الدالة في DAO لتقبل نطاقاً صحيحاً)
      // بدلاً من إضافة ثانية وهمية
      final fromHotelDay = HotelTimeEngine.getHotelDayKey(dateTime: fromDate);
      final toHotelDay = HotelTimeEngine.getHotelDayKey(dateTime: toDate);
      final expenses = await expensesDao.listFilteredByHotelDay(
        fromHotelDay: fromHotelDay,
        toHotelDay: toHotelDay,
      );

      // بيانات إضافية للتقرير
      final bookingsDao = BookingsDao(db, outboxDao);
      final debtsDao = DebtsDao(db, outboxDao);
      final employeesDao = EmployeesDao(db, outboxDao);

      final bookingFromStr = DateFormat('yyyy-MM-dd').format(fromDate);
      final bookingToStr = DateFormat('yyyy-MM-dd').format(toDate);
      final bookings = await bookingsDao.list(
        from: bookingFromStr,
        to: bookingToStr,
      );

      final allDebts = await debtsDao.list();
      final debtsInPeriod = await _filterDebtsInPeriod(allDebts, fromDate, toDate);
      final unsettledDebtsAll =
          allDebts.where((d) => d.isSettled == 0).toList();

      final allEmployees = await employeesDao.list();
      final employees =
          allEmployees.where((e) => StatusUtils.isEmployeeActive(e.status)).toList();
      final terminatedEmployees =
          allEmployees.where((e) => StatusUtils.isEmployeeTerminated(e.status)).toList();

      // خريطة أسماء النزلاء
      final bookingGuestMap = <int, String>{};
      for (final b in bookings) {
        bookingGuestMap[b.id] = b.guestName;
      }
      final allBookings = await bookingsDao.list(includeDeleted: true);
      for (final b in allBookings) {
        bookingGuestMap.putIfAbsent(b.id, () => b.guestName);
      }

      final result = await compute(
        _processReportData,
        _ReportParams(
          payments: payments
              .map(
                (p) => {
                  'date': p.paymentDate,
                  'roomNumber': p.roomNumber ?? '',
                  'guestName': p.bookingLocalId != null
                      ? (bookingGuestMap[p.bookingLocalId] ?? '')
                      : '',
                  'amount': p.amount,
                  'paymentMethod': p.paymentMethod,
                  'revenueType': p.revenueType,
                },
              )
              .toList(),
          expenses: expenses
              .map(
                (e) => {
                  'date': e.date,
                  'type': e.expenseType,
                  'description': e.description,
                  'amount': e.amount,
                },
              )
              .toList(),
          fromDate: _fromDate,
          toDate: _toDate,
          bookingsCount: bookings.length,
          activeBookingsCount:
              bookings.where((b) => b.status == 'checked_in').length,
          checkoutBookingsCount:
              bookings.where((b) => b.status == 'checked_out').length,
          totalDebtsCount: debtsInPeriod.length,
          unsettledDebtsCount: unsettledDebtsAll.length,
          unsettledDebtsAmount:
              unsettledDebtsAll.fold(0.0, (s, d) => s + d.remainingAmount),
          unsettledDebtsInPeriodCount:
              debtsInPeriod.where((d) => d.isSettled == 0).length,
          unsettledDebtsInPeriodAmount: debtsInPeriod
              .where((d) => d.isSettled == 0)
              .fold(0.0, (s, d) => s + d.remainingAmount),
          activeEmployeesCount: employees.length,
          terminatedEmployeesCount: terminatedEmployees.length,
          totalSalaryObligation:
              employees.fold(0.0, (s, e) => s + e.basicSalary),
        ),
      );

      if (mounted) {
        setState(() {
          _incomeEntries = result.incomeEntries;
          _expenseEntries = result.expenseEntries;
          _incomeTotal = result.incomeTotal;
          _expenseTotal = result.expenseTotal;
          _salaryTotal = result.salaryTotal;
          _net = result.net;
          _bookingsCount = result.bookingsCount;
          _activeBookingsCount = result.activeBookingsCount;
          _checkoutBookingsCount = result.checkoutBookingsCount;
          _totalDebtsCount = result.totalDebtsCount;
          _unsettledDebtsCount = result.unsettledDebtsCount;
          _unsettledDebtsAmount = result.unsettledDebtsAmount;
          _unsettledDebtsInPeriodCount = result.unsettledDebtsInPeriodCount;
          _unsettledDebtsInPeriodAmount = result.unsettledDebtsInPeriodAmount;
          _activeEmployeesCount = result.activeEmployeesCount;
          _terminatedEmployeesCount = result.terminatedEmployeesCount;
          _totalSalaryObligation = result.totalSalaryObligation;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تحميل التقرير: $e'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  // فلترة الديون (يمكن نقلها إلى DAO لاحقاً)
  Future<List<Debt>> _filterDebtsInPeriod(
      List<Debt> allDebts, DateTime from, DateTime to) async {
    final fromDay = DateTime(from.year, from.month, from.day);
    final toDay = DateTime(to.year, to.month, to.day);
    return allDebts.where((d) {
      final dateStr = d.dateRecorded.isNotEmpty ? d.dateRecorded : d.paymentDate;
      if (dateStr.isEmpty) return false;
      try {
        final debtDate = DateTime.parse(
          dateStr.length > 10 ? dateStr.replaceFirst(' ', 'T') : dateStr,
        );
        final debtDay = DateTime(debtDate.year, debtDate.month, debtDate.day);
        return !debtDay.isBefore(fromDay) && !debtDay.isAfter(toDay);
      } catch (_) {
        return false;
      }
    }).toList();
  }

  // ------------------------------------------------
  // دوال مساعدة للتجميع والعرض
  // ------------------------------------------------
  String _getGroupKey(DateTime date, String groupBy) {
    switch (groupBy) {
      case 'daily':
        return DateFormat('yyyy-MM-dd').format(date);
      case 'monthly':
        return DateFormat('yyyy-MM').format(date);
      case 'yearly':
        return DateFormat('yyyy').format(date);
      default:
        return 'all';
    }
  }

  String _getGroupLabel(String key, String groupBy) {
    switch (groupBy) {
      case 'daily':
        final dt = DateTime.parse(key);
        return '${dt.day} ${_arabicMonths[dt.month]} ${dt.year} (${_arabicDayName(dt)})';
      case 'monthly':
        final parts = key.split('-');
        return '${_arabicMonths[int.tryParse(parts[1]) ?? 1]} ${parts[0]}';
      case 'yearly':
        return '$key م';
      default:
        return '';
    }
  }

  String _getGroupTypeLabel(String groupBy) {
    switch (groupBy) {
      case 'daily':
        return 'يومي';
      case 'monthly':
        return 'شهري';
      case 'yearly':
        return 'سنوي';
      default:
        return 'عام';
    }
  }

  List<_GroupedData> _buildGroupedData(String groupBy) {
    final incomeMap = <String, List<_IncomeEntry>>{};
    final expenseMap = <String, List<_ExpenseEntry>>{};

    for (final e in _incomeEntries) {
      final key = _getGroupKey(e.date, groupBy);
      incomeMap.putIfAbsent(key, () => []).add(e);
    }
    for (final e in _expenseEntries) {
      final key = _getGroupKey(e.date, groupBy);
      expenseMap.putIfAbsent(key, () => []).add(e);
    }

    final allKeys = <String>{...incomeMap.keys, ...expenseMap.keys}.toList()
      ..sort();

    return allKeys.asMap().entries.map((entry) {
      final idx = entry.key;
      final key = entry.value;
      final inc = incomeMap[key] ?? [];
      final exp = expenseMap[key] ?? [];
      final incTotal = inc.fold(0.0, (s, e) => s + e.amount);
      final expTotal = exp.fold(0.0, (s, e) => s + e.amount);
      final salTotal =
          exp.where((e) => e.isSalary).fold(0.0, (s, e) => s + e.amount);
      return _GroupedData(
        index: idx + 1,
        key: key,
        label: _getGroupLabel(key, groupBy),
        incomeEntries: inc,
        expenseEntries: exp,
        incomeTotal: incTotal,
        expenseTotal: expTotal,
        salaryTotal: salTotal,
        net: incTotal - expTotal,
        incomeCount: inc.length,
        expenseCount: exp.length,
      );
    }).toList();
  }

  // ------------------------------------------------
  // بناء ملفات PDF المشتركة (مستخرجة لتجنب التكرار)
  // ------------------------------------------------
  pw.Widget _buildReportHeader(
      ArabicPdfFonts fonts, String fromLabel, String toLabel) {
    return pw.Container(
      width: double.infinity,
      decoration: const pw.BoxDecoration(color: PdfColors.primary),
      padding: const pw.EdgeInsets.all(20),
      child: pw.Column(
        children: [
          pw.Text(
            'تقرير الدورة المالية الشامل',
            style: pw.TextStyle(
              font: fonts.bold,
              fontSize: 22,
              color: PdfColors.textWhite,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'فندق مارينا بلازا',
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 14,
              color: PdfColors.secondary,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'الفترة من $fromLabel إلى $toLabel',
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 12,
              color: PdfColors.textWhite,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'تاريخ الإنشاء: ${EnhancedPdfUtils.formatDateTime(DateTime.now())}',
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 10,
              color: PdfColors.textWhite,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildExecutiveSummary(ArabicPdfFonts fonts) {
    final nonSalaryExpenses = _expenseTotal - _salaryTotal;
    final profitMargin =
        _incomeTotal > 0 ? (_net / _incomeTotal * 100) : 0.0;

    pw.Widget summaryBox(String title, String value, PdfColor color) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.backgroundLight,
          border: pw.Border.all(color: color, width: 0.8),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          children: [
            pw.Text(title,
                style: pw.TextStyle(
                    font: fonts.regular, fontSize: 10, color: PdfColors.textLight)),
            pw.SizedBox(height: 3),
            pw.Text(value,
                style: pw.TextStyle(font: fonts.bold, fontSize: 15, color: color)),
          ],
        ),
      );
    }

    return pw.Column(
      children: [
        _buildSectionTitle(fonts, 'الملخص التنفيذي', PdfColors.primary),
        pw.Row(children: [
          pw.Expanded(child: summaryBox('إجمالي الإيرادات',
              EnhancedPdfUtils.formatNumber(_incomeTotal), PdfColors.success)),
          pw.SizedBox(width: 6),
          pw.Expanded(child: summaryBox('إجمالي المصروفات',
              EnhancedPdfUtils.formatNumber(_expenseTotal), PdfColors.danger)),
        ]),
        pw.SizedBox(height: 6),
        pw.Row(children: [
          pw.Expanded(child: summaryBox('مصروفات الرواتب',
              EnhancedPdfUtils.formatNumber(_salaryTotal), PdfColors.warning)),
          pw.SizedBox(width: 6),
          pw.Expanded(child: summaryBox('مصروفات تشغيلية',
              EnhancedPdfUtils.formatNumber(nonSalaryExpenses), PdfColors.info)),
        ]),
        pw.SizedBox(height: 6),
        pw.Row(children: [
          pw.Expanded(child: summaryBox('صافي الربح / الخسارة',
              EnhancedPdfUtils.formatNumber(_net),
              _net >= 0 ? PdfColors.success : PdfColors.danger)),
          pw.SizedBox(width: 6),
          pw.Expanded(child: summaryBox('هامش الربح',
              '${profitMargin.toStringAsFixed(1)}%',
              profitMargin > 0 ? PdfColors.success : PdfColors.danger)),
        ]),
      ],
    );
  }

  pw.Widget _buildIncomeDetails(ArabicPdfFonts fonts) {
    if (_incomeEntries.isEmpty) return pw.Container();
    return pw.Column(children: [
      _buildSectionTitle(fonts, 'تفاصيل الإيرادات', PdfColors.success),
      EnhancedPdfUtils.buildProfessionalTable(
        headers: ['#', 'التاريخ', 'الغرفة', 'النزيل', 'طريقة الدفع', 'نوع الإيراد', 'المبلغ'],
        fonts: fonts,
        headerColor: PdfColors.success,
        alternateRowColor: PdfColors.backgroundLight,
        data: _incomeEntries.asMap().entries.map((entry) {
          final e = entry.value;
          return [
            '${entry.key + 1}',
            _dateFormat.format(e.date),
            e.roomNumber.isNotEmpty ? e.roomNumber : '-',
            e.guestName.isNotEmpty ? e.guestName : '-',
            _paymentMethodName(e.paymentMethod),
            _revenueTypeName(e.revenueType),
            EnhancedPdfUtils.formatNumber(e.amount),
          ];
        }).toList(),
      ),
    ]);
  }

  pw.Widget _buildExpenseDetails(ArabicPdfFonts fonts) {
    if (_expenseEntries.isEmpty) return pw.Container();
    return pw.Column(children: [
      _buildSectionTitle(fonts, 'تفاصيل المصروفات', PdfColors.danger),
      EnhancedPdfUtils.buildProfessionalTable(
        headers: ['#', 'التاريخ', 'النوع', 'الوصف', 'المبلغ'],
        fonts: fonts,
        headerColor: PdfColors.danger,
        alternateRowColor: PdfColors.backgroundLight,
        data: _expenseEntries.asMap().entries.map((entry) {
          final e = entry.value;
          return [
            '${entry.key + 1}',
            _dateFormat.format(e.date),
            e.isSalary ? 'رواتب' : e.type,
            e.description.isNotEmpty ? e.description : '-',
            EnhancedPdfUtils.formatNumber(e.amount),
          ];
        }).toList(),
      ),
    ]);
  }

  pw.Widget _buildPaymentMethodsTable(ArabicPdfFonts fonts) {
    final cashIncome = _incomeEntries
        .where((e) => e.paymentMethod == 'cash')
        .fold(0.0, (s, e) => s + e.amount);
    final cardIncome = _incomeEntries
        .where((e) => e.paymentMethod == 'card')
        .fold(0.0, (s, e) => s + e.amount);
    final transferIncome = _incomeEntries
        .where((e) => e.paymentMethod == 'transfer')
        .fold(0.0, (s, e) => s + e.amount);
    final otherMethodIncome =
        _incomeTotal - cashIncome - cardIncome - transferIncome;

    final rows = <List<String>>[
      [
        'نقداً',
        EnhancedPdfUtils.formatNumber(cashIncome),
        '${_incomeEntries.where((e) => e.paymentMethod == 'cash').length}',
        _incomeTotal > 0
            ? '${(cashIncome / _incomeTotal * 100).toStringAsFixed(1)}%'
            : '0%',
      ],
      [
        'بطاقة ائتمانية',
        EnhancedPdfUtils.formatNumber(cardIncome),
        '${_incomeEntries.where((e) => e.paymentMethod == 'card').length}',
        _incomeTotal > 0
            ? '${(cardIncome / _incomeTotal * 100).toStringAsFixed(1)}%'
            : '0%',
      ],
      [
        'تحويل بنكي',
        EnhancedPdfUtils.formatNumber(transferIncome),
        '${_incomeEntries.where((e) => e.paymentMethod == 'transfer').length}',
        _incomeTotal > 0
            ? '${(transferIncome / _incomeTotal * 100).toStringAsFixed(1)}%'
            : '0%',
      ],
      if (otherMethodIncome > 0)
        [
          'أخرى',
          EnhancedPdfUtils.formatNumber(otherMethodIncome),
          '${_incomeEntries.where((e) => e.paymentMethod != 'cash' && e.paymentMethod != 'card' && e.paymentMethod != 'transfer').length}',
          _incomeTotal > 0
              ? '${(otherMethodIncome / _incomeTotal * 100).toStringAsFixed(1)}%'
              : '0%',
        ],
      [
        'الإجمالي',
        EnhancedPdfUtils.formatNumber(_incomeTotal),
        '${_incomeEntries.length}',
        '100%',
      ],
    ];

    return _buildSectionWithTable(
        fonts, 'تحليل طرق الدفع', PdfColors.secondary, [
      'طريقة الدفع',
      'المبلغ',
      'العدد',
      'النسبة'
    ], rows);
  }

  pw.Widget _buildDebtAnalysisTable(
      ArabicPdfFonts fonts, double debtCoverage) {
    return _buildSectionWithTable(
        fonts, 'تحليل الديون المستحقة', PdfColors.danger, ['البيان', 'القيمة'],
        [
          ['إجمالي الديون في الفترة', '$_totalDebtsCount دين'],
          ['ديون غير مسددة في الفترة', '$_unsettledDebtsInPeriodCount دين'],
          [
            'مبلغ الديون غير المسددة في الفترة',
            EnhancedPdfUtils.formatNumber(_unsettledDebtsInPeriodAmount)
          ],
          ['إجمالي الديون غير المسددة (كل الفترات)', '$_unsettledDebtsCount دين'],
          [
            'مبلغ الديون غير المسددة الكلي',
            EnhancedPdfUtils.formatNumber(_unsettledDebtsAmount)
          ],
          [
            'نسبة الديون غير المسددة الكلية من الإيرادات',
            _incomeTotal > 0
                ? '${(_unsettledDebtsAmount / _incomeTotal * 100).toStringAsFixed(1)}%'
                : '0%'
          ],
          [
            'قدرة تغطية الديون (صافي / ديون)',
            debtCoverage > 0
                ? '${debtCoverage.toStringAsFixed(2)}x'
                : 'غير كافٍ'
          ],
        ],
        columnWidths: [200, 130]);
  }

  pw.Widget _buildFinancialIndicatorsTable(ArabicPdfFonts fonts,
      double profitMargin, double expenseRatio, double salaryExpenseRatio,
      double debtCoverage) {
    return _buildSectionWithTable(
        fonts, 'المؤشرات المالية الرئيسية', PdfColors.primary,
        ['المؤشر', 'القيمة', 'التقييم'], [
      [
        'هامش الربح الصافي',
        '${profitMargin.toStringAsFixed(1)}%',
        profitMargin > 20
            ? 'ممتاز'
            : profitMargin > 10
                ? 'جيد'
                : profitMargin > 0
                    ? 'مقبول'
                    : 'خسارة'
      ],
      [
        'نسبة المصروفات إلى الإيرادات',
        '${expenseRatio.toStringAsFixed(1)}%',
        expenseRatio < 60
            ? 'ممتاز'
            : expenseRatio < 80
                ? 'جيد'
                : 'مرتفع'
      ],
      [
        'نسبة الرواتب إلى الإيرادات',
        '${salaryExpenseRatio.toStringAsFixed(1)}%',
        salaryExpenseRatio < 30
            ? 'ممتاز'
            : salaryExpenseRatio < 50
                ? 'جيد'
                : 'مرتفع'
      ],
      [
        'معدل تغطية الديون',
        debtCoverage > 0
            ? '${debtCoverage.toStringAsFixed(2)}x'
            : 'غير كافٍ',
        debtCoverage > 2
            ? 'ممتاز'
            : debtCoverage > 1
                ? 'جيد'
                : 'ضعيف'
      ],
    ]);
  }

  pw.Widget _buildHumanResourcesSection(ArabicPdfFonts fonts,
      double salaryExpenseRatio) {
    return _buildSectionWithTable(
        fonts, 'تكاليف الموارد البشرية', PdfColors.warning, ['البيان', 'القيمة'],
        [
          ['عدد الموظفين النشطين', '$_activeEmployeesCount موظف'],
          ['عدد الموظفين المنهية خدمتهم', '$_terminatedEmployeesCount موظف'],
          [
            'إجمالي الالتزامات الرواتب الشهرية',
            EnhancedPdfUtils.formatNumber(_totalSalaryObligation)
          ],
          [
            'الرواتب المدفوعة في الفترة',
            EnhancedPdfUtils.formatNumber(_salaryTotal)
          ],
          [
            'نسبة الرواتب من الإيرادات',
            '${salaryExpenseRatio.toStringAsFixed(1)}%'
          ],
          [
            'نسبة الرواتب من المصروفات',
            _expenseTotal > 0
                ? '${(_salaryTotal / _expenseTotal * 100).toStringAsFixed(1)}%'
                : '0%'
          ],
        ],
        columnWidths: [200, 130]);
  }

  pw.Widget _buildBookingsStats(ArabicPdfFonts fonts) {
    return _buildSectionWithTable(
        fonts, 'إحصائيات الحجوزات والإشغال', PdfColors.info,
        ['البيان', 'القيمة'], [
      ['إجمالي الحجوزات في الفترة', '$_bookingsCount حجز'],
      ['حجوزات نشطة (داخلين)', '$_activeBookingsCount حجز'],
      ['حجوزات مغادرة', '$_checkoutBookingsCount حجز'],
      [
        'متوسط الإيراد لكل حجز',
        _bookingsCount > 0
            ? EnhancedPdfUtils.formatNumber(_incomeTotal / _bookingsCount)
            : '0'
      ],
    ], columnWidths: [200, 130]);
  }

  pw.Widget _buildAccountingSummary(ArabicPdfFonts fonts) {
    final roomRevenue = _incomeEntries
        .where((e) => e.revenueType == 'room' || e.revenueType.isEmpty)
        .fold(0.0, (s, e) => s + e.amount);
    final otherRevenue = _incomeTotal - roomRevenue;
    final nonSalaryExpenses = _expenseTotal - _salaryTotal;

    return _buildSectionWithTable(
        fonts, 'الملخص المحاسبي الشامل', PdfColors.primary, ['البيان', 'المبلغ'],
        [
          ['إيرادات الغرف', EnhancedPdfUtils.formatNumber(roomRevenue)],
          ['إيرادات أخرى', EnhancedPdfUtils.formatNumber(otherRevenue)],
          ['إجمالي الإيرادات', EnhancedPdfUtils.formatNumber(_incomeTotal)],
          ['(-) مصروفات تشغيلية', EnhancedPdfUtils.formatNumber(nonSalaryExpenses)],
          ['(-) رواتب ومخصصات', EnhancedPdfUtils.formatNumber(_salaryTotal)],
          ['إجمالي المصروفات', EnhancedPdfUtils.formatNumber(_expenseTotal)],
          ['صافي الربح / الخسارة', EnhancedPdfUtils.formatNumber(_net)],
          [
            '(+) ديون مستحقة غير مسددة',
            EnhancedPdfUtils.formatNumber(_unsettledDebtsAmount)
          ],
          [
            'الوضع المالي الصافي',
            EnhancedPdfUtils.formatNumber(_net - _unsettledDebtsAmount)
          ],
        ],
        columnWidths: [200, 130]);
  }

  // دالة مساعدة: عنوان قسم
  pw.Widget _buildSectionTitle(
      ArabicPdfFonts fonts, String title, PdfColor color) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      margin: const pw.EdgeInsets.only(top: 16, bottom: 8),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          font: fonts.bold,
          fontSize: 13,
          color: PdfColors.textWhite,
        ),
      ),
    );
  }

  // دالة مساعدة: جدول داخل قسم
  pw.Widget _buildSectionWithTable(
      ArabicPdfFonts fonts,
      String title,
      PdfColor headerColor,
      List<String> headers,
      List<List<String>> data,
      {List<double>? columnWidths}) {
    return pw.Column(children: [
      _buildSectionTitle(fonts, title, headerColor),
      EnhancedPdfUtils.buildProfessionalTable(
        headers: headers,
        fonts: fonts,
        headerColor: headerColor,
        alternateRowColor: PdfColors.backgroundLight,
        data: data,
        columnWidths: columnWidths,
      ),
    ]);
  }

  // ------------------------------------------------
  // بناء PDF الرئيسي
  // ------------------------------------------------
  Future<pw.Document> _buildPdfDocument() async {
    final fonts = await EnhancedPdfUtils.loadArabicFonts();
    final doc = pw.Document();
    final fromLabel = DateFormat('yyyy-MM-dd').format(_fromDate);
    final toLabel = DateFormat('yyyy-MM-dd').format(_toDate);

    final profitMargin =
        _incomeTotal > 0 ? (_net / _incomeTotal * 100) : 0.0;
    final expenseRatio =
        _incomeTotal > 0 ? (_expenseTotal / _incomeTotal * 100) : 0.0;
    final salaryExpenseRatio =
        _incomeTotal > 0 ? (_salaryTotal / _incomeTotal * 100) : 0.0;
    final debtCoverage =
        _unsettledDebtsAmount > 0 && _net > 0
            ? _net / _unsettledDebtsAmount
            : 0.0;

    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        footer: (context) => pw.Align(
          child: pw.Text(
            'صفحة ${context.pageNumber} من ${context.pagesCount}',
            style: pw.TextStyle(font: fonts.regular, fontSize: 10),
          ),
        ),
        build: (context) {
          return [
            _buildReportHeader(fonts, fromLabel, toLabel),
            pw.SizedBox(height: 16),
            _buildExecutiveSummary(fonts),
            _buildIncomeDetails(fonts),
            _buildPaymentMethodsTable(fonts),
            _buildExpenseDetails(fonts),
            _buildSectionTitle(fonts, 'تحليل المصروفات حسب الفئة', PdfColors.accent),
            _buildExpenseCategoryAnalysis(fonts),
            _buildHumanResourcesSection(fonts, salaryExpenseRatio),
            _buildDebtAnalysisTable(fonts, debtCoverage),
            _buildBookingsStats(fonts),
            _buildFinancialIndicatorsTable(
                fonts, profitMargin, expenseRatio, salaryExpenseRatio, debtCoverage),
            _buildAccountingSummary(fonts),
            pw.SizedBox(height: 20),
            pw.Divider(color: PdfColors.textLight),
            pw.SizedBox(height: 8),
            _buildFooterLine(fonts),
          ];
        },
      ),
    );

    return doc;
  }

  pw.Widget _buildExpenseCategoryAnalysis(ArabicPdfFonts fonts) {
    final expenseByType = <String, double>{};
    for (final e in _expenseEntries) {
      final key = e.isSalary ? 'رواتب' : e.type;
      expenseByType[key] = (expenseByType[key] ?? 0) + e.amount;
    }
    final sorted = expenseByType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (sorted.isEmpty) return pw.Container();

    return EnhancedPdfUtils.buildProfessionalTable(
      headers: ['الفئة', 'المبلغ', 'النسبة من الإيرادات', 'النسبة من المصروفات'],
      fonts: fonts,
      headerColor: PdfColors.accent,
      alternateRowColor: PdfColors.backgroundLight,
      data: sorted.map((entry) {
        return [
          entry.key,
          EnhancedPdfUtils.formatNumber(entry.value),
          _incomeTotal > 0
              ? '${(entry.value / _incomeTotal * 100).toStringAsFixed(1)}%'
              : '0%',
          _expenseTotal > 0
              ? '${(entry.value / _expenseTotal * 100).toStringAsFixed(1)}%'
              : '0%',
        ];
      }).toList(),
    );
  }

  pw.Widget _buildFooterLine(ArabicPdfFonts fonts) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'تم إنشاء هذا التقرير تلقائياً - فندق مارينا بلازا',
          style: pw.TextStyle(
              font: fonts.regular, fontSize: 9, color: PdfColors.textLight),
        ),
        pw.Text(
          'تقرير الدورة المالية الشامل',
          style: pw.TextStyle(
              font: fonts.bold, fontSize: 9, color: PdfColors.primary),
        ),
      ],
    );
  }

  // ------------------------------------------------
  // بناء PDF المجمع (يومي/شهري/سنوي)
  // ------------------------------------------------
  Future<pw.Document> _buildDetailedGroupedPdf(String groupBy) async {
    final fonts = await EnhancedPdfUtils.loadArabicFonts();
    final doc = pw.Document();
    final groupedData = _buildGroupedData(groupBy);
    final groupTypeLabel = _getGroupTypeLabel(groupBy);
    final fromLabel = DateFormat('yyyy-MM-dd').format(_fromDate);
    final toLabel = DateFormat('yyyy-MM-dd').format(_toDate);

    final profitMargin =
        _incomeTotal > 0 ? (_net / _incomeTotal * 100) : 0.0;
    final expenseRatio =
        _incomeTotal > 0 ? (_expenseTotal / _incomeTotal * 100) : 0.0;
    final salaryExpenseRatio =
        _incomeTotal > 0 ? (_salaryTotal / _incomeTotal * 100) : 0.0;
    final debtCoverage =
        _unsettledDebtsAmount > 0 && _net > 0
            ? _net / _unsettledDebtsAmount
            : 0.0;

    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        footer: (context) => pw.Align(
          child: pw.Text(
            'صفحة ${context.pageNumber} من ${context.pagesCount}',
            style: pw.TextStyle(font: fonts.regular, fontSize: 10),
          ),
        ),
        build: (context) {
          return [
            _buildGroupedReportHeader(fonts, groupTypeLabel, fromLabel, toLabel,
                groupedData.length),
            pw.SizedBox(height: 16),
            _buildOverallSummaryBoxes(fonts),
            pw.SizedBox(height: 16),
            _buildPeriodCards(fonts, groupedData),
            pw.SizedBox(height: 16),
            _buildFinalSummarySection(fonts, groupedData),
            // أقسام الدورة المالية المضافة للتقرير المجمع
            _buildPaymentMethodsTable(fonts),
            _buildHumanResourcesSection(fonts, salaryExpenseRatio),
            _buildDebtAnalysisTable(fonts, debtCoverage),
            _buildBookingsStats(fonts),
            _buildFinancialIndicatorsTable(
                fonts, profitMargin, expenseRatio, salaryExpenseRatio, debtCoverage),
            _buildAccountingSummary(fonts),
            pw.SizedBox(height: 20),
            pw.Divider(color: PdfColors.textLight),
            pw.SizedBox(height: 8),
            _buildFooterLine(fonts),
          ];
        },
      ),
    );

    return doc;
  }

  pw.Widget _buildGroupedReportHeader(ArabicPdfFonts fonts, String groupTypeLabel,
      String fromLabel, String toLabel, int periodCount) {
    return pw.Container(
      width: double.infinity,
      decoration: const pw.BoxDecoration(color: PdfColors.primary),
      padding: const pw.EdgeInsets.all(20),
      child: pw.Column(
        children: [
          pw.Text(
            'تقرير الدخل والمصروفات التفصيلي',
            style: pw.TextStyle(
              font: fonts.bold,
              fontSize: 20,
              color: PdfColors.textWhite,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: const pw.BoxDecoration(color: PdfColors.secondary),
            child: pw.Text(
              'تجميع $groupTypeLabel',
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 12,
                color: PdfColors.textWhite,
              ),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'الفترة من $fromLabel إلى $toLabel',
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 12,
              color: PdfColors.textWhite,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'عدد الفترات: $periodCount',
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 10,
              color: PdfColors.textWhite,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildOverallSummaryBoxes(ArabicPdfFonts fonts) {
    pw.Widget box(String title, String value, PdfColor color) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.backgroundLight,
          border: pw.Border.all(color: color, width: 0.8),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          children: [
            pw.Text(title,
                style: pw.TextStyle(
                    font: fonts.regular, fontSize: 10, color: PdfColors.textLight)),
            pw.SizedBox(height: 3),
            pw.Text(value,
                style: pw.TextStyle(font: fonts.bold, fontSize: 15, color: color)),
          ],
        ),
      );
    }

    return pw.Column(children: [
      pw.Row(children: [
        pw.Expanded(child: box('إجمالي الدخل',
            EnhancedPdfUtils.formatNumber(_incomeTotal), PdfColors.success)),
        pw.SizedBox(width: 6),
        pw.Expanded(child: box('إجمالي المصروفات',
            EnhancedPdfUtils.formatNumber(_expenseTotal), PdfColors.danger)),
      ]),
      pw.SizedBox(height: 6),
      pw.Row(children: [
        pw.Expanded(child: box('مصروفات الرواتب',
            EnhancedPdfUtils.formatNumber(_salaryTotal), PdfColors.warning)),
        pw.SizedBox(width: 6),
        pw.Expanded(child: box('صافي الربح / الخسارة',
            EnhancedPdfUtils.formatNumber(_net),
            _net >= 0 ? PdfColors.success : PdfColors.danger)),
      ]),
    ]);
  }

  pw.Widget _buildPeriodCards(
      ArabicPdfFonts fonts, List<_GroupedData> groups) {
    return pw.Column(
      children: [
        _buildSectionTitle(fonts, 'التفاصيل حسب الفترة', PdfColors.accent),
        ...groups.map((group) => _buildPeriodCard(fonts, group)),
      ],
    );
  }

  pw.Widget _buildPeriodCard(ArabicPdfFonts fonts, _GroupedData group) {
    final isProfit = group.net >= 0;
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
            color: isProfit ? PdfColors.success : PdfColors.danger,
            width: 0.8),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const pw.BoxDecoration(
              color: PdfColors.primary,
              borderRadius: pw.BorderRadius.only(
                  topLeft: pw.Radius.circular(7),
                  topRight: pw.Radius.circular(7)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${group.index}. ${group.label}',
                  style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 13,
                      color: PdfColors.textWhite),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: pw.BoxDecoration(
                    color: isProfit ? PdfColors.success : PdfColors.danger,
                    borderRadius:
                        const pw.BorderRadius.all(pw.Radius.circular(10)),
                  ),
                  child: pw.Text(
                    isProfit ? 'ربح' : 'خسارة',
                    style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 9,
                        color: PdfColors.textWhite),
                  ),
                ),
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            child: pw.Column(children: [
              _buildMiniSummaryRow(fonts, group),
              pw.SizedBox(height: 8),
              _buildMiniTable(
                  fonts,
                  'الدخل',
                  ['التاريخ', 'الغرفة', 'الدفع', 'النوع', 'المبلغ'],
                  group.incomeEntries
                      .map((e) => [
                            DateFormat('dd/MM').format(e.date),
                            e.roomNumber.isNotEmpty ? e.roomNumber : '-',
                            _paymentMethodName(e.paymentMethod),
                            _revenueTypeName(e.revenueType),
                            EnhancedPdfUtils.formatNumber(e.amount),
                          ])
                      .toList(),
                  PdfColors.success,
                  boldColumnIndex: 4),
              pw.SizedBox(height: 4),
              _buildMiniTable(
                  fonts,
                  'المصروفات',
                  ['التاريخ', 'الوصف', 'المبلغ'],
                  group.expenseEntries
                      .map((e) => [
                            DateFormat('dd/MM').format(e.date),
                            e.description.isNotEmpty ? e.description : e.type,
                            EnhancedPdfUtils.formatNumber(e.amount),
                          ])
                      .toList(),
                  PdfColors.danger,
                  boldColumnIndex: 2),
            ]),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildMiniSummaryRow(
      ArabicPdfFonts fonts, _GroupedData group) {
    final isProfit = group.net >= 0;
    return pw.Row(children: [
      pw.Expanded(child: _miniSummaryBox(fonts, 'الدخل',
          EnhancedPdfUtils.formatNumber(group.incomeTotal), PdfColors.success)),
      pw.Expanded(child: _miniSummaryBox(fonts, 'المصروفات',
          EnhancedPdfUtils.formatNumber(group.expenseTotal), PdfColors.danger)),
      pw.Expanded(child: _miniSummaryBox(fonts, 'الرواتب',
          EnhancedPdfUtils.formatNumber(group.salaryTotal), PdfColors.warning)),
      pw.Expanded(child: _miniSummaryBox(fonts, 'الصافي',
          EnhancedPdfUtils.formatNumber(group.net),
          isProfit ? PdfColors.success : PdfColors.danger)),
    ]);
  }

  pw.Widget _miniSummaryBox(
      ArabicPdfFonts fonts, String title, String value, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      margin: const pw.EdgeInsets.only(right: 4),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(children: [
        pw.Text(title,
            style: pw.TextStyle(
                font: fonts.regular, fontSize: 9, color: PdfColors.textWhite)),
        pw.SizedBox(height: 2),
        pw.Text(value,
            style: pw.TextStyle(
                font: fonts.bold, fontSize: 12, color: PdfColors.textWhite)),
      ]),
    );
  }

  pw.Widget _buildMiniTable(
      ArabicPdfFonts fonts,
      String title,
      List<String> headers,
      List<List<String>> rows,
      PdfColor headerColor,
      {int boldColumnIndex = -1}) {
    if (rows.isEmpty) return pw.Container();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title,
            style: pw.TextStyle(
                font: fonts.bold, fontSize: 10, color: headerColor)),
        pw.SizedBox(height: 3),
        pw.Container(
          decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.textLight, width: 0.3)),
          child: pw.Table(children: [
            pw.TableRow(
                decoration: pw.BoxDecoration(color: headerColor),
                children: headers
                    .map((h) =>
                        _miniCell(h, fonts.bold, PdfColors.textWhite))
                    .toList()),
            ...rows.asMap().entries.map((entry) => pw.TableRow(
                decoration: entry.key.isEven
                    ? const pw.BoxDecoration(
                        color: PdfColors.backgroundLight)
                    : null,
                children: entry.value.asMap().entries.map((cell) {
                  final isBold = cell.key == boldColumnIndex;
                  return _miniCell(
                    cell.value,
                    isBold ? fonts.bold : fonts.regular,
                    PdfColors.textDark,
                    align: isBold ? pw.TextAlign.left : pw.TextAlign.center,
                  );
                }).toList())),
          ]),
        ),
      ],
    );
  }

  pw.Widget _miniCell(String text, pw.Font font, PdfColor color,
      {pw.TextAlign align = pw.TextAlign.center}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      child: pw.Text(text,
          style: pw.TextStyle(font: font, fontSize: 8, color: color),
          textAlign: align),
    );
  }

  pw.Widget _buildFinalSummarySection(
      ArabicPdfFonts fonts, List<_GroupedData> groups) {
    _GroupedData? bestPeriod;
    _GroupedData? worstPeriod;
    double maxProfit = double.negativeInfinity;
    double maxLoss = double.infinity;
    for (final g in groups) {
      if (g.net > maxProfit) {
        maxProfit = g.net;
        bestPeriod = g;
      }
      if (g.net < maxLoss) {
        maxLoss = g.net;
        worstPeriod = g;
      }
    }
    final totalTx = _incomeEntries.length + _expenseEntries.length;
    final avgDaily = groups.isEmpty ? 0.0 : _net / groups.length;

    final data = <List<String>>[
      ['إجمالي المعاملات', '$totalTx معاملة'],
      ['عدد الفترات', '${groups.length} فترة'],
      ['متوسط الصافي لكل فترة', EnhancedPdfUtils.formatNumber(avgDaily)],
      ['إجمالي الدخل', EnhancedPdfUtils.formatNumber(_incomeTotal)],
      ['إجمالي المصروفات', EnhancedPdfUtils.formatNumber(_expenseTotal)],
      ['مصروفات الرواتب', EnhancedPdfUtils.formatNumber(_salaryTotal)],
      ['الصافي النهائي', EnhancedPdfUtils.formatNumber(_net)],
      if (bestPeriod != null)
        [
          'أفضل فترة (أعلى ربح)',
          '${bestPeriod.label} - ${EnhancedPdfUtils.formatNumber(bestPeriod.net)}'
        ],
      if (worstPeriod != null && worstPeriod.net < 0)
        [
          'أسوأ فترة (أعلى خسارة)',
          '${worstPeriod.label} - ${EnhancedPdfUtils.formatNumber(worstPeriod.net)}'
        ],
    ];

    return _buildSectionWithTable(fonts, 'الملخص النهائي الشامل',
        PdfColors.primary, ['البيان', 'القيمة'], data,
        columnWidths: [180, 150]);
  }

  // ------------------------------------------------
  // دوال التصدير والطباعة
  // ------------------------------------------------
  String _getFilename({String suffix = ''}) {
    final s = suffix.isNotEmpty ? '-$suffix' : '';
    return 'تقرير-الدورة-المالية-الشامل$s-${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';
  }

  Future<void> _exportPdf() async {
    if (!_hasData) return;
    await _withLoadingDialog(() async {
      final doc = await _buildPdfDocument();
      await Printing.sharePdf(
          bytes: await doc.save(), filename: _getFilename());
    });
  }

  Future<void> _exportDetailedGroupedPdf(String groupBy) async {
    if (!_hasData) return;
    await _withLoadingDialog(() async {
      final doc = await _buildDetailedGroupedPdf(groupBy);
      await Printing.sharePdf(
          bytes: await doc.save(),
          filename: _getFilename(suffix: _getGroupTypeLabel(groupBy)));
    });
  }

  Future<void> _printPdf() async {
    if (!_hasData) return;
    await _withLoadingDialog(() async {
      final doc = await _buildPdfDocument();
      await Printing.layoutPdf(onLayout: (format) async => doc.save());
    });
  }

  Future<void> _savePdf() async {
    if (!_hasData) return;
    await _withLoadingDialog(() async {
      final doc = await _buildPdfDocument();
      final bytes = await doc.save();
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${_getFilename()}');
      await file.writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حفظ الملف: ${file.path}'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    });
  }

  Future<void> _exportCsv() async {
    if (!_hasData) return;
    await _withLoadingDialog(() async {
      final buffer = StringBuffer();
      buffer.writeln('\uFEFF');
      buffer.writeln('النوع,التاريخ,الوصف,المبلغ,التصنيف');

      final allEntries = <Map<String, dynamic>>[];
      for (final e in _incomeEntries) {
        allEntries.add({
          'type': 'دخل',
          'date': _dateFormat.format(e.date),
          'desc': e.description,
          'amount': e.amount,
          'category': 'دفعة',
        });
      }
      for (final e in _expenseEntries) {
        allEntries.add({
          'type': e.isSalary ? 'راتب' : 'مصروف',
          'date': _dateFormat.format(e.date),
          'desc': e.description.isNotEmpty ? e.description : e.type,
          'amount': e.amount,
          'category': e.type,
        });
      }
      allEntries.sort((a, b) => DateTime.parse(a['date'] as String)
          .compareTo(DateTime.parse(b['date'] as String)));

      for (final entry in allEntries) {
        buffer.writeln(
          '${entry["type"]},${entry["date"]},"${entry["desc"]}",${entry["amount"]},${entry["category"]}',
        );
      }

      buffer.writeln();
      buffer.writeln('الملخص');
      buffer.writeln('إجمالي الدخل,$_incomeTotal');
      buffer.writeln('إجمالي المصروفات,$_expenseTotal');
      buffer.writeln('مصروفات الرواتب,$_salaryTotal');
      buffer.writeln('صافي الربح,$_net');

      final csvBytes = buffer.toString().codeUnits;
      final dir = await getTemporaryDirectory();
      final filename =
          'تقرير-${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(csvBytes);

      if (mounted) {
        await Share.shareXFiles([XFile(file.path)],
            text: 'تقرير الدخل والمصروفات');
      }
    });
  }

  bool get _hasData => _incomeEntries.isNotEmpty || _expenseEntries.isNotEmpty;

  Future<void> _withLoadingDialog(Future<void> Function() task) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await task();
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  // ------------------------------------------------
  // خيارات التصدير
  // ------------------------------------------------
  void _showExportOptions() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'تصدير التقرير',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              _buildExportOption(
                icon: Icons.calendar_today_rounded,
                iconColor: Colors.blue,
                iconBg: const Color(0x1A2196F3),
                title: 'تقرير يومي',
                subtitle: 'تجميع حسب كل يوم (مع اسم اليوم بالعربي)',
                onTap: () {
                  Navigator.pop(context);
                  _exportDetailedGroupedPdf('daily');
                },
              ),
              _buildExportOption(
                icon: Icons.calendar_month_rounded,
                iconColor: Colors.teal,
                iconBg: const Color(0x1A009688),
                title: 'تقرير شهري',
                subtitle: 'تجميع حسب كل شهر (بالأسماء العربية)',
                onTap: () {
                  Navigator.pop(context);
                  _exportDetailedGroupedPdf('monthly');
                },
              ),
              _buildExportOption(
                icon: Icons.date_range_rounded,
                iconColor: Colors.purple,
                iconBg: const Color(0x1A9C27B0),
                title: 'تقرير سنوي',
                subtitle: 'تجميع حسب كل سنة',
                onTap: () {
                  Navigator.pop(context);
                  _exportDetailedGroupedPdf('yearly');
                },
              ),
              const Divider(),
              _buildExportOption(
                icon: Icons.share,
                iconColor: Colors.blue,
                iconBg: const Color(0x1A2196F3),
                title: 'مشاركة PDF',
                subtitle: 'إرسال التقرير العام عبر التطبيقات',
                onTap: () {
                  Navigator.pop(context);
                  _exportPdf();
                },
              ),
              _buildExportOption(
                icon: Icons.print,
                iconColor: Colors.green,
                iconBg: const Color(0x1A4CAF50),
                title: 'طباعة',
                subtitle: 'طباعة التقرير مباشرة',
                onTap: () {
                  Navigator.pop(context);
                  _printPdf();
                },
              ),
              _buildExportOption(
                icon: Icons.save_alt,
                iconColor: Colors.orange,
                iconBg: const Color(0x1AFF9800),
                title: 'حفظ في الجهاز',
                subtitle: 'حفظ كملف PDF',
                onTap: () {
                  Navigator.pop(context);
                  _savePdf();
                },
              ),
              _buildExportOption(
                icon: Icons.table_chart,
                iconColor: Colors.indigo,
                iconBg: const Color(0x1A3F51B5),
                title: 'تصدير CSV',
                subtitle: 'ملف جدول بيانات لفتحه في Excel',
                onTap: () {
                  Navigator.pop(context);
                  _exportCsv();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExportOption({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
      onTap: onTap,
    );
  }

  // ------------------------------------------------
  // واجهة المستخدم
  // ------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final hasData = _hasData;
    return AppScaffold(
      title: 'تقرير الدخل والمصروفات',
      actions: [
        IconButton(
          icon: const Icon(Icons.picture_as_pdf),
          tooltip: 'تصدير PDF',
          onPressed: !hasData || _loading ? null : _showExportOptions,
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          children: [
            NeuCard(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.date_range_rounded,
                            color: Theme.of(context).colorScheme.primary, size: 16),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'فترة التقرير',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ReportDateFilterWidget(
                    controller: _filterController,
                    onDateRangeChanged: (range) {
                      setState(() {
                        _fromDate = range.from ?? _fromDate;
                        _toDate = range.to ?? _toDate;
                      });
                      _fetchReport();
                    },
                    dateButtonsFirst: true,
                    dateButtonsBuilder: (context, onPickFrom, onPickTo) => [
                      Expanded(
                        child: NeuDateButton(
                          icon: Icons.calendar_month_rounded,
                          label: 'من: ${_dateFormat.format(_fromDate)}',
                          onTap: onPickFrom,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: NeuDateButton(
                          icon: Icons.event_rounded,
                          label: 'إلى: ${_dateFormat.format(_toDate)}',
                          onTap: onPickTo,
                        ),
                      ),
                    ],
                    extraChips: [
                      const SizedBox(width: 10),
                      NeuQuickFilterChip(
                        label: _detailedMode ? 'تفصيلي' : 'ملخص',
                        selected: _detailedMode,
                        onTap: () =>
                            setState(() => _detailedMode = !_detailedMode),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _buildSummaryCards(),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : !hasData
                      ? const EmptyState(
                          title: 'لا توجد بيانات',
                          message:
                              'لا يوجد دخل أو مصروفات ضمن الفترة المحددة.',
                          icon: Icons.receipt_long,
                        )
                      : _buildDetails(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        SizedBox(
          width: 140,
          child: NeuStatCard(
            icon: Icons.trending_down_rounded,
            title: 'إجمالي الدخل',
            value: _currencyFormat.format(_incomeTotal),
            iconColor: Colors.green,
            valueColor: Colors.green.shade700,
          ),
        ),
        SizedBox(
          width: 140,
          child: NeuStatCard(
            icon: Icons.trending_up_rounded,
            title: 'إجمالي المصروفات',
            value: _currencyFormat.format(_expenseTotal),
            iconColor: Colors.red,
            valueColor: Colors.red.shade700,
          ),
        ),
        SizedBox(
          width: 140,
          child: NeuStatCard(
            icon: Icons.people_rounded,
            title: 'مصروفات الرواتب',
            value: _currencyFormat.format(_salaryTotal),
            iconColor: Colors.orange,
            valueColor: Colors.orange.shade700,
          ),
        ),
        SizedBox(
          width: 140,
          child: NeuStatCard(
            icon: _net >= 0
                ? Icons.rocket_launch_rounded
                : Icons.warning_rounded,
            title: 'صافي الربح',
            value: _currencyFormat.format(_net),
            iconColor: _net >= 0 ? Colors.teal : Colors.red,
            valueColor: _net >= 0 ? Colors.teal.shade700 : Colors.red.shade700,
            emphasize: true,
          ),
        ),
      ],
    );
  }

  Widget _buildDetails() {
    if (!_detailedMode) return _buildStatsList();
    return _buildCombinedList();
  }

  Widget _buildCombinedList() {
    final List<_CombinedEntry> combined = [];
    for (final e in _incomeEntries) {
      combined.add(_CombinedEntry(
          date: e.date,
          description: e.description,
          amount: e.amount,
          isIncome: true,
          isSalary: false,
          type: ''));
    }
    for (final e in _expenseEntries) {
      combined.add(_CombinedEntry(
          date: e.date,
          description: e.description.isNotEmpty ? e.description : e.type,
          amount: e.amount,
          isIncome: false,
          isSalary: e.isSalary,
          type: e.type));
    }
    combined.sort((a, b) => b.date.compareTo(a.date));

    return ListView.builder(
      cacheExtent: 500,
      itemCount: combined.length,
      itemBuilder: (context, index) {
        final entry = combined[index];
        final color = entry.isIncome
            ? Colors.green
            : (entry.isSalary ? Colors.orange : Colors.red);
        final icon = entry.isIncome
            ? Icons.arrow_downward
            : (entry.isSalary ? Icons.people : Icons.arrow_upward);

        return Card(
          elevation: 0.5,
          margin: const EdgeInsets.symmetric(vertical: 2),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            dense: true,
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.1),
              radius: 14,
              child: Icon(icon, color: color, size: 14),
            ),
            title: Text(entry.description, style: const TextStyle(fontSize: 11)),
            subtitle: Row(
              children: [
                Text(_dateFormat.format(entry.date),
                    style: const TextStyle(fontSize: 9)),
                const SizedBox(width: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    entry.isIncome
                        ? 'دخل'
                        : (entry.isSalary ? 'راتب' : 'مصروف'),
                    style: TextStyle(fontSize: 8, color: color),
                  ),
                ),
              ],
            ),
            trailing: Text(
              '${entry.isIncome ? '+' : '-'}${_currencyFormat.format(entry.amount)}',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: color, fontSize: 11),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatsList() {
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            dense: true,
            leading: const Icon(Icons.arrow_downward,
                color: Colors.green, size: 18),
            title: const Text('عدد معاملات الدخل',
                style: TextStyle(fontSize: 11)),
            trailing: Text('${_incomeEntries.length}',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: const Icon(Icons.arrow_upward,
                color: Colors.red, size: 18),
            title: const Text('عدد معاملات المصروفات',
                style: TextStyle(fontSize: 11)),
            trailing: Text('${_expenseEntries.length}',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading:
                const Icon(Icons.people, color: Colors.orange, size: 18),
            title: const Text('عدد معاملات الرواتب',
                style: TextStyle(fontSize: 11)),
            trailing: Text(
              '${_expenseEntries.where((e) => e.isSalary).length}',
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------
  // أسماء مترجمة
  // ------------------------------------------------
  static const _arabicDays = [
    'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس',
    'الجمعة', 'السبت', 'الأحد',
  ];
  static const _arabicMonths = [
    '', 'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

  String _arabicDayName(DateTime date) => _arabicDays[date.weekday - 1];

  String _paymentMethodName(String method) {
    switch (method) {
      case 'cash': return 'نقداً';
      case 'card': return 'بطاقة';
      case 'transfer': return 'تحويل';
      case 'check': return 'شيك';
      default: return method.isNotEmpty ? method : '-';
    }
  }

  String _revenueTypeName(String type) {
    switch (type) {
      case 'room': return 'إقامة';
      case 'restaurant': return 'مطعم';
      case 'services': return 'خدمات';
      case 'other': return 'أخرى';
      default: return type.isNotEmpty ? type : 'إقامة';
    }
  }
}

// ------------------------------------------------
// نماذج البيانات
// ------------------------------------------------
class _GroupedData {
  _GroupedData({
    required this.index,
    required this.key,
    required this.label,
    required this.incomeEntries,
    required this.expenseEntries,
    required this.incomeTotal,
    required this.expenseTotal,
    required this.salaryTotal,
    required this.net,
    required this.incomeCount,
    required this.expenseCount,
  });
  final int index;
  final String key;
  final String label;
  final List<_IncomeEntry> incomeEntries;
  final List<_ExpenseEntry> expenseEntries;
  final double incomeTotal;
  final double expenseTotal;
  final double salaryTotal;
  final double net;
  final int incomeCount;
  final int expenseCount;
}

class _IncomeEntry {
  _IncomeEntry({
    required this.date,
    required this.description,
    required this.amount,
    this.roomNumber = '',
    this.guestName = '',
    this.paymentMethod = '',
    this.revenueType = '',
  });
  final DateTime date;
  final String description;
  final double amount;
  final String roomNumber;
  final String guestName;
  final String paymentMethod;
  final String revenueType;
}

class _ExpenseEntry {
  _ExpenseEntry({
    required this.date,
    required this.type,
    required this.description,
    required this.amount,
    required this.isSalary,
  });
  final DateTime date;
  final String type;
  final String description;
  final double amount;
  final bool isSalary;
}

class _CombinedEntry {
  _CombinedEntry({
    required this.date,
    required this.description,
    required this.amount,
    required this.isIncome,
    required this.isSalary,
    required this.type,
  });
  final DateTime date;
  final String description;
  final double amount;
  final bool isIncome;
  final bool isSalary;
  final String type;
}

class _ReportParams {
  _ReportParams({
    required this.payments,
    required this.expenses,
    required this.fromDate,
    required this.toDate,
    this.bookingsCount = 0,
    this.activeBookingsCount = 0,
    this.checkoutBookingsCount = 0,
    this.totalDebtsCount = 0,
    this.unsettledDebtsCount = 0,
    this.unsettledDebtsAmount = 0,
    this.unsettledDebtsInPeriodCount = 0,
    this.unsettledDebtsInPeriodAmount = 0,
    this.activeEmployeesCount = 0,
    this.terminatedEmployeesCount = 0,
    this.totalSalaryObligation = 0,
  });
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> expenses;
  final DateTime fromDate;
  final DateTime toDate;
  final int bookingsCount;
  final int activeBookingsCount;
  final int checkoutBookingsCount;
  final int totalDebtsCount;
  final int unsettledDebtsCount;
  final double unsettledDebtsAmount;
  final int unsettledDebtsInPeriodCount;
  final double unsettledDebtsInPeriodAmount;
  final int activeEmployeesCount;
  final int terminatedEmployeesCount;
  final double totalSalaryObligation;
}

class _ReportResult {
  _ReportResult({
    required this.incomeEntries,
    required this.expenseEntries,
    required this.incomeTotal,
    required this.expenseTotal,
    required this.salaryTotal,
    required this.net,
    this.bookingsCount = 0,
    this.activeBookingsCount = 0,
    this.checkoutBookingsCount = 0,
    this.totalDebtsCount = 0,
    this.unsettledDebtsCount = 0,
    this.unsettledDebtsAmount = 0,
    this.unsettledDebtsInPeriodCount = 0,
    this.unsettledDebtsInPeriodAmount = 0,
    this.activeEmployeesCount = 0,
    this.terminatedEmployeesCount = 0,
    this.totalSalaryObligation = 0,
  });
  final List<_IncomeEntry> incomeEntries;
  final List<_ExpenseEntry> expenseEntries;
  final double incomeTotal;
  final double expenseTotal;
  final double salaryTotal;
  final double net;
  final int bookingsCount;
  final int activeBookingsCount;
  final int checkoutBookingsCount;
  final int totalDebtsCount;
  final int unsettledDebtsCount;
  final double unsettledDebtsAmount;
  final int unsettledDebtsInPeriodCount;
  final double unsettledDebtsInPeriodAmount;
  final int activeEmployeesCount;
  final int terminatedEmployeesCount;
  final double totalSalaryObligation;
}

_ReportResult _processReportData(_ReportParams params) {
  bool isSalaryExpense(String type) {
    final normalized = type.trim();
    return normalized == 'رواتب' ||
        normalized == 'سحب راتب' ||
        normalized == 'سحب من الراتب' ||
        normalized == 'خصم راتب' ||
        normalized == 'خصم من الراتب' ||
        normalized.contains('راتب');
  }

  final incomeList = <_IncomeEntry>[];
  for (final p in params.payments) {
    final dateStr = (p['date'] ?? '').toString().trim();
    if (dateStr.isEmpty) continue;
    DateTime? dt;
    try {
      dt = DateTime.parse(
          dateStr.length > 10 ? dateStr.replaceFirst(' ', 'T') : dateStr);
    } catch (_) {
      continue;
    }
    final room = (p['roomNumber'] ?? '').toString().trim();
    final desc = room.isNotEmpty ? 'دفعة من حجز رقم $room' : 'دفعة من حجز';
    incomeList.add(_IncomeEntry(
      date: dt,
      description: desc,
      amount: ((p['amount'] ?? 0) as num).toDouble(),
      roomNumber: room,
      guestName: (p['guestName'] ?? '').toString(),
      paymentMethod: (p['paymentMethod'] ?? '').toString(),
      revenueType: (p['revenueType'] ?? '').toString(),
    ));
  }

  final expenseList = <_ExpenseEntry>[];
  for (final e in params.expenses) {
    final dateStr = (e['date'] ?? '').toString().trim();
    if (dateStr.isEmpty) continue;
    DateTime? dt;
    try {
      dt = DateTime.parse(
          dateStr.length > 10 ? dateStr.replaceFirst(' ', 'T') : dateStr);
    } catch (_) {
      continue;
    }
    final type = (e['type'] ?? '').toString();
    expenseList.add(_ExpenseEntry(
      date: dt,
      type: type,
      description: (e['description'] ?? '').toString(),
      amount: ((e['amount'] ?? 0) as num).toDouble(),
      isSalary: isSalaryExpense(type),
    ));
  }

  incomeList.sort((a, b) => a.date.compareTo(b.date));
  expenseList.sort((a, b) => a.date.compareTo(b.date));

  final incTotal = incomeList.fold(0.0, (s, e) => s + e.amount);
  final expTotal = expenseList.fold(0.0, (s, e) => s + e.amount);
  final salTotal =
      expenseList.where((e) => e.isSalary).fold(0.0, (s, e) => s + e.amount);

  return _ReportResult(
    incomeEntries: incomeList,
    expenseEntries: expenseList,
    incomeTotal: incTotal,
    expenseTotal: expTotal,
    salaryTotal: salTotal,
    net: incTotal - expTotal,
    bookingsCount: params.bookingsCount,
    activeBookingsCount: params.activeBookingsCount,
    checkoutBookingsCount: params.checkoutBookingsCount,
    totalDebtsCount: params.totalDebtsCount,
    unsettledDebtsCount: params.unsettledDebtsCount,
    unsettledDebtsAmount: params.unsettledDebtsAmount,
    unsettledDebtsInPeriodCount: params.unsettledDebtsInPeriodCount,
    unsettledDebtsInPeriodAmount: params.unsettledDebtsInPeriodAmount,
    activeEmployeesCount: params.activeEmployeesCount,
    terminatedEmployeesCount: params.terminatedEmployeesCount,
    totalSalaryObligation: params.totalSalaryObligation,
  );
}
