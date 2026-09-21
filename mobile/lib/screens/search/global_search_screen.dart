import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../components/app_scaffold.dart';
import '../../components/widgets/empty_state.dart';
import '../../providers/auth_provider.dart';
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart';
import '../../services/repositories/blacklist_repository.dart';
import '../../services/search/global_search_service.dart';
import '../../utils/hotel_time_engine.dart';

/// ✅ (2026-09-22) شاشة البحث الشامل — واجهة فوق [GlobalSearchService].
///
/// العقد:
/// - debounce 300ms وحد أدنى حرفان — لا استعلام لكل ضغطة.
/// - النتائج مجمعة بالكيان مع الإجمالي الصادق (قد يتجاوز المعروض).
/// - رقائق تصفية بالكيان (تُبنى من صلاحيات المستخدم — النوع غير
///   المسموح لا يظهر أصلاً) + نطاق زمني اختياري (الكل افتراضياً).
/// - لوحة تفصيل للسجل عند النقر — بحثٌ للقراءة والسياق، التعديل في
///   شاشاته الأصلية.
/// - للمدير: مفتاحا إظهار المحذوف والملغاة/المعلقة (تدقيق).
class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

enum _DateMode { all, today, week, month, custom }

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  static const _minQueryLength = 2;
  static const _debounce = Duration(milliseconds: 300);

  final _controller = TextEditingController();
  final _currencyFmt = NumberFormat('#,##0', 'en_US');

  Timer? _debounceTimer;
  GlobalSearchResults? _results;
  bool _searching = false;

  late GlobalSearchService _service;
  Set<SearchEntityKind> _selectedKinds = {};
  _DateMode _dateMode = _DateMode.all;
  String? _customFromDay;
  String? _customToDay;
  bool _includeDeleted = false;
  bool _includeInactivePayments = false;

  bool get _isAdmin {
    final user = ref.read(authProvider).currentUser;
    return user?.isAdmin ?? false;
  }

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).currentUser;
    _service = GlobalSearchService(
      ref.read(databaseProvider),
      // المدير (أو صلاحية all) يرى كل الأنواع — غيره بأنواعه المسموحة
      allowedPermissionKeys: (user == null || user.isAdmin)
          ? null
          : user.permissions.toSet(),
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, _runSearch);
  }

  Future<void> _runSearch() async {
    final text = _controller.text.trim();
    if (text.length < _minQueryLength) {
      if (mounted) {
        setState(() {
          _results = null;
          _searching = false;
        });
      }
      return;
    }
    final (fromDay, toDay) = _currentDayRange();
    setState(() => _searching = true);
    try {
      final results = await _service.search(
        GlobalSearchQuery(
          text: text,
          fromDay: fromDay,
          toDay: toDay,
          includeDeleted: _includeDeleted,
          includeInactivePayments: _includeInactivePayments,
          kinds: _selectedKinds.isEmpty ? null : _selectedKinds,
        ),
      );
      if (mounted) {
        setState(() {
          _results = results;
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _searching = false);
      }
    }
  }

  (String?, String?) _currentDayRange() {
    final today = HotelTimeEngine.getHotelDayKey();
    switch (_dateMode) {
      case _DateMode.all:
        return (null, null);
      case _DateMode.today:
        return (today, today);
      case _DateMode.week:
        final sixDaysAgo = DateTime.now().subtract(const Duration(days: 6));
        final from = HotelTimeEngine.getHotelDayKey(
          dateTime: DateTime(
            sixDaysAgo.year,
            sixDaysAgo.month,
            sixDaysAgo.day,
            14,
            1,
          ),
        );
        return (from, today);
      case _DateMode.month:
        final now = DateTime.now();
        final from = DateTime(now.year, now.month, 1, 14, 1);
        return (HotelTimeEngine.getHotelDayKey(dateTime: from), today);
      case _DateMode.custom:
        return (_customFromDay, _customToDay);
    }
  }

  String get _dateModeLabel {
    switch (_dateMode) {
      case _DateMode.all:
        return 'كل الفترات';
      case _DateMode.today:
        return 'اليوم';
      case _DateMode.week:
        return 'آخر 7 أيام';
      case _DateMode.month:
        return 'هذا الشهر';
      case _DateMode.custom:
        return '${_customFromDay ?? '؟'} → ${_customToDay ?? '؟'}';
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(
        start: now.subtract(const Duration(days: 30)),
        end: now,
      ),
      helpText: 'نطاق البحث',
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _dateMode = _DateMode.custom;
      _customFromDay = _dayKey(picked.start);
      _customToDay = _dayKey(picked.end);
    });
    unawaited(_runSearch());
  }

  static String _dayKey(DateTime d) {
    final iso = d.toIso8601String();
    return iso.substring(0, 10);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'البحث الشامل',
      actions: [
        if (_isAdmin)
          PopupMenuButton<_AdminToggle>(
            icon: const Icon(Icons.tune),
            tooltip: 'خيارات المدير',
            onSelected: (item) {
              setState(() => item.apply(this));
              unawaited(_runSearch());
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: _AdminToggle.includeDeleted,
                checked: _includeDeleted,
                child: const Text('إظهار المحذوف'),
              ),
              CheckedPopupMenuItem(
                value: _AdminToggle.includeInactivePayments,
                checked: _includeInactivePayments,
                child: const Text('إظهار الملغاة والمعلقة'),
              ),
            ],
          ),
      ],
      body: Column(
        children: [
          _buildSearchField(),
          _buildDateChips(),
          _buildKindChips(),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _runSearch(),
        onChanged: _onQueryChanged,
        decoration: InputDecoration(
          hintText: 'ابحث في كل البيانات: اسم، غرفة، رقم هوية، مبلغ…',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searching
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : (_controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _results = null);
                        },
                      )),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildDateChips() {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: [
          _dateChip(_DateMode.all, 'كل الفترات'),
          _dateChip(_DateMode.today, 'اليوم'),
          _dateChip(_DateMode.week, 'آخر 7 أيام'),
          _dateChip(_DateMode.month, 'هذا الشهر'),
          if (_dateMode == _DateMode.custom)
            _dateChip(_DateMode.custom, _dateModeLabel, locked: true),
          ActionChip(
            avatar: const Icon(Icons.date_range, size: 16),
            label: const Text('مخصص'),
            onPressed: _pickCustomRange,
          ),
        ],
      ),
    );
  }

  Widget _dateChip(_DateMode mode, String label, {bool locked = false}) {
    final selected = _dateMode == mode;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: locked
            ? null
            : (v) {
                if (!v && mode != _DateMode.all) {
                  setState(() => _dateMode = _DateMode.all);
                } else {
                  setState(() => _dateMode = mode);
                }
                unawaited(_runSearch());
              },
      ),
    );
  }

  Widget _buildKindChips() {
    final allowed = _service.allowedKinds;
    const order = SearchEntityKind.values;
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: FilterChip(
              label: const Text('الكل'),
              selected: _selectedKinds.isEmpty,
              onSelected: (_) {
                setState(() => _selectedKinds = {});
                unawaited(_runSearch());
              },
            ),
          ),
          for (final kind in order.where(allowed.contains))
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: FilterChip(
                label: Text(
                  '${kindLabel(kind)}'
                  '${_results != null && (_results!.totals[kind] ?? 0) > 0 ? ' (${_results!.totals[kind]})' : ''}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                selected: _selectedKinds.contains(kind),
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      _selectedKinds = {..._selectedKinds, kind};
                    } else {
                      _selectedKinds = _selectedKinds
                          .where((k) => k != kind)
                          .toSet();
                    }
                  });
                  unawaited(_runSearch());
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_controller.text.trim().length < _minQueryLength) {
      return const EmptyState(
        title: 'ابدأ البحث',
        message: 'اكتب حرفين على الأقل للبحث في كل بيانات النظام.',
        icon: Icons.manage_search,
      );
    }
    if (_searching && _results == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final results = _results;
    if (results == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (results.isEmpty) {
      return const EmptyState(
        title: 'لا توجد نتائج',
        message: 'لم يُعثر على مطابقات لهذا البحث ضمن النطاق المحدد.',
        icon: Icons.search_off,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: results.hits.length + 1,
      itemBuilder: (context, index) {
        if (index == results.hits.length) {
          return _buildFooterSummary(results);
        }
        final kind = results.hits.keys.elementAt(index);
        final hits = results.hits[kind]!;
        return _buildKindSection(
          kind,
          hits,
          results.totals[kind] ?? hits.length,
        );
      },
    );
  }

  Widget _buildKindSection(
    SearchEntityKind kind,
    List<GlobalSearchHit> hits,
    int total,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: kindColor(kind).withValues(alpha: 0.12),
                child: Icon(kindIcon(kind), size: 14, color: kindColor(kind)),
              ),
              const SizedBox(width: 8),
              Text(
                kindLabel(kind),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                hits.length < total ? '${hits.length} من $total' : '$total',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        for (final hit in hits)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            child: RepaintBoundary(child: _buildHitCard(hit)),
          ),
      ],
    );
  }

  Widget _buildHitCard(GlobalSearchHit hit) {
    final color = kindColor(hit.kind);
    return Card(
      elevation: 0.5,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showHitDetails(hit),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(kindIcon(hit.kind), size: 15, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      hit.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hit.amount != null)
                    Text(
                      _currencyFmt.format(hit.amount),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: hit.amount! < 0 ? Colors.red : Colors.green,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      [
                        if (hit.subtitle.isNotEmpty) hit.subtitle,
                        if (hit.dayKey != null) hit.dayKey!,
                      ].join(' • '),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (hit.matchedFields.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      for (final field in hit.matchedFields)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            field,
                            style: TextStyle(fontSize: 9, color: color),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooterSummary(GlobalSearchResults results) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Text(
          '${results.totalHits} نتيجة معروضة'
          '${results.elapsed.inMilliseconds > 0 ? ' في ${results.elapsed.inMilliseconds} م.ث' : ''}',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
        ),
      ),
    );
  }

  // ─────────────────────────── لوحة التفصيل ───────────────────────────

  Future<void> _showHitDetails(GlobalSearchHit hit) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final rows = _detailRowsFor(hit);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Row(
                  children: [
                    Icon(
                      kindIcon(hit.kind),
                      color: kindColor(hit.kind),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hit.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Text(
                      kindLabel(hit.kind),
                      style: TextStyle(
                        fontSize: 10,
                        color: kindColor(hit.kind),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                for (final row in rows)
                  if (row.$2.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 110,
                            child: Text(
                              row.$1,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              row.$2,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            );
          },
        );
      },
    );
  }

  List<(String, String)> _detailRowsFor(GlobalSearchHit hit) {
    final record = hit.record;
    final rows = switch (record) {
      final Booking b => [
        ('رقم الحجز', '#${b.id.toString().padLeft(6, '0')}'),
        ('النزيل', b.guestName),
        ('الهاتف', b.guestPhone),
        ('رقم الهوية', b.guestIdNumber),
        ('الجنسية', b.guestNationality),
        ('الغرفة', b.roomNumber),
        ('الدخول', b.checkinDate),
        ('الخروج', b.checkoutDate ?? b.actualCheckout ?? '—'),
        ('الحالة', b.status),
        ('الإجمالي المستحق', _fmt(b.totalDueCached)),
        ('المدفوع', _fmt(b.totalPaidCached)),
        ('المتبقي', _fmt(b.remainingBalanceCached)),
        ('ملاحظات', b.notes ?? ''),
      ],
      final GuestInfo g => [
        ('الضيف', g.guestName),
        ('رقم الهوية', g.idNumber),
        ('نوع الهوية', g.idType),
        ('الجنسية', g.nationality),
        ('الهاتف', g.guestPhone ?? ''),
        ('الغرفة', g.roomNumber),
        ('المحافظة', g.governorate ?? ''),
        ('جهة الإصدار', g.issuePlace ?? ''),
        ('ملاحظات', g.notes ?? ''),
      ],
      final Payment p => [
        ('المبلغ', _fmt(p.amount)),
        ('التاريخ', p.paymentDate),
        ('اليوم الفندقي', p.hotelDayKey ?? '—'),
        ('الغرفة', p.roomNumber ?? ''),
        ('طريقة الدفع', p.paymentMethod),
        ('نوع الإيراد', p.revenueType),
        ('المستلم', p.receivedByName ?? ''),
        ('رقم المرجع', p.referenceNumber ?? ''),
        if (p.isVoided) ('الحالة', 'ملغاة (${p.voidReason ?? ''})'),
        if (p.isPendingBalance) ('الحالة', 'رصيد معلق'),
        ('ملاحظات', p.notes ?? ''),
      ],
      final Expense e => [
        ('الوصف', e.description),
        ('النوع', e.expenseType),
        ('المبلغ', _fmt(e.amount)),
        ('التاريخ', e.date),
        ('اليوم الفندقي', e.hotelDayKey ?? '—'),
        if (e.isAutoGenerated) ('مصدر السجل', 'مولّد تلقائياً'),
      ],
      final SalaryWithdrawal w => [
        ('الموظف', hit.title),
        ('المبلغ', _fmt(w.amount)),
        ('التاريخ', w.withdrawDate),
        ('اليوم الفندقي', w.hotelDayKey ?? '—'),
        ('السبب', w.reason ?? ''),
        ('النوع', w.withdrawalType ?? ''),
        ('الوصف', w.description ?? ''),
      ],
      final Debt d => [
        ('المدين', d.guestName),
        ('الهاتف', d.guestPhone ?? ''),
        ('السبب', d.debtReason),
        ('إجمالي الدين', _fmt(d.totalAmount)),
        ('المسدد', _fmt(d.paidAmount)),
        ('المتبقي', _fmt(d.remainingAmount)),
        ('تاريخ التسجيل', d.paymentDate),
        ('الحالة', d.isSettled == 1 ? 'مسدد' : 'قائم'),
        ('الرهان', d.pledge ?? ''),
        ('ملاحظات', d.note ?? ''),
      ],
      final Employee e => [
        ('الاسم', e.name),
        ('الوظيفة', e.position),
        ('الحالة', e.status),
        ('الراتب الأساسي', _fmt(e.basicSalary)),
        ('الهاتف', e.phone),
        ('الرقم الوظيفي', e.employeeID ?? ''),
        ('تاريخ التعيين', e.hireDate),
      ],
      final Room r => [
        ('الغرفة', r.roomNumber),
        ('النوع', r.type),
        ('الحالة', r.status),
        ('السعر', _fmt(r.price)),
        ('الصيانة', r.requiresMaintenance ? 'تحتاج صيانة' : 'لا'),
      ],
      final InventoryItem i => [
        ('الصنف', i.name),
        ('التصنيف', i.category ?? ''),
        ('الكمية', '${i.quantity} ${i.unit}'),
        ('الحد الأدنى', '${i.minimumQuantity} ${i.unit}'),
        ('الحالة', i.isActive ? 'نشط' : 'موقوف'),
      ],
      final BlacklistEntry b => [
        ('الاسم', b.name),
        ('الجنسية', b.nationality ?? ''),
        ('رقم الهوية', b.nationalId ?? ''),
        ('الهاتف', b.phone ?? ''),
        ('السبب', b.reason ?? ''),
        ('ملاحظات', b.notes ?? ''),
        ('المصدر', b.reportedBy),
        ('الحالة', b.active ? 'نشط' : 'موقوف'),
        ('تاريخ الإضافة', _dayKeyOf(b.createdAt)),
      ],
      _ => [('المعرف', '${hit.id}')],
    };
    return rows.where((row) => row.$2.isNotEmpty && row.$2 != '—').toList();
  }

  String _fmt(num value) => _currencyFmt.format(value);

  static String _dayKeyOf(DateTime d) => d.toIso8601String().substring(0, 10);
}

enum _AdminToggle { includeDeleted, includeInactivePayments }

extension _AdminToggleApply on _AdminToggle {
  void apply(_GlobalSearchScreenState state) {
    switch (this) {
      case _AdminToggle.includeDeleted:
        state._includeDeleted = !state._includeDeleted;
      case _AdminToggle.includeInactivePayments:
        state._includeInactivePayments = !state._includeInactivePayments;
    }
  }
}

// ─────────────────────── خرائط عرض الكيانات ───────────────────────

String kindLabel(SearchEntityKind kind) => switch (kind) {
  SearchEntityKind.booking => 'الحجوزات',
  SearchEntityKind.guestInfo => 'بطاقات الضيوف',
  SearchEntityKind.payment => 'المدفوعات',
  SearchEntityKind.expense => 'المصروفات',
  SearchEntityKind.withdrawal => 'سحبيات الرواتب',
  SearchEntityKind.debt => 'الديون',
  SearchEntityKind.employee => 'الموظفون',
  SearchEntityKind.room => 'الغرف',
  SearchEntityKind.inventoryItem => 'المخزون',
  SearchEntityKind.blacklist => 'القائمة السوداء',
};

IconData kindIcon(SearchEntityKind kind) => switch (kind) {
  SearchEntityKind.booking => Icons.assignment,
  SearchEntityKind.guestInfo => Icons.badge,
  SearchEntityKind.payment => Icons.payments,
  SearchEntityKind.expense => Icons.account_balance_wallet,
  SearchEntityKind.withdrawal => Icons.payments_outlined,
  SearchEntityKind.debt => Icons.pie_chart,
  SearchEntityKind.employee => Icons.person,
  SearchEntityKind.room => Icons.room,
  SearchEntityKind.inventoryItem => Icons.inventory_2_outlined,
  SearchEntityKind.blacklist => Icons.block,
};

Color kindColor(SearchEntityKind kind) => switch (kind) {
  SearchEntityKind.booking => Colors.indigo,
  SearchEntityKind.guestInfo => Colors.teal,
  SearchEntityKind.payment => Colors.green,
  SearchEntityKind.expense => Colors.orange,
  SearchEntityKind.withdrawal => Colors.blue,
  SearchEntityKind.debt => Colors.purple,
  SearchEntityKind.employee => Colors.brown,
  SearchEntityKind.room => Colors.cyan.shade700,
  SearchEntityKind.inventoryItem => Colors.deepOrange,
  SearchEntityKind.blacklist => Colors.red,
};
