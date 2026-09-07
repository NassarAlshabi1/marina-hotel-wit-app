import 'package:drift/drift.dart' as d;

import '../../utils/id.dart';
import '../adapters/adapter_registry.dart';
import '../appwrite_sync_manager.dart';
import '../daos/outbox_dao.dart';
import '../local_db.dart';

class InventoryRepository {
  InventoryRepository(this.db, [AdapterRegistry? registry])
    : outbox = OutboxDao(db, registry ?? AdapterRegistry.testing(db));

  final AppDatabase db;
  final OutboxDao outbox;

  Stream<List<InventoryItem>> watchActiveItems() {
    return (db.select(db.inventoryItems)
          ..where((item) => item.isActive.equals(true))
          ..orderBy([(item) => d.OrderingTerm.asc(item.name)]))
        .watch();
  }

  Stream<List<InventoryTransaction>> watchTransactions(int itemId) {
    return (db.select(db.inventoryTransactions)
          ..where((movement) => movement.itemId.equals(itemId))
          ..orderBy([(movement) => d.OrderingTerm.desc(movement.createdAt)]))
        .watch();
  }

  Future<int> createItem({
    required String name,
    required String unit,
    required int initialQuantity, required int minimumQuantity, String? category,
  }) async {
    if (name.trim().isEmpty) throw ArgumentError('اسم الصنف مطلوب');
    if (initialQuantity < 0 || minimumQuantity < 0) {
      throw ArgumentError('الكميات لا يمكن أن تكون سالبة');
    }

    final now = _nowEpoch;
    final localUuid = _newUuid;
    return db.transaction(() async {
      final itemId = await db
          .into(db.inventoryItems)
          .insert(
            InventoryItemsCompanion.insert(
              name: name.trim(),
              localUuid: localUuid,
              unit: d.Value(unit.trim().isEmpty ? 'قطعة' : unit.trim()),
              category: d.Value(_optionalText(category)),
              quantity: d.Value(initialQuantity),
              minimumQuantity: d.Value(minimumQuantity),
              createdAt: now,
              updatedAt: now,
              lastModified: now,
              origin: const d.Value('local'),
              deviceId: d.Value(_deviceId),
            ),
          );
      final item = await (db.select(
        db.inventoryItems,
      )..where((row) => row.id.equals(itemId))).getSingle();
      await outbox.merge(
        entity: 'inventory_items',
        op: 'create',
        localUuid: item.localUuid,
        payload: _itemPayload(item),
        clientTs: now,
      );

      if (initialQuantity > 0) {
        final movementUuid = _newUuid;
        final movementId = await db
            .into(db.inventoryTransactions)
            .insert(
              InventoryTransactionsCompanion.insert(
                itemLocalUuid: d.Value(item.localUuid),
                itemId: itemId,
                movementType: 'opening',
                quantity: initialQuantity,
                balanceAfter: initialQuantity,
                note: const d.Value('الرصيد الافتتاحي'),
                createdAt: now,
                localUuid: movementUuid,
                createdAtEpoch: d.Value(now),
                updatedAt: now,
                lastModified: now,
                origin: const d.Value('local'),
                deviceId: d.Value(_deviceId),
              ),
            );
        final movement = await (db.select(
          db.inventoryTransactions,
        )..where((row) => row.id.equals(movementId))).getSingle();
        await outbox.merge(
          entity: 'inventory_transactions',
          op: 'create',
          localUuid: movement.localUuid,
          payload: _transactionPayload(movement),
          clientTs: now,
        );
      }
      return itemId;
    });
  }

