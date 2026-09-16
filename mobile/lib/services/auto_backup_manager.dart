// lib/services/auto_backup_manager.dart
//
// ✅ (2026-09-17) نسخة محلية فقط — بطلب المستخدم («مزامنة appwrite و
// sync google drive لا احتاجها نهائياً») أُزيل نظام Google Drive كاملاً
// فأُعيدت كتابة المدير ليحافظ على نفس الواجهة العامة التي يستدعيها
// المستودعات والخدمات (onDataChange) لكن بنسخ احتياطي محلي فقط.
//
// السياسة (حماية الأجهزة الضعيفة):
// - onDataChange يجمّع التغييرات في نافذة debounce (60 ثانية) ثم ينشئ
//   نسخة محلية واحدة — لا نسخة لكل عملية كتابة.
// - حد أدنى بين النسخ التلقائية (10 دقائق) — دفعات الكتابة المتلاحقة
//   تُنتج نسخة واحدة لا عشرات.
// - 'auto_local_backup_enabled' = false يعطّل المدير بالكامل.

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/debug_log.dart';
import 'local_backup_service.dart';

/// مدير النسخ الاحتياطي التلقائي المحلي — يُشغَّل بعد تغيّر البيانات.
class AutoBackupManager {
  AutoBackupManager._();

  static AutoBackupManager? _instance;
  // ignore: prefer_constructors_over_static_methods
  static AutoBackupManager get instance => _instance ??= AutoBackupManager._();

  static const String _autoLocalBackupEnabledKey = 'auto_local_backup_enabled';
  static const String _lastAutoBackupKey = 'last_auto_backup_timestamp';

  /// نافذة تجميع التغييرات قبل إنشاء نسخة واحدة.
  static const Duration _debounceWindow = Duration(seconds: 60);

  /// الحد الأدنى بين نسختين تلقائيتين متتاليتين.
  static const Duration _minInterval = Duration(minutes: 10);

  Timer? _debounceTimer;
  bool _isBackingUp = false;
  int _pendingChanges = 0;

  /// تهيئة (idempotent) — تُستدعى من مزود النسخ عند الحاجة.
  Future<void> initialize() async {
    dlog(() => '🤖 مدير النسخ المحلي التلقائي جاهز');
  }

  /// إشعار بتغيّر البيانات — يُستدعى من المستودعات/الخدمات بعد كل كتابة.
  ///
  /// يجمع التغييرات في نافذة debounce ثم ينشئ نسخة محلية واحدة عند
  /// اكتمالها (إن كان النسخ التلقائي مفعلاً ومرّ الحد الأدنى بين النسخ).
  Future<void> onDataChange(
    String table,
    String operation, {
    Map<String, dynamic>? recordData,
  }) async {
    _pendingChanges++;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceWindow, _createBackupIfDue);
  }

  Future<void> _createBackupIfDue() async {
    if (_isBackingUp) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_autoLocalBackupEnabledKey) ?? true;
      if (!enabled) {
        _pendingChanges = 0;
        return;
      }

      final lastMs = prefs.getInt(_lastAutoBackupKey) ?? 0;
      final elapsed = DateTime.now().millisecondsSinceEpoch - lastMs;
      if (elapsed < _minInterval.inMilliseconds) {
        dlog(
          () =>
              '⏭️ نسخة تلقائية مؤجلة — مضت ${elapsed ~/ 60000} دقيقة فقط '
              'من النسخة السابقة (الحد الأدنى ${_minInterval.inMinutes} دقيقة)',
        );
        _pendingChanges = 0;
        return;
      }

      _isBackingUp = true;
      final local = LocalBackupService();
      final format = await local.getPreferredBackupFormat();
      await local.createLocalBackup(format: format);
      await prefs.setInt(
        _lastAutoBackupKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      dlog(
        () =>
            '💾 نسخة محلية تلقائية بعد $_pendingChanges تغييراً مجمّعاً '
            '(صيغة ${format.name})',
      );
      _pendingChanges = 0;
    } catch (e) {
      dlog(() => '❌ فشل النسخ المحلي التلقائي: $e');
    } finally {
      _isBackingUp = false;
    }
  }

  /// تنظيف الموارد.
  Future<void> dispose() async {
    _debounceTimer?.cancel();
    _pendingChanges = 0;
  }

  /// حالة المدير (تشخيصية).
  Future<Map<String, dynamic>> getStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'enabled': prefs.getBool(_autoLocalBackupEnabledKey) ?? true,
      'is_backing_up': _isBackingUp,
      'pending_changes': _pendingChanges,
      'last_auto_backup': prefs.getInt(_lastAutoBackupKey),
      'debounce_seconds': _debounceWindow.inSeconds,
      'min_interval_minutes': _minInterval.inMinutes,
      'target': 'local',
    };
  }
}
