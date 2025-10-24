import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/google_drive_backup_service.dart';
import '../services/local_backup_service.dart';
import '../services/file_management_service.dart';
import '../services/auto_backup_task.dart';
import '../services/backup_sync_service.dart';

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

  const AutoBackupSettings({
    this.isEnabled = false,
    this.frequency = 'daily',
    this.time = '02:00',
    this.weekday,
    this.day,
    this.backupType = BackupType.both,
    this.enableLocalBackup = true,
    this.enableGoogleDriveBackup = false,
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
    );
  }

  bool get isSignedIn => signedInAccount != null;
  bool get isWorking => status == BackupStatus.signIn || 
                       status == BackupStatus.uploading ||
                       status == BackupStatus.downloading ||
                       status == BackupStatus.restoring ||
                       status == BackupStatus.checkingPermissions ||
                       status == BackupStatus.importingFile;
}

// Notifier للتحكم في حالة النسخ الاحتياطي
class BackupStatusNotifier extends StateNotifier<BackupState> {
  BackupStatusNotifier(this._backupService, this._localBackupService, this._fileService, this._syncService) : super(BackupState()) {
    _initialize();
  }

  final GoogleDriveBackupService _backupService;
  final LocalBackupService _localBackupService;
  final FileManagementService _fileService;
  final BackupSyncService _syncService;

  Future<void> _initialize() async {
    try {
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
      
      // التحقق من تسجيل الدخول في Google Drive
      GoogleSignInAccount? account;
      List<DriveBackupFile> driveBackups = [];
      if (_backupService.isSignedIn) {
        account = _backupService.currentUser;
        // جلب قائمة النسخ المتاحة في Google Drive
        try {
          driveBackups = await _backupService.listBackupFiles();
        } catch (e) {
          debugPrint('⚠️ خطأ في جلب نسخ Google Drive: $e');
        }
      } else {
        await _backupService.trySilentSignIn();
      }

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
          isEnabled: autoEnabled,
          frequency: frequency,
          time: time,
          enableLocalBackup: enableLocal,
          enableGoogleDriveBackup: autoEnabled,
          backupType: enableLocal && autoEnabled ? BackupType.both :
                     enableLocal ? BackupType.local : BackupType.googleDrive,
        ),
      );
    } catch (e) {
      debugPrint('❌ خطأ في تهيئة BackupStatusNotifier: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في التهيئة: ${e.toString()}',
      );
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
        // جلب قائمة النسخ المتاحة
        final backups = await _backupService.listBackupFiles();
        
        state = state.copyWith(
          status: BackupStatus.success,
          message: 'تم تسجيل الدخول بنجاح',
          signedInAccount: account,
          availableBackups: backups,
        );
        await _syncService.syncFromDriveIfNeeded();
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
        message: 'تصدير البيانات...',
        progress: 0.0,
      );

      // تصدير البيانات
      final backupData = await _backupService.exportDatabaseToJson();
      
      state = state.copyWith(
        message: 'رفع النسخة الاحتياطية...',
        progress: 0.5,
      );

      // رفع النسخة
      final fileId = await _backupService.uploadBackup(backupData);
      
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
      state = state.copyWith(
        status: BackupStatus.downloading,
        message: 'تنزيل النسخة الاحتياطية...',
        progress: 0.0,
      );

      // تنزيل النسخة الاحتياطية
      final backupData = await _backupService.downloadBackup(fileId);
      
      state = state.copyWith(
        status: BackupStatus.restoring,
        message: 'استعادة البيانات...',
        progress: 0.5,
      );

      // استعادة البيانات
      await _backupService.restoreFromBackup(backupData);

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
      await _backupService.setAutoBackupEnabled(settings.isEnabled);
      
      if (settings.isEnabled) {
        await _backupService.setAutoBackupFrequency(settings.frequency);
        await _backupService.setAutoBackupTime(settings.time);
        
        // جدولة المهمة حسب التكرار
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
        }
      } else {
        await AutoBackupTask.cancelScheduled();
      }

      state = state.copyWith(
        autoSettings: settings,
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
    try {
      state = state.copyWith(
        status: BackupStatus.uploading,
        message: 'إنشاء نسخة احتياطية محلية...',
        progress: 0.0,
      );

      final filePath = await _localBackupService.createLocalBackup();
      
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
        message: 'تم إنشاء النسخة الاحتياطية المحلية بنجاح',
        progress: 1.0,
        localBackups: localBackups,
        lastLocalBackupTime: lastLocalBackup,
        backupFolderInfo: folderInfo,
      );
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

      final filePath = await _localBackupService.importBackupFromFile();
      
      state = state.copyWith(
        message: 'تحديث قائمة النسخ...',
        progress: 0.8,
      );

      // تحديث قائمة النسخ المحلية
      final localBackups = await _localBackupService.listLocalBackups();
      final folderInfo = await _localBackupService.getBackupFolderInfo();

      state = state.copyWith(
        status: BackupStatus.success,
        message: 'تم استيراد النسخة الاحتياطية بنجاح',
        progress: 1.0,
        localBackups: localBackups,
        backupFolderInfo: folderInfo,
      );
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
        message: 'تم تصدير النسخة الاحتياطية إلى: Downloads',
        progress: 1.0,
      );
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
    try {
      state = state.copyWith(
        status: BackupStatus.uploading,
        message: 'إنشاء نسخة احتياطية شاملة...',
        progress: 0.0,
      );

      // إنشاء النسخة المحلية أولاً
      if (state.hasStoragePermission) {
        state = state.copyWith(
          message: 'إنشاء النسخة المحلية...',
          progress: 0.2,
        );
        await _localBackupService.createLocalBackup();
      }

      // ثم النسخة السحابية إذا كان المستخدم مسجل الدخول
      if (state.isSignedIn) {
        state = state.copyWith(
          message: 'رفع النسخة إلى Google Drive...',
          progress: 0.6,
        );
        final backupData = await _backupService.exportDatabaseToJson();
        await _backupService.uploadBackup(backupData);
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
        message: 'تم تصدير البيانات إلى CSV بنجاح',
        progress: 1.0,
      );
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
        message: 'تم إنشاء التقرير الشامل بنجاح',
        progress: 1.0,
      );
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
        message: 'تم دمج النسخ الاحتياطية بنجاح',
        progress: 1.0,
      );
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

// Provider للخدمة
final googleDriveBackupServiceProvider = Provider<GoogleDriveBackupService>((ref) {
  return GoogleDriveBackupService();
});

final backupSyncServiceProvider = Provider<BackupSyncService>((ref) {
  final driveService = ref.watch(googleDriveBackupServiceProvider);
  return BackupSyncService(driveService);
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
  final syncService = ref.watch(backupSyncServiceProvider);
  return BackupStatusNotifier(driveService, localService, fileService, syncService);
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