  Future<void> recordMovement({
    required int itemId,
    required String movementType,
    required int quantity,
    String? note,
    int? userId,
    String? userName,
  }) async {
    if (quantity <= 0) throw ArgumentError('الكمية يجب أن تكون أكبر من صفر');
    if (movementType != 'in' && movementType != 'out') {
      throw ArgumentError('نوع الحركة غير صالح');
    }

    await db.transaction(() async {
      final item = await _getItem(itemId);
      if (item == null || !item.isActive) {
        throw StateError('الصنف غير موجود أو غير نشط');
      }
      final delta = movementType == 'in' ? quantity : -quantity;
      final nextBalance = item.quantity + delta;
      if (nextBalance < 0) {
        throw StateError('لا يمكن صرف كمية أكبر من الرصيد الحالي');
      }

      final now = _nowEpoch;
      final nowIso = DateTime.now().toIso8601String();
      await (db.update(
        db.inventoryItems,
      )..where((row) => row.id.equals(itemId))).write(
        InventoryItemsCompanion(
          quantity: d.Value(nextBalance),
          updatedAt: d.Value(now),
          lastModified: d.Value(now),
          version: d.Value(item.version + 1),
          origin: const d.Value('local'),
          deviceId: d.Value(_deviceId),
        ),
      );
      final updatedItem = await _getItem(itemId);
      if (updatedItem == null) throw StateError('تعذر تحديث الصنف');
      await outbox.merge(
        entity: 'inventory_items',
        op: 'update',
        localUuid: updatedItem.localUuid,
        payload: _itemPayload(updatedItem),
        clientTs: now,
      );

      final movementId = await db
          .into(db.inventoryTransactions)
          .insert(
            InventoryTransactionsCompanion.insert(
              itemLocalUuid: d.Value(item.localUuid),
              itemId: itemId,
              movementType: movementType,
              quantity: quantity,
              balanceAfter: nextBalance,
              note: d.Value(_optionalText(note)),
              userId: d.Value(userId),
              userName: d.Value(_optionalText(userName)),
              createdAt: now,
              createdAtIso: d.Value(nowIso),
              localUuid: _newUuid,
              createdAtEpoch: d.Value(now),
              updatedAt: now,
              lastModified: now,
              origin: const d.Value('local'),
              deviceId: d.Value(_deviceId),
            ),
          );
      final movement = await (db.select(
        db.inventoryTransactions,
      )..where((row) => row.id.equals(movementId))).getSingle();
      await outbox.merge(
        entity: 'inventory_transactions',
        op: 'create',
        localUuid: movement.localUuid,
        payload: _transactionPayload(movement),
        clientTs: now,
      );
    });
  }

  Future<void> setStock({
    required int itemId,
    required int actualQuantity,
    String? note,
    int? userId,
    String? userName,
  }) async {
    if (actualQuantity < 0) {
      throw ArgumentError('الرصيد لا يمكن أن يكون سالباً');
    }

    await db.transaction(() async {
      final item = await _getItem(itemId);
      if (item == null || !item.isActive) {
        throw StateError('الصنف غير موجود أو غير نشط');
      }
      final delta = actualQuantity - item.quantity;
      if (delta == 0) return;

      final now = _nowEpoch;
      final nowIso = DateTime.now().toIso8601String();
      await (db.update(
        db.inventoryItems,
      )..where((row) => row.id.equals(itemId))).write(
        InventoryItemsCompanion(
          quantity: d.Value(actualQuantity),
          updatedAt: d.Value(now),
          lastModified: d.Value(now),
          version: d.Value(item.version + 1),
          origin: const d.Value('local'),
          deviceId: d.Value(_deviceId),
        ),
      );
      final updatedItem = await _getItem(itemId);
      if (updatedItem == null) throw StateError('تعذر تحديث الصنف');
      await outbox.merge(
        entity: 'inventory_items',
        op: 'update',
        localUuid: updatedItem.localUuid,
        payload: _itemPayload(updatedItem),
        clientTs: now,
      );

      final movementId = await db
          .into(db.inventoryTransactions)
          .insert(
            InventoryTransactionsCompanion.insert(
              itemLocalUuid: d.Value(item.localUuid),
              itemId: itemId,
              movementType: 'adjustment',
              quantity: delta,
              balanceAfter: actualQuantity,
              note: d.Value(_optionalText(note) ?? 'تعديل جرد'),
              userId: d.Value(userId),
              userName: d.Value(_optionalText(userName)),
              createdAt: now,
              createdAtIso: d.Value(nowIso),
              localUuid: _newUuid,
              createdAtEpoch: d.Value(now),
              updatedAt: now,
              lastModified: now,
              origin: const d.Value('local'),
              deviceId: d.Value(_deviceId),
            ),
          );
      final movement = await (db.select(
        db.inventoryTransactions,
      )..where((row) => row.id.equals(movementId))).getSingle();
      await outbox.merge(
        entity: 'inventory_transactions',
        op: 'create',
        localUuid: movement.localUuid,
        payload: _transactionPayload(movement),
        clientTs: now,
      );
    });
  }

