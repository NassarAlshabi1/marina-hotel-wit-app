// lib/providers/backup_provider.dart
//
// ✅ (2026-09-17) إعادة كتابة — نسخ احتياطي محلي فقط.
//
// بطلب المستخدم («مزامنة appwrite و sync google drive لا احتاجها نهائياً»)
// أُزيل نظام Google Drive كاملاً: تسجيل الدخول، النسخ السحابي، قائمة نسخ
// Drive، وحالة requiresDriveLogin التي كانت بوابة شاشة دخول Drive.
//
// ما بقي (وكل وظيفته محفوظة كما كانت):
// - النسخ الاحتياطي المحلي (JSON / SQLite) واستعادته والتحقق من تجزئته
// - النسخة الاحتياطية الشاملة (محلية) + الإصلاح التلقائي بعد الاستعادة
// - تصدير CSV / التقارير / المشاركة / الدمج / التنظيف
// - الرفع الصريح إلى Cloudflare بعد الاستعادة (syncToCloud) — عبر
//   AppwriteSyncManager (الاسم التاريخي لـ CloudflareSyncManager)
// - إعدادات النسخ المحلي التلقائي + جدولة إنذار Android اليومي

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/alarm_backup.dart';
import '../services/appwrite_sync_manager.dart';
import '../services/backup_data_service.dart';
import '../services/file_management_service.dart';
import '../services/local_backup_service.dart'
    show LocalBackupService, LocalBackupFile;
import '../services/local_db.dart';
import '../services/restore_fix_service.dart';
import '../services/sqlite_backup_restore.dart';
import '../utils/debug_log.dart';
import 'appwrite_providers.dart';

// حالة النسخ الاحتياطي
enum BackupStatus {
  idle,
  uploading,
  downloading,
  restoring,
  success,
  error,
  checkingPermissions,
  importingFile,
}

// حالة النسخ التلقائي (محلي فقط)
class AutoBackupSettings {
  const AutoBackupSettings({
    this.isEnabled = true,
    this.frequency = 'daily',
    this.time = '21:00',
    this.weekday,
    this.day,
    this.enableLocalBackup = true,
    // ✅ إصلاح (2026-06-28): افتراضي SQLite .db بدلاً من JSON —
    // المستخدم يفضّل النسخة السريعة الخام (.db) على JSON.
    this.backupFormat = BackupFormat.sqlite,
  });
  final bool isEnabled;
  final String frequency; // daily, weekly, monthly
  final String time; // HH:mm format
  final int? weekday; // 1-7 للنسخ الأسبوعي
  final int? day; // 1-31 للنسخ الشهري
  final bool enableLocalBackup; // تفعيل النسخ المحلي
  final BackupFormat backupFormat;

  AutoBackupSettings copyWith({
    bool? isEnabled,
    String? frequency,
    String? time,
    int? weekday,
    int? day,
    bool? enableLocalBackup,
    BackupFormat? backupFormat,
  }) {
    return AutoBackupSettings(
      isEnabled: isEnabled ?? this.isEnabled,
      frequency: frequency ?? this.frequency,
      time: time ?? this.time,
      weekday: weekday ?? this.weekday,
      day: day ?? this.day,
      enableLocalBackup: enableLocalBackup ?? this.enableLocalBackup,
      backupFormat: backupFormat ?? this.backupFormat,
    );
  }
}

// حالة عملية النسخ الاحتياطي
class BackupState {
  BackupState({
    this.status = BackupStatus.idle,
    this.message,
    this.progress,
    this.lastBackupTime,
    this.localBackups = const [],
    this.lastLocalBackupTime,
    this.autoSettings = const AutoBackupSettings(),
    this.databaseSizeBytes,
    this.hasStoragePermission = false,
    this.backupFolderInfo,
    this.lastSqliteBackupPath,
  });
  final BackupStatus status;
  final String? message;
  final double? progress;
  final DateTime? lastBackupTime;
  final List<LocalBackupFile> localBackups;
  final DateTime? lastLocalBackupTime;
  final AutoBackupSettings autoSettings;
  final int? databaseSizeBytes;
  final bool hasStoragePermission;
  final Map<String, dynamic>? backupFolderInfo;
  final String? lastSqliteBackupPath;

