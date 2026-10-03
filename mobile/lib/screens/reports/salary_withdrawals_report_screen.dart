import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../components/app_scaffold.dart';
import '../../components/widgets/empty_state.dart';
import '../../providers/repository_providers.dart';
import '../../services/daos/expenses_dao.dart';
import '../../services/daos/outbox_dao.dart';
import '../../services/local_db.dart';
import '../../services/salary_mirror_matcher.dart';
import '../../utils/device_attribution.dart';
import '../../utils/enhanced_pdf_utils.dart';
import '../../utils/hotel_time_engine.dart';
import '../../utils/report_pdf_builder.dart';
import '../../widgets/report_date_filter.dart';

import 'package:marina_hotel_mobile/utils/debug_log.dart';

/// بيانات معاملة واحدة من جدول salary_withdrawals
class _SalaryTxRow {
  _SalaryTxRow({
    required this.id,
    required this.date,
    required this.amount,
    required this.withdrawalType,
    required this.reason,
    required this.description,
    required this.employee,
    this.createdAt,
    this.recorderName,
    this.deviceId,
    this.deviceHint,
  });

  final int id;
  final DateTime date;
  final double amount;
  final String withdrawalType;
  final String reason;
  final String description;
  final Employee? employee;

  /// ✅ وقت الإنشاء الفعلي (epoch) — سابقاً كان التقرير يعرض 00:00 وهمية
  /// لأنه يحلل withdrawDate (نص تاريخ بلا وقت) كمنتصف الليل.
  final DateTime? createdAt;

  /// ✅ اسم المستخدم الذي سجّل السحبة (migration 66) — فارغ للسجلات القديمة
  final String? recorderName;

  /// هوية الجهاز المسجّل (عمود SyncFields الموجود أصلاً)
  final String? deviceId;

  /// تلميح الجهاز من الساعة الاتجاهية — يكشف جهاز التسجيل للسجلات القديمة
  /// التي رُفعت قبل وسم deviceId (مثل: "marina_HNBRC-M1_be06acca" →
  /// "HNBRC-M1 (be06acca)").
  final String? deviceHint;
}

/// بيانات مجمعة لموظف واحد
class _EmployeeSalaryGroup {
  _EmployeeSalaryGroup({required this.employee});

  final Employee? employee;
  final List<_SalaryTxRow> transactions = [];
  double totalAmount = 0;
  int txCount = 0;
}

/// ✅ (2026-09-21) اسم الموظف للعرض في التقارير — المحذوف ناعماً يظهر
/// باسمه الحقيقي مع وسم "(محذوف)" بدل "غير محدد":
/// السحوبات التاريخية المرتبطة به يجب أن تظل قابلة للقراءة في التقارير
/// و PDF، مع تمييز واضح أنه غير نشط (حتى لا يبدو خطأً في البيانات).
/// [fallback] نص بديل عندما لا يمكن حل الموظف إطلاقاً (صف مفقود محلياً).
String _employeeDisplayName(Employee? e, {String fallback = 'غير محدد'}) {
  if (e == null) return fallback;
  return e.deletedAt == null ? e.name : '${e.name} (محذوف)';
}

