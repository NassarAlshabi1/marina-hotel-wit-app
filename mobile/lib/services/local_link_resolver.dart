import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'local_db.dart';

/// صف في `pending_links` — سجل وصل رابطُه الأبوي متأخراً.
///
/// وثيقة الربط والمزامنة الموحدة §5.2: السجل **لا يُحذف ولا يُنسب تخميناً**؛
/// يُحفظ هنا بعد أن يُخزَّن محلياً بحالة unresolved، وتُعاد المحاولة عند
/// وصول الأب، ويظهر سببه في تقرير الصيانة.
class PendingLink {
  const PendingLink({
    required this.id,
    required this.entity,
    required this.localUuid,
    required this.missingKind,
    required this.missingUuid,
    required this.attempts,
    this.lastError,
    this.payloadJson,
  });

  final int id;

  /// `expense` | `salary_withdrawal` | `salary_cycle` | `salary_payment` |
  /// `salary_carry_over_log`
  final String entity;

  /// هوية السجل صاحب الرابط الناقص (ثابتة عبر الأجهزة).
  final String localUuid;

  /// نوع الأب المفقود: `employee_uuid` | `expense_uuid`.
  final String missingKind;

  /// UUID الأب المفقود.
  final String missingUuid;

  final int attempts;
  final String? lastError;
  final String? payloadJson;

  @override
  String toString() =>
      'PendingLink($entity/$localUuid ← $missingKind=$missingUuid, '
      'attempts=$attempts)';
}

/// خدمة الربط المحلية الوحيدة (وثيقة الربط §5.1 — `LocalLinkResolver`).
///
/// المسؤولية الوحيدة: تحويل UUID إلى **الأرقام المحلية** التي تعتمد عليها
/// الاستعلامات والعلاقات (FK)، والعكس غير مسموح: لا يُستخدم رقم قادم من
/// Appwrite كمعرّف محلي أبداً (§1.3/3).
///
/// مبادئ ملزمة لهذه الخدمة:
/// - لا تخمين: إن لم يوجد الأب بالـ UUID ⇒ لا رقم (null) ولا fallback
///   إلى `employeeId`/`relatedId`/`expenseId` البعيدة (§5.3).
/// - لا كتابة إلى outbox ولا رفع `version`/`lastModified` عند الربط
///   (الربط تصحيح بنيوي محلي، لا تعديل مستخدم — §4.2/§10).
/// - السجلات غير المحلولة تُحفظ في `pending_links` وتُعاد المحاولة،
///   ولا تُحذف ولا تُسقط من outbox (§8.1/§8.2).
class LocalLinkResolver {
  LocalLinkResolver(this._db);

  final AppDatabase _db;

  // ═══════════════════════════════════════════════════════════════════
  //  1) حل الهوية: UUID ⇒ رقم محلي
  // ═══════════════════════════════════════════════════════════════════

  /// `employeeUuid → employees.id` (لا يتعامل مع صف محذوف منطقياً).
  Future<int?> employeeIdForUuid(String? employeeUuid) async {
    final uuid = employeeUuid?.trim();
    if (uuid == null || uuid.isEmpty) return null;

    final rows = await _db
        .customSelect(
          'SELECT id FROM employees '
          'WHERE local_uuid = ? AND deleted_at IS NULL LIMIT 1',
          variables: [Variable.withString(uuid)],
          readsFrom: {_db.employees},
        )
        .get();
    if (rows.isEmpty) return null;
    final value = rows.first.data['id'];
    return value is int ? value : int.tryParse('$value');
  }

  /// `expenseUuid → expenses.id` (نشط فقط).
  Future<int?> expenseIdForUuid(String? expenseUuid) async {
    final uuid = expenseUuid?.trim();
    if (uuid == null || uuid.isEmpty) return null;

    final rows = await _db
        .customSelect(
          'SELECT id FROM expenses '
          'WHERE local_uuid = ? AND deleted_at IS NULL LIMIT 1',
          variables: [Variable.withString(uuid)],
          readsFrom: {_db.expenses},
        )
        .get();
    if (rows.isEmpty) return null;
    final value = rows.first.data['id'];
    return value is int ? value : int.tryParse('$value');
  }

