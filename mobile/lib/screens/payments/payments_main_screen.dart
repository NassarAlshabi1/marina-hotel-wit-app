import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../mixins/sync_on_exit_mixin.dart';
import '../../models/payment_models.dart';
import '../../providers/appwrite_providers.dart' hide ConnectionState;
import '../../providers/repository_providers.dart';
import '../../services/analytics_service.dart';
import '../../services/crashlytics_service.dart';
import '../../services/local_db.dart' as db;
import '../../utils/currency_formatter.dart';
import '../../utils/hotel_time_engine.dart';
import '../../utils/status_utils.dart';
import '../../utils/time.dart';
import 'booking_checkout_screen.dart';
import 'payment_history_screen.dart';
import '../../utils/english_digits_input_formatter.dart';

class PaymentsMainScreen extends ConsumerStatefulWidget {
  const PaymentsMainScreen({super.key});

  @override
  ConsumerState<PaymentsMainScreen> createState() => _PaymentsMainScreenState();
}

class _PaymentsMainScreenState extends ConsumerState<PaymentsMainScreen>
    with SingleTickerProviderStateMixin, SyncOnExitMixin {
  @override
  String get screenId => 'payments_main';
  late TabController _tabController;
  // ✅ ValueNotifier بدلاً من bool + setState — يمنع إعادة بناء الشاشة كاملة
  // عند تغيير حالة الحفظ (يُعيد بناء الزر فقط)
  final ValueNotifier<bool> _isSavingPayment = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    CrashlyticsService.instance.setCurrentScreen('PaymentsMainScreen');
    // ✅ Analytics: تتبّع مشاهدة شاشة المدفوعات
    unawaited(
      AnalyticsService().logScreenView(
        screenName: 'payments_main',
        screenClass: 'PaymentsMainScreen',
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _isSavingPayment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return wrapWithSyncOnExit(
      child: AppScaffold(
        title: 'إدارة المدفوعات',
        fab: FloatingActionButton.extended(
          onPressed: _isSavingPayment.value ? null : _showNewPaymentDialog,
          icon: const Icon(Icons.add_card),
          label: const Text('دفعة جديدة'),
          backgroundColor: Colors.green,
        ),
        body: Column(
          children: [
            TabBar(
              controller: _tabController,
              labelColor: Colors.green.shade800,
              unselectedLabelColor: Colors.grey.shade600,
              indicatorColor: Colors.green,
              labelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              unselectedLabelStyle: const TextStyle(fontSize: 11),
              tabs: const [
                Tab(text: 'نظرة عامة', icon: Icon(Icons.dashboard, size: 18)),
                Tab(text: 'المعاملات', icon: Icon(Icons.list, size: 18)),
                Tab(text: 'الحجوزات النشطة', icon: Icon(Icons.hotel, size: 18)),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOverviewTab(),
                  _buildTransactionsTab(),
                  _buildActiveBookingsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    final paymentsRepo = ref.read(paymentsRepoProvider);

    return StreamBuilder<List<db.Payment>>(
      stream: paymentsRepo.watchAll(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.payment_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'لا توجد مدفوعات مسجلة',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        final payments = snapshot.data;
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // الإحصائيات السريعة
              _buildQuickStats(payments ?? []),

              const SizedBox(height: 16),

              // المدفوعات الأخيرة
              _buildRecentPayments(payments ?? []),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickStats(List<db.Payment> payments) {
    final today = DateTime.now();
    final hotelDay = HotelTimeEngine.getHotelDayKey();
    final startOfMonth = DateTime(today.year, today.month);

    // حساب المبالغ
    final totalAmount = payments.fold<double>(0, (sum, p) => sum + p.amount);

    // مدفوعات اليوم الفندقي الحالي
    final todayPayments = payments.where((p) {
      if (p.isVoided) {
        return false;
      }
      if (p.hotelDayKey == hotelDay) {
        return true;
      }
      if (p.hotelDayKey == null && p.paymentDate.startsWith(hotelDay)) {
        return true;
      }
      return false;
    }).toList();
    final todayAmount = todayPayments.fold<double>(
      0,
      (sum, p) => sum + p.amount,
    );

    // مدفوعات هذا الشهر
    final monthlyPayments = payments.where((p) {
      try {
        final date = DateTime.parse(p.paymentDate);
        return date.isAfter(startOfMonth);
      } catch (e) {
        return false;
      }
    }).toList();
    final monthlyAmount = monthlyPayments.fold<double>(
      0,
      (sum, p) => sum + p.amount,
    );

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'اليوم الفندقي',
            CurrencyFormatter.formatAmount(todayAmount),
            Icons.today,
            Colors.amber.shade700,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'الإجمالي',
            CurrencyFormatter.formatAmount(totalAmount),
            Icons.account_balance_wallet,
            Colors.green,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'هذا الشهر',
            CurrencyFormatter.formatAmount(monthlyAmount),
            Icons.calendar_month,
            Colors.blue,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 1),
            Text(
              title,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildPaymentMethodChart(List<db.Payment> payments) {
    final methodCounts = <String, double>{};

    for (final payment in payments) {
      methodCounts[payment.paymentMethod] =
          (methodCounts[payment.paymentMethod] ?? 0) + payment.amount;
    }

    if (methodCounts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'توزيع المدفوعات حسب الطريقة',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: methodCounts.entries.map((entry) {
                    final color = _getPaymentMethodColor(entry.key);
                    return PieChartSectionData(
                      value: entry.value,
                      title:
                          '${entry.key}\n${(entry.value / methodCounts.values.reduce((a, b) => a + b) * 100).toStringAsFixed(1)}%',
                      color: color,
                      radius: 80,
                      titleStyle: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    );
                  }).toList(),
                  centerSpaceRadius: 40,
                  sectionsSpace: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentPayments(List<db.Payment> payments) {
    // عرض مدفوعات اليوم الفندقي الحالي
    final hotelDay = HotelTimeEngine.getHotelDayKey();
    final todayPayments = payments.where((p) {
      if (p.isVoided) {
        return false;
      }
      if (p.hotelDayKey == hotelDay) {
        return true;
      }
      if (p.hotelDayKey == null && p.paymentDate.startsWith(hotelDay)) {
        return true;
      }
      return false;
    }).toList();

    // ترتيب تنازلي حسب التاريخ
    todayPayments.sort((a, b) {
      try {
        return DateTime.parse(
          b.paymentDate,
        ).compareTo(DateTime.parse(a.paymentDate));
      } catch (_) {
        return 0;
      }
    });

    final recentPayments = todayPayments.take(10).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'مدفوعات اليوم الفندقي',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton(
                  onPressed: () => _tabController.animateTo(1),
                  child: const Text('عرض الكل'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...recentPayments.map(
              (payment) => RepaintBoundary(
                child: ListTile(
                  leading: Icon(
                    _getPaymentMethodIcon(payment.paymentMethod),
                    color: _getPaymentMethodColor(payment.paymentMethod),
                  ),
                  title: Text(CurrencyFormatter.formatAmount(payment.amount)),
                  subtitle: Text(
                    '${payment.paymentMethod} • ${payment.paymentDate}',
                  ),
                  trailing: payment.roomNumber != null
                      ? Chip(
                          label: Text(payment.roomNumber!),
                          backgroundColor: Colors.blue.shade50,
                        )
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionsTab() {
    return const PaymentHistoryScreen();
  }

  Widget _buildActiveBookingsTab() {
    final bookingsRepo = ref.read(bookingsRepoProvider);

    return StreamBuilder<List<db.Booking>>(
      stream: bookingsRepo.watchList(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.hotel_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'لا توجد حجوزات نشطة',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        final activeBookings = snapshot.data!
            .where((booking) => StatusUtils.isActiveBooking(booking.status))
            .toList();

        if (activeBookings.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                SizedBox(height: 16),
                Text(
                  'جميع الحجوزات مكتملة!',
                  style: TextStyle(fontSize: 18, color: Colors.green),
                ),
              ],
            ),
          );
        }

        // ✅ تنبيه تأخر السداد: نحسب الساعة الحالية لتحديد ما إذا كان
        // الحجز يحتاج إلى مؤشر برتقالي (22:00-23:00) أو أحمر متأخر (23:00-05:00).
        final now = DateTime.now();
        final hour = now.hour;
        final isLateWindow = hour >= 22 && hour < 23;
        final isOverdueWindow = hour >= 23 || hour < 5;

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: activeBookings.length,
          itemBuilder: (context, index) {
            final booking = activeBookings[index];
            // ✅ حالة تأخر السداد الخاصة بهذا الحجز (لا تظهر إلا إذا كان
            // هناك رصيد متبقي + نحن داخل نافذة التنبيه الليلية).
            final hasRemainingBalance =
                booking.remainingBalanceCached.round() > 0;
            final isLate = hasRemainingBalance && isLateWindow;
            final isOverdue = hasRemainingBalance && isOverdueWindow;

            // ✅ لون دائرة رقم الغرفة يتغير حسب الحالة.
            final Color avatarBg = isOverdue
                ? Colors.red.shade100
                : isLate
                ? Colors.orange.shade100
                : Colors.orange.shade100;
            final Color avatarFg = isOverdue
                ? Colors.red.shade700
                : isLate
                ? Colors.orange.shade700
                : Colors.orange;

            return RepaintBoundary(
              child: Card(
                margin: const EdgeInsets.only(bottom: 6),
                // ✅ حدود ملوّنة عند التنبيه للتأخر
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: isOverdue
                      ? BorderSide(color: Colors.red.shade700, width: 1.5)
                      : isLate
                      ? BorderSide(color: Colors.orange.shade700, width: 1.2)
                      : BorderSide.none,
                ),
                child: ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: avatarBg,
                    child: Text(
                      booking.roomNumber,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: avatarFg,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          booking.guestName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      // ✅ شارة تنبيه برتقالية/حمراء عند التأخر
                      if (isLate)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.orange.shade700,
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 10,
                                color: Colors.orange.shade700,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                'تنبيه 22:00',
                                style: TextStyle(
                                  fontSize: 8,
                                  color: Colors.orange.shade800,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (isOverdue)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.red.shade700,
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 10,
                                color: Colors.red.shade700,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                'متأخر',
                                style: TextStyle(
                                  fontSize: 8,
                                  color: Colors.red.shade800,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الهاتف: ${booking.guestPhone}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        'دخول: ${booking.checkinDate}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        'الجنسية: ${booking.guestNationality}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  trailing: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (context) =>
                              BookingCheckoutScreen(booking: booking),
                        ),
                      );
                    },
                    icon: const Icon(Icons.payment, size: 14),
                    label: Text(
                      isOverdue ? 'دفع فوري' : 'دفع',
                      style: const TextStyle(fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      // ✅ زر الدفع يتحول إلى أحمر/برتقالي حسب حالة التأخر.
                      backgroundColor: isOverdue
                          ? Colors.red.shade700
                          : isLate
                          ? Colors.orange.shade600
                          : Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                    ),
                  ),
                  isThreeLine: true,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Color _getPaymentMethodColor(String method) {
    switch (method) {
      case 'نقدي':
        return Colors.green;
      case 'بطاقة':
        return Colors.blue;
      case 'تحويل':
        return Colors.orange;
      case 'شيك':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  IconData _getPaymentMethodIcon(String method) {
    switch (method) {
      case 'نقدي':
        return Icons.money;
      case 'بطاقة':
        return Icons.credit_card;
      case 'تحويل':
        return Icons.account_balance;
      case 'شيك':
        return Icons.receipt_long;
      default:
        return Icons.payment;
    }
  }

  // ─── إضافة دفعة جديدة تراكمية ───

  Future<void> _showNewPaymentDialog() async {
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    final referenceController = TextEditingController();
    PaymentMethod selectedMethod = PaymentMethod.cash;

    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.add_card, color: Colors.green),
                  SizedBox(width: 8),
                  Text('دفعة جديدة تراكمية'),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // اختيار طريقة الدفع
                      const Text(
                        'طريقة الدفع',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: PaymentMethod.values.map((method) {
                          final isSelected = selectedMethod == method;
                          return ChoiceChip(
                            avatar: Icon(
                              method.icon,
                              size: 16,
                              color: isSelected ? Colors.white : method.color,
                            ),
                            label: Text(
                              method.displayName,
                              style: TextStyle(
                                fontSize: 12,
                                color: isSelected ? Colors.white : method.color,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: method.color,
                            onSelected: (_) {
                              setDialogState(() {
                                selectedMethod = method;
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      // حقل المبلغ
                      TextField(
                        controller: amountController,
                        decoration: const InputDecoration(
                          labelText: 'المبلغ *',
                          prefixText: 'ر.ي ',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: const [englishIntegerInputFormatter],
                      ),
                      const SizedBox(height: 12),

                      // رقم المرجع (للتحويل والشيك)
                      if (selectedMethod == PaymentMethod.transfer ||
                          selectedMethod == PaymentMethod.check) ...[
                        TextField(
                          controller: referenceController,
                          decoration: const InputDecoration(
                            labelText: 'رقم المرجع / الشيك',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // ملاحظات
                      TextField(
                        controller: notesController,
                        decoration: const InputDecoration(
                          labelText: 'ملاحظات (اختياري)',
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
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: _isSavingPayment.value
                      ? null
                      : () => _saveStandalonePayment(
                          ctx,
                          amountController.text,
                          notesController.text,
                          referenceController.text,
                          selectedMethod,
                        ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _isSavingPayment,
                    builder: (context, isSaving, _) => isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('تسجيل الدفعة'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      amountController.dispose();
      notesController.dispose();
      referenceController.dispose();
    }
  }

  Future<void> _saveStandalonePayment(
    BuildContext dialogContext,
    String amountText,
    String notes,
    String reference,
    PaymentMethod method,
  ) async {
    final parsedAmount = CurrencyFormatter.parseAmount(amountText);
    if (parsedAmount == null || parsedAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال مبلغ صحيح'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _isSavingPayment.value = true;

    try {
      final paymentsRepo = ref.read(paymentsRepoProvider);

      String dbMethod;
      switch (method) {
        case PaymentMethod.cash:
          dbMethod = 'نقدي';
        case PaymentMethod.card:
          dbMethod = 'بطاقة';
        case PaymentMethod.transfer:
          dbMethod = 'تحويل';
        case PaymentMethod.check:
          dbMethod = 'شيك';
        case PaymentMethod.installment:
          dbMethod = 'تقسيط';
      }

      await paymentsRepo.create(
        amount: parsedAmount,
        paymentDate: Time.nowIso(),
        notes: notes.trim().isEmpty ? null : notes.trim(),
        paymentMethod: dbMethod,
        revenueType: 'other',
      );

      unawaited(ref.read(appwriteSyncManagerProvider).pushLocalChanges());

      if (mounted && dialogContext.mounted) {
        Navigator.pop(dialogContext);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تسجيل الدفعة ${CurrencyFormatter.formatAmount(parsedAmount)} بنجاح',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'PaymentsMainScreen',
        action: 'saveStandalonePayment',
        error: e,
        stackTrace: stack,
        extra: {'amount': amountText, 'method': method.name},
      );
      if (mounted && dialogContext.mounted) {
        Navigator.pop(dialogContext);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تسجيل الدفعة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        _isSavingPayment.value = false;
      }
    }
  }
}
