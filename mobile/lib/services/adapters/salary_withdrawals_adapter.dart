import 'dart:convert';
import 'package:drift/drift.dart' as d;

import '../local_db.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import 'entity_adapter.dart';
import 'id_resolver.dart';
import 'resolve_result.dart';
import 'source.dart';

/// Adapter for SalaryWithdrawal entity
/// Handles conversion between:
/// - Local database (Drift/SQLite)
/// - Appwrite Cloud (salary_withdrawals collection)
/// - Google Drive (JSON backup)
class SalaryWithdrawalsAdapter
    extends EntityAdapter<SalaryWithdrawal, SalaryWithdrawalsCompanion> {
  SalaryWithdrawalsAdapter(this.resolver);

  final IdResolver resolver;

  @override
  String get collectionId => 'salary_withdrawals';

  @override
  String get drivePath => 'salary_withdrawals.json';

  @override
  String get tableName => 'salary_withdrawals';

  @override
  Future<ResolveResult> resolveRefs(
    AppDatabase db,
    Map<String, dynamic> json, {
    required Source src,
  }) async {
    final createdAt = _epoch(json, 'createdAt', src);
    final lastModified = _epoch(json, 'lastModified', src);

    return ResolveResult(
      createdAtEpoch: createdAt,
      lastModifiedEpoch: lastModified,
    );
  }

  @override
  SalaryWithdrawalsCompanion fromJson(
    Map<String, dynamic> json, {
    required Source src,
    required ResolveResult refs,
  }) {
    final now = Time.nowEpoch();
    final createdAt =
        refs.createdAtEpoch ?? _epoch(json, 'createdAt', src) ?? now;
    final lastModified =
        refs.lastModifiedEpoch ??
        _epoch(json, 'lastModified', src) ??
        createdAt;

    // ✅ action: String حر من Appwrite (أي قيمة يختارها المستخدم)
    final action = _asString(json, 'action', src)?.trim() ?? 'سحب من الراتب';

    // ✅ employeeId: required integer
    final employeeId =
        _asInt(json, 'employeeId', src) ?? _asInt(json, 'employee_id', src);
    if (employeeId == null || employeeId <= 0) {
      throw FormatException('employeeId is required: $employeeId');
    }

    // ✅ amount: integer من Appwrite (convert to double للـ local)
    final amountInt = _asInt(json, 'amount', src);
    final amount =
        amountInt?.toDouble() ?? _asDouble(json, 'amount', src) ?? 0.0;

    return SalaryWithdrawalsCompanion(
      // ✅ id: integer (primary key محلي)
      id: _vInt(json, 'id', src),

      // ✅ localUuid: string(255) - UUID للمزامنة
      localUuid: d.Value(
        _asString(json, 'localUuid', src) ??
            _asString(json, 'local_uuid', src) ??
            IdGen.uuid(),
      ),

      // ✅ serverId: integer optional (legacy)
      serverId: _vInt(json, 'serverId', src),

      // ✅ expenseId: integer optional (foreign key)
      expenseId: _vInt(json, 'expenseId', src, altKey: 'expense_id'),

      // ✅ employeeId: integer required (foreign key)
      employeeId: d.Value(employeeId),

      // ✅ name: string optional - اسم الموظف للتخزين والعرض السريع
      name: _vStr(json, 'name', src),

      // ✅ action: string(255) required - حر بدون قيود
      action: d.Value(action),

      // ✅ amount: integer (converted to double for local)
      amount: d.Value(amount),

      // ✅ note: string(1000) optional
      note: _vStr(json, 'note', src),

      // ✅ date: string(50) required (ISO format)
      date: _vStr(json, 'date', src, fallback: Time.hotelDayKey()),

      // ✅ createdAt: integer required (epoch seconds)
      createdAt: d.Value(createdAt),

      // ✅ updatedAt: integer required
      updatedAt: d.Value(_epoch(json, 'updatedAt', src) ?? createdAt),

      // ✅ deletedAt: integer optional (soft delete)
      deletedAt: _vInt(json, 'deletedAt', src),

      // ✅ lastModified: integer required (لـ Delta Sync)
      lastModified: d.Value(lastModified),

      // ✅ createdAtIso: string optional (ISO format)
      createdAtIso: _vStr(json, 'createdAtIso', src),

      // ✅ updatedAtIso: string optional
      updatedAtIso: _vStr(json, 'updatedAtIso', src),

      // ✅ deletedAtIso: string optional
      deletedAtIso: _vStr(json, 'deletedAtIso', src),

      // ✅ createdAtEpoch: integer (نفس createdAt)
      createdAtEpoch: d.Value(createdAt),

      // ✅ lastModifiedEpoch: integer (نفس lastModified)
      lastModifiedEpoch: d.Value(lastModified),

      // ✅ version: integer required (Optimistic Locking)
      version: _vInt(json, 'version', src, fallback: 1),

      // ✅ origin: string(50) required
      origin: _vStr(json, 'origin', src, fallback: 'mobile'),

      // ✅ vectorClock: string(2000) required (JSON encoded)
      vectorClock: _vMapJson(
        json,
        'vectorClock',
        src,
        altKey: 'vector_clock',
        fallback: {},
      ),

      // ❌ syncTimestamp: integer optional - يُضاف في AppwriteDeltaSync
      // ❌ deviceId: string(255) optional - يُضاف في AppwriteDeltaSync
    );
  }

  @override
  Map<String, dynamic> toJson(SalaryWithdrawal model, {required Source src}) {
    return {
      // ✅ Core fields
      _k(src, 'id', 'id'): model.id,
      _k(src, 'localUuid', 'local_uuid'): model.localUuid,

      // ✅ Foreign keys
      _k(src, 'serverId', 'server_id'): model.serverId,
      _k(src, 'expenseId', 'expense_id'): model.expenseId,
      _k(src, 'employeeId', 'employee_id'): model.employeeId,

      // ✅ Employee name for quick display
      _k(src, 'name', 'name'): model.name,

      // ✅ Business fields
      _k(src, 'action', 'action'): model.action, // حر بدون قيود
      _k(src, 'amount', 'amount'): model.amount
          .round(), // ✅ integer for Appwrite
      _k(src, 'note', 'note'): model.note,
      _k(src, 'date', 'date'): model.date,

      // ✅ Timestamps
      _k(src, 'createdAt', 'created_at'): model.createdAt,
      _k(src, 'updatedAt', 'updated_at'): model.updatedAt,
      _k(src, 'deletedAt', 'deleted_at'): model.deletedAt,
      _k(src, 'lastModified', 'last_modified'): model.lastModified,

      // ✅ ISO timestamps (optional)
      _k(src, 'createdAtIso', 'created_at_iso'): model.createdAtIso,
      _k(src, 'updatedAtIso', 'updated_at_iso'): model.updatedAtIso,
      _k(src, 'deletedAtIso', 'deleted_at_iso'): model.deletedAtIso,

      // ✅ Epoch timestamps
      _k(src, 'createdAtEpoch', 'created_at_epoch'): model.createdAtEpoch,
      _k(src, 'lastModifiedEpoch', 'last_modified_epoch'):
          model.lastModifiedEpoch,

      // ✅ Sync metadata
      _k(src, 'version', 'version'): model.version,
      _k(src, 'origin', 'origin'): model.origin,

      // ✅ vectorClock as JSON string
      _k(
        src,
        'vectorClock',
        'vector_clock',
      ): model.vectorClock?.isNotEmpty ?? false
          ? jsonEncode(model.vectorClock)
          : '{}',

      // ❌ syncTimestamp و deviceId يُضافان في AppwriteDeltaSync
    };
  }
}

