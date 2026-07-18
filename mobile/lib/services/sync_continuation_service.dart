// lib/services/sync_continuation_service.dart
//
// ✅ خدمة إكمال المزامنة عبر WorkManager عند إغلاق التطبيق.
//
// المشكلة التي تُحلّ:
// - عند الخروج من شاشة أثناء المزامنة، _pushPendingChangesOnPause()
//   يُحاول push خلال 10 ثوانٍ فقط.
// - إذا انتهى timeout قبل اكتمال المزامنة، تُفقد الفرصة.
// - البيانات محفوظة في outbox (آمنة) لكنها تنتظر المزامنة الدورية التالية (15 دقيقة).
//
// الحل:
// - عند كل خروج من الشاشة/إغلاق التطبيق أثناء مزامنة نشطة، نُسجّل
//   مهمة WorkManager فورية لإكمال المزامنة.
// - المهمة تعمل في الخلفية مع constraints (network connected).
// - تُحاول push + pull بشكل كامل.
// - تُحدّث pending flag عند الفشل ليُعالج في المرة القادمة.
//
// ملاحظة عن الـ Callback Dispatcher:
// Workmanager().initialize() يقبل callback واحد فقط. التطبيق يستخدم
// _unifiedCallbackDispatcher في main.dart الذي يُوجّه المهام بناءً
// على اسمها. هذا الـ service يُوفّر helpers فقط (schedule/cancel/consume).
//
// الاستخدام:
// ```dart
// // في didChangeAppLifecycleState (paused):
// await SyncContinuationService.scheduleSyncCompletion(
//   push: true,
//   pull: true,
// );
// ```

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'unified_sync_orchestrator.dart';

/// معرّفات المهام في WorkManager
const String kSyncCompletionTask = 'marina_sync_completion';
const String kSyncCompletionImmediateTask = 'marina_sync_completion_immediate';

/// ✅ مفاتيح SharedPreferences — public ليستخدمها _unifiedCallbackDispatcher
/// في main.dart بدون string literals (منع typos + DRY).
const String kSyncActiveFlag = 'sync_continuation_active';
const String kSyncPendingPushFlag = 'sync_continuation_pending_push';
const String kSyncPendingPullFlag = 'sync_continuation_pending_pull';
const String kSyncStartTimeKey = 'sync_continuation_start_time';

/// مدة صلاحية المهمة — إذا تجاوزتها، نعتبر المزامنة معلّقة ونعيد الجدولة
const Duration kMaxSyncDuration = Duration(minutes: 10);

/// خدمة إكمال المزامنة عبر WorkManager
class SyncContinuationService {
  SyncContinuationService._();

  static bool _initialized = false;

  /// تهيئة الخدمة (تُستدعى مرة واحدة من main.dart)
  static Future<void> initialize({bool debug = false}) async {
    if (_initialized) return;
    WidgetsFlutterBinding.ensureInitialized();
    _initialized = true;
    developer.log('✅ SyncContinuationService initialized', name: 'SyncContinuation');
  }

  /// جدولة مهمة إكمال المزامنة فوراً
  ///
  /// [push] هل نحتاج إكمال push
  /// [pull] هل نحتاج إكمال pull
  ///
  /// تُستدعى من:
  /// - didChangeAppLifecycleState (paused/inactive)
  /// - dispose() عندما يُدمّر الـ widget
  /// - أي مكان يُغادر فيه المستخدم الشاشة أثناء مزامنة
  static Future<void> scheduleSyncCompletion({bool push = true, bool pull = false}) async {
    if (!_initialized) {
      developer.log('⚠️ SyncContinuationService not initialized', name: 'SyncContinuation');
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      // تسجيل العمليات المعلّقة
      if (push) {
        await prefs.setBool(kSyncPendingPushFlag, true);
      }
      if (pull) {
        await prefs.setBool(kSyncPendingPullFlag, true);
      }
      await prefs.setBool(kSyncActiveFlag, true);

      // تسجيل وقت البدء (للفحص الزمني)
      if (prefs.getInt(kSyncStartTimeKey) == null) {
        await prefs.setInt(kSyncStartTimeKey, DateTime.now().millisecondsSinceEpoch);
      }

      // تسجيل مهمة WorkManager فورية
      // الـ callback dispatcher الموحّد في main.dart يُوجّه المهمة
      await Workmanager().registerOneOffTask(
        kSyncCompletionImmediateTask,
        kSyncCompletionImmediateTask,
        initialDelay: const Duration(seconds: 2), // تأخير بسيط
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.replace,
        inputData: <String, dynamic>{'push': push, 'pull': pull, 'scheduled_at': DateTime.now().toIso8601String()},
      );

      developer.log('📅 SyncContinuation: تمت جدولة مهمة الإكمال (push=$push, pull=$pull)', name: 'SyncContinuation');
    } catch (e) {
      developer.log('⚠️ SyncContinuation: فشل جدولة المهمة: $e', name: 'SyncContinuation');
    }
  }

