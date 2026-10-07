// lib/services/sync_core/financial_link_store.dart
//
// ✅ (G-1 / G-2 — 2026-10-06): مخزن **الروابط المالية الدائمة** التي كانت
// تُبنى لحظة الرفع فقط، فتنكسر عند تبديل المزوّد أو غياب صف الأب محلياً.
//
// **المشكلتان كما أُثبتتا في الكود (تدقيق §3.3):**
//   • G-1: `salary_payments` بلا `cycle_uuid` — الرابط يُبنى في
//     `appwrite_sync_manager` (`paymentCycle.localUuid`) لحظة الرفع فقط.
//     غياب صف الدورة وقت الرفع ⇒ تُرفع الدفعة بالمعرّف الرقمي وحده.
//   • G-2: `salary_carry_over_logs.from_cycle_id/to_cycle_id` لا يُكتبان
//     إطلاقاً (لا في الإدراج ولا في الحمولة) ⇒ سجل الترحيل بلا علاقة
//     دورات ثابتة.
//
// **المبدأ الحاكم (البند 12 — لا تخمين):**
//   لا يُكتب أي رابط إلا إن كان **مُثبتاً** بأحد مصدرين:
//     1) `UUID` ورد في الحمولة نفسها من المزوّد (هوية معلنة).
//     2) مفتاح أجنبي محلي سليم (`salary_payments.cycle_id → salary_cycles.id`)
//        أو مفتاح دورة حتمي (`cycle_key`/`hotel_day_start` يطابق بداية الدورة
//        بدقة) **ولمطابقة واحدة فقط**. صفر مطابقة أو أكثر من واحدة ⇒ لا كتابة.
//   ولا يُعدَّل أي مبلغ أو تاريخ أو حالة — الكتابة على عمود الهوية فقط.
//
// ملاحظة تنفيذية: العمود يُنشأ في `local_db.beforeOpen` (إضافي، idempotent)
// لذا لا يعتمد هذا الملف على إعادة توليد `local_db.g.dart`.
import 'package:drift/drift.dart' show Variable;

import '../local_db.dart';

class FinancialLinkStore {
  FinancialLinkStore(this.db);

  final AppDatabase db;

  /// اسم عمود الهوية على `salary_payments` (قيمة السلسلة = UUID الدورة).
  static const String paymentCycleColumn = 'cycle_uuid';

  // ─────────────────────────────────────────────────────────────────────
  // G-1 — رابط الدفعة ↔ الدورة
  // ─────────────────────────────────────────────────────────────────────

  /// يقرأ `cycle_uuid` المخزَّن لدفعة (null إن لم يوجد أو لم يُكتب بعد).
  Future<String?> paymentCycleUuid(String paymentLocalUuid) async {
    if (paymentLocalUuid.isEmpty) return null;
    try {
      final row = await db
          .customSelect(
            'SELECT $paymentCycleColumn AS c FROM salary_payments '
            'WHERE local_uuid = ? LIMIT 1',
            variables: [Variable.withString(paymentLocalUuid)],
          )
          .getSingleOrNull();
      if (row == null) return null;
      final value = row.data['c'];
      if (value == null) return null;
      final text = value.toString().trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      // العمود غير موجود (تثبيت قديم لم يُفتح بعد) — لا كسر للمزامنة.
      return null;
    }
  }

  /// يثبّت رابط الدورة على الدفعة إن كان مفقوداً — ويُعيد الرابط الفعلي
  /// (المخزَّن، أو المُثبت الآن، أو القيمة المفضَّلة المُمرَّرة).
  ///
  /// الترتيب (كلٌّ منها **دليل** لا تخمين):
  ///   1) `cycle_uuid` المخزَّن مسبقاً (لا يُدهَس أبداً بقيمة أضعف).
  ///   2) [preferredCycleUuid] — UUID ورد من الحمولة/معروف من الدورة.
  ///   3) [fallbackCycleLocalId] — مفتاح أجنبي محلي: يُترجم إلى
  ///      `salary_cycles.local_uuid` لنفس الصف.
  ///
  /// لا يكتب شيئاً إن لم يتوفر دليل (يبقى null ويظهر في تقرير المراجعة G-8).
  Future<String?> stampPaymentCycleIfMissing({
    required String paymentLocalUuid,
    String? preferredCycleUuid,
    int? fallbackCycleLocalId,
  }) async {
    if (paymentLocalUuid.isEmpty) return null;

    final existing = await paymentCycleUuid(paymentLocalUuid);
    if (existing != null) return existing;

    var resolved = (preferredCycleUuid ?? '').trim();
    if (resolved.isEmpty && fallbackCycleLocalId != null) {
      resolved = (await cycleUuidById(fallbackCycleLocalId)) ?? '';
    }
    if (resolved.isEmpty) return null;

    try {
      await db.customStatement(
        'UPDATE salary_payments SET $paymentCycleColumn = ? '
        "WHERE local_uuid = ? AND ($paymentCycleColumn IS NULL "
        "OR TRIM($paymentCycleColumn) = '')",
        [resolved, paymentLocalUuid],
      );
    } catch (_) {
      // فشل الكتابة لا يجوز أن يُسقط المزامنة — تُعاد المحاولة لاحقاً.
    }
    return resolved;
  }

  /// UUID دورة من معرّفها المحلي (مفتاح أجنبي سليم ⇒ ربط حتمي).
  Future<String?> cycleUuidById(int cycleLocalId) async {
    try {
      final row = await db
          .customSelect(
            'SELECT local_uuid AS u FROM salary_cycles WHERE id = ? LIMIT 1',
            variables: [Variable.withInt(cycleLocalId)],
          )
          .getSingleOrNull();
      final value = row?.data['u']?.toString().trim();
      return (value == null || value.isEmpty) ? null : value;
    } catch (_) {
      return null;
    }
  }

