import 'dart:async';
import 'dart:convert';
import 'package:appwrite/appwrite.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'appwrite_config.dart';
import 'daos/outbox_dao.dart';
import 'local_db.dart';
import 'secondary_appwrite_config.dart';
import 'secondary_appwrite_service.dart';

/// Secondary Sync Manager — مزامنة الوجهة الثانوية بنفس outbox الرئيسي.
///
/// ## الفلسفة التصميمية
///
/// الـ outbox المحلي هو **مصدر واحد للحقائق** لجميع التغييرات المحلية.
/// عندما يحدث تغيير محلي (إنشاء/تعديل/حذف)، يُضاف إلى outbox مرة واحدة.
/// ثم يعمل **مزامنان متوازيان** على نفس الـ outbox:
///
///   1. AppwriteSyncManager (Primary) — يرفع للوجهة الرئيسية
///   2. SecondarySyncManager (Secondary) — يرفع للوجهة الثانوية
///
/// لمنع سباق البيانات (race condition) بين المزامنتين، نستخدم:
///
///   - `delivered_to_primary` (bool): هل تم تسليم السجل للرئيسي؟
///   - `delivered_to_secondary` (bool): هل تم تسليم السجل للثانوي؟
///
/// **السجل يُحذف فقط بعد نجاح كلا الوجهتين** (أو تعطيل Secondary).
///
/// ## الفائدة
///
/// - لا فقدان بيانات: لو فشل Secondary، يبقى السجل حتى تنجح المحاولة التالية
/// - لا تكرار: كل وجهة ترى نفس الـ localUuid، فلا تُنشئ مستندات مكررة
/// - استقلالية: Secondary يمكن تعطيله/تفعيله في أي وقت دون التأثير على Primary
/// - شفافية: dashboard_sync_button يُظهر حالة كل وجهة بشكل مستقل
class SecondarySyncManager {
  factory SecondarySyncManager() =>
      _instance ??= SecondarySyncManager._();

  SecondarySyncManager._();
  static SecondarySyncManager? _instance;

  // ignore: prefer_constructors_over_static_methods
  static SecondarySyncManager get instance => SecondarySyncManager();

  Timer? _syncTimer;
  bool _isSyncing = false;
  DateTime? _lastSync;

  DateTime? get lastSync => _lastSync;
  bool get isSyncing => _isSyncing;
  bool get isAutoSyncEnabled => _syncTimer != null;

  /// بدء المزامنة التلقائية
  void startAutoSync({Duration interval = const Duration(minutes: 15)}) {
    if (!SecondaryAppwriteConfig.isEnabled) {
      debugPrint('🔵 [SecondarySync] Disabled - enable first');
      return;
    }

    stopAutoSync();
    _syncTimer = Timer.periodic(interval, (_) => sync());
    debugPrint(
        '🔵 [SecondarySync] Auto-sync started (every ${interval.inMinutes} min)');
  }