  /// جدولة مهمة دورية للتأكد من إكمال المزامنات المعلّقة
  ///
  /// تُسجّل مرة واحدة عند بدء التطبيق لتفقد المزامنات المعلّقة
  /// كل 15 دقيقة (الحد الأدنى لـ WorkManager على Android).
  static Future<void> schedulePeriodicCheck() async {
    if (!_initialized) return;

    try {
      await Workmanager().registerPeriodicTask(
        kSyncCompletionTask,
        kSyncCompletionTask,
        frequency: const Duration(minutes: 15),
        initialDelay: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );

      developer.log('📅 SyncContinuation: تم تسجيل الفحص الدوري (كل 15 دقيقة)', name: 'SyncContinuation');
    } catch (e) {
      developer.log('⚠️ SyncContinuation: فشل تسجيل الفحص الدوري: $e', name: 'SyncContinuation');
    }
  }

  /// إلغاء جميع مهام الإكمال
  static Future<void> cancelAll() async {
    try {
      await Workmanager().cancelByUniqueName(kSyncCompletionImmediateTask);
      await Workmanager().cancelByUniqueName(kSyncCompletionTask);
      final prefs = await SharedPreferences.getInstance();
      await _clearAllFlags(prefs);
      developer.log('🧹 SyncContinuation: تم إلغاء جميع المهام', name: 'SyncContinuation');
    } catch (e) {
      developer.log('⚠️ SyncContinuation: فشل الإلغاء: $e', name: 'SyncContinuation');
    }
  }

  /// هل توجد عمليات معلّقة؟
  static Future<bool> hasPendingOperations() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getBool(kSyncPendingPushFlag) ?? false) || (prefs.getBool(kSyncPendingPullFlag) ?? false);
  }

  /// استهلاك العمليات المعلّقة وتشغيل المزامنة في التطبيق الرئيسي
  ///
  /// يُستدعى عند عودة التطبيق للواجهة (resumed) لإكمال أي عمليات معلّقة
  /// قبل انتظار WorkManager.
  static Future<void> consumePendingAndSync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasPendingPush = prefs.getBool(kSyncPendingPushFlag) ?? false;
      final hasPendingPull = prefs.getBool(kSyncPendingPullFlag) ?? false;

      if (!hasPendingPush && !hasPendingPull) {
        return;
      }

      developer.log(
        '🔄 SyncContinuation: استهلاك معلّق (push=$hasPendingPush, pull=$hasPendingPull)',
        name: 'SyncContinuation',
      );

      // تنفيذ المزامنة في التطبيق الرئيسي
      await UnifiedSyncOrchestrator.instance.syncNow(
        push: hasPendingPush,
        pull: hasPendingPull,
        reason: 'consume_pending_sync',
      );

      // تنظيف الأعلام
      await _clearAllFlags(prefs);

      // إلغاء مهمة WorkManager (لم تعد ضرورية)
      await Workmanager().cancelByUniqueName(kSyncCompletionImmediateTask);

      developer.log('✅ SyncContinuation: تم استهلاك المعلّق بنجاح', name: 'SyncContinuation');
    } catch (e) {
      developer.log('⚠️ SyncContinuation: فشل استهلاك المعلّق: $e', name: 'SyncContinuation');
    }
  }

  /// تنظيف كل الأعلام
  static Future<void> _clearAllFlags(SharedPreferences prefs) async {
    await prefs.setBool(kSyncActiveFlag, false);
    await prefs.setBool(kSyncPendingPushFlag, false);
    await prefs.setBool(kSyncPendingPullFlag, false);
    await prefs.remove(kSyncStartTimeKey);
  }

  /// معلومات تصحيح الأخطاء
  static Future<Map<String, dynamic>> getDebugInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'initialized': _initialized,
      'active': prefs.getBool(kSyncActiveFlag) ?? false,
      'pending_push': prefs.getBool(kSyncPendingPushFlag) ?? false,
      'pending_pull': prefs.getBool(kSyncPendingPullFlag) ?? false,
      'start_time': prefs.getInt(kSyncStartTimeKey),
      'elapsed_seconds': prefs.getInt(kSyncStartTimeKey) != null
          ? (DateTime.now().millisecondsSinceEpoch - prefs.getInt(kSyncStartTimeKey)!) ~/ 1000
          : 0,
    };
  }
}
