import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/google_drive_backup_service.dart' show GoogleDriveBackupService, BackupFormat, DriveBackupFile;
import '../services/google_drive_logger.dart';
import '../services/logging/log_models.dart';
import '../services/local_backup_service.dart' show LocalBackupService, LocalBackupFile;
import '../services/file_management_service.dart';
import '../services/auto_backup_task.dart';
import '../services/smart_sync_manager.dart';
import '../services/google_drive_auto_sync_engine.dart';

import '../services/sqlite_backup_restore.dart';
import '../services/restore_fix_service.dart';
import '../services/local_db.dart';

const _driveLoginSkippedKey = 'drive_login_skipped';

// حالة النسخ الاحتياطي
enum BackupStatus { idle, signIn, uploading, downloading, restoring, success, error, checkingPermissions, importingFile }

// نوع النسخ الاحتياطي
enum BackupType { googleDrive, local, both }

// حالة النسخ التلقائي
class AutoBackupSettings {
  final bool isEnabled;
  final String frequency; // daily, weekly, monthly
  final String time; // HH:mm format
  final int? weekday; // 1-7 للنسخ الأسبوعي
  final int? day; // 1-31 للنسخ الشهري
  final BackupType backupType; // نوع النسخ (Google Drive، محلي، أو كليهما)
  final bool enableLocalBackup; // تفعيل النسخ المحلي
  final bool enableGoogleDriveBackup; // تفعيل النسخ السحابي
  final BackupFormat backupFormat; // تنسيق النسخ الاحتياطي المستخدم

  const AutoBackupSettings({
    this.isEnabled = true,
    this.frequency = 'daily',
    this.time = '02:00',
    this.weekday,
    this.day,
    this.backupType = BackupType.both,
    this.enableLocalBackup = true,
    this.enableGoogleDriveBackup = true,
    this.backupFormat = BackupFormat.json,
  });

  AutoBackupSettings copyWith({
    bool? isEnabled,
    String? frequency,
    String? time,
    int? weekday,
    int? day,
    BackupType? backupType,
    bool? enableLocalBackup,
    bool? enableGoogleDriveBackup,
    BackupFormat? backupFormat,
  }) {
    return AutoBackupSettings(
      isEnabled: isEnabled ?? this.isEnabled,
      frequency: frequency ?? this.frequency,
      time: time ?? this.time,
      weekday: weekday ?? this.weekday,
      day: day ?? this.day,
      backupType: backupType ?? this.backupType,
      enableLocalBackup: enableLocalBackup ?? this.enableLocalBackup,
      enableGoogleDriveBackup: enableGoogleDriveBackup ?? this.enableGoogleDriveBackup,
      backupFormat: backupFormat ?? this.backupFormat,
    );
  }
}

// حالة عملية النسخ الاحتياطي
class BackupState {
  final BackupStatus status;
  final String? message;
  final double? progress;
  final GoogleSignInAccount? signedInAccount;
  final DateTime? lastBackupTime;
  final List<DriveBackupFile> availableBackups;
  final List<LocalBackupFile> localBackups;
  final DateTime? lastLocalBackupTime;
  final AutoBackupSettings autoSettings;
  final int? databaseSizeBytes;
  final bool hasStoragePermission;
  final Map<String, dynamic>? backupFolderInfo;
  final String? lastSqliteBackupPath;
  final bool driveLoginSkipped;

  BackupState({
    this.status = BackupStatus.idle,
    this.message,
    this.progress,
    this.signedInAccount,
    this.lastBackupTime,
    this.availableBackups = const [],
    this.localBackups = const [],
    this.lastLocalBackupTime,
    this.autoSettings = const AutoBackupSettings(),
    this.databaseSizeBytes,
    this.hasStoragePermission = false,
    this.backupFolderInfo,
    this.lastSqliteBackupPath,
    this.driveLoginSkipped = false,
  });

  BackupState copyWith({
    BackupStatus? status,
    String? message,
    double? progress,
    GoogleSignInAccount? signedInAccount,
    DateTime? lastBackupTime,
    List<DriveBackupFile>? availableBackups,
    List<LocalBackupFile>? localBackups,
    DateTime? lastLocalBackupTime,
    AutoBackupSettings? autoSettings,
    int? databaseSizeBytes,
    bool? hasStoragePermission,
    Map<String, dynamic>? backupFolderInfo,
    String? lastSqliteBackupPath,
    bool? driveLoginSkipped,
  }) {
    return BackupState(
      status: status ?? this.status,
      message: message ?? this.message,
      progress: progress ?? this.progress,
      signedInAccount: signedInAccount ?? this.signedInAccount,
      lastBackupTime: lastBackupTime ?? this.lastBackupTime,
      availableBackups: availableBackups ?? this.availableBackups,
      localBackups: localBackups ?? this.localBackups,
      lastLocalBackupTime: lastLocalBackupTime ?? this.lastLocalBackupTime,
      autoSettings: autoSettings ?? this.autoSettings,
      databaseSizeBytes: databaseSizeBytes ?? this.databaseSizeBytes,
      hasStoragePermission: hasStoragePermission ?? this.hasStoragePermission,
      backupFolderInfo: backupFolderInfo ?? this.backupFolderInfo,
      lastSqliteBackupPath: lastSqliteBackupPath ?? this.lastSqliteBackupPath,
      driveLoginSkipped: driveLoginSkipped ?? this.driveLoginSkipped,
    );
  }

