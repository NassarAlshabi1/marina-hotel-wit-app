// ignore_for_file: use_build_context_synchronously
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/appwrite_providers.dart';
import '../providers/core_providers.dart';
import '../providers/sync_providers.dart';
import '../providers/service_providers.dart';

import '../providers/room_payment_status_provider.dart';
import '../providers/realtime_sync_provider.dart';
import '../providers/remote_config_provider.dart';
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
    unawaited(ref.read(analyticsServiceProvider).logScreenView(screenName: 'dashboard', screenClass: 'DashboardScreen'));
    // سحب البيانات من Appwrite تلقائياً عند فتح التطبيق
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoPullFromAppwrite();
    });
  }

  Future<void> _autoPullFromAppwrite() async {
    // ✅ P3-5 (Global SyncGate): السحب التلقائي عند الفتح يمرّ عبر البوّابة
    // العامة. إذا كان المستخدم قد ضغط زر مزامنة يدوياً، أو كان المؤقّت
    // يعمل، فإن السحب التلقائي يُلغى بصمت دون منافسة على الموارد.
    final executed = await ref.read(syncGateProvider).runGuardedVoid(
      operation: 'auto_pull',
      source: 'auto_open',
      task: _autoPullFromAppwriteInner,
    );
    if (!executed) {
      debugPrint(
        'ℹ️ [AutoPull] skipped — SyncGate busy with '
        '${ref.read(syncGateProvider).state.operation} from '
        '${ref.read(syncGateProvider).state.source}',
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
      final lastPullEpochMs = prefs.getInt(ref.read(lastAppOpenPullKeyProvider));
      if (lastPullEpochMs != null) {
        final lastPull = DateTime.fromMillisecondsSinceEpoch(lastPullEpochMs);
        final elapsed = DateTime.now().difference(lastPull);
        if (elapsed < ref.read(appOpenSyncIntervalProvider)) {
          return;
        }
      }

      // التأكد من الاتصال
      await ref.read(connectionStatusProvider.notifier).checkConnection();
      final isConnected = ref.read(connectionStatusProvider).isConnected;
      if (!isConnected) {
        return;
      }

      // ✅ إشعار تحميل قابل للإغلاق برمجياً
      LoadingSnackBar? loading;
      if (mounted) {
        loading = LoadingSnackBar.show(context, message: '📥 جاري سحب البيانات...');
      }

      final syncManager = ref.read(appwriteSyncManagerProvider);
      final result = await syncManager.sync(push: false);
      final pulledCount = result.recordsPulled;

      // ✅ إغلاق إشعار التحميل فور انتهاء السحب
      if (mounted) {
        loading?.close();
      }

      // إعادة تعيين علامة التغييرات عن بعد
      ref.read(appwriteRealtimeSyncProvider).resetRemoteChangesFlag();

      // ─── تسجيل وقت هذا السحب التلقائي ───
      await prefs.setInt(ref.read(lastAppOpenPullKeyProvider), DateTime.now().millisecondsSinceEpoch);

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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
    final hex = ref.read(remoteConfigServiceProvider).overdueRoomColor;
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'لوحة التحكم',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            fontFamily: 'Tajawal',
            color: Color(0xFF1A1A2E),
          ),
        ),
        Row(
          children: [
            const DashboardConflictsBadge(),
            const SizedBox(width: 8),
            const DashboardSyncButton(),
          ],
        ),
      ],
    );
  }

  Widget _buildStatisticsCards() {
    return Consumer(
      builder: (context, ref, child) {
        final todayPayments = ref.watch(todayPaymentsProvider).valueOrNull ?? 0.0;
        final todayExpenses = ref.watch(todayExpensesProvider).valueOrNull ?? 0.0;
        final pendingDebts = ref.watch(pendingDebtsProvider).length;

        return Row(
          children: [
            Expanded(
              child: _StatCard(
                title: 'المدفوعات اليوم',
                value: NumberFormat.currency(locale: 'ar', symbol: 'ر.س').format(todayPayments),
                icon: Icons.attach_money,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                title: 'المصروفات اليوم',
                value: NumberFormat.currency(locale: 'ar', symbol: 'ر.س').format(todayExpenses),
                icon: Icons.money_off,
                color: Colors.red,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                title: 'الديون المستحقة',
                value: pendingDebts.toString(),
                icon: Icons.warning_amber_rounded,
                color: Colors.orange,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRoomsSection() {
    return Consumer(
      builder: (context, ref, child) {
        final roomsAsync = ref.watch(roomsListProvider);
        return roomsAsync.when(
          data: (rooms) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'الغرف',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Tajawal',
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    Text(
                      '${rooms.length} غرفة',
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily: 'Tajawal',
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildRoomsGrid(rooms),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text(
              'خطأ في تحميل الغرف: $e',
              style: const TextStyle(color: Colors.red, fontFamily: 'Tajawal'),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoomsGrid(List<Room> rooms) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: rooms.length,
      itemBuilder: (context, index) {
        final room = rooms[index];
        final isOverdue = _isRoomOverdue(room);
        final isOccupied = _isRoomOccupied(room);

        return _RoomCard(
          room: room,
          isOverdue: isOverdue,
          isOccupied: isOccupied,
          overdueColor: _overdueColor(),
          onTap: () => _navigateToRoomDetail(room),
        );
      },
    );
  }

  bool _isRoomOverdue(Room room) {
    // منطق مبسط للتحقق من التأخر
    return room.status == 'مأجور' && room.remainingBalance > 0;
  }

  bool _isRoomOccupied(Room room) {
    return room.status == 'مأجور';
  }

  void _navigateToRoomDetail(Room room) {
    // الانتقال لتفاصيل الغرفة
  }

  Widget _buildColorInstructions() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📋 دليل الألوان:',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'Tajawal',
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _ColorDot(color: Colors.green, label: 'شاغرة'),
              const SizedBox(width: 16),
              _ColorDot(color: Colors.blue, label: 'مأجورة'),
              const SizedBox(width: 16),
              _ColorDot(color: Colors.orange, label: 'قيد التنظيف'),
              const SizedBox(width: 16),
              _ColorDot(color: Colors.red, label: 'صيانة'),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontFamily: 'Tajawal',
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'Tajawal',
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.isOverdue,
    required this.isOccupied,
    required this.overdueColor,
    required this.onTap,
  });

  final Room room;
  final bool isOverdue;
  final bool isOccupied;
  final Color overdueColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    if (isOverdue) {
      statusColor = overdueColor;
    } else if (isOccupied) {
      statusColor = Colors.blue;
    } else if (room.status == 'قيد التنظيف') {
      statusColor = Colors.orange;
    } else if (room.status == 'صيانة') {
      statusColor = Colors.red;
    } else {
      statusColor = Colors.green;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: statusColor.withOpacity(0.3), width: 2),
          boxShadow: [
            BoxShadow(
              color: statusColor.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with room number and status
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    room.roomNumber,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Tajawal',
                      color: statusColor,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      room.status,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Tajawal',
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Room details
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (room.guestName.isNotEmpty) ...[
                      _DetailRow(
                        icon: Icons.person,
                        label: 'الضيف',
                        value: room.guestName,
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (room.checkinDate.isNotEmpty) ...[
                      _DetailRow(
                        icon: Icons.login,
                        label: 'دخول',
                        value: room.checkinDate,
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (room.checkoutDate.isNotEmpty) ...[
                      _DetailRow(
                        icon: Icons.logout,
                        label: 'خروج',
                        value: room.checkoutDate,
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (room.remainingBalance > 0) ...[
                      _DetailRow(
                        icon: Icons.attach_money,
                        label: 'المتبقي',
                        value: NumberFormat.currency(locale: 'ar', symbol: 'ر.س').format(room.remainingBalance),
                        valueColor: Colors.red,
                      ),
                    ],
                    if (isOverdue) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: overdueColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: overdueColor.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: overdueColor, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'متأخر عن السداد',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Tajawal',
                                  color: overdueColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade500),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'Tajawal',
            color: Colors.grey.shade600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              fontFamily: 'Tajawal',
              color: valueColor ?? Colors.grey.shade800,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontFamily: 'Tajawal',
            color: Color(0xFF1A1A2E),
          ),
        ),
      ],
    );
  }
}
