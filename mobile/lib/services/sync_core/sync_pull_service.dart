// ignore_for_file: unused_element, deprecated_member_use
import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:collection/collection.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../appwrite_config.dart';
import '../appwrite_logger.dart';
import '../appwrite_service.dart';
import '../daos/ancestor_cache_dao.dart';
import '../daos/outbox_dao.dart';
import '../local_db.dart';
import '../vector_clock_service.dart';
import 'smart_conflict_resolver.dart';

/// خدمة سحب التغييرات من Appwrite Cloud إلى القاعدة المحلية
///
/// ✅ Audit Fix (2026-08-06): تمت إضافة `checkAndResolveConflict` — منطق
/// كشف وحل التعارضات الذي كان مُلصقاً في 17 موقعاً في AppwriteSyncManager.
/// الآن SyncPullService هو المسؤول الوحيد عن:
///   - بناء delta queries
///   - إدارة pull timestamps
///   - **كشف وحل التعارضات** (جديد)
///
/// AppwriteSyncManager._isRemoteDataNewer يُفوّض الآن إلى
/// `_pullService.checkAndResolveConflict(...)`.
class SyncPullService {
  SyncPullService({
    required this.appwriteService,
    required this.database,
    required this.outboxDao,
    AppwriteLogger? logger,
  }) : _logger = logger ?? AppwriteLogger(),
       _ancestorCacheDao = null;

  final AppwriteService appwriteService;
  final AppDatabase database;
  final OutboxDao outboxDao;
  final AppwriteLogger _logger;

  /// ✅ Audit Fix: AncestorCacheDao للوصول إلى الـ ancestor cache.
  /// يُحقنlazy من AppwriteSyncManager عبر [setAncestorCacheDao].
  AncestorCacheDao? _ancestorCacheDao;

  /// ✅ Audit Fix: deviceId الحالي (لـ LWW tie-break).
  String? _currentDeviceId;

  /// ✅ Audit Fix: حقن AncestorCacheDao من AppwriteSyncManager.
  /// هذا يسمح لـ SyncPullService بالوصول إلى الـ ancestor cache
  /// بدون إنشاء instance منفصل (يضمن استخدام نفس الـ DAO).
  void setAncestorCacheDao(AncestorCacheDao dao, {String? deviceId}) {
    _ancestorCacheDao = dao;
    _currentDeviceId = deviceId;
  }

  // ── Conflict Detection & Resolution ──────────────────────────────────