  bool get isSignedIn => signedInAccount != null;
  bool get requiresDriveLogin => !isSignedIn && !driveLoginSkipped;
  bool get isWorking => status == BackupStatus.signIn || 
                       status == BackupStatus.uploading ||
                       status == BackupStatus.downloading ||
                       status == BackupStatus.restoring ||
                       status == BackupStatus.checkingPermissions ||
                       status == BackupStatus.importingFile;
}

// Notifier للتحكم في حالة النسخ الاحتياطي
class BackupStatusNotifier extends StateNotifier<BackupState> {
  BackupStatusNotifier(this._backupService, this._localBackupService, this._fileService) : super(BackupState()) {
    _initialize();
  }

  final GoogleDriveBackupService _backupService;
  final LocalBackupService _localBackupService;
  final FileManagementService _fileService;

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final skipPref = prefs.getBool(_driveLoginSkippedKey) ?? false;
      // جلب آخر وقت نسخ احتياطي (Google Drive)
      final lastBackup = await _backupService.getLastBackupTime();
      
      // جلب آخر وقت نسخ احتياطي محلي
      final lastLocalBackup = await _localBackupService.getLastLocalBackupTime();
      
      // جلب حجم قاعدة البيانات
      final dbSize = await _backupService.estimateDatabaseSize();
      
      // التحقق من أذونات التخزين المحلي
      final hasPermission = await _localBackupService.checkPermissions();
      
      // جلب معلومات مجلد النسخ المحلي
      Map<String, dynamic>? folderInfo;
      List<LocalBackupFile> localBackups = [];
      if (hasPermission) {
        folderInfo = await _localBackupService.getBackupFolderInfo();
        localBackups = await _localBackupService.listLocalBackups();
      }
      
      // جلب إعدادات النسخ التلقائي
      final autoEnabled = await _backupService.isAutoBackupEnabled();
      final frequency = await _backupService.getAutoBackupFrequency();
      final time = await _backupService.getAutoBackupTime();
      final enableLocal = await _localBackupService.isAutoLocalBackupEnabled();
      final localFreq = await _localBackupService.getAutoLocalBackupFrequency();

      final isAutoEnabled = autoEnabled || enableLocal;
      final resolvedFrequency = autoEnabled ? frequency : localFreq;
      final resolvedBackupType = enableLocal && autoEnabled
          ? BackupType.both
          : enableLocal
              ? BackupType.local
              : autoEnabled
                  ? BackupType.googleDrive
                  : BackupType.both;

      // محاولة استعادة جلسة Google Drive تلقائياً
      await _backupService.attemptSilentSignIn();
      
      // التحقق من تسجيل الدخول في Google Drive
      GoogleSignInAccount? account;
      List<DriveBackupFile> driveBackups = [];
      if (_backupService.isSignedIn) {
        account = _backupService.currentUser;
        
        // إشعار مديري المزامنة بنجاح تسجيل الدخول الصامت
        await _notifySyncManagers(true);
        
        // جلب قائمة النسخ المتاحة في Google Drive
        try {
          driveBackups = await _backupService.listBackupFiles();
        } catch (e) {
          debugPrint('⚠️ خطأ في جلب نسخ Google Drive: $e');
        }
      }

      if (account != null && skipPref) {
        await prefs.setBool(_driveLoginSkippedKey, false);
      }
      final driveLoginSkipped = account == null && skipPref;

