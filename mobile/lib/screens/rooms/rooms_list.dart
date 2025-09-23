import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../providers/core_providers.dart';
import '../../providers/core_providers.dart' as coreProviders;
import '../../services/local_db.dart';
import '../../services/sync_service.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as d;
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';

Future<ImagePicker> _lazyPicker() async => ImagePicker();

class RoomsListScreen extends ConsumerWidget {
  const RoomsListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(coreProviders.dbProvider);
    return AppScaffold(
      title: 'الغرف',
      actions: [
        IconButton(
          onPressed: () => ref.read(coreProviders.syncProvider).runSync(),
          icon: const Icon(Icons.sync),
        ),
        IconButton(
          onPressed: () async {
            await _editRoom(context, ref, db);
          },
          icon: const Icon(Icons.add),
        )
      ],
      body: StreamBuilder(
        stream: db.select(db.rooms).watch(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final rooms = snapshot.data!;
          return ListView.builder(
            itemCount: rooms.length,
            itemBuilder: (c, i) {
              final r = rooms[i];
              return ListTile(
                title: Text('${r.roomNumber} • ${r.type}'),
                subtitle: Text('السعر: ${r.price.toStringAsFixed(2)} • الحالة: ${r.status}'),
                trailing: Wrap(spacing: 8, children: [
                  IconButton(
                    icon: const Icon(Icons.camera_alt),
                    onPressed: () async {
                      await _uploadImage(context, r.roomNumber);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _editRoom(context, ref, db, existing: r),
                  ),
                ]),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _editRoom(BuildContext context, WidgetRef ref, AppDatabase db, {RoomsData? existing}) async {
    final roomNumberCtrl = TextEditingController(text: existing?.roomNumber ?? '');
    final typeCtrl = TextEditingController(text: existing?.type ?? '');
    final priceCtrl = TextEditingController(text: existing?.price.toString() ?? '');
    String status = existing?.status ?? 'شاغرة';

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

    final uuid = const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final comp = RoomsCompanion(
      localUuid: d.Value(uuid),
      serverId: const d.Value(null),
      lastModified: d.Value(now),
      deletedAt: const d.Value(null),
      version: const d.Value(1),
      origin: const d.Value('local'),
      roomNumber: d.Value(roomNumberCtrl.text.trim()),
      type: d.Value(typeCtrl.text.trim()),
      price: d.Value(double.tryParse(priceCtrl.text) ?? 0),
      status: d.Value(status),
    );

    if (existing == null) {
      await db.into(db.rooms).insert(comp);
      await ref.read(coreProviders.syncProvider).queueChange(
            entity: 'rooms',
            op: 'create',
            localUuid: uuid,
            data: {
              'room_number': roomNumberCtrl.text.trim(),
              'type': typeCtrl.text.trim(),
              'price': double.tryParse(priceCtrl.text) ?? 0,
              'status': status,
            },
          );
    } else {
      // update existing: insert new row version and queue update
      await (db.update(db.rooms)..where((t) => t.localUuid.equals(existing.localUuid))).write(comp);
      await ref.read(coreProviders.syncProvider).queueChange(
            entity: 'rooms',
            op: 'update',
            localUuid: existing.localUuid,
            data: {
              'room_number': roomNumberCtrl.text.trim(),
              'type': typeCtrl.text.trim(),
              'price': double.tryParse(priceCtrl.text) ?? 0,
              'status': status,
            },
          );
    }
  }

  Future<void> _uploadImage(BuildContext context, String roomNumber) async {
    try {
      // pick image
      // Lazy import to keep file concise
      // ignore: depend_on_referenced_packages
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
