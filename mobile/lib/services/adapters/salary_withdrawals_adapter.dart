import 'package:drift/drift.dart' as d;
import 'package:flutter/foundation.dart';

import '../../utils/id.dart';
import '../../utils/time.dart';
import '../local_db.dart';
import 'entity_adapter.dart';
import 'id_resolver.dart';
import 'resolve_result.dart';
import 'source.dart';

class SalaryWithdrawalsAdapter
    extends EntityAdapter<SalaryWithdrawal, SalaryWithdrawalsCompanion> {
  SalaryWithdrawalsAdapter(this.resolver);
  final IdResolver resolver;

  /// ✅ كتابة expense_id في عمود SQL خام بعد الإدراج
  /// العمود أُضيف عبر Migration 40 ولا يوجد في الـ data class المُولّد
  Future<void> writeExpenseIdRaw(AppDatabase db, int salaryWithdrawalId, int expenseId) async {
    try {
      await db.customStatement(
        'UPDATE salary_withdrawals SET expense_id = ? WHERE id = ?',
        [expenseId, salaryWithdrawalId],
      );
    } catch (_) {
      debugPrint('⚠️ SalaryWithdrawalsAdapter: العمود قد لا يكون موجوداً');
    }
  }

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
    // ✅ حل FK الموظف بالترتيب: UUID -> id -> serverId -> employeeId
    final remoteEmployeeUuid = _asString(json, 'employeeUuid', src) ?? 
                               _asString(json, 'employee_uuid', src) ??
                               _asString(json, 'employeeLocalUuid', src) ??
                               _asString(json, 'employee_local_uuid', src);
    final remoteEmployeeId = _asInt(json, 'employeeId', src) ?? _asInt(json, 'employee_id', src);
    final remoteServerId = _asInt(json, 'serverId', src) ?? _asInt(json, 'server_id', src);

    final resolvedEmployeeId = await resolver.resolveEmployee(
      uuid: remoteEmployeeUuid,
      localId: remoteEmployeeId,
      serverId: remoteServerId,
      employeeId: remoteEmployeeId,
    );

    final createdAt = _epoch(json, 'createdAt', src);
    final lastModified = _epoch(json, 'lastModified', src);
    return ResolveResult(
      employeeLocalId: resolvedEmployeeId,
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
    // دعم الحقول القديمة من Appwrite (date, action, note, notes, expenseId)
    // عند السحب من السيرفر، قد تأتي بالحقل القديم أو الجديد
    final appwriteDate = _asString(json, 'date', src);
    final appwriteAction = _asString(json, 'action', src);
    final appwriteNote = _asString(json, 'note', src);
    final appwriteNotes = _asString(json, 'notes', src);
    final appwriteExpenseId = _asInt(json, 'expenseId', src);
    final wd = _asString(json, 'withdrawDate', src) ?? appwriteDate ?? '';
    final wt = _asString(json, 'withdrawalType', src) ?? appwriteAction;
    final desc = _asString(json, 'description', src) ?? appwriteNotes ?? appwriteNote;
    String? reasonVal = _asString(json, 'reason', src);
    if (reasonVal == null && appwriteExpenseId != null) {
      reasonVal = 'exp_$appwriteExpenseId';
    }

    return SalaryWithdrawalsCompanion(
      id: _vInt(json, 'id', src),
      localUuid: d.Value(
        _asString(json, 'localUuid', src) ??
            _asString(json, 'local_uuid', src) ??
            IdGen.uuid(),
      ),
      serverId: _vInt(json, 'serverId', src),
      // ✅ إصلاح دقيق: استخدام employeeLocalId المحلول بدل القيمة الخام من Appwrite
      // إذا لم يتم حل الموظف (لا يوجد محلياً — يتيم أو محذوف)، نتخطى الحقل
      // تماماً بـ d.Value.absent() لمنع إدراج قيمة FK غير صالحة.
      // ملاحظة: employeeId هو NOT NULL، لذا إدراج بـ absent سيفشل بـ NOT NULL constraint
      // بدلاً من FK constraint — وهذا أفضل لأنه يُمكّن المتصل من التقاط الخطأ
      // وتخطي السجل بدلاً من إدراج بيانات فاسدة.
      // المتصل (_syncSalaryWithdrawals / AppwriteFullPull) يفحص قبل الإدراج.
      employeeId: refs.employeeLocalId != null
          ? d.Value(refs.employeeLocalId!)
          : (src == Source.appwrite || src == Source.drive)
              ? const d.Value.absent() // يتيم — لا نستخدم القيمة الخامة البعيدة
              : _vInt(json, 'employeeId', src, altKey: 'employee_id'),
      amount: _vDouble(json, 'amount', src, fallback: 0),
      withdrawDate: d.Value(wd),
      reason: reasonVal != null ? d.Value(reasonVal) : const d.Value.absent(),
      hotelDayKey: _vStr(
        json,
        'hotelDayKey',
        src,
        altKey: 'hotel_day_key',
      ),
      withdrawalType: wt != null ? d.Value(wt) : const d.Value.absent(),
      description: desc != null ? d.Value(desc) : const d.Value.absent(),
      createdAt: d.Value(createdAt),
      updatedAt: d.Value(_epoch(json, 'updatedAt', src) ?? createdAt),
      deletedAt: _vInt(json, 'deletedAt', src),
      lastModified: d.Value(lastModified),
      createdAtIso: _vStr(json, 'createdAtIso', src),
      updatedAtIso: _vStr(json, 'updatedAtIso', src),
      deletedAtIso: _vStr(json, 'deletedAtIso', src),
      createdAtEpoch: _vInt(json, 'createdAtEpoch', src, fallback: createdAt),
      lastModifiedEpoch: _vInt(
        json,
        'lastModifiedEpoch',
        src,
        fallback: lastModified,
      ),
      version: _vInt(json, 'version', src, fallback: 1),
      // ✅ إصلاح: عند src=Source.appwrite، نصر على origin='server' دائماً
      // لمنع مشكلة أن البيانات المسحوبة من السيرفر تحمل origin='mobile'
      // مما يمنع _cleanupOutboxAfterPull من تنظيف عناصر outbox بشكل صحيح
      origin: src == Source.appwrite || src == Source.drive
          ? const d.Value('server')
          : _vStr(json, 'origin', src, fallback: 'server'),
      vectorClock: _vStr(
        json,
        'vectorClock',
        src,
        altKey: 'vector_clock',
        fallback: '{}',
      ),
      deviceId: _vStr(json, 'deviceId', src, altKey: 'device_id'),
    );
  }

  @override
  Map<String, dynamic> toJson(SalaryWithdrawal model, {required Source src}) {
    // استخراج expenseId من حقل reason (الصيغة: "exp_123")
    int? expenseId;
    if (model.reason != null && model.reason!.startsWith('exp_')) {
      expenseId = int.tryParse(model.reason!.substring(4));
    }

    final map = <String, dynamic>{
      _k(src, 'id', 'id'): model.id,
      _k(src, 'localUuid', 'local_uuid'): model.localUuid,
      _k(src, 'serverId', 'server_id'): model.serverId,
      _k(src, 'employeeId', 'employee_id'): model.employeeId,
      _k(src, 'amount', 'amount'): model.amount.round(), // Appwrite: integer
      _k(src, 'withdrawDate', 'withdraw_date'): model.withdrawDate,
      _k(src, 'reason', 'reason'): model.reason,
      _k(src, 'hotelDayKey', 'hotel_day_key'): model.hotelDayKey,
      _k(src, 'withdrawalType', 'withdrawal_type'): model.withdrawalType,
      _k(src, 'description', 'description'): model.description,
      _k(src, 'createdAt', 'created_at'): model.createdAt,
      _k(src, 'updatedAt', 'updated_at'): model.updatedAt,
      _k(src, 'deletedAt', 'deleted_at'): model.deletedAt,
      _k(src, 'lastModified', 'last_modified'): model.lastModified,
      _k(src, 'version', 'version'): model.version,
      _k(src, 'origin', 'origin'): model.origin,
      'sync_origin': model.origin,
      _k(src, 'vectorClock', 'vector_clock'): model.vectorClock,
      _k(src, 'deviceId', 'device_id'): model.deviceId,
      // ✅ حقول SyncFields المفقودة — ضرورية لمسار الـ outbox
      _k(src, 'createdAtIso', 'created_at_iso'): model.createdAtIso,
      _k(src, 'updatedAtIso', 'updated_at_iso'): model.updatedAtIso,
      _k(src, 'deletedAtIso', 'deleted_at_iso'): model.deletedAtIso,
      _k(src, 'createdAtEpoch', 'created_at_epoch'): model.createdAtEpoch,
      _k(src, 'lastModifiedEpoch', 'last_modified_epoch'): model.lastModifiedEpoch,
    };

    // حقول إضافية مطلوبة من Appwrite Schema
    // الحقول date و action مطلوبة (REQUIRED) في Appwrite
    if (src == Source.appwrite) {
      map['date'] = model.withdrawDate;
      map['action'] = model.withdrawalType;
      map['note'] = model.description;
      map['expenseId'] = expenseId;
    }

    return map;
  }
}

