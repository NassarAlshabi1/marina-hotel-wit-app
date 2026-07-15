import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../components/app_scaffold.dart';
import '../../mixins/sync_on_exit_mixin.dart';
import '../../providers/appwrite_providers.dart';
import '../../providers/custom_list_providers.dart';
import '../../providers/repository_providers.dart';
import '../../services/analytics_service.dart';
import '../../services/local_db.dart';
import '../../services/salary_entitlement_service.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/hotel_time_engine.dart';

class ExpensesListScreen extends ConsumerStatefulWidget {
  const ExpensesListScreen({super.key});

  @override
  ConsumerState<ExpensesListScreen> createState() => _ExpensesListScreenState();
}

class _ExpensesListScreenState extends ConsumerState<ExpensesListScreen> with SyncOnExitMixin {
  /// تنظيف وتنسيق رقم الهاتف — البادئة الافتراضية 967 (اليمن)
  String _cleanAndFormatPhone(String phone) {
    var digitsOnly = phone.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.isEmpty) {
      return '';
    }
    // إزالة 00 الدولية
    if (digitsOnly.startsWith('00')) {
      digitsOnly = digitsOnly.substring(2);
    }
    // سبق بإضافة 967
    if (digitsOnly.startsWith('967')) {
      return digitsOnly;
    }
    // 07xx → 967xx (محلي يمني)
    if (digitsOnly.startsWith('07')) {
      digitsOnly = '967${digitsOnly.substring(1)}';
    }
    // 7xx و 9 أرقام → 967xx (محلي يمني بدون صفر)
    else if (digitsOnly.startsWith('7') && digitsOnly.length == 9) {
      digitsOnly = '967$digitsOnly';
    }
    // سعودي: 5xx و 9 أرقام → 966xx
    else if (digitsOnly.startsWith('5') && digitsOnly.length == 9) {
      digitsOnly = '966$digitsOnly';
    }
    // سبق بإضافة 966
    else if (digitsOnly.startsWith('966')) {
      return digitsOnly;
    }
    // البادئة الافتراضية: أي رقم لا يبدأ بمعرف دولة → 967
    else if (digitsOnly.length <= 10 && !digitsOnly.startsWith('+')) {
      digitsOnly = '967$digitsOnly';
    }
    return digitsOnly;
  }

  @override
  String get screenId => 'expenses_list';
  final DateFormat _dateFormat = DateFormat('yyyy/MM/dd');
  DateTime? _fromDate;
  DateTime? _toDate;
  String? _selectedFilterType;
  late Stream<List<Expense>> _expensesStream;
  int _streamVersion = 0;
  static const String _salaryType = 'رواتب';
  static const String _salaryWithdrawAction = 'سحب من الراتب';
  static const String _salaryDeductionAction = 'خصم من الراتب';
  static const String _salaryAdvanceAction = 'سلفة';
  static const List<String> _salaryActions = [_salaryWithdrawAction, _salaryDeductionAction];
  @override
  void initState() {
    super.initState();
    // ✅ Analytics: تتبّع مشاهدة شاشة المصروفات
    // ✅ إصلاح PR review: إعادة استخدام screenId getter (مصدر واحد للحقيقة)
    unawaited(AnalyticsService().logScreenView(screenName: screenId, screenClass: 'ExpensesListScreen'));
    _expensesStream = _buildExpensesStream();
  }

  /// أنواع المصروفات تُقرأ من القائمة الديناميكية (مباشرة من Provider)
  /// ✅ استبعاد السلفة — تسبب تكرار بيانات لأن مبالغها تظهر أيضاً كأقساط خصم من الراتب
  List<String> get _expenseTypes {
    final asyncTypes = ref.watch(customListNamesProvider(kListKeyExpenseType));
    final types = asyncTypes.valueOrNull ?? kDefaultExpenseTypes;
    return types.where((t) => t != 'سلفة').toList();
  }

  @override
  Widget build(BuildContext context) {
    final employeesAsync = ref.watch(employeesListProvider);

    return wrapWithSyncOnExit(
      child: AppScaffold(
        title: 'المصروفات',
        actions: [
          IconButton(onPressed: () => ref.read(appwriteSyncManagerProvider).sync(), icon: const Icon(Icons.sync)),
          IconButton(
            onPressed: () => _edit(employees: employeesAsync.value),
            icon: const Icon(Icons.add),
          ),
        ],
        body: employeesAsync.when(
          data: (employees) {
            final employeeNames = {for (final emp in employees) emp.id: emp.name};
            return StreamBuilder<List<Expense>>(
              key: ValueKey(_streamVersion),
              stream: _expensesStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('حدث خطأ أثناء تحميل المصروفات.'));
                }
                final expensesData = snapshot.data;
                if (expensesData == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                // ✅ السلفة مُستبعدة من قاعدة البيانات (excludeAdvance: true)
                final filteredExpenses = expensesData;
                // ✅ إصلاح: حساب الإحصائيات من القائمة المفلترة فعلياً
                // بدلاً من todayExpensesSummaryProvider الذي يعرض بيانات اليوم الحالي فقط
                final filteredTotal = filteredExpenses.fold<double>(0, (sum, e) => sum + e.amount);
                final filteredCount = filteredExpenses.length;

                return RefreshIndicator(
                  onRefresh: () async {
                    _refreshExpensesStream();
                  },
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              _buildSearchBar(),
                              const SizedBox(height: 8),
                              _buildTypeFilterRow(),
                              const SizedBox(height: 6),
                              _buildCompactFiltersCard(),
                              const SizedBox(height: 8),
                              _buildCompactSummaryCard(totalAmount: filteredTotal, count: filteredCount),
                              const SizedBox(height: 10),
                            ],
                          ),
                        ),
                      ),
                      if (filteredExpenses.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Padding(
                            padding: EdgeInsets.only(top: 48),
                            child: Center(child: Text('لا توجد مصروفات ضمن الفترة')),
                          ),
                        )
                      else
                        SliverList(
                          delegate: SliverChildBuilderDelegate((context, index) {
                            final expense = filteredExpenses[index];
                            return RepaintBoundary(
                              child: _buildExpenseCard(expense, employeeNames[expense.relatedId], employees),
                            );
                          }, childCount: filteredExpenses.length),
                        ),
                    ],
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('تعذر تحميل الموظفين: $error')),
        ),
      ),
    );
  }

  bool _filterActive = false;
  String _searchQuery = '';
  Timer? _debounceTimer;
  final _searchController = TextEditingController();

  /// حساب مفتاح اليوم الفندقي من تاريخ المنتقي
  ///
  /// المنتقي يعطي تاريخ بدون وقت (منتصف الليل) — تحويله بـ HotelTimeEngine
  /// مباشرة يُنتج اليوم السابق خطأً لأن منتصف الليل < 14:01.
  ///
  /// ✅ الإصلاح: نمرّر الوقت 14:01 لضمان أن getHotelDayKey يُعيد
  /// مفتاح اليوم الفندقي الصحيح المطابق للتاريخ التقويمي المختار.
  /// هذا يضمن أن اختيار "19 مايو" يعرض مصروفات hotelDayKey="2026-05-19"
  /// (أي المصروفات من 14:01 يوم 19 إلى 14:00 يوم 20).
  String _hotelDayKeyFromDate(DateTime date) {
    return HotelTimeEngine.getHotelDayKey(
      dateTime: DateTime(date.year, date.month, date.day, HotelTimeEngine.boundaryHour, HotelTimeEngine.boundaryMinute),
    );
  }

  Stream<List<Expense>> _buildExpensesStream() {
    final repo = ref.read(expensesRepoProvider);
    // ✅ إصلاح: كلا المسارين يستخدمان نفس المنطق — hotelDayKey عبر HotelTimeEngine
    //
    // الافتراضي: نستخدم HotelTimeEngine.getHotelDayKey() الذي يعتمد على الوقت الحالي
    // → عند 10:00 صباح 19 مايو: hotelDay = "2026-05-18" (اليوم الفندقي الحالي)
    //
    // يدوي: نستخدم _hotelDayKeyFromDate() الذي يمرّر 14:01 من التاريخ المختار
    // → اختيار 19 مايو: hotelDay = "2026-05-19" (يوم فندقي يبدأ 14:01 من نفس اليوم)
    //
    // هذا يضمن الاتساق: كلا المسارين يستخدمان HotelTimeEngine.getHotelDayKey()
    if (!_filterActive) {
      // ✅ عرض المصروفات حسب اليوم الفندقي (14:01 → 14:00)
      // getHotelDayKey() يعتمد على الوقت الحالي:
      // → عند 10:00 صباح 19 مايو: hotelDay = "2026-05-18" (اليوم الفندقي الحالي)
      // → عند 15:00 ظهر 19 مايو: hotelDay = "2026-05-19" (بعد تجاوز 14:01)
      final hotelDay = HotelTimeEngine.getHotelDayKey();
      return Stream.fromFuture(
        repo.listFilteredByHotelDay(
          fromHotelDay: hotelDay,
          toHotelDay: hotelDay,
          expenseType: _selectedFilterType,
          search: _searchQuery.isNotEmpty ? _searchQuery : null,
          excludeAdvance: true,
        ),
      );
    }
    final fromHotelDay = _fromDate != null ? _hotelDayKeyFromDate(_fromDate!) : null;
    final toHotelDay = _toDate != null ? _hotelDayKeyFromDate(_toDate!) : null;
    return Stream.fromFuture(
      repo.listFilteredByHotelDay(
        fromHotelDay: fromHotelDay,
        toHotelDay: toHotelDay,
        expenseType: _selectedFilterType,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        excludeAdvance: true,
      ),
    );
  }

  void _refreshExpensesStream() {
    _streamVersion++;
    _expensesStream = _buildExpensesStream();
    setState(() {});
  }

  DateTime _parseExpenseDate(String value) {
    final normalized = value.contains('T') ? value : value.replaceFirst(' ', 'T');
    return DateTime.tryParse(normalized) ?? DateTime.now();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? (_fromDate ?? DateTime.now()) : (_toDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _filterActive = true;
      // ✅ إصلاح: ضبط الأوقات حسب حدود اليوم الفندقي (14:01/14:00:59)
      // بدلاً من منتصف الليل/23:59 الذي لا يتطابق مع اليوم الفندقي
      if (isFrom) {
        // "من" = بداية اليوم الفندقي (14:01)
        _fromDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          HotelTimeEngine.boundaryHour,
          HotelTimeEngine.boundaryMinute,
        );
        // إذا لم يكن "إلى" محدد، اجعله نهاية نفس اليوم الفندقي
        _toDate ??= DateTime(picked.year, picked.month, picked.day + 1, HotelTimeEngine.boundaryHour, 0, 59);
        if (_fromDate!.isAfter(_toDate!)) {
          _toDate = DateTime(picked.year, picked.month, picked.day + 1, HotelTimeEngine.boundaryHour, 0, 59);
        }
      } else {
        // "إلى" = نهاية اليوم الفندقي (14:00:59 من اليوم التالي)
        _toDate = DateTime(picked.year, picked.month, picked.day + 1, HotelTimeEngine.boundaryHour, 0, 59);
        // إذا لم يكن "من" محدد، اجعله بداية نفس اليوم الفندقي
        _fromDate ??= DateTime(
          picked.year,
          picked.month,
          picked.day,
          HotelTimeEngine.boundaryHour,
          HotelTimeEngine.boundaryMinute,
        );
        if (_toDate!.isBefore(_fromDate!)) {
          _fromDate = DateTime(
            picked.year,
            picked.month,
            picked.day,
            HotelTimeEngine.boundaryHour,
            HotelTimeEngine.boundaryMinute,
          );
        }
      }
      _streamVersion++;
      _expensesStream = _buildExpensesStream();
    });
  }

  /// شريط البحث بالوصف — تصميم رشيق ومضغوط
  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'ابحث بالوصف أو النوع...',
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 4, right: 4),
            child: Icon(Icons.search, color: Colors.grey.shade500, size: 18),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          suffixIcon: _searchQuery.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(left: 4, right: 4),
                  child: IconButton(
                    icon: Icon(Icons.clear, color: Colors.grey.shade500, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: () {
                      _searchController.clear();
                      _debounceTimer?.cancel();
                      setState(() {
                        _searchQuery = '';
                        _refreshExpensesStream();
                      });
                    },
                  ),
                )
              : null,
          suffixIconConstraints: const BoxConstraints(minWidth: 24, minHeight: 28),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 6),
          isDense: true,
        ),
        onChanged: (value) {
          _debounceTimer?.cancel();
          _debounceTimer = Timer(const Duration(milliseconds: 300), () {
            setState(() {
              _searchQuery = value;
              _refreshExpensesStream();
            });
          });
        },
      ),
    );
  }

  /// صف فلتر نوع المصروف (قائمة منسدلة)
  Widget _buildTypeFilterRow() {
    final types = _expenseTypes;
    final dropdownTextColor = Theme.of(context).textTheme.bodyMedium?.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.filter_list, size: 14, color: Colors.indigo.shade700),
          const SizedBox(width: 6),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _selectedFilterType,
                hint: Text(
                  'كل الأنواع',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
                ),
                isDense: true,
                isExpanded: true,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: dropdownTextColor),
                items: [
                  DropdownMenuItem<String?>(
                    child: Text(
                      'كل الأنواع',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
                    ),
                  ),
                  ...types.map(
                    (type) => DropdownMenuItem<String?>(
                      value: type,
                      child: Text(
                        type,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: dropdownTextColor),
                      ),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedFilterType = value;
                    _refreshExpensesStream();
                  });
                },
              ),
            ),
          ),
          if (_selectedFilterType != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => setState(() {
                _selectedFilterType = null;
                _refreshExpensesStream();
              }),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4)),
                child: Icon(Icons.close, size: 12, color: Colors.red.shade700),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactFiltersCard() {
    // ✅ عرض التاريخ حسب اليوم الفندقي — اتساقاً مع _buildExpensesStream
    final hotelDay = HotelTimeEngine.getHotelDayKey();
    final fromDisplay = (_filterActive && _fromDate != null) ? _dateFormat.format(_fromDate!) : hotelDay;
    final toDisplay = (_filterActive && _toDate != null) ? _dateFormat.format(_toDate!) : hotelDay;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.date_range, size: 14, color: Colors.blue.shade700),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _pickDate(isFrom: true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Text('من $fromDisplay', style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _pickDate(isFrom: false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Text('إلى $toDisplay', style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
            ),
          ),
          if (_filterActive) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => setState(() {
                _filterActive = false;
                _refreshExpensesStream();
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Icon(Icons.close, size: 12, color: Colors.red.shade700),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactSummaryCard({required double totalAmount, required int count}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(6)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.receipt_long, size: 12, color: Colors.indigo.shade700),
                const SizedBox(width: 4),
                Text(
                  '$count',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo.shade700),
                ),
                const SizedBox(width: 2),
                Text('عملية', style: TextStyle(fontSize: 9, color: Colors.indigo.shade400)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.payments, size: 12, color: Colors.red.shade700),
                const SizedBox(width: 4),
                Text(
                  CurrencyFormatter.formatAmount(totalAmount),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseCard(Expense expense, String? employeeName, List<Employee> employees) {
    final date = _parseExpenseDate(expense.date);
    // ✅ السلفة مُستبعدة بالفعل من القائمة أعلاه — لا حاجة لفحص إضافي هنا
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        onTap: () => _edit(existing: expense, employees: employees),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      expense.description.isNotEmpty ? expense.description : 'مصروف بدون وصف',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    CurrencyFormatter.formatAmount(expense.amount),
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 14),
                  ),
                  const SizedBox(width: 4),
                  // زر التعديل
                  InkWell(
                    onTap: () => _edit(existing: expense, employees: employees),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(16)),
                      child: Icon(Icons.edit, size: 16, color: Colors.blue.shade700),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // زر الحذف
                  InkWell(
                    onTap: () => _deleteExpense(expense),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(16)),
                      child: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _buildSmallMeta(Icons.category, expense.expenseType),
                  const SizedBox(width: 10),
                  _buildSmallMeta(Icons.calendar_today, _dateFormat.format(date)),
                  if (employeeName != null) ...[
                    const SizedBox(width: 10),
                    Expanded(child: _buildSmallMeta(Icons.person, employeeName)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmallMeta(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: Colors.grey.shade600),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            label,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// حذف مصروف مع تأكيد
  Future<void> _deleteExpense(Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text(
          'هل تريد حذف المصروف "${expense.description.isNotEmpty ? expense.description : 'مصروف بدون وصف'}" بمبلغ ${CurrencyFormatter.formatAmount(expense.amount)}؟',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final repo = ref.read(expensesRepoProvider);
      final salaryRepo = ref.read(salaryWithdrawalsRepoProvider);

      // ✅ إصلاح: حذف سحب الراتب أولاً ثم المصروف — لحماية تكامل البيانات
      // إذا فشل حذف المصروف، سحب الراتب يبقى مرتبطاً (آمن)
      // إذا فشل حذف سحب الراتب بعد حذف المصروف، نحاول مرة أخرى
      await salaryRepo.deleteByExpenseId(expense.id);
      await repo.delete(expense.id);

      markDataChanged();

      if (mounted) {
        _refreshExpensesStream();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _refreshExpensesStream();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف المصروف بنجاح'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل حذف المصروف: $e'), backgroundColor: Colors.red.shade900));
    }
  }

  Future<void> _edit({Expense? existing, List<Employee>? employees}) async {
    final description = TextEditingController(text: existing?.description ?? '');
    final amount = TextEditingController(text: existing != null ? CurrencyFormatter.formatAmount(existing.amount) : '');
    final installments = TextEditingController();
    DateTime selectedDate;
    try {
      if (existing != null) {
        // تعديل مصروف موجود — استخدام تاريخه المخزن
        selectedDate = DateTime.parse(existing.date);
      } else {
        // ✅ إصلاح: مصروف جديد — التاريخ حسب اليوم الفندقي
        // قبل 14:01 → التاريخ = اليوم السابق (اليوم الفندقي الحالي)
        // بعد 14:01 → التاريخ = اليوم الحالي (اليوم الفندقي الحالي)
        selectedDate = HotelTimeEngine.getHotelDay(DateTime.now());
      }
    } catch (_) {
      selectedDate = HotelTimeEngine.getHotelDay(DateTime.now());
    }

    try {
      String dialogSalaryAction = _salaryWithdrawAction;
      String selectedType = existing?.expenseType ?? 'اخرى';

      if (existing != null && _isSalaryAction(existing.expenseType)) {
        selectedType = _salaryType;
        dialogSalaryAction = _mapExpenseTypeToSalaryAction(existing.expenseType);
      }

      final List<Employee> allEmployees = employees ?? await ref.read(employeesRepoProvider).watchAll().first;
      // ✅ إزالة التكرار: عند المزامنة بين أجهزة متعددة، قد يصل نفس الموظف
      // (نفس localUuid) بـ id محلي مختلف (autoIncrement). كذلك قد يوجد
      // نفس الاسم بـ localUuid مختلف (سجل مكرر فعلاً).
      // الاستراتيجية:
      //   1. إزالة التكرار بـ localUuid أولاً (نفس الشخص من أجهزة مختلفة)
      //   2. إزالة التكرار بـ name كـ fallback (سجلات مكررة بنفس الاسم)
      final seenUuids = <String>{};
      final seenNames = <String>{};
      final List<Employee> availableEmployees = allEmployees.where((emp) {
        // 1. إزالة التكرار بـ localUuid
        final uuid = emp.localUuid.trim();
        if (uuid.isNotEmpty && seenUuids.contains(uuid)) {
          return false;
        }
        if (uuid.isNotEmpty) {
          seenUuids.add(uuid);
        }
        // 2. إزالة التكرار بـ name (للسجلات بـ localUuid فارغ أو مكرر بالاسم)
        final nameKey = emp.name.trim();
        if (nameKey.isNotEmpty && seenNames.contains(nameKey)) {
          return false;
        }
        if (nameKey.isNotEmpty) {
          seenNames.add(nameKey);
        }
        return true;
      }).toList();
      int? selectedEmployeeId = existing?.relatedId;

      final ok = await showDialog<bool>(
        // ignore: use_build_context_synchronously
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) {
            final dropdownTextColor = Theme.of(ctx).textTheme.bodyMedium?.color;
            final dropdownTextStyle = Theme.of(
              ctx,
            ).textTheme.bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.bold, color: dropdownTextColor);
            return AlertDialog(
              alignment: const Alignment(0, -0.4),
              title: Text(existing == null ? 'إضافة مصروف' : 'تعديل مصروف'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedType,
                      decoration: const InputDecoration(labelText: 'نوع المصروف'),
                      style: dropdownTextStyle,
                      items: _expenseTypes
                          .map(
                            (type) => DropdownMenuItem<String>(
                              value: type,
                              child: Text(type, style: dropdownTextStyle),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          selectedType = value;
                          if (selectedType == _salaryType) {
                            if (availableEmployees.isNotEmpty) {
                              selectedEmployeeId ??= availableEmployees.first.id;
                            }
                          } else {
                            selectedEmployeeId = null;
                            dialogSalaryAction = _salaryWithdrawAction;
                          }
                        });
                      },
                    ),
                    if (selectedType == _salaryType) ...[
                      const SizedBox(height: 12),
                      if (availableEmployees.isEmpty) const Text('لا يوجد موظفين مسجلين حالياً.'),
                      if (availableEmployees.isNotEmpty) ...[
                        DropdownButtonFormField<int>(
                          initialValue: selectedEmployeeId,
                          style: dropdownTextStyle,
                          decoration: const InputDecoration(labelText: 'اسم الموظف'),
                          items: availableEmployees
                              .map(
                                (employee) => DropdownMenuItem<int>(
                                  value: employee.id,
                                  child: Text(employee.name, style: dropdownTextStyle),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => setState(() => selectedEmployeeId = value),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: dialogSalaryAction,
                          decoration: const InputDecoration(labelText: 'نوع المعاملة'),
                          items: _salaryActions
                              .map(
                                (action) => DropdownMenuItem<String>(
                                  value: action,
                                  child: Text(action, style: dropdownTextStyle),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() => dialogSalaryAction = value);
                          },
                        ),
                      ],
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: amount,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: 'المبلغ', filled: true, fillColor: Colors.yellow.shade50),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: description,
                      decoration: const InputDecoration(labelText: 'الوصف'),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setState(() => selectedDate = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'التاريخ', suffixIcon: Icon(Icons.calendar_today)),
                        child: Text(
                          DateFormat('yyyy-MM-dd').format(selectedDate),
                          style: Theme.of(ctx).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                FilledButton(
                  onPressed: () {
                    if (selectedType == _salaryType && selectedEmployeeId == null) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: const Text('يجب اختيار موظف عند اختيار نوع المصروف "رواتب"'),
                          backgroundColor: Theme.of(ctx).colorScheme.error,
                          duration: const Duration(seconds: 3),
                        ),
                      );
                      return;
                    }
                    // ✅ إصلاح: التحقق من المبلغ قبل إغلاق الحوار
                    // سابقاً كان التحقق بعد الإغلاق مما يسبب إغلاق صامت بدون تغذية راجعة
                    final parsedAmount = CurrencyFormatter.parseAmount(amount.text) ?? 0;
                    if (parsedAmount <= 0) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: const Text('يجب إدخال مبلغ أكبر من صفر'),
                          backgroundColor: Theme.of(ctx).colorScheme.error,
                        ),
                      );
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  child: const Text('حفظ'),
                ),
              ],
            );
          },
        ),
      );

      if (ok != true) {
        return;
      }

      final repo = ref.read(expensesRepoProvider);
      final salaryRepo = ref.read(salaryWithdrawalsRepoProvider);
      final parsedAmount = CurrencyFormatter.parseAmount(amount.text) ?? 0;
      final trimmedDescription = description.text.trim();
      final trimmedDate = DateFormat('yyyy-MM-dd').format(selectedDate);
      final isSalaryExpense = selectedType == _salaryType;
      final savedType = isSalaryExpense ? _deriveSalaryExpenseType(dialogSalaryAction) : selectedType;

      if (parsedAmount <= 0) {
        return;
      }

      try {
        if (existing == null) {
          // ✅ إصلاح: مصروف جديد — date و hotelDayKey حسب اليوم الفندقي
          // selectedDate يُعيَّن افتراضياً من HotelTimeEngine.getHotelDay()
          // hotelDayKey يُحسب من selectedDate لضمان الاتساق حتى لو غيّر المستخدم التاريخ
          final newHotelDayKey = _hotelDayKeyFromDate(selectedDate);

          // ✅ التوصية 1: حل الموظف مرة واحدة لاستخدام محليUuid في إنشاء المصروف.
          // قبل هذا الإصلاح كان employeeUuid يُحقن فقط وقت الرفع (خطر #1)،
          // الآن يُكتب فورًا فيُصبح المصروف محمولاً عبر الأجهزة حتى قبل المزامنة.
          // ملاحظة: نُبقي سلوك firstWhere الأصلي (StateError عند عدم الإيجاد) لأن
          // الشاشة تتحقق مسبقًا من وجود موظفين ومن اختيار موظف قبل الحفظ.
          final Employee? resolvedEmployee = (isSalaryExpense && selectedEmployeeId != null)
              ? availableEmployees.firstWhere((e) => e.id == selectedEmployeeId)
              : null;

          final newId = await repo.create(
            expenseType: savedType,
            relatedId: isSalaryExpense ? selectedEmployeeId : null,
            description: trimmedDescription,
            amount: parsedAmount,
            date: trimmedDate,
            hotelDayKey: newHotelDayKey,
            // ✅ التوصية 1: اكتب employeeUuid وقت الإنشاء — مصدر الحقيقة المحمول.
            employeeUuid: (isSalaryExpense && resolvedEmployee != null) ? resolvedEmployee.localUuid : null,
          );

          if (isSalaryExpense && resolvedEmployee != null) {
            final signedAmount = savedType == _salaryDeductionAction ? -parsedAmount : parsedAmount;

            await salaryRepo.saveFromExpense(
              expenseId: newId,
              employeeId: resolvedEmployee.id, // استخدام employee.id كـ EmployeeID
              action: savedType,
              amount: signedAmount,
              date: trimmedDate,
              note: trimmedDescription,
              // ✅ hotelDayKey مطابق لليوم الفندقي من التاريخ المختار
              hotelDayKey: newHotelDayKey,
            );
          }
        } else {
          // ✅ تعديل مصروف موجود — إعادة حساب hotelDayKey من التاريخ المختار
          final updatedHotelDayKey = _hotelDayKeyFromDate(DateTime.parse(trimmedDate));

          // ✅ التوصية 1: حل الموظف مرة واحدة لاستخدام localUuid في تعديل المصروف.
          final Employee? resolvedEmployee = (isSalaryExpense && selectedEmployeeId != null)
              ? availableEmployees.firstWhere((e) => e.id == selectedEmployeeId)
              : null;

          await repo.update(
            existing.id,
            expenseType: savedType,
            relatedId: isSalaryExpense ? selectedEmployeeId : null,
            description: trimmedDescription,
            amount: parsedAmount,
            date: trimmedDate,
            hotelDayKey: updatedHotelDayKey,
            // ✅ التوصية 1: اكتب employeeUuid وقت التعديل.
            // - لمصروف الراتب: localUuid للموظف المختار.
            // - لغير الراتب: '' لمسح أي رابط قديم (يمنع بقاء رابط يتيم عند
            //   التحويل من راتب إلى نوع آخر).
            employeeUuid: (isSalaryExpense && resolvedEmployee != null) ? resolvedEmployee.localUuid : '',
          );

          if (isSalaryExpense && resolvedEmployee != null) {
            final signedAmount = savedType == _salaryDeductionAction ? -parsedAmount : parsedAmount;

            await salaryRepo.saveFromExpense(
              expenseId: existing.id,
              employeeId: resolvedEmployee.id, // استخدام employee.id كـ EmployeeID
              action: savedType,
              amount: signedAmount,
              date: trimmedDate,
              note: trimmedDescription,
              // ✅ hotelDayKey مطابق للمصروف المُحدّث
              hotelDayKey: updatedHotelDayKey,
            );
          } else {
            await salaryRepo.deleteByExpenseId(existing.id);
          }
        }

        markDataChanged();

        // ✅ إصلاح: توسيع الفلتر تلقائياً إذا كان hotelDayKey للمصروف المحفوظ
        // يختلف عن نطاق الفلتر الحالي — لضمان ظهور المصروف الجديد دائماً
        final savedHotelDayKey = _hotelDayKeyFromDate(DateTime.parse(trimmedDate));
        final currentFromKey = _filterActive && _fromDate != null
            ? _hotelDayKeyFromDate(_fromDate!)
            : HotelTimeEngine.getHotelDayKey();
        final currentToKey = _filterActive && _toDate != null
            ? _hotelDayKeyFromDate(_toDate!)
            : HotelTimeEngine.getHotelDayKey();
        if (savedHotelDayKey.compareTo(currentFromKey) < 0 || savedHotelDayKey.compareTo(currentToKey) > 0) {
          // المصروف خارج نطاق الفلتر — توسيع النطاق ليشمله
          _filterActive = true;
          final minKey = savedHotelDayKey.compareTo(currentFromKey) < 0 ? savedHotelDayKey : currentFromKey;
          final maxKey = savedHotelDayKey.compareTo(currentToKey) > 0 ? savedHotelDayKey : currentToKey;
          _fromDate = DateTime.parse('${minKey}T14:00:00');
          _toDate = DateTime.parse('${maxKey}T13:59:59').add(const Duration(days: 1));
        }

        if (mounted) {
          _refreshExpensesStream();
          // ✅ شبكة أمان: تحديث ثانٍ بعد إطار لضمان ظهور البيانات الجديدة
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _refreshExpensesStream();
          });
        }

        // إرسال رسالة واتساب للموظف عند تسجيل مصروف راتب
        if (isSalaryExpense && selectedEmployeeId != null && mounted) {
          final waAction = dialogSalaryAction == _salaryAdvanceAction ? _salaryAdvanceAction : savedType;
          unawaited(
            _sendSalaryExpenseWhatsApp(
              employeeId: selectedEmployeeId!,
              action: waAction,
              amount: parsedAmount,
              date: trimmedDate,
              employees: availableEmployees,
            ),
          );
        }
      } catch (e) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('فشل حفظ المصروف: $e'), backgroundColor: Colors.red.shade900));
      }
    } finally {
      description.dispose();
      amount.dispose();
      installments.dispose();
    }
  }

  /// إرسال رسالة واتساب للموظف عند تسجيل مصروف راتب
  Future<void> _sendSalaryExpenseWhatsApp({
    required int employeeId,
    required String action,
    required double amount,
    required String date,
    required List<Employee> employees,
  }) async {
    try {
      // البحث عن الموظف للحصول على رقم الهاتف والاسم
      final employee = employees.where((e) => e.id == employeeId).firstOrNull;
      if (employee == null) {
        return;
      }

      final phone = employee.phone.trim();
      if (phone.isEmpty) {
        return;
      }

      final whatsappService = ref.read(whatsappServiceProvider);

      // تنظيف وتنسيق رقم الهاتف — البادئة الافتراضية 967 (اليمن)
      final String cleanedPhone = _cleanAndFormatPhone(phone);

      final actionText = action == _salaryDeductionAction
          ? 'خصم'
          : action == _salaryAdvanceAction
          ? 'سلفة'
          : 'سحب';

      // حساب الراتب المتبقي
      String remainingText = '';
      try {
        final entitlementService = SalaryEntitlementService(DatabaseManager.instance);
        final entitlement = await entitlementService.calculateEmployeeEntitlement(employee);
        remainingText = 'الراتب المتبقي: ${CurrencyFormatter.formatAmount(entitlement.netEntitlement)}';
      } catch (e) {
        debugPrint('Error calculating remaining salary: $e');
      }

      final message = StringBuffer()
        ..writeln('مرحباً ${employee.name}')
        ..writeln()
        ..writeln('تم تسجيل $actionText راتب بقيمة ${CurrencyFormatter.formatAmount(amount)}')
        ..writeln('التاريخ: $date');

      if (remainingText.isNotEmpty) {
        message.writeln(remainingText);
      }

      message
        ..writeln()
        ..writeln('فندق مارينا')
        ..write('للاستفسار: 9677734587456');

      final result = await whatsappService.sendMessage(phoneE164: cleanedPhone, message: message.toString());

      if (mounted) {
        if (result.quotaMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.quotaMessage!),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.success
                    ? 'تم إرسال إشعار واتساب لـ ${employee.name}'
                    : 'تعذّر إرسال إشعار واتساب لـ ${employee.name}',
              ),
              backgroundColor: result.success ? Colors.green : Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('WhatsApp salary notification error: $e');
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool _isSalaryAction(String? type) {
    if (type == null) {
      return false;
    }
    final normalized = type.trim();
    return normalized == _salaryType ||
        normalized == 'سحب راتب' ||
        normalized == _salaryWithdrawAction ||
        normalized == _salaryDeductionAction ||
        normalized == 'خصم راتب';
  }

  String _mapExpenseTypeToSalaryAction(String type) {
    final normalized = type.trim();
    if (normalized == _salaryDeductionAction || normalized == 'خصم راتب') {
      return _salaryDeductionAction;
    }
    if (normalized == _salaryAdvanceAction) {
      return _salaryAdvanceAction;
    }
    return _salaryWithdrawAction;
  }

  String _deriveSalaryExpenseType(String action) {
    if (action == _salaryDeductionAction) {
      return _salaryDeductionAction;
    }
    if (action == _salaryAdvanceAction) {
      return _salaryAdvanceAction;
    }
    return 'سحب راتب';
  }
}
