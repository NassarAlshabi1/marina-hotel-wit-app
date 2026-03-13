import 'package:drift/drift.dart' as d;
import '../local_db.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import 'entity_adapter.dart';
import 'id_resolver.dart';
import 'resolve_result.dart';
import 'source.dart';

class CashTransactionsAdapter
    extends EntityAdapter<CashTransaction, CashTransactionsCompanion> {
  CashTransactionsAdapter(this.resolver);
  final IdResolver resolver;

  @override
  String get collectionId => 'cash_transactions';

  @override
  String get drivePath => 'cash_transactions.json';

  @override
  String get tableName => 'cash_transactions';

  @override
  Future<ResolveResult> resolveRefs(
    AppDatabase db,
    Map<String, dynamic> json, {
    required Source src,
  }) async {
    final uuid = _asString(json, 'localUuid', src) ??
        _asString(json, 'local_uuid', src) ??
        IdGen.uuid();
    // ignore: unused_local_variable
    final serverId =
        _asInt(json, 'serverId', src) ?? _asInt(json, 'server_id', src);
    // ignore: unused_local_variable
    final localId = _asInt(json, 'id', src);

    final createdAt = _epoch(json, 'createdAt', src);
    final lastModified = _epoch(json, 'lastModified', src);

    return ResolveResult(
      bookingLocalId: null,
      bookingUuidCache: uuid,
      createdAtEpoch: createdAt,
      lastModifiedEpoch: lastModified,
    );
  }

  @override
  CashTransactionsCompanion fromJson(
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

    return CashTransactionsCompanion(
      id: _vInt(json, 'id', src),
      localUuid: d.Value(refs.bookingUuidCache ?? IdGen.uuid()),
      serverId: _vInt(json, 'serverId', src),
      registerId: _vInt(json, 'registerId', src, altKey: 'register_id'),
      transactionType: _vStr(
        json,
        'transactionType',
        src,
        altKey: 'transaction_type',
        fallback: 'expense',
      ),
      amount: _vDouble(json, 'amount', src, fallback: 0),
      referenceType: _vStr(
        json,
        'referenceType',
        src,
        altKey: 'reference_type',
      ),
      referenceId: _vInt(json, 'referenceId', src, altKey: 'reference_id'),
      description: _vStr(json, 'description', src),
      transactionTime: _vStr(
        json,
        'transactionTime',
        src,
        altKey: 'transaction_time',
        fallback: DateTime.now().toIso8601String(),
      ),
      createdBy: _vInt(json, 'createdBy', src, altKey: 'created_by'),
      createdAt: d.Value(createdAt),
      updatedAt: d.Value(_epoch(json, 'updatedAt', src) ?? createdAt),
      deletedAt: _vInt(json, 'deletedAt', src),
      lastModified: d.Value(lastModified),
      createdAtIso: _vStr(json, 'createdAtIso', src),
      updatedAtIso: _vStr(json, 'updatedAtIso', src),
      deletedAtIso: _vStr(json, 'deletedAtIso', src),
      version: _vInt(json, 'version', src, fallback: 1),
      origin: _vStr(json, 'origin', src, fallback: 'server'),
    );
  }

  @override
  Map<String, dynamic> toJson(CashTransaction model, {required Source src}) {
    return {
      _k(src, 'id'): model.id,
      _k(src, 'localUuid'): model.localUuid,
      _k(src, 'serverId'): model.serverId,
      _k(src, 'registerId'): model.registerId,
      _k(src, 'transactionType'): model.transactionType,
      _k(src, 'amount'): model.amount,
      _k(src, 'referenceType'): model.referenceType,
      _k(src, 'referenceId'): model.referenceId,
      _k(src, 'description'): model.description,
      _k(src, 'transactionTime'): model.transactionTime,
      _k(src, 'createdBy'): model.createdBy,
      _k(src, 'createdAt'): model.createdAt,
      _k(src, 'updatedAt'): model.updatedAt,
      _k(src, 'deletedAt'): model.deletedAt,
      _k(src, 'lastModified'): model.lastModified,
      _k(src, 'version'): model.version,
      _k(src, 'origin'): model.origin,
    };
  }
}

// Helpers (Copied from bookings_adapter.dart to avoid dependency issues if not shared)
// In a real refactor, these should be in a shared mixin or utility file.

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

int? _epoch(Map<String, dynamic> json, String key, Source src) {
  final v = _asInt(json, key, src);
  if (v != null) return v;
  final s = _asString(json, key, src);
  if (s == null) return null;
  final parsed = int.tryParse(s);
  return parsed;
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

double? _asDouble(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
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

String _k(Source src, String camel) => camel; // camelCase only
// removed:

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
