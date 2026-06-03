import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../mixins/sync_on_exit_mixin.dart';
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/time.dart';
import 'create_debt_from_booking.dart';

class DebtsListScreen extends ConsumerStatefulWidget {
  const DebtsListScreen({super.key});

  @override
  ConsumerState<DebtsListScreen> createState() => _DebtsListScreenState();
}

class _DebtsListScreenState extends ConsumerState<DebtsListScreen>
    with SyncOnExitMixin {
  @override
  String get screenId => 'debts_list';
  String _searchQuery = '';
  String _filterStatus = 'all'; // all, pending, settled, overdue
  Timer? _debounceTimer;
  bool _isSendingWhatsApp = false;

  /// تنظيف وتنسيق رقم الهاتف
  String _cleanAndFormatPhone(String phone) {
    var digitsOnly = phone.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.isEmpty) {
      return '';
    }
    if (digitsOnly.startsWith('00')) {
      digitsOnly = digitsOnly.substring(2);
    }
    if (digitsOnly.startsWith('967')) {
      return digitsOnly;
    }
    if (digitsOnly.startsWith('07')) {
      digitsOnly = '967${digitsOnly.substring(1)}';
    } else if (digitsOnly.startsWith('7') && digitsOnly.length == 9) {
      digitsOnly = '967$digitsOnly';
    } else if (digitsOnly.startsWith('5') && digitsOnly.length == 9) {
      digitsOnly = '966$digitsOnly';
    } else if (digitsOnly.startsWith('966')) {
      return digitsOnly;
    }
    else if (digitsOnly.length <= 10 && !digitsOnly.startsWith('+')) {
      digitsOnly = '967$digitsOnly';
    }
    return digitsOnly;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final debtsAsync = ref.watch(debtsListProvider);

    return wrapWithSyncOnExit(
      child: AppScaffold(
        title: 'إدارة الديون',
        actions: [
          IconButton(
            onPressed: () => _showQuickAddMenu(context),
            icon: const Icon(Icons.add_circle),
            tooltip: 'إضافة دين جديد',
          ),
        ],
        body: Column(
          children: [
            // شريط البحث والتصفية
            _buildSearchAndFilters(),

            // الإحصائيات السريعة
            _buildQuickStats(),

            // قائمة الديون
            Expanded(
              child: debtsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error, size: 64, color: Colors.red.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'حدث خطأ في تحميل البيانات',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        error.toString(),
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                data: _buildDebtsList,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey.shade50,
      child: Column(
        children: [
          // شريط البحث
          TextField(
            style: const TextStyle(fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: 'ابحث باسم النزيل أو رقم الغرفة...',
              hintStyle: TextStyle(
                fontWeight: FontWeight.normal,
                color: Colors.grey[500],
              ),
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            onChanged: (value) {
              _debounceTimer?.cancel();
              _debounceTimer = Timer(const Duration(milliseconds: 300), () {
                setState(() => _searchQuery = value);
              });
            },
          ),

          const SizedBox(height: 12),

          // مرشحات الحالة
          Row(
            children: [
              Expanded(child: _buildFilterChip('الكل', 'all')),
              const SizedBox(width: 8),
              Expanded(child: _buildFilterChip('معلق', 'pending')),
              const SizedBox(width: 8),
              Expanded(child: _buildFilterChip('مسدد', 'settled')),
              const SizedBox(width: 8),
              Expanded(child: _buildFilterChip('متأخر', 'overdue')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filterStatus == value;
    return FilterChip(
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      selected: isSelected,
      onSelected: (selected) => setState(() => _filterStatus = value),
      selectedColor: Colors.blue.shade100,
      checkmarkColor: Colors.blue.shade700,
    );
  }

  Widget _buildQuickStats() {
    return Consumer(
      builder: (context, ref, _) {
        final debtsAsync = ref.watch(debtsListProvider);

        return debtsAsync.when(
          loading: () => const SizedBox(),
          error: (_, __) => const SizedBox(),
          data: (debts) {
            final totalDebts = debts.length;
            final pendingDebts = debts.where((d) => d.isSettled == 0).length;
            final totalAmount = debts.fold(
              0.0,
              (sum, debt) => sum + debt.remainingAmount,
            );

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'إجمالي الديون',
                      totalDebts.toString(),
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatCard(
                      'معلق',
                      pendingDebts.toString(),
                      Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatCard(
                      'القيمة الإجمالية',
                      CurrencyFormatter.formatAmount(totalAmount),
                      Colors.red,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.8)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDebtsList(List<Debt> allDebts) {
    // تطبيق البحث والتصفية
    final filteredDebts = allDebts.where((debt) {
      // البحث
      final matchesSearch =
          _searchQuery.isEmpty ||
          debt.guestName.toLowerCase().contains(_searchQuery.toLowerCase());

      // التصفية حسب الحالة
      bool matchesFilter = true;
      switch (_filterStatus) {
        case 'pending':
          matchesFilter = debt.isSettled == 0 && debt.remainingAmount > 0;
        case 'settled':
          matchesFilter = debt.isSettled == 1 || debt.remainingAmount <= 0;
        case 'overdue':
          // الديون المتأخرة (أكثر من 30 يوم)
          final debtDateStr = debt.dateRecorded.isNotEmpty
              ? debt.dateRecorded
              : debt.checkoutDate;
          final debtDate = DateTime.tryParse(debtDateStr);
          if (debtDate != null) {
            final daysPassed = DateTime.now().difference(debtDate).inDays;
            matchesFilter =
                daysPassed > 30 &&
                debt.isSettled == 0 &&
                debt.remainingAmount > 0;
          } else {
            matchesFilter = false;
          }
      }

      return matchesSearch && matchesFilter;
    }).toList();

    // ترتيب الديون: غير المسددة أولاً، ثم حسب التاريخ
    filteredDebts.sort((a, b) {
      // الديون غير المسددة أولاً
      if (a.isSettled != b.isSettled) {
        return a.isSettled.compareTo(b.isSettled);
      }
      // ثم حسب تاريخ الخروج (الأحدث أولاً)
      return b.checkoutDate.compareTo(a.checkoutDate);
    });

    if (filteredDebts.isEmpty) {
      String emptyMessage = 'لا توجد ديون';
      if (_searchQuery.isNotEmpty) {
        emptyMessage = 'لا توجد نتائج للبحث "$_searchQuery"';
      } else if (_filterStatus != 'all') {
        emptyMessage = 'لا توجد ديون في هذه الفئة';
      }

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.account_balance_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: const TextStyle(
                fontSize: 18,
                color: Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'اضغط على + لإضافة دين جديد',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(debtsListProvider);
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: filteredDebts.length,
        itemBuilder: (context, index) {
          final debt = filteredDebts[index];
          return RepaintBoundary(
            child: _buildDebtCard(debt),
          );
        },
      ),
    );
  }

  Widget _buildDebtCard(Debt debt) {
    final isSettled = debt.isSettled == 1 || debt.remainingAmount <= 0;
    final debtDate = DateTime.tryParse(
      debt.dateRecorded.isNotEmpty ? debt.dateRecorded : debt.checkoutDate,
    );
    final daysPassed = debtDate != null
        ? DateTime.now().difference(debtDate).inDays
        : 0;
    final isOverdue = daysPassed > 30 && !isSettled;

    Color cardColor = Colors.white;
    Color borderColor = Colors.grey.shade300;

    if (isSettled) {
      cardColor = Colors.green.shade50;
      borderColor = Colors.green.shade300;
    } else if (isOverdue) {
      cardColor = Colors.red.shade50;
      borderColor = Colors.red.shade300;
    } else if (!isSettled) {
      cardColor = Colors.orange.shade50;
      borderColor = Colors.orange.shade300;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // الرأس
            Row(
              children: [
                Expanded(
                  child: Text(
                    debt.guestName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _buildStatusBadge(debt),
              ],
            ),

            const SizedBox(height: 8),

            // التواريخ والسبب
            Row(
              children: [
                Expanded(
                  child: _buildInfoRow(
                    Icons.login,
                    'الدخول',
                    _formatDate(debt.checkinDate),
                  ),
                ),
                Expanded(
                  child: _buildInfoRow(
                    Icons.logout,
                    'الخروج',
                    _formatDate(debt.checkoutDate),
                  ),
                ),
              ],
            ),

            if (debt.debtReason.isNotEmpty) ...[
              const SizedBox(height: 4),
              _buildInfoRow(Icons.info, 'السبب', debt.debtReason),
            ],

            const Divider(height: 20),

            // المبالغ
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إجمالي المبلغ',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        CurrencyFormatter.formatAmount(debt.totalAmount),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'المدفوع',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        CurrencyFormatter.formatAmount(debt.paidAmount),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'المتبقي',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        CurrencyFormatter.formatAmount(debt.remainingAmount),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // الرهن إذا كان موجود
            if (debt.pledge?.isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.security, size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'رهن: ${debt.pledge}',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (debt.pledgeType?.isNotEmpty ?? false)
                      Text(
                        ' (${debt.pledgeType})',
                        style: TextStyle(
                          color: Colors.blue.shade600,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
            ],

            // الملاحظة إذا كانت موجودة
            if (debt.note?.isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text(
                  debt.note!,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 12),

            // أزرار الإجراءات
            Row(
              children: [
                if (!isSettled) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _markAsSettled(debt),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('تم السداد'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isSendingWhatsApp
                        ? null
                        : () => _sendDebtWhatsApp(debt),
                    icon: const Icon(Icons.chat, size: 16, color: Colors.green),
                    label: const Text(
                      'واتساب',
                      style: TextStyle(color: Colors.green),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green,
                      side: const BorderSide(color: Colors.green),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openDebtForm(context, existing: debt),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('تعديل'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _deleteDebt(context, debt),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                  child: const Icon(Icons.delete, size: 16),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(Debt debt) {
    final isSettled = debt.isSettled == 1 || debt.remainingAmount <= 0;
    final debtDateStr = debt.dateRecorded.isNotEmpty
        ? debt.dateRecorded
        : debt.checkoutDate;
    final debtDate = DateTime.tryParse(debtDateStr);
    final daysPassed = debtDate != null
        ? DateTime.now().difference(debtDate).inDays
        : 0;
    final isOverdue = daysPassed > 30 && !isSettled && debt.remainingAmount > 0;

    String text;
    Color color;

    if (isSettled) {
      text = 'مسدد';
      color = Colors.green;
    } else if (isOverdue) {
      text = 'متأخر ($daysPassed يوم)';
      color = Colors.red;
    } else if (debt.remainingAmount > 0) {
      text = 'معلق';
      color = Colors.orange;
    } else {
      text = 'مسدد';
      color = Colors.green;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  void _showQuickAddMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'إضافة دين جديد',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.hotel_outlined, color: Colors.blue),
              title: const Text('دين من حجز موجود'),
              subtitle: const Text(
                'اختر حجز وأنشئ دين بناء على الأيام المتبقية',
              ),
              onTap: () {
                Navigator.pop(context);
                _createDebtFromBooking();
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.add_circle_outline,
                color: Colors.green,
              ),
              title: const Text('دين يدوي'),
              subtitle: const Text('أدخل تفاصيل الدين يدوياً'),
              onTap: () {
                Navigator.pop(context);
                _openDebtForm(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createDebtFromBooking() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (context) => const CreateDebtFromBookingScreen(),
      ),
    );

    // إذا تم إنشاء دين بنجاح، قم بتحديث البيانات
    if (result ?? false) {
      ref.invalidate(debtsListProvider);
    }
  }

  String _formatDate(String value) {
    return Time.safeIsoToDateString(value);
  }

  Future<void> _markAsSettled(Debt debt) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد السداد'),
        content: Text('هل تريد تسجيل دين "${debt.guestName}" كمسدد؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop<bool>(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop<bool>(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('تأكيد السداد'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      try {
        final repo = ref.read(debtsRepoProvider);
        await repo.update(
          id: debt.id,
          isSettled: 1,
          paidAmount: debt.totalAmount,
          remainingAmount: 0,
          paymentDate: Time.nowDateString(),
        );
        markDataChanged();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تم تسجيل سداد دين ${debt.guestName}')),
          );
        }
      } catch (e) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تسجيل السداد: $e'),
            backgroundColor: Colors.red.shade900,
          ),
        );
      }
    }
  }

  Future<void> _openDebtForm(BuildContext context, {Debt? existing}) async {
    final guestNameCtrl = TextEditingController(
      text: existing?.guestName ?? '',
    );
    final checkinCtrl = TextEditingController(
      text: Time.safeIsoToDateString(existing?.checkinDate),
    );
    final checkoutCtrl = TextEditingController(
      text: Time.safeIsoToDateString(existing?.checkoutDate),
    );
    final totalCtrl = TextEditingController(
      text: existing != null
          ? CurrencyFormatter.formatAmount(existing.totalAmount)
          : '0',
    );
    final paidCtrl = TextEditingController(
      text: existing != null
          ? CurrencyFormatter.formatAmount(existing.paidAmount)
          : '0',
    );
    final remainingCtrl = TextEditingController(
      text: existing != null
          ? CurrencyFormatter.formatAmount(existing.remainingAmount)
          : '0',
    );
    final debtReasonCtrl = TextEditingController(
      text: existing?.debtReason ?? 'عدم سداد قيمة أيام إضافية',
    );
    final pledgeCtrl = TextEditingController(text: existing?.pledge ?? '');
    final pledgeTypeCtrl = TextEditingController(
      text: existing?.pledgeType ?? '',
    );
    final noteCtrl = TextEditingController(text: existing?.note ?? '');
    const titleStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.bold);
    const labelStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.bold);
    const fieldStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.bold);

    Future<void> pickDate(
      BuildContext pickerContext,
      TextEditingController controller,
    ) async {
      final initial = DateTime.tryParse(controller.text) ?? DateTime.now();
      final picked = await showDatePicker(
        context: pickerContext,
        initialDate: initial,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      if (picked != null) {
        controller.text = Time.safeIsoToDateString(picked.toIso8601String());
      }
    }

    void recalculate() {
      final total = CurrencyFormatter.parseAmount(totalCtrl.text) ?? 0;
      final paid = CurrencyFormatter.parseAmount(paidCtrl.text) ?? 0;
      final remaining = (total - paid).clamp(0.0, double.infinity);
      remainingCtrl.text = CurrencyFormatter.formatAmount(remaining);
    }

    totalCtrl.addListener(recalculate);
    paidCtrl.addListener(recalculate);
    recalculate();

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: Text(
                existing == null ? 'إضافة دين جديد' : 'تعديل الدين',
                style: titleStyle,
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: guestNameCtrl,
                        style: fieldStyle,
                        decoration: const InputDecoration(
                          labelText: 'اسم النزيل*',
                          labelStyle: labelStyle,
                          floatingLabelStyle: labelStyle,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: checkinCtrl,
                              readOnly: true,
                              onTap: () => pickDate(dialogContext, checkinCtrl),
                              style: fieldStyle,
                              decoration: const InputDecoration(
                                labelText: 'تاريخ الدخول',
                                labelStyle: labelStyle,
                                floatingLabelStyle: labelStyle,
                                border: OutlineInputBorder(),
                                suffixIcon: Icon(
                                  Icons.calendar_today,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: checkoutCtrl,
                              readOnly: true,
                              onTap: () =>
                                  pickDate(dialogContext, checkoutCtrl),
                              style: fieldStyle,
                              decoration: const InputDecoration(
                                labelText: 'تاريخ الخروج',
                                labelStyle: labelStyle,
                                floatingLabelStyle: labelStyle,
                                border: OutlineInputBorder(),
                                suffixIcon: Icon(
                                  Icons.calendar_today,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: debtReasonCtrl,
                        style: fieldStyle,
                        decoration: const InputDecoration(
                          labelText: 'سبب الدين',
                          labelStyle: labelStyle,
                          floatingLabelStyle: labelStyle,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: totalCtrl,
                              style: fieldStyle,
                              decoration: const InputDecoration(
                                labelText: 'إجمالي المبلغ*',
                                labelStyle: labelStyle,
                                floatingLabelStyle: labelStyle,
                                border: OutlineInputBorder(),
                                // suffixText: 'ر.س',
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: paidCtrl,
                              style: fieldStyle,
                              decoration: const InputDecoration(
                                labelText: 'المدفوع',
                                labelStyle: labelStyle,
                                floatingLabelStyle: labelStyle,
                                border: OutlineInputBorder(),
                                // suffixText: 'ر.س',
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: remainingCtrl,
                        readOnly: true,
                        style: fieldStyle,
                        decoration: const InputDecoration(
                          labelText: 'المتبقي',
                          labelStyle: labelStyle,
                          floatingLabelStyle: labelStyle,
                          border: OutlineInputBorder(),
                          // suffixText: 'ر.س',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: pledgeCtrl,
                              style: fieldStyle,
                              decoration: const InputDecoration(
                                labelText: 'الرهن',
                                labelStyle: labelStyle,
                                floatingLabelStyle: labelStyle,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: pledgeTypeCtrl,
                              style: fieldStyle,
                              decoration: const InputDecoration(
                                labelText: 'نوع الرهن',
                                labelStyle: labelStyle,
                                floatingLabelStyle: labelStyle,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: noteCtrl,
                        style: fieldStyle,
                        decoration: const InputDecoration(
                          labelText: 'ملاحظة إضافية',
                          labelStyle: labelStyle,
                          floatingLabelStyle: labelStyle,
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  // ✅ إصلاح: التحقق من صحة البيانات قبل إغلاق الحوار
                  // سابقاً كان التحقق بعد الإغلاق مما يسبب فقدان البيانات المدخلة
                  onPressed: () {
                    final guestName = guestNameCtrl.text.trim();
                    if (guestName.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('يرجى إدخال اسم النزيل')),
                      );
                      return;
                    }
                    final totalAmount = CurrencyFormatter.parseAmount(totalCtrl.text) ?? 0;
                    if (totalAmount <= 0) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('يجب إدخال مبلغ الدين الكلي أكبر من صفر')),
                      );
                      return;
                    }
                    Navigator.pop(dialogContext, true);
                  },
                  child: Text(existing == null ? 'إضافة الدين' : 'تحديث الدين'),
                ),
              ],
            ),
          );
        },
      );

      if (confirmed != true) {
        return;
      }

      // ✅ التحقق من اسم النزيل والمبلغ أصبح داخل الحوار الآن
      // لا حاجة لإعادة التحقق هنا
      final guestName = guestNameCtrl.text.trim();

      final checkinDate = checkinCtrl.text.trim().isEmpty
          ? Time.nowDateString()
          : checkinCtrl.text.trim();
      final checkoutDate = checkoutCtrl.text.trim().isEmpty
          ? Time.nowDateString()
          : checkoutCtrl.text.trim();
      final totalAmount = CurrencyFormatter.parseAmount(totalCtrl.text) ?? 0;
      final paidAmount = CurrencyFormatter.parseAmount(paidCtrl.text) ?? 0;
      final debtReason = debtReasonCtrl.text.trim();
      final pledge = pledgeCtrl.text.trim().isEmpty
          ? null
          : pledgeCtrl.text.trim();
      final pledgeType = pledgeTypeCtrl.text.trim().isEmpty
          ? null
          : pledgeTypeCtrl.text.trim();
      final note = noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim();

      final repo = ref.read(debtsRepoProvider);
      if (existing == null) {
        await repo.create(
          guestName: guestName,
          checkinDate: checkinDate,
          checkoutDate: checkoutDate,
          dateRecorded: Time.nowDateString(),
          debtReason: debtReason,
          totalAmount: totalAmount,
          paidAmount: paidAmount,
          paymentDate: Time.nowDateString(),
          pledge: pledge,
          pledgeType: pledgeType,
          note: note,
        );
      } else {
        await repo.update(
          id: existing.id,
          guestName: guestName,
          checkinDate: checkinDate,
          checkoutDate: checkoutDate,
          debtReason: debtReason,
          totalAmount: totalAmount,
          paidAmount: paidAmount,
          paymentDate: Time.nowDateString(),
          pledge: pledge,
          pledgeType: pledgeType,
          note: note,
        );
      }
      markDataChanged();

      if (mounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              existing == null
                  ? 'تم إضافة الدين بنجاح'
                  : 'تم تحديث الدين بنجاح',
            ),
          ),
        );
      }
    } finally {
      totalCtrl.removeListener(recalculate);
      paidCtrl.removeListener(recalculate);
      guestNameCtrl.dispose();
      checkinCtrl.dispose();
      checkoutCtrl.dispose();
      totalCtrl.dispose();
      paidCtrl.dispose();
      remainingCtrl.dispose();
      debtReasonCtrl.dispose();
      pledgeCtrl.dispose();
      pledgeTypeCtrl.dispose();
      noteCtrl.dispose();
    }
  }

  /// إرسال تنبيه واتساب لدين
  Future<void> _sendDebtWhatsApp(Debt debt) async {
    // البحث عن رقم هاتف النزيل من الحجوزات
    String phone = '';
    try {
      final bookingsAsync = ref.read(bookingsListProvider);
      final bookings = bookingsAsync.valueOrNull ?? [];
      final booking = bookings.cast<Booking?>().firstWhere(
        (b) => b?.id == debt.bookingLocalId,
        orElse: () => null,
      );
      if (booking != null) {
        phone = booking.guestPhone;
      }
    } catch (_) {}

    if (phone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا يوجد رقم هاتف لهذا النزيل'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final cleanedPhone = _cleanAndFormatPhone(phone);
    if (cleanedPhone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('رقم الهاتف غير صالح'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() => _isSendingWhatsApp = true);

    try {
      final whatsappService = ref.read(whatsappServiceProvider);

      final debtDate = DateTime.tryParse(
        debt.dateRecorded.isNotEmpty ? debt.dateRecorded : debt.checkoutDate,
      );
      final daysPassed = debtDate != null
          ? DateTime.now().difference(debtDate).inDays
          : 0;

      final message = StringBuffer()
        ..writeln('عزيزي ${debt.guestName}')
        ..writeln()
        ..writeln('تذكير بالمبلغ المتبقي عليكم')
        ..writeln(
            'إجمالي المبلغ: ${CurrencyFormatter.formatAmount(debt.totalAmount)}',)
        ..writeln(
            'المدفوع: ${CurrencyFormatter.formatAmount(debt.paidAmount)}',)
        ..writeln(
            'المتبقي: ${CurrencyFormatter.formatAmount(debt.remainingAmount)}',);

      if (debt.debtReason.isNotEmpty) {
        message.writeln('السبب: ${debt.debtReason}');
      }
      if (daysPassed > 0) {
        message.writeln('مرت: $daysPassed يوم');
      }

      message
        ..writeln()
        ..writeln('نرجو منكم تسديد المبلغ المتبقي')
        ..writeln()
        ..writeln('شكراً لتعاونكم')
        ..writeln('فندق مارينا')
        ..write('للاستفسار: 9677734587456');

      final result = await whatsappService.sendMessage(
        phoneE164: cleanedPhone,
        message: message.toString(),
      );

      if (mounted) {
        setState(() => _isSendingWhatsApp = false);
        if (result.quotaMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.quotaMessage!),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.success
                  ? 'تم إرسال تنبيه واتساب لـ ${debt.guestName}'
                  : 'تعذّر إرسال واتساب لـ ${debt.guestName}',),
              backgroundColor: result.success ? Colors.green : Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSendingWhatsApp = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteDebt(BuildContext context, Debt debt) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: Text(
            'هل أنت متأكد من حذف دين "${debt.guestName}"؟\n\nهذا الإجراء لا يمكن التراجع عنه.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('حذف'),
            ),
          ],
        );
      },
    );

    if (confirm != true) {
      return;
    }

    try {
      final repo = ref.read(debtsRepoProvider);
      await repo.delete(debt.id);
      markDataChanged();

      if (mounted) {
        ScaffoldMessenger.of(
          // ignore: use_build_context_synchronously
          context,
        ).showSnackBar(SnackBar(content: Text('تم حذف دين ${debt.guestName}')));
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل حذف الدين: $e'),
          backgroundColor: Colors.red.shade900,
        ),
      );
    }
  }
}