  /// يمشي على الدفعات التي رابط دورتها مفقود ويثبّته من المفتاح الأجنبي
  /// المحلي السليم (`cycle_id → salary_cycles.id`).
  ///
  /// حتمي بالكامل: لا مطابقة بالمبلغ/التاريخ/التشابه — فقط صلة FK حقيقية
  /// قائمة في القاعدة. تُستدعى بحدّ أعلى (bounded) من مسار المزامنة.
  Future<int> stampProvablePaymentCycles({int limit = 500}) async {
    try {
      final rows = await db
          .customSelect(
            'SELECT p.id AS pid, c.local_uuid AS cuuid FROM salary_payments p '
            'JOIN salary_cycles c ON c.id = p.cycle_id '
            "WHERE p.$paymentCycleColumn IS NULL "
            "OR TRIM(p.$paymentCycleColumn) = '' "
            "OR p.$paymentCycleColumn != c.local_uuid "
            'LIMIT ?',
            variables: [Variable.withInt(limit)],
          )
          .get();
      if (rows.isEmpty) return 0;
      var stamped = 0;
      for (final row in rows) {
        final cycleUuid = row.data['cuuid']?.toString().trim() ?? '';
        final paymentId = row.data['pid'] as int?;
        if (cycleUuid.isEmpty || paymentId == null) continue;
        try {
          await db.customStatement(
            'UPDATE salary_payments SET $paymentCycleColumn = ? WHERE id = ?',
            [cycleUuid, paymentId],
          );
          stamped++;
        } catch (_) {
          // صف واحد فشل — نكمل البقية.
        }
      }
      return stamped;
    } catch (_) {
      return 0;
    }
  }

  /// ملخص الرابط (للتقرير G-8): إجمالي الدفعات · المرتبطة · غير المرتبطة.
  Future<Map<String, int>> paymentCycleLinkSummary() async {
    try {
      final row = await db
          .customSelect(
            'SELECT COUNT(*) AS total, '
            "SUM(CASE WHEN $paymentCycleColumn IS NOT NULL "
            "AND TRIM($paymentCycleColumn) != '' THEN 1 ELSE 0 END) AS linked "
            'FROM salary_payments WHERE deleted_at IS NULL',
          )
          .getSingle();
      final total = (row.data['total'] as int?) ?? 0;
      final linked = (row.data['linked'] as int?) ?? 0;
      return {
        'payments_total': total,
        'payments_cycle_linked': linked,
        'payments_cycle_unlinked': total - linked,
      };
    } catch (_) {
      return const {
        'payments_total': 0,
        'payments_cycle_linked': 0,
        'payments_cycle_unlinked': 0,
      };
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // G-2 — رابط سجل الترحيل ↔ الدورتين
  // ─────────────────────────────────────────────────────────────────────

  /// UUID الدورة المطابقة لفترة **بمطابقة واحدة فقط**.
  ///
  /// المطابقة حتمية ومعلنة:
  ///   • `hotel_day_start` == [cycleStartIsoDate] (yyyy-MM-dd) — أدق دليل، أو
  ///   • `cycle_key` == [monthKey] (yyyy-MM) مع غياب/تطابق `hotel_day_start`.
  /// أكثر من صف أو صفر صف ⇒ null (لا تخمين — يظهر في تقرير المراجعة).
  Future<String?> cycleUuidForPeriod({
    required int employeeId,
    required String cycleStartIsoDate,
    String? monthKey,
  }) async {
    if (cycleStartIsoDate.isEmpty) return null;
    try {
      final rows = await db
          .customSelect(
            'SELECT local_uuid AS u FROM salary_cycles '
            'WHERE employee_id = ? AND ('
            '  hotel_day_start = ? '
            "  OR (hotel_day_start IS NULL AND cycle_key = ?)"
            ') LIMIT 2',
            variables: [
              Variable.withInt(employeeId),
              Variable.withString(cycleStartIsoDate),
              Variable.withString(
                monthKey ?? cycleStartIsoDate.substring(0, 7),
              ),
            ],
          )
          .get();
      if (rows.length != 1) return null; // صفر أو متعدد ⇒ لا ربط
      final value = rows.first.data['u']?.toString().trim() ?? '';
      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  /// ملخص الروابط الدائمة على مستوى القاعدة (للتقرير G-8).
  Future<Map<String, int>> summary() async {
    final paymentLinks = await paymentCycleLinkSummary();
    var carryLinked = 0;
    var carryTotal = 0;
    try {
      final row = await db
          .customSelect(
            'SELECT COUNT(*) AS total, '
            'SUM(CASE WHEN (from_cycle_id IS NOT NULL '
            "AND TRIM(from_cycle_id) != '') AND (to_cycle_id IS NOT NULL "
            "AND TRIM(to_cycle_id) != '') THEN 1 ELSE 0 END) AS linked "
            'FROM salary_carry_over_logs WHERE deleted_at IS NULL',
          )
          .getSingle();
      carryTotal = (row.data['total'] as int?) ?? 0;
      carryLinked = (row.data['linked'] as int?) ?? 0;
    } catch (_) {
      // لا شيء — تبقى الأصفار.
    }
    return {
      ...paymentLinks,
      'carry_over_total': carryTotal,
      'carry_over_cycle_linked': carryLinked,
      'carry_over_cycle_unlinked': carryTotal - carryLinked,
    };
  }
}
