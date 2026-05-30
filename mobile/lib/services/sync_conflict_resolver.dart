import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../utils/app_logger.dart';

import '../utils/debug_logs.dart';
import 'local_db.dart';

/// استراتيجية حل التعارضات
enum ConflictStrategy { serverWins, localWins, manualReview }

/// نتيجة كشف/حل التعارض
class ConflictCheckResult {
  const ConflictCheckResult({
    this.isConflict = false,
    this.resolved = false,
    this.usedLocal = false,
    this.usedRemote = false,
    this.reason = '',
    this.conflictId,
  });

  /// هل يوجد تعارض فعلاً؟
  final bool isConflict;

  /// هل تم الحل تلقائياً؟
  final bool resolved;

  /// هل تم الاحتفاظ بالبيانات المحلية؟
  final bool usedLocal;

  /// هل تم تطبيق البيانات البعيدة؟
  final bool usedRemote;

  /// سبب القرار
  final String reason;

  /// معرف التعارض في جدول sync_conflicts (إذا تم تسجيله)
  final int? conflictId;
}

/// محلل تعارضات المزامنة - يكشف التعارضات الحقيقية ويسجلها ويحلها
///
/// يستخدم جدول sync_conflicts لتخزين التعارضات التي تحتاج مراجعة يدوية.
/// يعتمد على مقارنة lastModified و version لتحديد ما إذا كان هناك تعارض حقيقي.
class SyncConflictResolver {
  SyncConflictResolver(this.db);

  final AppDatabase db;

  /// كشف تعارض حقيقي عند سحب بيانات من السيرفر
  ///
  /// منطق كشف التعارض:
  /// - إذا السجل المحلي تم تعديله بعد آخر مزامنة (origin = 'local', modified > lastPullTs)
  /// - والسجل البعيد تم تعديله أيضاً (lastModified البعيد > lastModified المحلي)
  /// - فهذا تعارض حقيقي
  ///
  /// [table] اسم الجدول في قاعدة البيانات
  /// [localUuid] المعرف الفريد المحلي للسجل
  /// [remoteData] البيانات القادمة من السيرفر
  /// [strategy] استراتيجية الحل المطلوبة
  /// [lastPullTs] طابع زمني آخر سحب (يُقرأ من sync_state تلقائياً إذا لم يُمرر)
  ///
  /// returns: [ConflictCheckResult] يحتوي على نتيجة الكشف والحل
  Future<ConflictCheckResult> detectAndResolve({
    required String table,
    required String localUuid,
    required Map<String, dynamic> remoteData,
    required ConflictStrategy strategy,
    int? lastPullTs,
  }) async {
    try {
      // قراءة lastPullTs من sync_state إذا لم يُمرر
      lastPullTs ??= await _getLastPullTs();

      // البحث عن السجل المحلي
      final localRow = await _findLocalRow(table, localUuid);

      // إذا لم يكن هناك سجل محلي - لا يوجد تعارض، يمكن الإدراج مباشرة
      if (localRow == null) {
        return const ConflictCheckResult(
          reason: 'لا يوجد سجل محلي - لا يوجد تعارض',
        );
      }

      // استخراج بيانات السجل المحلي
      final localLastModified = _extractIntField(localRow, 'lastModified') ??
          _extractIntField(localRow, 'last_modified') ??
          0;
      final localVersion = _extractIntField(localRow, 'version') ?? 1;
      final localOrigin = _extractStringField(localRow, 'origin') ?? 'local';
      final remoteLastModified = (remoteData['lastModified'] as int?) ??
          (remoteData['last_modified'] as int?) ??
          0;
      final remoteVersion = (remoteData['version'] as int?) ?? 1;

      // حالة 1: السجل المحلي لم يتغير منذ آخر سحب - لا يوجد تعارض
      if (localOrigin != 'local' || localLastModified <= lastPullTs) {
        // السجل المحلي لم يُعدل محلياً - تطبيق البعيد بأمان
        return const ConflictCheckResult(
          resolved: true,
          usedRemote: true,
          reason: 'السجل المحلي لم يُعدل محلياً - تطبيق البيانات البعيدة',
        );
      }

      // حالة 2: السجل المحلي تم تعديله محلياً، تحقق مما إذا كان البعيد أيضاً معدلاً
      if (remoteLastModified <= localLastModified) {
        // البعيد ليس أحدث من المحلي - الاحتفاظ بالمحلي
        return const ConflictCheckResult(
          resolved: true,
          usedLocal: true,
          reason: 'البيانات المحلية أحدث من البعيدة - الاحتفاظ بالمحلي',
        );
      }

      // حالة 3: كلاهما معدّل - تعارض حقيقي!
      _log(
        '⚠️ تعارض حقيقي مكتشف: $table/$localUuid '
        '(محلي: v$localVersion@$localLastModified vs بعيد: v$remoteVersion@$remoteLastModified)',
      );

      // تطبيق الاستراتيجية
      switch (strategy) {
        case ConflictStrategy.serverWins:
          _log('🔧 حل تعارض $table/$localUuid: السيرفر يفوز');
          return const ConflictCheckResult(
            isConflict: true,
            resolved: true,
            usedRemote: true,
            reason:
                'تعارض حقيقي - تم اختيار بيانات السيرفر (serverWins strategy)',
          );

        case ConflictStrategy.localWins:
          _log('🔧 حل تعارض $table/$localUuid: المحلي يفوز');
          return const ConflictCheckResult(
            isConflict: true,
            resolved: true,
            usedLocal: true,
            reason:
                'تعارض حقيقي - تم الاحتفاظ بالبيانات المحلية (localWins strategy)',
          );

        case ConflictStrategy.manualReview:
          // تسجيل التعارض للمراجعة اليدوية
          final conflictId = await logConflict(
            table: table,
            localUuid: localUuid,
            localData: _rowToMap(localRow),
            remoteData: remoteData,
          );
          _log(
            '📝 تعارض $table/$localUuid: مُسجّل للمراجعة اليدوية (conflict#$conflictId)',
          );
          return ConflictCheckResult(
            isConflict: true,
            usedLocal: true,
            reason:
                'تعارض حقيقي - مُسجّل للمراجعة اليدوية (manualReview strategy)',
            conflictId: conflictId,
          );
      }
    } catch (e, st) {
      _log('❌ خطأ في كشف التعارض $table/$localUuid: $e');
      debugPrint('SyncConflictResolver.detectAndResolve stackTrace: $st');
      // في حالة الخطأ - الاحتفاظ بالمحلي كإجراء آمن
      return const ConflictCheckResult(
        resolved: true,
        usedLocal: true,
        reason: 'خطأ في الكشف - الاحتفاظ بالبيانات المحلية كإجراء آمن',
      );
    }
  }

