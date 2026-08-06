// lib/services/daos/ancestor_cache_dao.dart
//
// ✅ DAO لجدول AncestorCache — يخزّن آخر نسخة معروفة مشتركة (common ancestor)
// لكل سجل، ويُستخدم في الدمج ثلاثي الأطراف (3-way merge) لحل التعارضات.

import 'dart:convert';

import 'package:drift/drift.dart';

import '../local_db.dart';

part 'ancestor_cache_dao.g.dart';

@DriftAccessor(tables: [AncestorCache])
class AncestorCacheDao extends DatabaseAccessor<AppDatabase>
    with _$AncestorCacheDaoMixin {
  AncestorCacheDao(super.db);

  /// حفظ نسخة من السجل كما جاءت من السحابة آخر مرة
  Future<void> saveAncestor({
    required String entity,
    required String localUuid,
    required Map<String, dynamic> data,
  }) async {
    await into(ancestorCache).insertOnConflictUpdate(
      AncestorCacheCompanion.insert(
        entity: entity,
        localUuid: localUuid,
        dataJson: jsonEncode(data),
        // ✅ P0-2 Audit Fix (2026-08-06): استخدام مللي ثانية (epoch ms)
        // بدلاً من ثواني. توحيد مع باقي الجداول (Outbox.clientTs,
        // SyncState.lastServerTs). Migration 51 يُحدّث القيم الموجودة.
        capturedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// استرجاع النسخة المشتركة لسجل معيّن
  Future<Map<String, dynamic>?> getAncestor(
    String entity,
    String localUuid,
  ) async {
    final row =
        await (select(ancestorCache)
              ..where(
                (t) => t.entity.equals(entity) & t.localUuid.equals(localUuid),
              )
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    try {
      return jsonDecode(row.dataJson) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// حذف نسخة ancestor (عند حذف السجل نفسه)
  Future<void> deleteAncestor(String entity, String localUuid) async {
    await (delete(ancestorCache)..where(
          (t) => t.entity.equals(entity) & t.localUuid.equals(localUuid),
        ))
        .go();
  }

  /// تنظيف السجلات القديمة (أقدم من maxAgeDays)
  ///
  /// ✅ P0-2 Audit Fix: استخدام مللي ثانية بدلاً من ثواني.
  Future<int> cleanupOldEntries({int maxAgeDays = 30}) async {
    final cutoff =
        DateTime.now()
            .subtract(Duration(days: maxAgeDays))
            .millisecondsSinceEpoch;
    return (delete(
      ancestorCache,
    )..where((t) => t.capturedAt.isSmallerThanValue(cutoff))).go();
  }
}