  /// ✅ Audit Fix (2026-08-06): كشف وحل التعارضات.
  ///
  /// هذه الدالة هي القلب المنطقي للمزامنة — تحدد ما إذا كان يجب تطبيق
  /// البيانات البعيدة، وتحل التعارضات المتزامنة عبر 3-way merge.
  ///
  /// المعاملات:
  /// - [remoteData] — بيانات المستند البعيد (من Appwrite). **يُعدَّل in-place**
  ///   عند الدمج (يُستبدل بالبيانات المدموجة).
  /// - [localLastModified] — timestamp آخر تعديل محلي (epoch seconds).
  /// - [localDeletedAt] — timestamp الحذف المحلي (null إذا غير محذوف).
  /// - [remoteUpdatedAtSec] — `$updatedAt` من Appwrite (seconds).
  /// - [localVectorClock] — VC المحلي (JSON string).
  /// - [entityName] — اسم الكيان (لـ SmartConflictResolver policies).
  /// - [localUuid] — UUID المحلي للسجل.
  /// - [localData] — البيانات المحلية الكاملة (لـ 3-way merge).
  ///
  /// Returns: [RemoteCheckResult] مع `shouldApplyRemote` وبيانات الدمج.
  Future<RemoteCheckResult> checkAndResolveConflict(
    Map<String, dynamic> remoteData,
    int? localLastModified, {
    int? localDeletedAt,
    int? remoteUpdatedAtSec,
    String? localVectorClock,
    String? entityName,
    String? localUuid,
    Map<String, dynamic>? localData,
  }) async {
    // 1) حماية الحذف المحلي (soft delete) — له أولوية أعلى
    if (localDeletedAt != null) {
      final remoteDeletedAt =
          _asIntNullable(remoteData['deletedAt']) ??
          _asIntNullable(remoteData['deleted_at']);
      if (remoteDeletedAt != null) {
        return const RemoteCheckResult(shouldApplyRemote: true);
      }
      return const RemoteCheckResult(shouldApplyRemote: false);
    }

    // 2) السجل غير موجود محلياً → يجب إضافته
    if (localLastModified == null) {
      return const RemoteCheckResult(shouldApplyRemote: true);
    }

    // 3) استخراج timestamp البعيد
    final remoteLastModified =
        _asIntNullable(remoteData['lastModified']) ??
        _asIntNullable(remoteData['last_modified']) ??
        _asIntNullable(remoteData['lastModifiedEpoch']);
    final effectiveRemoteTs = remoteLastModified ?? remoteUpdatedAtSec;

    if (effectiveRemoteTs == null) {
      // لا timestamp متاح → تطبيق البعيد كحل آمن
      _logger.debug(
        'checkAndResolveConflict: no remote timestamp — applying remote. '
        'uuid=$localUuid',
        tag: 'SYNC',
      );
      return const RemoteCheckResult(shouldApplyRemote: true);
    }

    // 4) Vector Clock comparison
    final remoteVcStr =
        (remoteData['vectorClock'] as String?) ??
        (remoteData['vector_clock'] as String?) ??
        '{}';

    // إذا كانت كلتا الساعتين فارغتين → LWW
    if ((localVectorClock == null ||
            localVectorClock.isEmpty ||
            localVectorClock == '{}') &&
        (remoteVcStr.isEmpty || remoteVcStr == '{}')) {
      final normalizedRemoteTs = effectiveRemoteTs > 10000000000
          ? effectiveRemoteTs ~/ 1000
          : effectiveRemoteTs;
      final normalizedLocalTs = localLastModified > 10000000000
          ? localLastModified ~/ 1000
          : localLastModified;
      return RemoteCheckResult(
        shouldApplyRemote: normalizedRemoteTs > normalizedLocalTs,
      );
    }

    final localVc = VectorClock.fromString(localVectorClock ?? '{}');
    final remoteVc = VectorClock.fromString(remoteVcStr);

    if (kDebugMode && (localVc.isEmpty || remoteVc.isEmpty)) {
      _logger.info(
        'VC empty: entity=$entityName, uuid=$localUuid, '
        'localVc=${localVc.isEmpty ? "empty" : "non-empty"}, '
        'remoteVc=${remoteVc.isEmpty ? "empty" : "non-empty"}',
        tag: 'VC_HEALTH',
      );
    }

    final comparison = VectorClockComparator.compare(localVc, remoteVc);

    switch (comparison) {
      case VectorClockComparison.equal:
        // ✅ Fix (2026-08-08): لا نرفض السجل صامتاً عند تطابق الـ VC.
        // Appwrite لا يزيد الـ vectorClock تلقائياً عند التخزين، لذا قد يتطابق
        // VC رغم اختلاف البيانات الفعلية (مثل تغيّر status/actualCheckout).
        // نتحقق من المحتوى الفعلي — إن اختلف → البعيد أحدث ويُطبَّق.
        if (localData != null && !_contentEquals(localData, remoteData)) {
          return const RemoteCheckResult(shouldApplyRemote: true);
        }
        return const RemoteCheckResult(shouldApplyRemote: false);

      case VectorClockComparison.remoteNewer:
        return const RemoteCheckResult(shouldApplyRemote: true);

      case VectorClockComparison.localNewer:
        return const RemoteCheckResult(shouldApplyRemote: false);

      case VectorClockComparison.concurrent:
        // ⚠️ تعارض متزامن!
        _logger.warning(
          '⚠️ CONCURRENT CONFLICT: entity=$entityName, uuid=$localUuid, '
          'localVc=$localVectorClock, remoteVc=$remoteVcStr.',
          tag: 'CONFLICT',
        );

        // محاولة الحل الذكي عبر SmartConflictResolver (3-way merge)
        if (entityName != null &&
            localUuid != null &&
            localData != null &&
            _ancestorCacheDao != null) {
          try {
            final ancestor = await _ancestorCacheDao!.getAncestor(
              entityName,
              localUuid,
            );
            final remoteDataOriginal = Map<String, dynamic>.from(remoteData);
            final resolution = SmartConflictResolver.resolve(
              entity: entityName,
              localData: localData,
              remoteData: remoteData,
              commonAncestor: ancestor,
            );

            if (resolution.strategy == ResolutionStrategy.fieldLevelMerge) {
              _logger.info(
                '✅ 3-way merge resolved: entity=$entityName, uuid=$localUuid, '
                'warnings=${resolution.warnings.length}',
                tag: 'CONFLICT',
              );
              // كتابة البيانات المدمجة في remoteData in-place.
              // ✅ Sync Safety Fix (2026-08-10): استخدم iterative put بدل
              // addAll لتفادي type mismatch عند runtime. مشكلة addAll: إذا
              // كان remoteData من literal `{'k': 'v'}` يصبح runtime type
              // هو `_Map<String, Object>`، بينما mergedData قد يكون
              // `Map<String, dynamic>` → addAll يرمي type error ويُحوِّل
              // المسار لـ LWW fallback (فقدان النتيجة المدمجة).
              // الـ iterative put يتجاوز variance rules في Dart.
              remoteData.clear();
              for (final entry in resolution.mergedData.entries) {
                remoteData[entry.key] = entry.value;
              }
              // حفظ البيانات البعيدة الأصلية كـ ancestor
              await _ancestorCacheDao!.saveAncestor(
                entity: entityName,
                localUuid: localUuid,
                data: remoteDataOriginal,
              );
              return RemoteCheckResult(
                shouldApplyRemote: true,
                mergedData: resolution.mergedData,
                pushedToRemote: resolution.pushedToRemote,
              );
            }
          } catch (e) {
            _logger.warning(
              '⚠️ SmartConflictResolver failed, LWW fallback: $e',
              tag: 'CONFLICT',
            );
          }
        }

        // LWW fallback + deviceId tie-break
        final normalizedRemoteTs = effectiveRemoteTs > 10000000000
            ? effectiveRemoteTs ~/ 1000
            : effectiveRemoteTs;
        final remoteDeviceId = (remoteData['deviceId'] as String?) ?? '';
        final localDeviceId = _currentDeviceId ?? '';
        final shouldApply =
            normalizedRemoteTs > localLastModified ||
            (normalizedRemoteTs == localLastModified &&
                remoteDeviceId.compareTo(localDeviceId) < 0);
        return RemoteCheckResult(shouldApplyRemote: shouldApply);
    }
  }

