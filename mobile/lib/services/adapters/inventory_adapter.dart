import 'package:drift/drift.dart' as d;

import '../../utils/id.dart';
import '../../utils/time.dart';
import '../local_db.dart';
import 'entity_adapter.dart';
import 'id_resolver.dart';
import 'resolve_result.dart';
import 'source.dart';

class InventoryItemsAdapter
    extends EntityAdapter<InventoryItem, InventoryItemsCompanion> {
  InventoryItemsAdapter(this.resolver);

  final IdResolver resolver;

  @override
  String get collectionId => 'inventory_items';

  @override
  String get drivePath => 'inventory_items.json';

  @override
  String get tableName => 'inventory_items';

  @override
  Future<ResolveResult> resolveRefs(
    AppDatabase db,
    Map<String, dynamic> json, {
    required Source src,
  }) async {
    return ResolveResult(
      createdAtEpoch: _int(json, 'createdAt') ?? _int(json, 'created_at'),
      lastModifiedEpoch:
          _int(json, 'lastModified') ?? _int(json, 'last_modified'),
    );
  }

  @override
  InventoryItemsCompanion fromJson(
    Map<String, dynamic> json, {
    required Source src,
    required ResolveResult refs,
  }) {
    final now = Time.nowEpoch();
    final createdAt = refs.createdAtEpoch ?? now;
    final lastModified = refs.lastModifiedEpoch ?? createdAt;
    return InventoryItemsCompanion(
      id: _valueInt(json, 'id'),
      localUuid: d.Value(
        _string(json, 'localUuid') ??
            _string(json, 'local_uuid') ??
            IdGen.uuid(),
      ),
      serverId: _valueInt(json, 'serverId', altKey: 'server_id'),
      name: d.Value(_string(json, 'name') ?? ''),
      unit: d.Value(_string(json, 'unit') ?? 'قطعة'),
      category: _valueString(json, 'category'),
      quantity: d.Value(_int(json, 'quantity') ?? 0),
      minimumQuantity: d.Value(
        _int(json, 'minimumQuantity') ?? _int(json, 'minimum_quantity') ?? 0,
      ),
      isActive: d.Value(
        _bool(json, 'isActive') ?? _bool(json, 'is_active') ?? true,
      ),
      createdAt: d.Value(createdAt),
      updatedAt: d.Value(
        _int(json, 'updatedAt') ?? _int(json, 'updated_at') ?? createdAt,
      ),
      deletedAt: _valueInt(json, 'deletedAt', altKey: 'deleted_at'),
      lastModified: d.Value(lastModified),
      createdAtIso: _valueString(
        json,
        'createdAtIso',
        altKey: 'created_at_iso',
      ),
      updatedAtIso: _valueString(
        json,
        'updatedAtIso',
        altKey: 'updated_at_iso',
      ),
      deletedAtIso: _valueString(
        json,
        'deletedAtIso',
        altKey: 'deleted_at_iso',
      ),
      createdAtEpoch: d.Value(
        _int(json, 'createdAtEpoch') ??
            _int(json, 'created_at_epoch') ??
            createdAt,
      ),
      lastModifiedEpoch: d.Value(
        _int(json, 'lastModifiedEpoch') ??
            _int(json, 'last_modified_epoch') ??
            lastModified,
      ),
      version: d.Value(_int(json, 'version') ?? 1),
      origin: src == Source.appwrite || src == Source.drive
          ? const d.Value('server')
          : d.Value(_string(json, 'origin') ?? 'server'),
      vectorClock: d.Value(
        _string(json, 'vectorClock') ?? _string(json, 'vector_clock') ?? '{}',
      ),
      deviceId: d.Value(
        _string(json, 'deviceId') ?? _string(json, 'device_id') ?? '',
      ),
      syncTimestamp: d.Value(
        _int(json, 'syncTimestamp') ?? _int(json, 'sync_timestamp') ?? 0,
      ),
      idempotencyKey: _valueString(
        json,
        'idempotencyKey',
        altKey: 'idempotency_key',
      ),
    );
  }

  @override
  Map<String, dynamic> toJson(InventoryItem model, {required Source src}) {
    final snake = src != Source.appwrite;
    return {
      _key(snake, 'id', 'id'): model.id,
      _key(snake, 'localUuid', 'local_uuid'): model.localUuid,
      _key(snake, 'serverId', 'server_id'): model.serverId,
      _key(snake, 'name', 'name'): model.name,
      _key(snake, 'unit', 'unit'): model.unit,
      _key(snake, 'category', 'category'): model.category,
      _key(snake, 'quantity', 'quantity'): model.quantity,
      _key(snake, 'minimumQuantity', 'minimum_quantity'): model.minimumQuantity,
      _key(snake, 'isActive', 'is_active'): model.isActive,
      _key(snake, 'createdAt', 'created_at'): model.createdAt,
      _key(snake, 'updatedAt', 'updated_at'): model.updatedAt,
      _key(snake, 'deletedAt', 'deleted_at'): model.deletedAt,
      _key(snake, 'lastModified', 'last_modified'): model.lastModified,
      _key(snake, 'createdAtIso', 'created_at_iso'): model.createdAtIso,
      _key(snake, 'updatedAtIso', 'updated_at_iso'): model.updatedAtIso,
      _key(snake, 'deletedAtIso', 'deleted_at_iso'): model.deletedAtIso,
      _key(snake, 'createdAtEpoch', 'created_at_epoch'): model.createdAtEpoch,
      _key(snake, 'lastModifiedEpoch', 'last_modified_epoch'):
          model.lastModifiedEpoch,
      _key(snake, 'version', 'version'): model.version,
      _key(snake, 'origin', 'origin'): model.origin,
      _key(snake, 'vectorClock', 'vector_clock'): model.vectorClock,
      _key(snake, 'deviceId', 'device_id'): model.deviceId,
      _key(snake, 'syncTimestamp', 'sync_timestamp'): model.syncTimestamp,
      _key(snake, 'idempotencyKey', 'idempotency_key'): model.idempotencyKey,
    };
  }
}

