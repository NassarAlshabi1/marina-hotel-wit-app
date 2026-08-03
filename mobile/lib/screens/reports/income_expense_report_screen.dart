// TODO(phase-2): remove this ignore and fix violations (discarded_futures)
// ignore_for_file: discarded_futures
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
import '../../services/daos/employees_dao.dart';
import '../../services/daos/expenses_dao.dart';
import '../../services/daos/outbox_dao.dart';
import '../../services/daos/payments_dao.dart';
import '../../utils/enhanced_pdf_utils.dart';
import '../../utils/hotel_time_engine.dart';
import '../../utils/status_utils.dart';
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

  DateTime? _fromDate;
  DateTime? _toDate;

  bool _loading = false;
  bool _detailedMode = false;

  List<_IncomeEntry> _incomeEntries = [];
  List<_ExpenseEntry> _expenseEntries = [];

  double _incomeTotal = 0;
  double _expenseTotal = 0;
  double _salaryTotal = 0;
  double _net = 0;

  // بيانات إضافية للدورة المالية
  int _bookingsCount = 0;
  int _activeBookingsCount = 0;
  int _checkoutBookingsCount = 0;
  int _totalDebtsCount = 0;
  int _unsettledDebtsCount = 0;
  double _unsettledDebtsAmount = 0;
  int _activeEmployeesCount = 0;
  int _terminatedEmployeesCount = 0;
  double _totalSalaryObligation = 0;
  // الديون غير المسددة في الفترة المحددة فقط
  int _unsettledDebtsInPeriodCount = 0;
  double _unsettledDebtsInPeriodAmount = 0;

  @override
  void initState() {
    super.initState();
    // الافتراضي: اليوم الفندقي الحالي (14:01 → 14:00)
    final range = DateFilterController.getDefaultHotelDayRange();
    _fromDate = range.from;
    _toDate = range.to;
    _fetchReport();
  }

  Future<void> _fetchReport() async {
    setState(() => _loading = true);
    try {
      final db = ref.read(databaseProvider);
      final outboxDao = OutboxDao(db);
      final paymentsDao = PaymentsDao(db, outboxDao);
      final expensesDao = ExpensesDao(db, outboxDao);

      // ═══════════════════════════════════════════════════════════════
      // حساب نطاق الفلترة بدقة خارقة
      // _fromDate يأتي من ReportDateFilterWidget:
      //   - اليوم الفندقي: 14:01 أمس/اليوم → 14:00:59 اليوم/غداً
      //   - الأسبوع: 14:01 بداية الأسبوع → 14:00:59 نهاية اليوم
      //   - الشهر: 14:01 أول الشهر → 14:00:59 نهاية اليوم
      //   - السنة: 14:01 أول السنة → 14:00:59 نهاية اليوم
      //   - يدوي: من تاريخ → إلى تاريخ
      //
      // _fromDate دائماً يحتوي على وقت البداية (14:01 أو وقت منتقي)
      // _toDate دائماً يحتوي على وقت النهاية (14:00:59 أو وقت منتقي)
      // ═══════════════════════════════════════════════════════════════
      final fromDate = _fromDate!;
      final toDate = _toDate!;

      // ✅ إصلاح: المدفوعات والمصروفات تُفلتر بـ hotelDayKey بدلاً من date التقويمي
      // لمنع إدراج معاملات الصباح التي تنتمي لليوم الفندقي السابق
      // ✅ استخدام HotelTimeEngine.getHotelDayKey للتوافق مع البيانات المُخزنة
      // PaymentsRepository.create() و ExpensesRepository.create()
      // يخزنان hotelDayKey باستخدام HotelTimeEngine
      // فلابد أن تكون الفلترة بنفس الدالة لتطابق المفاتيح
      //
      // ⚠️ ملاحظة حرجة: getHotelDayKey تعتبر 14:00:59 بالضبط نهاية اليوم السابق
      // (14:01:00 = بداية اليوم الجديد). بما أن fromDate يأتي دائماً بوقت 14:01:00
      // من ReportDateFilterWidget، نحتاج إضافة ثانية واحدة لضمان
      // أن getHotelDayKey يُعيد اليوم الصحيح (وليس السابق)
      final fromHotelDay = HotelTimeEngine.getHotelDayKey(
        dateTime: fromDate.add(const Duration(seconds: 1)),
      );
      final toHotelDay = HotelTimeEngine.getHotelDayKey(dateTime: toDate);

      final payments = await paymentsDao.listFilteredByHotelDay(
        fromHotelDay: fromHotelDay,
        toHotelDay: toHotelDay,
        excludeVoided: true,
        excludePendingBalance: true,
      );

      // ✅ استبعاد السلفة — تسبب تكرار بيانات لأن مبالغها تظهر أيضاً كأقساط خصم من الراتب
      final expenses = await expensesDao.listFilteredByHotelDay(
        fromHotelDay: fromHotelDay,
        toHotelDay: toHotelDay,
        excludeAdvance: true,
      );

      // بيانات إضافية للتقرير التفصيلي للدورة المالية
      final bookingsDao = BookingsDao(db, outboxDao);
      final debtsDao = DebtsDao(db, outboxDao);
      final employeesDao = EmployeesDao(db, outboxDao);

      // الحجوزات: فلترة بنطاق تاريخ checkin (تاريخ فقط بدون وقت)
      final bookingFromStr = DateFormat('yyyy-MM-dd').format(fromDate);
      final bookingToStr = DateFormat('yyyy-MM-dd').format(toDate);
      final bookings = await bookingsDao.list(
        from: bookingFromStr,
        to: bookingToStr,
      );

      // الديون: فلترة بتاريخ التسجيل ضمن الفترة المحددة
      final allDebts = await debtsDao.list();
      final debtsInPeriod = allDebts.where((d) {
        // فلترة الديون بنطاق التاريخ
        if (d.dateRecorded.isNotEmpty) {
          try {
            final debtDate = DateTime.parse(
              d.dateRecorded.length > 10
                  ? d.dateRecorded.replaceFirst(' ', 'T')
                  : d.dateRecorded,
            );
            // مقارنة باليوم فقط (بدون وقت) ضمن النطاق
            final debtDay = DateTime(
              debtDate.year,
              debtDate.month,
              debtDate.day,
            );
            final fromDay = DateTime(
              fromDate.year,
              fromDate.month,
              fromDate.day,
            );
            final toDay = DateTime(toDate.year, toDate.month, toDate.day);
            return !debtDay.isBefore(fromDay) && !debtDay.isAfter(toDay);
          } catch (e) {
            debugPrint(
              '⚠️ تعذر تحليل تاريخ الدين dateRecorded="${d.dateRecorded}": $e',
            );
            return false; // استبعاد السجل غير الصالح من فلترة الفترة
          }
        }
        // إذا لم يوجد dateRecorded نعتمد على paymentDate
        if (d.paymentDate.isNotEmpty) {
          try {
            final debtDate = DateTime.parse(
              d.paymentDate.length > 10
                  ? d.paymentDate.replaceFirst(' ', 'T')
                  : d.paymentDate,
            );
            final debtDay = DateTime(
              debtDate.year,
              debtDate.month,
              debtDate.day,
            );
            final fromDay = DateTime(
              fromDate.year,
              fromDate.month,
              fromDate.day,
            );
            final toDay = DateTime(toDate.year, toDate.month, toDate.day);
            return !debtDay.isBefore(fromDay) && !debtDay.isAfter(toDay);
          } catch (e) {
            debugPrint(
              '⚠️ تعذر تحليل تاريخ الدين paymentDate="${d.paymentDate}": $e',
            );
            return false; // استبعاد السجل غير الصالح من فلترة الفترة
          }
        }
        return false; // ✅ إصلاح: استبعاد الديون بدون تواريخ صالحة
      }).toList();

      // الديون غير المسددة: نحتاج كل الديون غير المسددة (حتى خارج الفترة)
      // لأنها تمثل التزامات مالية لا تزال قائمة
      final unsettledDebtsAll = allDebts
          .where((d) => d.isSettled == 0)
          .toList();

      final allEmployees = await employeesDao.list();
      final employees = allEmployees
          .where((e) => StatusUtils.isEmployeeActive(e.status))
          .toList();
      final terminatedEmployees = allEmployees
          .where((e) => StatusUtils.isEmployeeTerminated(e.status))
          .toList();

      // بناء خريطة بين معرف الحجز واسم النزيل لاستخدامه في المدفوعات
      final bookingGuestMap = <int, String>{};
      for (final b in bookings) {
        bookingGuestMap[b.id] = b.guestName;
      }
      // جلب كل الحجوزات لبناء خريطة شاملة (لأن بعض المدفوعات قد تكون لحجوزات خارج الفترة)
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
          fromDate: _fromDate!,
          toDate: _toDate!,
          bookingsCount: bookings.length,
          activeBookingsCount: bookings
              .where((b) => b.status == 'checked_in')
              .length,
          checkoutBookingsCount: bookings
              .where((b) => b.status == 'checked_out')
              .length,
          totalDebtsCount: debtsInPeriod.length,
          unsettledDebtsCount: unsettledDebtsAll.length,
          unsettledDebtsAmount: unsettledDebtsAll.fold<double>(
            0,
            (s, d) => s + d.remainingAmount,
          ),
          unsettledDebtsInPeriodCount: debtsInPeriod
              .where((d) => d.isSettled == 0)
              .length,
          unsettledDebtsInPeriodAmount: debtsInPeriod
              .where((d) => d.isSettled == 0)
              .fold<double>(0, (s, d) => s + d.remainingAmount),
          activeEmployeesCount: employees.length,
          terminatedEmployeesCount: terminatedEmployees.length,
          totalSalaryObligation: employees.fold<double>(
            0,
            (s, e) => s + e.basicSalary,
          ),
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
      }
    }
  }

  // ===== أسماء الأيام والشهور بالعربي =====
  static const _arabicDays = [
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
    'الأحد',
  ];
  static const _arabicMonths = [
    '',
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  String _arabicDayName(DateTime date) {
    return _arabicDays[date.weekday - 1];
  }

  // ===== تجميع البيانات =====
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
        return '${_arabicMonths[int.parse(parts[1])]} ${parts[0]}';
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
      final incTotal = inc.fold<double>(0, (s, e) => s + e.amount);
      final expTotal = exp.fold<double>(0, (s, e) => s + e.amount);
      final salTotal = exp
          .where((e) => e.isSalary)
          .fold<double>(0, (s, e) => s + e.amount);
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

  // ===== بناء PDF التقرير التفصيلي للدورة المالية الكاملة =====
  Future<pw.Document> _buildPdfDocument() async {
    final fonts = await EnhancedPdfUtils.loadArabicFonts();
    final doc = pw.Document();
    final fromLabel = DateFormat('yyyy-MM-dd').format(_fromDate!);
    final toLabel = DateFormat('yyyy-MM-dd').format(_toDate!);
    final nonSalaryExpenses = _expenseTotal - _salaryTotal;

    // ===== حسابات تحليل أنواع الإيرادات =====
    final roomRevenue = _incomeEntries
        .where((e) => e.revenueType == 'room' || e.revenueType.isEmpty)
        .fold<double>(0, (s, e) => s + e.amount);
    final otherRevenue = _incomeTotal - roomRevenue;

    // ===== حسابات تحليل أنواع المصروفات =====
    final expenseByType = <String, double>{};
    for (final e in _expenseEntries) {
      final key = e.isSalary ? 'رواتب' : e.type;
      expenseByType[key] = (expenseByType[key] ?? 0) + e.amount;
    }
    final sortedExpenseTypes = expenseByType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // ===== مؤشرات مالية =====
    final profitMargin = _incomeTotal > 0 ? (_net / _incomeTotal * 100) : 0.0;
    final expenseRatio = _incomeTotal > 0
        ? (_expenseTotal / _incomeTotal * 100)
        : 0.0;
    final salaryExpenseRatio = _incomeTotal > 0
        ? (_salaryTotal / _incomeTotal * 100)
        : 0.0;
    final debtCoverage = _unsettledDebtsAmount > 0 && _net > 0
        ? _net / _unsettledDebtsAmount
        : 0.0;

    /// صندوق ملخص
    pw.Widget buildSummaryBox(String title, String value, PdfColor color) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.backgroundLight,
          border: pw.Border.all(color: color, width: 0.8),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                font: fonts.regular,
                fontSize: 10,
                color: PdfColors.textLight,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              value,
              style: pw.TextStyle(font: fonts.bold, fontSize: 15, color: color),
            ),
          ],
        ),
      );
    }

    /// عنوان قسم
    pw.Widget buildSectionTitle(String title, PdfColor color) {
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
          final widgets = <pw.Widget>[];

          // ═══════════════════════════════════════
          // القسم 1: رأس التقرير
          // ═══════════════════════════════════════
          widgets.add(
            pw.Container(
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
            ),
          );

          // ═══════════════════════════════════════
          // القسم 2: الملخص التنفيذي
          // ═══════════════════════════════════════
          widgets.add(pw.SizedBox(height: 16));
          widgets.add(buildSectionTitle('الملخص التنفيذي', PdfColors.primary));

          widgets.add(
            pw.Row(
              children: [
                pw.Expanded(
                  child: buildSummaryBox(
                    'إجمالي الإيرادات',
                    EnhancedPdfUtils.formatNumber(_incomeTotal),
                    PdfColors.success,
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: buildSummaryBox(
                    'إجمالي المصروفات',
                    EnhancedPdfUtils.formatNumber(_expenseTotal),
                    PdfColors.danger,
                  ),
                ),
              ],
            ),
          );
          widgets.add(pw.SizedBox(height: 6));
          widgets.add(
            pw.Row(
              children: [
                pw.Expanded(
                  child: buildSummaryBox(
                    'مصروفات الرواتب',
                    EnhancedPdfUtils.formatNumber(_salaryTotal),
                    PdfColors.warning,
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: buildSummaryBox(
                    'مصروفات تشغيلية',
                    EnhancedPdfUtils.formatNumber(nonSalaryExpenses),
                    PdfColors.info,
                  ),
                ),
              ],
            ),
          );
          widgets.add(pw.SizedBox(height: 6));
          widgets.add(
            pw.Row(
              children: [
                pw.Expanded(
                  child: buildSummaryBox(
                    'صافي الربح / الخسارة',
                    EnhancedPdfUtils.formatNumber(_net),
                    _net >= 0 ? PdfColors.success : PdfColors.danger,
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: buildSummaryBox(
                    'هامش الربح',
                    '${profitMargin.toStringAsFixed(1)}%',
                    profitMargin > 0 ? PdfColors.success : PdfColors.danger,
                  ),
                ),
              ],
            ),
          );

          // ═══════════════════════════════════════
          // القسم 3: تفاصيل الإيرادات
          // ═══════════════════════════════════════
          widgets.add(buildSectionTitle('تفاصيل الإيرادات', PdfColors.success));

          if (_incomeEntries.isNotEmpty) {
            widgets.add(
              EnhancedPdfUtils.buildProfessionalTable(
                headers: [
                  '#',
                  'التاريخ',
                  'الغرفة',
                  'النزيل',
                  'طريقة الدفع',
                  'نوع الإيراد',
                  'المبلغ',
                ],
                fonts: fonts,
                headerColor: PdfColors.success,
                alternateRowColor: PdfColors.backgroundLight,
                data: _incomeEntries.asMap().entries.map((entry) {
                  final e = entry.value;
                  final i = entry.key + 1;
                  return [
                    '$i',
                    _dateFormat.format(e.date),
                    if (e.roomNumber.isNotEmpty) e.roomNumber else '-',
                    if (e.guestName.isNotEmpty) e.guestName else '-',
                    _paymentMethodName(e.paymentMethod),
                    _revenueTypeName(e.revenueType),
                    EnhancedPdfUtils.formatNumber(e.amount),
                  ];
                }).toList(),
              ),
            );
          }

          // ═══════════════════════════════════════
          // القسم 4: تحليل طرق الدفع
          // ═══════════════════════════════════════
          widgets.add(
            buildSectionTitle('تحليل طرق الدفع', PdfColors.secondary),
          );
          widgets.add(_buildPaymentMethodsTable(fonts));

          // ═══════════════════════════════════════
          // القسم 5: تفاصيل المصروفات
          // ═══════════════════════════════════════
          widgets.add(buildSectionTitle('تفاصيل المصروفات', PdfColors.danger));

          if (_expenseEntries.isNotEmpty) {
            widgets.add(
              EnhancedPdfUtils.buildProfessionalTable(
                headers: ['#', 'التاريخ', 'النوع', 'الوصف', 'المبلغ'],
                fonts: fonts,
                headerColor: PdfColors.danger,
                alternateRowColor: PdfColors.backgroundLight,
                data: _expenseEntries.asMap().entries.map((entry) {
                  final e = entry.value;
                  final i = entry.key + 1;
                  return [
                    '$i',
                    _dateFormat.format(e.date),
                    if (e.isSalary) 'رواتب' else e.type,
                    if (e.description.isNotEmpty) e.description else '-',
                    EnhancedPdfUtils.formatNumber(e.amount),
                  ];
                }).toList(),
              ),
            );
          }

          // ═══════════════════════════════════════
          // القسم 6: تحليل المصروفات حسب الفئة
          // ═══════════════════════════════════════
          if (sortedExpenseTypes.isNotEmpty) {
            widgets.add(
              buildSectionTitle('تحليل المصروفات حسب الفئة', PdfColors.accent),
            );
            widgets.add(
              EnhancedPdfUtils.buildProfessionalTable(
                headers: [
                  'الفئة',
                  'المبلغ',
                  'النسبة من الإيرادات',
                  'النسبة من المصروفات',
                ],
                fonts: fonts,
                headerColor: PdfColors.accent,
                alternateRowColor: PdfColors.backgroundLight,
                data: sortedExpenseTypes.map((entry) {
                  return [
                    entry.key,
                    EnhancedPdfUtils.formatNumber(entry.value),
                    if (_incomeTotal > 0)
                      '${(entry.value / _incomeTotal * 100).toStringAsFixed(1)}%'
                    else
                      '0%',
                    if (_expenseTotal > 0)
                      '${(entry.value / _expenseTotal * 100).toStringAsFixed(1)}%'
                    else
                      '0%',
                  ];
                }).toList(),
              ),
            );
          }

          // ═══════════════════════════════════════
          // القسم 7: تكاليف الموارد البشرية
          // ═══════════════════════════════════════
          widgets.add(
            buildSectionTitle('تكاليف الموارد البشرية', PdfColors.warning),
          );
          widgets.add(
            EnhancedPdfUtils.buildProfessionalTable(
              headers: ['البيان', 'القيمة'],
              fonts: fonts,
              headerColor: PdfColors.warning,
              alternateRowColor: PdfColors.backgroundLight,
              columnWidths: [200, 130],
              data: [
                ['عدد الموظفين النشطين', '$_activeEmployeesCount موظف'],
                [
                  'عدد الموظفين المنهية خدمتهم',
                  '$_terminatedEmployeesCount موظف',
                ],
                [
                  'إجمالي الالتزامات الرواتب الشهرية',
                  EnhancedPdfUtils.formatNumber(_totalSalaryObligation),
                ],
                [
                  'الرواتب المدفوعة في الفترة',
                  EnhancedPdfUtils.formatNumber(_salaryTotal),
                ],
                [
                  'نسبة الرواتب من الإيرادات',
                  '${salaryExpenseRatio.toStringAsFixed(1)}%',
                ],
                [
                  'نسبة الرواتب من المصروفات',
                  if (_expenseTotal > 0)
                    '${(_salaryTotal / _expenseTotal * 100).toStringAsFixed(1)}%'
                  else
                    '0%',
                ],
              ],
            ),
          );

          // ═══════════════════════════════════════
          // القسم 8: تحليل الديون
          // ═══════════════════════════════════════
          widgets.add(
            buildSectionTitle('تحليل الديون المستحقة', PdfColors.danger),
          );
          widgets.add(_buildDebtAnalysisTable(fonts, debtCoverage));

          // ═══════════════════════════════════════
          // القسم 9: إحصائيات الحجوزات والإشغال
          // ═══════════════════════════════════════
          widgets.add(
            buildSectionTitle('إحصائيات الحجوزات والإشغال', PdfColors.info),
          );
          widgets.add(
            EnhancedPdfUtils.buildProfessionalTable(
              headers: ['البيان', 'القيمة'],
              fonts: fonts,
              headerColor: PdfColors.info,
              alternateRowColor: PdfColors.backgroundLight,
              columnWidths: [200, 130],
              data: [
                ['إجمالي الحجوزات في الفترة', '$_bookingsCount حجز'],
                ['حجوزات نشطة (داخلين)', '$_activeBookingsCount حجز'],
                ['حجوزات مغادرة', '$_checkoutBookingsCount حجز'],
                [
                  'متوسط الإيراد لكل حجز',
                  if (_bookingsCount > 0)
                    EnhancedPdfUtils.formatNumber(_incomeTotal / _bookingsCount)
                  else
                    '0',
                ],
              ],
            ),
          );

          // ═══════════════════════════════════════
          // القسم 10: المؤشرات المالية الرئيسية
          // ═══════════════════════════════════════
          widgets.add(
            buildSectionTitle('المؤشرات المالية الرئيسية', PdfColors.primary),
          );
          widgets.add(
            _buildFinancialIndicatorsTable(
              fonts,
              profitMargin,
              expenseRatio,
              salaryExpenseRatio,
              debtCoverage,
            ),
          );

          // ═══════════════════════════════════════
          // القسم 11: الملخص المحاسبي الشامل
          // ═══════════════════════════════════════
          widgets.add(
            buildSectionTitle('الملخص المحاسبي الشامل', PdfColors.primary),
          );
          widgets.add(
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.backgroundCard,
                border: pw.Border.all(color: PdfColors.primary),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Column(
                children: [
                  EnhancedPdfUtils.buildProfessionalTable(
                    headers: ['البيان', 'المبلغ'],
                    fonts: fonts,
                    headerColor: PdfColors.primary,
                    alternateRowColor: PdfColors.backgroundLight,
                    columnWidths: [200, 130],
                    data: [
                      [
                        'إيرادات الغرف',
                        EnhancedPdfUtils.formatNumber(roomRevenue),
                      ],
                      [
                        'إيرادات أخرى',
                        EnhancedPdfUtils.formatNumber(otherRevenue),
                      ],
                      [
                        'إجمالي الإيرادات',
                        EnhancedPdfUtils.formatNumber(_incomeTotal),
                      ],
                      [
                        '(-) مصروفات تشغيلية',
                        EnhancedPdfUtils.formatNumber(nonSalaryExpenses),
                      ],
                      [
                        '(-) رواتب ومخصصات',
                        EnhancedPdfUtils.formatNumber(_salaryTotal),
                      ],
                      [
                        'إجمالي المصروفات',
                        EnhancedPdfUtils.formatNumber(_expenseTotal),
                      ],
                      [
                        'صافي الربح / الخسارة',
                        EnhancedPdfUtils.formatNumber(_net),
                      ],
                      [
                        '(+) ديون مستحقة غير مسددة',
                        EnhancedPdfUtils.formatNumber(_unsettledDebtsAmount),
                      ],
                      [
                        'الوضع المالي الصافي',
                        EnhancedPdfUtils.formatNumber(
                          _net - _unsettledDebtsAmount,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );

          // تذييل
          widgets.add(pw.SizedBox(height: 20));
          widgets.add(pw.Divider(color: PdfColors.textLight));
          widgets.add(pw.SizedBox(height: 8));
          widgets.add(
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'تم إنشاء هذا التقرير تلقائياً - فندق مارينا بلازا',
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 9,
                    color: PdfColors.textLight,
                  ),
                ),
                pw.Text(
                  'تقرير الدورة المالية الشامل',
                  style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: 9,
                    color: PdfColors.primary,
                  ),
                ),
              ],
            ),
          );

          return widgets;
        },
      ),
    );

    return doc;
  }

  /// جدول تحليل طرق الدفع (مشترك بين PDF العادي والمجمع)
  pw.Widget _buildPaymentMethodsTable(ArabicPdfFonts fonts) {
    final cashIncome = _incomeEntries
        .where((e) => e.paymentMethod == 'cash')
        .fold<double>(0, (s, e) => s + e.amount);
    final cardIncome = _incomeEntries
        .where((e) => e.paymentMethod == 'card')
        .fold<double>(0, (s, e) => s + e.amount);
    final transferIncome = _incomeEntries
        .where((e) => e.paymentMethod == 'transfer')
        .fold<double>(0, (s, e) => s + e.amount);
    final otherMethodIncome =
        _incomeTotal - cashIncome - cardIncome - transferIncome;

    return EnhancedPdfUtils.buildProfessionalTable(
      headers: ['طريقة الدفع', 'المبلغ', 'العدد', 'النسبة'],
      fonts: fonts,
      headerColor: PdfColors.secondary,
      alternateRowColor: PdfColors.backgroundLight,
      data: [
        [
          'نقداً',
          EnhancedPdfUtils.formatNumber(cashIncome),
          '${_incomeEntries.where((e) => e.paymentMethod == 'cash').length}',
          if (_incomeTotal > 0)
            '${(cashIncome / _incomeTotal * 100).toStringAsFixed(1)}%'
          else
            '0%',
        ],
        [
          'بطاقة ائتمانية',
          EnhancedPdfUtils.formatNumber(cardIncome),
          '${_incomeEntries.where((e) => e.paymentMethod == 'card').length}',
          if (_incomeTotal > 0)
            '${(cardIncome / _incomeTotal * 100).toStringAsFixed(1)}%'
          else
            '0%',
        ],
        [
          'تحويل بنكي',
          EnhancedPdfUtils.formatNumber(transferIncome),
          '${_incomeEntries.where((e) => e.paymentMethod == 'transfer').length}',
          if (_incomeTotal > 0)
            '${(transferIncome / _incomeTotal * 100).toStringAsFixed(1)}%'
          else
            '0%',
        ],
        if (otherMethodIncome > 0)
          [
            'أخرى',
            EnhancedPdfUtils.formatNumber(otherMethodIncome),
            '${_incomeEntries.where((e) => e.paymentMethod != 'cash' && e.paymentMethod != 'card' && e.paymentMethod != 'transfer').length}',
            if (_incomeTotal > 0)
              '${(otherMethodIncome / _incomeTotal * 100).toStringAsFixed(1)}%'
            else
              '0%',
          ],
        [
          'الإجمالي',
          EnhancedPdfUtils.formatNumber(_incomeTotal),
          '${_incomeEntries.length}',
          '100%',
        ],
      ],
    );
  }

  /// جدول تحليل الديون المستحقة (مشترك بين PDF العادي والمجمع)
  pw.Widget _buildDebtAnalysisTable(ArabicPdfFonts fonts, double debtCoverage) {
    return EnhancedPdfUtils.buildProfessionalTable(
      headers: ['البيان', 'القيمة'],
      fonts: fonts,
      headerColor: PdfColors.danger,
      alternateRowColor: PdfColors.backgroundLight,
      columnWidths: [200, 130],
      data: [
        ['إجمالي الديون في الفترة', '$_totalDebtsCount دين'],
        ['ديون غير مسددة في الفترة', '$_unsettledDebtsInPeriodCount دين'],
        [
          'مبلغ الديون غير المسددة في الفترة',
          EnhancedPdfUtils.formatNumber(_unsettledDebtsInPeriodAmount),
        ],
        ['إجمالي الديون غير المسددة (كل الفترات)', '$_unsettledDebtsCount دين'],
        [
          'مبلغ الديون غير المسددة الكلي',
          EnhancedPdfUtils.formatNumber(_unsettledDebtsAmount),
        ],
        [
          'نسبة الديون غير المسددة الكلية من الإيرادات',
          if (_incomeTotal > 0)
            '${(_unsettledDebtsAmount / _incomeTotal * 100).toStringAsFixed(1)}%'
          else
            '0%',
        ],
        [
          'قدرة تغطية الديون (صافي / ديون)',
          if (debtCoverage > 0)
            '${debtCoverage.toStringAsFixed(2)}x'
          else
            'غير كافٍ',
        ],
      ],
    );
  }

  /// جدول المؤشرات المالية الرئيسية (مشترك بين PDF العادي والمجمع)
  pw.Widget _buildFinancialIndicatorsTable(
    ArabicPdfFonts fonts,
    double profitMargin,
    double expenseRatio,
    double salaryExpenseRatio,
    double debtCoverage,
  ) {
    return EnhancedPdfUtils.buildProfessionalTable(
      headers: ['المؤشر', 'القيمة', 'التقييم'],
      fonts: fonts,
      headerColor: PdfColors.primary,
      alternateRowColor: PdfColors.backgroundLight,
      data: [
        [
          'هامش الربح الصافي',
          '${profitMargin.toStringAsFixed(1)}%',
          if (profitMargin > 20)
            'ممتاز'
          else if (profitMargin > 10)
            'جيد'
          else if (profitMargin > 0)
            'مقبول'
          else
            'خسارة',
        ],
        [
          'نسبة المصروفات إلى الإيرادات',
          '${expenseRatio.toStringAsFixed(1)}%',
          if (expenseRatio < 60)
            'ممتاز'
          else if (expenseRatio < 80)
            'جيد'
          else
            'مرتفع',
        ],
        [
          'نسبة الرواتب إلى الإيرادات',
          '${salaryExpenseRatio.toStringAsFixed(1)}%',
          if (salaryExpenseRatio < 30)
            'ممتاز'
          else if (salaryExpenseRatio < 50)
            'جيد'
          else
            'مرتفع',
        ],
        [
          'معدل تغطية الديون',
          if (debtCoverage > 0)
            '${debtCoverage.toStringAsFixed(2)}x'
          else
            'غير كافٍ',
          if (debtCoverage > 2)
            'ممتاز'
          else if (debtCoverage > 1)
            'جيد'
          else
            'ضعيف',
        ],
      ],
    );
  }

  /// ترجمة طريقة الدفع
  String _paymentMethodName(String method) {
    switch (method) {
      case 'cash':
        return 'نقداً';
      case 'card':
        return 'بطاقة';
      case 'transfer':
        return 'تحويل';
      case 'check':
        return 'شيك';
      default:
        return method.isNotEmpty ? method : '-';
    }
  }

  /// ترجمة نوع الإيراد
  String _revenueTypeName(String type) {
    switch (type) {
      case 'room':
        return 'إقامة';
      case 'restaurant':
        return 'مطعم';
      case 'services':
        return 'خدمات';
      case 'other':
        return 'أخرى';
      default:
        return type.isNotEmpty ? type : 'إقامة';
    }
  }

  // ===== بناء PDF التقرير التفصيلي المجمع =====
  Future<pw.Document> _buildDetailedGroupedPdf(String groupBy) async {
    final fonts = await EnhancedPdfUtils.loadArabicFonts();
    final doc = pw.Document();
    final groupedData = _buildGroupedData(groupBy);
    final groupTypeLabel = _getGroupTypeLabel(groupBy);
    final fromLabel = DateFormat('yyyy-MM-dd').format(_fromDate!);
    final toLabel = DateFormat('yyyy-MM-dd').format(_toDate!);

    /// بناء صندوق ملخص ملون
    pw.Widget buildSummaryBox(String title, String value, PdfColor color) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: pw.BoxDecoration(
          color: PdfColors.backgroundLight,
          border: pw.Border.all(color: color, width: 0.8),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                font: fonts.regular,
                fontSize: 10,
                color: PdfColors.textLight,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              value,
              style: pw.TextStyle(font: fonts.bold, fontSize: 15, color: color),
            ),
          ],
        ),
      );
    }

    /// بناء بطاقة فترة مرقمة
    pw.Widget buildPeriodCard(_GroupedData group) {
      final isProfit = group.net >= 0;
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(
            color: isProfit ? PdfColors.success : PdfColors.danger,
            width: 0.8,
          ),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // عنوان الفترة المرقم
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: const pw.BoxDecoration(
                color: PdfColors.primary,
                borderRadius: pw.BorderRadius.only(
                  topLeft: pw.Radius.circular(7),
                  topRight: pw.Radius.circular(7),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '$group.index. ${group.label}',
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 13,
                      color: PdfColors.textWhite,
                    ),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: pw.BoxDecoration(
                      color: isProfit ? PdfColors.success : PdfColors.danger,
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(10),
                      ),
                    ),
                    child: pw.Text(
                      isProfit ? 'ربح' : 'خسارة',
                      style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 9,
                        color: PdfColors.textWhite,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              child: pw.Column(
                children: [
                  // 4 صناديق ملخص مصغرة
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(6),
                          margin: const pw.EdgeInsets.only(left: 4),
                          decoration: const pw.BoxDecoration(
                            color: PdfColors.success,
                            borderRadius: pw.BorderRadius.all(
                              pw.Radius.circular(4),
                            ),
                          ),
                          child: pw.Column(
                            children: [
                              pw.Text(
                                'الدخل',
                                style: pw.TextStyle(
                                  font: fonts.regular,
                                  fontSize: 9,
                                  color: PdfColors.textWhite,
                                ),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                EnhancedPdfUtils.formatNumber(
                                  group.incomeTotal,
                                ),
                                style: pw.TextStyle(
                                  font: fonts.bold,
                                  fontSize: 12,
                                  color: PdfColors.textWhite,
                                ),
                              ),
                              pw.Text(
                                '${group.incomeCount} معاملة',
                                style: pw.TextStyle(
                                  font: fonts.regular,
                                  fontSize: 8,
                                  color: PdfColors.textWhite,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(6),
                          margin: const pw.EdgeInsets.only(left: 4),
                          decoration: const pw.BoxDecoration(
                            color: PdfColors.danger,
                            borderRadius: pw.BorderRadius.all(
                              pw.Radius.circular(4),
                            ),
                          ),
                          child: pw.Column(
                            children: [
                              pw.Text(
                                'المصروفات',
                                style: pw.TextStyle(
                                  font: fonts.regular,
                                  fontSize: 9,
                                  color: PdfColors.textWhite,
                                ),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                EnhancedPdfUtils.formatNumber(
                                  group.expenseTotal,
                                ),
                                style: pw.TextStyle(
                                  font: fonts.bold,
                                  fontSize: 12,
                                  color: PdfColors.textWhite,
                                ),
                              ),
                              pw.Text(
                                '${group.expenseCount} معاملة',
                                style: pw.TextStyle(
                                  font: fonts.regular,
                                  fontSize: 8,
                                  color: PdfColors.textWhite,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(6),
                          decoration: pw.BoxDecoration(
                            color: group.salaryTotal > 0
                                ? PdfColors.warning
                                : PdfColors.backgroundCard,
                            borderRadius: const pw.BorderRadius.all(
                              pw.Radius.circular(4),
                            ),
                          ),
                          child: pw.Column(
                            children: [
                              pw.Text(
                                'الرواتب',
                                style: pw.TextStyle(
                                  font: fonts.regular,
                                  fontSize: 9,
                                  color: group.salaryTotal > 0
                                      ? PdfColors.textWhite
                                      : PdfColors.textLight,
                                ),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                EnhancedPdfUtils.formatNumber(
                                  group.salaryTotal,
                                ),
                                style: pw.TextStyle(
                                  font: fonts.bold,
                                  fontSize: 12,
                                  color: group.salaryTotal > 0
                                      ? PdfColors.textWhite
                                      : PdfColors.textLight,
                                ),
                              ),
                              pw.SizedBox(height: 10),
                            ],
                          ),
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(6),
                          decoration: pw.BoxDecoration(
                            color: isProfit
                                ? PdfColors.success
                                : PdfColors.danger,
                            borderRadius: const pw.BorderRadius.all(
                              pw.Radius.circular(4),
                            ),
                          ),
                          child: pw.Column(
                            children: [
                              pw.Text(
                                'الصافي',
                                style: pw.TextStyle(
                                  font: fonts.regular,
                                  fontSize: 9,
                                  color: PdfColors.textWhite,
                                ),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                EnhancedPdfUtils.formatNumber(group.net),
                                style: pw.TextStyle(
                                  font: fonts.bold,
                                  fontSize: 12,
                                  color: PdfColors.textWhite,
                                ),
                              ),
                              pw.SizedBox(height: 10),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  // جداول تفصيلية مضغوطة
                  pw.SizedBox(height: 8),
                  _buildMiniTable(
                    fonts,
                    'الدخل',
                    ['التاريخ', 'الغرفة', 'الدفع', 'النوع', 'المبلغ'],
                    group.incomeEntries
                        .map(
                          (e) => [
                            DateFormat('dd/MM').format(e.date),
                            if (e.roomNumber.isNotEmpty) e.roomNumber else '-',
                            _paymentMethodName(e.paymentMethod),
                            _revenueTypeName(e.revenueType),
                            EnhancedPdfUtils.formatNumber(e.amount),
                          ],
                        )
                        .toList(),
                    PdfColors.success,
                    boldColumnIndex: 4,
                  ),
                  pw.SizedBox(height: 4),
                  _buildMiniTable(
                    fonts,
                    'المصروفات',
                    ['التاريخ', 'الوصف', 'المبلغ'],
                    group.expenseEntries
                        .map(
                          (e) => [
                            DateFormat('dd/MM').format(e.date),
                            if (e.description.isNotEmpty)
                              e.description
                            else
                              e.type,
                            EnhancedPdfUtils.formatNumber(e.amount),
                          ],
                        )
                        .toList(),
                    PdfColors.danger,
                    boldColumnIndex: 2,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

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
          final widgets = <pw.Widget>[
            // رأس التقرير
            pw.Container(
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
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.secondary,
                    ),
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
                    'عدد الفترات: ${groupedData.length}',
                    style: pw.TextStyle(
                      font: fonts.regular,
                      fontSize: 10,
                      color: PdfColors.textWhite,
                    ),
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 16),

            // 4 صناديق الملخص العام
            pw.Row(
              children: [
                pw.Expanded(
                  child: buildSummaryBox(
                    'إجمالي الدخل',
                    EnhancedPdfUtils.formatNumber(_incomeTotal),
                    PdfColors.success,
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: buildSummaryBox(
                    'إجمالي المصروفات',
                    EnhancedPdfUtils.formatNumber(_expenseTotal),
                    PdfColors.danger,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Row(
              children: [
                pw.Expanded(
                  child: buildSummaryBox(
                    'مصروفات الرواتب',
                    EnhancedPdfUtils.formatNumber(_salaryTotal),
                    PdfColors.warning,
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: buildSummaryBox(
                    'صافي الربح / الخسارة',
                    EnhancedPdfUtils.formatNumber(_net),
                    _net >= 0 ? PdfColors.success : PdfColors.danger,
                  ),
                ),
              ],
            ),

            pw.SizedBox(height: 16),

            // عنوان الأقسام
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(vertical: 8),
              decoration: const pw.BoxDecoration(
                color: PdfColors.accent,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Text(
                'التفاصيل حسب الفترة ($groupTypeLabel)',
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 14,
                  color: PdfColors.textWhite,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),

            pw.SizedBox(height: 12),
          ];

          // بطاقات الفترات
          for (final group in groupedData) {
            widgets.add(buildPeriodCard(group));
          }

          // ملخص نهائي شامل
          widgets.add(pw.SizedBox(height: 16));
          widgets.add(_buildFinalSummarySection(fonts, groupedData));

          // ═══════════════════════════════════════
          // أقسام الدورة المالية في التقرير المجمع
          // ═══════════════════════════════════════

          // مؤشرات مالية
          final profitMargin = _incomeTotal > 0
              ? (_net / _incomeTotal * 100)
              : 0.0;
          final expenseRatio = _incomeTotal > 0
              ? (_expenseTotal / _incomeTotal * 100)
              : 0.0;
          final salaryExpenseRatio = _incomeTotal > 0
              ? (_salaryTotal / _incomeTotal * 100)
              : 0.0;
          final debtCoverage = _unsettledDebtsAmount > 0 && _net > 0
              ? _net / _unsettledDebtsAmount
              : 0.0;

          // تحليل طرق الدفع
          widgets.add(
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(
                vertical: 8,
                horizontal: 12,
              ),
              margin: const pw.EdgeInsets.only(top: 16, bottom: 8),
              decoration: const pw.BoxDecoration(
                color: PdfColors.secondary,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Text(
                'تحليل طرق الدفع',
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 13,
                  color: PdfColors.textWhite,
                ),
              ),
            ),
          );
          widgets.add(_buildPaymentMethodsTable(fonts));

          // تكاليف الموارد البشرية
          widgets.add(
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(
                vertical: 8,
                horizontal: 12,
              ),
              margin: const pw.EdgeInsets.only(top: 16, bottom: 8),
              decoration: const pw.BoxDecoration(
                color: PdfColors.warning,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Text(
                'تكاليف الموارد البشرية',
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 13,
                  color: PdfColors.textWhite,
                ),
              ),
            ),
          );
          widgets.add(
            EnhancedPdfUtils.buildProfessionalTable(
              headers: ['البيان', 'القيمة'],
              fonts: fonts,
              headerColor: PdfColors.warning,
              alternateRowColor: PdfColors.backgroundLight,
              columnWidths: [200, 130],
              data: [
                ['عدد الموظفين النشطين', '$_activeEmployeesCount موظف'],
                [
                  'عدد الموظفين المنهية خدمتهم',
                  '$_terminatedEmployeesCount موظف',
                ],
                [
                  'إجمالي الالتزامات الرواتب الشهرية',
                  EnhancedPdfUtils.formatNumber(_totalSalaryObligation),
                ],
                [
                  'الرواتب المدفوعة في الفترة',
                  EnhancedPdfUtils.formatNumber(_salaryTotal),
                ],
                [
                  'نسبة الرواتب من الإيرادات',
                  '${salaryExpenseRatio.toStringAsFixed(1)}%',
                ],
                [
                  'نسبة الرواتب من المصروفات',
                  if (_expenseTotal > 0)
                    '${(_salaryTotal / _expenseTotal * 100).toStringAsFixed(1)}%'
                  else
                    '0%',
                ],
              ],
            ),
          );

          // تحليل الديون المستحقة
          widgets.add(
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(
                vertical: 8,
                horizontal: 12,
              ),
              margin: const pw.EdgeInsets.only(top: 16, bottom: 8),
              decoration: const pw.BoxDecoration(
                color: PdfColors.danger,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Text(
                'تحليل الديون المستحقة',
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 13,
                  color: PdfColors.textWhite,
                ),
              ),
            ),
          );
          widgets.add(_buildDebtAnalysisTable(fonts, debtCoverage));

          // إحصائيات الحجوزات والإشغال
          widgets.add(
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(
                vertical: 8,
                horizontal: 12,
              ),
              margin: const pw.EdgeInsets.only(top: 16, bottom: 8),
              decoration: const pw.BoxDecoration(
                color: PdfColors.info,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Text(
                'إحصائيات الحجوزات والإشغال',
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 13,
                  color: PdfColors.textWhite,
                ),
              ),
            ),
          );
          widgets.add(
            EnhancedPdfUtils.buildProfessionalTable(
              headers: ['البيان', 'القيمة'],
              fonts: fonts,
              headerColor: PdfColors.info,
              alternateRowColor: PdfColors.backgroundLight,
              columnWidths: [200, 130],
              data: [
                ['إجمالي الحجوزات في الفترة', '$_bookingsCount حجز'],
                ['حجوزات نشطة (داخلين)', '$_activeBookingsCount حجز'],
                ['حجوزات مغادرة', '$_checkoutBookingsCount حجز'],
                [
                  'متوسط الإيراد لكل حجز',
                  if (_bookingsCount > 0)
                    EnhancedPdfUtils.formatNumber(_incomeTotal / _bookingsCount)
                  else
                    '0',
                ],
              ],
            ),
          );

          // المؤشرات المالية الرئيسية
          widgets.add(
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(
                vertical: 8,
                horizontal: 12,
              ),
              margin: const pw.EdgeInsets.only(top: 16, bottom: 8),
              decoration: const pw.BoxDecoration(
                color: PdfColors.primary,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Text(
                'المؤشرات المالية الرئيسية',
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 13,
                  color: PdfColors.textWhite,
                ),
              ),
            ),
          );
          widgets.add(
            _buildFinancialIndicatorsTable(
              fonts,
              profitMargin,
              expenseRatio,
              salaryExpenseRatio,
              debtCoverage,
            ),
          );

          return widgets;
        },
      ),
    );

    return doc;
  }

  /// جدول مصغر موحد (مشترك بين جدول المصروفات وجدول الإيرادات)
  pw.Widget _buildMiniTable(
    ArabicPdfFonts fonts,
    String title,
    List<String> headers,
    List<List<String>> rows,
    PdfColor headerColor, {
    int boldColumnIndex = -1,
  }) {
    if (rows.isEmpty) {
      return pw.Container();
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            font: fonts.bold,
            fontSize: 10,
            color: headerColor,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.textLight, width: 0.3),
          ),
          child: pw.Table(
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: headerColor),
                children: headers
                    .map((h) => _miniCell(h, fonts.bold, PdfColors.textDark))
                    .toList(),
              ),
              ...rows.asMap().entries.map((entry) {
                final isEven = entry.key.isEven;
                return pw.TableRow(
                  decoration: isEven
                      ? const pw.BoxDecoration(color: PdfColors.backgroundLight)
                      : null,
                  children: entry.value.asMap().entries.map((cell) {
                    final isBold = cell.key == boldColumnIndex;
                    return _miniCell(
                      cell.value,
                      isBold ? fonts.bold : fonts.regular,
                      PdfColors.textDark,
                      align: isBold ? pw.TextAlign.left : pw.TextAlign.center,
                    );
                  }).toList(),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _miniCell(
    String text,
    pw.Font font,
    PdfColor color, {
    pw.TextAlign align = pw.TextAlign.center,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(font: font, fontSize: 8, color: color),
        textAlign: align,
      ),
    );
  }

  /// ملخص نهائي شامل في آخر التقرير
  pw.Widget _buildFinalSummarySection(
    ArabicPdfFonts fonts,
    List<_GroupedData> groups,
  ) {
    // أطول فترة ربحية وخاسرة
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

    // إجمالي المعاملات
    final totalTx = _incomeEntries.length + _expenseEntries.length;
    final avgDaily = groups.isEmpty ? 0.0 : _net / groups.length;

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.backgroundCard,
        border: pw.Border.all(color: PdfColors.primary),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 6),
            child: pw.Text(
              'الملخص النهائي الشامل',
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 14,
                color: PdfColors.primary,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.SizedBox(height: 8),

          // جدول الملخص النهائي
          EnhancedPdfUtils.buildProfessionalTable(
            headers: ['البيان', 'القيمة'],
            fonts: fonts,
            headerColor: PdfColors.primary,
            alternateRowColor: PdfColors.backgroundLight,
            columnWidths: [180, 150],
            data: [
              ['إجمالي المعاملات', '$totalTx معاملة'],
              ['عدد الفترات', '${groups.length} فترة'],
              [
                'متوسط الصافي لكل فترة',
                EnhancedPdfUtils.formatNumber(avgDaily),
              ],
              ['إجمالي الدخل', EnhancedPdfUtils.formatNumber(_incomeTotal)],
              [
                'إجمالي المصروفات',
                EnhancedPdfUtils.formatNumber(_expenseTotal),
              ],
              ['مصروفات الرواتب', EnhancedPdfUtils.formatNumber(_salaryTotal)],
              ['الصافي النهائي', EnhancedPdfUtils.formatNumber(_net)],
              if (bestPeriod != null)
                [
                  'أفضل فترة (أعلى ربح)',
                  '${bestPeriod.label} - ${EnhancedPdfUtils.formatNumber(bestPeriod.net)}',
                ],
              if (worstPeriod != null && worstPeriod.net < 0)
                [
                  'أسوأ فترة (أعلى خسارة)',
                  '${worstPeriod.label} - ${EnhancedPdfUtils.formatNumber(worstPeriod.net)}',
                ],
            ],
          ),
        ],
      ),
    );
  }

  // ===== تصدير =====
  String _getFilename({String suffix = ''}) {
    final s = suffix.isNotEmpty ? '-$suffix' : '';
    return 'تقرير-الدورة-المالية-الشامل$s-${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';
  }

  Future<void> _exportPdf() async {
    if (_incomeEntries.isEmpty && _expenseEntries.isEmpty) {
      return;
    }
    final doc = await _buildPdfDocument();
    await Printing.sharePdf(bytes: await doc.save(), filename: _getFilename());
  }

  Future<void> _exportDetailedGroupedPdf(String groupBy) async {
    if (_incomeEntries.isEmpty && _expenseEntries.isEmpty) {
      return;
    }
    final doc = await _buildDetailedGroupedPdf(groupBy);
    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: _getFilename(suffix: _getGroupTypeLabel(groupBy)),
    );
  }

  Future<void> _printPdf() async {
    if (_incomeEntries.isEmpty && _expenseEntries.isEmpty) {
      return;
    }
    final doc = await _buildPdfDocument();
    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }

  Future<void> _savePdf() async {
    if (_incomeEntries.isEmpty && _expenseEntries.isEmpty) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      final doc = await _buildPdfDocument();
      final bytes = await doc.save();
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${_getFilename()}');
      await file.writeAsBytes(bytes);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('تم حفظ الملف: ${file.path}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('خطأ في الحفظ: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _exportCsv() async {
    if (_incomeEntries.isEmpty && _expenseEntries.isEmpty) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
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
      allEntries.sort(
        (a, b) => DateTime.parse(
          a['date'] as String,
        ).compareTo(DateTime.parse(b['date'] as String)),
      );

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
        await Share.shareXFiles([
          XFile(file.path),
        ], text: 'تقرير الدخل والمصروفات');
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('خطأ في تصدير CSV: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // ===== نافذة خيارات التصدير =====
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
              // مقبض السحب
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

              // ===== قسم التقرير التفصيلي =====
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.summarize_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'تقرير تفصيلي',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'تقرير PDF مفصل مع تجميع حسب الفترة وملخص نهائي شامل',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 10),
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
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ===== قسم التصدير العام =====
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

  @override
  Widget build(BuildContext context) {
    final hasData = _incomeEntries.isNotEmpty || _expenseEntries.isNotEmpty;
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
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.date_range_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'فترة التقرير',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // فلتر التاريخ المشترك
                  ReportDateFilterWidget(
                    controller: _filterController,
                    onDateRangeChanged: (range) {
                      setState(() {
                        _fromDate = range.from;
                        _toDate = range.to;
                      });
                      _fetchReport();
                    },
                    dateButtonsFirst: true,
                    dateButtonsBuilder: (context, onPickFrom, onPickTo) => [
                      Expanded(
                        child: NeuDateButton(
                          icon: Icons.calendar_month_rounded,
                          label: 'من: ${_dateFormat.format(_fromDate!)}',
                          onTap: onPickFrom,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: NeuDateButton(
                          icon: Icons.event_rounded,
                          label: 'إلى: ${_dateFormat.format(_toDate!)}',
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
                  : (_incomeEntries.isEmpty && _expenseEntries.isEmpty)
                  ? const EmptyState(
                      title: 'لا توجد بيانات',
                      message: 'لا يوجد دخل أو مصروفات ضمن الفترة المحددة.',
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
    return RepaintBoundary(
      child: Wrap(
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
              valueColor: _net >= 0
                  ? Colors.teal.shade700
                  : Colors.red.shade700,
              emphasize: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetails() {
    if (!_detailedMode) {
      return _buildStatsList();
    }
    return _buildCombinedList();
  }

  Widget _buildCombinedList() {
    final List<_CombinedEntry> combined = [];
    for (final e in _incomeEntries) {
      combined.add(
        _CombinedEntry(
          date: e.date,
          description: e.description,
          amount: e.amount,
          isIncome: true,
          isSalary: false,
          type: '',
        ),
      );
    }
    for (final e in _expenseEntries) {
      combined.add(
        _CombinedEntry(
          date: e.date,
          description: e.description.isNotEmpty ? e.description : e.type,
          amount: e.amount,
          isIncome: false,
          isSalary: e.isSalary,
          type: e.type,
        ),
      );
    }
    combined.sort((a, b) => b.date.compareTo(a.date));

    if (combined.isEmpty) {
      return const Center(child: Text('لا توجد بيانات'));
    }

    return ListView.builder(
      // ignore: deprecated_member_use
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

        return RepaintBoundary(
          child: Card(
            elevation: 0.5,
            margin: const EdgeInsets.symmetric(vertical: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: ListTile(
              dense: true,
              leading: CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.1),
                radius: 14,
                child: Icon(icon, color: color, size: 14),
              ),
              title: Text(
                entry.description,
                style: const TextStyle(fontSize: 11),
              ),
              subtitle: Row(
                children: [
                  Text(
                    _dateFormat.format(entry.date),
                    style: const TextStyle(fontSize: 9),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
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
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatsList() {
    return RepaintBoundary(
      child: Card(
        elevation: 0.5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              dense: true,
              leading: const Icon(
                Icons.arrow_downward,
                color: Colors.green,
                size: 18,
              ),
              title: const Text(
                'عدد معاملات الدخل',
                style: TextStyle(fontSize: 11),
              ),
              trailing: Text(
                '${_incomeEntries.length}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: const Icon(
                Icons.arrow_upward,
                color: Colors.red,
                size: 18,
              ),
              title: const Text(
                'عدد معاملات المصروفات',
                style: TextStyle(fontSize: 11),
              ),
              trailing: Text(
                '${_expenseEntries.length}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: const Icon(Icons.people, color: Colors.orange, size: 18),
              title: const Text(
                'عدد معاملات الرواتب',
                style: TextStyle(fontSize: 11),
              ),
              trailing: Text(
                '${_expenseEntries.where((e) => e.isSalary).length}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== نماذج البيانات =====

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
  // ✅ إصلاح: إزالة الفلترة المزدوجة — البيانات مُفلترة مسبقاً من SQL
  // المدفوعات: مُفلترة بنطاق زمني كامل من paymentsDao.list()
  // المصروفات: مُفلترة بـ hotelDayKey من expensesDao.listFilteredByHotelDay()
  // لا حاجة لإعادة الفلترة في Dart — كان يسبب استبعاد بيانات صحيحة

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
    if (dateStr.isEmpty) {
      continue;
    }
    DateTime? dt;
    try {
      dt = DateTime.parse(
        dateStr.length > 10 ? dateStr.replaceFirst(' ', 'T') : dateStr,
      );
    } catch (_) {
      continue;
    }
    // ✅ إزالة isWithinRange — البيانات مُفلترة مسبقاً من SQL
    final room = (p['roomNumber'] ?? '').toString().trim();
    final desc = room.isNotEmpty ? 'دفعة من حجز رقم $room' : 'دفعة من حجز';
    incomeList.add(
      _IncomeEntry(
        date: dt,
        description: desc,
        amount: ((p['amount'] ?? 0) as num).toDouble(),
        roomNumber: room,
        guestName: (p['guestName'] ?? '').toString(),
        paymentMethod: (p['paymentMethod'] ?? '').toString(),
        revenueType: (p['revenueType'] ?? '').toString(),
      ),
    );
  }

  final expenseList = <_ExpenseEntry>[];
  for (final e in params.expenses) {
    final dateStr = (e['date'] ?? '').toString().trim();
    if (dateStr.isEmpty) {
      continue;
    }
    DateTime? dt;
    try {
      dt = DateTime.parse(
        dateStr.length > 10 ? dateStr.replaceFirst(' ', 'T') : dateStr,
      );
    } catch (_) {
      continue;
    }
    // ✅ إزالة isWithinRange — البيانات مُفلترة مسبقاً من SQL
    final type = (e['type'] ?? '').toString();
    expenseList.add(
      _ExpenseEntry(
        date: dt,
        type: type,
        description: (e['description'] ?? '').toString(),
        amount: ((e['amount'] ?? 0) as num).toDouble(),
        isSalary: isSalaryExpense(type),
      ),
    );
  }

  incomeList.sort((a, b) => a.date.compareTo(b.date));
  expenseList.sort((a, b) => a.date.compareTo(b.date));

  final incTotal = incomeList.fold<double>(0, (s, e) => s + e.amount);
  final expTotal = expenseList.fold<double>(0, (s, e) => s + e.amount);
  final salTotal = expenseList
      .where((e) => e.isSalary)
      .fold<double>(0, (s, e) => s + e.amount);

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
