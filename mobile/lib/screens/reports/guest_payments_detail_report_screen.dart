import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/status_utils.dart';

/// تقرير تفصيلي لمدفوعات النزلاء مع حساب عدد الأيام والرصيد المتبقي للأيام القادمة
class GuestPaymentsDetailReportScreen extends ConsumerStatefulWidget {
  const GuestPaymentsDetailReportScreen({super.key});

  @override
  ConsumerState<GuestPaymentsDetailReportScreen> createState() =>
      _GuestPaymentsDetailReportScreenState();
}

class _GuestPaymentsDetailReportScreenState
    extends ConsumerState<GuestPaymentsDetailReportScreen> {
  final DateFormat _dateFmt = DateFormat('yyyy/MM/dd');
  String _searchQuery = '';
  String _filterStatus = 'all'; // all, partial, unpaid, overpaid
  String _sortBy = 'room'; // room, name, remaining
  bool _showOnlyActive = true;
  bool _isLoading = true;

  /// حساب الأيام المقضية فعلياً (من تاريخ الوصول إلى اليوم أو المغادرة)
  int _getActualDaysSpent(Booking b) {
    final checkin = DateTime.tryParse(b.checkinDate);
    if (checkin == null) return 0;
    final now = DateTime.now();
    // إذا تم المغادرة فعلياً
    if (b.actualCheckout != null && b.actualCheckout!.isNotEmpty) {
      final actual = DateTime.tryParse(b.actualCheckout!);
      if (actual != null) return now.difference(checkin).inDays > 0 ? actual.difference(checkin).inDays : 1;
    }
    // إذا حدد تاريخ مغادرة
    if (b.checkoutDate != null && b.checkoutDate!.isNotEmpty) {
      final checkout = DateTime.tryParse(b.checkoutDate!);
      if (checkout != null) {
        final end = checkout.isBefore(now) ? checkout : now;
        final days = end.difference(checkin).inDays;
        return days > 0 ? days : 1;
      }
    }
    return now.difference(checkin).inDays + 1;
  }

  /// حساب الأيام المتبقية حتى تاريخ المغادرة المخطط
  int _getDaysUntilCheckout(Booking b) {
    if (b.checkoutDate == null || b.checkoutDate!.isEmpty) return 0;
    final checkout = DateTime.tryParse(b.checkoutDate!);
    if (checkout == null) return 0;
    final now = DateTime.now();
    if (checkout.isBefore(now)) return 0; // انتهت المدة
    return checkout.difference(now).inDays;
  }

  /// حساب متوسط سعر الليلة الواحدة
  double _getAverageNightlyRate(Booking b) {
    if (b.calculatedNights <= 0) return 0;
    return b.totalDueCached / b.calculatedNights;
  }

  /// حساب عدد الأيام الممكنة بالرصيد المتبقي
  int _getDaysCoveredByRemaining(Booking b) {
    final remaining = b.remainingBalanceCached;
    if (remaining <= 0) return 0;
    final nightlyRate = _getAverageNightlyRate(b);
    if (nightlyRate <= 0) return 0;
    return (remaining / nightlyRate).floor();
  }

  /// حساب تكلفة الأيام المتبقية حتى تاريخ المغادرة
  double _getUpcomingDaysCost(Booking b) {
    final daysLeft = _getDaysUntilCheckout(b);
    if (daysLeft <= 0) return 0;
    final nightlyRate = _getAverageNightlyRate(b);
    return nightlyRate * daysLeft;
  }

  /// هل الحجز تجاوز تاريخ المغادرة؟
  bool _isOverdue(Booking b) {
    return _getDaysUntilCheckout(b) == 0 && _getActualDaysSpent(b) > b.calculatedNights;
  }

  /// حساب عدد أيام التأخير
  int _getOverdueDays(Booking b) {
    if (!_isOverdue(b)) return 0;
    final spent = _getActualDaysSpent(b);
    return spent > b.calculatedNights ? spent - b.calculatedNights : 0;
  }

  /// تكلفة أيام التأخير
  double _getOverdueCost(Booking b) {
    final days = _getOverdueDays(b);
    if (days <= 0) return 0;
    return _getAverageNightlyRate(b) * days;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() => _isLoading = false);
    });
  }

  List<Booking> _filterAndSort(List<Booking> allBookings) {
    // فلترة حسب النشاط
    var filtered = _showOnlyActive
        ? allBookings.where((b) => StatusUtils.isBookingActive(b)).toList()
        : allBookings.where((b) => b.deletedAt == null).toList();

    // بحث
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((b) {
        return b.guestName.toLowerCase().contains(q) ||
            b.roomNumber.toLowerCase().contains(q) ||
            b.guestPhone.toLowerCase().contains(q);
      }).toList();
    }

    // فلترة حسب حالة الدفع
    if (_filterStatus == 'partial') {
      filtered = filtered.where((b) => b.totalPaidCached > 0 && b.remainingBalanceCached > 0).toList();
    } else if (_filterStatus == 'unpaid') {
      filtered = filtered.where((b) => b.totalPaidCached <= 0).toList();
    } else if (_filterStatus == 'overpaid') {
      filtered = filtered.where((b) => b.totalPaidCached >= b.totalDueCached).toList();
    }

    // ترتيب
    filtered.sort((a, b) {
      if (_sortBy == 'room') {
        return a.roomNumber.compareTo(b.roomNumber);
      } else if (_sortBy == 'remaining') {
        return b.remainingBalanceCached.compareTo(a.remainingBalanceCached);
      } else {
        return a.guestName.compareTo(b.guestName);
      }
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(bookingsListProvider);

    if (_isLoading) {
      return const AppScaffold(
        title: 'تقرير تفصيلي - مدفوعات النزلاء',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return AppScaffold(
      title: 'تقرير تفصيلي - مدفوعات النزلاء',
      body: Column(
        children: [
          _buildSearchAndFilters(),
          Expanded(
            child: bookingsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('خطأ: $e')),
              data: (bookings) => _buildReport(bookings),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.grey.shade50,
      child: Column(
        children: [
          // بحث
          TextField(
            style: const TextStyle(fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: 'ابحث باسم النزيل أو رقم الغرفة أو الهاتف...',
              hintStyle: TextStyle(fontWeight: FontWeight.normal, color: Colors.grey[500]),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () => setState(() => _searchQuery = ''),
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(25)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          const SizedBox(height: 8),

          // فلتر الحالة
          Row(
            children: [
              Expanded(child: _buildFilterChip('الكل', 'all', Colors.blue)),
              const SizedBox(width: 6),
              Expanded(child: _buildFilterChip('دفع جزئي', 'partial', Colors.orange)),
              const SizedBox(width: 6),
              Expanded(child: _buildFilterChip('لم يدفع', 'unpaid', Colors.red)),
              const SizedBox(width: 6),
              Expanded(child: _buildFilterChip('مسدد', 'overpaid', Colors.green)),
            ],
          ),
          const SizedBox(height: 8),

          // خيارات إضافية
          Row(
            children: [
              // النشطة فقط
              Expanded(
                child: FilterChip(
                  label: const Text('النشطة فقط', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  selected: _showOnlyActive,
                  onSelected: (v) => setState(() => _showOnlyActive = v),
                  selectedColor: Colors.blue.withOpacity(0.15),
                  checkmarkColor: Colors.blue,
                  labelStyle: TextStyle(color: _showOnlyActive ? Colors.blue : null, fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              // ترتيب
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _sortBy,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'ترتيب',
                    labelStyle: TextStyle(fontSize: 11),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  style: const TextStyle(fontSize: 11),
                  items: const [
                    DropdownMenuItem(value: 'room', child: Text('رقم الغرفة', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 'name', child: Text('اسم النزيل', style: TextStyle(fontSize: 11))),
                    DropdownMenuItem(value: 'remaining', child: Text('المتبقي', style: TextStyle(fontSize: 11))),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _sortBy = v);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, Color color) {
    final isSelected = _filterStatus == value;
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      selected: isSelected,
      onSelected: (_) => setState(() => _filterStatus = value),
      selectedColor: color.withOpacity(0.15),
      checkmarkColor: color,
      labelStyle: TextStyle(color: isSelected ? color : null, fontSize: 11),
    );
  }

  Widget _buildReport(List<Booking> allBookings) {
    final filtered = _filterAndSort(allBookings);

    // إحصائيات
    final totalDue = filtered.fold(0.0, (s, b) => s + b.totalDueCached);
    final totalPaid = filtered.fold(0.0, (s, b) => s + b.totalPaidCached);
    final totalRemaining = filtered.fold(0.0, (s, b) => s + b.remainingBalanceCached);
    final upcomingCost = filtered.fold(0.0, (s, b) => s + _getUpcomingDaysCost(b));
    final overdueCount = filtered.where((b) => _isOverdue(b)).length;
    final partiallyPaid = filtered.where((b) => b.totalPaidCached > 0 && b.remainingBalanceCached > 0).length;
    final unpaid = filtered.where((b) => b.totalPaidCached <= 0).length;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ملخص إحصائي
        _buildSummaryCard(
          totalDue: totalDue,
          totalPaid: totalPaid,
          totalRemaining: totalRemaining,
          upcomingCost: upcomingCost,
          totalCount: filtered.length,
          overdueCount: overdueCount,
          partiallyPaid: partiallyPaid,
          unpaid: unpaid,
        ),
        const SizedBox(height: 12),

        // عنوان القائمة
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'عدد الحجوزات: ${filtered.length}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[700]),
            ),
            if (filtered.isNotEmpty)
              Text(
                'إجمالي المتبقي: ${CurrencyFormatter.formatAmount(totalRemaining)}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red.shade700),
              ),
          ],
        ),
        const SizedBox(height: 8),

        // قائمة الحجوزات
        if (filtered.isEmpty)
          Center(
            child: Column(
              children: [
                Icon(Icons.inbox, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 8),
                Text('لا توجد حجوزات مطابقة', style: TextStyle(color: Colors.grey[600])),
              ],
            ),
          )
        else
          ...filtered.map((b) => _buildBookingCard(b)),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildSummaryCard({
    required double totalDue,
    required double totalPaid,
    required double totalRemaining,
    required double upcomingCost,
    required int totalCount,
    required int overdueCount,
    required int partiallyPaid,
    required int unpaid,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            // الصف الأول
            Row(
              children: [
                Expanded(child: _buildStatItem('إجمالي الفواتير', CurrencyFormatter.formatAmount(totalDue), Colors.blue.shade700)),
                Container(width: 1, height: 40, color: Colors.grey.shade200),
                Expanded(child: _buildStatItem('إجمالي المدفوع', CurrencyFormatter.formatAmount(totalPaid), Colors.green.shade700)),
              ],
            ),
            const SizedBox(height: 8),
            // الصف الثاني
            Row(
              children: [
                Expanded(child: _buildStatItem('المتبقي', CurrencyFormatter.formatAmount(totalRemaining), Colors.red.shade700)),
                Container(width: 1, height: 40, color: Colors.grey.shade200),
                Expanded(child: _buildStatItem('تكلفة الأيام القادمة', CurrencyFormatter.formatAmount(upcomingCost), Colors.orange.shade700)),
              ],
            ),
            const Divider(height: 16),
            // الصف الثالث - أرقام
            Row(
              children: [
                Expanded(
                  child: _buildMiniBadge('حجوزات', '$totalCount', Colors.blue),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildMiniBadge('دفع جزئي', '$partiallyPaid', Colors.orange),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildMiniBadge('لم يدفع', '$unpaid', Colors.red),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildMiniBadge('متأخر', '$overdueCount', Colors.deepOrange),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildMiniBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildBookingCard(Booking b) {
    final actualDays = _getActualDaysSpent(b);
    final daysLeft = _getDaysUntilCheckout(b);
    final nightlyRate = _getAverageNightlyRate(b);
    final daysCovered = _getDaysCoveredByRemaining(b);
    const upcomingCost = 0.0;
    final overdueDays = _getOverdueDays(b);
    final overdueCost = _getOverdueCost(b);
    final isOverdue = _isOverdue(b);
    final paidPercent = b.totalDueCached > 0 ? (b.totalPaidCached / b.totalDueCached * 100) : 0.0;

    // ألوان الحالة
    Color cardColor = Colors.white;
    Color borderColor = Colors.grey.shade300;
    if (isOverdue) {
      cardColor = Colors.red.shade50;
      borderColor = Colors.red.shade300;
    } else if (b.remainingBalanceCached > 0 && b.totalPaidCached > 0) {
      cardColor = Colors.orange.shade50;
      borderColor = Colors.orange.shade300;
    } else if (b.totalPaidCached <= 0) {
      cardColor = Colors.blue.shade50;
      borderColor = Colors.blue.shade300;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── الرأس: غرفة + اسم + حالة ───
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade700,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    b.roomNumber,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    b.guestName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isOverdue)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning, size: 12, color: Colors.red),
                        const SizedBox(width: 2),
                        Text('+$overdueDays يوم', style: const TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )
                else if (daysLeft > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green),
                    ),
                    child: Text(
                      '$daysLeft يوم متبقي',
                      style: const TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // ─── التواريخ ───
            _buildInfoRow(Icons.calendar_today, 'الوصول: ${_dateFmt.tryParse(b.checkinDate) != null ? _dateFmt.format(DateTime.parse(b.checkinDate)) : b.checkinDate.split(' ').first}',
                Icons.event, 'المغادرة: ${b.checkoutDate?.split(' ').first ?? '---'}'),
            const SizedBox(height: 6),

            // ─── الأيام ───
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text('حساب الأيام والمدفوعات', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDaysCard('الأيام المقضية', '$actualDays', 'يوم', Icons.bed, Colors.blue),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildDaysCard('الأيام المخططة', '${b.calculatedNights}', 'يوم', Icons.nightlight_round, Colors.purple),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildDaysCard('سعر الليلة', CurrencyFormatter.formatAmount(nightlyRate), 'ريال', Icons.attach_money, Colors.teal),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDaysCard('الأيام المتبقية', '$daysLeft', 'يوم', Icons.hourglass_top, Colors.orange),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildDaysCard(
                          'أيام بالرصيد',
                          b.remainingBalanceCached <= 0 ? '0' : '$daysCovered',
                          'يوم',
                          Icons.account_balance_wallet,
                          daysCovered >= daysLeft ? Colors.green : Colors.red,
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (isOverdue)
                        Expanded(
                          child: _buildDaysCard('أيام تأخير', '$overdueDays', 'يوم', Icons.warning_amber, Colors.red),
                        )
                      else
                        const Expanded(child: SizedBox()),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ─── شريط التقدم + المبالغ ───
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('تقدم الدفع', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                      Text(
                        '${paidPercent.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: paidPercent >= 100 ? Colors.green : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: paidPercent.clamp(0, 100) / 100,
                      minHeight: 6,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        paidPercent >= 100 ? Colors.green : paidPercent >= 50 ? Colors.orange : Colors.red,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _buildAmountCol('الإجمالي', b.totalDueCached, Colors.blue.shade700)),
                      Expanded(child: _buildAmountCol('المدفوع', b.totalPaidCached, Colors.green.shade700)),
                      Expanded(child: _buildAmountCol('المتبقي', b.remainingBalanceCached, Colors.red.shade700)),
                    ],
                  ),
                  if (isOverdue) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, size: 14, color: Colors.red),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'تكلفة التأخير: ${CurrencyFormatter.formatAmount(overdueCost)} ريال ($overdueDays يوم)',
                              style: TextStyle(fontSize: 11, color: Colors.red.shade700, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (daysCovered < daysLeft && !isOverdue && b.remainingBalanceCached > 0) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, size: 14, color: Colors.orange),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'الرصيد يكفي $daysCovered يوم فقط من $daysLeft يوم متبقي',
                              style: TextStyle(fontSize: 11, color: Colors.orange.shade700, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 6),

            // ─── رقم الهاتف ───
            if (b.guestPhone.isNotEmpty)
              Row(
                children: [
                  const Icon(Icons.phone, size: 12, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(b.guestPhone, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon1, String text1, IconData icon2, String text2) {
    return Row(
      children: [
        Icon(icon1, size: 12, color: Colors.grey.shade500),
        const SizedBox(width: 3),
        Expanded(child: Text(text1, style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
        const SizedBox(width: 12),
        Icon(icon2, size: 12, color: Colors.grey.shade500),
        const SizedBox(width: 3),
        Expanded(child: Text(text2, style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
      ],
    );
  }

  Widget _buildDaysCard(String label, String value, String unit, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 8, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildAmountCol(String label, double value, Color color) {
    return Column(
      children: [
        Text(CurrencyFormatter.formatAmount(value), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
      ],
    );
  }
}
