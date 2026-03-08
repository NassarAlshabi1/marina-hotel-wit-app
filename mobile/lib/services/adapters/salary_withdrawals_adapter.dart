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
    final lastModified = refs.lastModifiedEpoch ??
        _epoch(json, 'lastModified', src) ??
        createdAt;
    return SalaryWithdrawalsCompanion(
      id: _vInt(json, 'id', src),
      localUuid: d.Value(
        _asString(json, 'localUuid', src) ??
            _asString(json, 'local_uuid', src) ??
            IdGen.uuid(),
      ),
      serverId: _vInt(json, 'serverId', src),
      expenseId: _vInt(json, 'expenseId', src, altKey: 'expense_id'),
      employeeId: d.Value(_asInt(json, 'employeeId', src) ??
          _asInt(json, 'employee_id', src) ??
          0),
      action: d.Value(_asString(json, 'action', src) ?? ''),
      amount: d.Value(_asInt(json, 'amount', src) ?? 0),
      note: d.Value(_asString(json, 'note', src)),
      date: d.Value(_asString(json, 'date', src) ?? ''),
      createdAt: d.Value(createdAt),
      updatedAt: d.Value(_epoch(json, 'updatedAt', src) ?? createdAt),
      deletedAt: _vInt(json, 'deletedAt', src, altKey: 'deleted_at'),
      lastModified: d.Value(lastModified),
      createdAtIso: d.Value(_asString(json, 'createdAtIso', src)),
      updatedAtIso: d.Value(_asString(json, 'updatedAtIso', src)),
      deletedAtIso: d.Value(_asString(json, 'deletedAtIso', src)),
      createdAtEpoch: d.Value(_asInt(json, 'createdAtEpoch', src) ?? createdAt),
      lastModifiedEpoch: d.Value(
        _asInt(json, 'lastModifiedEpoch', src) ?? lastModified,
      ),
      version: d.Value(_asInt(json, 'version', src) ?? 1),
      origin: d.Value(_asString(json, 'origin', src) ?? 'server'),
      vectorClock: d.Value(
        _asString(json, 'vectorClock', src) ??
            _asString(json, 'vector_clock', src) ??
            '{}',
      ),
    );
  }

  @override
  Map<String, dynamic> toJson(SalaryWithdrawal model, {required Source src}) {
    return {
      // الحقول الأساسية للمزامنة
      'localUuid': model.localUuid,
      'serverId': model.serverId,
      'version': model.version,
      'origin': model.origin,
      
      // الحقول الأساسية للسحب
      'expenseId': model.expenseId,
      'employeeId': model.employeeId,
      'action': model.action,
      'amount': model.amount,
      'note': model.note,
      'date': model.date,
      
      // التواريخ المتزامنة
      'createdAt': model.createdAt,
      'updatedAt': model.updatedAt,
      'deletedAt': model.deletedAt,
      'lastModified': model.lastModified,
    };
  }
  
  /// تحويل مختصر للمزامنة السريعة
  Map<String, dynamic> toJsonCompact(SalaryWithdrawal model, {required Source src}) {
    return {
      'localUuid': model.localUuid,
      'serverId': model.serverId,
      'employeeId': model.employeeId,
      'action': model.action,
      'amount': model.amount,
      'date': model.date,
      'lastModified': model.lastModified,
      'version': model.version,
      'origin': model.origin,
    };
  }
}

d.Value<int> _vInt(
  Map<String, dynamic> json,
  String key,
  Source src, {
  String? altKey,
}) {
  final v = _asInt(json, key, src) ??
      (altKey != null ? _asInt(json, altKey, src) : null);
  return v == null ? const d.Value.absent() : d.Value(v);
}

int? _epoch(Map<String, dynamic> json, String key, Source src) {
  final v = _asInt(json, key, src);
  if (v != null) return v;
  final s = _asString(json, key, src);
  if (s == null) return null;
  return int.tryParse(s);
}

int? _asInt(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v is bool) return v ? 1 : 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    // تجاهل UUID أو strings طويلة
    if (v.contains('-') || v.length > 20) return null;
    return int.tryParse(v);
  }
  return null;
}

String? _asString(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v == null) return null;
  return v.toString();
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
