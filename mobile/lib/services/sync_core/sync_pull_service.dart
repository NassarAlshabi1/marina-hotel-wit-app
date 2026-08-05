// ignore_for_file: unused_element, deprecated_member_use
import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:drift/drift.dart' as drift;
import 'package:shared_preferences/shared_preferences.dart';

import '../appwrite_config.dart';
import '../appwrite_logger.dart';
import '../appwrite_service.dart';
import '../daos/outbox_dao.dart';
import '../local_db.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// خدمة سحب التغييرات من Appwrite Cloud إلى القاعدة المحلية
///
/// نسخة مُنظَّفة (v2) — تحتوي فقط على الدوال المستخدمة فعليًا من AppwriteSyncManager.
/// الدوال المُكررة (17 دالة _syncXxx + دوال المساعدة) محذوفة لأن AppwriteSyncManager
/// يحتفظ بنسخه الخاصة الحية منها.
///
/// الدوال المُستخدمة (7):
///   - buildDeltaQueries / bookingNightsDeltaQueries
///   - isRemoteEpochMillis
///   - getBookingNightsPullTs / updateBookingNightsPullTs
///   - getLastPullTs / updateLastPullTs
class SyncPullService {
  SyncPullService({
    required this.appwriteService,
    required this.database,
    required this.outboxDao,
    AppwriteLogger? logger,
  }) : _logger = logger ?? AppwriteLogger();

  final AppwriteService appwriteService;
  final AppDatabase database;
  final OutboxDao outboxDao;
  final AppwriteLogger _logger;

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
    } catch (e) {
      debugPrint('⚠️ Swallowed error in sync_pull_service.dart: ');
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
    } catch (e) {
      debugPrint('⚠️ Swallowed error in sync_pull_service.dart: ');
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