  // ── Helper Methods ─────────────────────────────────────────────────────

  bool? _remoteEpochIsMillis;

  // ── Helper Methods ─────────────────────────────────────────────────────

  int? _asIntNullable(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String && value.isNotEmpty) {
      final parsedInt = int.tryParse(value);
      if (parsedInt != null) return parsedInt;
      final parsedDouble = double.tryParse(value);
      if (parsedDouble != null) return parsedDouble.toInt();
    }
    return null;
  }

  /// ✅ Fix (2026-08-08): يقارن محتوى البيانات الفعلي متجاهلاً الحقول الوصفية
  /// (timestamps/version/vectorClock/ids). يُستخدم لمنع تخطّي سجل تغيّرت
  /// بياناته رغم تطابق vectorClock — الحالة التي تحدث عندما يرفع نفس الجهاز
  /// نفس السجل بقيم مختلفة دون أن يزيد Appwrite الـ VC تلقائياً.
  static bool _contentEquals(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    const skip = {
      'lastModified',
      'updatedAt',
      'version',
      'vectorClock',
      'vector_clock',
      'last_modified',
      'last_modified_epoch',
      'updated_at',
      'createdAt',
      'created_at',
      'deletedAt',
      'deleted_at',
      'syncTimestamp',
      'sync_origin',
      'localUuid',
      'serverId',
      'id',
      'idempotencyKey',
      'lastModifiedEpoch',
      'createdAtEpoch',
      'createdAtIso',
      'updatedAtIso',
      'deletedAtIso',
      '\$id',
      '\$createdAt',
      '\$updatedAt',
      '\$permissions',
    };
    final keys = <String>{...a.keys, ...b.keys}..removeWhere(skip.contains);
    const eq = DeepCollectionEquality();
    for (final k in keys) {
      if (!eq.equals(a[k], b[k])) return false;
    }
    return true;
  }

  /// يحدد ما إذا كان الطابع الزمني البعيد مُعبَّرًا عنه بالميلي ثانية أم بالثواني.
  /// يُستخدم لبناء delta queries بالوحدة الصحيحة.
  Future<bool> isRemoteEpochMillis() async {
    final cached = _remoteEpochIsMillis;
    if (cached != null) {
      return cached;
    }
    try {
      final info = appwriteService.getProjectInfo();
      final dbId = info['databaseId'] ?? AppwriteConfig.databaseId;

      final list = await appwriteService.databases.listDocuments(
        databaseId: dbId,
        collectionId: AppwriteConfig.roomsCollectionId,
        queries: [Query.limit(1)],
      );

      if (list.documents.isEmpty) {
        _remoteEpochIsMillis = false;
        return false;
      }

      final data = list.documents.first.data;
      final raw =
          data['lastModified'] ??
          data['last_modified'] ??
          data['last_modified_epoch'];

      final value = raw is int
          ? raw
          : raw is num
          ? raw.toInt()
          : raw is String
          ? int.tryParse(raw)
          : null;

      final isMillis = value != null && value > 10000000000;
      _remoteEpochIsMillis = isMillis;
      return isMillis;
    } catch (_) {
      _remoteEpochIsMillis = false;
      return false;
    }
  }

  /// ✅ إصلاح جوهري: يبني استعلامات delta للسحب التزايدي بناءً على **زمن الخادم**
  /// (`$updatedAt`) بدل زمن الحدث المحلي (`lastModified`).
  ///
  /// المشكلة القديمة: الفلترة بـ `lastModified` (زمن إنشاء السجل على جهاز المصدر)
  /// كانت تُفوّت السجلات على الأجهزة البطيئة. السيناريو:
  /// - الجهاز A يُنشئ دفعة الساعة 10:00 → lastModified = 10:00
  /// - الرفع يتأخر → يصل السحابة 10:05 (لكن lastModified ما زال 10:00)
  /// - الجهاز B يسحب 10:06 بفلتر lastModified > (lastPullTs - 5)
  /// - السجل (10:00) أقل من cutoff → يُستبعد للأبد ❌
  ///
  /// الحل: `$updatedAt` حقل نظام في Appwrite يُضبط لحظة كتابة المستند فعلياً
  /// على الخادم، فيراه أي سحب لاحق مهما كان lastModified قديماً.
  ///
  /// المؤشر: يُشتق من `max($updatedAt)` في الصفحة المسحوبة (سلطة الخادم)،
  /// لا من `Time.nowEpoch()` (وقت الجهاز الساحب).
  ///
  /// نافذة الأمان: 15 ثانية — كافية لتفادي انحراف الساعات بين الأجهزة
  /// دون التسبب بجلب مكرر كبير.
  ///
  /// fallback: `lastModified` يُستخدم فقط إذا كان `lastPullTs` قديماً جداً
  /// (قبل تطبيق هذا الإصلاح) — لضمان عدم فقدان السجلات القديمة.
  ///
  /// إذا كان lastPullTs <= 0 → يُعيد قائمة فارغة (سحب كامل).
  static const int _safetyWindowSeconds = 15;

  Future<List<String>> buildDeltaQueries(int lastPullTs) async {
    if (lastPullTs <= 0) {
      return [];
    }
    final cutoffSeconds = lastPullTs - _safetyWindowSeconds;
    final cutoffIso = DateTime.fromMillisecondsSinceEpoch(
      cutoffSeconds * 1000,
      isUtc: true,
    ).toIso8601String();
    return [Query.greaterThan(r'$updatedAt', cutoffIso)];
  }

  /// ✅ إصلاح جوهري: يبني delta queries خاصة بـ booking_nights بنفس النهج
  /// (فلترة بـ `$updatedAt` بدل `lastModified`).
  ///
  /// نسخة متزامنة (non-async) تستقبل remoteEpochIsMillis كمعامل للتوافق
  /// مع الكود الموجود، لكنها تتجاهله الآن لأن `$updatedAt` بصيغة ISO
  /// (لا يتأثر بوحدة الثواني/الميلي ثانية).
  List<String> bookingNightsDeltaQueries(
    int lastPullTs, {
    required bool remoteEpochIsMillis,
  }) {
    if (lastPullTs > 0) {
      final cutoffSeconds = lastPullTs - _safetyWindowSeconds;
      final cutoffIso = DateTime.fromMillisecondsSinceEpoch(
        cutoffSeconds * 1000,
        isUtc: true,
      ).toIso8601String();
      return [Query.greaterThan(r'$updatedAt', cutoffIso)];
    }
    return []; // full fetch
  }

  // ── Booking Nights Pull Timestamp ──────────────────────────────────────

  /// يقرأ آخر timestamp لسحب booking_nights من SharedPreferences.
  /// يُعالج الحالة التي يكون فيها الطابع الزمني بالميلي ثانية بتحويله للثواني.
  Future<int> getBookingNightsPullTs() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt('sync_last_pull_booking_nights') ?? 0;
    if (ts > 10000000000) {
      return ts ~/ 1000;
    }
    return ts;
  }

  /// يحدّث آخر timestamp لسحب booking_nights في SharedPreferences.
  Future<void> updateBookingNightsPullTs(int ts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sync_last_pull_booking_nights', ts);
  }

  // ── Global Pull Timestamp ──────────────────────────────────────────────

  /// يقرأ آخر timestamp لسحب كل البيانات من جدول SyncState.
  /// يُعالج الحالة التي يكون فيها الطابع الزمني بالميلي ثانية.
  Future<int> getLastPullTs() async {
    try {
      final state = await (database.select(
        database.syncState,
      )..where((t) => t.id.equals(1))).getSingleOrNull();
      final ts = state?.lastPullTs ?? 0;
      if (ts > 10000000000) {
        return ts ~/ 1000;
      }
      return ts;
    } catch (_) {
      _logger.warning('Failed to read lastPullTs, using 0', tag: 'SYNC');
      return 0;
    }
  }

  /// يحدّث آخر timestamp لسحب كل البيانات في جدول SyncState.
  /// نستخدم insertOnConflictUpdate بدلاً من update فقط
  /// لأن صف SyncState (id=1) قد لا يكون موجوداً بعد، مما يجعل UPDATE
  /// لا يؤثر على أي صف — وبالتالي lastPullTs يبقى 0 للأبد،
  /// وكل مزامنة تسحب كل البيانات بدلاً من التغييرات فقط (delta).
  Future<void> updateLastPullTs(int ts) async {
    try {
      await database
          .into(database.syncState)
          .insertOnConflictUpdate(
            SyncStateCompanion(
              id: const drift.Value(1),
              lastPullTs: drift.Value(ts),
            ),
          );
    } catch (e) {
      _logger.warning('Failed to update lastPullTs: $e', tag: 'SYNC');
    }
  }
}

/// ✅ Audit Fix (2026-08-06): نتيجة فحص التعارض.
///
/// تُماثل `_RemoteNewerResult` في AppwriteSyncManager لكنها public
/// لتسمح لـ SyncPullService بإرجاعها مباشرة.
class RemoteCheckResult {
  const RemoteCheckResult({
    required this.shouldApplyRemote,
    this.mergedData,
    this.pushedToRemote = false,
  });

  /// هل يجب تطبيق البيانات البعيدة؟
  final bool shouldApplyRemote;

  /// البيانات المدموجة (فقط عند 3-way merge ناجح).
  final Map<String, dynamic>? mergedData;

  /// هل يجب رفع النتيجة للسحابة؟ (فقط عند 3-way merge مع pushedToRemote=true).
  final bool pushedToRemote;
}