  /// حل دفعة من الـ UUIDs باستعلام واحد (بدل N استعلاماً في مسارات السحب).
  Future<Map<String, int>> employeeIdsForUuids(Iterable<String> uuids) async {
    final unique = uuids
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (unique.isEmpty) return const <String, int>{};

    final placeholders = List<String>.filled(unique.length, '?').join(',');
    final rows = await _db
        .customSelect(
          'SELECT local_uuid, id FROM employees '
          'WHERE deleted_at IS NULL AND local_uuid IN ($placeholders)',
          variables: unique.map(Variable.withString).toList(),
          readsFrom: {_db.employees},
        )
        .get();

    return <String, int>{
      for (final row in rows)
        '${row.data['local_uuid']}': row.data['id'] is int
            ? row.data['id'] as int
            : int.tryParse('${row.data['id']}') ?? 0,
    };
  }

  // ═══════════════════════════════════════════════════════════════════
  //  2) pending_links: حفظ السجل غير المحلول وإعادة المحاولة
  // ═══════════════════════════════════════════════════════════════════

  /// يسجّل سجلاً لم يُحلّ أبوه. آمن للتكرار: نفس (entity, localUuid,
  /// missingKind, missingUuid) لا يُنشئ صفاً ثانياً — تُزاد المحاولات فقط.
  Future<void> recordPendingLink({
    required String entity,
    required String localUuid,
    required String missingKind,
    required String missingUuid,
    Map<String, dynamic>? payload,
    String? lastError,
  }) async {
    if (entity.trim().isEmpty ||
        localUuid.trim().isEmpty ||
        missingKind.trim().isEmpty ||
        missingUuid.trim().isEmpty) {
      return;
    }

    final now = DateTime.now().toUtc().toIso8601String();
    await _db.customStatement(
      'INSERT INTO pending_links '
      '(entity, local_uuid, missing_kind, missing_uuid, payload_json, '
      ' attempts, last_error, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?) '
      'ON CONFLICT(entity, local_uuid, missing_kind, missing_uuid) DO UPDATE '
      'SET attempts = attempts + 1, last_error = excluded.last_error, '
      '    updated_at = excluded.updated_at',
      [
        entity.trim(),
        localUuid.trim(),
        missingKind.trim(),
        missingUuid.trim(),
        payload == null ? null : jsonEncode(payload),
        lastError,
        now,
        now,
      ],
    );
  }

  /// يعيد محاولة كل الروابط المعلّقة (أو نوعاً واحداً) بعد وصول آباء جدد.
  /// يعيد عدد السجلات التي حُلّت فعلاً.
  ///
  /// لا يلمس صفاً لم يُحلّ: يُحدّث `attempts`/`last_error` فقط — فلا فقدان
  /// ولا نسبة تخمينية، ويستمر ظهوره في تقرير الصيانة (§11).
  Future<int> retryPendingLinks({
    String? missingKind,
    int limit = 500,
    Future<bool> Function(String entity, Map<String, dynamic> payload)? reapply,
  }) async {
    final where = missingKind == null ? '' : 'WHERE missing_kind = ?';
    final rows = await _db
        .customSelect(
          'SELECT * FROM pending_links $where ORDER BY attempts ASC, id ASC '
          'LIMIT ?',
          variables: [
            if (missingKind != null) Variable.withString(missingKind),
            Variable.withInt(limit),
          ],
          readsFrom: const {},
        )
        .get();

    var resolved = 0;
    for (final row in rows) {
      final id = row.data['id'] as int;
      final entity = '${row.data['entity']}';
      final localUuid = '${row.data['local_uuid']}';
      final kind = '${row.data['missing_kind']}';
      final parentUuid = '${row.data['missing_uuid']}';

      final parentId = switch (kind) {
        'employee_uuid' => await employeeIdForUuid(parentUuid),
        'expense_uuid' => await expenseIdForUuid(parentUuid),
        _ => null,
      };

      if (parentId == null) {
        await _db.customStatement(
          'UPDATE pending_links '
          'SET attempts = attempts + 1, '
          '    last_error = ?, updated_at = ? '
          'WHERE id = ?',
          [
            'الأب غير موجود بعد: $kind=$parentUuid',
            DateTime.now().toUtc().toIso8601String(),
            id,
          ],
        );
        continue;
      }

      final appliedRows = await _applyResolvedParent(
        entity: entity,
        localUuid: localUuid,
        missingKind: kind,
        parentId: parentId,
      );

      // ✅ PR-5 (§8.1): السجل الذي لم يُدرج أصلاً (تخطّي عند السحب) لا صف
      // له ليُحدَّث — نُعيد إدخاله من الحمولة المحفوظة بعد أن صار الأب
      // موجوداً. بلا هذا يبقى «مربوطاً» على الورق ومفقوداً فعلياً.
      var applied = appliedRows > 0;
      if (appliedRows == 0 && reapply != null) {
        final payloadJson = row.data['payload_json'];
        if (payloadJson is String && payloadJson.trim().isNotEmpty) {
          try {
            final payload =
                jsonDecode(payloadJson) as Map<String, dynamic>;
            applied = await reapply(entity, payload);
          } catch (e) {
            await _db.customStatement(
              'UPDATE pending_links '
              'SET attempts = attempts + 1, last_error = ?, updated_at = ? '
              'WHERE id = ?',
              [
                'تعذّر إعادة تطبيق الحمولة المحفوظة: $e',
                DateTime.now().toUtc().toIso8601String(),
                id,
              ],
            );
            continue;
          }
        }
      }

      if (applied) {
        await _db.customStatement('DELETE FROM pending_links WHERE id = ?', [
          id,
        ]);
        resolved++;
      } else {
        await _db.customStatement(
          'UPDATE pending_links '
          'SET attempts = attempts + 1, '
          '    last_error = ?, updated_at = ? '
          'WHERE id = ?',
          [
            'نوع غير معروف للربط: entity=$entity kind=$kind',
            DateTime.now().toUtc().toIso8601String(),
            id,
          ],
        );
      }
    }
    return resolved;
  }

