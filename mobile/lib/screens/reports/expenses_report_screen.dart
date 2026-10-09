import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../components/widgets/empty_state.dart';
import '../../mixins/pdf_export_guard_mixin.dart';
import '../../providers/repository_providers.dart';
import '../../services/daos/expenses_dao.dart';
import '../../services/daos/outbox_dao.dart';
import '../../services/local_db.dart';
import '../../services/salary_mirror_matcher.dart';
import '../../src/pdf/report_templates/expenses_report_pdf.dart';
import '../../utils/debug_log.dart';
import '../../utils/hotel_time_engine.dart';
import '../../utils/sql_date_range.dart';
import '../../widgets/report_date_filter.dart';
import 'report_page_scaffold.dart';

/// أيقونات وألوان لأنواع المصروفات
const _typeConfig = <String, _ExpenseTypeConfig>{
  'رواتب': _ExpenseTypeConfig(Icons.account_balance_wallet, Colors.purple),
  'سحب راتب': _ExpenseTypeConfig(Icons.account_balance_wallet, Colors.purple),
  'سحب من الراتب': _ExpenseTypeConfig(
    Icons.account_balance_wallet,
    Colors.purple,
  ),
  'خصم راتب': _ExpenseTypeConfig(Icons.remove_circle_outline, Colors.purple),
  'خصم من الراتب': _ExpenseTypeConfig(
    Icons.remove_circle_outline,
    Colors.purple,
  ),
  'ديزل': _ExpenseTypeConfig(Icons.local_gas_station, Colors.amber),
  'صيانة': _ExpenseTypeConfig(Icons.build, Colors.orange),
  'فواتير كهرباء ومياه': _ExpenseTypeConfig(
    Icons.electrical_services,
    Colors.teal,
  ),
  'مستلزمات': _ExpenseTypeConfig(Icons.inventory_2, Colors.indigo),
  'مساعدة محتاج': _ExpenseTypeConfig(Icons.volunteer_activism, Colors.pink),
  'اخرى': _ExpenseTypeConfig(Icons.more_horiz, Colors.grey),
};

_ExpenseTypeConfig _configForType(String type) {
  for (final key in _typeConfig.keys) {
    if (type.contains(key)) {
      return _typeConfig[key]!;
    }
  }
  return const _ExpenseTypeConfig(Icons.receipt, Colors.grey);
}

/// هل النوع مرتبط بالرواتب
bool _isSalaryType(String type) {
  const salaryKeywords = [
    'رواتب',
    'سحب راتب',
    'سحب من الراتب',
    'خصم راتب',
    'خصم من الراتب',
  ];
  for (final keyword in salaryKeywords) {
    if (type.contains(keyword)) {
      return true;
    }
  }
  return false;
}

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

