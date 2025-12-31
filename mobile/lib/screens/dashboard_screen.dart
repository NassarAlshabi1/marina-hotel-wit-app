import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' as drift;

import '../services/local_db.dart';
import '../providers/repository_providers.dart';
import '../providers/smart_sync_provider.dart';
import '../providers/appwrite_providers.dart';
import '../utils/status_utils.dart';
import '../utils/currency_formatter.dart';

import '../widgets/smart_sync_widgets.dart';
import 'bookings/booking_edit.dart';
import 'bookings/bookings_list.dart';
import 'reports/expenses_report_screen.dart';
import 'payments/booking_payment_screen.dart';
import 'payments/payments_main_screen.dart';

const List<String> _dashboardRoomNumbers = [
  '101', '102', '103', '104',
  '201', '202', '203', '204',
  '301', '302', '303', '304',
  '401', '402', '403', '404',
  '501', '502', '503', '504',
];

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> with SingleTickerProviderStateMixin {
  bool _isImmediateSyncing = false;
  Timer? _lastSyncUpdateTimer;
  late AnimationController _syncAnimationController;
  int _pendingChangesCount = 0;

  @override
  void initState() {
    super.initState();
    _syncAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _lastSyncUpdateTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() {});
      }
    });
    _loadPendingChangesCount();
  }

  @override
  void dispose() {
    _lastSyncUpdateTimer?.cancel();
    _syncAnimationController.dispose();
    super.dispose();
  }

  Future<void> _loadPendingChangesCount() async {
    try {
      final db = ref.read(databaseProvider);
      final count = await (db.select(db.outbox)).get();
      if (mounted) {
        setState(() {
          _pendingChangesCount = count.length;
        });
      }
    } catch (e) {
      debugPrint('خطأ في تحميل عدد التغييرات: $e');
    }
  }

  Future<bool> _checkLocalChanges() async {
    try {
      final manager = ref.read(smartSyncManagerProvider);
      final hasChanges = await manager.hasLocalChanges();
      return hasChanges;
    } catch (e) {
      debugPrint('❌ خطأ في فحص التغييرات المحلية: $e');
      return false;
    }
  }

  Future<void> _triggerImmediateSync(BuildContext context) async {
    if (_isImmediateSyncing) {
      return;
    }

    _syncAnimationController.repeat();

    try {
      final hasLocalChanges = await _checkLocalChanges();
      await _loadPendingChangesCount();
      
      if (hasLocalChanges) {
        final action = await _showLocalChangesDialog(context);
        
        if (action == null) {
          return;
        }
        
        setState(() => _isImmediateSyncing = true);
        
        if (action == 'push_first') {
          await _pushThenPull(context);
        } else if (action == 'pull_only') {
          await _pullOnly(context);
        }
      } else {
        setState(() => _isImmediateSyncing = true);
        await _performSync(context);
      }
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ فشلت المزامنة: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      _syncAnimationController.stop();
      _syncAnimationController.reset();
      if (mounted) {
        setState(() => _isImmediateSyncing = false);
        await _loadPendingChangesCount();
      }
    }
  }

  Future<String?> _showLocalChangesDialog(BuildContext context) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Expanded(child: Text('⚠️ تنبيه: تغييرات محلية')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'لديك تغييرات محلية لم يتم رفعها إلى السحابة بعد.',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '💡 ماذا تريد أن تفعل؟',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• رفع أولاً: يرفع تغييراتك ثم يسحب من السحابة',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '• سحب فقط: يسحب من السحابة دون رفع تغييراتك',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text('إلغاء'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, 'pull_only'),
            icon: Icon(Icons.download, size: 18),
            label: Text('سحب فقط'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, 'push_first'),
            icon: Icon(Icons.upload, size: 18),
            label: Text('رفع أولاً'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          ),
        ],
        actionsAlignment: MainAxisAlignment.spaceBetween,
      ),
    );
  }

  Future<void> _pushThenPull(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    
    try {
      final smartSyncManager = ref.read(smartSyncManagerProvider);
      final appwriteSyncManager = ref.read(appwriteSyncManagerProvider);
      
      messenger.showSnackBar(
        const SnackBar(
          content: Text('📤 جاري رفع التغييرات المحلية (Smart Sync + Appwrite)...'),
          duration: Duration(seconds: 2),
        ),
      );
      
      final results = await Future.wait([
        smartSyncManager.pushLocalChanges(),
        appwriteSyncManager.sync(),
      ]);
      
      if (!mounted) return;
      
      final smartSyncPushSuccess = results[0] as bool;
      
      if (!smartSyncPushSuccess) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('⚠️ فشل رفع بعض التغييرات'),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('✅ تم رفع التغييرات بنجاح'),
            duration: Duration(seconds: 1),
          ),
        );
      }
      
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (!mounted) return;
      await _performSync(context);
      
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('❌ خطأ في رفع التغييرات: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pullOnly(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    
    try {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('⚠️ تحذير: سيتم تجاهل التغييرات المحلية'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (!mounted) return;
      await _performSync(context);
      
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('❌ خطأ في السحب: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _performSync(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    
    messenger.showSnackBar(
      const SnackBar(
        content: Text('🔄 جاري مزامنة Smart Sync و Appwrite...'),
        duration: Duration(seconds: 2),
      ),
    );
    
    try {
      final smartSyncManager = ref.read(smartSyncManagerProvider);
      final appwriteSyncManager = ref.read(appwriteSyncManagerProvider);
      
      await Future.wait([
        smartSyncManager.forceSyncNow(),
        appwriteSyncManager.sync(),
      ]);
      
      ref.invalidate(smartSyncStatusProvider);
      
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('✅ تمت المزامنة بنجاح (Smart Sync + Appwrite)'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('❌ خطأ في المزامنة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      rethrow;
    }
  }

  String _formatLastSyncTime(DateTime? lastSync) {
    if (lastSync == null) return 'لم تتم مزامنة بعد';
    
    final now = DateTime.now();
    final difference = now.difference(lastSync);
    
    if (difference.inSeconds < 60) {
      return 'منذ ${difference.inSeconds} ثانية';
    } else if (difference.inMinutes < 60) {
      return 'منذ ${difference.inMinutes} دقيقة';
    } else if (difference.inHours < 24) {
      return 'منذ ${difference.inHours} ساعة';
    } else {
      final days = difference.inDays;
      return 'منذ $days ${days == 1 ? "يوم" : "أيام"}';
    }
  }

  Widget _buildEnhancedSyncButton(BuildContext context, AsyncValue<Map<String, dynamic>> statusAsync) {
    return statusAsync.when(
      data: (status) {
        final lastSyncStr = status['last_sync_check'] as String?;
        final lastSync = lastSyncStr != null ? DateTime.tryParse(lastSyncStr) : null;
        final isEnabled = status['enabled'] as bool? ?? false;
        final isSyncing = status['is_syncing'] as bool? ?? false;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: _pendingChangesCount > 0
                  ? 'لديك $_pendingChangesCount تغيير معلق - اضغط للمزامنة\n(Smart Sync + Appwrite)'
                  : 'مزامنة البيانات مع السحابة\n(Smart Sync + Appwrite)',
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _isImmediateSyncing
                            ? [Colors.blue.shade400, Colors.blue.shade600]
                            : isSyncing
                                ? [Colors.orange.shade400, Colors.orange.shade600]
                                : isEnabled
                                    ? [Colors.green.shade400, Colors.green.shade600]
                                    : [Colors.grey.shade400, Colors.grey.shade600],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: (_isImmediateSyncing || isSyncing
                                  ? Colors.blue
                                  : isEnabled
                                      ? Colors.green
                                      : Colors.grey)
                              .withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _isImmediateSyncing ? null : () => _triggerImmediateSync(context),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isImmediateSyncing || isSyncing)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    RotationTransition(
                                      turns: _syncAnimationController,
                                      child: Icon(
                                        Icons.sync,
                                        size: 20,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    RotationTransition(
                                      turns: _syncAnimationController,
                                      child: Icon(
                                        Icons.cloud_sync,
                                        size: 18,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isEnabled ? Icons.cloud_upload : Icons.cloud_off,
                                      size: 20,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 2),
                                    Icon(
                                      Icons.storage,
                                      size: 16,
                                      color: Colors.white70,
                                    ),
                                  ],
                                ),
                              const SizedBox(width: 8),
                              Text(
                                _isImmediateSyncing
                                    ? 'جاري المزامنة...'
                                    : isSyncing
                                        ? 'المزامنة نشطة'
                                        : 'مزامنة فورية',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_pendingChangesCount > 0)
                    Positioned(
                      top: -6,
                      right: -6,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withOpacity(0.5),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 22,
                          minHeight: 22,
                        ),
                        child: Center(
                          child: Text(
                            _pendingChangesCount > 99 ? '99+' : '$_pendingChangesCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSyncing
                    ? Colors.blue.shade50
                    : isEnabled
                        ? Colors.green.shade50
                        : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSyncing
                      ? Colors.blue.shade200
                      : isEnabled
                          ? Colors.green.shade200
                          : Colors.grey.shade300,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isEnabled
                        ? (isSyncing ? Icons.sync : Icons.check_circle)
                        : Icons.cloud_off,
                    size: 16,
                    color: isSyncing
                        ? Colors.blue
                        : isEnabled
                            ? Colors.green
                            : Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isSyncing ? 'جاري المزامنة...' : _formatLastSyncTime(lastSync),
                        style: TextStyle(
                          fontSize: 12,
                          color: isSyncing
                              ? Colors.blue.shade900
                              : isEnabled
                                  ? Colors.green.shade900
                                  : Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (isEnabled && !isSyncing)
                        Text(
                          'Smart Sync + Appwrite',
                          style: TextStyle(
                            fontSize: 8,
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey.shade600),
                ),
                const SizedBox(width: 8),
                Text(
                  'تحميل...',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 15),
                ),
              ],
            ),
          ),
        ],
      ),
      error: (err, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.red.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 20, color: Colors.red.shade700),
                const SizedBox(width: 8),
                Text(
                  'خطأ في التحميل',
                  style: TextStyle(color: Colors.red.shade900, fontSize: 15),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(smartSyncStatusProvider);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // Header with sync button
          Row(
            children: [
              const Text(
                'لوحة التحكم - نظام إدارة الفندق',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              _buildEnhancedSyncButton(context, statusAsync),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Smart Sync Status Card
          const SmartSyncDashboardCard(),
          
          const SizedBox(height: 16),
          
          // Statistics Cards - بطاقات أصغر مع إحصائيات مفيدة أكثر
          _buildStatisticsCards(),
          
          const SizedBox(height: 24),
          
          // Rooms Status Section
          Consumer(
            builder: (context, ref, _) {
              final roomsAsync = ref.watch(roomsListProvider);

              return roomsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Center(child: Text('خطأ: $e')),
                data: (rooms) => _buildRoomsStatusSection(context, rooms),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsCards() {
    final currencyFmt = NumberFormat('#,##0', 'en_US');
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.0, // تصغير البطاقات
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: [
        // نسبة الإشغال
        Consumer(
          builder: (context, ref, _) {
            final roomsAsync = ref.watch(roomsListProvider);
            return roomsAsync.when(
              loading: () => const _LoadingStatCard(
                title: 'نسبة الإشغال',
                icon: Icons.pie_chart,
                color: Colors.orange,
              ),
              error: (e, _) => _StatCard(
                title: 'نسبة الإشغال',
                value: 'خطأ',
                icon: Icons.pie_chart,
                color: Colors.orange,
              ),
              data: (rooms) {
                final totalRooms = rooms.length;
                final occupiedRooms = rooms.where((r) => StatusUtils.isRoomOccupied(r.status)).length;
                final occupancyRate = totalRooms > 0 ? ((occupiedRooms / totalRooms) * 100).round() : 0;
                return _StatCard(
                  title: 'نسبة الإشغال',
                  value: '$occupancyRate%',
                  icon: Icons.pie_chart,
                  color: Colors.orange,
                );
              },
            );
          },
        ),

        // المدفوعات اليومية
        Consumer(
          builder: (context, ref, _) {
            final paymentsAsync = ref.watch(todayPaymentsProvider);
            return paymentsAsync.when(
              loading: () => const _LoadingStatCard(
                title: 'مدفوعات اليوم',
                icon: Icons.payments,
                color: Colors.green,
              ),
              error: (e, _) => const _StatCard(
                title: 'مدفوعات اليوم',
                value: 'خطأ',
                icon: Icons.payments,
                color: Colors.green,
              ),
              data: (total) => _StatCard(
                title: 'مدفوعات اليوم',
                value: currencyFmt.format(total),
                icon: Icons.payments,
                color: Colors.green,
              ),
            );
          },
        ),

        // المصروفات اليومية
        Consumer(
          builder: (context, ref, _) {
            final expensesAsync = ref.watch(todayExpensesProvider);
            return expensesAsync.when(
              loading: () => const _LoadingStatCard(
                title: 'مصروفات اليوم',
                icon: Icons.money_off,
                color: Colors.red,
              ),
              error: (e, _) => const _StatCard(
                title: 'مصروفات اليوم',
                value: 'خطأ',
                icon: Icons.money_off,
                color: Colors.red,
              ),
              data: (total) => _StatCard(
                title: 'مصروفات اليوم',
                value: currencyFmt.format(total),
                icon: Icons.money_off,
                color: Colors.red,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ExpensesReportScreen()),
                ),
              ),
            );
          },
        ),

        // الغرف المحجوزة
        Consumer(
          builder: (context, ref, _) {
            final roomsAsync = ref.watch(roomsListProvider);
            return roomsAsync.when(
              loading: () => const _LoadingStatCard(
                title: 'الغرف المحجوزة',
                icon: Icons.bed,
                color: Colors.blue,
              ),
              error: (e, _) => const _StatCard(
                title: 'الغرف المحجوزة',
                value: 'خطأ',
                icon: Icons.bed,
                color: Colors.blue,
              ),
              data: (rooms) {
                final occupiedRooms = rooms.where((r) => StatusUtils.isRoomOccupied(r.status)).length;
                return _StatCard(
                  title: 'الغرف المحجوزة',
                  value: occupiedRooms.toString(),
                  icon: Icons.bed,
                  color: Colors.blue,
                );
              },
            );
          },
        ),
      ],
    );
  }
  
  Widget _buildRoomsStatusSection(BuildContext context, List<Room> rooms) {
    final Map<String, Room> roomsMap = {for (final room in rooms) room.roomNumber: room};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'حالة الغرف',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8, // تقليل المسافات
              runSpacing: 8,
              children: _dashboardRoomNumbers.map((roomNumber) {
                final room = roomsMap[roomNumber];
                final bool isOccupied = room != null && StatusUtils.isRoomOccupied(room.status);
                final bool isAvailable = room != null && StatusUtils.isRoomAvailable(room.status);
                final bool isNewRoom = roomNumber == '503' || roomNumber == '504';
                final Color backgroundColor = isOccupied
                    ? Colors.red.shade600
                    : (isAvailable 
                        ? Colors.green.shade600 
                        : (isNewRoom 
                            ? Colors.blue.shade400  // لون أزرق للغرف الجديدة
                            : Colors.grey.shade500));
                final bool useDarkText = backgroundColor.computeLuminance() > 0.5;
                final Color foregroundColor = useDarkText ? Colors.black : Colors.white;
                final String tooltipText = room != null 
                    ? room.status 
                    : (roomNumber == '503' || roomNumber == '504') 
                        ? 'غرفة جديدة - قيد التجهيز'
                        : 'غير مسجل في النظام';

                return Tooltip(
                  message: tooltipText,
                  child: SizedBox(
                    width: 60, // تصغير الأزرار
                    child: ElevatedButton(
                      onPressed: () => _handleRoomTap(context, roomNumber, room),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: backgroundColor,
                        foregroundColor: foregroundColor,
                        minimumSize: const Size(60, 40), // تصغير الحجم
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14, // تصغير الخط
                        ),
                      ),
                      child: Text(roomNumber),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
  
  /// التعامل مع الضغط على أزرار الغرف
  void _handleRoomTap(BuildContext context, String roomNumber, Room? room) async {
    if (roomNumber == '503' || roomNumber == '504') {
      _showNewRoomDialog(context, roomNumber);
    } else if (room != null) {
      final isAvailable = StatusUtils.isRoomAvailable(room.status);
      final isOccupied = StatusUtils.isRoomOccupied(room.status);
      
      if (isAvailable) {
        _navigateToNewBooking(context, roomNumber);
      } else if (isOccupied) {
        await _navigateToPaymentForRoom(context, roomNumber);
      } else {
        _showRoomDetailsDialog(context, room);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('الغرفة $roomNumber غير مسجلة في النظام'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
  
  /// الانتقال إلى شاشة حجز جديد مع رقم الغرفة المحدد
  void _navigateToNewBooking(BuildContext context, String roomNumber) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => BookingEditScreen(
          initialRoomNumber: roomNumber,
        ),
      ),
    );
  }
  
  /// الانتقال إلى شاشة إضافة دفعة للغرفة المحجوزة
  Future<void> _navigateToPaymentForRoom(BuildContext context, String roomNumber) async {
    try {
      final bookingsRepo = ref.read(bookingsRepoProvider);
      
      // البحث عن الحجز النشط للغرفة
      final activeBooking = await bookingsRepo.getActiveBookingForRoom(roomNumber);
      
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
      
      // الانتقال لشاشة إضافة دفعة
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => BookingPaymentScreen(
              booking: activeBooking,
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل الحجز: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  /// الانتقال إلى قائمة الحجوزات لغرفة محددة
  void _navigateToBookingsForRoom(BuildContext context, String roomNumber) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const BookingsListScreen(),
      ),
    );
  }
  
  /// إظهار حوار للغرف الجديدة 503 و 504
  void _showNewRoomDialog(BuildContext context, String roomNumber) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('الغرفة $roomNumber'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.hotel,
              size: 48,
              color: Colors.blue,
            ),
            const SizedBox(height: 16),
            const Text(
              'غرفة جديدة قيد التجهيز',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text('نوع الغرفة: سرير فردي'),
            const Text('السعر المتوقع: 7,000 ريال'),
            const Text('الحالة: قيد التجهيز'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: const Text(
                '💡 هذه الغرفة متوفرة في الواجهة فقط ولم تُضف إلى قاعدة البيانات بعد.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.blue,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('موافق'),
          ),
        ],
      ),
    );
  }
  
  /// إظهار تفاصيل الغرف الموجودة
  void _showRoomDetailsDialog(BuildContext context, Room room) {
    final isOccupied = StatusUtils.isRoomOccupied(room.status);
    final statusColor = isOccupied ? Colors.red : Colors.green;
    final statusIcon = isOccupied ? Icons.person : Icons.person_outline;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('الغرفة ${room.roomNumber}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 24),
                const SizedBox(width: 8),
                Text(
                  room.status,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('نوع الغرفة: ${room.type}'),
            Text('السعر: ${CurrencyFormatter.formatAmount(room.price)} ريال'),
          ],
        ),
        actions: [
          if (isOccupied)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _navigateToBookingsForRoom(context, room.roomNumber);
              },
              child: const Text('عرض الحجز'),
            ),
          if (!isOccupied)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _navigateToNewBooking(context, room.roomNumber);
              },
              child: const Text('حجز جديد'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12), // تقليل padding
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: color), // تصغير الأيقونة
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16, // تصغير الخط
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12, // تصغير الخط
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingStatCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  
  const _LoadingStatCard({
    required this.title,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 4),
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}