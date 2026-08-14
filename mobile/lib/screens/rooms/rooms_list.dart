// ignore_for_file: use_build_context_synchronously
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../mixins/sync_on_exit_mixin.dart';
import '../../providers/appwrite_providers.dart';
import '../../providers/auth_provider.dart';
import '../../providers/repository_providers.dart';
import '../../providers/room_payment_status_provider.dart'; // استيراد البروفايدر الجديد
import '../../services/local_db.dart';
import '../../services/price_adjustment_service.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/performance_config.dart';
import '../../utils/status_utils.dart';
import '../../utils/theme.dart';

class RoomsListScreen extends ConsumerStatefulWidget {
  const RoomsListScreen({super.key});

  @override
  ConsumerState<RoomsListScreen> createState() => _RoomsListScreenState();
}

class _RoomsListScreenState extends ConsumerState<RoomsListScreen>
    with SyncOnExitMixin {
  @override
  String get screenId => 'rooms_list';

  bool _isGridView = true;

  Map<String, List<RoomWithPaymentStatus>> _groupByFloor(
    List<RoomWithPaymentStatus> rooms,
  ) {
    final Map<String, List<RoomWithPaymentStatus>> floorMap = {};
    for (final roomData in rooms) {
      String floorNumber = '0';
      if (roomData.room.roomNumber.isNotEmpty) {
        floorNumber = roomData.room.roomNumber[0];
      }
      floorMap.putIfAbsent(floorNumber, () => []).add(roomData);
    }
    for (final floor in floorMap.keys) {
      floorMap[floor]!.sort((a, b) {
        final aNum = int.tryParse(a.room.roomNumber);
        final bNum = int.tryParse(b.room.roomNumber);
        if (aNum != null && bNum != null) {
          return aNum.compareTo(bNum);
        }
        return a.room.roomNumber.compareTo(b.room.roomNumber);
      });
    }
    return floorMap;
  }

  @override
  Widget build(BuildContext context) {
    // استخدام البروفايدر المدمج
    final roomsStream = ref.watch(roomsWithPaymentStatusProvider);
    final auth = ref.watch(authProvider);
    final canRooms =
        (auth.currentUser?.permissions.contains('all') ?? false) ||
        auth.currentUser?.userType == 'admin' ||
        (auth.currentUser?.permissions.contains('rooms') ?? false);

    return wrapWithSyncOnExit(
      child: AppScaffold(
        title: 'إدارة الغرف',
        actions: [
          IconButton(
            onPressed: () => setState(() => _isGridView = !_isGridView),
            icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
            tooltip: _isGridView ? 'عرض قائمة' : 'عرض شبكي',
          ),
          if (canRooms)
            IconButton(
              onPressed: () => _editRoom(context, ref),
              icon: const Icon(Icons.add),
              tooltip: 'إضافة غرفة',
            ),
        ],
        body: roomsStream.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text('خطأ: $e', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () =>
                      ref.invalidate(roomsWithPaymentStatusProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
          data: (rooms) {
            if (rooms.isEmpty) {
              return _buildEmptyState(canRooms);
            }

            return _isGridView
                ? _buildGridView(rooms, canRooms)
                : _buildListView(rooms, canRooms);
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool canAdd) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(50),
            ),
            child: Icon(
              Icons.hotel,
              size: 50,
              color: AppColors.primaryColor.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'لا توجد غرف مسجلة',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'ابدأ بإضافة الغرف لإدارة الفندق',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          if (canAdd) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _editRoom(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('إضافة غرفة'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGridView(List<RoomWithPaymentStatus> rooms, bool canEdit) {
    final floorMap = _groupByFloor(rooms);
    final sortedFloors = floorMap.keys.toList()..sort();

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(roomsWithPaymentStatusProvider);
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollCacheExtent: optimizedScrollCacheExtent,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: false,
        itemCount: sortedFloors.length,
        itemBuilder: (context, index) {
          final floorNumber = sortedFloors[index];
          final floorRooms = floorMap[floorNumber]!;
          // ✅ حساب الغرف المتاحة بناءً على الحجز النشط بدلاً من room.status المخزن
          final availableCount = floorRooms
              .where(
                (r) =>
                    !r.hasActiveBooking &&
                    r.room.status != 'صيانة' &&
                    r.room.status != 'maintenance',
              )
              .length;

          return RepaintBoundary(
            child: _FloorExpansionTile(
              floorNumber: floorNumber,
              totalRooms: floorRooms.length,
              availableRooms: availableCount,
              // لا نفتتح أكثر من طابق واحد في ملف 1GB لتقليل بناء GridView.
              initiallyExpanded: !isLowEndDevice && index < 2,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: MediaQuery.of(context).size.width > 600
                          ? 5
                          : 3,
                      childAspectRatio: 0.85,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: floorRooms.length,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: false,
                    itemBuilder: (context, i) {
                      final roomData = floorRooms[i];
                      return RepaintBoundary(
                        child: _RoomGridCard(
                          roomData: roomData,
                          onTap: () => _showRoomActions(
                            context,
                            ref,
                            roomData.room,
                            canEdit,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildListView(List<RoomWithPaymentStatus> rooms, bool canEdit) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(roomsWithPaymentStatusProvider);
      },
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        scrollCacheExtent: optimizedScrollCacheExtent,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: false,
        itemCount: rooms.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final roomData = rooms[index];
          return RepaintBoundary(
            child: _RoomListCard(
              roomData: roomData,
              onTap: () =>
                  _showRoomActions(context, ref, roomData.room, canEdit),
              onEdit: canEdit
                  ? () => _editRoom(context, ref, existing: roomData.room)
                  : null,
            ),
          );
        },
      ),
    );
  }

  void _showRoomActions(
    BuildContext context,
    WidgetRef ref,
    Room room,
    bool canEdit,
  ) {
    final isAvailable = StatusUtils.isRoomAvailable(room.status);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              _buildRoomHeader(room, isAvailable),
              const Divider(),
              if (canEdit) ...[
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.edit,
                      color: AppColors.primaryColor,
                    ),
                  ),
                  title: const Text('تعديل الغرفة'),
                  subtitle: const Text('تغيير السعر والنوع والحالة'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _editRoom(context, ref, existing: room);
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:
                          (isAvailable
                                  ? AppColors.dangerColor
                                  : AppColors.successColor)
                              .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isAvailable ? Icons.block : Icons.check_circle,
                      color: isAvailable
                          ? AppColors.dangerColor
                          : AppColors.successColor,
                    ),
                  ),
                  title: Text(
                    isAvailable ? 'تحويل إلى محجوزة' : 'تحويل إلى شاغرة',
                  ),
                  subtitle: const Text('تغيير حالة الغرفة بسرعة'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _quickStatusChange(
                      room,
                      isAvailable ? 'محجوزة' : 'شاغرة',
                    );
                  },
                ),
              ],
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.infoColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.info_outline,
                    color: AppColors.infoColor,
                  ),
                ),
                title: const Text('تفاصيل الغرفة'),
                subtitle: const Text('عرض المعلومات الكاملة'),
                onTap: () {
                  Navigator.pop(ctx);
                  // هنا يمكن فتح شاشة التفاصيل
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoomHeader(Room room, bool isAvailable) {
    final color = isAvailable ? AppColors.successColor : AppColors.dangerColor;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.hotel, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'غرفة ${room.roomNumber}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  room.type.isEmpty ? 'غرفة فندقية' : room.type,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              room.status, // ✅ room.status سيكون صحيحاً بعد refreshAllRoomOccupancy
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _quickStatusChange(Room room, String newStatus) async {
    final repo = ref.read(roomsRepoProvider);
    // ✅ منع تحويل غرفة لشاغرة إذا كان عليها حجز نشط
    if (newStatus == 'شاغرة') {
      final bookingsRepo = ref.read(bookingsRepoProvider);
      final activeBooking = await bookingsRepo.getActiveBookingForRoom(
        room.roomNumber,
      );
      if (activeBooking != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'لا يمكن تحويل الغرفة ${room.roomNumber}: يوجد حجز نشط (${activeBooking.guestName})',
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }
    await repo.updateByRoomNumber(room.roomNumber, status: newStatus);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم تغيير حالة الغرفة ${room.roomNumber} إلى $newStatus',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _editRoom(
    BuildContext context,
    WidgetRef ref, {
    Room? existing,
  }) async {
    final formKey = GlobalKey<FormState>();
    final roomNumberCtrl = TextEditingController(
      text: existing?.roomNumber ?? '',
    );
    final typeCtrl = TextEditingController(text: existing?.type ?? '');
    final priceCtrl = TextEditingController(
      text: existing?.price.toString() ?? '',
    );
    String status = existing?.status ?? 'شاغرة';
    final String? imageUrl = existing?.imageUrl;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  existing == null ? Icons.add : Icons.edit,
                  color: AppColors.primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                existing == null
                    ? 'إضافة غرفة جديدة'
                    : 'تعديل غرفة ${existing.roomNumber}',
              ),
            ],
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: roomNumberCtrl,
                    decoration: InputDecoration(
                      labelText: 'رقم الغرفة',
                      prefixIcon: const Icon(Icons.meeting_room),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    readOnly: existing != null,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'أدخل رقم الغرفة';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: typeCtrl,
                    decoration: InputDecoration(
                      labelText: 'نوع الغرفة',
                      prefixIcon: const Icon(Icons.category),
                      hintText: 'مثال: فردية، مزدوجة، جناح',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: priceCtrl,
                    decoration: InputDecoration(
                      labelText: 'السعر لليلة',
                      prefixIcon: const Icon(Icons.attach_money),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'أدخل السعر';
                      }
                      final price = CurrencyFormatter.parseAmount(v);
                      if (price == null || price <= 0) {
                        return 'أدخل سعراً صحيحاً';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  StatefulBuilder(
                    builder: (context, setLocalState) =>
                        DropdownButtonFormField<String>(
                          initialValue: status,
                          decoration: InputDecoration(
                            labelText: 'الحالة',
                            prefixIcon: const Icon(Icons.toggle_on),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'شاغرة',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    color: AppColors.successColor,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text('شاغرة'),
                                ],
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'محجوزة',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.block,
                                    color: AppColors.dangerColor,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text('محجوزة'),
                                ],
                              ),
                            ),
                          ],
                          onChanged: (v) =>
                              setLocalState(() => status = v ?? status),
                        ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.pop(ctx, true);
                }
              },
              icon: const Icon(Icons.save),
              label: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) {
      // ✅ إصلاح تسرب ذاكرة: dispose المتحكمات عند الإلغاء
      roomNumberCtrl.dispose();
      typeCtrl.dispose();
      priceCtrl.dispose();
      return;
    }

    final repo = ref.read(roomsRepoProvider);
    final newPrice = CurrencyFormatter.parseAmount(priceCtrl.text) ?? 0;

    try {
      if (existing == null) {
        await repo.create(
          roomNumber: roomNumberCtrl.text.trim(),
          type: typeCtrl.text.trim(),
          price: newPrice,
          status: status,
          imageUrl: imageUrl,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تمت إضافة الغرفة ${roomNumberCtrl.text.trim()}'),
              backgroundColor: AppColors.successColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        final oldPrice = existing.price;
        final priceChanged = (oldPrice - newPrice).abs() > 0.01;

        await repo.updateByRoomNumber(
          existing.roomNumber,
          type: typeCtrl.text.trim(),
          price: newPrice,
          status: status,
          imageUrl: imageUrl,
        );

        if (priceChanged && context.mounted) {
          await _handlePriceChange(
            context,
            ref,
            roomNumber: existing.roomNumber,
            oldPrice: oldPrice,
            newPrice: newPrice,
          );
        }
      }
      markDataChanged();
      // ✅ رفع فوري لغرفة جديدة/محدَّثة إلى Appwrite Cloud.
      unawaited(ref.read(appwriteSyncManagerProvider).pushLocalChanges());
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل حفظ الغرفة: $e'),
          backgroundColor: Colors.red.shade900,
        ),
      );
    } finally {
      // ✅ إصلاح تسرب ذاكرة: dispose المتحكمات دائماً
      roomNumberCtrl.dispose();
      typeCtrl.dispose();
      priceCtrl.dispose();
    }
  }

  Future<void> _handlePriceChange(
    BuildContext context,
    WidgetRef ref, {
    required String roomNumber,
    required double oldPrice,
    required double newPrice,
  }) async {
    final db = ref.read(databaseProvider);
    final service = PriceAdjustmentService(db);

    final preview = await service.previewPriceChange(
      roomNumber: roomNumber,
      newPrice: newPrice,
    );

    final affectedBookings = preview['bookingsAffected'] as int;
    if (affectedBookings == 0) {
      return;
    }

    if (!context.mounted) {
      return;
    }

    final totalDiff = preview['totalDifference'] as double;
    final nightsAffected = preview['totalNightsAffected'] as int;

    final apply = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.warningColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.price_change,
                  color: AppColors.warningColor,
                ),
              ),
              const SizedBox(width: 12),
              const Text('تطبيق السعر الجديد؟'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Column(
                      children: [
                        const Text(
                          'السعر القديم',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          CurrencyFormatter.formatAmount(oldPrice),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Icon(Icons.arrow_forward, color: Colors.grey[400]),
                    ),
                    Column(
                      children: [
                        const Text(
                          'السعر الجديد',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          CurrencyFormatter.formatAmount(newPrice),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: newPrice > oldPrice
                                ? AppColors.successColor
                                : AppColors.dangerColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildImpactRow(
                Icons.book,
                'الحجوزات المتأثرة',
                affectedBookings.toString(),
              ),
              _buildImpactRow(
                Icons.nightlight,
                'الليالي المتأثرة',
                nightsAffected.toString(),
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'الفرق الإجمالي:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${totalDiff >= 0 ? "+" : ""}${CurrencyFormatter.formatAmount(totalDiff)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: totalDiff >= 0
                          ? AppColors.successColor
                          : AppColors.dangerColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تطبيق على الحجوزات'),
            ),
          ],
        ),
      ),
    );

    if (apply ?? false) {
      final auth = ref.read(authProvider);
      final userName =
          auth.currentUser?.name ?? auth.currentUser?.username ?? 'موظف';

      await service.applyRoomPriceChange(
        roomNumber: roomNumber,
        oldPrice: oldPrice,
        newPrice: newPrice,
        appliedBy: userName,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تحديث أسعار الحجوزات بنجاح'),
            backgroundColor: AppColors.successColor,
          ),
        );
      }
    }
  }

  Widget _buildImpactRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _FloorExpansionTile extends StatelessWidget {
  const _FloorExpansionTile({
    required this.floorNumber,
    required this.totalRooms,
    required this.availableRooms,
    required this.children,
    this.initiallyExpanded = false,
  });
  final String floorNumber;
  final int totalRooms;
  final int availableRooms;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        title: Text(
          'الطابق $floorNumber',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text(
          'إجمالي: $totalRooms | شاغر: $availableRooms',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.apartment,
            color: AppColors.primaryColor,
            size: 20,
          ),
        ),
        children: children,
      ),
    );
  }
}

