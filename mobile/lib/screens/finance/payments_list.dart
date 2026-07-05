import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../mixins/sync_on_exit_mixin.dart';
import '../../providers/repository_providers.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/stream_helpers.dart';

class PaymentsListScreen extends ConsumerStatefulWidget {
  const PaymentsListScreen({super.key});

  @override
  ConsumerState<PaymentsListScreen> createState() => _PaymentsListScreenState();
}

class _PaymentsListScreenState extends ConsumerState<PaymentsListScreen>
    with SyncOnExitMixin {
  @override
  String get screenId => 'payments_list';

  String _searchQuery = '';
  String? _filterMethod;
  String? _filterType;
  String _sortOrder = 'desc';

  final List<String> _methods = ['نقدي', 'تحويل', 'بطاقة', 'شيك', 'تقسيط'];
  final List<MapEntry<String, String>> _types = const [
    MapEntry('room', 'غرفة'),
    MapEntry('service', 'خدمات'),
    MapEntry('deposit', 'عربون'),
    MapEntry('other', 'أخرى'),
  ];

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(paymentsRepoProvider);

    return wrapWithSyncOnExit(
      child: AppScaffold(
        title: 'المدفوعات',
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'sort_asc':
                  setState(() => _sortOrder = 'asc');
                case 'sort_desc':
                  setState(() => _sortOrder = 'desc');
                case 'clear':
                  setState(() {
                    _searchQuery = '';
                    _filterMethod = null;
                    _filterType = null;
                    _sortOrder = 'desc';
                  });
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'sort_desc',
                child: Row(
                  children: [
                    Icon(Icons.arrow_downward,
                        color: _sortOrder == 'desc'
                            ? Colors.amber.shade700
                            : Colors.grey,),
                    const SizedBox(width: 8),
                    const Text('الأحدث أولاً'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'sort_asc',
                child: Row(
                  children: [
                    Icon(Icons.arrow_upward,
                        color: _sortOrder == 'asc'
                            ? Colors.amber.shade700
                            : Colors.grey,),
                    const SizedBox(width: 8),
                    const Text('الأقدم أولاً'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.clear_all, color: Colors.red),
                    SizedBox(width: 8),
                    Text('مسح الفلاتر', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
        body: Column(
          children: [
            // ─── شريط البحث ───
            _buildSearchBar(),
            // ─── فلاتر سريعة ───
            _buildFilterChips(),
            // ─── قائمة المدفوعات ───
            Expanded(
              child: StreamBuilder(
                stream: debounceStream(repo.watchAll(), const Duration(milliseconds: 150)),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFFFCC80),
                      ),
                    );
                  }

                  final payments = snapshot.data ?? [];

                  // تطبيق الفلاتر
                  final filtered = _applyFilters(payments);

                  if (payments.isEmpty) {
                    return _buildEmptyState(
                      icon: Icons.payment_outlined,
                      title: 'لا توجد مدفوعات',
                      subtitle: 'لم يتم تسجيل أي دفعات بعد',
                    );
                  }

                  if (filtered.isEmpty) {
                    return _buildEmptyState(
                      icon: Icons.filter_list_off,
                      title: 'لا توجد نتائج',
                      subtitle: 'لا توجد مدفوعات تطابق البحث أو الفلاتر',
                    );
                  }

                  return RefreshIndicator(
                    color: const Color(0xFFFFCC80),
                    onRefresh: () async {
                      setState(() {});
                    },
                    child: Column(
                      children: [
                        // ─── شريط الإحصائيات ───
                        _buildStatsBar(filtered),
                        // ─── عداد النتائج ───
                        _buildResultsCount(filtered),
                        const Divider(height: 1),
                        // ─── القائمة ───
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.only(
                              top: 8,
                              right: 12,
                              left: 12,
                              bottom: 80,
                            ),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              return RepaintBoundary(
                                child: _buildPaymentCard(filtered[index]),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  شريط البحث
  // ═══════════════════════════════════════════

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: TextField(
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: 'بحث بالاسم، المبلغ، رقم الغرفة...',
          hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          prefixIcon: Icon(Icons.search, color: Colors.grey.shade500, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: Colors.grey.shade500, size: 18),
                  onPressed: () => setState(() => _searchQuery = ''),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  فلاتر سريعة
  // ═══════════════════════════════════════════

  Widget _buildFilterChips() {
    return Container(
      height: 44,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // فلتر طريقة الدفع
          ..._methods.map((method) {
            final isSelected = _filterMethod == method;
            return Padding(
              padding: const EdgeInsets.only(left: 6),
              child: FilterChip(
                avatar: Icon(
                  _getMethodIcon(method),
                  size: 14,
                  color: isSelected ? Colors.white : _getMethodColor(method),
                ),
                label: Text(
                  method,
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected ? Colors.white : _getMethodColor(method),
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                selected: isSelected,
                selectedColor: _getMethodColor(method),
                backgroundColor: Colors.white,
                side: BorderSide(
                  color: isSelected
                      ? _getMethodColor(method)
                      : Colors.grey.shade300,
                ),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onSelected: (_) {
                  setState(() {
                    _filterMethod = isSelected ? null : method;
                  });
                },
              ),
            );
          }),
          // فاصل
          if (_methods.isNotEmpty) const SizedBox(width: 4),
          // فلاتر نوع الإيراد
          ..._types.map((entry) {
            final isSelected = _filterType == entry.key;
            return Padding(
              padding: const EdgeInsets.only(left: 6),
              child: FilterChip(
                label: Text(
                  entry.value,
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected
                        ? Colors.white
                        : Colors.amber.shade700,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                selected: isSelected,
                selectedColor: const Color(0xFFFFCC80),
                backgroundColor: Colors.white,
                side: BorderSide(
                  color: isSelected
                      ? const Color(0xFFFFCC80)
                      : Colors.grey.shade300,
                ),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onSelected: (_) {
                  setState(() {
                    _filterType = isSelected ? null : entry.key;
                  });
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  شريط الإحصائيات
  // ═══════════════════════════════════════════

  Widget _buildStatsBar(List<dynamic> payments) {
    final total = payments.fold<double>(0, (s, p) => s + (p.amount as num).toDouble());
    final now = DateTime.now();
    final today = payments.where((p) {
      try {
        final d = DateTime.parse(p.paymentDate as String);
        return d.year == now.year && d.month == now.month && d.day == now.day;
      } catch (_) {
        return false;
      }
    });
    final todayTotal = today.fold<double>(0, (s, p) => s + (p.amount as num).toDouble());
    final cashTotal = payments
        .where((p) => p.paymentMethod == 'نقدي')
        .fold<double>(0, (s, p) => s + (p.amount as num).toDouble());
    final transferTotal = payments
        .where((p) => p.paymentMethod == 'تحويل')
        .fold<double>(0, (s, p) => s + (p.amount as num).toDouble());

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFCC80), Color(0xFFFFB74D)],
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFB74D).withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem('إجمالي', total, Colors.white),
          _statItem('اليوم', todayTotal, Colors.white70),
          _statItem('نقدي', cashTotal, Colors.white),
          _statItem('تحويل', transferTotal, Colors.white70),
        ],
      ),
    );
  }

  Widget _statItem(String label, double amount, Color valueColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          CurrencyFormatter.formatAmount(amount),
          style: TextStyle(
            color: valueColor,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: valueColor.withValues(alpha: 0.8),
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════
  //  عداد النتائج
  // ═══════════════════════════════════════════

  Widget _buildResultsCount(List<dynamic> payments) {
    final hasFilters = _filterMethod != null || _filterType != null || _searchQuery.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$payments دفعة',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (hasFilters)
            Text(
              'نتائج مفلترة',
              style: TextStyle(
                fontSize: 11,
                color: Colors.amber.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  بطاقة الدفعة
  // ═══════════════════════════════════════════

  Widget _buildPaymentCard(dynamic payment) {
    final methodColor = _getMethodColor(payment.paymentMethod as String);
    final methodIcon = _getMethodIcon(payment.paymentMethod as String);
    final revenueLabel = _getRevenueLabel(payment.revenueType as String);
    final formattedDate = _formatDate(payment.paymentDate as String);
    final isToday = _isToday(payment.paymentDate as String);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200, width: 0.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showPaymentDetails(payment),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // أيقونة طريقة الدفع
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: methodColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(methodIcon, color: methodColor, size: 20),
              ),
              const SizedBox(width: 12),
              // التفاصيل
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // الصف الأول: المبلغ + نوع الإيراد
                    Row(
                      children: [
                        Text(
                          CurrencyFormatter.formatAmount((payment.amount as num).toDouble()),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2,),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFCC80).withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            revenueLabel,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.amber.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isToday) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1,),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'اليوم',
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    // الصف الثاني: طريقة الدفع + التاريخ
                    Row(
                      children: [
                        Icon(Icons.payment, size: 13, color: Colors.grey.shade500),
                        const SizedBox(width: 3),
                        Text(
                          payment.paymentMethod as String,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(Icons.calendar_today,
                            size: 12, color: Colors.grey.shade400,),
                        const SizedBox(width: 3),
                        Text(
                          formattedDate,
                          style: TextStyle(
                            fontSize: 11,
                            color: isToday ? Colors.green.shade600 : Colors.grey.shade500,
                            fontWeight: isToday ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    // الصف الثالث: ملاحظات
                    if (payment.notes != null &&
                        (payment.notes as String).trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.notes,
                              size: 12, color: Colors.grey.shade400,),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              payment.notes as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade500,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // رقم الغرفة
              if (payment.roomNumber != null &&
                  (payment.roomNumber as String).trim().isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.hotel,
                          size: 12, color: Colors.blue.shade400,),
                      const SizedBox(height: 1),
                      Text(
                        payment.roomNumber as String,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              // سهم التنقل
              if (payment.roomNumber == null ||
                  (payment.roomNumber as String).trim().isEmpty)
                Icon(Icons.chevron_left, color: Colors.grey.shade400, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  حوار تفاصيل الدفعة
  // ═══════════════════════════════════════════

  void _showPaymentDetails(dynamic payment) {
    final methodColor = _getMethodColor(payment.paymentMethod as String);
    final revenueLabel = _getRevenueLabel(payment.revenueType as String);
    final formattedDate = _formatDate(payment.paymentDate as String);
    final isToday = _isToday(payment.paymentDate as String);

    showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: methodColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getMethodIcon(payment.paymentMethod as String),
                  color: methodColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Text('تفاصيل الدفعة'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailDivider('المبلغ', CurrencyFormatter.formatAmount((payment.amount as num).toDouble()),
                  icon: Icons.payments_outlined, color: Colors.green,),
              _detailDivider('طريقة الدفع', payment.paymentMethod as String,
                  icon: _getMethodIcon(payment.paymentMethod as String),
                  color: methodColor,),
              _detailDivider('نوع الإيراد', revenueLabel,
                  icon: Icons.category, color: Colors.amber.shade700,),
              _detailDivider('التاريخ', isToday ? '$formattedDate (اليوم)' : formattedDate,
                  icon: Icons.event, color: isToday ? Colors.green : Colors.blue,),
              if (payment.roomNumber != null &&
                  (payment.roomNumber as String).trim().isNotEmpty)
                _detailDivider('رقم الغرفة', payment.roomNumber as String,
                    icon: Icons.hotel, color: Colors.indigo,),
              if (payment.referenceNumber != null &&
                  (payment.referenceNumber as String).trim().isNotEmpty)
                _detailDivider('رقم المرجع', payment.referenceNumber as String,
                    icon: Icons.numbers, color: Colors.purple,),
              if (payment.notes != null && (payment.notes as String).trim().isNotEmpty)
                _detailDivider('ملاحظات', payment.notes as String,
                    icon: Icons.notes, color: Colors.grey,),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailDivider(String label, String value,
      {required IconData icon, required Color color,}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  حالة فارغة
  // ═══════════════════════════════════════════

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 40, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  فلاتر وترتيب
  // ═══════════════════════════════════════════

  List<dynamic> _applyFilters(List<dynamic> payments) {
    final result = payments.where((p) {
      // فلتر البحث
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final amountMatch =
            CurrencyFormatter.formatAmount((p.amount as num).toDouble()).contains(q);
        final methodMatch = (p.paymentMethod as String).toLowerCase().contains(q);
        final roomMatch = ((p.roomNumber as String?) ?? '').toLowerCase().contains(q);
        final notesMatch = ((p.notes as String?) ?? '').toLowerCase().contains(q);
        if (!amountMatch && !methodMatch && !roomMatch && !notesMatch) {
          return false;
        }
      }
      // فلتر طريقة الدفع
      if (_filterMethod != null && (p.paymentMethod as String) != _filterMethod) {
        return false;
      }
      // فلتر نوع الإيراد
      if (_filterType != null && (p.revenueType as String) != _filterType) {
        return false;
      }
      return true;
    }).toList();

    // ترتيب حسب التاريخ
    result.sort((a, b) {
      try {
        final dateA = DateTime.parse(a.paymentDate as String);
        final dateB = DateTime.parse(b.paymentDate as String);
        return _sortOrder == 'desc'
            ? dateB.compareTo(dateA)
            : dateA.compareTo(dateB);
      } catch (_) {
        return 0;
      }
    });

    return result;
  }

  // ═══════════════════════════════════════════
  //  مساعدات
  // ═══════════════════════════════════════════

  Color _getMethodColor(String method) {
    switch (method) {
      case 'نقدي':
        return Colors.green;
      case 'بطاقة':
        return Colors.blue;
      case 'تحويل':
        return Colors.orange;
      case 'شيك':
        return Colors.purple;
      case 'تقسيط':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }

  IconData _getMethodIcon(String method) {
    switch (method) {
      case 'نقدي':
        return Icons.money;
      case 'بطاقة':
        return Icons.credit_card;
      case 'تحويل':
        return Icons.account_balance;
      case 'شيك':
        return Icons.receipt_long;
      case 'تقسيط':
        return Icons.calendar_view_month;
      default:
        return Icons.payment;
    }
  }

  String _getRevenueLabel(String type) {
    switch (type) {
      case 'room':
        return 'غرفة';
      case 'service':
        return 'خدمات';
      case 'deposit':
        return 'عربون';
      case 'other':
        return 'أخرى';
      default:
        return type;
    }
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }

  bool _isToday(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      return date.year == now.year && date.month == now.month && date.day == now.day;
    } catch (_) {
      return false;
    }
  }
}
