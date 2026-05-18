import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../components/app_scaffold.dart';
import '../../mixins/sync_on_exit_mixin.dart';
import '../../providers/appwrite_providers.dart';
import '../../providers/custom_list_providers.dart';
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart';
import '../../services/salary_entitlement_service.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/time.dart';

class ExpensesListScreen extends ConsumerStatefulWidget {
  const ExpensesListScreen({super.key});

  @override
  ConsumerState<ExpensesListScreen> createState() => _ExpensesListScreenState();
}

class _ExpensesListScreenState extends ConsumerState<ExpensesListScreen>
    with SyncOnExitMixin {
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
  String? selectedType;
  late Stream<List<Expense>> _expensesStream;
  static const String _salaryType = 'رواتب';
  static const String _salaryWithdrawAction = 'سحب من الراتب';
  static const String _salaryDeductionAction = 'خصم من الراتب';
  static const String _salaryAdvanceAction = 'سلفة';
  static const List<String> _salaryActions = [
    _salaryWithdrawAction,
    _salaryDeductionAction,
    _salaryAdvanceAction,
  ];
  @override
  void initState() {
    super.initState();
    _expensesStream = _buildExpensesStream();
  }

  /// أنواع المصروفات تُقرأ من القائمة الديناميكية (مباشرة من Provider)
  List<String> get _expenseTypes {
    final asyncTypes = ref.watch(customListNamesProvider(kListKeyExpenseType));
    return asyncTypes.valueOrNull ?? kDefaultExpenseTypes;
  }

  @override
  Widget build(BuildContext context) {
    final employeesAsync = ref.watch(employeesListProvider);

    final todaySummary = ref.watch(todayExpensesSummaryProvider);
    final todayData = todaySummary.valueOrNull ?? (count: 0, total: 0.0);

    return wrapWithSyncOnExit(
      child: AppScaffold(
        title: 'المصروفات',
        actions: [
          IconButton(
            onPressed: () => ref.read(appwriteSyncManagerProvider).sync(),
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            onPressed: () => _edit(employees: employeesAsync.value),
            icon: const Icon(Icons.add),
          ),
        ],
        body: employeesAsync.when(
          data: (employees) {
            final employeeNames = {
              for (final emp in employees) emp.id: emp.name,
            };
            return StreamBuilder<List<Expense>>(
              stream: _expensesStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('حدث خطأ أثناء تحميل المصروفات.'),
                  );
                }
                final expensesData = snapshot.data;
                if (expensesData == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                // ── فلتر البحث بالوصف ──
                final filteredExpenses = _searchQuery.isEmpty
                    ? expensesData
                    : expensesData.where((expense) {
                        final q = _searchQuery.toLowerCase();
                        return expense.description.toLowerCase().contains(q) ||
                            expense.expenseType.toLowerCase().contains(q) ||
                            (employeeNames[expense.relatedId]?.toLowerCase().contains(q) ?? false);
                      }).toList();

                return RefreshIndicator(
                  onRefresh: () async {
                    _refreshExpensesStream();
                  },
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _buildSearchBar(),
                      const SizedBox(height: 8),
                      _buildCompactFiltersCard(),
                      const SizedBox(height: 8),
                      _buildCompactSummaryCard(
                        totalAmount: todayData.total,
                        count: todayData.count,
                      ),
                      const SizedBox(height: 10),
                      if (filteredExpenses.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 48),
                          child: Center(
                            child: Text('لا توجد مصروفات ضمن الفترة'),
                          ),
                        )
                      else
                        ...filteredExpenses.map(
                          (expense) => RepaintBoundary(
                            child: _buildExpenseCard(
                              expense,
                              employeeNames[expense.relatedId],
                              employees,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              Center(child: Text('تعذر تحميل الموظفين: $error')),
        ),
      ),
    );
  }

  bool _filterActive = false;
  String _searchQuery = '';
  Timer? _debounceTimer;
  final _searchController = TextEditingController();

  Stream<List<Expense>> _buildExpensesStream() {
    final repo = ref.read(expensesRepoProvider);
    if (!_filterActive) {
      // الافتراضي: عرض مصروفات اليوم الفندقي فقط
      final hotelDay = Time.hotelDayKey();
      return Stream.fromFuture(
        repo.listFiltered(from: hotelDay, to: hotelDay),
      );
    }
    final fromStr = _fromDate != null ? Time.dateToString(_fromDate!) : null;
    final toStr = _toDate != null ? Time.dateToString(_toDate!) : null;
    return Stream.fromFuture(repo.listFiltered(from: fromStr, to: toStr));
  }

  void _refreshExpensesStream() {
    setState(() {
      _expensesStream = _buildExpensesStream();
    });
  }

  DateTime _parseExpenseDate(String value) {
    final normalized = value.contains('T')
        ? value
        : value.replaceFirst(' ', 'T');
    return DateTime.tryParse(normalized) ?? DateTime.now();
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
    if (picked == null) {
      return;
    }
    setState(() {
      _filterActive = true;
      if (isFrom) {
        _fromDate = DateTime(picked.year, picked.month, picked.day);
        // إذا لم يكن "إلى" محدد، اجعله نفس تاريخ "من"
        _toDate ??= DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        if (_fromDate!.isAfter(_toDate!)) {
          _toDate = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        }
      } else {
        _toDate = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        // إذا لم يكن "من" محدد، اجعله نفس تاريخ "إلى"
        _fromDate ??= DateTime(picked.year, picked.month, picked.day);
        if (_toDate!.isBefore(_fromDate!)) {
          _fromDate = DateTime(picked.year, picked.month, picked.day);
        }
      }
      _expensesStream = _buildExpensesStream();
    });
  }

  /// شريط البحث بالوصف
  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'ابحث بالوصف أو النوع أو اسم الموظف...',
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          prefixIcon: Icon(Icons.search, color: Colors.grey.shade500),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: Colors.grey.shade500, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    _debounceTimer?.cancel();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          isDense: true,
        ),
        onChanged: (value) {
          _debounceTimer?.cancel();
          _debounceTimer = Timer(const Duration(milliseconds: 300), () {
            setState(() => _searchQuery = value);
          });
        },
      ),
    );
  }

  Widget _buildCompactFiltersCard() {
    final hotelDay = Time.hotelDayKey();
    final fromDisplay = (_filterActive && _fromDate != null)
        ? _dateFormat.format(_fromDate!)
        : hotelDay;
    final toDisplay = (_filterActive && _toDate != null)
        ? _dateFormat.format(_toDate!)
        : hotelDay;
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
              child: Text(
                'من $fromDisplay',
                style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
              ),
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
              child: Text(
                'إلى $toDisplay',
                style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
              ),
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

  Widget _buildCompactSummaryCard({
    required double totalAmount,
    required int count,
  }) {
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
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.receipt_long, size: 12, color: Colors.indigo.shade700),
                const SizedBox(width: 4),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade700,
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  'عملية',
                  style: TextStyle(fontSize: 9, color: Colors.indigo.shade400),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.payments, size: 12, color: Colors.red.shade700),
                const SizedBox(width: 4),
                Text(
                  CurrencyFormatter.formatAmount(totalAmount),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseCard(
    Expense expense,
    String? employeeName,
    List<Employee> employees,
  ) {
    final date = _parseExpenseDate(expense.date);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _edit(existing: expense, employees: employees),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      expense.description.isNotEmpty
                          ? expense.description
                          : 'مصروف بدون وصف',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    CurrencyFormatter.formatAmount(expense.amount),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _buildMetaChip(Icons.category, expense.expenseType),
                  _buildMetaChip(
                    Icons.calendar_today,
                    _dateFormat.format(date),
                  ),
                  _buildMetaChip(Icons.person, employeeName ?? 'بدون موظف'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetaChip(IconData icon, String label) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }

  Future<void> _edit({Expense? existing, List<Employee>? employees}) async {
    final description = TextEditingController(
      text: existing?.description ?? '',
    );
    final amount = TextEditingController(
      text: existing != null
          ? CurrencyFormatter.formatAmount(existing.amount)
          : '',
    );
    final installments = TextEditingController();
    DateTime selectedDate;
    try {
      selectedDate = DateTime.parse(existing?.date ?? Time.hotelDayKey());
    } catch (_) {
      selectedDate = DateTime.now();
    }

    try {
    String dialogSalaryAction = _salaryWithdrawAction;
    bool startNextMonth = true;
    selectedType = existing?.expenseType ?? 'اخرى';

    if (existing != null && _isSalaryAction(existing.expenseType)) {
      selectedType = _salaryType;
      dialogSalaryAction = _mapExpenseTypeToSalaryAction(existing.expenseType);
    }

    final List<Employee> availableEmployees =
        employees ?? await ref.read(employeesRepoProvider).watchAll().first;
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
                    if (availableEmployees.isEmpty)
                      const Text('لا يوجد موظفين مسجلين حالياً.'),
                    if (availableEmployees.isNotEmpty) ...[
                      DropdownButtonFormField<int>(
                        initialValue: selectedEmployeeId,
                        style: dropdownTextStyle,
                        decoration: const InputDecoration(
                          labelText: 'اسم الموظف',
                        ),
                        items: availableEmployees
                            .map(
                              (employee) => DropdownMenuItem<int>(
                                value: employee.id,
                                child: Text(employee.name, style: dropdownTextStyle),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => selectedEmployeeId = value),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: dialogSalaryAction,
                        decoration: const InputDecoration(
                          labelText: 'نوع المعاملة',
                        ),
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
                      if (existing == null &&
                          dialogSalaryAction == _salaryAdvanceAction) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: installments,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'عدد الأقساط',
                          ),
                        ),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          value: startNextMonth,
                          onChanged: (v) => setState(() {
                            startNextMonth = v ?? true;
                          }),
                          title: const Text('ابدأ الخصم من الشهر القادم'),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ],
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: amount,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'المبلغ',
                      filled: true,
                      fillColor: Colors.yellow.shade50,
                    ),
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
                      decoration: const InputDecoration(
                        labelText: 'التاريخ',
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
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
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () {
                  if (selectedType == _salaryType &&
                      selectedEmployeeId == null) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: const Text(
                          'يجب اختيار موظف عند اختيار نوع المصروف "رواتب"',
                        ),
                        backgroundColor: Theme.of(ctx).colorScheme.error,
                        duration: const Duration(seconds: 5),
                        action: SnackBarAction(
                          label: 'إغلاق',
                          textColor: Colors.white,
                          onPressed: () =>
                              ScaffoldMessenger.of(ctx).hideCurrentSnackBar(),
                        ),
                      ),
                    );
                    return;
                  }
                  if (existing == null &&
                      selectedType == _salaryType &&
                      dialogSalaryAction == _salaryAdvanceAction) {
                    final count = int.tryParse(installments.text.trim()) ?? 0;
                    if (count <= 0) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: const Text('يجب إدخال عدد الأقساط'),
                          backgroundColor: Theme.of(ctx).colorScheme.error,
                        ),
                      );
                      return;
                    }
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
    final savedType = isSalaryExpense
        ? _deriveSalaryExpenseType(dialogSalaryAction)
        : (selectedType ?? 'اخرى');

    if (parsedAmount <= 0) {
      return;
    }

    try {
      if (existing == null) {
        if (isSalaryExpense &&
            selectedEmployeeId != null &&
            dialogSalaryAction == _salaryAdvanceAction) {
          final count = int.tryParse(installments.text.trim()) ?? 0;
          await ref
              .read(salaryAdvanceInstallmentsServiceProvider)
              .createInstallmentAdvance(
                employeeId: selectedEmployeeId!,
                totalAmount: parsedAmount,
                advanceDate: trimmedDate,
                description: trimmedDescription,
                installments: count,
                startNextMonth: startNextMonth,
              );
        } else {
          final newId = await repo.create(
            expenseType: savedType,
            relatedId: isSalaryExpense ? selectedEmployeeId : null,
            description: trimmedDescription,
            amount: parsedAmount,
            date: trimmedDate,
          );

          if (isSalaryExpense && selectedEmployeeId != null) {
            final signedAmount = savedType == _salaryDeductionAction
                ? -parsedAmount
                : parsedAmount;
            await salaryRepo.saveFromExpense(
              expenseId: newId,
              employeeId: selectedEmployeeId!,
              action: savedType,
              amount: signedAmount,
              date: trimmedDate,
              note: trimmedDescription,
              hotelDayKey: trimmedDate,
            );
          }
        }
      } else {
        await repo.update(
          existing.id,
          expenseType: savedType,
          relatedId: isSalaryExpense ? selectedEmployeeId : null,
          description: trimmedDescription,
          amount: parsedAmount,
          date: trimmedDate,
        );

        if (isSalaryExpense && selectedEmployeeId != null) {
          final signedAmount =
              savedType == _salaryDeductionAction ? -parsedAmount : parsedAmount;
          await salaryRepo.saveFromExpense(
            expenseId: existing.id,
            employeeId: selectedEmployeeId!,
            action: savedType,
            amount: signedAmount,
            date: trimmedDate,
            note: trimmedDescription,
            hotelDayKey: trimmedDate,
          );
        } else {
          await salaryRepo.deleteByExpenseId(existing.id);
        }
      }

      markDataChanged();
      if (mounted) {
        _refreshExpensesStream();
      }

      // إرسال رسالة واتساب للموظف عند تسجيل مصروف راتب
      if (isSalaryExpense && selectedEmployeeId != null && mounted) {
        final waAction = dialogSalaryAction == _salaryAdvanceAction
            ? _salaryAdvanceAction
            : savedType;
        unawaited(_sendSalaryExpenseWhatsApp(
          employeeId: selectedEmployeeId!,
          action: waAction,
          amount: parsedAmount,
          date: trimmedDate,
          employees: availableEmployees,
        ),);
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل حفظ المصروف: $e'),
          backgroundColor: Colors.red.shade900,
        ),
      );
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
        final entitlementService = SalaryEntitlementService(
          DatabaseManager.instance,
        );
        final entitlement = await entitlementService
            .calculateEmployeeEntitlement(employee);
        remainingText =
            'الراتب المتبقي: ${CurrencyFormatter.formatAmount(entitlement.netEntitlement)}';
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

      final result = await whatsappService.sendMessage(
        phoneE164: cleanedPhone,
        message: message.toString(),
      );

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
              content: Text(result.success
                  ? 'تم إرسال إشعار واتساب لـ ${employee.name}'
                  : 'تعذّر إرسال إشعار واتساب لـ ${employee.name}',),
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
        normalized == _salaryAdvanceAction ||
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