class _RoomGridCard extends StatelessWidget {
  const _RoomGridCard({required this.roomData, required this.onTap});
  final RoomWithPaymentStatus roomData; // تغيير النوع
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final room = roomData.room;
    // ✅ استخدام displayStatus المشتق من الحجز النشط بدلاً من room.status المخزن
    final isAvailable =
        !roomData.hasActiveBooking &&
        room.status != 'صيانة' &&
        room.status != 'maintenance';
    // استخدام اللون التلقائي من الموديل
    final cardColor = roomData.roomColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: cardColor.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: cardColor.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cardColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isAvailable ? Icons.hotel : Icons.hotel_outlined,
                  color: cardColor,
                  size: 20,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                room.roomNumber,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: cardColor,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cardColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  roomData.displayStatus,
                  style: TextStyle(
                    fontSize: 9,
                    color: cardColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (room.type.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  room.type,
                  style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomListCard extends StatelessWidget {
  const _RoomListCard({
    required this.roomData,
    required this.onTap,
    this.onEdit,
  });
  final RoomWithPaymentStatus roomData; // تغيير النوع
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final room = roomData.room;
    // ✅ استخدام displayStatus المشتق من الحجز النشط بدلاً من room.status المخزن
    final isAvailable =
        !roomData.hasActiveBooking &&
        room.status != 'صيانة' &&
        room.status != 'maintenance';
    // استخدام اللون التلقائي من الموديل
    final statusColor = roomData.roomColor;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Center(
                  child: Text(
                    room.roomNumber,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: statusColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'غرفة ${room.roomNumber}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        if (room.type.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.infoColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              room.type,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.infoColor,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.attach_money,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          CurrencyFormatter.formatAmount(room.price),
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isAvailable ? Icons.check_circle : Icons.block,
                      size: 14,
                      color: statusColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      roomData.displayStatus,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (onEdit != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit, size: 20),
                  color: AppColors.primaryColor,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primaryColor.withValues(
                      alpha: 0.1,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