/// يدمج سحوبات المرآة المكرّرة لنفس مصروف راتب واحد في سحبة تمثيلية
/// واحدة (الأحدث تحديثاً) — انظر التعليق عند نقطة الاستدعاء في
/// [_SalaryWithdrawalsReportScreenState._loadSalaryData] لتفصيل العيب.
///
/// القاعدة:
/// - سحبة تُحلّ (Level 1/2 عبر [SalaryMirrorMatcher.resolveLinkedExpenseId])
///   لمصروف محلي حقيقي واحد → "مُرسّاة" على ذلك المصروف. إن ترسّت أكثر
///   من سحبة على نفس المصروف (لا يجب أن يحدث عادة) تُبقى الأحدث فقط.
/// - سحبة تحمل علامة مرآة (expense_id/exp_N) لكن رابطها لا يُحلّ محلياً
///   (مرآة يتيمة من جهاز آخر) → تُجمَّع بمفتاح احتياطي (موظف+يوم+عائلة
///   نقدية). إن وُجدت لنفس المفتاح سحبة "مُرسّاة" واحدة بالضبط فهذه
///   اليتيمة مكرّرة لها أكيداً وتُحذف. إن كان هناك أكثر من مُرسّاة
///   لنفس المفتاح (موظف لديه أكثر من مصروف راتب في نفس اليوم) فالحالة
///   غامضة ولا نحذف — نُبقي اليتيمة احتياطاً حتى لا نُخفي سحبة حقيقية.
/// - سحبة بلا أي علامة مرآة إطلاقاً (سحوبات مباشرة، أو سجلات قديمة
///   يدوية) → تبقى كما هي دائماً، لا علاقة لها بهذا العيب.
@visibleForTesting
List<SalaryWithdrawal> dedupeMirrorDuplicates(
  List<SalaryWithdrawal> withdrawals,
  List<MirrorExpenseCandidate> expenses,
) {
  bool isNewer(SalaryWithdrawal a, SalaryWithdrawal b) {
    if (a.updatedAt != b.updatedAt) return a.updatedAt > b.updatedAt;
    return a.id > b.id;
  }

  String groupKey(SalaryWithdrawal sw) {
    final day = (sw.hotelDayKey ?? '').trim().isNotEmpty
        ? sw.hotelDayKey!.trim()
        : sw.withdrawDate.trim();
    final family = sw.amount >= 0 ? 'cash' : 'deduction';
    return '${sw.employeeId}|$day|$family';
  }

  final kept = <SalaryWithdrawal>[];
  final anchored = <int, SalaryWithdrawal>{}; // expenseId → أحدث سحبة
  final orphansByGroup = <String, List<SalaryWithdrawal>>{};

  for (final sw in withdrawals) {
    final resolvedId = SalaryMirrorMatcher.resolveLinkedExpenseId(
      expenseId: sw.expenseId,
      reason: sw.reason,
      expenses: expenses,
    );
    if (resolvedId != null) {
      final current = anchored[resolvedId];
      if (current == null || isNewer(sw, current)) {
        anchored[resolvedId] = sw;
      }
      continue;
    }

    final hasMarker = SalaryMirrorMatcher.hasMirrorMarker(
      expenseId: sw.expenseId,
      reason: sw.reason,
    );
    if (!hasMarker) {
      kept.add(sw); // لا علاقة لها بهذا العيب — تبقى كما هي
      continue;
    }

    orphansByGroup.putIfAbsent(groupKey(sw), () => []).add(sw);
  }

  kept.addAll(anchored.values);

  // مجموعات المُرسّاة (موظف+يوم+عائلة) — لتقرير غموض التبنّي.
  final anchoredGroupCounts = <String, int>{};
  for (final sw in anchored.values) {
    final key = groupKey(sw);
    anchoredGroupCounts[key] = (anchoredGroupCounts[key] ?? 0) + 1;
  }

  for (final entry in orphansByGroup.entries) {
    final anchoredCount = anchoredGroupCounts[entry.key] ?? 0;
    if (anchoredCount == 1) {
      // مصروف واحد بالضبط مُرسّى لنفس المفتاح — كل اليتامى هنا مكرّرون له.
      continue;
    }
    if (anchoredCount == 0 && entry.value.length > 1) {
      // لا مُرسّاة إطلاقاً، لكن أكثر من يتيمة لنفس المفتاح — على الأرجح
      // نفس مصروف الراتب عُدّل أكثر من مرة قبل أي مزامنة ناجحة؛ نُبقي
      // الأحدث فقط بدل عرضهم جميعاً.
      final newest = entry.value.reduce((a, b) => isNewer(b, a) ? b : a);
      kept.add(newest);
      continue;
    }
    // أُخرى: لا مُرسّاة (يتيمة وحيدة) أو حالة غامضة (أكثر من مُرسّاة
    // لنفس المفتاح) — نُبقي الكل احتياطاً لتفادي إخفاء سحبة حقيقية.
    kept.addAll(entry.value);
  }

  return kept;
}

class SalaryWithdrawalsReportScreen extends ConsumerStatefulWidget {
  const SalaryWithdrawalsReportScreen({super.key});

  @override
  ConsumerState<SalaryWithdrawalsReportScreen> createState() =>
      _SalaryWithdrawalsReportScreenState();
}

