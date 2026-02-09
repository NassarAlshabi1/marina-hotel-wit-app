import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart';
import '../../services/price_adjustment_service.dart';
import '../../utils/currency_formatter.dart';

import '../../providers/auth_provider.dart';
import '../../mixins/sync_on_exit_mixin.dart';
import '../../providers/core_providers.dart';

class RoomsListScreen extends ConsumerStatefulWidget {
  const RoomsListScreen({super.key});

  @override
  ConsumerState<RoomsListScreen> createState() => _RoomsListScreenState();
}

class _RoomsListScreenState extends ConsumerState<RoomsListScreen>
    with SyncOnExitMixin {
  @override
  String get screenId => 'rooms_list';

  @override
  Widget build(BuildContext context) {
    final roomsStream = ref.watch(roomsListProvider);
    final auth = ref.watch(authProvider);
    final canRooms =
        auth.currentUser?.permissions.contains('all') == true ||
        auth.currentUser?.userType == 'admin' ||
        (auth.currentUser?.permissions.contains('rooms') ?? false);
    return wrapWithSyncOnExit(
      child: AppScaffold(
        title: 'الغرف',
        actions: [
          if (canRooms)
            IconButton(
              onPressed: () async {
                await _editRoom(context, ref);
              },
              icon: const Icon(Icons.add),
            ),
        ],
        body: roomsStream.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('خطأ: $e')),
          data: (rooms) {
            return ListView.builder(
              itemCount: rooms.length,
              itemBuilder: (c, i) {
                final r = rooms[i];
                return ListTile(
                  title: Text('${r.roomNumber} • ${r.type}'),
                  subtitle: Text(
                    'السعر: ${CurrencyFormatter.formatAmount(r.price)} • الحالة: ${r.status}',
                  ),
                  trailing: canRooms
                      ? IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _editRoom(context, ref, existing: r),
                        )
                      : null,
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _editRoom(
    BuildContext context,
    WidgetRef ref, {
    Room? existing,
  }) async {
    final roomNumberCtrl = TextEditingController(
      text: existing?.roomNumber ?? '',
    );
    final typeCtrl = TextEditingController(text: existing?.type ?? '');
    final priceCtrl = TextEditingController(
      text: existing != null
          ? CurrencyFormatter.formatAmount(existing.price)
          : '',
    );
    String status = existing?.status ?? 'شاغرة';

    final imageUrl = existing?.imageUrl;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(existing == null ? 'إضافة غرفة' : 'تعديل غرفة'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: roomNumberCtrl,
                  decoration: const InputDecoration(labelText: 'رقم الغرفة'),
                  readOnly: existing != null,
                ),
                TextField(
                  controller: typeCtrl,
                  decoration: const InputDecoration(labelText: 'النوع'),
                ),
                TextField(
                  controller: priceCtrl,
                  decoration: const InputDecoration(labelText: 'السعر'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: status,
                  items: const [
                    DropdownMenuItem(value: 'شاغرة', child: Text('شاغرة')),
                    DropdownMenuItem(value: 'محجوزة', child: Text('محجوزة')),
                  ],
                  onChanged: (v) => status = v ?? status,
                  decoration: const InputDecoration(labelText: 'الحالة'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final repo = ref.read(roomsRepoProvider);
    final newPrice = CurrencyFormatter.parseAmount(priceCtrl.text) ?? 0;
    
    if (existing == null) {
      await repo.create(
        roomNumber: roomNumberCtrl.text.trim(),
        type: typeCtrl.text.trim(),
        price: newPrice,
        status: status,
        imageUrl: imageUrl,
      );
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
  }

  Future<void> _handlePriceChange(
    BuildContext context,
    WidgetRef ref, {
    required String roomNumber,
    required double oldPrice,
    required double newPrice,
  }) async {
    final db = ref.read(dbProvider);
    final service = PriceAdjustmentService(db);
    
    final preview = await service.previewPriceChange(
      roomNumber: roomNumber,
      newPrice: newPrice,
    );
    
    final affectedBookings = preview['bookingsAffected'] as int;
    if (affectedBookings == 0) return;
    
    if (!context.mounted) return;
    
    final totalDiff = preview['totalDifference'] as double;
    final nightsAffected = preview['totalNightsAffected'] as int;
    
    final apply = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تطبيق السعر الجديد؟'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'تغيّر السعر من ${CurrencyFormatter.formatAmount(oldPrice)} '
                'إلى ${CurrencyFormatter.formatAmount(newPrice)}',
              ),
              const SizedBox(height: 12),
              Text('الحجوزات النشطة المتأثرة: $affectedBookings'),
              Text('الليالي المتأثرة: $nightsAffected'),
              const SizedBox(height: 8),
              Text(
                'الفرق الإجمالي: ${totalDiff >= 0 ? "+" : ""}'
                '${CurrencyFormatter.formatAmount(totalDiff)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: totalDiff >= 0 ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'هل تريد تطبيق السعر الجديد على الليالي القادمة؟',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('لا، إبقاء السعر القديم'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('نعم، تطبيق السعر الجديد'),
            ),
          ],
        ),
      ),
    );
    
    if (apply == true && context.mounted) {
      final auth = ref.read(authProvider);
      final appliedBy = auth.currentUser?.name ?? 'unknown';
      
      final result = await service.applyRoomPriceChange(
        roomNumber: roomNumber,
        oldPrice: oldPrice,
        newPrice: newPrice,
        appliedBy: appliedBy,
        reason: 'تعديل السعر من شاشة الغرف',
      );
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.success
                  ? 'تم تحديث ${result.nightsUpdated} ليلة في '
                    '${result.bookingsAffected} حجز'
                  : 'خطأ: ${result.error}',
            ),
            backgroundColor: result.success ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }
}
