import 'dart:convert';
import '../local_db.dart';
import '../adapters/adapter_registry.dart';
import '../adapters/source.dart';
import '../daos/outbox_dao.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';

const _uuid = Uuid();

class SalaryWithdrawalsRepository {
  SalaryWithdrawalsRepository(this._db)
      : _outbox = OutboxDao(_db),
        _adapters = AdapterRegistry(_db);

  final AppDatabase _db;
  final OutboxDao _outbox;
  final AdapterRegistry _adapters;

  /// ✅ حفظ سحب الراتب من شاشة المصروفات
  /// يتضمن: حفظ محلي + Outbox + المرآة
  Future<void> saveFromExpense({
    required int expenseId,
    required int employeeId,
    required String action,
    required double amount,
    required String date,
    String? note,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final nowIso = DateTime.now().toIso8601String();

    // Check if record exists
    final existing = await (_db.select(_db.salaryWithdrawals)
          ..where((t) => t.expenseId.equals(expenseId)))
        .getSingleOrNull();

    String localUuid;
    int? recordId;
    bool isNewRecord = existing == null;

    if (existing != null) {
      // Update existing
      localUuid = existing.localUuid;
      recordId = existing.id;

      await (_db.update(_db.salaryWithdrawals)
            ..where((t) => t.expenseId.equals(expenseId)))
          .write(SalaryWithdrawalsCompanion(
        employeeId: Value(employeeId),
        action: Value(action),
        amount: Value(amount),
        note: Value(note),
        date: Value(date),
        updatedAt: Value(now),
        lastModified: Value(now),
        updatedAtIso: Value(nowIso),
      ));
    } else {
      // Insert new
      localUuid = _uuid.v4();

      recordId = await _db.into(_db.salaryWithdrawals).insert(
        SalaryWithdrawalsCompanion(
          expenseId: Value(expenseId),
          employeeId: Value(employeeId),
          action: Value(action),
          amount: Value(amount),
          note: Value(note),
          date: Value(date),
          localUuid: Value(localUuid),
          createdAt: Value(now),
          updatedAt: Value(now),
          lastModified: Value(now),
          createdAtIso: Value(nowIso),
          updatedAtIso: Value(nowIso),
          version: const Value(1),
          origin: const Value('local'),
        ),
      );
    }

    // ✅ بناء بيانات السجل الكاملة
    final payload = _buildPayload(
      localUuid: localUuid,
      recordId: recordId!,
      expenseId: expenseId,
      employeeId: employeeId,
      action: action,
      amount: amount,
      date: date,
      note: note,
      now: now,
      nowIso: nowIso,
    );

    // ✅ 1. إضافة للمزامنة عبر Outbox
    await _addToOutbox(
      localUuid: localUuid,
      recordId: recordId,
      payload: payload,
      now: now,
    );

    // ✅ 2. تحديث المرآة فوراً (لـ Delta Sync)
    await _updateMirror(
      localUuid: localUuid,
      payload: payload,
      now: now,
      isNewRecord: isNewRecord,
    );
  }

  /// ✅ بناء payload كامل للسجل
  Map<String, dynamic> _buildPayload({
    required String localUuid,
    required int recordId,
    required int expenseId,
    required int employeeId,
    required String action,
    required double amount,
    required String date,
    String? note,
    required int now,
    required String nowIso,
  }) {
    return {
      // ✅ الحقول الأساسية
      'id': recordId,
      'localUuid': localUuid,
      'expenseId': expenseId,
      'employeeId': employeeId,
      'action': action,
      'amount': amount.toInt(), // ✅ integer for Appwrite
      'date': date,
      if (note != null && note.isNotEmpty) 'note': note,
      
      // ✅ Timestamps
      'createdAt': now,
      'updatedAt': now,
      'lastModified': now,
      'createdAtIso': nowIso,
      'updatedAtIso': nowIso,
      
      // ✅ Sync metadata
      'version': 1,
      'origin': 'local',
      'vectorClock': '{}',
    };
  }

  /// ✅ إضافة سجل للـ Outbox للمزامنة
  Future<void> _addToOutbox({
    required String localUuid,
    required int recordId,
    required Map<String, dynamic> payload,
    required int now,
  }) async {
    await _outbox.merge(
      entity: 'salary_withdrawals',
      op: 'upsert',
      localUuid: localUuid,
      serverId: recordId,
      payload: payload,
      clientTs: now ~/ 1000,
    );
  }

  /// ✅ تحديث المرآة فوراً (لـ Delta Sync)
  /// هذا يضمن أن Delta Sync يكتشف التغييرات بشكل صحيح
  Future<void> _updateMirror({
    required String localUuid,
    required Map<String, dynamic> payload,
    required int now,
    required bool isNewRecord,
  }) async {
    try {
      // حساب hash للبيانات
      final sortedPayload = _sortMapForHash(payload);
      final rowHash = sha1.convert(utf8.encode(jsonEncode(sortedPayload))).toString();
      
      // تحديث أو إدراج في المرآة
      await _db.customStatement(
        '''INSERT OR REPLACE INTO sync_mirror 
           (sync_entity_name, local_uuid, row_hash, payload, last_seen_at) 
           VALUES (?, ?, ?, ?, ?)''',
        ['salary_withdrawals', localUuid, rowHash, jsonEncode(payload), now],
      );
      
      print('✅ [Mirror] Updated salary_withdrawals/$localUuid (isNew: $isNewRecord)');
    } catch (e) {
      print('⚠️ [Mirror] Failed to update mirror: $e');
      // لا نرمي الخطأ لأن العملية الأساسية نجحت
    }
  }

  /// ترتيب Map لحساب hash متسق
  Map<String, dynamic> _sortMapForHash(Map<String, dynamic> source) {
    final entries = source.entries.map((entry) {
      final value = entry.value;
      dynamic normalized;
      if (value is Map<String, dynamic>) {
        normalized = _sortMapForHash(value);
      } else if (value is List) {
        normalized = value.map((item) {
          if (item is Map<String, dynamic>) return _sortMapForHash(item);
          return item;
        }).toList();
      } else {
        normalized = value;
      }
      return MapEntry(entry.key, normalized);
    }).toList()..sort((a, b) => a.key.compareTo(b.key));
    return Map<String, dynamic>.fromEntries(entries);
  }

  /// ✅ حذف سجل بواسطة expenseId
  Future<void> deleteByExpenseId(int expenseId) async {
    // جلب السجل قبل الحذف للحصول على localUuid
    final existing = await (_db.select(_db.salaryWithdrawals)
          ..where((t) => t.expenseId.equals(expenseId)))
        .getSingleOrNull();

    if (existing != null) {
      final now = DateTime.now().millisecondsSinceEpoch;

      // حذف من قاعدة البيانات المحلية
      await (_db.delete(_db.salaryWithdrawals)
            ..where((t) => t.expenseId.equals(expenseId)))
          .go();

      // ✅ 1. إضافة عملية حذف للـ Outbox
      await _outbox.merge(
        entity: 'salary_withdrawals',
        op: 'delete',
        localUuid: existing.localUuid,
        payload: {'deleted': true, 'localUuid': existing.localUuid, 'deletedAt': now},
        clientTs: now ~/ 1000,
      );

      // ✅ 2. تحديث المرآة بحذف السجل
      await _deleteFromMirror(existing.localUuid);
    }
  }

  /// ✅ حذف من المرآة
  Future<void> _deleteFromMirror(String localUuid) async {
    try {
      await _db.customStatement(
        'DELETE FROM sync_mirror WHERE sync_entity_name = ? AND local_uuid = ?',
        ['salary_withdrawals', localUuid],
      );
      print('✅ [Mirror] Deleted salary_withdrawals/$localUuid');
    } catch (e) {
      print('⚠️ [Mirror] Failed to delete from mirror: $e');
    }
  }

  /// جلب جميع السجلات
  Future<List<SalaryWithdrawal>> listAll() async {
    return await (_db.select(_db.salaryWithdrawals)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// جلب سجل واحد بواسطة localUuid
  Future<SalaryWithdrawal?> getByUuid(String localUuid) async {
    return await (_db.select(_db.salaryWithdrawals)
          ..where((t) => t.localUuid.equals(localUuid)))
        .getSingleOrNull();
  }

  /// تحويل السجل إلى JSON للإرسال
  Map<String, dynamic> toJson(SalaryWithdrawal record) {
    return _adapters.salaryWithdrawals.adapter.toJson(record, src: Source.appwrite);
  }

  /// ✅ إعادة بناء المرآة من قاعدة البيانات
  /// يُستخدم عند بدء التطبيق أو عند اكتشاف عدم تطابق
  Future<int> rebuildMirror() async {
    try {
      // مسح المرآة القديمة للجدول
      await _db.customStatement(
        'DELETE FROM sync_mirror WHERE sync_entity_name = ?',
        ['salary_withdrawals'],
      );

      // جلب جميع السجلات
      final records = await listAll();
      final now = DateTime.now().millisecondsSinceEpoch;
      int count = 0;

      for (final record in records) {
        final payload = toJson(record);
        final sortedPayload = _sortMapForHash(payload);
        final rowHash = sha1.convert(utf8.encode(jsonEncode(sortedPayload))).toString();

        await _db.customStatement(
          '''INSERT INTO sync_mirror 
             (sync_entity_name, local_uuid, row_hash, payload, last_seen_at) 
             VALUES (?, ?, ?, ?, ?)''',
          ['salary_withdrawals', record.localUuid, rowHash, jsonEncode(payload), now],
        );
        count++;
      }

      print('✅ [Mirror] Rebuilt salary_withdrawals: $count records');
      return count;
    } catch (e) {
      print('❌ [Mirror] Failed to rebuild mirror: $e');
      return 0;
    }
  }
}