  /// إيقاف المزامنة التلقائية
  void stopAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    debugPrint('🔵 [SecondarySync] Auto-sync stopped');
  }

  /// مزامنة كاملة (Push only)
  ///
  /// يأخذ batch من سجلات outbox التي لم تُسلّم للثانوي بعد، يرفعها،
  /// ثم يضع علامة `delivered_to_secondary = true`. حذف السجل يحدث فقط
  /// إذا كانت `delivered_to_primary = true` أيضاً.
  Future<SecondarySyncResult> sync() async {
    if (_isSyncing) {
      return SecondarySyncResult(
        success: false,
        message: 'مزامنة ثانوية جارية',
      );
    }

    if (!SecondaryAppwriteConfig.isEnabled) {
      return SecondarySyncResult(
        success: false,
        message: 'المزامنة الثانوية معطّلة',
      );
    }

    if (!SecondaryAppwriteConfig.isPushEnabled) {
      return SecondarySyncResult(
        success: false,
        message: 'الرفع للثانوي معطّل',
      );
    }

    _isSyncing = true;

    try {
      final db = AppDatabase();
      final outboxDao = OutboxDao(db);
      final service = SecondaryAppwriteService.instance;

      int pushed = 0;
      int failed = 0;

      // نأخذ batch من السجلات غير المُسلّمة للثانوي
      while (true) {
        final entries = await _takeUndeliveredBatch(db, batchSize: 50);
        if (entries.isEmpty) break;

        for (final entry in entries) {
          try {
            final success = await _processEntry(service, entry);
            if (success) {
              // ✅ ضع علامة "مُسلّم للثانوي" — لا نحذف!
              await outboxDao.markDeliveredToSecondary(entry.id);
              pushed++;
            } else {
              failed++;
            }
          } catch (e) {
            debugPrint('❌ [SecondarySync] Failed entry ${entry.id}: $e');
            await outboxDao.setError(entry.id, e.toString(), entry.attempts + 1);
            failed++;
          }
        }
      }

      _lastSync = DateTime.now();
      await SecondaryAppwriteConfig.updateLastSync();
      await SecondaryAppwriteConfig.updateSyncStatus(
        failed == 0 ? 'success' : 'partial',
      );

      return SecondarySyncResult(
        success: failed == 0,
        message: 'رفع للثانوي: $pushed، فشل: $failed',
        pushed: pushed,
        failed: failed,
      );
    } catch (e) {
      debugPrint('❌ [SecondarySync] sync() error: $e');
      await SecondaryAppwriteConfig.updateSyncStatus('error');
      return SecondarySyncResult(
        success: false,
        message: 'خطأ: $e',
      );
    } finally {
      _isSyncing = false;
    }
  }

  /// رفع التغييرات المحلية فقط (مثل sync لكن مع returns bool)
  Future<bool> pushLocalChanges() async {
    final result = await sync();
    return result.pushed > 0;
  }

  /// سحب التغييرات من الثانوي — غير مُدعوم في هذه النسخة
  ///
  /// السحب من Secondary يحتاج منطقاً معقداً للتعارض مع Primary (أيهما أحدث؟).
  /// يُنصح باستخدام Secondary للقراءة فقط عند فشل Primary (Failover).
  Future<bool> pullRemoteChanges() async {
    if (!SecondaryAppwriteConfig.isPullEnabled) {
      debugPrint('🔵 [SecondarySync] Pull disabled');
      return false;
    }
    debugPrint('🔵 [SecondarySync] Pull not implemented in this version');
    return false;
  }

  /// يأخذ batch من سجلات outbox التي لم تُسلّم للثانوي بعد.
  ///
  /// نستخدم atomic UPDATE...RETURNING لمنع سباق البيانات. السجلات تُؤخذ
  /// بشكل مستقل عن Primary (الذي يأخذ سجلاته الخاصة بناءً على
  /// delivered_to_primary).
  Future<List<OutboxData>> _takeUndeliveredBatch(
    AppDatabase db, {
    required int batchSize,
  }) async {
    final worker = DateTime.now().millisecondsSinceEpoch.toString();
    final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // بناء شرط source: نأخذ فقط سجلات 'local' (تغييرات المستخدم)
    // ولا نأخذ 'restore' (استعادة من نسخة احتياطية لا تحتاج secondary)
    const sourceCondition = " AND source = 'local'";

    // ✅ Atomic claim: ضع علامة processing على السجلات غير المُسلّمة للثانوي
    final claimed = await db.customSelect(
      'UPDATE outbox SET processing_status = ?, processing_started_at = ?, processing_worker = ? '
      'WHERE id IN ('
      '  SELECT id FROM outbox WHERE delivered_to_secondary = 0 AND processing_status = ?$sourceCondition '
      '  ORDER BY client_ts ASC LIMIT ? '
      ') RETURNING *',
      variables: [
        const drift.Variable<String>('processing'),
        drift.Variable<int>(nowEpoch),
        drift.Variable<String>('secondary_$worker'),
        const drift.Variable<String>('pending'),
        drift.Variable<int>(batchSize),
      ],
      readsFrom: {db.outbox},
    ).map((row) => OutboxData(
          id: row.read<int>('id'),
          entity: row.read<String>('entity'),
          op: row.read<String>('op'),
          localUuid: row.read<String>('local_uuid'),
          serverId: row.read<int?>('server_id'),
          payload: row.read<String>('payload'),
          clientTs: row.read<int>('client_ts'),
          processingStatus: row.read<String>('processing_status'),
          processingStartedAt: row.read<int?>('processing_started_at'),
          processingWorker: row.read<String?>('processing_worker'),
          lastError: row.read<String?>('last_error'),
          attempts: row.read<int>('attempts'),
          idempotencyKey: row.read<String?>('idempotency_key'),
          source: row.read<String>('source'),
          deliveredToPrimary: row.read<bool>('delivered_to_primary'),
          deliveredToSecondary: row.read<bool>('delivered_to_secondary'),
        )).get();

    return claimed;
  }

  /// معالجة سجل واحد من outbox وإرساله للثانوي
  Future<bool> _processEntry(
    SecondaryAppwriteService service,
    OutboxData entry,
  ) async {
    final collectionId = AppwriteConfig.collectionIdFor(entry.entity);
    if (collectionId == null) {
      debugPrint('⚠️ [SecondarySync] Unknown entity: ${entry.entity}');
      return false;
    }

    final payload = _parsePayload(entry.payload);
    payload['localUuid'] = entry.localUuid;

    // إضافة idempotencyKey إذا كان موجوداً
    if (entry.idempotencyKey != null && entry.idempotencyKey!.isNotEmpty) {
      payload['idempotencyKey'] = entry.idempotencyKey;
    }

    try {
      if (entry.op == 'delete') {
        await service.deleteDocument(
          collectionId: collectionId,
          documentId: entry.localUuid,
        );
        return true;
      }

      // create أو update — نستخدم upsert (نفس منطق Primary)
      await service.upsertDocument(
        collectionId: collectionId,
        documentId: entry.localUuid,
        data: payload,
      );
      return true;
    } on AppwriteException catch (e) {
      // أخطاء غير قابلة لإعادة المحاولة — نسجلها ولا نعيد المحاولة
      if (e.code == 400 || e.code == 401 || e.code == 403) {
        debugPrint(
            '❌ [SecondarySync] Permanent error for ${entry.entity}/${entry.localUuid}: ${e.code} ${e.message}');
        // نضع علامة "مُسلّم" لتجنب إعادة المحاولة لأبد — السجل معطوب
        // لكن نحتفظ به للتحقيق
        return false;
      }
      rethrow;
    }
  }

  /// تحويل payload من JSON string إلى Map
  Map<String, dynamic> _parsePayload(String payload) {
    try {
      if (payload.isEmpty || payload == '{}') return {};
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        return Map<String, dynamic>.from(decoded);
      }
      return {};
    } catch (e) {
      debugPrint('⚠️ [SecondarySync] Failed to parse payload: $e');
      return {};
    }
  }
}

/// نتيجة المزامنة الثانوية
class SecondarySyncResult {
  SecondarySyncResult({
    required this.success,
    required this.message,
    this.pushed = 0,
    this.failed = 0,
  });

  final bool success;
  final String message;
  final int pushed;
  final int failed;
}
