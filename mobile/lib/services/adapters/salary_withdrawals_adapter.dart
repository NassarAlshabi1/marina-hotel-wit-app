import 'dart:convert';
import 'package:drift/drift.dart' as d;

import '../local_db.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import 'entity_adapter.dart';
import 'id_resolver.dart';
import 'resolve_result.dart';
import 'source.dart';

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
    // ✅ استخدم resolver للـ foreign keys
    final employeeId = await resolver.resolveEmployee(
      db,
      json['employeeId'] ?? json['employee_id'],
      src: src,
    );

    final expenseId = json['expenseId'] != null || json['expense_id'] != null
        ? await resolver.resolveExpense(
            db,
            json['expenseId'] ?? json['expense_id'],
            src: src,
          )
        : null;

    final createdAt = _epoch(json, 'createdAt', src);
    final lastModified = _epoch(json, 'lastModified', src);

    return ResolveResult(
      createdAtEpoch: createdAt,
      lastModifiedEpoch: lastModified,
      resolvedEmployeeId: employeeId,
      resolvedExpenseId: expenseId,
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
    final lastModified = refs.lastModifiedEpoch ??
        _epoch(json, 'lastModified', src) ??
        createdAt;

    // ✅ validation للـ amount
    final amount = _asDouble(json, 'amount', src) ?? 0.0;
    if (amount < 0) {
      throw ArgumentError('Amount cannot be negative: $amount');
    }

    return SalaryWithdrawalsCompanion(
      id: _vInt(json, 'id', src),
      localUuid: d.Value(
        _asString(json, 'localUuid', src) ??
            _asString(json, 'local_uuid', src) ??
            (src == Source.drive
                ? throw ArgumentError('localUuid required for Drive import')
                : IdGen.uuid()),
      ),
      serverId: _vInt(json, 'serverId', src),
      expenseId: refs.resolvedExpenseId != null
          ? d.Value(refs.resolvedExpenseId!)
          : _vInt(json, 'expenseId', src, altKey: 'expense_id'),
      employeeId: refs.resolvedEmployeeId != null
          ? d.Value(refs.resolvedEmployeeId!)
          : _vInt(json, 'employeeId', src, altKey: 'employee_id', fallback: 0),
      action: _vStr(
        json,
        'action',
        src,
        fallback: 'سحب راتب',
      ),
      amount: d.Value(amount),
      note: _vStr(json, 'note', src),
      date: _vStr(
        json,
        'date',
        src,
        fallback: Time.hotelDayKey(),
      ),
      createdAt: d.Value(createdAt),
      updatedAt: d.Value(_epoch(json, 'updatedAt', src) ?? createdAt),
      deletedAt: _vInt(json, 'deletedAt', src),
      lastModified: d.Value(lastModified),
      createdAtIso: _vStr(json, 'createdAtIso', src,
          fallback: Time.epochToIso(createdAt)),
      updatedAtIso: _vStr(json, 'updatedAtIso', src),
      deletedAtIso: _vStr(json, 'deletedAtIso', src),
      createdAtEpoch: d.Value(createdAt),
      lastModifiedEpoch: d.Value(lastModified),
      version: _vInt(json, 'version', src, fallback: 1),
      origin: _vStr(json, 'origin', src,
          fallback: src == Source.appwrite ? 'server' : 'mobile'),
      vectorClock: _vMapJson(
        json,
        'vectorClock',
        src,
        altKey: 'vector_clock',
        fallback: {},
      ),
    );
  }

  @override
  Map<String, dynamic> toJson(SalaryWithdrawal model, {required Source src}) {
    final json = <String, dynamic>{
      _k(src, 'id', 'id'): model.id,
      _k(src, 'localUuid', 'local_uuid'): model.localUuid,
      _k(src, 'serverId', 'server_id'): model.serverId,
      _k(src, 'expenseId', 'expense_id'): model.expenseId,
      _k(src, 'employeeId', 'employee_id'): model.employeeId,
      _k(src, 'action', 'action'): model.action,
      _k(src, 'amount', 'amount'): model.amount,
      _k(src, 'note', 'note'): model.note,
      _k(src, 'date', 'date'): model.date,
      _k(src, 'createdAt', 'created_at'): model.createdAt,
      _k(src, 'updatedAt', 'updated_at'): model.updatedAt,
      _k(src, 'deletedAt', 'deleted_at'): model.deletedAt,
      _k(src, 'lastModified', 'last_modified'): model.lastModified,
      _k(src, 'version', 'version'): model.version,
      _k(src, 'origin', 'origin'): model.origin,
    };

    // ✅ vectorClock دائماً Map
    final vc = model.vectorClock;
    if (vc != null && vc.isNotEmpty) {
      json[_k(src, 'vectorClock', 'vector_clock')] = vc;
    } else {
      json[_k(src, 'vectorClock', 'vector_clock')] = <String, dynamic>{};
    }

    return json;
  }
}

d.Value<int> _vInt(
  Map<String, dynamic> json,
  String key,
  Source src, {
  String? altKey,
  int? fallback,
}) {
  final v = _asInt(json, key, src) ??
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
  final v = _asString(json, key, src) ??
      (altKey != null ? _asString(json, altKey, src) : null) ??
      fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

d.Value<bool> _vBool(
  Map<String, dynamic> json,
  String key,
  Source src, {
  String? altKey,
  bool? fallback,
}) {
  final v = _asBool(json, key, src) ??
      (altKey != null ? _asBool(json, altKey, src) : null) ??
      fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

/// ✅ Improved _epoch with ISO 8601 support
int? _epoch(Map<String, dynamic> json, String key, Source src) {
  final v = _asInt(json, key, src);
  if (v != null) return v;

  final s = _asString(json, key, src);
  if (s == null) return null;

  // محاولة parsing كـ int أولاً
  final asInt = int.tryParse(s);
  if (asInt != null) return asInt;

  // محاولة parsing كـ ISO 8601 date
  try {
    final date = DateTime.parse(s);
    return date.millisecondsSinceEpoch ~/ 1000; // convert to seconds
  } catch (_) {}

  return null;
}

int? _asInt(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v is bool) return v ? 1 : 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    if (v.contains('-') || v.length > 20) return null;
    return int.tryParse(v);
  }
  return null;
}

bool? _asBool(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final t = v.toLowerCase();
    if (t == 'true' || t == '1') return true;
    if (t == 'false' || t == '0') return false;
  }
  return null;
}

d.Value<double> _vDouble(
  Map<String, dynamic> json,
  String key,
  Source src, {
  String? altKey,
  double? fallback,
}) {
  final v = _asDouble(json, key, src) ??
      (altKey != null ? _asDouble(json, altKey, src) : null) ??
      fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

double? _asDouble(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

d.Value<Map<String, dynamic>> _vMapJson(
  Map<String, dynamic> json,
  String key,
  Source src, {
  String? altKey,
  Map<String, dynamic>? fallback,
}) {
  final v = _asMap(json, key, src) ??
      (altKey != null ? _asMap(json, altKey, src) : null) ??
      fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

Map<String, dynamic>? _asMap(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
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

String? _asString(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v == null) return null;
  final str = v.toString();
  return str.isEmpty ? null : str; // ✅ تجاهل empty strings
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