  /// تسجيل تعارض للمراجعة اليدوية في جدول sync_conflicts
  ///
  /// [table] اسم الجدول
  /// [localUuid] المعرف الفريد المحلي
  /// [localData] البيانات المحلية (خريطة)
  /// [remoteData] البيانات البعيدة (خريطة)
  /// [logId] معرف سجل المزامنة (اختياري)
  ///
  /// returns: معرف التعارض المُسجّل
  Future<int> logConflict({
    required String table,
    required String localUuid,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> remoteData,
    int? logId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();

    try {
      final companion = SyncConflictsCompanion.insert(
        logId: logId ?? 0,
        targetTable: table,
        uuid: localUuid,
        resolution: 'pending',
        localPayload: jsonEncode(localData),
        remotePayload: jsonEncode(remoteData),
        createdAt: now,
      );

      final id = await db.into(db.syncConflicts).insert(companion);
      _log(
        '📝 تم تسجيل تعارض #$id في $table/$localUuid للمراجعة اليدوية',
      );
      return id;
    } catch (e) {
      _log('❌ فشل تسجيل التعارض $table/$localUuid: $e');
      rethrow;
    }
  }

  /// كشف تعارضات متعددة لجدول معين
  ///
  /// يفحص مجموعة من السجلات ويُرجع قائمة بالتعارضات المكتشفة
  Future<List<ConflictCheckResult>> detectBatchConflicts({
    required String table,
    required List<Map<String, dynamic>> remoteRecords,
    required ConflictStrategy strategy,
  }) async {
    final lastPullTs = await _getLastPullTs();
    final results = <ConflictCheckResult>[];

    for (final remoteData in remoteRecords) {
      final localUuid = (remoteData['local_uuid'] ?? remoteData['localUuid'])
          as String?;
      if (localUuid == null || localUuid.isEmpty) {
        continue;
      }

      final result = await detectAndResolve(
        table: table,
        localUuid: localUuid,
        remoteData: remoteData,
        strategy: strategy,
        lastPullTs: lastPullTs,
      );
      results.add(result);
    }

    final conflictCount = results.where((r) => r.isConflict).length;
    if (conflictCount > 0) {
      _log(
        '📊 كشف $conflictCount تعارض من ${remoteRecords.length} سجل في $table',
      );
    }

    return results;
  }

  /// جلب جميع التعارضات غير المحلولة
  Future<List<SyncConflictRow>> getPendingConflicts() async {
    return (db.select(db.syncConflicts)
          ..where((t) => t.resolution.equals('pending')))
        .get();
  }

  /// جلب التعارضات حسب الجدول
  Future<List<SyncConflictRow>> getConflictsByTable(String table) async {
    return (db.select(db.syncConflicts)
          ..where((t) => t.targetTable.equals(table)))
        .get();
  }

  /// حل تعارض يدوياً - اختيار البيانات المحلية أو البعيدة
  ///
  /// [conflictId] معرف التعارض
  /// [useRemote] true لاختيار البعيد، false للاحتفاظ بالمحلي
  /// [resolutionNote] ملاحظة اختيارية حول القرار
  Future<void> resolveManually({
    required int conflictId,
    required bool useRemote,
    String resolutionNote = '',
  }) async {
    final resolution = useRemote ? 'resolved_remote' : 'resolved_local';
    final note =
        resolutionNote.isNotEmpty ? resolutionNote : (useRemote ? 'تم اختيار البيانات البعيدة يدوياً' : 'تم الاحتفاظ بالبيانات المحلية يدوياً');

    await (db.update(db.syncConflicts)..where((t) => t.id.equals(conflictId)))
        .write(
          SyncConflictsCompanion(
            resolution: Value(resolution),
          ),
        );

    _log(
      '✅ تم حل التعارض #$conflictId يدوياً: $note',
    );
  }

  /// حذف التعارضات القديمة (أقدم من [maxAgeDays] يوماً)
  Future<int> cleanupOldConflicts({int maxAgeDays = 30}) async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: maxAgeDays))
        .toUtc()
        .toIso8601String();

    // استخدام استعلام مخصص لحذف التعارضات القديمة لتجنب تعقيد أنواع Drift
    final deleteResult = await db.customSelect(
      'DELETE FROM sync_conflicts WHERE resolution != ? AND created_at < ?',
      variables: [
        const Variable<String>('pending'),
        Variable<String>(cutoff),
      ],
    ).get();

    final resolvedConflicts = deleteResult.length;

    if (resolvedConflicts > 0) {
      _log('🧹 تم حذف $resolvedConflicts تعارض قديم (أقدم من $maxAgeDays يوم)');
    }
    return resolvedConflicts;
  }

  /// جلب عدد التعارضات المعلقة
  Future<int> getPendingConflictCount() async {
    final result = await db
        .customSelect(
          'SELECT COUNT(*) as cnt FROM sync_conflicts WHERE resolution = ?',
          variables: [const Variable<String>('pending')],
        )
        .getSingleOrNull();

    return result?.data['cnt'] as int? ?? 0;
  }

  // ─── دوال مساعدة خاصة ────────────────────────────────────────────

  /// قراءة lastPullTs من جدول sync_state
  Future<int> _getLastPullTs() async {
    try {
      final state = await db.select(db.syncState).getSingleOrNull();
      return state?.lastPullTs ?? 0;
    } catch (e) {
      _log('⚠️ فشل قراءة lastPullTs: $e');
      return 0;
    }
  }

  /// البحث عن سجل محلي بواسطة اسم الجدول والـ localUuid
  ///
  /// يستخدم استعلام مخصص لأن الجداول المختلفة لها حقول مختلفة
  /// ✅ إصلاح: استخدام قائمة بيضاء للجداول بدلاً من تنظيف بسيط لمنع حقن SQL
  static const _allowedTables = {
    'rooms', 'bookings', 'booking_notes', 'shift_notes', 'employees',
    'expenses', 'cash_transactions', 'payments', 'debts', 'booking_nights',
    'hotel_day_ledger', 'booking_price_adjustments', 'salary_withdrawals',
    'salary_cycles', 'salary_payments', 'guest_infos', 'payment_voids',
  };

  Future<Map<String, dynamic>?> _findLocalRow(
    String table,
    String localUuid,
  ) async {
    // التحقق من أن اسم الجدول في القائمة البيضاء لمنع حقن SQL
    if (!_allowedTables.contains(table)) {
      _log('⚠️ اسم جدول غير مسموح: $table');
      return null;
    }

    try {
      final result = await db
          .customSelect(
            'SELECT * FROM "$table" WHERE local_uuid = ? LIMIT 1',
            variables: [Variable<String>(localUuid)],
          )
          .getSingleOrNull();

      return result?.data;
    } catch (e) {
      _log('⚠️ فشل البحث عن سجل محلي في $table/$localUuid: $e');
      return null;
    }
  }

  /// استخراج حقل رقمي من صف ناتج عن customSelect
  int? _extractIntField(Map<String, dynamic> row, String field) {
    final value = row[field];
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  /// استخراج حقل نصي من صف ناتج عن customSelect
  String? _extractStringField(Map<String, dynamic> row, String field) {
    final value = row[field];
    if (value is String) {
      return value;
    }
    return value?.toString();
  }

  /// تحويل صف ناتج عن customSelect إلى Map<String, dynamic>
  Map<String, dynamic> _rowToMap(Map<String, dynamic> row) {
    return Map<String, dynamic>.from(row);
  }

  void _log(String message) {
    DebugLogs.add('SyncConflictResolver', message);
    debugPrint('[SyncConflictResolver] $message');
  }
}