  BackupState copyWith({
    BackupStatus? status,
    String? message,
    double? progress,
    DateTime? lastBackupTime,
    List<LocalBackupFile>? localBackups,
    DateTime? lastLocalBackupTime,
    AutoBackupSettings? autoSettings,
    int? databaseSizeBytes,
    bool? hasStoragePermission,
    Map<String, dynamic>? backupFolderInfo,
    String? lastSqliteBackupPath,
  }) {
    return BackupState(
      status: status ?? this.status,
      message: message ?? this.message,
      progress: progress ?? this.progress,
      lastBackupTime: lastBackupTime ?? this.lastBackupTime,
      localBackups: localBackups ?? this.localBackups,
      lastLocalBackupTime: lastLocalBackupTime ?? this.lastLocalBackupTime,
      autoSettings: autoSettings ?? this.autoSettings,
      databaseSizeBytes: databaseSizeBytes ?? this.databaseSizeBytes,
      hasStoragePermission: hasStoragePermission ?? this.hasStoragePermission,
      backupFolderInfo: backupFolderInfo ?? this.backupFolderInfo,
      lastSqliteBackupPath: lastSqliteBackupPath ?? this.lastSqliteBackupPath,
    );
  }

  bool get isWorking =>
      status == BackupStatus.uploading ||
      status == BackupStatus.downloading ||
      status == BackupStatus.restoring ||
      status == BackupStatus.checkingPermissions ||
      status == BackupStatus.importingFile;
}

// Notifier للتحكم في حالة النسخ الاحتياطي
class BackupStatusNotifier extends StateNotifier<BackupState> {
  BackupStatusNotifier(
    this._localBackupService,
    this._fileService,
    this._appwriteSyncManager,
  ) : super(BackupState()) {
    unawaited(_initialize());
  }

  final LocalBackupService _localBackupService;
  final FileManagementService _fileService;
  final AppwriteSyncManager _appwriteSyncManager;
  bool _mounted = true;