class _ExpensesReportScreenState extends ConsumerState<ExpensesReportScreen>
    with PdfExportGuardMixin {
  final NumberFormat _currencyFmt = NumberFormat('#,##0', 'en_US');
  final _filterController = DateFilterController();

  final DateFormat _dateLabelFormat = DateFormat('yyyy/MM/dd');
  final DateFormat _timeFormat = DateFormat('HH:mm');

  DateTime? _fromDate;
  DateTime? _toDate;
  bool _loading = false;

  final List<_ExpenseReportRow> _rows = [];
  final List<String> _availableTypes = [];

  String? _selectedType;
  double _totalAmount = 0;

  /// النتائج مجمعة حسب النوع
  Map<String, List<_ExpenseReportRow>> _grouped = {};
  Map<String, double> _typeSubtotals = {};

  /// هل توجد بيانات رواتب (لعرض عمود الموظف في PDF تلقائياً)
  bool _hasSalaryData = false;

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      unawaited(_initializeDefaults());
    }
  }

  Future<void> _initializeDefaults() async {
    final range = DateFilterController.getDefaultHotelDayRange();
    _fromDate = range.from;
    _toDate = range.to;

    if (widget.allowedTypes != null && widget.allowedTypes!.isNotEmpty) {
      setState(() {
        _availableTypes
          ..clear()
          ..addAll(widget.allowedTypes!.toList());
        _selectedType = widget.showTypeFilter
            ? (widget.initialType ?? widget.allowedTypes!.first)
            : null;
      });
    } else {
      await _loadExpenseTypes();
    }
    await _fetchReport();
  }

  Future<void> _loadExpenseTypes() async {
    final db = ref.read(databaseProvider);
    // ✅ إصلاح: فلترة المصروفات المحذوفة soft-delete
    // بدون هذا الفلتر، أنواع المصروفات المحذوفة تظهر في القائمة المنسدلة
    final query = await db
        .customSelect(
          'SELECT DISTINCT expense_type FROM expenses WHERE deleted_at IS NULL',
        )
        .get();
    // ✅ إزالة "سحب راتب" — نوع مُشتق يُحفظ تلقائياً عند "رواتب" → "سحب من الراتب"
    final types =
        query
            .map((row) => row.data['expense_type'] as String)
            .where((t) => t != 'سحب راتب')
            .toList()
          ..sort();
    setState(() {
      _availableTypes
        ..clear()
        ..addAll(types);
    });
  }

  Future<void> _fetchReport() async {
    if (_loading) {
      return;
    }
    setState(() {
      _loading = true;
    });
    try {
      final db = ref.read(databaseProvider);
      final result = await _loadExpensesReport(db);
      setState(() {
        _rows
          ..clear()
          ..addAll(result.rows);
        _totalAmount = result.totalAmount;
        _hasSalaryData = result.hasSalaryData;
        _buildGroups();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _buildGroups() {
    _grouped = {};
    _typeSubtotals = {};
    for (final row in _rows) {
      _grouped.putIfAbsent(row.type, () => []).add(row);
      _typeSubtotals[row.type] = (_typeSubtotals[row.type] ?? 0) + row.amount;
    }
    // ترتيب حسب المبلغ الأعلى
    final sortedKeys = _typeSubtotals.keys.toList()
      ..sort((a, b) => _typeSubtotals[b]!.compareTo(_typeSubtotals[a]!));
    final ordered = <String, List<_ExpenseReportRow>>{};
    for (final key in sortedKeys) {
      ordered[key] = _grouped[key]!;
    }
    _grouped = ordered;
  }

  Future<_ExpensesReportResult> _loadExpensesReport(AppDatabase db) async {
    final outboxDao = OutboxDao(db);
    final expensesDao = ExpensesDao(db, outboxDao);
    // ✅ إصلاح: تحويل نطاق التاريخ إلى مفاتيح أيام فندقية
    // نستخدم HotelTimeEngine.getHotelDayKey للتوافق مع البيانات المُخزنة
    // لأن ExpensesRepository.create() يخزن hotelDayKey باستخدام HotelTimeEngine
    //
    // ⚠️ ملاحظة حرجة: getHotelDayKey تعتبر 14:00:59 بالضبط نهاية اليوم السابق
    // (14:01:00 = بداية اليوم الجديد). بما أن _fromDate يأتي دائماً بوقت 14:01:00
    // من ReportDateFilterWidget، نحتاج إضافة ثانية واحدة لضمان
    // أن getHotelDayKey يُعيد اليوم الصحيح (وليس السابق)
    //
    // مثال: فلتر "اليوم" عند 10:00 صباح 2026-05-19:
    //   _fromDate = 18-May 14:01 → +1s → fromHotelDay = "2026-05-18" ✓
    //   _toDate  = 19-May 14:00:59 → toHotelDay   = "2026-05-18" ✓
    //   → فقط مصروفات hotelDayKey="2026-05-18" ✅
    final fromHotelDay = _fromDate != null
        ? HotelTimeEngine.getHotelDayKey(
            dateTime: _fromDate!.add(const Duration(seconds: 1)),
          )
        : null;
    final toHotelDay = _toDate != null
        ? HotelTimeEngine.getHotelDayKey(dateTime: _toDate)
        : null;
    final selectedType =
        widget.showTypeFilter &&
            _selectedType != null &&
            _selectedType!.isNotEmpty
        ? _selectedType
        : null;

    // هل نعرض الكل (بدون فلتر نوع)؟
    final showAll = selectedType == null;

    // ✅ فلترة بحقل hotelDayKey بدلاً من date التقويمي
    // ✅ (2026-09-14) العقد النقدي: السلفة نقد خرج فعلاً فتُعرض وتُحسب
    // مرة واحدة — إزالة التكرار مع السحوبات عبر UUID المستقر.
    // أدناه، وأقساط «خصم من الراتب» تظهر كسجلات معلوماتية في مجموعتها الخاصة.
    var expenses = await expensesDao.listFilteredByHotelDay(
      fromHotelDay: fromHotelDay,
      toHotelDay: toHotelDay,
      expenseType: selectedType,
    );

    if (widget.allowedTypes != null && widget.allowedTypes!.isNotEmpty) {
      expenses = expenses
          .where(
            (expense) => widget.allowedTypes!.contains(expense.expenseType),
          )
          .toList();
    }

    // ─── سحب أسماء الموظفين من جدول expenses ───
    final employeeMap = <int, Employee>{};
    final employeeMapByUuid = <String, Employee>{};
    final employeeIds = expenses
        .map((e) => e.relatedId)
        .whereType<int>()
        .toSet();
    final employeeUuids = expenses
        .map((e) => e.employeeUuid?.trim())
        .whereType<String>()
        .where((uuid) => uuid.isNotEmpty)
        .toSet();

    // ─── سحب سحوبات الرواتب من salary_withdrawals ───
    // ✅ إصلاح: جلب salary_withdrawals أيضاً عند اختيار نوع راتب
    // لعرض السحوبات اليتيمة المرتبطة بنوع الراتب المحدد
    final shouldFetchSalaryWithdrawals =
        showAll ||
        (_isSalaryType(selectedType)); // ignore: unnecessary_null_comparison
    List<SalaryWithdrawal> salaryWithdrawals = [];
    if (shouldFetchSalaryWithdrawals) {
      try {
        var swQuery = db.select(db.salaryWithdrawals)
          ..where((tbl) => tbl.deletedAt.isNull());
        // ✅ إصلاح: فلترة salary_withdrawals بـ hotelDayKey أيضاً
        if (fromHotelDay != null) {
          swQuery = swQuery
            ..where(
              (tbl) =>
                  (tbl.hotelDayKey.isNotNull() &
                      tbl.hotelDayKey.equals('').not() &
                      tbl.hotelDayKey.isBiggerOrEqualValue(fromHotelDay)) |
                  ((tbl.hotelDayKey.isNull() | tbl.hotelDayKey.equals('')) &
                      tbl.withdrawDate.isBiggerOrEqualValue(fromHotelDay)),
            );
        }
        if (toHotelDay != null) {
          final endRange = SqlDateRange.forDay(toHotelDay);
          swQuery = swQuery
            ..where(
              (tbl) =>
                  (tbl.hotelDayKey.isNotNull() &
                      tbl.hotelDayKey.equals('').not() &
                      tbl.hotelDayKey.isSmallerOrEqualValue(toHotelDay)) |
                  ((tbl.hotelDayKey.isNull() | tbl.hotelDayKey.equals('')) &
                      (endRange == null
                          ? tbl.withdrawDate.isSmallerOrEqualValue(toHotelDay)
                          : tbl.withdrawDate.isSmallerThanValue(
                              endRange.endExclusive,
                            ))),
            );
        }
        salaryWithdrawals = await swQuery.get();
        // إضافة أرقام الموظفين من salary_withdrawals
        for (final sw in salaryWithdrawals) {
          employeeIds.add(sw.employeeId);
          final uuid = sw.employeeUuid?.trim();
          if (uuid != null && uuid.isNotEmpty) employeeUuids.add(uuid);
        }
      } catch (_) {
        // في حال عدم وجود الجدول أو خطأ آخر
      }
    }

    // اقرأ الروابط العكسية الثابتة خارج نطاق التاريخ أيضاً: قد يقع المصروف
    // في يوم مختلف عن السحوبة، ويجب ألا نرجع عندها إلى مطابقة IDs رقمية.
    final reverseExpensesByWithdrawalUuid = <String, List<Expense>>{};
    var reverseExpenseLookupComplete = true;
    final withdrawalUuids = salaryWithdrawals
        .map((sw) => sw.localUuid.trim())
        .where((uuid) => uuid.isNotEmpty)
        .toSet()
        .toList();
    try {
      for (var offset = 0; offset < withdrawalUuids.length; offset += 500) {
        final end = offset + 500 < withdrawalUuids.length
            ? offset + 500
            : withdrawalUuids.length;
        final chunk = withdrawalUuids.sublist(offset, end);
        final linkedExpenses =
            await (db.select(db.expenses)..where(
                  (expense) =>
                      expense.withdrawalUuid.isIn(chunk) &
                      expense.deletedAt.isNull(),
                ))
                .get();
        for (final expense in linkedExpenses) {
          final withdrawalUuid = expense.withdrawalUuid?.trim();
          if (withdrawalUuid == null || withdrawalUuid.isEmpty) continue;
          reverseExpensesByWithdrawalUuid
              .putIfAbsent(withdrawalUuid, () => [])
              .add(expense);
        }
      }
    } catch (_) {
      // لا نستخدم أي fallback رقمي إذا تعذر التأكد من الروابط الثابتة.
      reverseExpenseLookupComplete = false;
    }

    // جلب بيانات الموظفين دفعة واحدة
    if (employeeIds.isNotEmpty || employeeUuids.isNotEmpty) {
      final employeeQuery = db.select(db.employees)
        ..where((tbl) => tbl.deletedAt.isNull());
      if (employeeIds.isNotEmpty && employeeUuids.isNotEmpty) {
        employeeQuery.where(
          (tbl) =>
              tbl.id.isIn(employeeIds.toList()) |
              tbl.localUuid.isIn(employeeUuids.toList()),
        );
      } else if (employeeIds.isNotEmpty) {
        employeeQuery.where((tbl) => tbl.id.isIn(employeeIds.toList()));
      } else {
        employeeQuery.where(
          (tbl) => tbl.localUuid.isIn(employeeUuids.toList()),
        );
      }
      final employees = await employeeQuery.get();
      for (final employee in employees) {
        employeeMap[employee.id] = employee;
        final uuid = employee.localUuid.trim();
        if (uuid.isNotEmpty) employeeMapByUuid[uuid] = employee;
      }
    }

    final rows = <_ExpenseReportRow>[];
    double totalAmount = 0;
    bool hasSalaryData = false;

    // ═══════════════════════════════════════════════════════════════════════
    // ✅ إصلاح تكرار البيانات — الطبعة الخامسة (حتمي + شبكة أمان)
    //
    // المشكلة الجذرية: تقرير المصروفات يعرض نفس المعاملة مرتين
    //   مرة من جدول expenses ومرة من جدول salary_withdrawals
    //
    // السبب: السجلات القديمة قد تفتقد روابط UUID المباشرة.
    //   لا تحتوي على رابط مباشر → تُعتبر يتيماً → تُضاف مكررة
    //
    // طرق المطابقة (مرتبة بالأولوية):
    //
    //   1) expense_uuid / withdrawal_uuid عبر local_uuid.
    //   2) expense_id وexp_XX كمسار توافق للصفوف المحلية القديمة فقط.
    //   3) مطابقة احتياطية تتطلب employee_uuid واليوم الفندقي والمبلغ.
    //
    //   السحوبات المباشرة (reason يبدأ بـ "direct_withdrawal_") لا تُطابق أبداً
    //   لأنها لا تحتوي على مصروف مقابل أصلاً.
    // ═══════════════════════════════════════════════════════════════════════

    // ─── فهارس محلية للمطابقة: local_uuid هو هوية الصف ───
    final expensesByLocalId = {for (final e in expenses) e.id: e};
    final expensesByUuid = {for (final e in expenses) e.localUuid: e};
    final addedExpenseUuids = expenses.map((e) => e.localUuid).toSet();
    final Set<String> addedWithdrawalUuids = {};

    // ─── أولاً: إضافة جميع المصروفات من جدول expenses ───
    // ✅ (2026-09-14) العقد النقدي: السلفة تُعرض وتُحسب مرة واحدة —
    // سجل السلفة المقترن بسحب يُطابق عبر UUID (أدناه) فلا يتكرر،
    // بينما أقساط «خصم من الراتب» تظهر كسجلات في مجموعتها
    // الخاصة دون دخول ملخص سحوبات الرواتب النقدي.
    for (final expense in expenses) {
      final employeeUuid = expense.employeeUuid?.trim();
      final employee = employeeUuid != null && employeeUuid.isNotEmpty
          ? employeeMapByUuid[employeeUuid]
          : expense.employeeLinkCleared == 0 && expense.relatedId != null
          ? employeeMap[expense.relatedId!]
          : null;
      // ✅ إصلاح: عرض تاريخ اليوم الفندقي بدلاً من التاريخ التقويمي
      // المصروفات القديمة قد يكون date فيها تقويمياً مختلفاً عن hotelDayKey
      final displayDateStr =
          (expense.hotelDayKey != null && expense.hotelDayKey!.isNotEmpty)
          ? expense.hotelDayKey!
          : expense.date;
      final date = _parseExpenseDate(displayDateStr);
      totalAmount += expense.amount;
      if (_isSalaryType(expense.expenseType)) {
        hasSalaryData = true;
      }
      rows.add(
        _ExpenseReportRow(
          date: date,
          amount: expense.amount,
          type: expense.expenseType,
          description: expense.description,
          employee: employee,
          relatedId: expense.relatedId,
        ),
      );
    }

    // ─── ثانياً: معالجة سحوبات الرواتب – إضافة اليتيمة فقط ───
    if (shouldFetchSalaryWithdrawals && salaryWithdrawals.isNotEmpty) {
      hasSalaryData = true;

      for (final sw in salaryWithdrawals) {
        // تجنب إضافة نفس السحب مرتين (أمان)
        if (!addedWithdrawalUuids.add(sw.localUuid)) {
          continue;
        }

        bool hasMatchingExpense = false;

        // ─── السحوبات المباشرة لا تُطابق أبداً (ليس لها مصروف مقابل) ───
        final isDirectWithdrawal =
            sw.reason != null && sw.reason!.startsWith('direct_withdrawal_');

        if (!isDirectWithdrawal) {
          final expenseUuid = sw.expenseUuid?.trim();
          final reverseLinkedExpenses =
              reverseExpensesByWithdrawalUuid[sw.localUuid.trim()] ?? const [];
          final reverseCandidates = reverseLinkedExpenses
              .where((e) => _isSalaryType(e.expenseType))
              .toList();
          final hasStableReference =
              (expenseUuid != null && expenseUuid.isNotEmpty) ||
              reverseLinkedExpenses.isNotEmpty ||
              !reverseExpenseLookupComplete;

          // العقد الأساسي: روابط UUID، لا IDs محلية.
          if (expenseUuid != null && expenseUuid.isNotEmpty) {
            final linkedExpense = expensesByUuid[expenseUuid];
            hasMatchingExpense =
                linkedExpense != null &&
                addedExpenseUuids.contains(expenseUuid) &&
                _isSalaryType(linkedExpense.expenseType) &&
                SalaryMirrorMatcher.hasStableExpenseLink(linkedExpense, sw);
          } else if (reverseCandidates.length == 1) {
            final linkedExpense =
                expensesByUuid[reverseCandidates.single.localUuid];
            hasMatchingExpense =
                linkedExpense != null &&
                SalaryMirrorMatcher.hasStableExpenseLink(linkedExpense, sw);
          }

          // توافق محدود للسجلات المحلية القديمة فقط: تُحوّل المراجع
          // الرقمية إلى local_uuid أولاً ولا تُستخدم كهوية للمزامنة.
          if (!hasMatchingExpense && !hasStableReference) {
            final legacyIds = <int>{
              if (sw.expenseId != null && sw.expenseId! > 0) sw.expenseId!,
              if (sw.reason != null)
                ...RegExp(r'exp_(\d+)')
                    .allMatches(sw.reason!)
                    .map((m) => int.tryParse(m.group(1)!))
                    .whereType<int>(),
            };
            final legacyCandidates = legacyIds
                .map((id) => expensesByLocalId[id])
                .whereType<Expense>()
                .where((e) => _isSalaryType(e.expenseType))
                .where(
                  (e) =>
                      e.withdrawalUuid == null ||
                      e.withdrawalUuid!.trim().isEmpty ||
                      e.withdrawalUuid == sw.localUuid,
                )
                .where((e) => SalaryMirrorMatcher.employeesMatch(e, sw))
                .toSet();
            hasMatchingExpense = legacyCandidates.length == 1;
          }

          // شبكة أمان للبيانات التاريخية التي لا تحمل أي مرجع ثابت.
          // لا نخمن إذا ظهر UUID صريح لكنه غير متطابق أو غير مكتمل.
          if (!hasMatchingExpense && !hasStableReference) {
            for (final expense in expenses) {
              if (_isSalaryType(expense.expenseType) &&
                  SalaryMirrorMatcher.employeesMatch(expense, sw) &&
                  _hotelDayKeysMatch(
                    expense.hotelDayKey,
                    sw.hotelDayKey,
                    expense.date,
                    sw.withdrawDate,
                  ) &&
                  expense.amount.abs() == sw.amount.abs()) {
                hasMatchingExpense = true;
                dlog(
                  () =>
                      '⚠️ تم ربط سحب راتب قديم (id=${sw.id}) بمصروف (id=${expense.id}) عبر المطابقة بالبيانات',
                );
                break;
              }
            }
          }
        }

        // إذا لم يتم العثور على مصروف مقابل، فهذا السحب يتيم – أضفه
        if (!hasMatchingExpense) {
          final employeeUuid = sw.employeeUuid?.trim();
          final employee = employeeUuid != null && employeeUuid.isNotEmpty
              ? employeeMapByUuid[employeeUuid]
              : employeeMap[sw.employeeId];
          // ✅ إصلاح: عرض تاريخ اليوم الفندقي بدلاً من التاريخ التقويمي
          final swDisplayDate =
              (sw.hotelDayKey != null && sw.hotelDayKey!.isNotEmpty)
              ? sw.hotelDayKey!
              : sw.withdrawDate;
          final date = _parseExpenseDate(swDisplayDate);
          final wType = sw.withdrawalType ?? 'سحب راتب';
          final isDeduction =
              wType.contains('خصم') || wType.contains('deduction');
          final displayType = isDeduction ? 'خصم من الراتب' : 'سحب راتب';

          final descParts = <String>[];
          if (sw.reason != null &&
              sw.reason!.isNotEmpty &&
              !sw.reason!.startsWith('exp_')) {
            descParts.add(sw.reason!);
          }
          if (sw.description != null && sw.description!.isNotEmpty) {
            descParts.add(sw.description!);
          }
          final description = descParts.join(' — ');

          totalAmount += sw.amount;
          rows.add(
            _ExpenseReportRow(
              date: date,
              amount: sw.amount,
              type: displayType,
              description: description,
              employee: employee,
              relatedId: sw.employeeId,
              isSalaryWithdrawal: true,
            ),
          );
        }
      }
    }

    // ترتيب حسب التاريخ الأحدث
    rows.sort((a, b) => b.date.compareTo(a.date));

    return _ExpensesReportResult(
      rows: rows,
      totalAmount: totalAmount,
      hasSalaryData: hasSalaryData,
    );
  }

  // ─── PDF ───
  Future<void> _exportPdf() async {
    if (_rows.isEmpty) {
      return;
    }
    await runProtectedPdfExport(_buildAndShareExpensesPdf);
  }

  Future<void> _buildAndShareExpensesPdf() async {
    // ✅ الشاشة تُمرّر بيانات فقط — التصميم بالكامل في القالب المستقل
    // lib/src/pdf/report_templates/expenses_report_pdf.dart.
    await ExpensesReportPdf.share(
      ExpensesReportData(
        rows: _rows
            .map(
              (row) => ExpensesReportRow(
                date: row.date,
                amount: row.amount,
                type: row.type,
                description: row.description,
                employeeName: row.employee?.name,
                isSalaryWithdrawal: row.isSalaryWithdrawal,
              ),
            )
            .toList(),
        totalAmount: _totalAmount,
        hasSalaryData: widget.includeEmployeeDetails || _hasSalaryData,
        labels: ExpensesReportLabels(
          title: widget.title,
          typeLabel: widget.typeLabel,
          totalSummaryLabel: widget.totalSummaryLabel,
          totalRowLabel: widget.totalRowLabel,
        ),
        fromDate: _fromDate,
        toDate: _toDate,
        selectedTypeLabel: _selectedType?.isNotEmpty ?? false
            ? _selectedType!
            : 'الكل',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ReportPageScaffold(
      title: widget.title,
      filterController: _filterController,
      onDateRangeChanged: (range) {
        setState(() {
          _fromDate = range.from;
          _toDate = range.to;
        });
        unawaited(_fetchReport());
      },
      onExportPdf: _exportPdf,
      onSearch: _fetchReport,
      isPdfEnabled: _rows.isNotEmpty && !isPdfExporting,
      isLoading: _loading,
      filterWidgets: [
        if (widget.showTypeFilter)
          SizedBox(
            width: 160,
            child: DropdownButtonFormField<String?>(
              initialValue: _selectedType,
              decoration: InputDecoration(
                labelText: widget.typeLabel,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
              ),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
              items: [
                DropdownMenuItem<String?>(
                  child: Text(
                    'الكل',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                  ),
                ),
                ..._availableTypes.map(
                  (type) => DropdownMenuItem<String?>(
                    value: type,
                    child: Text(
                      type,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                      ),
                    ),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedType = value;
                });
              },
            ),
          ),
      ],
      summaryWidget: _buildDetailedSummary(),
      contentWidget: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
          ? const EmptyState(
              title: 'لا توجد بيانات',
              message: 'لم يتم العثور على مصروفات ضمن النطاق المحدد.',
              icon: Icons.receipt_long,
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: _buildGroupedList(),
            ),
    );
  }

  /// بناء القائمة مجمعة حسب نوع المصروف
  List<Widget> _buildGroupedList() {
    final widgets = <Widget>[];
    final sortedTypes = _grouped.keys.toList();

    for (int t = 0; t < sortedTypes.length; t++) {
      final type = sortedTypes[t];
      final items = _grouped[type]!;
      final subtotal = _typeSubtotals[type] ?? 0.0;
      final cfg = _configForType(type);
      // رأس المجموعة
      widgets.add(
        _buildGroupHeader(
          type: type,
          icon: cfg.icon,
          color: cfg.color,
          count: items.length,
          subtotal: subtotal,
        ),
      );
      widgets.add(const SizedBox(height: 2));

      // بنود المجموعة
      for (int i = 0; i < items.length; i++) {
        widgets.add(_buildDetailedExpenseCard(items[i], rowIndex: i + 1));
        if (i < items.length - 1) {
          widgets.add(const SizedBox(height: 2));
        }
      }

      // فاصل بين المجموعات
      if (t < sortedTypes.length - 1) {
        widgets.add(const SizedBox(height: 8));
      }
    }

    return widgets;
  }

  /// رأس مجموعة النوع مع المبلغ الإجمالي (مصغّر)
  Widget _buildGroupHeader({
    required String type,
    required IconData icon,
    required Color color,
    required int count,
    required double subtotal,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.6),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              type,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          Text(
            _currencyFmt.format(subtotal),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// بطاقة المصروف المفصلة (مصغّرة)
  Widget _buildDetailedExpenseCard(
    _ExpenseReportRow row, {
    required int rowIndex,
  }) {
    final cfg = _configForType(row.type);
    final hasDesc = row.description.isNotEmpty;
    final hasEmployee = row.employee != null;
    final isSalary = _isSalaryType(row.type);

    return Card(
      elevation: 0.3,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSalary ? Colors.purple.shade100 : Colors.grey.shade100,
          width: isSalary ? 0.8 : 0.4,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // الصف الأول: رقم + التاريخ والوقت + المبلغ
            Row(
              children: [
                // رقم البند
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: cfg.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$rowIndex',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: cfg.color,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // التاريخ والوقت
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 11,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        _dateLabelFormat.format(row.date),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.access_time,
                        size: 11,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        _timeFormat.format(row.date),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                // المبلغ
                Text(
                  _currencyFmt.format(row.amount),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: cfg.color,
                  ),
                ),
              ],
            ),

            // الصف الثاني: الوصف
            if (hasDesc) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.notes, size: 11, color: Colors.grey.shade400),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      row.description,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                        height: 1.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            // الصف الثالث: الموظف — يظهر دائماً لمصروفات الرواتب
            if (hasEmployee || isSalary) ...[
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: isSalary ? Colors.purple.shade50 : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isSalary
                        ? Colors.purple.shade200
                        : Colors.blue.shade100,
                    width: 0.4,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 11,
                      color: isSalary
                          ? Colors.purple.shade400
                          : Colors.blue.shade400,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      hasEmployee
                          ? row.employee!.name
                          : (row.relatedId != null
                                ? 'موظف #${row.relatedId}'
                                : 'موظف غير محدد'),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isSalary
                            ? Colors.purple.shade700
                            : Colors.blue.shade600,
                      ),
                    ),
                    if (hasEmployee && row.employee!.phone.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.phone, size: 10, color: Colors.grey.shade400),
                      const SizedBox(width: 2),
                      Text(
                        row.employee!.phone,
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                    if (hasEmployee && row.employee!.position.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          row.employee!.position,
                          style: TextStyle(
                            fontSize: 8,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            // شارة سحب راتب
            if (row.isSalaryWithdrawal) ...[
              const SizedBox(height: 3),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: Colors.purple.shade200,
                        width: 0.4,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 9,
                          color: Colors.purple.shade400,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          'سحب راتب',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                            color: Colors.purple.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// ملخص تفصيلي (مصغّر - بدون توزيع الأنواع)
  Widget _buildDetailedSummary() {
    if (_rows.isEmpty) {
      return const SizedBox.shrink();
    }

    // حساب إجمالي الرواتب والمصروفات التشغيلية
    final salaryTotal = _rows
        .where((r) => _isSalaryType(r.type))
        .fold<double>(0, (sum, r) => sum + r.amount);
    final nonSalaryTotal = _totalAmount - salaryTotal;
    final salaryCount = _rows.where((r) => _isSalaryType(r.type)).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // الإجمالي الرئيسي - سطر واحد مصغّر
          Row(
            children: [
              const Icon(Icons.payments, color: Colors.orange, size: 14),
              const SizedBox(width: 5),
              Text(
                widget.totalSummaryLabel,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              ),
              const Spacer(),
              Text(
                _currencyFmt.format(_totalAmount),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '${_rows.length} عملية',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ),
            ],
          ),

          // سحوبات الرواتب ومصروفات التشغيلية - بجانب بعض مصغّرة
          if (_hasSalaryData) ...[
            const SizedBox(height: 4),
            const Divider(height: 1, thickness: 0.5),
            const SizedBox(height: 4),
            Row(
              children: [
                // سحوبات الرواتب
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.purple.shade200,
                        width: 0.3,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.account_balance_wallet,
                          size: 11,
                          color: Colors.purple.shade600,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'سحوبات الرواتب',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purple.shade700,
                                ),
                              ),
                              Text(
                                _currencyFmt.format(salaryTotal),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purple.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '$salaryCount',
                          style: TextStyle(
                            fontSize: 8,
                            color: Colors.purple.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // مصروفات تشغيلية
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.teal.shade200,
                        width: 0.3,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.build_circle,
                          size: 11,
                          color: Colors.teal.shade600,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'مصروفات تشغيلية',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal.shade700,
                                ),
                              ),
                              Text(
                                _currencyFmt.format(nonSalaryTotal),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${_rows.length - salaryCount}',
                          style: TextStyle(
                            fontSize: 8,
                            color: Colors.teal.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// مطابقة مفتاحي اليوم الفندقي بين مصروف وسحب راتب
  /// تأخذ بعين الاعتبار أن البيانات القديمة قد لا تحتوي على hotelDayKey
  /// في هذه الحالة نلجأ لمقارنة جزء التاريخ فقط (yyyy-MM-dd)
  static bool _hotelDayKeysMatch(
    String? expenseHotelDayKey,
    String? swHotelDayKey,
    String expenseDate,
    String swDate,
  ) {
    // أفضل حالة: كلاهما يحتوي على hotelDayKey
    if (expenseHotelDayKey != null &&
        expenseHotelDayKey.isNotEmpty &&
        swHotelDayKey != null &&
        swHotelDayKey.isNotEmpty) {
      return expenseHotelDayKey == swHotelDayKey;
    }
    // حالة احتياطية: مقارنة جزء التاريخ فقط (للسجلات القديمة بدون hotelDayKey)
    return _extractDatePart(expenseDate) == _extractDatePart(swDate);
  }

  DateTime _parseExpenseDate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    final hasTime = trimmed.length > 10;
    final normalized = hasTime
        ? trimmed.replaceFirst(' ', 'T')
        : '${trimmed}T00:00:00';
    try {
      return DateTime.parse(normalized);
    } catch (e) {
      dlog(() => '⚠️ تعذر تحليل تاريخ المصروف "$value": $e');
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  /// استخراج جزء التاريخ فقط (yyyy-MM-dd) من سلسلة نصية
  /// قد تحتوي على وقت مثل "2025-06-03 14:30" → "2025-06-03"
  /// يُستخدم لمقارنة الأيام بدلاً من مقارنة نص التاريخ الكامل
  static String _extractDatePart(String dateStr) {
    final trimmed = dateStr.trim();
    if (trimmed.length >= 10) {
      return trimmed.substring(0, 10);
    }
    return trimmed;
  }
}

class _ExpenseReportRow {
  _ExpenseReportRow({
    required this.date,
    required this.amount,
    required this.type,
    required this.description,
    required this.employee,
    this.relatedId,
    this.isSalaryWithdrawal = false,
  });

  final DateTime date;
  final double amount;
  final String type;
  final String description;
  final Employee? employee;
  final int? relatedId;
  final bool isSalaryWithdrawal;
}

class _ExpensesReportResult {
  _ExpensesReportResult({
    required this.rows,
    required this.totalAmount,
    required this.hasSalaryData,
  });

  final List<_ExpenseReportRow> rows;
  final double totalAmount;
  final bool hasSalaryData;
}

class _ExpenseTypeConfig {
  const _ExpenseTypeConfig(this.icon, this.color);
  final IconData icon;
  final Color color;
}
