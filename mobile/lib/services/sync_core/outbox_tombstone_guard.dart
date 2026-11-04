import 'package:drift/drift.dart' as drift;

import '../local_db.dart';

/// ✅ (2026-11-04 — وثيقة الربط والمزامنة الموحدة §7.5/§8.2) حارس
/// Tombstone لعناصر Outbox — يمنع عنصر رفع قديماً من إحياء سجل حذفته
/// السحابة، عبر تعليمه `superseded_by_cloud`.
///
/// القاعدة:
/// - الصف المحلي محذوف منطقياً بوصلة سحابية (origin='server' + deletedAt).
/// - وعنصر الـ outbox أقدم من آخر تعديل للصف (clientTs ≤ lastModified).
/// → الرفع سيعيد إحياء المحذوف على السحابة — يُعلَّم العنصر ولا يُرفع.
///
/// الاستثناء المقصود: تعديل محلي جديد بعد وصول tombstone (clientTs أحدث)
/// يُرفع — قرار المستخدم المحلي الأخير.
///
/// قائمة بيضاء للجداول المالية/الأساسية — كيانات غير معروفة تُتجاوز
/// بلا حارس (سلوك قديم)، وكل فشل غير معطل للرفع العادي.
class OutboxTombstoneGuard {
  const OutboxTombstoneGuard();

  static const Map<String, String> guardTables = {
    'employees': 'employees',
    'expenses': 'expenses',
    'salary_withdrawals': 'salary_withdrawals',
    'salary_cycles': 'salary_cycles',
    'salary_payments': 'salary_payments',
    'salary_carry_over_logs': 'salary_carry_over_logs',
    'bookings': 'bookings',
    'booking_nights': 'booking_nights',
    'booking_notes': 'booking_notes',
    'booking_price_adjustments': 'booking_price_adjustments',
    'payments': 'payments',
    'debts': 'debts',
    'cash_transactions': 'cash_transactions',
    'rooms': 'rooms',
    'guest_infos': 'guest_infos',
    'shift_notes': 'shift_notes',
  };

  /// يفحص العنصر ويُعلمه `superseded_by_cloud` عند التجاوز.
  ///
  /// returns: true إذا عُلّم العنصر (يجب ألا يُرفع)، false للسماح بالرفع.
  Future<bool> supersedeIfStaleOverCloudTombstone({
    required AppDatabase db,
    required String entity,
    required String localUuid,
    required int outboxRowId,
    required int clientTs,
    String op = 'update',
  }) async {
    if (op == 'delete') return false; // الحذف حذف — لا إحياء
    final table = guardTables[entity];
    if (table == null) return false;

    try {
      final row = await db
          .customSelect(
            'SELECT deleted_at, last_modified, origin FROM "$table" '
            'WHERE local_uuid = ? LIMIT 1',
            variables: [drift.Variable<String>(localUuid)],
          )
          .getSingleOrNull();
      if (row == null) return false;

      final deletedAt = row.data['deleted_at'];
      final origin = (row.data['origin'] ?? '').toString();
      final lastModifiedRaw = row.data['last_modified'];
      final lastModified = lastModifiedRaw is int
          ? lastModifiedRaw
          : int.tryParse('$lastModifiedRaw') ?? 0;

      final isCloudTombstone = deletedAt != null && origin == 'server';
      final entryIsStale = clientTs <= lastModified;
      if (!isCloudTombstone || !entryIsStale) return false;

      await db.customUpdate(
        'UPDATE outbox SET processing_status = ?, last_error = ? WHERE id = ?',
        variables: [
          const drift.Variable<String>('superseded_by_cloud'),
          const drift.Variable<String>(
            'superseded_by_cloud: tombstone سحابي وصل بعد إنشاء هذه العملية — '
            'الرفع سيعيد إحياء المحذوف (وثيقة §7.5/§8.2)',
          ),
          drift.Variable<int>(outboxRowId),
        ],
        updates: {db.outbox},
      );
      return true;
    } catch (_) {
      // فشل الحارس لا يعطل الرفع العادي — سلوك قديم.
      return false;
    }
  }
}