class InventoryTransactionsAdapter
    extends
        EntityAdapter<InventoryTransaction, InventoryTransactionsCompanion> {
  InventoryTransactionsAdapter(this.resolver);

  final IdResolver resolver;

  @override
  String get collectionId => 'inventory_transactions';

  @override
  String get drivePath => 'inventory_transactions.json';

  @override
  String get tableName => 'inventory_transactions';

  @override
  Future<ResolveResult> resolveRefs(
    AppDatabase db,
    Map<String, dynamic> json, {
    required Source src,
  }) async {
    final itemUuid =
        _string(json, 'itemLocalUuid') ?? _string(json, 'item_local_uuid');
    final remoteItemId = _int(json, 'itemId') ?? _int(json, 'item_id');
    InventoryItem? item;
    if (itemUuid != null && itemUuid.isNotEmpty) {
      item =
          await (db.select(db.inventoryItems)
                ..where((row) => row.localUuid.equals(itemUuid))
                ..limit(1))
              .getSingleOrNull();
    } else if (src == Source.local && remoteItemId != null) {
      item =
          await (db.select(db.inventoryItems)
                ..where((row) => row.id.equals(remoteItemId))
                ..limit(1))
              .getSingleOrNull();
    }

    if (item == null) {
      return const ResolveResult(
        shouldSkip: true,
        skipReason: 'inventory transaction references an unknown item',
      );
    }
    return ResolveResult(
      inventoryItemLocalId: item.id,
      createdAtEpoch: _int(json, 'createdAt') ?? _int(json, 'created_at'),
      lastModifiedEpoch:
          _int(json, 'lastModified') ?? _int(json, 'last_modified'),
    );
  }

  @override
  InventoryTransactionsCompanion fromJson(
    Map<String, dynamic> json, {
    required Source src,
    required ResolveResult refs,
  }) {
    final now = Time.nowEpoch();
    final createdAt = refs.createdAtEpoch ?? now;
    final lastModified = refs.lastModifiedEpoch ?? createdAt;
    return InventoryTransactionsCompanion(
      id: _valueInt(json, 'id'),
      localUuid: d.Value(
        _string(json, 'localUuid') ??
            _string(json, 'local_uuid') ??
            IdGen.uuid(),
      ),
      serverId: _valueInt(json, 'serverId', altKey: 'server_id'),
      itemLocalUuid: _valueString(
        json,
        'itemLocalUuid',
        altKey: 'item_local_uuid',
      ),
      itemId: d.Value(refs.inventoryItemLocalId!),
      movementType: d.Value(
        _string(json, 'movementType') ??
            _string(json, 'movement_type') ??
            'adjustment',
      ),
      quantity: d.Value(_int(json, 'quantity') ?? 0),
      balanceAfter: d.Value(
        _int(json, 'balanceAfter') ?? _int(json, 'balance_after') ?? 0,
      ),
      note: _valueString(json, 'note'),
      userId: _valueInt(json, 'userId', altKey: 'user_id'),
      userName: _valueString(json, 'userName', altKey: 'user_name'),
      createdAt: d.Value(createdAt),
      updatedAt: d.Value(
        _int(json, 'updatedAt') ?? _int(json, 'updated_at') ?? createdAt,
      ),
      deletedAt: _valueInt(json, 'deletedAt', altKey: 'deleted_at'),
      lastModified: d.Value(lastModified),
      createdAtIso: _valueString(
        json,
        'createdAtIso',
        altKey: 'created_at_iso',
      ),
      updatedAtIso: _valueString(
        json,
        'updatedAtIso',
        altKey: 'updated_at_iso',
      ),
      deletedAtIso: _valueString(
        json,
        'deletedAtIso',
        altKey: 'deleted_at_iso',
      ),
      createdAtEpoch: d.Value(
        _int(json, 'createdAtEpoch') ??
            _int(json, 'created_at_epoch') ??
            createdAt,
      ),
      lastModifiedEpoch: d.Value(
        _int(json, 'lastModifiedEpoch') ??
            _int(json, 'last_modified_epoch') ??
            lastModified,
      ),
      version: d.Value(_int(json, 'version') ?? 1),
      origin: src == Source.appwrite || src == Source.drive
          ? const d.Value('server')
          : d.Value(_string(json, 'origin') ?? 'server'),
      vectorClock: d.Value(
        _string(json, 'vectorClock') ?? _string(json, 'vector_clock') ?? '{}',
      ),
      deviceId: d.Value(
        _string(json, 'deviceId') ?? _string(json, 'device_id') ?? '',
      ),
      syncTimestamp: d.Value(
        _int(json, 'syncTimestamp') ?? _int(json, 'sync_timestamp') ?? 0,
      ),
      idempotencyKey: _valueString(
        json,
        'idempotencyKey',
        altKey: 'idempotency_key',
      ),
    );
  }

  @override
  Map<String, dynamic> toJson(
    InventoryTransaction model, {
    required Source src,
  }) {
    final snake = src != Source.appwrite;
    return {
      _key(snake, 'id', 'id'): model.id,
      _key(snake, 'localUuid', 'local_uuid'): model.localUuid,
      _key(snake, 'serverId', 'server_id'): model.serverId,
      _key(snake, 'itemLocalUuid', 'item_local_uuid'): model.itemLocalUuid,
      _key(snake, 'itemId', 'item_id'): model.itemId,
      _key(snake, 'movementType', 'movement_type'): model.movementType,
      _key(snake, 'quantity', 'quantity'): model.quantity,
      _key(snake, 'balanceAfter', 'balance_after'): model.balanceAfter,
      _key(snake, 'note', 'note'): model.note,
      _key(snake, 'userId', 'user_id'): model.userId,
      _key(snake, 'userName', 'user_name'): model.userName,
      _key(snake, 'createdAt', 'created_at'): model.createdAt,
      _key(snake, 'updatedAt', 'updated_at'): model.updatedAt,
      _key(snake, 'deletedAt', 'deleted_at'): model.deletedAt,
      _key(snake, 'lastModified', 'last_modified'): model.lastModified,
      _key(snake, 'createdAtIso', 'created_at_iso'): model.createdAtIso,
      _key(snake, 'updatedAtIso', 'updated_at_iso'): model.updatedAtIso,
      _key(snake, 'deletedAtIso', 'deleted_at_iso'): model.deletedAtIso,
      _key(snake, 'createdAtEpoch', 'created_at_epoch'): model.createdAtEpoch,
      _key(snake, 'lastModifiedEpoch', 'last_modified_epoch'):
          model.lastModifiedEpoch,
      _key(snake, 'version', 'version'): model.version,
      _key(snake, 'origin', 'origin'): model.origin,
      _key(snake, 'vectorClock', 'vector_clock'): model.vectorClock,
      _key(snake, 'deviceId', 'device_id'): model.deviceId,
      _key(snake, 'syncTimestamp', 'sync_timestamp'): model.syncTimestamp,
      _key(snake, 'idempotencyKey', 'idempotency_key'): model.idempotencyKey,
    };
  }
}

String _key(bool snake, String camel, String snakeName) =>
    snake ? snakeName : camel;

String? _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

int? _int(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

bool? _bool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    if (value.toLowerCase() == 'true' || value == '1') return true;
    if (value.toLowerCase() == 'false' || value == '0') return false;
  }
  return null;
}

d.Value<int> _valueInt(
  Map<String, dynamic> json,
  String key, {
  String? altKey,
}) {
  final value = _int(json, key) ?? (altKey == null ? null : _int(json, altKey));
  return value == null ? const d.Value.absent() : d.Value(value);
}

d.Value<String> _valueString(
  Map<String, dynamic> json,
  String key, {
  String? altKey,
}) {
  final value =
      _string(json, key) ?? (altKey == null ? null : _string(json, altKey));
  return value == null ? const d.Value.absent() : d.Value(value);
}
