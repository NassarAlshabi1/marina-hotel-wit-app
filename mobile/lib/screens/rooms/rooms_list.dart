import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../services/sync_service.dart';
import '../../services/local_db.dart';
import '../../utils/currency_formatter.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as d;
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../../providers/auth_provider.dart';
import '../../mixins/sync_on_exit_mixin.dart';
import '../../services/screen_sync_controller.dart';

Future<ImagePicker> _lazyPicker() async => ImagePicker();

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
    final canRooms = auth.currentUser?.permissions.contains('all') == true ||
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
            )
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
                  subtitle: Text('السعر: ${CurrencyFormatter.formatAmount(r.price)} • الحالة: ${r.status}'),
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

  Future<void> _editRoom(BuildContext context, WidgetRef ref, {Room? existing}) async {
    final roomNumberCtrl = TextEditingController(text: existing?.roomNumber ?? '');
    final typeCtrl = TextEditingController(text: existing?.type ?? '');
    final priceCtrl = TextEditingController(text: existing != null ? CurrencyFormatter.formatAmount(existing.price) : '');
    String status = existing?.status ?? 'شاغرة';

    String? imageUrl = existing?.imageUrl;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(existing == null ? 'إضافة غرفة' : 'تعديل غرفة'),
          content: SingleChildScrollView(
            child: Column(children: [
              TextField(controller: roomNumberCtrl, decoration: const InputDecoration(labelText: 'رقم الغرفة'), readOnly: existing != null),
              TextField(controller: typeCtrl, decoration: const InputDecoration(labelText: 'النوع')),
              TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: 'السعر'), keyboardType: TextInputType.number),
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
              if (imageUrl != null) Image.network(imageUrl!, height: 120, fit: BoxFit.cover),
              TextButton.icon(
                onPressed: () async {
                  final picker = ImagePicker();
                  final img = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
                  if (img != null) {
                    imageUrl = img.path;
                    (ctx as Element).markNeedsBuild();
                  }
                },
                icon: const Icon(Icons.image),
                label: const Text('اختر صورة'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final repo = ref.read(roomsRepoProvider);
    if (existing == null) {
      await repo.create(
        roomNumber: roomNumberCtrl.text.trim(),
        type: typeCtrl.text.trim(),
        price: CurrencyFormatter.parseAmount(priceCtrl.text) ?? 0,
        status: status,
        imageUrl: imageUrl,
      );
    } else {
      await repo.updateByRoomNumber(
        existing.roomNumber,
        type: typeCtrl.text.trim(),
        price: CurrencyFormatter.parseAmount(priceCtrl.text) ?? 0,
        status: status,
        imageUrl: imageUrl,
      );
    }
    markDataChanged();
  }

  Future<void> _uploadImage(BuildContext context, String roomNumber) async {
    try {
      final picker = await _lazyPicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
      if (picked == null) return;
      final url = await ApiService.I.uploadRoomImage(roomNumber, picked.path);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(url != null ? 'تم رفع الصورة' : 'فشل رفع الصورة')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    }
  }
}
