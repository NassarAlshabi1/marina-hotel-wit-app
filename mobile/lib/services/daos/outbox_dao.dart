import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../adapters/adapter_registry.dart';
import '../appwrite_logger.dart';
import '../appwrite_sync_manager.dart';
import '../crashlytics_service.dart';
import '../local_db.dart';
import '../secondary_appwrite_config.dart';
import '../vector_clock_service.dart';

part 'outbox_dao.g.dart';

const _uuid = Uuid();

@DriftAccessor(tables: [Outbox])
class OutboxDao extends DatabaseAccessor<AppDatabase> with _$OutboxDaoMixin {
  OutboxDao(super.db, this.adapters);

  final AdapterRegistry adapters;

  /// مشاهدة عدد عناصر outbox المعلقة/الفاشلة
  /// [sources] — إذا حُدد، يقتصر العد على هذه المصادر فقط
  Stream<int> watchCount({List<String>? sources}) {
    final countExp = outbox.id.count();
    final query = selectOnly(outbox)
      ..addColumns([countExp])
      ..where(outbox.processingStatus.isIn(['pending', 'failed']));
    if (sources != null && sources.isNotEmpty) {
      query.where(outbox.source.isIn(sources));
    }
    return query.map((row) => row.read(countExp) ?? 0).watchSingle();
  }

