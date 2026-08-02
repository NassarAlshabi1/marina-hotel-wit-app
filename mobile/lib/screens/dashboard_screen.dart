import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/appwrite_providers.dart';
import '../providers/core_providers.dart';
import '../providers/repository_providers.dart';
import '../providers/room_payment_status_provider.dart';
import '../services/analytics_service.dart';
import '../services/local_db.dart';
import '../services/remote_config_service.dart';
import '../services/sync/sync_gate.dart';
import '../services/sync_constants.dart';
import '../utils/loading_snackbar.dart';
import '../utils/performance_monitor.dart';
import '../utils/status_utils.dart';
import '../widgets/dashboard_conflicts_badge.dart';
import '../widgets/dashboard_sync_button.dart';
import 'bookings/booking_edit.dart';
import 'payments/booking_payment_screen.dart';
import 'reports/expenses_report_screen.dart';

const List<String> _dashboardRoomNumbers = [
  '101',
  '102',
  '103',
  '104',
  '201',
  '202',
  '203',
  '204',
  '301',
  '302',
  '303',
  '304',
  '401',
  '402',
  '403',
  '404',
  '501',
  '502',
  '503',
  '504',
];

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    // ✅ Analytics: تتبّع مشاهدة الشاشة لفهم سلوك المستخدم
    unawaited(
      AnalyticsService().logScreenView(
        screenName: 'dashboard',
        screenClass: 'DashboardScreen',
      ),
    );
    // سحب البيانات من Appwrite تلقائياً عند فتح التطبيق
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoPullFromAppwrite();
    });
  }

  Future<void> _autoPullFromAppwrite() async {
    // ✅ P3-5 (Global SyncGate): السحب التلقائي عند الفتح يمرّ عبر البوّابة
    // العامة. إذا كان المستخدم قد ضغط زر مزامنة يدوياً، أو كان المؤقّت
    // يعمل، فإن السحب التلقائي يُلغى بصمت دون منافسة على الموارد.
    final executed = await SyncGate.instance.runGuardedVoid(
      operation: 'auto_pull',
      source: 'auto_open',
      task: _autoPullFromAppwriteInner,
    );
    if (!executed) {
      debugPrint(
        'ℹ️ [AutoPull] skipped — SyncGate busy with '
        '${SyncGate.instance.state.operation} from '
        '${SyncGate.instance.state.source}',
      );
    }
  }

  Future<void> _autoPullFromAppwriteInner() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appwriteEnabled = prefs.getBool('appwrite_sync_enabled') ?? true;

      if (!appwriteEnabled) {
        return;
      }

      // ─── فحص ذكي: هل مرت ساعة منذ آخر سحب تلقائي؟ ───
      final lastPullEpochMs = prefs.getInt(SyncConstants.lastAppOpenPullKey);
      if (lastPullEpochMs != null) {
        final lastPull = DateTime.fromMillisecondsSinceEpoch(lastPullEpochMs);
        final elapsed = DateTime.now().difference(lastPull);
        if (elapsed < SyncConstants.appOpenSyncInterval) {
          return;
        }
      }

      // Connection check (Cloudflare) — always connected
      // ✅ إشعار تحميل قابل للإغلاق برمجياً
      LoadingSnackBar? loading;
      if (mounted) {
        loading = LoadingSnackBar.show(
          context,
          message: '📥 جاري سحب البيانات...',
        );
      }

      final syncManager = ref.read(appwriteSyncManagerProvider);
      final result = await syncManager.sync(push: false);
      final pulledCount = result.recordsPulled;

      // ✅ إغلاق إشعار التحميل فور انتهاء السحب
      if (mounted) {
        loading?.close();
      }

      // ─── تسجيل وقت هذا السحب التلقائي ───
      await prefs.setInt(
        SyncConstants.lastAppOpenPullKey,
        DateTime.now().millisecondsSinceEpoch,
      );

      if (mounted && pulledCount > 0) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.cloud_download, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '✅ تم سحب $pulledCount سجل جديد من Appwrite تلقائياً',
                    style: const TextStyle(fontFamily: 'Tajawal'),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      } else if (mounted) {
        // إشعار صامت بأن البيانات محدثة
        debugPrint('✅ البيانات محدثة — لا توجد سجلات جديدة');
      }
    } catch (e) {
      debugPrint('❌ فشل السحب التلقائي عند الفتح: $e');
    }
  }

  /// لون الغرفة المتأخرة عن السداد — يُقرأ من Remote Config
  Color _overdueColor() {
    final hex = RemoteConfigService.instance.overdueRoomColor;
    final parsed = int.tryParse('FF$hex', radix: 16);
    if (parsed == null) {
      return Colors.red; // fallback آمن
    }
    return Color(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return PerformanceInspector(
      name: 'DashboardScreen',
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildStatisticsCards(),
              const SizedBox(height: 20),
              _buildRoomsSection(),
              const SizedBox(height: 12),
              _buildColorInstructions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final versionAsync = ref.watch(appVersionProvider);
    final versionLabel = versionAsync.valueOrNull ?? '...';
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade600, Colors.blue.shade400],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.hotel, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'فندق مارينا',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  const Text(
                    'لوحة التحكم',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(width: 6),
                  // ✅ رقم إصدار APK — يُقرأ ديناميكياً من package_info_plus.
                  // يظهر للمستخدم مباشرةً في الـ header حتى يسهل التحقق من
                  // النسخة المثبّتة دون فتح شاشة الإعدادات.
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.blue.shade200,
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      'v$versionLabel',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const DashboardConflictsBadge(),
        const SizedBox(width: 8),
        const DashboardSyncButton(),
      ],
    );
  }

  Widget _buildStatisticsCards() {
    final currencyFmt = NumberFormat('#,##0', 'en_US');
    return Row(
      children: [
        Expanded(
          child: Consumer(
            builder: (context, ref, _) {
              final incomeAsync = ref.watch(todayPaymentsProvider);
              final expensesAsync = ref.watch(todayExpensesProvider);

              // التعامل مع حالة التحميل
              final isLoading =
                  incomeAsync.isLoading || expensesAsync.isLoading;
              final hasError = incomeAsync.hasError || expensesAsync.hasError;

              if (isLoading) {
                return _buildStatCard(
                  'المتبقي',
                  '...',
                  Icons.savings,
                  Colors.indigo,
                );
              }

              if (hasError) {
                return _buildStatCard(
                  'المتبقي',
                  '--',
                  Icons.savings,
                  Colors.indigo,
                );
              }

              final income = incomeAsync.valueOrNull ?? 0.0;
              final expenses = expensesAsync.valueOrNull ?? 0.0;
              final balance = income - expenses;

              return _buildStatCard(
                balance >= 0 ? 'المتبقي' : 'عجز',
                currencyFmt.format(balance.abs()),
                balance >= 0 ? Icons.savings : Icons.warning_amber_rounded,
                balance >= 0 ? Colors.indigo : Colors.orange,
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Consumer(
            builder: (context, ref, _) {
              final paymentsAsync = ref.watch(todayPaymentsProvider);
              return paymentsAsync.when(
                loading: () => _buildStatCard(
                  'مدفوعات اليوم',
                  '...',
                  Icons.payments_rounded,
                  Colors.green,
                ),
                error: (e, _) => _buildStatCard(
                  'مدفوعات اليوم',
                  '--',
                  Icons.payments_rounded,
                  Colors.green,
                ),
                data: (total) => _buildStatCard(
                  'مدفوعات اليوم',
                  currencyFmt.format(total),
                  Icons.payments_rounded,
                  Colors.green,
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Consumer(
            builder: (context, ref, _) {
              final expensesAsync = ref.watch(todayExpensesProvider);
              return expensesAsync.when(
                loading: () => _buildStatCard(
                  'المصروفات',
                  '...',
                  Icons.money_off_rounded,
                  Colors.red,
                ),
                error: (e, _) => _buildStatCard(
                  'المصروفات',
                  '--',
                  Icons.money_off_rounded,
                  Colors.red,
                ),
                data: (total) => _buildStatCard(
                  'المصروفات',
                  currencyFmt.format(total),
                  Icons.money_off_rounded,
                  Colors.red,
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const ExpensesReportScreen(),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              title,
              style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomsSection() {
    return Consumer(
      builder: (context, ref, _) {
        final roomsWithStatusAsync = ref.watch(roomsWithPaymentStatusProvider);
        return roomsWithStatusAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, st) {
            debugPrint('❌ Dashboard rooms error: $e');
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Colors.red.shade400,
                    size: 40,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'تعذر تحميل الغرف',
                    style: TextStyle(
                      color: Colors.red.shade600,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$e',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          },
          data: _buildRoomsCard,
        );
      },
    );
  }

  Widget _buildRoomsCard(List<RoomWithPaymentStatus> roomsWithStatus) {
    final Map<String, RoomWithPaymentStatus> roomsMap = {
      for (final rws in roomsWithStatus) rws.room.roomNumber: rws,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'حالة الغرف',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              _buildLegendItem('محجوزة', Colors.red.shade600),
              const SizedBox(width: 8),
              _buildLegendItem('متأخر', _overdueColor()),
              const SizedBox(width: 8),
              _buildLegendItem('شاغرة', Colors.green.shade600),
            ],
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.2,
            ),
            itemCount: _dashboardRoomNumbers.length,
            itemBuilder: (context, index) {
              final roomNumber = _dashboardRoomNumbers[index];
              final rws = roomsMap[roomNumber];
              return RepaintBoundary(
                child: _buildRoomButton(context, roomNumber, rws),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildRoomButton(
    BuildContext context,
    String roomNumber,
    RoomWithPaymentStatus? rws,
  ) {
    final Color bgColor = rws?.roomColor ?? Colors.grey.shade400;
    final String tooltipText = rws != null ? rws.displayStatus : 'غير مسجلة';
    final bool isOverdue = rws?.isPaymentOverdue ?? false;

    // ✅ إصلاح الوميض: استخدام ValueKey يمنع flutter_animate من إعادة تشغيل
    // الرسوم المتحركة عند إعادة بناء الـ widget بنفس البيانات
    // المفتاح يتضمن حالة التأخر فقط — لا يتغير إلا عند تغيير الحالة فعلياً
    final keySuffix = isOverdue ? '_overdue' : '_normal';

    final Widget button = Tooltip(
      message: isOverdue
          ? '$tooltipText — ⚠️ تأخر سداد (بعد 10 مساءً)'
          : tooltipText,
      child: GestureDetector(
        onLongPress: rws != null
            ? () => _showRoomOptionsDialog(context, rws.room)
            : null,
        child: Material(
          key: ValueKey('room_$roomNumber$keySuffix'),
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _handleRoomTap(context, roomNumber, rws?.room),
            child: Stack(
              children: [
                // رقم الغرفة في المنتصف
                Center(
                  child: Text(
                    roomNumber,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                // ─── شريط برتقالي على اليمين عند تأخر الدفع ───
                // يظهر بعد الساعة 10 مساءً للغرف المحجوزة التي لها رصيد متبقي
                if (isOverdue)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      decoration: BoxDecoration(
                        color: Colors.orange.shade400,
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(10),
                          bottomRight: Radius.circular(10),
                        ),
                      ),
                      child: const Center(
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: Text(
                            '⚠',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                // ─── نقطة برتقالية في الأعلى عند تأخر الدفع ───
                if (isOverdue)
                  Positioned(
                    left: 4,
                    top: 4,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.orange.shade300,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withValues(alpha: 0.6),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    if (isOverdue) {
      // ✅ إصلاح الوميض: استخدام target(uniqueKey) لمنع إعادة تشغيل
      // الرسوم المتحركة عند إعادة بناء القائمة بدون تغيير حقيقي
      return button
          .animate(key: ValueKey('anim_${roomNumber}_overdue'))
          .tint(color: const Color(0x30FF9800), duration: 1000.ms)
          .scale(
            begin: const Offset(1.0, 1.0),
            end: const Offset(1.02, 1.02),
            duration: 1000.ms,
            curve: Curves.easeInOut,
          )
          .then()
          .tint(color: const Color(0x00FF9800), duration: 1000.ms)
          .scale(
            begin: const Offset(1.02, 1.02),
            end: const Offset(1.0, 1.0),
            duration: 1000.ms,
            curve: Curves.easeInOut,
          );
    }

    return button;
  }

  void _showRoomOptionsDialog(BuildContext context, Room room) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.settings, color: Colors.blue.shade600),
            const SizedBox(width: 8),
            Text('غرفة ${room.roomNumber}'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('الحالة الحالية: ${room.status}'),
            const SizedBox(height: 16),
            if (room.status != 'صيانة')
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _updateRoomStatus(room, 'صيانة');
                  },
                  icon: const Icon(Icons.build, color: Colors.white),
                  label: const Text('تحويل إلى صيانة'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade600,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateRoomStatus(Room room, String newStatus) async {
    try {
      final roomsRepo = ref.read(roomsRepoProvider);
      await roomsRepo.updateStatus(room.id, newStatus);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تحديث حالة الغرفة ${room.roomNumber} إلى $newStatus',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحديث الحالة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleRoomTap(
    BuildContext context,
    String roomNumber,
    Room? room,
  ) async {
    if (room != null) {
      final isAvailable = StatusUtils.isRoomAvailable(room.status);
      final isOccupied = StatusUtils.isRoomOccupied(room.status);

      if (isAvailable) {
        // الانتقال مباشرة إلى شاشة إضافة حجز جديد عند النقر على غرفة شاغرة
        _navigateToNewBooking(context, roomNumber);
      } else if (isOccupied) {
        // الانتقال مباشرة إلى شاشة الدفع/عرض الحجز عند النقر على غرفة محجوزة
        await _navigateToPaymentForRoom(context, roomNumber);
      } else {
        // للحالات الأخرى مثل الصيانة
        _showRoomDetailsDialog(context, room);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('الغرفة $roomNumber غير مسجلة في النظام'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _navigateToNewBooking(BuildContext context, String roomNumber) {
    Navigator.of(
      context,
    ).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => BookingEditScreen(initialRoomNumber: roomNumber),
      ),
    );
  }

  Future<void> _navigateToPaymentForRoom(
    BuildContext context,
    String roomNumber,
  ) async {
    try {
      final bookingsRepo = ref.read(bookingsRepoProvider);
      final activeBooking = await bookingsRepo.getActiveBookingForRoom(
        roomNumber,
      );

      if (activeBooking == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('لا يوجد حجز محجوز للغرفة $roomNumber'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if (context.mounted) {
        unawaited(
          Navigator.of(
            context,
          ).push<void>(
            MaterialPageRoute<void>(
              builder: (context) =>
                  BookingPaymentScreen(booking: activeBooking),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showRoomDetailsDialog(BuildContext context, Room room) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('غرفة ${room.roomNumber}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('الحالة', room.status),
            _buildDetailRow('النوع', room.type),
            _buildDetailRow('السعر', '${room.price.toStringAsFixed(0)} ريال'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
          if (!StatusUtils.isRoomOccupied(room.status))
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _navigateToNewBooking(context, room.roomNumber);
              },
              child: const Text('حجز جديد'),
            ),
        ],
      ),
    );
  }

  Widget _buildColorInstructions() {
    return Align(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildInstructionDot(Colors.green.shade600, 'شاغرة (متاحة)'),
          const SizedBox(width: 12),
          _buildInstructionDot(Colors.red.shade600, 'محجوزة (مشغولة)'),
          const SizedBox(width: 12),
          _buildInstructionDot(Colors.red.shade600, 'وميض: تأخر سداد (11م-5ص)'),
        ],
      ),
    );
  }

  Widget _buildInstructionDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 8, color: Colors.grey.shade500)),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(value),
        ],
      ),
    );
  }
}
