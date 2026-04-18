import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/status_utils.dart';
import '../../utils/time.dart';

/// شاشة إرسال تذكير واتساب بالمبلغ المتبقي للحجوزات النشطة
/// تعرض جميع الحجوزات النشطة التي لديها مبلغ متبقي مع إمكانية إرسال رسالة تذكير
class ActiveBookingsReminderScreen extends ConsumerStatefulWidget {
  const ActiveBookingsReminderScreen({super.key});

  @override
  ConsumerState<ActiveBookingsReminderScreen> createState() =>
      _ActiveBookingsReminderScreenState();
}

class _ActiveBookingsReminderScreenState
    extends ConsumerState<ActiveBookingsReminderScreen> {
  String _searchQuery = '';
  String _filterStatus = 'all'; // all, partial, unpaid
  Set<int> _selectedIds = {};
  bool _isSending = false;
  int _sentCount = 0;
  int _failedCount = 0;

  /// تنظيف وتنسيق رقم الهاتف ليمني/سعودي
  String _cleanAndFormatPhone(String phone) {
    var digitsOnly = phone.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.isEmpty) return '';
    if (digitsOnly.startsWith('00')) digitsOnly = digitsOnly.substring(2);
    if (digitsOnly.startsWith('07')) {
      digitsOnly = '967${digitsOnly.substring(1)}';
    } else if (digitsOnly.startsWith('5') && digitsOnly.length == 9) {
      digitsOnly = '966$digitsOnly';
    }
    return digitsOnly;
  }

  /// حساب عدد الليالي المتأخرة عن تاريخ المغادرة المخطط
  int _getDaysSinceCheckout(Booking booking) {
    if (booking.checkoutDate == null || booking.checkoutDate!.isEmpty) return 0;
    final checkout = DateTime.tryParse(booking.checkoutDate!);
    if (checkout == null) return 0;
    return DateTime.now().difference(checkout).inDays;
  }

  /// بناء رسالة تذكير بالمبلغ المتبقي للحجز النشط
  String _buildReminderMessage(Booking booking) {
    final checkin = booking.checkinDate.split(' ').first;
    final checkout = booking.checkoutDate?.split(' ').first ?? 'لم يحدد';
    final nights = booking.calculatedNights;
    final total = booking.totalDueCached;
    final paid = booking.totalPaidCached;
    final remaining = booking.remainingBalanceCached;
    final daysSinceCheckout = _getDaysSinceCheckout(booking);

    String message = 'عزيزي/عزيزتي ${booking.guestName}\n';
    message += '━━━━━━━━━━━━━━━\n\n';
    message += 'تحية طيبة من فندق مارينا\n\n';
    message += 'نتوجه لكم بتذكير بخصوص المبلغ المتبقي لإقامتكم:\n\n';
    message += 'رقم الغرفة: ${booking.roomNumber}\n';
    message += 'تاريخ الوصول: $checkin\n';
    message += 'تاريخ المغادرة: $checkout\n';
    message += 'عدد الليالي: $nights\n\n';
    message += 'الإجمالي: ${CurrencyFormatter.formatAmount(total)} ريال\n';
    message += 'المدفوع: ${CurrencyFormatter.formatAmount(paid)} ريال\n';
    message += 'المبلغ المتبقي: ${CurrencyFormatter.formatAmount(remaining)} ريال\n';

    if (daysSinceCheckout > 0) {
      message += '\nتنبيه: تجاوزتم موعد المغادرة بـ $daysSinceCheckout يوم\n';
    }

    message += '\n';
    message += 'نرجو منكم التكرم بتسديد المبلغ المتبقي في أقرب وقت ممكن.\n\n';
    message += 'مع خالص التحية والتقدير\n';
    message += 'فندق مارينا\n';
    message += 'للاستفسار: 9677734587456';

    return message;
  }

  /// إرسال رسالة واتساب لحجز واحد
  Future<bool> _sendSingleReminder(Booking booking) async {
    final whatsappService = ref.read(whatsappServiceProvider);
    final phone = _cleanAndFormatPhone(booking.guestPhone);
    if (phone.isEmpty) return false;

    final message = _buildReminderMessage(booking);
    return await whatsappService.sendMessage(phoneE164: phone, message: message);
  }

  /// إرسال تذكير لجميع الحجوزات المحددة
  Future<void> _sendBulkReminders(List<Booking> bookings) async {
    if (bookings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لم تختر أي حجز لإرسال التذكير'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSending = true;
      _sentCount = 0;
      _failedCount = 0;
    });

    for (final booking in bookings) {
      final success = await _sendSingleReminder(booking);
      if (success) {
        _sentCount++;
      } else {
        _failedCount++;
      }
    }

    if (mounted) {
      setState(() => _isSending = false);
      final message =
          'تم إرسال $_sentCount تذكير بنجاح${_failedCount > 0 ? ' وفشل $_failedCount' : ''}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: _failedCount > 0 ? Colors.orange : Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
      setState(() => _selectedIds.clear());
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(bookingsListProvider);

    return AppScaffold(
      title: 'تذكير المتبقي - حجوزات نشطة',
      actions: [
        IconButton(
          onPressed: () => _showBulkSendConfirmation(context),
          icon: const Icon(Icons.send),
          tooltip: 'إرسال للمحدد',
          style: IconButton.styleFrom(
            foregroundColor:
                _selectedIds.isNotEmpty ? Colors.white : Colors.grey,
          ),
        ),
      ],
      body: Column(
        children: [
          // شريط البحث والتصفية
          _buildSearchAndFilters(),

          // الإحصائيات
          _buildQuickStats(bookingsAsync),

          // شريط الإرسال المجمّع
          if (_selectedIds.isNotEmpty) _buildBulkActionBar(),

          // قائمة الحجوزات
          Expanded(
            child: bookingsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('خطأ: $e')),
              data: (bookings) => _buildBookingsList(bookings),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey.shade50,
      child: Column(
        children: [
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
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildFilterChip('الكل', 'all')),
              const SizedBox(width: 8),
              Expanded(child: _buildFilterChip('دفع جزئي', 'partial')),
              const SizedBox(width: 8),
              Expanded(child: _buildFilterChip('لم يدفع', 'unpaid')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filterStatus == value;
    Color color;
    if (value == 'unpaid') {
      color = Colors.red;
    } else if (value == 'partial') {
      color = Colors.orange;
    } else {
      color = Colors.blue;
    }
    return FilterChip(
      label:
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      selected: isSelected,
      onSelected: (_) => setState(() => _filterStatus = value),
      selectedColor: color.withOpacity(0.15),
      checkmarkColor: color,
      labelStyle: TextStyle(color: isSelected ? color : null),
    );
  }

  Widget _buildQuickStats(AsyncValue<List<Booking>> bookingsAsync) {
    return bookingsAsync.when(
      loading: () => const SizedBox(),
      error: (_, __) => const SizedBox(),
      data: (bookings) {
        // فلترة: حجوزات نشطة فقط مع متبقي > 0
        final activeWithRemaining = bookings
            .where(
              (b) =>
                  StatusUtils.isBookingActive(b) &&
                  b.remainingBalanceCached > 0,
            )
            .toList();

        final partialPaid = activeWithRemaining
            .where((b) => b.totalPaidCached > 0)
            .toList();
        final unpaid = activeWithRemaining
            .where((b) => b.totalPaidCached <= 0)
            .toList();
        final totalRemaining = activeWithRemaining.fold(
          0.0,
          (sum, b) => sum + b.remainingBalanceCached,
        );
        final overdue = activeWithRemaining
            .where((b) => _getDaysSinceCheckout(b) > 0)
            .toList();

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildMiniStat(
                      'حجوزات متبقي',
                      activeWithRemaining.length.toString(),
                      Colors.blue,
                    ),
                  ),
                  Container(width: 1, height: 40, color: Colors.blue.shade200),
                  Expanded(
                    child: _buildMiniStat(
                      'دفع جزئي',
                      partialPaid.length.toString(),
                      Colors.orange,
                    ),
                  ),
                  Container(width: 1, height: 40, color: Colors.blue.shade200),
                  Expanded(
                    child: _buildMiniStat(
                      'لم يدفع',
                      unpaid.length.toString(),
                      Colors.red,
                    ),
                  ),
                ],
              ),
              if (overdue.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber, size: 14, color: Colors.red.shade700),
                      const SizedBox(width: 4),
                      Text(
                        '${overdue.length} حجز تجاوز تاريخ المغادرة',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.payments, size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 6),
                    Text(
                      'إجمالي المبالغ المتبقية: ${CurrencyFormatter.formatAmount(totalRemaining)} ريال',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMiniStat(String title, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          title,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildBulkActionBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'تم اختيار ${_selectedIds.length} حجز لإرسال التذكير',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green.shade700,
                fontSize: 13,
              ),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _selectedIds.clear()),
            child: Text(
              'إلغاء التحديد',
              style: TextStyle(
                color: Colors.green.shade700,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Booking> _filterBookings(List<Booking> allBookings) {
    // فلترة: حجوزات نشطة فقط مع متبقي > 0
    var filtered = allBookings
        .where(
          (b) =>
              StatusUtils.isBookingActive(b) && b.remainingBalanceCached > 0,
        )
        .toList();

    // بحث
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((booking) {
        final query = _searchQuery.toLowerCase();
        if (booking.guestName.toLowerCase().contains(query)) return true;
        if (booking.roomNumber.toLowerCase().contains(query)) return true;
        return false;
      }).toList();
    }

    // تصفية حسب الحالة
    if (_filterStatus == 'partial') {
      filtered =
          filtered.where((b) => b.totalPaidCached > 0).toList();
    } else if (_filterStatus == 'unpaid') {
      filtered =
          filtered.where((b) => b.totalPaidCached <= 0).toList();
    }

    // ترتيب: التي تجاوزت المغادرة أولاً، ثم حسب المبلغ المتبقي الأعلى
    filtered.sort((a, b) {
      final aDays = _getDaysSinceCheckout(a);
      final bDays = _getDaysSinceCheckout(b);
      // الحجوزات المتجاوزة للمغادرة أولاً
      if (aDays > 0 && bDays <= 0) return -1;
      if (bDays > 0 && aDays <= 0) return 1;
      // بين المتجاوزة: الأقدم أولاً
      if (aDays > 0 && bDays > 0) {
        final cmp = bDays.compareTo(aDays);
        if (cmp != 0) return cmp;
      }
      // حسب المبلغ المتبقي الأعلى
      return b.remainingBalanceCached.compareTo(a.remainingBalanceCached);
    });

    return filtered;
  }

  Widget _buildBookingsList(List<Booking> allBookings) {
    final filteredBookings = _filterBookings(allBookings);

    if (filteredBookings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline,
                size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'لا توجد حجوزات بمبلغ متبقي',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'جميع الحجوزات النشطة مسددة أو لا يوجد متبقي',
              style: TextStyle(color: Colors.grey.shade400),
            ),
          ],
        ),
      );
    }

    if (_isSending) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              'جاري إرسال التذكيرات...',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.green.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'نجاح: $_sentCount | فشل: $_failedCount',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredBookings.length,
      itemBuilder: (context, index) {
        final booking = filteredBookings[index];
        return _buildBookingCard(booking);
      },
    );
  }

  Widget _buildBookingCard(Booking booking) {
    final isSelected = _selectedIds.contains(booking.id);
    final hasPhone = booking.guestPhone.isNotEmpty &&
        _cleanAndFormatPhone(booking.guestPhone).isNotEmpty;
    final daysSinceCheckout = _getDaysSinceCheckout(booking);
    final isOverdue = daysSinceCheckout > 0;
    final paidPercent = booking.totalDueCached > 0
        ? (booking.totalPaidCached / booking.totalDueCached * 100)
        : 0.0;
    final isUnpaid = booking.totalPaidCached <= 0;

    Color cardColor = isOverdue
        ? Colors.red.shade50
        : isUnpaid
            ? Colors.orange.shade50
            : Colors.blue.shade50;
    Color borderColor = isOverdue
        ? Colors.red.shade300
        : isUnpaid
            ? Colors.orange.shade300
            : Colors.blue.shade300;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: isSelected ? 2 : 1),
      ),
      child: InkWell(
        onTap: () => setState(() {
          if (isSelected) {
            _selectedIds.remove(booking.id);
          } else {
            _selectedIds.add(booking.id);
          }
        }),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // الرأس: اسم + حالة + اختيار
              Row(
                children: [
                  Checkbox(
                    value: isSelected,
                    onChanged: (_) => setState(() {
                      if (isSelected) {
                        _selectedIds.remove(booking.id);
                      } else {
                        _selectedIds.add(booking.id);
                      }
                    }),
                    activeColor:
                        isOverdue ? Colors.red : isUnpaid ? Colors.orange : Colors.blue,
                  ),
                  Expanded(
                    child: Text(
                      booking.guestName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // شارة الحالة
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: (isOverdue
                              ? Colors.red
                              : isUnpaid
                                  ? Colors.orange
                                  : Colors.blue)
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isOverdue
                            ? Colors.red
                            : isUnpaid
                                ? Colors.orange
                                : Colors.blue,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isOverdue
                              ? Icons.warning_amber_rounded
                              : isUnpaid
                                  ? Icons.money_off
                                  : Icons.payment,
                          size: 14,
                          color: isOverdue
                              ? Colors.red
                              : isUnpaid
                                  ? Colors.orange
                                  : Colors.blue,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isOverdue
                              ? 'تجاوز +$daysSinceCheckout يوم'
                              : isUnpaid
                                  ? 'لم يدفع'
                                  : 'دفع جزئي',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isOverdue
                                ? Colors.red
                                : isUnpaid
                                    ? Colors.orange
                                    : Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // معلومات الحجز
              Row(
                children: [
                  Expanded(
                    child: _buildInfoChip(
                      Icons.hotel,
                      booking.roomNumber,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildInfoChip(
                      Icons.nightlight_round,
                      '${booking.calculatedNights} ليلة',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildInfoChip(
                      Icons.phone,
                      hasPhone ? booking.guestPhone : 'بدون رقم',
                      isValid: hasPhone,
                    ),
                  ),
                ],
              ),

              // تواريخ
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today,
                        size: 12, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text(
                      'الوصول: ${booking.checkinDate.split(' ').first}',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.event,
                        size: 12, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text(
                      'المغادرة: ${booking.checkoutDate?.split(' ').first ?? '---'}',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 4),

              // شريط التقدم + المبالغ
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    // شريط التقدم
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'تقدم الدفع',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Text(
                          '${paidPercent.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: paidPercent >= 100
                                ? Colors.green
                                : Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: paidPercent.clamp(0, 100) / 100,
                        minHeight: 4,
                        backgroundColor: Colors.grey.shade300,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          paidPercent >= 100
                              ? Colors.green
                              : Colors.orange,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // المبالغ
                    Row(
                      children: [
                        Expanded(
                          child: _buildAmountColumn(
                            'الإجمالي',
                            CurrencyFormatter.formatAmount(
                                booking.totalDueCached),
                            Colors.blue.shade700,
                          ),
                        ),
                        Expanded(
                          child: _buildAmountColumn(
                            'المدفوع',
                            CurrencyFormatter.formatAmount(
                                booking.totalPaidCached),
                            Colors.green.shade700,
                          ),
                        ),
                        Expanded(
                          child: _buildAmountColumn(
                            'المتبقي',
                            CurrencyFormatter.formatAmount(
                                booking.remainingBalanceCached),
                            Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // زر إرسال فردي
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: hasPhone
                      ? () => _sendSingleReminderWithFeedback(booking)
                      : null,
                  icon: const Icon(Icons.send, size: 16),
                  label: Text(
                    hasPhone
                        ? 'إرسال تذكير واتساب'
                        : 'لا يوجد رقم هاتف',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.green.shade700,
                    side: BorderSide(
                      color: hasPhone
                          ? Colors.green.shade300
                          : Colors.grey.shade300,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text, {bool isValid = true}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isValid ? Colors.grey.shade700 : Colors.red.shade400,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildAmountColumn(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  /// إرسال تذكير فردي مع رسالة تأكيد ونتيجة
  Future<void> _sendSingleReminderWithFeedback(Booking booking) async {
    final message = _buildReminderMessage(booking);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.send, color: Colors.green),
              SizedBox(width: 8),
              Text('تأكيد إرسال التذكير'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('سيتم إرسال تذكير بالمبلغ المتبقي إلى:'),
              const SizedBox(height: 12),
              _buildPreviewRow('العميل', booking.guestName),
              _buildPreviewRow('الغرفة', booking.roomNumber),
              _buildPreviewRow(
                  'رقم الهاتف',
                  booking.guestPhone.isNotEmpty
                      ? booking.guestPhone
                      : 'غير متوفر'),
              _buildPreviewRow(
                'المبلغ المتبقي',
                '${CurrencyFormatter.formatAmount(booking.remainingBalanceCached)} ريال',
                valueColor: Colors.red,
              ),
              _buildPreviewRow(
                'تاريخ المغادرة',
                booking.checkoutDate?.split(' ').first ?? 'لم يحدد',
              ),
              const Divider(),
              const Text(
                'معاينة الرسالة:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Text(
                    message,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.send, size: 16),
              label: const Text('إرسال'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('جاري الإرسال...',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );

    final success = await _sendSingleReminder(booking);

    if (mounted) {
      Navigator.pop(context); // إغلاق مؤشر التحميل
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'تم إرسال التذكير إلى ${booking.guestName} بنجاح'
                : 'فشل إرسال التذكير - تأكد من رقم الهاتف أو اتصال الواتساب',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Widget _buildPreviewRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: valueColor ?? Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  /// تأكيد الإرسال المجمّع
  Future<void> _showBulkSendConfirmation(BuildContext context) async {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اختر حجزاً واحداً على الأقل'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final bookingsAsync = ref.read(bookingsListProvider);
    final bookings = bookingsAsync.valueOrNull ?? [];
    final selectedBookings =
        bookings.where((b) => _selectedIds.contains(b.id)).toList();
    final totalRemaining = selectedBookings.fold(
      0.0,
      (sum, b) => sum + b.remainingBalanceCached,
    );

    // التحقق من وجود أرقام هواتف
    int withoutPhone = 0;
    for (final booking in selectedBookings) {
      final phone = _cleanAndFormatPhone(booking.guestPhone);
      if (phone.isEmpty) withoutPhone++;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.send, color: Colors.green),
              SizedBox(width: 8),
              Text('تأكيد الإرسال المجمّع'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'سيتم إرسال تذكير بالمبلغ المتبقي إلى ${selectedBookings.length} عميل:',
              ),
              const SizedBox(height: 12),
              _buildPreviewRow(
                'عدد التذكيرات',
                '${selectedBookings.length}',
                valueColor: Colors.blue,
              ),
              _buildPreviewRow(
                'إجمالي المبالغ المتبقية',
                '${CurrencyFormatter.formatAmount(totalRemaining)} ريال',
                valueColor: Colors.red,
              ),
              if (withoutPhone > 0)
                _buildPreviewRow(
                  'بدون رقم هاتف',
                  '$withoutPhone (سيتم تخطيهم)',
                  valueColor: Colors.orange,
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.send, size: 16),
              label: const Text('إرسال الكل'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    // تصفية الحجوزات التي لديها رقم هاتف فقط
    final bookingsWithPhone = <Booking>[];
    for (final booking in selectedBookings) {
      final phone = _cleanAndFormatPhone(booking.guestPhone);
      if (phone.isNotEmpty) {
        bookingsWithPhone.add(booking);
      }
    }

    await _sendBulkReminders(bookingsWithPhone);
  }
}