  /// عدد عناصر outbox المعلقة/الفاشلة
  /// [sources] — إذا حُدد، يقتصر العد على هذه المصادر فقط
  Future<int> count({List<String>? sources}) async {
    final countExp = outbox.id.count();
    final query = selectOnly(outbox)
      ..addColumns([countExp])
      ..where(outbox.processingStatus.isIn(['pending', 'failed']));
    if (sources != null && sources.isNotEmpty) {
      query.where(outbox.source.isIn(sources));
    }
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  /// ✅ P2-5 fix: عدد السجلات التي سيأخذها الرفع فعلياً (يطابق نطاق takeBatch).
  ///
  /// يطابق تماماً فلتر `takeBatch()` المستخدم في `pushLocalChanges()`:
  ///   - `processing_status = 'pending'` (فقط، لا يشمل 'failed' أو 'processing')
  ///   - `delivered_to_primary = 0` (لم تُسلَّم للرئيسي بعد)
  ///   - `source IN (sources)` عند تمريرها
  ///
  /// الفرق عن `count()`:
  ///   - `count()` يحسب `pending + failed` بغض النظر عن `delivered_to_primary`
  ///   - هذا يسبّب مبالغة في العدد المعروض لل مستخدم
  ///
  /// الاستخدام: شارة "تغييرات معلّقة" على زر الرفع في Dashboard.
  Future<int> countPendingPushable({List<String>? sources}) async {
    final countExp = outbox.id.count();
    final query = selectOnly(outbox)
      ..addColumns([countExp])
      ..where(outbox.processingStatus.equals('pending'))
      ..where(outbox.deliveredToPrimary.equals(false));
    if (sources != null && sources.isNotEmpty) {
      query.where(outbox.source.isIn(sources));
    }
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  /// ✅ عدد السجلات المحلية غير المُسلّمة للرئيسي بغضّ النظر عن حالتها الحالية
  /// (`pending` أو `processing` عالقة أو `failed`).
  ///
  /// الفرق الحرج عن `countPendingPushable`:
  ///   - `countPendingPushable` يحسب فقط `processing_status = 'pending'`.
  ///   - لكن عند الضغط على "رفع التغييرات" يحجز `takeBatch` السجلات فيحوّلها
  ///     إلى `processing`. إذا انقطع الرفع (إنترنت بطيء / إغلاق التطبيق قبل
  ///     الانتهاء) تبقى السجلات عالقة في `processing` → تختفي من عدّاد
  ///     `countPendingPushable` → يظهر 0 → يظنّ المستخدم أن الرفع نجح بينما
  ///     البيانات لم تصل الخادم فعلياً.
  ///
  /// هذا العدّاد يشمل كل ما لم يُسلَّم للرئيسي (`delivered_to_primary = 0`)
  /// وليس في حالة نهائية (`completed`/`dead`)، فتبقى التغييرات العالقة مرئية
  /// للمستخدم ويبقى زر الرفع مُفعّلاً لإعادة المحاولة.
  Future<int> countUndeliveredToPrimary({List<String>? sources}) async {
    final countExp = outbox.id.count();
    final query = selectOnly(outbox)
      ..addColumns([countExp])
      ..where(outbox.processingStatus.isIn(['pending', 'processing', 'failed']))
      ..where(outbox.deliveredToPrimary.equals(false));
    if (sources != null && sources.isNotEmpty) {
      query.where(outbox.source.isIn(sources));
    }
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  /// ✅ يُعيد السجلات العالقة في `processing` و/أو الفاشلة `failed` إلى
  /// `pending` قبل بدء رفع يدوي، بحيث تُلتقط بواسطة `takeBatch()` في الدورة
  /// التالية.
  ///
  /// يستدعي من `merge()` عند source='local' لضمان كشف كل التعديلات المتزامنة.
  Future<void> resetStuckProcessing({List<String>? sources}) async {
    final query = update(outbox)
      ..where(outbox.processingStatus.isIn(['processing', 'failed']));
    if (sources != null && sources.isNotEmpty) {
      query.where(outbox.source.isIn(sources));
    }
    await query.write(
      OutboxCompanion(
        processingStatus: const Value('pending'),
        processingStartedAt: const Value.absent(),
        processingWorker: const Value.absent(),
      ),
    );
  }

  /// إضافة عملية إلى outbox
  /// `entity` — اسم الكيان (جدول DB)
  /// `op` — العملية: create, update, delete
  /// `localUuid` — UUID محلي للسجل
  /// `serverId` — ID على السيرفر (اختياري)
  /// `payload` — بيانات العملية كـ JSON
  /// `clientTs` — timestamp العميل (epoch ms)
  /// `source` — مصدر العملية (local, appwrite, drive)
  /// `deliveredToSecondary` — هل سُلّمت للثانوي
  Future<int> merge({
    required String entity,
    required String op,
    required String localUuid,
    int? serverId,
    required Map<String, dynamic> payload,
    required int clientTs,
    String source = 'local',
    bool deliveredToSecondary = false,
  }) async {
    // ✅ فحص التكرار عبر idempotencyKey
    final idempKey = _generateIdempotencyKey(entity, op, localUuid, clientTs);
    final existing = await (select(outbox)
          ..where((t) => t.idempotencyKey.equals(idempKey))
          ..limit(1))
        .getSingleOrNull();

    if (existing != null) {
      // تحديث السجل الموجود إذا كان في حالة failed أو processing
      if (existing.processingStatus == 'failed' || existing.processingStatus == 'processing') {
        await (update(outbox)..where((t) => t.id.equals(existing.id))).write(
          OutboxCompanion(
            payload: Value(jsonEncode(payload)),
            clientTs: Value(clientTs),
            idempotencyKey: Value(idempKey),
            source: Value(source),
            deliveredToSecondary: Value(deliveredToSecondary),
            processingStatus: const Value('pending'),
            processingStartedAt: const Value(null),
            processingWorker: const Value(null),
          ),
        );
        return existing.id;
      }
      return existing.id;
    }

    return into(outbox).insert(
      OutboxCompanion.insert(
        entity: entity,
        op: op,
        localUuid: localUuid,
        serverId: Value(serverId),
        payload: jsonEncode(payload),
        clientTs: clientTs,
        idempotencyKey: Value(idempKey),
        source: Value(source),
        deliveredToSecondary: Value(deliveredToSecondary),
      ),
    );
  }

  /// يُستدعى من merge() عند source='local' لضمان كشف كل التعديلات المتزامنة.
  ///
  /// ✅ تحسين: استبدال silent catch بـ proper logging + Crashlytics reporting.
  /// سابقاً كان أي خطأ (SQL فشل، JSON تالف، etc.) يُتجاهل بصمت، مما يجعل
  /// debugging مستحيلاً ويُخفي مشاكل الـ vector clock في الإنتاج.
  /// الآن نُسجّل الخطأ محلياً + نُرسله إلى Crashlytics (low severity لأن
  /// الـ VC bump ليس حرجاً لدرجة تعطيل الكتابة، لكنه مهم لكشف التعارضات).
  Future<void> _bumpVectorClockForLocalWrite(String entity, String localUuid) async {
    final tableName = _entityTableMap[entity];
    if (tableName == null) return;

    final deviceId = AppwriteSyncManager.currentDeviceIdStatic;
    if (deviceId == null || deviceId.isEmpty) return;

    try {
      final rows = await attachedDatabase
          .customSelect(
            'SELECT vector_clock AS vc FROM $tableName WHERE local_uuid = ? LIMIT 1',
            variables: [Variable<String>(localUuid)],
          )
          .get();

      if (rows.isEmpty) return;

      final currentVcStr = (rows.first.data['vc'] as String?) ?? '{}';
      final vc = VectorClock.fromString(currentVcStr);

      // ✅ مراقبة: تسجيل السجلات ذات الـ VC الفارغ لإحصائيات الصحة
      if (vc.isEmpty) {
        developer.log(
          'VC bump: initializing empty vector clock for $entity/$localUuid '
          '(first local edit on device $deviceId)',
          name: 'VectorClock',
        );
      }

      vc.increment(deviceId);

      await attachedDatabase.customStatement('UPDATE $tableName SET vector_clock = ? WHERE local_uuid = ?', [
        vc.toString(),
        localUuid,
      ]);
    } catch (e, st) {
      // ✅ تحسين: تسجيل الخطأ بدلاً من التجاهل الصامت
      // الـ VC bump ليس حرجاً لدرجة تعطيل الكتابة، لكنه مهم لكشف التعارضات
      // نسجّل محلياً + نُرسل إلى Crashlytics بـ low severity
      developer.log('⚠️ VC bump failed for $entity/$localUuid: $e', name: 'VectorClock', error: e, stackTrace: st);
      debugPrint('⚠️ Vector clock bump failed for $entity (uuid=$localUuid): $e');

      // إرسال إلى Crashlytics بدون انتظار (fire-and-forget)
      unawaited(
        CrashlyticsService.instance.recordSyncError(
          operation: 'vc_bump_failed',
          error: e.toString(),
          stackTrace: st,
          severity: CrashlyticsSeverity.warning,
          context: {'entity': entity, 'local_uuid': localUuid, 'device_id': deviceId},
        ),
      );
    }
  }
}

/// سجل يمثل تعارض في البيانات
class ConflictRecord {
  ConflictRecord({
    required this.id,
    required this.uuid,
    required this.targetTable,
    required this.localPayload,
    required this.remotePayload,
    required this.lastError,
    required this.timestamp,
  });
  final int id;
  final String uuid;
  final String targetTable;
  final Map<String, dynamic> localPayload;
  final Map<String, dynamic> remotePayload;
  final String lastError;
  final DateTime timestamp;
}

/// ✅ خريطة أسماء الكيانات إلى أسماء الجداول
const _entityTableMap = <String, String>{
  'rooms': 'rooms',
  'bookings': 'bookings',
  'payments': 'payments',
  'expenses': 'expenses',
  'debts': 'debts',
  'employees': 'employees',
  'booking_notes': 'booking_notes',
  'booking_nights': 'booking_nights',
  'cash_transactions': 'cash_transactions',
  'shift_notes': 'shift_notes',
  'salary_cycles': 'salary_cycles',
  'salary_payments': 'salary_payments',
  'salary_withdrawals': 'salary_withdrawals',
  'guest_infos': 'guest_infos',
  'blacklist': 'blacklist',
  'booking_price_adjustments': 'booking_price_adjustments',
  'price_adjustments': 'price_adjustments',
  'payment_voids': 'payment_voids',
  'salary_carry_over_logs': 'salary_carry_over_logs',
  // ✅ app_users — للمزامنة وحل التعارضات عبر vector clock
  'app_users': 'app_users',
};

String _generateIdempotencyKey(String entity, String op, String localUuid, int clientTs) {
  return '${entity}:${op}:${localUuid}:${clientTs}';
}