// ==================== Helper Functions ====================

d.Value<int> _vInt(
  Map<String, dynamic> json,
  String key,
  Source src, {
  String? altKey,
  int? fallback,
}) {
  final v =
      _asInt(json, key, src) ??
      (altKey != null ? _asInt(json, altKey, src) : null) ??
      fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

d.Value<String> _vStr(
  Map<String, dynamic> json,
  String key,
  Source src, {
  String? altKey,
  String? fallback,
}) {
  final v =
      _asString(json, key, src) ??
      (altKey != null ? _asString(json, altKey, src) : null) ??
      fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

d.Value<Map<String, dynamic>> _vMapJson(
  Map<String, dynamic> json,
  String key,
  Source src, {
  String? altKey,
  Map<String, dynamic>? fallback,
}) {
  final v =
      _asMap(json, key, src) ??
      (altKey != null ? _asMap(json, altKey, src) : null) ??
      fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

int? _epoch(Map<String, dynamic> json, String key, Source src) {
  final v = _asInt(json, key, src);
  if (v != null) return v;

  final s = _asString(json, key, src);
  if (s == null) return null;

  final asInt = int.tryParse(s);
  if (asInt != null) return asInt;

  try {
    return DateTime.parse(s).millisecondsSinceEpoch ~/ 1000;
  } catch (_) {}

  return null;
}

int? _asInt(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v == null) return null;
  if (v is bool) return v ? 1 : 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    if (v.contains('-') || v.length > 20) return null;
    return int.tryParse(v);
  }
  return null;
}

double? _asDouble(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v == null) return null;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

String? _asString(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v == null) return null;
  final str = v.toString();
  return str.isEmpty ? null : str;
}

Map<String, dynamic>? _asMap(
  Map<String, dynamic> json,
  String key,
  Source src,
) {
  final v = _raw(json, key, src);
  if (v == null) return null;
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  if (v is String) {
    try {
      final decoded = jsonDecode(v);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  return null;
}

Object? _raw(Map<String, dynamic> json, String key, Source src) {
  if (json.containsKey(key)) return json[key];
  final alt = _altKey(key, src);
  if (alt != null && json.containsKey(alt)) return json[alt];
  return null;
}

String _k(Source src, String camel, String snake) =>
    src == Source.drive ? snake : camel;

String? _altKey(String camel, Source src) {
  if (src == Source.drive) return camel;
  final buf = StringBuffer();
  for (var i = 0; i < camel.length; i++) {
    final c = camel[i];
    if (c.toUpperCase() == c && c.toLowerCase() != c) {
      buf.write('_');
      buf.write(c.toLowerCase());
    } else {
      buf.write(c);
    }
  }
  return buf.toString();
}
