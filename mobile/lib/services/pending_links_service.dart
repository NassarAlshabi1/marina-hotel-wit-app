import 'daos/pending_links_dao.dart';
import 'local_db.dart';
import 'appwrite_sync_manager.dart';

/// خدمة لإدارة الروابط المؤجلة أثناء المزامنة
///
/// تُستخدم لتتبع علاقات الكيانات الفرعية التي تحتاج لكيانات آباء
/// لم تصل بعد من السحابة. تحل محل منطق "deferred" المؤقت في
/// appwrite_sync_manager.
class PendingLinksService {
  PendingLinksService(this.db) : _dao = PendingLinksDao(db);
  final AppDatabase db;
  final PendingLinksDao _dao;

  /// تسجيل رابط معلق لكيان فرعي تم مزامنته قبل أبيه
  Future<void> registerPendingLink({
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
    await _dao.addLink(
      childEntity: childEntity,
      childLocalUuid: childLocalUuid,
      parentEntity: parentEntity,
      childField: childField,
      parentLocalUuid: parentLocalUuid,
      parentServerId: parentServerId,
      linkType: linkType,
      parentField: parentField,
      metadata: metadata,
    );
  }

  /// محاولة حل الروابط المعلقة لكيان أب تم مزامنته للتو
  Future<int> tryResolveForParent({
    required String parentEntity,
    required String parentLocalUuid,
    String? parentServerId,
  }) async {
    return _dao.resolveAllForParent(
      parentEntity: parentEntity,
      parentLocalUuid: parentLocalUuid,
      parentServerId: parentServerId,
    );
  }

  /// معالجة دورية للروابط المعلقة (محاولة حلها)
  Future<void> processPendingLinks() async {
    final pending = await _dao.getAllPending();
    for (final link in pending) {
      // محاولة حل الرابط بناءً على معلومات الأب المتاحة
      await _tryResolveLink(link);
    }
  }

  Future<void> _tryResolveLink(PendingLink link) async {
    // محاولة العثور على الأب محلياً بـ UUID أو serverId
    String? parentLocalUuid;
    String? parentServerId;

    if (link.parentLocalUuid != null && link.parentLocalUuid!.isNotEmpty) {
      // لدينا UUID الأب — نحاول العثور عليه محلياً
      final parentTable = _getTableForEntity(link.parentEntity);
      if (parentTable != null) {
        final row = await (db.select(parentTable)
              ..where((t) => t.localUuid.equals(link.parentLocalUuid!))
              ..limit(1))
            .getSingleOrNull();
        if (row != null) {
          parentLocalUuid = row.localUuid;
          parentServerId = row.serverId?.toString();
        }
      }
    }

    await _dao.tryResolveLink(
      link.id,
      resolvedParentLocalUuid: parentLocalUuid,
      resolvedParentServerId: parentServerId,
    );
  }

  /// الحصول على جدول Drift لاسم كيان
  TableInfo<Table, dynamic>? _getTableForEntity(String entity) {
    switch (entity) {
      case 'bookings':
        return db.bookings;
      case 'expenses':
        return db.expenses;
      case 'employees':
        return db.employees;
      case 'salary_cycles':
        return db.salaryCycles;
      case 'payments':
        return db.payments;
      case 'debts':
        return db.debts;
      default:
        return null;
    }
  }

  /// تنظيف الروابط المحلولة القديمة
  Future<int> cleanup({int olderThanDays = 30}) async {
    return _dao.cleanupOldResolved(olderThanDays: olderThanDays);
  }

  /// الحصول على إحصائيات
  Future<Map<String, int>> getStats() async {
    return _dao.getStats();
  }
}