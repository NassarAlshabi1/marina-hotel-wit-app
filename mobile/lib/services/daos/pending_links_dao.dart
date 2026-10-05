import 'dart:convert';

import 'package:drift/drift.dart';

import '../local_db.dart';

part 'pending_links_dao.g.dart';

/// أنواع الكيانات المدعومة في pending_links
class PendingLinkChildEntity {
  static const String payments = 'payments';
  static const String debts = 'debts';
  static const String salaryWithdrawals = 'salary_withdrawals';
  static const String bookingNights = 'booking_nights';
  static const String salaryCycles = 'salary_cycles';
  static const String salaryPayments = 'salary_payments';
  static const String bookingPriceAdjustments = 'booking_price_adjustments';
}

/// أنواع العلاقات
class PendingLinkType {
  static const String fk = 'fk'; // مفتاح خارجي رقمي
  static const String uuid = 'uuid'; // ربط بـ UUID
  static const String composite = 'composite'; // ربط مركب
}

/// حالات الرابط
class PendingLinkStatus {
  static const String pending = 'pending';
  static const String resolved = 'resolved';
  static const String failed = 'failed';
}

@DriftAccessor(tables: [PendingLinks])
class PendingLinksDao extends DatabaseAccessor<AppDatabase> with _$PendingLinksDaoMixin {
  PendingLinksDao(super.db);