  /// كتابة الرقم المحلي في العمود الصحيح — بلا أي تعديل على هوية السجل أو
  /// `version`/`lastModified` (الربط ليس تعديل مستخدم).
  ///
  /// يعيد `true` فقط إذا كان (entity, missingKind) معروفاً — وإلا لا يكتب
  /// شيئاً بدل تخمين عمود قد يُنسب لموظف آخر.
  Future<int> _applyResolvedParent({
    required String entity,
    required String localUuid,
    required String missingKind,
    required int parentId,
  }) async {
    final (table, column) = switch ((entity, missingKind)) {
      ('expense', 'employee_uuid') => ('expenses', 'related_id'),
      ('salary_withdrawal', 'employee_uuid') => (
        'salary_withdrawals',
        'employee_id',
      ),
      ('salary_withdrawal', 'expense_uuid') => (
        'salary_withdrawals',
        'expense_id',
      ),
      ('salary_cycle', 'employee_uuid') => ('salary_cycles', 'employee_id'),
      ('salary_payment', 'employee_uuid') => ('salary_payments', 'employee_id'),
      ('salary_carry_over_log', 'employee_uuid') => (
        'salary_carry_over_logs',
        'employee_id',
      ),
      _ => (null, null),
    };

    if (table == null || column == null) return -1;

    // عدد الصفوف المحدَّثة هو الفرق الحقيقي بين «رُبط صفٌّ موجود» و«الصف
    // لم يُدرج أصلاً لأن السحب تخطّاه» (انظر reapply في retryPendingLinks).
    return _db.customStatement(
      'UPDATE $table SET $column = ? WHERE local_uuid = ?',
      [parentId, localUuid],
    );
  }

  /// الروابط المعلّقة (للتقرير / شاشة الصيانة).
  Future<List<PendingLink>> pendingLinks({
    String? missingKind,
    int limit = 200,
  }) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM pending_links '
          '${missingKind == null ? '' : 'WHERE missing_kind = ? '}'
          'ORDER BY attempts DESC, id ASC LIMIT ?',
          variables: [
            if (missingKind != null) Variable.withString(missingKind),
            Variable.withInt(limit),
          ],
          readsFrom: const {},
        )
        .get();

    return rows
        .map(
          (row) => PendingLink(
            id: row.data['id'] as int,
            entity: '${row.data['entity']}',
            localUuid: '${row.data['local_uuid']}',
            missingKind: '${row.data['missing_kind']}',
            missingUuid: '${row.data['missing_uuid']}',
            attempts: (row.data['attempts'] as int?) ?? 0,
            lastError: row.data['last_error'] as String?,
            payloadJson: row.data['payload_json'] as String?,
          ),
        )
        .toList();
  }

  /// عدد الروابط المعلّقة (يُعرض في الشارة/التقرير).
  Future<int> pendingLinksCount() async {
    final rows = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM pending_links',
          readsFrom: const {},
        )
        .get();
    final value = rows.isEmpty ? 0 : rows.first.data['c'];
    return value is int ? value : int.tryParse('$value') ?? 0;
  }

  /// للاختبارات فقط: هل عمود الربط موجود في القاعدة (تحقّق من مخطط PR-1)؟
  @visibleForTesting
  Future<bool> columnExists(String table, String column) async {
    final info = await _db.customSelect('PRAGMA table_info($table)').get();
    return info.any((row) => row.data['name'] == column);
  }
}