      state = state.copyWith(
        lastBackupTime: lastBackup,
        lastLocalBackupTime: lastLocalBackup,
        databaseSizeBytes: dbSize,
        hasStoragePermission: hasPermission,
        backupFolderInfo: folderInfo,
        localBackups: localBackups,
        availableBackups: driveBackups,
        signedInAccount: account,
        autoSettings: AutoBackupSettings(
          isEnabled: isAutoEnabled,
          frequency: resolvedFrequency,
          time: time,
          enableLocalBackup: enableLocal,
          enableGoogleDriveBackup: autoEnabled,
          backupType: resolvedBackupType,
        ),
        driveLoginSkipped: driveLoginSkipped,
      );
    } catch (e) {
      debugPrint('❌ خطأ في تهيئة BackupStatusNotifier: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في التهيئة: ${e.toString()}',
      );
    }
  }

  Future<void> setSkippedDriveLogin(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_driveLoginSkippedKey, value);
    state = state.copyWith(driveLoginSkipped: value);
  }

  /// إشعار مديري المزامنة بتغير حالة تسجيل الدخول
  Future<void> _notifySyncManagers(bool isSignedIn) async {
    // إشعار مدير المزامنة الذكية
    try {
      final smartSync = SmartSyncManager.instance;
      await smartSync.onGoogleDriveSignInChanged(isSignedIn);
    } catch (e) {
      debugPrint('⚠️ خطأ في إشعار مدير المزامنة: $e');
    }
    
    // إشعار محرك المزامنة التلقائية
    try {
      final autoSyncEngine = AutoSyncEngine.instance;
      await autoSyncEngine.onSignInChanged(isSignedIn);
    } catch (e) {
      debugPrint('⚠️ خطأ في إشعار محرك المزامنة التلقائية: $e');
    }
  }

  /// تسجيل الدخول في Google Drive
  Future<void> signInToDrive() async {
    try {
      state = state.copyWith(
        status: BackupStatus.signIn,
        message: 'تسجيل الدخول في Google Drive...',
      );

      final account = await _backupService.signInForDrive();
      
      if (account != null) {
        await setSkippedDriveLogin(false);
        
        // جلب قائمة النسخ المتاحة (مع معالجة الأخطاء)
        List<DriveBackupFile> backups = [];
        try {
          backups = await _backupService.listBackupFiles();
        } catch (e) {
          debugPrint('⚠️ خطأ في جلب قائمة النسخ الاحتياطية: $e');
        }
        
        // إشعار مديري المزامنة بتغير حالة تسجيل الدخول (مع معالجة الأخطاء)
        try {
          await _notifySyncManagers(true);
        } catch (e) {
          debugPrint('⚠️ خطأ في إشعار مديري المزامنة: $e');
        }
        
        state = state.copyWith(
          status: BackupStatus.success,
          message: 'تم تسجيل الدخول بنجاح',
          signedInAccount: account,
          availableBackups: backups,
        );
        
        // مسح الرسالة تلقائياً بعد 3 ثوانٍ
        Future.delayed(const Duration(seconds: 3), () {
          if (state.message == 'تم تسجيل الدخول بنجاح') {
            clearMessage();
          }
        });
      } else {
        state = state.copyWith(
          status: BackupStatus.error,
          message: 'فشل تسجيل الدخول',
        );
      }
    } catch (e) {
      debugPrint('❌ خطأ في تسجيل الدخول: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في تسجيل الدخول: ${e.toString()}',
      );
    }
  }

  /// تسجيل الخروج من Google Drive
  Future<void> signOut() async {
    try {
      await _backupService.signOut();
      await setSkippedDriveLogin(false);
      
      // إشعار مديري المزامنة بتسجيل الخروج
      await _notifySyncManagers(false);
      
      state = state.copyWith(
        status: BackupStatus.success,
        message: 'تم تسجيل الخروج',
        signedInAccount: null,
        availableBackups: [],
      );
    } catch (e) {
      debugPrint('❌ خطأ في تسجيل الخروج: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في تسجيل الخروج: ${e.toString()}',
      );
    }
  }

  /// إنشاء نسخة احتياطية
  Future<void> createBackup() async {
    if (!state.isSignedIn) {
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'يجب تسجيل الدخول أولاً',
      );
      return;
    }

    try {
      state = state.copyWith(
        status: BackupStatus.uploading,
        message: 'تجهيز النسخة الاحتياطية...',
        progress: 0.0,
      );

      state = state.copyWith(
        message: 'رفع النسخة الاحتياطية...',
        progress: 0.5,
      );

      final backupData = await _backupService.exportDatabaseToJson();
      // رفع كنسخة شاملة يدوية (isSync = false بشكل افتراضي)
      await _backupService.uploadBackup(backupData);
      
      state = state.copyWith(
        message: 'جلب قائمة النسخ المحدثة...',
        progress: 0.8,
      );

      // تحديث قائمة النسخ المتاحة
      final backups = await _backupService.listBackupFiles();
      final lastBackup = await _backupService.getLastBackupTime();

      state = state.copyWith(
        status: BackupStatus.success,
        message: 'تم إنشاء النسخة الاحتياطية بنجاح',
        progress: 1.0,
        availableBackups: backups,
        lastBackupTime: lastBackup,
      );
    } catch (e) {
      debugPrint('❌ خطأ في إنشاء النسخة الاحتياطية: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في إنشاء النسخة الاحتياطية: ${e.toString()}',
        progress: null,
      );
    }
  }

  /// استعادة من نسخة احتياطية
  Future<void> restoreFromBackup(String fileId) async {
    if (!state.isSignedIn) {
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'يجب تسجيل الدخول أولاً',
      );
      return;
    }

    try {
      DriveBackupFile? driveBackup;
      try {
        driveBackup = state.availableBackups.firstWhere(
          (backup) => backup.fileId == fileId,
        );
      } catch (_) {
        driveBackup = null;
      }

      if (driveBackup == null) {
        state = state.copyWith(
          status: BackupStatus.error,
          message: 'لم يتم العثور على النسخة الاحتياطية المحددة.',
        );
        return;
      }

      state = state.copyWith(
        status: BackupStatus.downloading,
        message: 'تنزيل النسخة الاحتياطية...',
        progress: 0.0,
      );

      final downloaded = await _backupService.downloadBackup(driveBackup.fileId);

      state = state.copyWith(
        status: BackupStatus.restoring,
        message: 'استعادة البيانات...',
        progress: 0.5,
      );

      await _backupService.restoreFromBackup(downloaded);

      // تشغيل الإصلاح التلقائي
      state = state.copyWith(
        status: BackupStatus.restoring,
        message: 'تشغيل عملية الإصلاح التلقائي...',
        progress: 0.8,
      );

      final fixService = RestoreFixService(DatabaseManager.instance);
      final fixReport = await fixService.runAutoFixAfterRestore();

      if (!fixReport.success) {
        debugPrint('⚠️ فشل الإصلاح التلقائي: ${fixReport.error}');
      } else {
        debugPrint('✅ اكتمل الإصلاح التلقائي: ${fixReport.bookingsFixed} حجز، ${fixReport.roomsUpdated} غرفة');
      }

      state = state.copyWith(
        status: BackupStatus.success,
        message: 'تم استعادة البيانات بنجاح',
        progress: 1.0,
      );
    } catch (e) {
      debugPrint('❌ خطأ في استعادة البيانات: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في استعادة البيانات: ${e.toString()}',
        progress: null,
      );
    }
  }

  /// تحديث قائمة النسخ المتاحة
  Future<void> refreshBackupsList() async {
    if (!state.isSignedIn) return;

    try {
      final backups = await _backupService.listBackupFiles();
      state = state.copyWith(availableBackups: backups);
    } catch (e) {
      debugPrint('❌ خطأ في تحديث قائمة النسخ: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في تحديث قائمة النسخ: ${e.toString()}',
      );
    }
  }

  /// تحديث حجم قاعدة البيانات
  Future<void> updateDatabaseSize() async {
    try {
      final size = await _backupService.estimateDatabaseSize();
      state = state.copyWith(databaseSizeBytes: size);
    } catch (e) {
      debugPrint('❌ خطأ في تحديث حجم قاعدة البيانات: $e');
    }
  }

  /// تحديث إعدادات النسخ التلقائي
  Future<void> updateAutoBackupSettings(AutoBackupSettings settings) async {
    try {
      final enableDrive = settings.isEnabled && settings.enableGoogleDriveBackup;
      final enableLocal = settings.isEnabled && settings.enableLocalBackup;
      final shouldScheduleTask = enableDrive || enableLocal;

      await _backupService.setAutoBackupEnabled(enableDrive);
      await _backupService.setAutoBackupFrequency(settings.frequency);
      await _backupService.setAutoBackupTime(settings.time);

      await _localBackupService.setAutoLocalBackupEnabled(enableLocal);
      await _localBackupService.setAutoLocalBackupFrequency(settings.frequency);

      if (shouldScheduleTask) {
        switch (settings.frequency) {
          case 'daily':
            await AutoBackupTask.scheduleDaily(time: settings.time);
            break;
          case 'weekly':
            await AutoBackupTask.scheduleWeekly(
              time: settings.time,
              weekday: settings.weekday ?? 1,
            );
            break;
          case 'monthly':
            await AutoBackupTask.scheduleMonthly(
              time: settings.time,
              day: settings.day ?? 1,
            );
            break;
          default:
            await AutoBackupTask.scheduleDaily(time: settings.time);
            break;
        }
      } else {
        await AutoBackupTask.cancelScheduled();
      }

      final updatedBackupType = enableDrive && enableLocal
          ? BackupType.both
          : enableLocal
              ? BackupType.local
              : enableDrive
                  ? BackupType.googleDrive
                  : settings.backupType;

      state = state.copyWith(
        autoSettings: settings.copyWith(
          isEnabled: shouldScheduleTask,
          backupType: updatedBackupType,
        ),
        status: BackupStatus.success,
        message: 'تم تحديث إعدادات النسخ التلقائي',
      );
    } catch (e) {
      debugPrint('❌ خطأ في تحديث إعدادات النسخ التلقائي: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في تحديث إعدادات النسخ التلقائي: ${e.toString()}',
      );
    }
  }

  /// مسح رسالة الحالة
  void clearMessage() {
    state = state.copyWith(
      status: BackupStatus.idle,
      message: null,
      progress: null,
    );
  }

  // وظائف النسخ الاحتياطي المحلي

  /// التحقق من أذونات التخزين المحلي
  Future<void> checkStoragePermissions() async {
    try {
      state = state.copyWith(
        status: BackupStatus.checkingPermissions,
        message: 'التحقق من أذونات التخزين...',
      );

      final hasPermission = await _localBackupService.checkPermissions();
      
      if (hasPermission) {
        // جلب معلومات مجلد النسخ والنسخ المحفوظة
        final folderInfo = await _localBackupService.getBackupFolderInfo();
        final localBackups = await _localBackupService.listLocalBackups();
        
        state = state.copyWith(
          status: BackupStatus.success,
          message: 'تم الحصول على أذونات التخزين',
          hasStoragePermission: hasPermission,
          backupFolderInfo: folderInfo,
          localBackups: localBackups,
        );
      } else {
        state = state.copyWith(
          status: BackupStatus.error,
          message: 'لا توجد أذونات للوصول للتخزين المحلي',
          hasStoragePermission: hasPermission,
        );
      }
    } catch (e) {
      debugPrint('❌ خطأ في التحقق من أذونات التخزين: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في التحقق من الأذونات: ${e.toString()}',
        hasStoragePermission: false,
      );
    }
  }

  /// إنشاء نسخة احتياطية محلية
  Future<void> createLocalBackup() async {
    if (!state.hasStoragePermission) {
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'لا توجد أذونات للوصول للتخزين المحلي',
        progress: null,
      );
      return;
    }

    try {
      state = state.copyWith(
        status: BackupStatus.uploading,
        message: 'إنشاء نسخة احتياطية محلية...',
        progress: 0.0,
      );

      final backupPath = await _localBackupService.createLocalBackup(
        format: state.autoSettings.backupFormat,
      );
      
      state = state.copyWith(
        message: 'تحديث قائمة النسخ...',
        progress: 0.8,
      );

      // تحديث قائمة النسخ المحلية
      final localBackups = await _localBackupService.listLocalBackups();
      final lastLocalBackup = await _localBackupService.getLastLocalBackupTime();
      final folderInfo = await _localBackupService.getBackupFolderInfo();

      state = state.copyWith(
        status: BackupStatus.success,
        message: 'تم إنشاء النسخة الاحتياطية المحلية بنجاح في: $backupPath',
        progress: 1.0,
        localBackups: localBackups,
        lastLocalBackupTime: lastLocalBackup,
        backupFolderInfo: folderInfo,
      );

      debugPrint('💾 Local backup saved at $backupPath');
    } catch (e) {
      debugPrint('❌ خطأ في إنشاء النسخة الاحتياطية المحلية: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في إنشاء النسخة الاحتياطية المحلية: ${e.toString()}',
        progress: null,
      );
    }
  }

  /// استعادة من نسخة احتياطية محلية
  Future<void> restoreFromLocalBackup(String filePath) async {
    try {
      state = state.copyWith(
        status: BackupStatus.restoring,
        message: 'استعادة النسخة الاحتياطية المحلية...',
        progress: 0.0,
      );

      await _localBackupService.restoreFromLocalBackup(filePath);

      // تشغيل الإصلاح التلقائي
      state = state.copyWith(
        status: BackupStatus.restoring,
        message: 'تشغيل عملية الإصلاح التلقائي...',
        progress: 0.8,
      );

      final fixService = RestoreFixService(DatabaseManager.instance);
      final fixReport = await fixService.runAutoFixAfterRestore();

      if (!fixReport.success) {
        debugPrint('⚠️ فشل الإصلاح التلقائي: ${fixReport.error}');
      } else {
        debugPrint('✅ اكتمل الإصلاح التلقائي: ${fixReport.bookingsFixed} حجز، ${fixReport.roomsUpdated} غرفة');
      }

      state = state.copyWith(
        status: BackupStatus.success,
        message: 'تم استعادة البيانات من النسخة المحلية بنجاح',
        progress: 1.0,
      );
    } catch (e) {
      debugPrint('❌ خطأ في استعادة البيانات من النسخة المحلية: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في استعادة البيانات: ${e.toString()}',
        progress: null,
      );
    }
  }

  /// إنشاء نسخة احتياطية لملف SQLite داخل مجلد Documents/MarinaHotelBackups المشارك مع المستخدم
  Future<void> createSqliteFileBackup() async {
    try {
      state = state.copyWith(
        status: BackupStatus.uploading,
        message: 'جاري إنشاء نسخة من ملف قاعدة البيانات...',
        progress: 0.0,
        lastSqliteBackupPath: null,
      );

      final path = await SqliteBackupRestore.backupDatabase();

      state = state.copyWith(
        status: BackupStatus.success,
        message: 'تم حفظ نسخة قاعدة البيانات في: $path',
        progress: 1.0,
        lastSqliteBackupPath: path,
      );
    } catch (e) {
      debugPrint('❌ خطأ في النسخ الاحتياطي لملف SQLite: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'فشل إنشاء نسخة ملف قاعدة البيانات: ${e.toString()}',
        progress: null,
      );
    }
  }

  /// استعادة قاعدة البيانات من ملف .db محدد
  Future<void> restoreFromSqliteFile(String sourcePath) async {
    try {
      state = state.copyWith(
        status: BackupStatus.restoring,
        message: 'جاري استعادة ملف قاعدة البيانات...',
        progress: 0.0,
      );

      await SqliteBackupRestore.restoreDatabase(sourcePath);

      // تشغيل الإصلاح التلقائي
      state = state.copyWith(
        status: BackupStatus.restoring,
        message: 'تشغيل عملية الإصلاح التلقائي...',
        progress: 0.8,
      );

      final fixService = RestoreFixService(DatabaseManager.instance);
      final fixReport = await fixService.runAutoFixAfterRestore();

      if (!fixReport.success) {
        debugPrint('⚠️ فشل الإصلاح التلقائي: ${fixReport.error}');
      } else {
        debugPrint('✅ اكتمل الإصلاح التلقائي: ${fixReport.bookingsFixed} حجز، ${fixReport.roomsUpdated} غرفة');
      }

      state = state.copyWith(
        status: BackupStatus.success,
        message: 'تمت استعادة قاعدة البيانات بنجاح',
        progress: 1.0,
      );
    } catch (e) {
      debugPrint('❌ خطأ في استعادة ملف SQLite: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'فشل استعادة قاعدة البيانات: ${e.toString()}',
        progress: null,
      );
    }
  }

  /// مشاركة نسخة احتياطية محلية
  Future<void> shareLocalBackup(String filePath) async {
    try {
      await _localBackupService.shareBackup(filePath);
      state = state.copyWith(
        status: BackupStatus.success,
        message: 'تم مشاركة النسخة الاحتياطية',
      );
    } catch (e) {
      debugPrint('❌ خطأ في مشاركة النسخة الاحتياطية: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في مشاركة النسخة الاحتياطية: ${e.toString()}',
      );
    }
  }

  /// استيراد نسخة احتياطية من ملف خارجي
  Future<void> importBackupFromFile() async {
    try {
      state = state.copyWith(
        status: BackupStatus.importingFile,
        message: 'استيراد ملف النسخة الاحتياطية...',
        progress: 0.0,
      );

      final importedPath = await _localBackupService.importBackupFromFile();
      
      state = state.copyWith(
        message: 'تحديث قائمة النسخ...',
        progress: 0.8,
      );

      // تحديث قائمة النسخ المحلية
      final localBackups = await _localBackupService.listLocalBackups();
      final folderInfo = await _localBackupService.getBackupFolderInfo();

      state = state.copyWith(
        status: BackupStatus.success,
        message: 'تم استيراد النسخة الاحتياطية من: $importedPath',
        progress: 1.0,
        localBackups: localBackups,
        backupFolderInfo: folderInfo,
      );

      debugPrint('📥 Imported backup from $importedPath');
    } catch (e) {
      debugPrint('❌ خطأ في استيراد النسخة الاحتياطية: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في استيراد النسخة الاحتياطية: ${e.toString()}',
        progress: null,
      );
    }
  }

  /// تصدير نسخة احتياطية إلى مجلد Downloads
  Future<void> exportToDownloads() async {
    try {
      state = state.copyWith(
        status: BackupStatus.uploading,
        message: 'تصدير النسخة الاحتياطية...',
        progress: 0.0,
      );

      final exportPath = await _localBackupService.exportToDownloads();

      state = state.copyWith(
        status: BackupStatus.success,
        message: 'تم تصدير النسخة الاحتياطية إلى: $exportPath',
        progress: 1.0,
      );

      debugPrint('📤 Exported backup to $exportPath');
    } catch (e) {
      debugPrint('❌ خطأ في تصدير النسخة الاحتياطية: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في تصدير النسخة الاحتياطية: ${e.toString()}',
        progress: null,
      );
    }
  }

  /// حذف نسخة احتياطية محلية
  Future<void> deleteLocalBackup(String filePath) async {
    try {
      await _localBackupService.deleteLocalBackup(filePath);
      
      // تحديث قائمة النسخ المحلية
      final localBackups = await _localBackupService.listLocalBackups();
      final folderInfo = await _localBackupService.getBackupFolderInfo();

      state = state.copyWith(
        status: BackupStatus.success,
        message: 'تم حذف النسخة الاحتياطية',
        localBackups: localBackups,
        backupFolderInfo: folderInfo,
      );
    } catch (e) {
      debugPrint('❌ خطأ في حذف النسخة الاحتياطية: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في حذف النسخة الاحتياطية: ${e.toString()}',
      );
    }
  }

  /// تحديث قائمة النسخ المحلية
  Future<void> refreshLocalBackups() async {
    if (!state.hasStoragePermission) return;

    try {
      final localBackups = await _localBackupService.listLocalBackups();
      final folderInfo = await _localBackupService.getBackupFolderInfo();
      
      state = state.copyWith(
        localBackups: localBackups,
        backupFolderInfo: folderInfo,
      );
    } catch (e) {
      debugPrint('❌ خطأ في تحديث قائمة النسخ المحلية: $e');
    }
  }

  /// تنظيف النسخ القديمة
  Future<void> cleanOldLocalBackups({int keepCount = 10}) async {
    try {
      await _localBackupService.cleanOldBackups(keepCount: keepCount);
      
      // تحديث قائمة النسخ المحلية
      await refreshLocalBackups();
      
      state = state.copyWith(
        status: BackupStatus.success,
        message: 'تم تنظيف النسخ القديمة',
      );
    } catch (e) {
      debugPrint('❌ خطأ في تنظيف النسخ القديمة: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في تنظيف النسخ القديمة: ${e.toString()}',
      );
    }
  }

  /// إنشاء نسخة احتياطية شاملة (محلي + Google Drive)
  Future<void> createComprehensiveBackup() async {
    String? tempSqlitePath;
    try {
      state = state.copyWith(
        status: BackupStatus.uploading,
        message: 'إنشاء نسخة احتياطية شاملة...',
        progress: 0.0,
      );

      String? localBackupPath;

      // إنشاء النسخة المحلية أولاً
      if (state.hasStoragePermission) {
        state = state.copyWith(
          message: 'إنشاء النسخة المحلية...',
          progress: 0.2,
        );
        localBackupPath = await _localBackupService.createLocalBackup(format: state.autoSettings.backupFormat);
      }

      // ثم النسخة السحابية إذا كان المستخدم مسجل الدخول
      if (state.isSignedIn) {
        state = state.copyWith(
          message: 'رفع النسخة إلى Google Drive...',
          progress: 0.6,
        );
        if (state.autoSettings.backupFormat == BackupFormat.json) {
          final backupData = await _backupService.exportDatabaseToJson();
          await _backupService.uploadBackup(backupData);
        } else {
          final sqlitePath = localBackupPath ?? (tempSqlitePath = await SqliteBackupRestore.backupDatabase());
          final sqliteFile = File(sqlitePath);
          if (!await sqliteFile.exists()) {
            throw Exception('تعذر العثور على ملف النسخة الاحتياطية SQLite لرفعه');
          }
          final bytes = await sqliteFile.readAsBytes();
          final timestamp = DateTime.now();
          final fileName = '${GoogleDriveBackupService.fullBackupPrefix}${timestamp.toIso8601String().split('T')[0]}_${timestamp.millisecondsSinceEpoch}.sqlite';
          final appProps = <String, String>{
            'format': BackupFormat.sqlite.name,
            'backup_type': 'manual',
          };
          await _backupService.uploadBackupWithName(fileName, bytes, appProperties: appProps);
        }
      }

      // تحديث جميع القوائم
      state = state.copyWith(
        message: 'تحديث القوائم...',
        progress: 0.9,
      );

      await refreshLocalBackups();
      await refreshBackupsList();

      final lastLocalBackup = await _localBackupService.getLastLocalBackupTime();
      final lastDriveBackup = await _backupService.getLastBackupTime();

      state = state.copyWith(
        status: BackupStatus.success,
        message: 'تم إنشاء النسخة الاحتياطية الشاملة بنجاح',
        progress: 1.0,
        lastLocalBackupTime: lastLocalBackup,
        lastBackupTime: lastDriveBackup,
      );
    } catch (e) {
      debugPrint('❌ خطأ في إنشاء النسخة الاحتياطية الشاملة: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في إنشاء النسخة الاحتياطية الشاملة: ${e.toString()}',
        progress: null,
      );
    } finally {
      if (tempSqlitePath != null) {
        try {
          final tempFile = File(tempSqlitePath);
          if (await tempFile.exists()) {
            await tempFile.delete();
            debugPrint('🗑️ تم حذف ملف النسخة المؤقت: $tempSqlitePath');
          }
        } catch (cleanupError) {
          debugPrint('⚠️ فشل حذف ملف النسخة المؤقت: $cleanupError');
        }
      }
    }
  }

  // وظائف إدارة الملفات

  /// تصدير البيانات إلى CSV
  Future<void> exportToCSV() async {
    try {
      state = state.copyWith(
        status: BackupStatus.uploading,
        message: 'تصدير البيانات إلى CSV...',
        progress: 0.0,
      );

      final csvPath = await _fileService.exportToCSV();

      state = state.copyWith(
        status: BackupStatus.success,
        message: 'تم تصدير البيانات إلى CSV: $csvPath',
        progress: 1.0,
      );

      debugPrint('📊 CSV exported to $csvPath');
    } catch (e) {
      debugPrint('❌ خطأ في تصدير البيانات إلى CSV: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في تصدير البيانات إلى CSV: ${e.toString()}',
        progress: null,
      );
    }
  }

  /// إنشاء تقرير شامل قابل للقراءة
  Future<void> createReadableReport() async {
    try {
      state = state.copyWith(
        status: BackupStatus.uploading,
        message: 'إنشاء تقرير شامل...',
        progress: 0.0,
      );

      final reportPath = await _fileService.exportReadableReport();

      state = state.copyWith(
        status: BackupStatus.success,
        message: 'تم إنشاء التقرير الشامل في: $reportPath',
        progress: 1.0,
      );

      debugPrint('📝 Readable report generated at $reportPath');
    } catch (e) {
      debugPrint('❌ خطأ في إنشاء التقرير الشامل: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في إنشاء التقرير الشامل: ${e.toString()}',
        progress: null,
      );
    }
  }

  /// مشاركة نسخ متعددة
  Future<void> shareMultipleBackups(List<String> filePaths) async {
    try {
      await _fileService.shareMultipleFiles(filePaths);
      state = state.copyWith(
        status: BackupStatus.success,
        message: 'تم مشاركة الملفات بنجاح',
      );
    } catch (e) {
      debugPrint('❌ خطأ في مشاركة الملفات: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في مشاركة الملفات: ${e.toString()}',
      );
    }
  }

  /// دمج نسخ متعددة
  Future<void> mergeBackups(List<String> backupPaths, String mergedFileName) async {
    try {
      state = state.copyWith(
        status: BackupStatus.uploading,
        message: 'دمج النسخ الاحتياطية...',
        progress: 0.0,
      );

      final mergedPath = await _fileService.mergeBackupFiles(backupPaths, mergedFileName);
      
      // تحديث قائمة النسخ المحلية
      await refreshLocalBackups();

      state = state.copyWith(
        status: BackupStatus.success,
        message: 'تم دمج النسخ الاحتياطية في: $mergedPath',
        progress: 1.0,
      );

      debugPrint('🗂️ Backup files merged into $mergedPath');
    } catch (e) {
      debugPrint('❌ خطأ في دمج النسخ الاحتياطية: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في دمج النسخ الاحتياطية: ${e.toString()}',
        progress: null,
      );
    }
  }

  /// تحليل وإحصائيات الملفات
  Future<void> analyzeBackupFiles() async {
    try {
      final analysis = await _fileService.analyzeBackupFiles();
      debugPrint('📊 تحليل النسخ الاحتياطية: $analysis');
      
      state = state.copyWith(
        status: BackupStatus.success,
        message: 'تم تحليل الملفات - راجع السجلات للتفاصيل',
      );
    } catch (e) {
      debugPrint('❌ خطأ في تحليل الملفات: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في تحليل الملفات: ${e.toString()}',
      );
    }
  }

  /// تنظيف الملفات المؤقتة
  Future<void> cleanupTempFiles() async {
    try {
      await _fileService.cleanupTempFiles();
      state = state.copyWith(
        status: BackupStatus.success,
        message: 'تم تنظيف الملفات المؤقتة',
      );
    } catch (e) {
      debugPrint('❌ خطأ في تنظيف الملفات المؤقتة: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في تنظيف الملفات المؤقتة: ${e.toString()}',
      );
    }
  }
}