  /// إضافة رابط معلق جديد
  Future<int> addLink({
    required String childEntity,
    required String childLocalUuid,
    required String parentEntity,
    required String childField,
    String? parentLocalUuid,
    String? parentServerId,
    String linkType = PendingLinkType.fk,
    String parentField = 'id',
    Map<String, dynamic>? metadata,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return into(pendingLinks).insert(
      PendingLinksCompanion(
        childEntity: Value(childEntity),
        childLocalUuid: Value(childLocalUuid),
        parentEntity: Value(parentEntity),
        parentLocalUuid: parentLocalUuid != null ? Value(parentLocalUuid) : const Value.absent(),
        parentServerId: parentServerId != null ? Value(parentServerId) : const Value.absent(),
        linkType: Value(linkType),
        childField: Value(childField),
        parentField: Value(parentField),
        status: Value(PendingLinkStatus.pending),
        resolveAttempts: const Value(0),
        createdAt: Value(now),
        metadataJson: metadata != null ? Value(jsonEncode(metadata)) : const Value.absent(),
      ),
    );
  }

  /// الحصول على جميع الروابط المعلقة لكيان فرعي محدد
  Future<List<PendingLink>> getPendingForChild({
    required String childEntity,
    required String childLocalUuid,
  }) async {
    return (select(pendingLinks)
          ..where((t) =>
              t.childEntity.equals(childEntity) &
              t.childLocalUuid.equals(childLocalUuid) &
              t.status.equals(PendingLinkStatus.pending)))
        .get();
  }

  /// الحصول على جميع الروابط المعلقة لكيان أب محدد
  Future<List<PendingLink>> getPendingForParent({
    required String parentEntity,
    required String parentLocalUuid,
  }) async {
    return (select(pendingLinks)
          ..where((t) =>
              t.parentEntity.equals(parentEntity) &
              t.parentLocalUuid.equals(parentLocalUuid) &
              t.status.equals(PendingLinkStatus.pending)))
        .get();
  }

  /// الحصول على جميع الروابط المعلقة (للإصلاح الدوري)
  Future<List<PendingLink>> getAllPending() async {
    return (select(pendingLinks)
          ..where((t) => t.status.equals(PendingLinkStatus.pending))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  /// محاولة حل رابط معلق
  Future<bool> tryResolveLink(int linkId, {String? resolvedParentLocalUuid, String? resolvedParentServerId}) async {
    final link = await (select(pendingLinks)..where((t) => t.id.equals(linkId))).getSingleOrNull();
    if (link == null || link.status != PendingLinkStatus.pending) {
      return false;
    }

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final newAttempts = link.resolveAttempts + 1;
    final maxAttempts = 10;

    if (resolvedParentLocalUuid != null || resolvedParentServerId != null) {
      // تم العثور على الأب — حل الرابط
      return update(pendingLinks).replace(
        PendingLinksCompanion(
          id: Value(linkId),
          status: Value(PendingLinkStatus.resolved),
          resolveAttempts: Value(newAttempts),
          lastAttemptAt: Value(now),
          resolvedAt: Value(now),
          parentLocalUuid: resolvedParentLocalUuid != null ? Value(resolvedParentLocalUuid) : const Value.absent(),
          parentServerId: resolvedParentServerId != null ? Value(resolvedParentServerId) : const Value.absent(),
        ),
      ) > 0;
    } else if (newAttempts >= maxAttempts) {
      // تجاوز الحد الأقصى للمحاولات — وسم كفاشل
      return update(pendingLinks).replace(
        PendingLinksCompanion(
          id: Value(linkId),
          status: Value(PendingLinkStatus.failed),
          resolveAttempts: Value(newAttempts),
          lastAttemptAt: Value(now),
          lastError: Value('Max resolve attempts ($maxAttempts) reached'),
        ),
      ) > 0;
    } else {
      // محاولة أخرى — تحديث العداد فقط
      return update(pendingLinks).replace(
        PendingLinksCompanion(
          id: Value(linkId),
          resolveAttempts: Value(newAttempts),
          lastAttemptAt: Value(now),
        ),
      ) > 0;
    }
  }

  /// حل جميع الروابط المعلقة لكيان أب عند وصوله
  Future<int> resolveAllForParent({
    required String parentEntity,
    required String parentLocalUuid,
    String? parentServerId,
  }) async {
    final links = await getPendingForParent(
      parentEntity: parentEntity,
      parentLocalUuid: parentLocalUuid,
    );

    int resolvedCount = 0;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    for (final link in links) {
      final success = await update(pendingLinks).replace(
        PendingLinksCompanion(
          id: Value(link.id),
          status: Value(PendingLinkStatus.resolved),
          resolveAttempts: Value(link.resolveAttempts + 1),
          lastAttemptAt: Value(now),
          resolvedAt: Value(now),
          parentLocalUuid: Value(parentLocalUuid),
          parentServerId: parentServerId != null ? Value(parentServerId) : const Value.absent(),
        ),
      );
      if (success) resolvedCount++;
    }

    return resolvedCount;
  }

  /// تنظيف الروابط المحلولة القديمة (أقدم من 30 يوم)
  Future<int> cleanupOldResolved({int olderThanDays = 30}) async {
    final cutoff = DateTime.now().subtract(Duration(days: olderThanDays)).millisecondsSinceEpoch ~/ 1000;
    return (delete(pendingLinks)
          ..where((t) =>
              t.status.equals(PendingLinkStatus.resolved) &
              t.resolvedAt.isSmallerThanValue(cutoff)))
        .go();
  }

  /// الحصول على إحصائيات الروابط المعلقة
  Future<Map<String, int>> getStats() async {
    final all = await select(pendingLinks).get();
    return {
      'total': all.length,
      'pending': all.where((l) => l.status == PendingLinkStatus.pending).length,
      'resolved': all.where((l) => l.status == PendingLinkStatus.resolved).length,
      'failed': all.where((l) => l.status == PendingLinkStatus.failed).length,
    };
  }

  /// مراقبة الروابط المعلقة لكيان فرعي
  Stream<List<PendingLink>> watchPendingForChild({
    required String childEntity,
    required String childLocalUuid,
  }) {
    return (select(pendingLinks)
          ..where((t) =>
              t.childEntity.equals(childEntity) &
              t.childLocalUuid.equals(childLocalUuid) &
              t.status.equals(PendingLinkStatus.pending)))
        .watch();
  }
}