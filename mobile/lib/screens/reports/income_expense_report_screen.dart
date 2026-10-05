import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
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
import '../../services/local_db.dart';
import '../../services/salary_expense_classifier.dart';
import '../../services/salary_mirror_matcher.dart';
import '../../utils/enhanced_pdf_utils.dart';
import '../../utils/hotel_time_engine.dart';
import '../../utils/income_expense_pdf_isolate.dart';
import '../../utils/performance_config.dart';
import '../../utils/status_utils.dart';
import '../../widgets/report_date_filter.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

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

      // ✅ إصلاح المعادلة «مصروفات الرواتب = استحقاقات الموظف»:
      // أُزيل excludeAdvance — السلفة نقد استلمه الموظف فعلاً ويجب أن تظهر
      // ضمن مصروفات الرواتب (وكانت تُستبعد هنا بينما تُخصم من الاستحقاق)
      final expenses = await expensesDao.listFilteredByHotelDay(
        fromHotelDay: fromHotelDay,
        toHotelDay: toHotelDay,
      );

      // ✅ إدخال السحوبات المباشرة (بلا مصروف مقابل) في التقرير:
      // السحب من شاشة الموظفين يُنشأ في salary_withdrawals فقط، لذلك كان
      // يظهر في تقرير المصروفات كمصروف يتيم لكنه مفقود من هذا التقرير.
      final directWithdrawalRows = await _loadDirectWithdrawalRows(
        db,
        fromHotelDay: fromHotelDay,
        toHotelDay: toHotelDay,
        linkedExpenseIds: expenses.map((e) => e.id).toSet(),
        readExpenses: expenses,
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
            dlog(
              () =>
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
            dlog(
              () =>
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
          expenses: [
            ...expenses.map(
              (e) => {
                'date': e.date,
                'type': e.expenseType,
                'description': e.description,
                'amount': e.amount,
              },
            ),
            ...directWithdrawalRows,
          ],
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

  // ===== جلب السحوبات المباشرة للتقرير =====

  /// جلب السحوبات المباشرة (بلا مصروف مقابل) ضمن النطاق الفندقي.
  ///
  /// مصدرها زر «سحب راتب» في شاشة الموظفين — سجلات salary_withdrawals فقط
  /// (expenseId = 0). تُدرَج هنا ضمن مصروفات الرواتب حتى تتطابق مصروفات
  /// التقرير مع ما يُخصم من استحقاق الموظف. dedup عبر SalaryMirrorMatcher
  /// (مصدر الحقيقة الموحّد):
  ///   1. عمود expense_id الخام — إن أشار لمصروف مقروء ضمن النطاق.
  ///   2. نمط reason القديم "exp_N" (id المحلي أو serverId جهاز المصدر).
  ///   3. مطابقة بيانات حتمية (موظف + نقدي + مبلغ + يوم) — تُغلق ثغرة العد
  ///      المزدوج عبر الأجهزة (حالة «الاورمو محمد» 2026-09-14).
  /// المرايا السالبة (خصوم) تُهمل — الخصوم ليست تدفق نقدي.
  Future<List<Map<String, dynamic>>> _loadDirectWithdrawalRows(
    AppDatabase db, {
    required String fromHotelDay,
    required String toHotelDay,
    required Set<int> linkedExpenseIds,
    List<Expense> readExpenses = const [],
  }) async {
    final rows = <Map<String, dynamic>>[];
    try {
      var q = db.select(db.salaryWithdrawals)
        ..where((tbl) => tbl.deletedAt.isNull());
      q = q
        ..where(
          (tbl) =>
              (tbl.hotelDayKey.isNotNull() &
                  tbl.hotelDayKey.isBiggerOrEqualValue(fromHotelDay)) |
              (tbl.hotelDayKey.isNull() &
                  tbl.withdrawDate.isBiggerOrEqualValue(fromHotelDay)),
        )
        ..where(
          (tbl) =>
              (tbl.hotelDayKey.isNotNull() &
                  tbl.hotelDayKey.isSmallerOrEqualValue(toHotelDay)) |
              (tbl.hotelDayKey.isNull() &
                  tbl.withdrawDate.isSmallerOrEqualValue(toHotelDay)),
        );
      final withdrawals = await q.get();
      if (withdrawals.isEmpty) return rows;

      for (final sw in withdrawals) {
        // الخصوم ليست تدفق نقدي — تُقرأ من جدول المصروفات كتسويات استحقاق
        if (sw.amount <= 0) continue;

        final isMirror = SalaryMirrorMatcher.isMirrorOfReadExpense(
          expenseId: sw.expenseId,
          expenseUuid: sw.expenseUuid,
          reason: sw.reason,
          amount: sw.amount,
          hotelDayKey: sw.hotelDayKey,
          withdrawDate: sw.withdrawDate,
          employeeId: sw.employeeId,
          expenses: readExpenses.map(
            (e) => MirrorExpenseCandidate(
              id: e.id,
              serverId: e.serverId,
              expenseType: e.expenseType,
              amount: e.amount,
              date: e.date,
              hotelDayKey: e.hotelDayKey,
              relatedId: e.relatedId,
              expenseUuid: e.localUuid,
            ),
          ),
        );
        if (isMirror) continue;

        final type = (sw.withdrawalType ?? '').trim();
        rows.add({
          'date': sw.withdrawDate,
          'type': type.contains('سلفة') ? 'سلفة' : 'سحب راتب',
          'description': sw.description ?? 'سحب مباشر من شاشة الموظفين',
          'amount': sw.amount,
        });
      }
    } catch (e) {
      dlog(() => '⚠️ تعذر جلب السحوبات المباشرة للتقرير: $e');
    }
    return rows;
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

  // ═══════════════════════════════════════════════════════════════
  // بناء PDF داخل isolate منفصل (إصلاح توقف التطبيق عند التصدير):
  // كان بناء المستند + doc.save() يُنفَّذان على الخيط الرئيسي فتتجمد
  // الواجهة ثم يظهر ANR. الآن تُبنى كل التخطيطات في الخلفية عبر compute
  // والخطوط تُمرَّر كبايتات خام قابلة للإرسال بين isolates.
  // ═══════════════════════════════════════════════════════════════

  Map<String, Object?> _incomeEntryToMap(_IncomeEntry e) => {
    'date': e.date.millisecondsSinceEpoch,
    'roomNumber': e.roomNumber,
    'guestName': e.guestName,
    'paymentMethod': e.paymentMethod,
    'revenueType': e.revenueType,
    'amount': e.amount,
  };

  Map<String, Object?> _expenseEntryToMap(_ExpenseEntry e) => {
    'date': e.date.millisecondsSinceEpoch,
    'type': e.type,
    'description': e.description,
    'amount': e.amount,
    'isSalary': e.isSalary,
  };

  Future<IncomeExpensePdfParams> _collectPdfParams({
    String groupBy = '',
  }) async {
    final regular = await EnhancedPdfUtils.regularFontBytes();
    final bold = await EnhancedPdfUtils.boldFontBytes();
    return IncomeExpensePdfParams(
      incomeRows: _incomeEntries.map(_incomeEntryToMap).toList(),
      expenseRows: _expenseEntries.map(_expenseEntryToMap).toList(),
      fromDate: _fromDate!,
      toDate: _toDate!,
      incomeTotal: _incomeTotal,
      expenseTotal: _expenseTotal,
      salaryTotal: _salaryTotal,
      net: _net,
      bookingsCount: _bookingsCount,
      activeBookingsCount: _activeBookingsCount,
      checkoutBookingsCount: _checkoutBookingsCount,
      totalDebtsCount: _totalDebtsCount,
      unsettledDebtsCount: _unsettledDebtsCount,
      unsettledDebtsAmount: _unsettledDebtsAmount,
      unsettledDebtsInPeriodCount: _unsettledDebtsInPeriodCount,
      unsettledDebtsInPeriodAmount: _unsettledDebtsInPeriodAmount,
      activeEmployeesCount: _activeEmployeesCount,
      terminatedEmployeesCount: _terminatedEmployeesCount,
      totalSalaryObligation: _totalSalaryObligation,
      groupBy: groupBy,
      fontRegularBytes: regular,
      fontBoldBytes: bold,
    );
  }

  /// بايتات تقرير الدورة المالية الشامل — تُبنى في خلفية isolate.
  Future<Uint8List> _buildMainPdfBytes() async {
    final params = await _collectPdfParams();
    return incomeExpensePdfMainJob(params);
  }

  /// بايتات التقرير التفصيلي المجمّع — تُبنى في خلفية isolate.
  Future<Uint8List> _buildGroupedPdfBytes(String groupBy) async {
    final params = await _collectPdfParams(groupBy: groupBy);
    return incomeExpensePdfGroupedJob(params);
  }

  // ===== تصدير =====
  String _getFilename({String suffix = ''}) {
    final s = suffix.isNotEmpty ? '-$suffix' : '';
    return 'تقرير-الدورة-المالية-الشامل$s-${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';
  }

  /// غلاف موحد لأعمال التصدير الطويلة: حوار انتظار غير قابل للإغلاق
  /// + معالجة أي خطأ برسالة واضحة بدل انهيار صامت للتطبيق.
  Future<void> _runLongExport(Future<void> Function() job) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Dialog(
          backgroundColor: Colors.transparent,
          child: Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('جاري تجهيز ملف PDF...'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    try {
      await job();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('تعذر إنشاء التقرير: $e'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (navigator.canPop()) {
        navigator.pop();
      }
    }
  }

  Future<void> _exportPdf() async {
    if (_incomeEntries.isEmpty && _expenseEntries.isEmpty) {
      return;
    }
    await _runLongExport(() async {
      final bytes = await _buildMainPdfBytes();
      await Printing.sharePdf(bytes: bytes, filename: _getFilename());
    });
  }

  Future<void> _exportDetailedGroupedPdf(String groupBy) async {
    if (_incomeEntries.isEmpty && _expenseEntries.isEmpty) {
      return;
    }
    await _runLongExport(() async {
      final bytes = await _buildGroupedPdfBytes(groupBy);
      await Printing.sharePdf(
        bytes: bytes,
        filename: _getFilename(suffix: _getGroupTypeLabel(groupBy)),
      );
    });
  }

  Future<void> _printPdf() async {
    if (_incomeEntries.isEmpty && _expenseEntries.isEmpty) {
      return;
    }
    await _runLongExport(() async {
      final bytes = await _buildMainPdfBytes();
      await Printing.layoutPdf(onLayout: (format) async => bytes);
    });
  }

  Future<void> _savePdf() async {
    if (_incomeEntries.isEmpty && _expenseEntries.isEmpty) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    await _runLongExport(() async {
      final bytes = await _buildMainPdfBytes();
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
    });
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
      // حد مركزي يمنع بناء بطاقات تقرير إضافية على أجهزة 1GB.
      scrollCacheExtent: optimizedScrollCacheExtent,
      addAutomaticKeepAlives: false,
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
    // ✅ توحيد التعريف مع خدمة استحقاقات الموظف (SalaryExpenseClassifier):
    // مصروفات الرواتب = النقد الخارج للموظف فعلاً (سحب + سلفة).
    return SalaryExpenseClassifier.isSalaryCashOut(type);
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

    // ✅ إصلاح المعادلة: الخصوم (خصم من الراتب / خصم راتب / خصم / غياب)
    // تسويات استحقاق بلا تدفق نقدي — لا تدخل قائمة المصروفات النقدية
    // إطلاقاً (كانت تُحسب مصروفات رواتب وتضخّم إجمالي المصروفات بلا نقد خارج).
    if (SalaryExpenseClassifier.isSalaryDeduction(type)) {
      continue;
    }

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