  /// تحديث حالة النسخ الاحتياطي
  void setStatus(BackupStatus status, String? message) {
    if (_mounted) {
      state = state.copyWith(status: status, message: message);
    }
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // جلب آخر وقت نسخ احتياطي محلي
      final lastLocalBackup = await _localBackupService
          .getLastLocalBackupTime();

      // جلب حجم قاعدة البيانات
      final dbSize = await BackupDataService.instance.estimateDatabaseSize();

      // التحقق من أذونات التخزين المحلي
      final hasPermission = await _localBackupService.checkPermissions();

      // جلب معلومات مجلد النسخ المحلي
      Map<String, dynamic>? folderInfo;
      List<LocalBackupFile> localBackups = [];
      if (hasPermission) {
        folderInfo = await _localBackupService.getBackupFolderInfo();
        localBackups = await _localBackupService.listLocalBackups();
      }

      // إعدادات النسخ المحلي التلقائي + النسخ المجدول بالإنذار اليومي
      final enableLocal = await _localBackupService.isAutoLocalBackupEnabled();
      final localFreq = await _localBackupService.getAutoLocalBackupFrequency();
      final scheduledEnabled =
          prefs.getBool('scheduled_backup_enabled') ?? true;
      final scheduledTime = prefs.getString('auto_backup_time') ?? '21:00';

      state = state.copyWith(
        lastLocalBackupTime: lastLocalBackup,
        databaseSizeBytes: dbSize,
        hasStoragePermission: hasPermission,
        backupFolderInfo: folderInfo,
        localBackups: localBackups,
        autoSettings: AutoBackupSettings(
          isEnabled: enableLocal || scheduledEnabled,
          frequency: localFreq,
          time: scheduledTime,
          enableLocalBackup: enableLocal,
        ),
      );
    } catch (e) {
      dlog(() => '❌ خطأ في تهيئة BackupStatusNotifier: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في التهيئة: $e',
      );
    }
  }

  Future<void> updateDatabaseSize() async {
    try {
      final size = await BackupDataService.instance.estimateDatabaseSize();
      state = state.copyWith(databaseSizeBytes: size);
    } catch (e) {
      dlog(() => '❌ خطأ في تحديث حجم قاعدة البيانات: $e');
    }
  }

  /// تحديث إعدادات النسخ التلقائي (محلي) + إعادة جدولة الإنذار اليومي
  Future<void> updateAutoBackupSettings(AutoBackupSettings settings) async {
    try {
      final enableLocal = settings.isEnabled && settings.enableLocalBackup;

      await _localBackupService.setAutoLocalBackupEnabled(enableLocal);
      await _localBackupService.setAutoLocalBackupFrequency(settings.frequency);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auto_backup_time', settings.time);
      await prefs.setBool('scheduled_backup_enabled', enableLocal);

      // إعادة جدولة إنذار النسخ اليومي (نسخة محلية عند الوقت المحدد)
      if (enableLocal) {
        final parts = settings.time.split(':');
        final hour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 21;
        final minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
        await AlarmBackup.rescheduleDaily(hour, minute);
      } else {
        await AlarmBackup.cancelAlarm();
      }

      state = state.copyWith(
        autoSettings: settings.copyWith(isEnabled: enableLocal),
        status: BackupStatus.success,
        message: 'تم تحديث إعدادات النسخ التلقائي',
      );
    } catch (e) {
      dlog(() => '❌ خطأ في تحديث إعدادات النسخ التلقائي: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في تحديث إعدادات النسخ التلقائي: $e',
      );
    }
  }

  /// مسح رسالة الحالة
  void clearMessage() {
    if (!_mounted) {
      return;
    }
    state = state.copyWith(status: BackupStatus.idle);
  }

  @override
  void dispose() {
    _mounted = false;
    super.dispose();
  }

  // ─── وظائف النسخ الاحتياطي المحلي ───────────────────────────────

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
      dlog(() => '❌ خطأ في التحقق من أذونات التخزين: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في التحقق من الأذونات: $e',
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

      state = state.copyWith(message: 'تحديث قائمة النسخ...', progress: 0.8);

      // تحديث قائمة النسخ المحلية
      final localBackups = await _localBackupService.listLocalBackups();
      final lastLocalBackup = await _localBackupService
          .getLastLocalBackupTime();
      final folderInfo = await _localBackupService.getBackupFolderInfo();

      state = state.copyWith(
        status: BackupStatus.success,
        message: 'تم إنشاء النسخة الاحتياطية المحلية بنجاح في: $backupPath',
        progress: 1.0,
        localBackups: localBackups,
        lastLocalBackupTime: lastLocalBackup,
        backupFolderInfo: folderInfo,
      );

      dlog(() => '💾 Local backup saved at $backupPath');
    } catch (e) {
      dlog(() => '❌ خطأ في إنشاء النسخة الاحتياطية المحلية: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في إنشاء النسخة الاحتياطية المحلية: $e',
      );
    }
  }

  /// استعادة من نسخة احتياطية محلية
  Future<void> restoreFromLocalBackup(
    String filePath, {
    bool syncToCloud = false,
  }) async {
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
        progress: 0.5,
      );

      final fixService = RestoreFixService(DatabaseManager.instance);
      final fixReport = await fixService.runAutoFixAfterRestore();

      if (!fixReport.success) {
        dlog(() => '⚠️ فشل الإصلاح التلقائي: ${fixReport.error}');
      } else {
        dlog(
          () =>
              '✅ اكتمل الإصلاح التلقائي: ${fixReport.bookingsFixed} حجز، ${fixReport.roomsUpdated} غرفة',
        );
      }

      // مزامنة البيانات إلى السحابة إذا طُلب ذلك صراحةً فقط.
      // الاستعادة المحلية لا تكتب إلى Cloud افتراضياً لحماية بيانات Cloud الحالية.
      // ✅ فصل هندسي: عند طلبها صراحةً، ندفع مباشرة إلى Cloudflare D1
      // دون إضافة بيانات إلى outbox — هذا يفصل عملية الاستعادة عن تتبع التغييرات المحلية
      if (syncToCloud) {
        state = state.copyWith(
          message: 'رفع البيانات إلى السحابة...',
          progress: 0.7,
        );

        try {
          final prefs = await SharedPreferences.getInstance();
          final cloudflareEnabled =
              prefs.getBool('appwrite_sync_enabled') ?? true;
          if (cloudflareEnabled) {
            state = state.copyWith(
              message: 'رفع البيانات إلى Cloudflare...',
              progress: 0.8,
            );
            try {
              await _appwriteSyncManager.pushAllLocalData();
              dlog('✅ تم رفع البيانات إلى Cloudflare');
            } catch (e) {
              dlog(() => '⚠️ فشل رفع البيانات إلى Cloudflare: $e');
            }
          }
        } catch (e) {
          dlog(() => '⚠️ خطأ في مزامنة البيانات إلى السحابة: $e');
          // نستمر بالعملية حتى لو فشلت المزامنة
        }
      }

      state = state.copyWith(
        status: BackupStatus.success,
        message: syncToCloud
            ? 'تم استعادة البيانات ورفعها إلى السحابة بنجاح'
            : 'تم استعادة البيانات من النسخة المحلية بنجاح',
        progress: 1.0,
      );
    } catch (e) {
      dlog(() => '❌ خطأ في استعادة البيانات من النسخة المحلية: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في استعادة البيانات: $e',
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
      );

      final path = await SqliteBackupRestore.backupDatabase();

      state = state.copyWith(
        status: BackupStatus.success,
        message: 'تم حفظ نسخة قاعدة البيانات في: $path',
        progress: 1.0,
        lastSqliteBackupPath: path,
      );
    } catch (e) {
      dlog(() => '❌ خطأ في النسخ الاحتياطي لملف SQLite: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'فشل إنشاء نسخة ملف قاعدة البيانات: $e',
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
        dlog(() => '⚠️ فشل الإصلاح التلقائي: ${fixReport.error}');
      } else {
        dlog(
          () =>
              '✅ اكتمل الإصلاح التلقائي: ${fixReport.bookingsFixed} حجز، ${fixReport.roomsUpdated} غرفة',
        );
      }

      state = state.copyWith(
        status: BackupStatus.success,
        message: 'تمت استعادة قاعدة البيانات بنجاح',
        progress: 1.0,
      );
    } catch (e) {
      dlog(() => '❌ خطأ في استعادة ملف SQLite: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'فشل استعادة قاعدة البيانات: $e',
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
      dlog(() => '❌ خطأ في مشاركة النسخة الاحتياطية: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في مشاركة النسخة الاحتياطية: $e',
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

      state = state.copyWith(message: 'تحديث قائمة النسخ...', progress: 0.8);

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

      dlog(() => '📥 Imported backup from $importedPath');
    } catch (e) {
      dlog(() => '❌ خطأ في استيراد النسخة الاحتياطية: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في استيراد النسخة الاحتياطية: $e',
      );
    }
  }

  /// استيراد نسخة احتياطية ثم استعادتها مباشرة
  Future<void> importAndRestoreBackup({bool syncToCloud = false}) async {
    try {
      state = state.copyWith(
        status: BackupStatus.importingFile,
        message: 'اختيار ملف النسخة الاحتياطية...',
        progress: 0.0,
      );

      final importedPath = await _localBackupService.importBackupFromFile();

      state = state.copyWith(
        status: BackupStatus.restoring,
        message: 'استعادة البيانات من النسخة المستوردة...',
        progress: 0.3,
      );

      await restoreFromLocalBackup(importedPath, syncToCloud: syncToCloud);
    } catch (e) {
      dlog(() => '❌ خطأ في استيراد واستعادة النسخة: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في الاستيراد والاستعادة: $e',
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

      dlog(() => '📤 Exported backup to $exportPath');
    } catch (e) {
      dlog(() => '❌ خطأ في تصدير النسخة الاحتياطية: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في تصدير النسخة الاحتياطية: $e',
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
      dlog(() => '❌ خطأ في حذف النسخة الاحتياطية: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في حذف النسخة الاحتياطية: $e',
      );
    }
  }

  /// تحديث قائمة النسخ المحلية
  Future<void> refreshLocalBackups() async {
    if (!state.hasStoragePermission) {
      return;
    }

    try {
      final localBackups = await _localBackupService.listLocalBackups();
      final folderInfo = await _localBackupService.getBackupFolderInfo();

      state = state.copyWith(
        localBackups: localBackups,
        backupFolderInfo: folderInfo,
      );
    } catch (e) {
      dlog(() => '❌ خطأ في تحديث قائمة النسخ المحلية: $e');
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
      dlog(() => '❌ خطأ في تنظيف النسخ القديمة: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في تنظيف النسخ القديمة: $e',
      );
    }
  }

  /// إنشاء نسخة احتياطية شاملة (محلية)
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
          progress: 0.4,
        );
        localBackupPath = await _localBackupService.createLocalBackup(
          format: state.autoSettings.backupFormat,
        );
      } else {
        // بلا أذونات تخزين: نسخة SQLite مؤقتة على الأقل (تُنظف لاحقاً)
        tempSqlitePath = await SqliteBackupRestore.backupDatabase();
        localBackupPath = tempSqlitePath;
      }

      // تحديث جميع القوائم
      state = state.copyWith(message: 'تحديث القوائم...', progress: 0.9);

      await refreshLocalBackups();

      final lastLocalBackup = await _localBackupService
          .getLastLocalBackupTime();

      state = state.copyWith(
        status: BackupStatus.success,
        message: 'تم إنشاء النسخة الاحتياطية الشاملة بنجاح',
        progress: 1.0,
        lastLocalBackupTime: lastLocalBackup,
      );
      dlog(() => '💾 Comprehensive (local) backup at $localBackupPath');
    } catch (e) {
      dlog(() => '❌ خطأ في إنشاء النسخة الاحتياطية الشاملة: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في إنشاء النسخة الاحتياطية الشاملة: $e',
      );
    } finally {
      if (tempSqlitePath != null) {
        try {
          final tempFile = File(tempSqlitePath);
          if (tempFile.existsSync()) {
            await tempFile.delete();
            dlog(() => '🗑️ تم حذف ملف النسخة المؤقت: $tempSqlitePath');
          }
        } catch (cleanupError) {
          dlog(() => '⚠️ فشل حذف ملف النسخة المؤقت: $cleanupError');
        }
      }
    }
  }

  // ─── وظائف إدارة الملفات ────────────────────────────────────────

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

      dlog(() => '📊 CSV exported to $csvPath');
    } catch (e) {
      dlog(() => '❌ خطأ في تصدير البيانات إلى CSV: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في تصدير البيانات إلى CSV: $e',
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

      dlog(() => '📝 Readable report generated at $reportPath');
    } catch (e) {
      dlog(() => '❌ خطأ في إنشاء التقرير الشامل: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في إنشاء التقرير الشامل: $e',
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
      dlog(() => '❌ خطأ في مشاركة الملفات: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في مشاركة الملفات: $e',
      );
    }
  }

  /// دمج نسخ متعددة
  Future<void> mergeBackups(
    List<String> backupPaths,
    String mergedFileName,
  ) async {
    try {
      state = state.copyWith(
        status: BackupStatus.uploading,
        message: 'دمج النسخ الاحتياطية...',
        progress: 0.0,
      );

      final mergedPath = await _fileService.mergeBackupFiles(
        backupPaths,
        mergedFileName,
      );

      // تحديث قائمة النسخ المحلية
      await refreshLocalBackups();

      state = state.copyWith(
        status: BackupStatus.success,
        message: 'تم دمج النسخ الاحتياطية في: $mergedPath',
        progress: 1.0,
      );

      dlog(() => '🗂️ Backup files merged into $mergedPath');
    } catch (e) {
      dlog(() => '❌ خطأ في دمج النسخ الاحتياطية: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في دمج النسخ الاحتياطية: $e',
      );
    }
  }

  /// تحليل وإحصائيات الملفات
  Future<void> analyzeBackupFiles() async {
    try {
      final analysis = await _fileService.analyzeBackupFiles();
      dlog(() => '📊 تحليل النسخ الاحتياطية: $analysis');

      state = state.copyWith(
        status: BackupStatus.success,
        message: 'تم تحليل الملفات - راجع السجلات للتفاصيل',
      );
    } catch (e) {
      dlog(() => '❌ خطأ في تحليل الملفات: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في تحليل الملفات: $e',
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
      dlog(() => '❌ خطأ في تنظيف الملفات المؤقتة: $e');
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'خطأ في تنظيف الملفات المؤقتة: $e',
      );
    }
  }
}