// Provider للخدمة مع الحفاظ على حالة واحدة (Singleton)
final googleDriveBackupServiceProvider = Provider<GoogleDriveBackupService>((ref) {
  ref.keepAlive(); // المحافظة على الخدمة في الذاكرة
  return GoogleDriveBackupService();
});

final localBackupServiceProvider = Provider<LocalBackupService>((ref) {
  return LocalBackupService();
});

final fileManagementServiceProvider = Provider<FileManagementService>((ref) {
  return FileManagementService();
});

// Provider للحالة
final backupStatusProvider = StateNotifierProvider<BackupStatusNotifier, BackupState>((ref) {
  final driveService = ref.watch(googleDriveBackupServiceProvider);
  final localService = ref.watch(localBackupServiceProvider);
  final fileService = ref.watch(fileManagementServiceProvider);
  return BackupStatusNotifier(driveService, localService, fileService);
});

// Provider للنسخ المتاحة (Google Drive)
final availableBackupsProvider = Provider<List<DriveBackupFile>>((ref) {
  final state = ref.watch(backupStatusProvider);
  return state.availableBackups;
});

// Provider للنسخ المحلية
final localBackupsProvider = Provider<List<LocalBackupFile>>((ref) {
  final state = ref.watch(backupStatusProvider);
  return state.localBackups;
});

