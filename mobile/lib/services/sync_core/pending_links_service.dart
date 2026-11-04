import 'dart:convert';

import 'package:drift/drift.dart' as d;

import '../local_db.dart';

/// ✅ «وثيقة الربط والمزامنة Appwrite الموحدة» — §4.1 / §5.2 / §8.1 (PR-5).
///
/// الخدمة الوحيدة التي تدير جدول `pending_links` (أنشأه الترحيل 75):
/// حفظ — بشكل دائم وقابل لإعادة المحاولة — الـ payloads الواردة من السحابة
/// التي لم يُحل رابطها الأبوي محلياً (موظف/مصروف/دورة لم يصلوا بعد)، بحيث:
///
/// - **لا حذف نهائي أبداً** لسجل مالي لأن أبوه لم يصل (§1.3-1)؛
/// - **يمكن للمؤشر (checkpoint) التقدم** بعد الحفظ الدائم لأن الـ payload
///   محفوظ محلياً (§8.1: «يُحفظ في pending_links، ثم يمكن التقدم لأن
///   payload محفوظ محلياً بشكل دائم؛ لا يجوز التقدم إذا لم يتم حفظه»)؛
/// - **إعادة المحاولة بعد وصول الأب** (§8.1: «بعد سحب employees/expenses،
///   إعادة محاولة pending links»)؛
/// - **سبب التعذر وعدد المحاولات معروضان** في تقرير السلامة (§5.2/§11).
///
/// تغطية الكيانات: salary_cycles / salary_payments / salary_carry_over_logs
/// (اليتيم فيها كان يُرمى أو يجمّد checkpoint). أما:
/// - `expenses`: يُحفظ الصف نفسه محلياً بـ employeeUuid ويُعاد ربط
///   relatedId عبر `_relinkOrphanSalaryExpenses` — لا حاجة لصف pending؛
/// - `salary_withdrawals`: لها طابور يتامى دائم خاص (pending queue في
///   الإعدادات) مع تحكيم مطالبة المرآة — يبقى كما هو (لا ازدواج وظيفة).
///
/// القيد (entity, local_uuid) يمنع التكرار؛ الإدخال الثاني لنفس الهوية
/// يحدّث الـ payload والسبب ويزيد عداد المحاولات ويعيد فتح الصف
/// (resolvedAt = NULL) إن كان قد حُلّ سابقاً.
class PendingLinksService {
  PendingLinksService(this.db);

  final AppDatabase db;

  /// يسجّل payload غير محلول (upsert على entity + localUuid).
  ///
  /// يعيد عدد المحاولات بعد التسجيل (للتشخيص/الاختبارات).
  Future<int> recordUnresolved({
    required String entity,
    required String localUuid,
    required String parentEntity,
    String? parentUuid,
    required Map<String, dynamic> payload,
    required String reason,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final payloadJson = jsonEncode(payload);
    final cleanUuid = localUuid.trim();
    final cleanParentUuid = parentUuid?.trim().isEmpty == true
        ? null
        : parentUuid?.trim();

    final existing = await (db.select(db.pendingLinks)
          ..where((r) => r.entity.equals(entity))
          ..where((r) => r.localUuid.equals(cleanUuid))
          ..limit(1))
        .getSingleOrNull();

    if (existing == null) {
      await db
          .into(db.pendingLinks)
          .insert(
            PendingLinksCompanion.insert(
              entity: entity,
              localUuid: cleanUuid,
              parentEntity: parentEntity,
              parentUuid: d.Value(cleanParentUuid),
              payloadJson: payloadJson,
              reason: reason,
              attempts: const d.Value(1),
              lastAttemptAt: d.Value(now),
              resolvedAt: const d.Value(null),
              resolvedHow: const d.Value(null),
              createdAt: now,
              updatedAt: now,
            ),
          );
      return 1;
    }

    // صف موجود: يُحدَّث (ويُعاد فتحه إن كان محلولاً) — لا صف ثانٍ أبداً.
    await (db.update(db.pendingLinks)..where((r) => r.id.equals(existing.id)))
        .write(
      PendingLinksCompanion(
        parentEntity: d.Value(parentEntity),
        parentUuid: d.Value(cleanParentUuid),
        payloadJson: d.Value(payloadJson),
        reason: d.Value(reason),
        attempts: d.Value(existing.attempts + 1),
        lastAttemptAt: d.Value(now),
        resolvedAt: const d.Value(null),
        resolvedHow: const d.Value(null),
        updatedAt: d.Value(now),
      ),
    );
    return existing.attempts + 1;
  }

  /// يعلّم صفًا كمُطبَّق (حُلّ قيد الأب ووُجد السجل محلياً).
  ///
  /// لا يحذف الصف — يبقى أثراً تشخيصياً (§1.3: لا حذف؛ §11 يعرض الحالة).
  Future<void> markResolved(
    String entity,
    String localUuid, {
    String how = 'parent_arrived',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await (db.update(db.pendingLinks)
          ..where((r) => r.entity.equals(entity))
          ..where((r) => r.localUuid.equals(localUuid.trim())))
        .write(
      PendingLinksCompanion(
        resolvedAt: d.Value(now),
        resolvedHow: d.Value(how),
        updatedAt: d.Value(now),
      ),
    );
  }

  /// الصفوف غير المحلولة — للاستعلام من مسار إعادة المحاولة والتقرير (§11).
  Future<List<PendingLinkRow>> unresolved({String? entity, int limit = 500}) {
    final query = db.select(db.pendingLinks)
      ..where((r) => r.resolvedAt.isNull())
      ..orderBy([
        (r) => d.OrderingTerm(
              expression: r.lastAttemptAt,
              mode: d.OrderingMode.asc,
            ),
      ])
      ..limit(limit);
    if (entity != null) {
      query.where((r) => r.entity.equals(entity));
    }
    return query.get();
  }

  /// الصفوف غير المحلولة المنتظرة أباً معيناً (فهرس idx_pending_links_parent).
  Future<List<PendingLinkRow>> unresolvedForParent({
    required String parentEntity,
    String? parentUuid,
    int limit = 500,
  }) {
    final query = db.select(db.pendingLinks)
      ..where((r) => r.parentEntity.equals(parentEntity))
      ..where((r) => r.resolvedAt.isNull())
      ..limit(limit);
    if (parentUuid != null && parentUuid.trim().isNotEmpty) {
      query.where((r) => r.parentUuid.equals(parentUuid.trim()));
    }
    return query.get();
  }

  /// عدد غير المحلول لكل كيان — لتقرير السلامة (§11).
  Future<Map<String, int>> unresolvedCountsByEntity() async {
    final countExp = db.pendingLinks.id.count();
    final query = db.selectOnly(db.pendingLinks)
      ..addColumns([db.pendingLinks.entity, countExp])
      ..where(db.pendingLinks.resolvedAt.isNull())
      ..groupBy([db.pendingLinks.entity]);
    final rows = await query.get();
    return {
      for (final row in rows)
        row.read(db.pendingLinks.entity) ?? '': row.read(countExp) ?? 0,
    };
  }

  /// إجمالي غير المحلول (كل الكيانات) — لتقرير السلامة (§11).
  Future<int> unresolvedCount() async {
    final countExp = db.pendingLinks.id.count();
    final query = db.selectOnly(db.pendingLinks)
      ..addColumns([countExp])
      ..where(db.pendingLinks.resolvedAt.isNull());
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }
}