// ─── Helpers ───────────────────────────────────────────────────────────

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

d.Value<double> _vDouble(
  Map<String, dynamic> json,
  String key,
  Source src, {
  String? altKey,
  double? fallback,
}) {
  final v =
      _asDouble(json, key, src) ??
      (altKey != null ? _asDouble(json, altKey, src) : null) ??
      fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

int? _epoch(Map<String, dynamic> json, String key, Source src) {
  final v = _asInt(json, key, src);
  if (v != null) {
    return v;
  }
  final s = _asString(json, key, src);
  if (s == null) {
    return null;
  }
  return int.tryParse(s);
}

int? _asInt(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v is bool) {
    return v ? 1 : 0;
  }
  if (v is int) {
    return v;
  }
  if (v is num) {
    return v.toInt();
  }
  if (v is String) {
    if (v.contains('-') || v.length > 20) {
      return null;
    }
    return int.tryParse(v);
  }
  return null;
}

double? _asDouble(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v is double) {
    return v;
  }
  if (v is int) {
    return v.toDouble();
  }
  if (v is num) {
    return v.toDouble();
  }
  if (v is String) {
    return double.tryParse(v);
  }
  return null;
}

String? _asString(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v == null) {
    return null;
  }
  return v.toString();
}

Object? _raw(Map<String, dynamic> json, String key, Source src) {
  if (json.containsKey(key)) {
    return json[key];
  }
  final alt = _altKey(key, src);
  if (alt != null && json.containsKey(alt)) {
    return json[alt];
  }
  return null;
}

String _k(Source src, String camel, String snake) =>
    src == Source.drive ? snake : camel;

String? _altKey(String camel, Source src) {
  if (src == Source.drive) {
    return camel;
  }
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
