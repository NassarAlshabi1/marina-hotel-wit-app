import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../providers/remote_config_provider.dart';
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart';
import '../../utils/currency_formatter.dart';

/// شاشة إرسال تنبيه واتساب للمبالغ المتأخرة
/// تعرض جميع الديون المعلقة والمتأخرة مع إمكانية إرسال رسالة تذكير
class LatePaymentWhatsAppScreen extends ConsumerStatefulWidget {
  const LatePaymentWhatsAppScreen({super.key});

  @override
  ConsumerState<LatePaymentWhatsAppScreen> createState() =>
      _LatePaymentWhatsAppScreenState();
}

class _LatePaymentWhatsAppScreenState
    extends ConsumerState<LatePaymentWhatsAppScreen> {
  String _searchQuery = '';
  String _filterStatus = 'all';
  final Set<int> _selectedIds = {};
  bool _isSending = false;
  int _sentCount = 0;
  int _failedCount = 0;

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
    // سبق بإضافة +967
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
    // سبق بإضافة +966
    else if (digitsOnly.startsWith('966')) {
      return digitsOnly;
    }
    // البادئة الافتراضية: أي رقم لا يبدأ بمعرف دولة → 967
    else if (digitsOnly.length <= 10 && !digitsOnly.startsWith('+')) {
      digitsOnly = '967$digitsOnly';
    }
    return digitsOnly;
  }

  /// بناء رسالة تنبيه تأخر الدفع
  String _buildLatePaymentMessage(Debt debt, {Booking? booking}) {
    final daysPassed = _getDaysPassed(debt);
    final roomInfo = booking?.roomNumber ?? '---';
    final checkin = debt.checkinDate.isNotEmpty
        ? debt.checkinDate.split(' ').first
        : '---';
    final checkout = debt.checkoutDate.isNotEmpty
        ? debt.checkoutDate.split(' ').first
        : '---';

    String message = 'تنبيه من فندق مارينا\n';
    message += '━━━━━━━━━━━━━━━\n\n';
    message += 'عزيزي/عزيزتي ${debt.guestName}\n\n';
    message += 'نتوجه لكم بهذا التنبيه بخصوص مبلغ متأخر السداد:\n\n';

    if (daysPassed > 0) {
      message += 'عدد الأيام المتأخرة: $daysPassed يوم\n';
    }
    message += 'رقم الغرفة: $roomInfo\n';
    message += 'فترة الإقامة: $checkin إلى $checkout\n';
    message +=
        'إجمالي المبلغ: ${CurrencyFormatter.formatAmount(debt.totalAmount)}\n';
    message += 'المدفوع: ${CurrencyFormatter.formatAmount(debt.paidAmount)}\n';
    message +=
        'المبلغ المتبقي: ${CurrencyFormatter.formatAmount(debt.remainingAmount)}\n';

    if (debt.debtReason.isNotEmpty) {
      message += 'سبب الدين: ${debt.debtReason}\n';
    }

    message += '\n';
    message += 'نرجو منكم التكرم بتسديد المبلغ المتبقي في أقرب وقت ممكن.\n\n';
    message += 'مع خالص التحية والتقدير\n';
    message += 'فندق مارينا\n';
    message +=
        'للاستفسار: ${ref.read(remoteConfigServiceProvider).hotelContactPhone}';

    return message;
  }

  int _getDaysPassed(Debt debt) {
    final dateStr = debt.dateRecorded.isNotEmpty
        ? debt.dateRecorded
        : debt.checkoutDate;
    final date = DateTime.tryParse(dateStr);
    if (date == null) {
      return 0;
    }
    return DateTime.now().difference(date).inDays;
  }

  bool _isOverdue(Debt debt) {
    final threshold = ref
        .read(remoteConfigServiceProvider)
        .latePaymentThresholdDays;
    return _getDaysPassed(debt) > threshold && debt.isSettled == 0;
  }

  /// إرسال رسالة واتساب لدين واحد
  Future<bool> _sendSingleReminder(Debt debt, Booking? booking) async {
    final whatsappService = ref.read(whatsappServiceProvider);
    final phone = _cleanAndFormatPhone(booking?.guestPhone ?? '');
    if (phone.isEmpty) {
      return false;
    }

    final message = _buildLatePaymentMessage(debt, booking: booking);
    final result = await whatsappService.sendMessage(
      phoneE164: phone,
      message: message,
    );
    if (result.quotaMessage != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(result.quotaMessage!),
          backgroundColor: Colors.orange,
        ),
      );
    }
    return result.success;
  }

  /// إرسال تنبيه لجميع الديون المحددة
  Future<void> _sendBulkReminders(List<Debt> debts) async {
    if (debts.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content: Text('لم تختر أي دين لإرسال التنبيه'),
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

    // جلب الحجوزات من stream provider
    final bookingsAsync = ref.read(bookingsListProvider);
    final bookings = bookingsAsync.valueOrNull ?? [];

    for (final debt in debts) {
      final booking = bookings.cast<Booking?>().firstWhere(
        (b) => b?.id == debt.bookingLocalId,
        orElse: () => null,
      );

      final success = await _sendSingleReminder(debt, booking);
      if (success) {
        _sentCount++;
      } else {
        _failedCount++;
      }
    }

    if (mounted) {
      setState(() => _isSending = false);
      final message =
          'تم إرسال $_sentCount تنبيه بنجاح${_failedCount > 0 ? ' وفشل $_failedCount' : ''}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: _failedCount > 0 ? Colors.orange : Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
      setState(_selectedIds.clear);
    }
  }

  @override
  Widget build(BuildContext context) {
    final debtsAsync = ref.watch(debtsListProvider);
    final bookingsAsync = ref.watch(bookingsListProvider);

    return AppScaffold(
      title: 'تنبيه تأخر الدفع',
      actions: [
        IconButton(
          onPressed: () => _showBulkSendConfirmation(context),
          icon: const Icon(Icons.send),
          tooltip: 'إرسال للمحدد',
          style: IconButton.styleFrom(
            foregroundColor: _selectedIds.isNotEmpty
                ? Colors.white
                : Colors.grey,
          ),
        ),
      ],
      body: Column(
        children: [
          // شريط البحث والتصفية
          _buildSearchAndFilters(),

          // الإحصائيات
          _buildQuickStats(),

          // شريط الإرسال المجمّع
          if (_selectedIds.isNotEmpty) _buildBulkActionBar(),

          // قائمة الديون
          Expanded(
            child: debtsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('خطأ: $e')),
              data: (debts) => bookingsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('خطأ: $e')),
                data: (bookings) => _buildDebtsList(debts, bookings),
              ),
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
              Expanded(child: _buildFilterChip('معلق', 'pending')),
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
    Color color;
    if (value == 'overdue') {
      color = Colors.red;
    } else if (value == 'pending') {
      color = Colors.orange;
    } else {
      color = Colors.blue;
    }
    return FilterChip(
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      selected: isSelected,
      onSelected: (_) => setState(() => _filterStatus = value),
      selectedColor: color.withValues(alpha: 0.15),
      checkmarkColor: color,
      labelStyle: TextStyle(color: isSelected ? color : null),
    );
  }

  Widget _buildQuickStats() {
    final debtsAsync = ref.watch(debtsListProvider);
    return debtsAsync.when(
      loading: () => const SizedBox(),
      error: (_, __) => const SizedBox(),
      data: (debts) {
        final pendingDebts = debts.where((d) => d.isSettled == 0).toList();
        final overdueDebts = pendingDebts.where(_isOverdue).toList();
        final totalRemaining = pendingDebts.fold(
          0.0,
          (sum, d) => sum + d.remainingAmount,
        );

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildMiniStat(
                  'ديون معلقة',
                  pendingDebts.length.toString(),
                  Colors.orange,
                ),
              ),
              Container(width: 1, height: 40, color: Colors.red.shade200),
              Expanded(
                child: _buildMiniStat(
                  'متأخرة (+30 يوم)',
                  overdueDebts.length.toString(),
                  Colors.red,
                ),
              ),
              Container(width: 1, height: 40, color: Colors.red.shade200),
              Expanded(
                child: _buildMiniStat(
                  'إجمالي المتبقي',
                  CurrencyFormatter.formatAmount(totalRemaining),
                  Colors.red.shade700,
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
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.blue.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'تم اختيار ${_selectedIds.length} دين لإرسال التنبيه',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
                fontSize: 13,
              ),
            ),
          ),
          TextButton(
            onPressed: () => setState(_selectedIds.clear),
            child: Text(
              'إلغاء التحديد',
              style: TextStyle(
                color: Colors.blue.shade700,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebtsList(List<Debt> allDebts, List<Booking> bookings) {
    // تصفية: فقط غير المسددة
    var filteredDebts = allDebts.where((d) => d.isSettled == 0).toList();

    // بحث
    if (_searchQuery.isNotEmpty) {
      filteredDebts = filteredDebts.where((debt) {
        final query = _searchQuery.toLowerCase();
        // بحث بالاسم
        if (debt.guestName.toLowerCase().contains(query)) {
          return true;
        }
        // بحث برقم الغرفة
        final booking = bookings.cast<Booking?>().firstWhere(
          (b) => b?.id == debt.bookingLocalId,
          orElse: () => null,
        );
        if (booking?.roomNumber.toLowerCase().contains(query) ?? false) {
          return true;
        }
        return false;
      }).toList();
    }

    // تصفية حسب الحالة
    if (_filterStatus == 'pending') {
      filteredDebts = filteredDebts.where((d) => !_isOverdue(d)).toList();
    } else if (_filterStatus == 'overdue') {
      filteredDebts = filteredDebts.where(_isOverdue).toList();
    }

    // ترتيب: المتأخرة أولاً ثم حسب المبلغ
    filteredDebts.sort((a, b) {
      final aOverdue = _isOverdue(a) ? 0 : 1;
      final bOverdue = _isOverdue(b) ? 0 : 1;
      if (aOverdue != bOverdue) {
        return aOverdue.compareTo(bOverdue);
      }
      return b.remainingAmount.compareTo(a.remainingAmount);
    });

    if (filteredDebts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد ديون متأخرة',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'جميع الديون مسددة أو لا يوجد ديون معلقة',
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
              'جاري إرسال التنبيهات...',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
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
      itemCount: filteredDebts.length,
      itemBuilder: (context, index) {
        final debt = filteredDebts[index];
        final booking = bookings.cast<Booking?>().firstWhere(
          (b) => b?.id == debt.bookingLocalId,
          orElse: () => null,
        );
        return _buildDebtCard(debt, booking);
      },
    );
  }

  Widget _buildDebtCard(Debt debt, Booking? booking) {
    final isSelected = _selectedIds.contains(debt.id);
    final isOverdue = _isOverdue(debt);
    final daysPassed = _getDaysPassed(debt);
    final hasPhone =
        booking != null &&
        booking.guestPhone.isNotEmpty &&
        _cleanAndFormatPhone(booking.guestPhone).isNotEmpty;

    Color cardColor = Colors.orange.shade50;
    Color borderColor = Colors.orange.shade300;
    IconData statusIcon = Icons.schedule;
    Color statusColor = Colors.orange;

    if (isOverdue) {
      cardColor = Colors.red.shade50;
      borderColor = Colors.red.shade300;
      statusIcon = Icons.warning_amber_rounded;
      statusColor = Colors.red;
    }

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
            _selectedIds.remove(debt.id);
          } else {
            _selectedIds.add(debt.id);
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
                        _selectedIds.remove(debt.id);
                      } else {
                        _selectedIds.add(debt.id);
                      }
                    }),
                    activeColor: statusColor,
                  ),
                  Expanded(
                    child: Text(
                      debt.guestName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 14, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          isOverdue
                              ? 'متأخر $daysPassed يوم'
                              : daysPassed > 0
                              ? 'معلق $daysPassed يوم'
                              : 'معلق',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
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
                      booking?.roomNumber ?? '---',
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

              const SizedBox(height: 8),

              // المبالغ
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildAmountColumn(
                        'المدفوع',
                        CurrencyFormatter.formatAmount(debt.paidAmount),
                        Colors.green.shade700,
                      ),
                    ),
                    Expanded(
                      child: _buildAmountColumn(
                        'المتبقي',
                        CurrencyFormatter.formatAmount(debt.remainingAmount),
                        Colors.red.shade700,
                      ),
                    ),
                    Expanded(
                      child: _buildAmountColumn(
                        'الإجمالي',
                        CurrencyFormatter.formatAmount(debt.totalAmount),
                        Colors.grey.shade700,
                      ),
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
                      ? () => _sendSingleReminderWithFeedback(debt, booking)
                      : null,
                  icon: const Icon(Icons.send, size: 16),
                  label: Text(
                    hasPhone ? 'إرسال تنبيه واتساب' : 'لا يوجد رقم هاتف',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
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

  /// إرسال تنبيه فردي مع رسالة تأكيد ونتيجة
  Future<void> _sendSingleReminderWithFeedback(
    Debt debt,
    Booking? booking,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.send, color: Colors.green),
            SizedBox(width: 8),
            Text('تأكيد إرسال التنبيه'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('سيتم إرسال تنبيه تأخر دفع إلى:'),
            const SizedBox(height: 12),
            _buildPreviewRow('العميل', debt.guestName),
            _buildPreviewRow('الغرفة', booking?.roomNumber ?? 'غير معروف'),
            _buildPreviewRow('رقم الهاتف', booking?.guestPhone ?? 'غير متوفر'),
            _buildPreviewRow(
              'المبلغ المتبقي',
              CurrencyFormatter.formatAmount(debt.remainingAmount),
              valueColor: Colors.red,
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
    );

    if (confirmed != true || !mounted) {
      return;
    }

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text(
                'جاري الإرسال...',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );

    final success = await _sendSingleReminder(debt, booking);

    if (mounted) {
      Navigator.pop(context); // إغلاق مؤشر التحميل
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'تم إرسال التنبيه إلى ${debt.guestName} بنجاح'
                : 'فشل إرسال التنبيه - تأكد من رقم الهاتف',
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content: Text('اختر ديناً واحداً على الأقل'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final debtsAsync = ref.read(debtsListProvider);
    final debts = debtsAsync.valueOrNull ?? [];
    final selectedDebts = debts
        .where((d) => _selectedIds.contains(d.id))
        .toList();
    final totalAmount = selectedDebts.fold(
      0.0,
      (sum, d) => sum + d.remainingAmount,
    );

    // التحقق من وجود أرقام هواتف
    final bookingsAsync = ref.read(bookingsListProvider);
    final bookings = bookingsAsync.valueOrNull ?? [];
    int withoutPhone = 0;
    for (final debt in selectedDebts) {
      final booking = bookings.cast<Booking?>().firstWhere(
        (b) => b?.id == debt.bookingLocalId,
        orElse: () => null,
      );
      final phone = _cleanAndFormatPhone(booking?.guestPhone ?? '');
      if (phone.isEmpty) {
        withoutPhone++;
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.send, color: Colors.blue),
            SizedBox(width: 8),
            Text('تأكيد الإرسال المجمّع'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'سيتم إرسال تنبيه تأخر الدفع إلى ${selectedDebts.length} عميل:',
            ),
            const SizedBox(height: 12),
            _buildPreviewRow(
              'عدد التنبيهات',
              '${selectedDebts.length}',
              valueColor: Colors.blue,
            ),
            _buildPreviewRow(
              'إجمالي المبالغ المتأخرة',
              CurrencyFormatter.formatAmount(totalAmount),
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
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    // تصفية الديون التي لديها رقم هاتف فقط
    final bookingsList = ref.read(bookingsListProvider).valueOrNull ?? [];
    final debtsWithPhone = <Debt>[];
    for (final debt in selectedDebts) {
      final booking = bookingsList.cast<Booking?>().firstWhere(
        (b) => b?.id == debt.bookingLocalId,
        orElse: () => null,
      );
      final phone = _cleanAndFormatPhone(booking?.guestPhone ?? '');
      if (phone.isNotEmpty) {
        debtsWithPhone.add(debt);
      }
    }

    await _sendBulkReminders(debtsWithPhone);
  }
}
