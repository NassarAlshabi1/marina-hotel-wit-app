// ignore_for_file: comment_references
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

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
  /// تحليل Vector Clock من JSON string
  /// مثال: '{"device1":3,"device2":5}' → {'device1': 3, 'device2': 5}
  Map<String, int> _parseVectorClock(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (k, v) => MapEntry(k.toString(), (v as num).toInt()),
        );
      }
    } catch (_) {}
    return {};
  }

  /// مقارنة Vector Clocks — ترجع 'remote' إذا البعيد أحدث، 'local' إذا المحلي أحدث، null إذا متعارض
  String? _compareVectorClocks(
    Map<String, int> local,
    Map<String, int> remote,
  ) {
    bool remoteNewer = false;
    bool localNewer = false;

    final allDevices = <String>{...local.keys, ...remote.keys};
    for (final device in allDevices) {
      final lv = local[device] ?? 0;
      final rv = remote[device] ?? 0;
      if (rv > lv) remoteNewer = true;
      if (lv > rv) localNewer = true;
    }

    if (remoteNewer && !localNewer) return 'remote';
    if (localNewer && !remoteNewer) return 'local';
    return null; // متعارض
  }

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
      final localLastModified =
          _extractIntField(localRow, 'lastModified') ??
          _extractIntField(localRow, 'last_modified') ??
          0;
      final localVersion = _extractIntField(localRow, 'version') ?? 1;
      final localOrigin = _extractStringField(localRow, 'origin') ?? 'local';
      final remoteLastModified =
          (remoteData['lastModified'] as int?) ??
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

      // ✅ التحقق من الاستراتيجية أولاً — قبل Vector Clock
      if (strategy == ConflictStrategy.serverWins) {
        _log('🔧 حل تعارض $table/$localUuid: serverWins ← البعيد');
        return const ConflictCheckResult(
          isConflict: true,
          resolved: true,
          usedRemote: true,
          reason: 'serverWins: تطبيق البيانات البعيدة',
        );
      }
      if (strategy == ConflictStrategy.localWins) {
        _log('🔧 حل تعارض $table/$localUuid: localWins ← المحلي');
        return const ConflictCheckResult(
          isConflict: true,
          resolved: true,
          usedLocal: true,
          reason: 'localWins: الاحتفاظ بالبيانات المحلية',
        );
      }
      if (strategy == ConflictStrategy.manualReview) {
        _log('🔧 حل تعارض $table/$localUuid: manualReview ← تسجيل للمراجعة');
        await logConflict(
          table: table,
          localUuid: localUuid,
          localData: Map<String, dynamic>.from(localRow),
          remoteData: remoteData,
        );
        return const ConflictCheckResult(
          isConflict: true,
          usedLocal: true,
          reason:
              'manualReview: تم تسجيل التعارض للمراجعة اليدوية — الاحتفاظ بالمحلي مؤقتاً',
        );
      }

      // ✅ Vector Clock: فحص التعديلات المنطقية
      final localVectorClockStr =
          _extractStringField(localRow, 'vectorClock') ??
          _extractStringField(localRow, 'vector_clock') ??
          '';
      final remoteVectorClockStr =
          (remoteData['vectorClock'] as String?) ??
          (remoteData['vector_clock'] as String?) ??
          '';

      if (localVectorClockStr.isNotEmpty && remoteVectorClockStr.isNotEmpty) {
        final localVC = _parseVectorClock(localVectorClockStr);
        final remoteVC = _parseVectorClock(remoteVectorClockStr);
        final vcResult = _compareVectorClocks(localVC, remoteVC);

        if (vcResult == 'remote') {
          _log('🔧 حل تعارض $table/$localUuid: Vector Clock ← البعيد أحدث');
          return const ConflictCheckResult(
            isConflict: true,
            resolved: true,
            usedRemote: true,
            reason: 'Vector Clock: البعيد أحدث في كل الأجهزة',
          );
        }
        if (vcResult == 'local') {
          _log('🔧 حل تعارض $table/$localUuid: Vector Clock ← المحلي أحدث');
          return const ConflictCheckResult(
            isConflict: true,
            resolved: true,
            usedLocal: true,
            reason: 'Vector Clock: المحلي أحدث في كل الأجهزة',
          );
        }
        // متعارض → استمرار لمقارنة lastModified
        _log(
          '⚠️ Vector Clock متعارض لـ $table/$localUuid — التحول إلى lastModified',
        );
      }

      // حل تلقائي بالكامل: مقارنة lastModified
      if (remoteLastModified > localLastModified) {
        _log('🔧 حل تعارض $table/$localUuid: البعيد أحدث ← remote wins');
        return const ConflictCheckResult(
          isConflict: true,
          resolved: true,
          usedRemote: true,
          reason: 'تعارض - البعيد أحدث (lastModified)',
        );
      } else {
        _log(
          '🔧 حل تعارض $table/$localUuid: المحلي أحدث أو مساوٍ ← local wins',
        );
        return const ConflictCheckResult(
          isConflict: true,
          resolved: true,
          usedLocal: true,
          reason: 'تعارض - المحلي أحدث أو مساوٍ (lastModified)',
        );
      }
    } catch (e, st) {
      _log('❌ خطأ في كشف التعارض $table/$localUuid: $e');
      dlog(() => 'SyncConflictResolver.detectAndResolve stackTrace: $st');
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
        // ✅ P1-7 fix: توحيد مؤشر "غير محلول" — '' بدل 'pending'
        // conflict_manager.dart يعتبر resolution == null أو '' كغير محلول
        resolution: '',
        localPayload: jsonEncode(localData),
        remotePayload: jsonEncode(remoteData),
        createdAt: now,
      );

      final id = await db.into(db.syncConflicts).insert(companion);
      _log('📝 تم تسجيل تعارض #$id في $table/$localUuid للمراجعة اليدوية');
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
      final localUuid =
          (remoteData['local_uuid'] ?? remoteData['localUuid']) as String?;
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
    return (db.select(
      db.syncConflicts,
    )..where((t) => t.resolution.equals(''))).get();
  }

  /// جلب التعارضات حسب الجدول
  Future<List<SyncConflictRow>> getConflictsByTable(String table) async {
    return (db.select(
      db.syncConflicts,
    )..where((t) => t.targetTable.equals(table))).get();
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
    final note = resolutionNote.isNotEmpty
        ? resolutionNote
        : (useRemote
              ? 'تم اختيار البيانات البعيدة يدوياً'
              : 'تم الاحتفاظ بالبيانات المحلية يدوياً');

    await (db.update(
      db.syncConflicts,
    )..where((t) => t.id.equals(conflictId))).write(
      SyncConflictsCompanion(resolution: Value(resolution)),
    );

    _log('✅ تم حل التعارض #$conflictId يدوياً: $note');
  }

  /// حذف التعارضات القديمة (أقدم من [maxAgeDays] يوماً)
  Future<int> cleanupOldConflicts({int maxAgeDays = 30}) async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: maxAgeDays))
        .toUtc()
        .toIso8601String();

    // استخدام استعلام مخصص لحذف التعارضات القديمة لتجنب تعقيد أنواع Drift
    final deleteResult = await db
        .customSelect(
          'DELETE FROM sync_conflicts WHERE resolution != ? AND created_at < ?',
          variables: [const Variable<String>(''), Variable<String>(cutoff)],
        )
        .get();

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
          variables: [const Variable<String>('')],
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
    'rooms',
    'bookings',
    'booking_notes',
    'shift_notes',
    'employees',
    'expenses',
    'cash_transactions',
    'payments',
    'debts',
    'booking_nights',
    'hotel_day_ledger',
    'booking_price_adjustments',
    'salary_withdrawals',
    'salary_cycles',
    'salary_payments',
    'guest_infos',
    'payment_voids',
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
  // ignore: unused_element
  Map<String, dynamic> _rowToMap(Map<String, dynamic> row) {
    return Map<String, dynamic>.from(row);
  }

  void _log(String message) {
    DebugLogs.add('SyncConflictResolver', message);
    dlog(() => '[SyncConflictResolver] $message');
  }
}