// ─── Providers ────────────────────────────────────────────────────

final localBackupServiceProvider = Provider<LocalBackupService>((ref) {
  return LocalBackupService();
});

final fileManagementServiceProvider = Provider<FileManagementService>((ref) {
  return FileManagementService();
});

// Provider للحالة
final backupStatusProvider =
    StateNotifierProvider<BackupStatusNotifier, BackupState>((ref) {
      final localService = ref.watch(localBackupServiceProvider);
      final fileService = ref.watch(fileManagementServiceProvider);
      final appwriteSync = ref.watch(appwriteSyncManagerProvider);
      return BackupStatusNotifier(localService, fileService, appwriteSync);
    });

// Provider للنسخ المحلية
final localBackupsProvider = Provider<List<LocalBackupFile>>((ref) {
  final state = ref.watch(backupStatusProvider);
  return state.localBackups;
});

// Provider لحالة أذونات التخزين المحلي
final storagePermissionProvider = Provider<bool>((ref) {
  final state = ref.watch(backupStatusProvider);
  return state.hasStoragePermission;
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

// Provider للإحصائيات والتحليل
final totalBackupsCountProvider = Provider<int>((ref) {
  final localBackups = ref.watch(localBackupsProvider);
  return localBackups.length;
});

final hasAnyBackupsProvider = Provider<bool>((ref) {
  return ref.watch(totalBackupsCountProvider) > 0;
});

final backupStatusSummaryProvider = Provider<String>((ref) {
  final state = ref.watch(backupStatusProvider);
  final localCount = state.localBackups.length;

  if (localCount == 0) {
    return 'لا توجد نسخ احتياطية';
  }
  return '$localCount نسخة محلية';
});