  Future<void> deactivateItem(int itemId) async {
    await db.transaction(() async {
      final item = await _getItem(itemId);
      if (item == null) return;
      final now = _nowEpoch;
      await (db.update(
        db.inventoryItems,
      )..where((row) => row.id.equals(itemId))).write(
        InventoryItemsCompanion(
          isActive: const d.Value(false),
          deletedAt: d.Value(now),
          updatedAt: d.Value(now),
          lastModified: d.Value(now),
          version: d.Value(item.version + 1),
          origin: const d.Value('local'),
          deviceId: d.Value(_deviceId),
        ),
      );
      final updated = await _getItem(itemId);
      if (updated == null) return;
      await outbox.merge(
        entity: 'inventory_items',
        op: 'update',
        localUuid: updated.localUuid,
        payload: _itemPayload(updated),
        clientTs: now,
      );
    });
  }

  Future<InventoryItem?> _getItem(int itemId) {
    return (db.select(
      db.inventoryItems,
    )..where((row) => row.id.equals(itemId))).getSingleOrNull();
  }

  String get _deviceId => AppwriteSyncManager.currentDeviceIdStatic ?? '';
  int get _nowEpoch => DateTime.now().millisecondsSinceEpoch ~/ 1000;
  String get _newUuid => IdGen.uuid();

  String? _optionalText(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Map<String, dynamic> _itemPayload(InventoryItem item) => {
    'localUuid': item.localUuid,
    'name': item.name,
    'unit': item.unit,
    'category': item.category,
    'quantity': item.quantity,
    'minimumQuantity': item.minimumQuantity,
    'isActive': item.isActive,
    'serverId': item.serverId,
    'createdAt': item.createdAt,
    'updatedAt': item.updatedAt,
    'deletedAt': item.deletedAt,
    'lastModified': item.lastModified,
    'createdAtEpoch': item.createdAtEpoch,
    'lastModifiedEpoch': item.lastModifiedEpoch,
    'version': item.version,
    'origin': item.origin,
    'vectorClock': item.vectorClock,
    'deviceId': item.deviceId,
    'syncTimestamp': item.syncTimestamp,
    'idempotencyKey': item.idempotencyKey,
  };

  Map<String, dynamic> _transactionPayload(InventoryTransaction movement) => {
    'localUuid': movement.localUuid,
    'itemId': movement.itemId,
    'movementType': movement.movementType,
    'quantity': movement.quantity,
    'balanceAfter': movement.balanceAfter,
    'note': movement.note,
    'userId': movement.userId,
    'userName': movement.userName,
    'createdAt': movement.createdAt,
    'createdAtEpoch': movement.createdAtEpoch,
    'updatedAt': movement.updatedAt,
    'deletedAt': movement.deletedAt,
    'lastModified': movement.lastModified,
    'createdAtIso': movement.createdAtIso,
    'updatedAtIso': movement.updatedAtIso,
    'deletedAtIso': movement.deletedAtIso,
    'lastModifiedEpoch': movement.lastModifiedEpoch,
    'version': movement.version,
    'origin': movement.origin,
    'vectorClock': movement.vectorClock,
    'deviceId': movement.deviceId,
    'syncTimestamp': movement.syncTimestamp,
    'idempotencyKey': movement.idempotencyKey,
  };
}