class _SalaryWithdrawalsReportScreenState
    extends ConsumerState<SalaryWithdrawalsReportScreen> {
  final NumberFormat _currencyFmt = NumberFormat('#,##0', 'en_US');
  final _filterController = DateFilterController();
  final DateFormat _dateLabelFormat = DateFormat('yyyy/MM/dd');
  final DateFormat _timeFormat = DateFormat('HH:mm');
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _loading = false;
  bool _initialized = false;

  final List<_SalaryTxRow> _allRows = [];
  final Map<int, _EmployeeSalaryGroup> _employeeGroups = {};
  final List<Employee> _allEmployees = [];

  final String _sortBy = 'date';
  int? _selectedEmployeeId; // null = الكل

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _initializeDefaults();
    }
  }

  Future<void> _initializeDefaults() async {
    // ✅ افتراضي: اليوم الفندقي الحالي (14:00 → 13:59)
    final range = DateFilterController.getDefaultHotelDayRange();
    _fromDate = range.from;
    _toDate = range.to;
    await _fetchReport();
  }

  Future<void> _fetchReport() async {
    if (_loading) {
      return;
    }
    setState(() => _loading = true);
    try {
      final db = ref.read(databaseProvider);
      final result = await _loadSalaryData(db);
      if (mounted) {
        setState(() {
          _allEmployees
            ..clear()
            ..addAll(result.allEmployees);
          _allRows
            ..clear()
            ..addAll(result.rows);
          _employeeGroups
            ..clear()
            ..addAll(result.groups);
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<_SalaryReportData> _loadSalaryData(AppDatabase db) async {
    // ✅ (2026-09-21) إصلاح الموظفين المحذوفين في التقارير: كان هذا
    // الاستعلام يستبعد الموظفين المحذوفين ناعماً (deletedAt IS NULL)، فتُبنى
    // خريطة الأسماء من النشطين فقط → سحوبات موظف محذوف تظهر باسم
    // "غير محدد" وتُجمّع تحت مجموعة مجهولة (id=0) رغم أن صف الموظف
    // موجود محلياً (tombstone يُسحب عبر entityNeedsTombstoneParents) —
    // السجلات المالية التاريخية يجب أن تحلّ أسماء أصحابها دائماً.
    // المحذوف يُوسَم في العرض بـ "(محذوف)" — انظر _employeeDisplayName.
    final allEmployees = await (db.select(db.employees)).get();
    allEmployees.sort((a, b) => a.name.compareTo(b.name));

    // جلب سجلات salary_withdrawals مع فلترة التاريخ
    var query = db.select(db.salaryWithdrawals)
      ..where((tbl) => tbl.deletedAt.isNull());

    // ✅ إصلاح: فلترة بـ hotelDayKey بدلاً من withdrawDate التقويمي
    // لمنع إدراج سحوبات الصباح من اليوم السابق خطأً
    //
    // ⚠️ ملاحظة حرجة: getHotelDayKey تعتبر 14:00:59 نهاية اليوم السابق
    // (14:01:00 = بداية اليوم الجديد). بما أن _fromDate يأتي دائماً بوقت 14:01:00
    // من ReportDateFilterWidget، نحتاج إضافة ثانية واحدة لضمان
    // أن getHotelDayKey يُعيد اليوم الصحيح (وليس السابق)
    //
    // مثال: فلتر "اليوم" عند 10:00 صباح 2026-05-19:
    //   _fromDate = 18-May 14:00 → +1s → fromHotelDay = "2026-05-18" ✓
    //   _toDate  = 19-May 13:59 → toHotelDay   = "2026-05-18" ✓
    //   → فقط سحبيات hotelDayKey="2026-05-18" ✅
    final fromHotelDay = _fromDate != null
        ? HotelTimeEngine.getHotelDayKey(
            dateTime: _fromDate!.add(const Duration(seconds: 1)),
          )
        : null;
    final toHotelDay = _toDate != null
        ? HotelTimeEngine.getHotelDayKey(dateTime: _toDate)
        : null;

    if (fromHotelDay != null) {
      query = query
        ..where(
          (tbl) =>
              (tbl.hotelDayKey.isNotNull() &
                  tbl.hotelDayKey.isBiggerOrEqualValue(fromHotelDay)) |
              (tbl.hotelDayKey.isNull() &
                  tbl.withdrawDate.isBiggerOrEqualValue(fromHotelDay)),
        );
    }
    if (toHotelDay != null) {
      query = query
        ..where(
          (tbl) =>
              (tbl.hotelDayKey.isNotNull() &
                  tbl.hotelDayKey.isSmallerOrEqualValue(toHotelDay)) |
              (tbl.hotelDayKey.isNull() &
                  tbl.withdrawDate.isSmallerOrEqualValue(toHotelDay)),
        );
    }

    // فلترة حسب الموظف المحدد
    if (_selectedEmployeeId != null) {
      query = query
        ..where((tbl) => tbl.employeeId.equals(_selectedEmployeeId!));
    }

    final rawWithdrawals = await query.get();

    // ═══════════════════════════════════════════════════════════════
    // ✅ إصلاح تكرار «تقرير سحبيات الرواتب» عند تعديل مبلغ مصروف راتب
    // من شاشة المصروفات (2026-09-24):
    //
    // مصدر هذا التقرير الوحيد جدول salary_withdrawals. عند تعديل مبلغ
    // مصروف راتب وصل عبر المزامنة من جهاز آخر، تحاول شاشة التعديل
    // "تبنّي" مرآته اليتيمة القديمة بدل إنشاء واحدة جديدة — لكن هذا
    // التبنّي يفشل في حالات (أكثر من سحبة/مصروف لنفس الموظف في نفس
    // اليوم، أو مرآة يتيمة موجودة أصلاً من قبل هذا الإصلاح)، فيبقى
    // صفّان في salary_withdrawals يمثّلان نفس مصروف الراتب الواحد.
    //
    // خلافاً لتقرير المصروفات وتقرير الإيرادات/المصروفات — اللذين
    // "يُخفيان" سحبة المرآة كلياً لأن قيمتها تُعرض من جدول expenses
    // مباشرة — هذا التقرير ليس لديه صف آخر يعوّض الإخفاء، فبدل
    // الإخفاء **ندمج**: كل السحوبات التي تُحلّ لنفس مصروف واحد (أو
    // يُرجَّح جداً أنها نفس المصروف: مرآة يتيمة وحيدة لنفس الموظف
    // واليوم والعائلة النقدية لمصروف مُحلّ بالفعل) تصبح سحبة واحدة
    // تمثيلية (الأحدث تحديثاً)، فيُحسب كل مصروف راتب مرة واحدة بالضبط.
    // ═══════════════════════════════════════════════════════════════
    final expensesDao = ExpensesDao(db, OutboxDao(db));
    List<Expense> rangeExpenses = [];
    try {
      rangeExpenses = await expensesDao.listFilteredByHotelDay(
        fromHotelDay: fromHotelDay,
        toHotelDay: toHotelDay,
      );
    } catch (_) {
      // فشل جلب المصروفات لا يجب أن يمنع عرض التقرير — يبقى الدمج
      // معطّلاً لهذه الدورة فقط (سلوك ما قبل هذا الإصلاح).
    }
    final expenseCandidates = rangeExpenses
        .map(
          (e) => MirrorExpenseCandidate(
            id: e.id,
            serverId: e.serverId,
            expenseType: e.expenseType,
            amount: e.amount,
            date: e.date,
            hotelDayKey: e.hotelDayKey,
            relatedId: e.relatedId,
          ),
        )
        .toList(growable: false);

    final withdrawals = dedupeMirrorDuplicates(
      rawWithdrawals,
      expenseCandidates,
    );

    // بناء خريطة الموظفين — من **كل** الموظفين (نشطين ومحذوفين ناعماً):
    // سحوبات الموظف المحذوف يجب أن تحلّ اسمه في التقارير (fix أعلاه).
    final employeeMap = <int, Employee>{};
    for (final emp in allEmployees) {
      employeeMap[emp.id] = emp;
    }

    // بناء الصفوف
    final rows = <_SalaryTxRow>[];
    for (final sw in withdrawals) {
      final employee = employeeMap[sw.employeeId];
      final date = _parseDate(sw.withdrawDate);
      // ✅ وقت الإنشاء الفعلي من عمود createdAt (epoch) — إن وُجد
      final createdAt = sw.createdAt > 0
          ? DateTime.fromMillisecondsSinceEpoch(sw.createdAt * 1000)
          : null;
      rows.add(
        _SalaryTxRow(
          id: sw.id,
          date: date,
          amount: sw.amount,
          withdrawalType: sw.withdrawalType ?? '',
          reason: sw.reason ?? '',
          description: sw.description ?? '',
          employee: employee,
          createdAt: createdAt,
          recorderName: (sw.recorderName ?? '').trim().isEmpty
              ? null
              : sw.recorderName,
          deviceId: sw.deviceId.trim().isEmpty ? null : sw.deviceId,
          deviceHint: deviceHintFromVectorClock(sw.vectorClock),
        ),
      );
    }

    // ترتيب حسب التاريخ الأحدث، ثم وقت الإنشاء الفعلي الأحدث داخل اليوم
    rows.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      if (byDate != 0) return byDate;
      final aCreated = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bCreated = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return bCreated.compareTo(aCreated);
    });

    // تجميع حسب الموظف
    final groups = <int, _EmployeeSalaryGroup>{};
    for (final row in rows) {
      final empId = row.employee?.id ?? 0;
      groups.putIfAbsent(
        empId,
        () => _EmployeeSalaryGroup(employee: row.employee),
      );
      final group = groups[empId]!;
      group.transactions.add(row);
      group.totalAmount += row.amount;
      group.txCount++;
    }

    return _SalaryReportData(
      rows: rows,
      groups: groups,
      allEmployees: allEmployees,
    );
  }

  // ─── PDF ───
  Future<void> _exportPdf() async {
    // استخدام البيانات المفلترة (حسب الموظف المحدد أو الكل)
    final rows = _filteredRows;
    if (rows.isEmpty) {
      return;
    }

    final selectedEmpName = _selectedEmployeeId != null
        ? _employeeDisplayName(
            _allEmployees.where((e) => e.id == _selectedEmployeeId).firstOrNull,
          )
        : null;

    final headers = _selectedEmployeeId != null
        ? <String>['التاريخ', 'المبلغ', 'النوع', 'السبب', 'الملاحظات']
        : <String>[
            'التاريخ',
            'المبلغ',
            'النوع',
            'السبب',
            'الملاحظات',
            'الموظف',
          ];

    final dataRows = <List<String>>[];
    for (final row in rows) {
      // تنظيف حقل السبب: إذا كان يبدأ بـ "exp_" يُعتبر ربط داخلي، لا يُعرض
      String displayReason = '-';
      if (row.reason.isNotEmpty && !row.reason.startsWith('exp_')) {
        displayReason = row.reason;
      }

      final cells = <String>[
        _dateLabelFormat.format(row.date),
        EnhancedPdfUtils.formatNumber(row.amount),
        if (row.withdrawalType.isNotEmpty) row.withdrawalType else 'سحب',
        displayReason,
        if (row.description.isNotEmpty) row.description else '-',
      ];
      if (_selectedEmployeeId == null) {
        cells.add(_employeeDisplayName(row.employee));
      }
      dataRows.add(cells);
    }

    final totalAmount = rows.fold<double>(0, (sum, r) => sum + r.amount);
    final emptyCells = List.filled(headers.length, '');
    dataRows.add([
      'الإجمالي',
      EnhancedPdfUtils.formatNumber(totalAmount),
      ...emptyCells.sublist(2),
    ]);

    await ReportPdfBuilder.buildAndShare(
      ReportPdfConfig(
        title: 'تقرير سحبيات الرواتب',
        fromDate: _fromDate,
        toDate: _toDate,
        buildContent: (fonts) {
          final fromLabel = _fromDate != null
              ? DateFormat('yyyy-MM-dd').format(_fromDate!)
              : 'غير محدد';
          final toLabel = _toDate != null
              ? DateFormat('yyyy-MM-dd').format(_toDate!)
              : 'غير محدد';

          return [
            pw.SizedBox(height: 16),
            EnhancedPdfUtils.buildInfoCard(
              title: 'تقرير سحبيات الرواتب',
              fonts: fonts,
              content: [
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 6),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'الفترة',
                        style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                      ),
                      pw.Text(
                        'من $fromLabel إلى $toLabel',
                        style: pw.TextStyle(font: fonts.regular, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 6),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'الموظف',
                        style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                      ),
                      pw.Text(
                        selectedEmpName ?? 'الكل',
                        style: pw.TextStyle(font: fonts.regular, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 6),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'عدد السجلات',
                        style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                      ),
                      pw.Text(
                        '${rows.length}',
                        style: pw.TextStyle(font: fonts.regular, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            EnhancedPdfUtils.buildProfessionalTable(
              headers: headers,
              data: dataRows,
              fonts: fonts,
              headerColor: PdfColors.primary,
              alternateRowColor: PdfColors.backgroundLight,
            ),
          ];
        },
        fileName: ReportPdfBuilder.generateFileName(
          selectedEmpName != null
              ? 'سحبيات راتب $selectedEmpName'
              : 'تقرير سحبيات الرواتب',
        ),
      ),
    );
  }

  List<_SalaryTxRow> get _filteredRows {
    if (_selectedEmployeeId == null) {
      return _allRows;
    }
    return _allRows
        .where((r) => r.employee?.id == _selectedEmployeeId)
        .toList();
  }

  Map<int, _EmployeeSalaryGroup> get _filteredGroups {
    if (_selectedEmployeeId == null) {
      return _employeeGroups;
    }
    final filtered = <int, _EmployeeSalaryGroup>{};
    final g = _employeeGroups[_selectedEmployeeId];
    if (g != null) {
      filtered[_selectedEmployeeId!] = g;
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final filteredRows = _filteredRows;
    final filteredGroups = _filteredGroups;
    final totalFiltered = filteredRows.fold<double>(
      0,
      (sum, r) => sum + r.amount,
    );

    return AppScaffold(
      title: 'تقرير سحبيات الرواتب',
      actions: [
        IconButton(
          icon: const Icon(Icons.picture_as_pdf),
          tooltip: 'تصدير PDF',
          onPressed: filteredRows.isEmpty ? null : _exportPdf,
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // فلتر التاريخ
            ReportDateFilterWidget(
              controller: _filterController,
              onDateRangeChanged: (range) {
                setState(() {
                  _fromDate = range.from;
                  _toDate = range.to;
                });
                _fetchReport();
              },
            ),
            const SizedBox(height: 8),

            // القائمة المنسدلة للموظف + زر البحث
            Row(
              children: [
                // القائمة المنسدلة
                Expanded(
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                        value: _selectedEmployeeId,
                        isExpanded: true,
                        hint: const Text(
                          'عرض بحسب الموظف',
                          style: TextStyle(fontSize: 13),
                        ),
                        icon: const Icon(Icons.arrow_drop_down, size: 20),
                        items: [
                          const DropdownMenuItem<int?>(
                            child: Row(
                              children: [
                                Icon(
                                  Icons.people,
                                  size: 18,
                                  color: Colors.blue,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'الكل',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          ..._allEmployees.map((emp) {
                            return DropdownMenuItem<int?>(
                              value: emp.id,
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.person,
                                    size: 18,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _employeeDisplayName(emp),
                                      style: const TextStyle(fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                        onChanged: (value) {
                          setState(() => _selectedEmployeeId = value);
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // زر البحث
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  onPressed: _loading ? null : _fetchReport,
                  icon: const Icon(Icons.search, size: 16),
                  label: Text(_loading ? 'جارٍ...' : 'بحث'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // شريط إجمالي مبسط
            if (filteredRows.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.receipt_long,
                      size: 18,
                      color: Colors.blue.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedEmployeeId != null
                            ? 'سحبيات: ${_employeeDisplayName(_allEmployees.where((e) => e.id == _selectedEmployeeId).firstOrNull, fallback: "")} — ${filteredRows.length} عملية'
                            : 'جميع الموظفين — ${filteredRows.length} عملية',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ),
                    Text(
                      '${_currencyFmt.format(totalFiltered)} ريال',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 8),

            // قائمة المعاملات
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filteredRows.isEmpty
                  ? const EmptyState(
                      title: 'لا توجد بيانات',
                      message:
                          'لم يتم العثور على سحبيات رواتب ضمن النطاق المحدد.',
                      icon: Icons.account_balance_wallet,
                    )
                  : _selectedEmployeeId == null
                  ? ListView(
                      padding: const EdgeInsets.only(bottom: 8),
                      children: _buildGroupedList(filteredGroups),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: filteredRows.length,
                      itemBuilder: (context, index) => RepaintBoundary(
                        child: _buildTransactionRow(filteredRows[index]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// بناء القائمة مجمععة حسب الموظف (عند اختيار "الكل")
  List<Widget> _buildGroupedList(Map<int, _EmployeeSalaryGroup> groups) {
    final widgets = <Widget>[];
    final entries = groups.entries.toList();

    // ترتيب
    switch (_sortBy) {
      case 'amount':
        entries.sort(
          (a, b) => b.value.totalAmount.compareTo(a.value.totalAmount),
        );
      case 'employee':
        entries.sort((a, b) {
          final aName = a.value.employee?.name ?? '';
          final bName = b.value.employee?.name ?? '';
          return aName.compareTo(bName);
        });
      case 'date':
      default:
        // ترتيب حسب أحدث معاملة
        entries.sort((a, b) {
          final aDate = a.value.transactions.isNotEmpty
              ? a.value.transactions.first.date
              : DateTime(2000);
          final bDate = b.value.transactions.isNotEmpty
              ? b.value.transactions.first.date
              : DateTime(2000);
          return bDate.compareTo(aDate);
        });
    }

    for (int i = 0; i < entries.length; i++) {
      final group = entries[i].value;
      widgets.add(_buildEmployeeCard(group, rank: i + 1));
      if (i < entries.length - 1) {
        const SizedBox(height: 8);
      }
    }

    return widgets;
  }

  /// بطاقة الموظف مع التفاصيل القابلة للتوسيع
  Widget _buildEmployeeCard(_EmployeeSalaryGroup group, {required int rank}) {
    final empName = _employeeDisplayName(
      group.employee,
      fallback: 'موظف غير محدد',
    );

    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          childrenPadding: const EdgeInsets.only(
            bottom: 8,
            left: 12,
            right: 12,
          ),
          initiallyExpanded: rank <= 3,
          shape: const Border(),
          collapsedShape: const Border(),

          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade400, Colors.purple.shade400],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              '$rank',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  empName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _currencyFmt.format(group.totalAmount),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.purple.shade700,
                    ),
                  ),
                  Text(
                    '${group.txCount} عملية',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ],
          ),
          children: [...group.transactions.map(_buildTransactionRow)],
        ),
      ),
    );
  }

  /// تسمية الإسناد: من سجّل السحبة / أي جهاز — null إن لا معلومة متاحة
  String? _attributionLabel(_SalaryTxRow tx) {
    final recorder = (tx.recorderName ?? '').trim();
    if (recorder.isNotEmpty) {
      return 'سجّله: $recorder';
    }
    final device = (tx.deviceId ?? '').trim();
    if (device.isNotEmpty) {
      return 'الجهاز: $device';
    }
    final hint = tx.deviceHint;
    if (hint != null && hint.isNotEmpty) {
      return 'الجهاز: $hint';
    }
    return null;
  }

  /// صف معاملة واحد
  Widget _buildTransactionRow(_SalaryTxRow tx) {
    final isDeduction =
        tx.withdrawalType.contains('deduction') ||
        tx.withdrawalType.contains('خصم');
    final accentColor = isDeduction ? Colors.red : Colors.orange;
    final typeLabel = isDeduction ? 'خصم' : 'سحب';
    final typeIcon = isDeduction
        ? Icons.remove_circle_outline
        : Icons.account_balance_wallet;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // الصف الرئيسي: النوع + التاريخ + المبلغ
          Row(
            children: [
              // شارة النوع
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(typeIcon, size: 12, color: accentColor),
                    const SizedBox(width: 4),
                    Text(
                      typeLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // التاريخ والوقت
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 12,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _dateLabelFormat.format(tx.date),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    // ✅ (2026-09-14) الوقت الفعلي للتسجيل من createdAt —
                    // سابقاً كان يظهر 00:00 وهمية لأن withdrawDate نص بلا وقت
                    if (tx.createdAt != null) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.access_time,
                        size: 11,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        _timeFormat.format(tx.createdAt!),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // المبلغ
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _currencyFmt.format(tx.amount),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
          // السبب
          if (tx.reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.label_outline,
                  size: 12,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    tx.reason,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          // ✅ (2026-09-14) الإسناد: من سجّل السحبة وعلى أي جهاز
          // الأولوية: الاسم → عمود deviceId → تلميح من الساعة الاتجاهية
          // (السجلات القديمة قبل وسم deviceId يكشفها الساعة الاتجاهية)
          if (tx.recorderName != null ||
              tx.deviceId != null ||
              tx.deviceHint != null) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.person_outline,
                  size: 12,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _attributionLabel(tx) ?? '',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          // الوصف
          if (tx.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notes, size: 12, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    tx.description,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  DateTime _parseDate(String value) {
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
      dlog(() => '⚠️ تعذر تحليل تاريخ سحب الراتب "$value": $e');
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }
}

/// نتيجة تحميل بيانات التقرير
class _SalaryReportData {
  _SalaryReportData({
    required this.rows,
    required this.groups,
    required this.allEmployees,
  });

  final List<_SalaryTxRow> rows;
  final Map<int, _EmployeeSalaryGroup> groups;
  final List<Employee> allEmployees;
}