// Provider لحالة تسجيل الدخول
final googleDriveSignInStatusProvider = Provider<bool>((ref) {
  final state = ref.watch(backupStatusProvider);
  return state.isSignedIn;
});

// Provider لحالة أذونات التخزين المحلي
final storagePermissionProvider = Provider<bool>((ref) {
  final state = ref.watch(backupStatusProvider);
  return state.hasStoragePermission;
});

// Provider لآخر وقت نسخ احتياطي (Google Drive)
final lastBackupTimeProvider = Provider<DateTime?>((ref) {
  final state = ref.watch(backupStatusProvider);
  return state.lastBackupTime;
});

// Provider لآخر وقت نسخ احتياطي محلي
final lastLocalBackupTimeProvider = Provider<DateTime?>((ref) {
  final state = ref.watch(backupStatusProvider);
  return state.lastLocalBackupTime;
});

// Provider لحجم قاعدة البيانات
final databaseSizeProvider = Provider<int?>((ref) {
  final state = ref.watch(backupStatusProvider);
  return state.databaseSizeBytes;
});

// Provider لمعلومات مجلد النسخ المحلي
final backupFolderInfoProvider = Provider<Map<String, dynamic>?>((ref) {
  final state = ref.watch(backupStatusProvider);
  return state.backupFolderInfo;
});

// Provider لإعدادات النسخ التلقائي
final autoBackupSettingsProvider = Provider<AutoBackupSettings>((ref) {
  final state = ref.watch(backupStatusProvider);
  return state.autoSettings;
});

// Providers جديدة للإحصائيات والتحليل
final totalBackupsCountProvider = Provider<int>((ref) {
  final driveBackups = ref.watch(availableBackupsProvider);
  final localBackups = ref.watch(localBackupsProvider);
  return driveBackups.length + localBackups.length;
});

final hasAnyBackupsProvider = Provider<bool>((ref) {
  return ref.watch(totalBackupsCountProvider) > 0;
});

final backupStatusSummaryProvider = Provider<String>((ref) {
  final state = ref.watch(backupStatusProvider);
  final driveCount = state.availableBackups.length;
  final localCount = state.localBackups.length;
  
  if (driveCount == 0 && localCount == 0) {
    return 'لا توجد نسخ احتياطية';
  } else if (driveCount > 0 && localCount > 0) {
    return '$driveCount سحابي • $localCount محلي';
  } else if (driveCount > 0) {
    return '$driveCount نسخة سحابية';
  } else {
    return '$localCount نسخة محلية';
  }
});

final googleDriveLoggerProvider = ChangeNotifierProvider<GoogleDriveLogger>((ref) {
  final logger = GoogleDriveLogger();
  ref.onDispose(() => logger.dispose());
  return logger;
});

final googleDriveLogStatsProvider = Provider<Map<String, int>>((ref) {
  final logger = ref.watch(googleDriveLoggerProvider);
  return logger.getStatistics();
});

final googleDriveLogsProvider = Provider<List<LogEntry>>((ref) {
  final logger = ref.watch(googleDriveLoggerProvider);
  return logger.getLogs();
});
