import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/debug_log.dart';
import '../utils/hotel_time_engine.dart';
import 'appwrite_service.dart';
import 'appwrite_sync_manager.dart';
import 'booking_derived_fields_service.dart';
import 'google_drive_backup_service.dart';
import 'google_drive_delta_sync.dart';
import 'local_db.dart';
import 'smart_sync_manager.dart';

/// مدير النسخ الاحتياطي التلقائي الذكي
/// يراقب التغييرات في قاعدة البيانات ويقوم بعمل نسخ احتياطية تلقائية
enum BackupMode { fullBackup, deltaSync, both }

class AutoBackupManager {
  AutoBackupManager._();
  static const String _lastAutoBackupKey = 'last_auto_backup_timestamp';
  static const String _autoBackupEnabledKey = 'auto_backup_enabled';
  static const String _maxBackupCountKey = 'max_backup_count';
  static const String _backupRetentionDaysKey = 'backup_retention_days';
  static const String _instantSyncEnabledKey = 'instant_sync_enabled';
  static const String _deltaSyncEnabledKey = 'delta_sync_enabled';
  static const String _backupModeKey = 'backup_mode';
  static const String _googleDriveDeltaSyncEnabledKey = 'google_drive_delta_sync_enabled';

  static AutoBackupManager? _instance;
  // ignore: prefer_constructors_over_static_methods
  static AutoBackupManager get instance => _instance ??= AutoBackupManager._();

  GoogleDriveBackupService? _backupService;
  GoogleDriveDeltaSync? _googleDriveDeltaSync;
  AppwriteService? _appwriteService;
  AppDatabase? _database;
  Timer? _debounceTimer;
  Timer? _deltaSyncDebounceTimer;
  Timer? _deltaSyncTimer;
  Timer? _cleanupTimer;
  bool _isBackingUp = false;
  bool _isDeltaSyncing = false;
  int _pendingChanges = 0;
  int _batchNesting = 0; // ✅ عدد الدُفعات المتداخلة (batchStart/batchEnd)
  bool _batchDirty = false; // ✅ هل حدث تغيير أثناء الـ batch؟
  String? _deviceId;
  BackupMode _currentMode = BackupMode.deltaSync;
  String? _lastRenewedHotelDay;

  /// مدة انتظار قبل النسخ التلقائي (بالثواني) - قللناها للاستجابة السريعة
  static const int _debounceSeconds = 5;

  /// مدة انتظار قبل المزامنة الفورية (بالملي ثانية)
  static const int _instantSyncDebounceMilliseconds = 500;

  /// عدد النسخ الاحتياطية الافتراضي المراد الاحتفاظ به
  static const int _defaultMaxBackups = 10;

  /// عدد أيام الاحتفاظ بالنسخ الاحتياطية
  static const int _defaultRetentionDays = 14;

  /// تهيئة المدير مع خدمة النسخ الاحتياطي
  Future<void> initialize(
    GoogleDriveBackupService backupService, {
    AppwriteService? appwriteService,
    AppDatabase? database,
  }) async {
    _backupService = backupService;
    _appwriteService = appwriteService;
    _database = database;
    await _initializeDeviceId();
    await _loadBackupMode();
    await _schedulePeriodicCleanup();

    if (database != null) {
      _googleDriveDeltaSync = GoogleDriveDeltaSync.instance;
      await _googleDriveDeltaSync!.initialize(backupService, database);

      await _startDeltaSyncTimer();
    }

    dlog(() => '🤖 مدير النسخ التلقائي: تم التهيئة بنجاح (الوضع: ${_currentMode.name})');
  }

  Future<void> _loadBackupMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIndex = prefs.getInt(_backupModeKey);
    if (savedIndex != null && savedIndex >= 0 && savedIndex < BackupMode.values.length) {
      _currentMode = BackupMode.values[savedIndex];
    } else {
      _currentMode = BackupMode.deltaSync;
    }
  }

  Future<void> _startDeltaSyncTimer() async {
    _deltaSyncTimer?.cancel();
    final deltaSyncEnabled = await isDeltaSyncEnabled();
    if (!deltaSyncEnabled) {
      return;
    }

    _deltaSyncTimer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      await performDeltaSync();
    });
    dlog('⏰ تم جدولة المزامنة التفاضلية كل 5 دقائق');
  }

  /// تهيئة معرف الجهاز للتمييز بين الأجهزة
  Future<void> _initializeDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('device_id');

    if (_deviceId == null) {
      final deviceInfo = DeviceInfoPlugin();
      String deviceName = 'Unknown';
      String deviceModel = 'Unknown';

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceName = androidInfo.device;
        deviceModel = androidInfo.model;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceName = iosInfo.name;
        deviceModel = iosInfo.model;
      }

      _deviceId = 'marina_${deviceName}_${deviceModel}_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('device_id', _deviceId!);
      dlog(() => '🆔 تم إنشاء معرف الجهاز: $_deviceId');
    }
  }

  /// تسجيل تغيير في قاعدة البيانات لبدء عد تنازلي للنسخ التلقائي
  /// ✅ بدء دفعة — يُعلّق الـ debounce أثناء العمليات المجمّعة
  /// استخدم هذا عندما تعرف أنك ستجري عدة تغييرات متتالية
  /// مثال: استيراد نسخة احتياطية، إضافة حجز مع دفعات وليالي
  void batchStart() {
    _batchNesting++;
  }

  /// ✅ إنهاء دفعة — يُفعّل الـ debounce ويُشغّل المزامنة إذا كان هناك تغييرات
  Future<void> batchEnd() async {
    _batchNesting--;
    if (_batchNesting <= 0) {
      _batchNesting = 0;
      if (_batchDirty) {
        _batchDirty = false;
        // شغّل المزامنة بعد إنهاء الدفعة
        var syncSucceeded = true;
        if (_currentMode == BackupMode.deltaSync || _currentMode == BackupMode.both) {
          final result = await performDeltaSync();
          syncSucceeded = result['success'] == true;
        }
        if (_currentMode == BackupMode.fullBackup || _currentMode == BackupMode.both) {
          unawaited(_performAutoBackup(reason: 'تغييرات مجمّعة', changesCount: _pendingChanges));
        }
        if (syncSucceeded) {
          _pendingChanges = 0;
        }
      }
    }
  }

  /// ✅ تشغيل عملية داخل دفعة بأمان — يضمن استدعاء [batchEnd] حتى عند رمي استثناء،
  /// فيمنع بقاء `_batchNesting > 0` للأبد (الذي يُعطّل النسخ التلقائي).
  Future<R> runInBatch<R>(Future<R> Function() action) async {
    batchStart();
    try {
      return await action();
    } finally {
      await batchEnd();
    }
  }

  Future<void> onDataChange(
    String tableName,
    String operation, {
    Map<String, dynamic>? recordData,
    int batchCount = 1,
  }) async {
    if (!await _isEnabled) {
      return;
    }

    _pendingChanges += batchCount;

    // ✅ أثناء الدفعة: نسجّل التغيير فقط ولا نشغّل الـ debounce
    if (_batchNesting > 0) {
      _batchDirty = true;
      return;
    }
    dlog(() => '🔄 تغيير في $tableName ($operation) - تغييرات معلقة: $_pendingChanges');

    if (_currentMode == BackupMode.deltaSync || _currentMode == BackupMode.both) {
      _deltaSyncDebounceTimer?.cancel();
      _deltaSyncDebounceTimer = Timer(const Duration(milliseconds: _instantSyncDebounceMilliseconds), () async {
        // ملاحظة: performDeltaSync() يحمي نفسه داخلياً ضد التزامن عبر
        // _isDeltaSyncing، فلا يمكن أن تعمل مزامنتان تفاضليتان معاً.
        // ✅ لا نصفّر العدّاد إلا إذا نُفّذت المزامنة فعلاً (لم تُتخطَّ لأن
        // أخرى جارية) حتى يبقى عدد التغييرات المعلّقة دقيقاً.
        final result = await performDeltaSync();
        if (result['success'] == true) {
          _pendingChanges = 0;
        }
      });
    }

    if (_currentMode == BackupMode.fullBackup || _currentMode == BackupMode.both) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(seconds: _debounceSeconds), () {
        _performAutoBackup(reason: 'تغييرات تلقائية ($tableName: $operation)', changesCount: _pendingChanges);
        _pendingChanges = 0;
      });
    }
  }

  /// إجراء نسخة احتياطية تلقائية
  Future<void> _performAutoBackup({required String reason, int changesCount = 1}) async {
    if (_isBackingUp || _backupService == null || !_backupService!.isSignedIn) {
      dwarn(() => 'نسخ تلقائي مؤجل: نسخ جارية $_isBackingUp، مسجل دخول ${_backupService?.isSignedIn}');
      return;
    }

    try {
      _isBackingUp = true;
      dlog(() => '🚀 بدء النسخ التلقائي: $reason ($changesCount تغييرات)');

      // التحقق من آخر نسخة احتياطية لتجنب النسخ المتكررة
      final lastBackupTime = await _getLastAutoBackupTime();
      final now = DateTime.now();

      if (lastBackupTime != null && now.difference(lastBackupTime).inMinutes < 5) {
        dwarn(() => 'تم تخطي النسخ التلقائي: نسخة حديثة موجودة (${now.difference(lastBackupTime).inMinutes} دقائق)');
        return;
      }

      // إنشاء وتصدير البيانات
      final backupData = await _backupService!.exportDatabaseToJson();

      // تحديث البيانات الوصفية لتمييز النسخة التلقائية
      final existingMetadata = backupData['metadata'];
      Map<String, dynamic> metadata;
      if (existingMetadata is Map<String, dynamic>) {
        metadata = existingMetadata;
      } else if (existingMetadata is Map) {
        metadata = Map<String, dynamic>.from(existingMetadata);
        backupData['metadata'] = metadata;
      } else {
        metadata = <String, dynamic>{};
        backupData['metadata'] = metadata;
      }
      metadata['backup_type'] = 'auto';
      metadata['trigger_reason'] = reason;
      metadata['changes_count'] = changesCount;
      metadata['device_info'] = '${Platform.operatingSystem} (تلقائي)';
      metadata['device_id'] = _deviceId;
      metadata['created_by_device'] = _deviceId;

      // رفع النسخة الاحتياطية كملف تلقائي
      final fileId = await _backupService!.uploadBackup(backupData, isSync: true);

      // حفظ وقت آخر نسخة تلقائية
      await _setLastAutoBackupTime(now);

      dlog(() => '✅ نسخ تلقائي مكتمل: $fileId ($changesCount تغييرات)');

      // تنظيف النسخ القديمة في الخلفية
      unawaited(_cleanupOldBackups());

      // إشعار مدير المزامنة الذكية لمزامنة الأجهزة الأخرى
      await _notifySmartSync();
    } catch (e) {
      derr(() => 'فشل النسخ التلقائي: $e');
    } finally {
      _isBackingUp = false;
    }
  }

  /// حذف النسخ الاحتياطية القديمة حسب التاريخ والعدد
  Future<void> _cleanupOldBackups() async {
    if (_backupService == null || !_backupService!.isSignedIn) {
      return;
    }

    try {
      dlog('🧹 بدء تنظيف النسخ القديمة...');

      final backupFiles = await _backupService!.listBackupFiles();
      if (backupFiles.isEmpty) {
        return;
      }

      // ترتيب النسخ حسب التاريخ (الأحدث أولاً)
      backupFiles.sort((a, b) => b.createdTime.compareTo(a.createdTime));

      final maxBackups = await _getMaxBackupCount();
      final retentionDays = await _getRetentionDays();
      final cutoffDate = DateTime.now().subtract(Duration(days: retentionDays));

      final filesToDelete = <DriveBackupFile>[];

      // حذف النسخ الزائدة عن العدد المحدد
      if (backupFiles.length > maxBackups) {
        final excessFiles = backupFiles.sublist(maxBackups);
        filesToDelete.addAll(excessFiles);
        dlog(() => '📊 نسخ زائدة عن العدد المحدد: ${excessFiles.length}');
      }

      // حذف النسخ الأقدم من فترة الاحتفاظ
      for (final file in backupFiles) {
        if (file.createdTime.isBefore(cutoffDate) && !filesToDelete.contains(file)) {
          filesToDelete.add(file);
        }
      }

      if (filesToDelete.isNotEmpty) {
        dlog(() => '🗑️ حذف ${filesToDelete.length} نسخة احتياطية قديمة...');

        for (final file in filesToDelete) {
          try {
            await _backupService!.deleteBackupFile(file.fileId);
            dlog(() => '✅ تم حذف: ${file.fileName} (${_formatDateTime(file.createdTime)})');
          } catch (e) {
            derr(() => 'فشل حذف ${file.fileName}: $e');
          }
        }

        dlog(() => '🧹 اكتمل التنظيف: تم حذف ${filesToDelete.length} نسخة');
      } else {
        dlog('✨ لا توجد نسخ قديمة للحذف');
      }
    } catch (e) {
      derr(() => 'خطأ في تنظيف النسخ القديمة: $e');
    }
  }

  /// جدولة تنظيف دوري للنسخ القديمة
  Future<void> _schedulePeriodicCleanup() async {
    _cleanupTimer?.cancel();

    // تنظيف دوري كل 6 ساعات
    _cleanupTimer = Timer.periodic(const Duration(hours: 6), (timer) {
      _cleanupOldBackups();
    });

    dlog('⏰ تم جدولة التنظيف الدوري كل 6 ساعات');
  }

  /// تنظيف فوري للنسخ القديمة (يمكن استدعاؤه يدوياً)
  Future<void> cleanupNow() async {
    dlog('🧹 تنظيف فوري مطلوب...');
    await _cleanupOldBackups();
  }

  /// إعدادات النسخ التلقائي

  Future<bool> get _isEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoBackupEnabledKey) ?? true; // مفعل افتراضياً
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoBackupEnabledKey, enabled);
    dlog(() => '🔧 النسخ التلقائي: ${enabled ? 'مفعل' : 'معطل'}');
  }

  Future<int> _getMaxBackupCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_maxBackupCountKey) ?? _defaultMaxBackups;
  }

  Future<void> setMaxBackupCount(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_maxBackupCountKey, count);
    dlog(() => '🔧 عدد النسخ القصوى: $count');
  }

  Future<int> getMaxBackupCount() async {
    return _getMaxBackupCount();
  }

  Future<int> _getRetentionDays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_backupRetentionDaysKey) ?? _defaultRetentionDays;
  }

  Future<void> setRetentionDays(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_backupRetentionDaysKey, days);
    dlog(() => '🔧 فترة الاحتفاظ: $days يوماً');
  }

  Future<int> getRetentionDays() async {
    return _getRetentionDays();
  }

  Future<DateTime?> _getLastAutoBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timeString = prefs.getString(_lastAutoBackupKey);
    return timeString != null ? DateTime.parse(timeString) : null;
  }

  Future<void> _setLastAutoBackupTime(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastAutoBackupKey, time.toIso8601String());
  }

  /// معلومات النسخ التلقائي
  Future<Map<String, dynamic>> getStatus() async {
    final isEnabled = await _isEnabled;
    final lastBackup = await _getLastAutoBackupTime();
    final maxBackups = await _getMaxBackupCount();
    final retentionDays = await _getRetentionDays();

    return {
      'enabled': isEnabled,
      'is_backing_up': _isBackingUp,
      'pending_changes': _pendingChanges,
      'last_auto_backup': lastBackup?.toIso8601String(),
      'max_backups': maxBackups,
      'retention_days': retentionDays,
      'signed_in': _backupService?.isSignedIn ?? false,
    };
  }

  /// إيقاف المدير وتنظيف الموارد
  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _deltaSyncDebounceTimer?.cancel();
    _deltaSyncDebounceTimer = null;
    _deltaSyncTimer?.cancel();
    _deltaSyncTimer = null;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    dlog('🛑 مدير النسخ التلقائي: تم التنظيف');
  }

  /// تنظيف الموارد الثابتة للـ singleton (يُستدعى عند إغلاق التطبيق)
  static void disposeInstance() {
    _instance?.dispose();
    _instance = null;
  }

  /// التحقق من حالة المزامنة التفاضلية
  bool get isDeltaSyncing => _isDeltaSyncing;

  /// تنسيق التاريخ والوقت للعرض
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// إشعار مدير المزامنة الذكية بوجود نسخة جديدة
  Future<void> _notifySmartSync() async {
    try {
      final smartSync = SmartSyncManager.instance;
      if (await smartSync.isEnabled()) {
        dlog('🔔 إشعار مدير المزامنة الذكية بالنسخة الجديدة...');
        await smartSync.onLocalBackupUploaded();
      }
    } catch (e) {
      dwarn(() => 'خطأ في إشعار مدير المزامنة: $e');
    }
  }

  /// تفعيل/تعطيل المزامنة الفورية
  Future<void> setInstantSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_instantSyncEnabledKey, enabled);
    dlog(() => '🔧 المزامنة الفورية: ${enabled ? 'مفعلة' : 'معطلة'}');
  }

  /// التحقق من تفعيل المزامنة الفورية
  Future<bool> isInstantSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_instantSyncEnabledKey) ?? true;
  }

  /// مزامنة فورية عند الطلب
  Future<void> syncNow() async {
    dlog('🚀 بدء المزامنة الفورية...');

    if (_currentMode == BackupMode.deltaSync || _currentMode == BackupMode.both) {
      await performDeltaSync();
    }

    if (_currentMode == BackupMode.fullBackup || _currentMode == BackupMode.both) {
      if (_backupService != null && _backupService!.isSignedIn) {
        await _performAutoBackup(reason: 'مزامنة فورية يدوية', changesCount: _pendingChanges > 0 ? _pendingChanges : 1);
      }
    }

    _pendingChanges = 0;
  }

  /// تنفيذ المزامنة التفاضلية
  Future<Map<String, dynamic>> performDeltaSync() async {
    if (_isDeltaSyncing) {
      return {'success': false, 'message': 'المزامنة التفاضلية جارية بالفعل'};
    }

    _isDeltaSyncing = true;
    final results = <String, dynamic>{'google_drive': null, 'appwrite': null, 'success': true};

    try {
      dlog('🔄 بدء المزامنة التفاضلية...');

      if (await isGoogleDriveDeltaSyncEnabled() && _googleDriveDeltaSync != null) {
        try {
          final pushResult = await _googleDriveDeltaSync!.pushDeltaChanges();
          final pullResult = await _googleDriveDeltaSync!.pullDeltaChanges();
          results['google_drive'] = {
            'push': {'success': pushResult.success, 'count': pushResult.changesCount},
            'pull': {'success': pullResult.success, 'count': pullResult.changesCount},
          };
          if (!pushResult.success || !pullResult.success) {
            results['success'] = false;
          }
          dlog(() => '✅ Google Drive Delta: رفع ${pushResult.changesCount}، سحب ${pullResult.changesCount}');
        } catch (e) {
          results['google_drive'] = {'error': e.toString()};
          results['success'] = false;
          derr(() => 'خطأ في مزامنة Google Drive التفاضلية: $e');
        }
      }

      // ✅ تم ترحيل المزامنة إلى AppwriteSyncManager (الطريقة الجديدة)
      // AppwriteDeltaSync محذوف — كل المزامنة عبر AppwriteSyncManager.sync()
      // ✅ Batch 3: استخدام singleton بدل إنشاء instance جديد عبر المصنع
      if (_appwriteService != null && _appwriteService!.isInitialized && _database != null) {
        try {
          final syncManager = AppwriteSyncManager.instance ?? AppwriteSyncManager(appwriteService: _appwriteService!, database: _database!);
          final result = await syncManager.sync();
          results['appwrite'] = {
            'push': {'success': result.status == SyncStatus.success, 'count': result.recordsPushed},
            'pull': {'success': result.status == SyncStatus.success, 'count': result.recordsPulled},
          };
          if (result.status != SyncStatus.success) {
            results['success'] = false;
          }
          dlog(() => '✅ Appwrite Sync: رفع ${result.recordsPushed}، سحب ${result.recordsPulled}');
        } catch (e) {
          results['appwrite'] = {'error': e.toString()};
          results['success'] = false;
          derr(() => 'خطأ في مزامنة Appwrite: $e');
        }
      }

      dlog('✅ اكتملت المزامنة التفاضلية');

      await _autoRenewActiveBookings();
    } catch (e) {
      results['success'] = false;
      results['error'] = e.toString();
      derr(() => 'خطأ في المزامنة التفاضلية: $e');
    } finally {
      _isDeltaSyncing = false;
    }

    return results;
  }

  Future<void> _autoRenewActiveBookings() async {
    try {
      final currentHotelDay = HotelTimeEngine.getHotelDayKey();
      if (_lastRenewedHotelDay == currentHotelDay) {
        return;
      }

      if (_database == null) {
        return;
      }
      final service = BookingDerivedFieldsService(_database!);
      final count = await service.refreshAllActiveBookings();
      _lastRenewedHotelDay = currentHotelDay;
      if (count > 0) {
        dlog(() => '🏨 تجديد تلقائي: $count حجز نشط (يوم فندقي: $currentHotelDay)');
      }
    } catch (e) {
      dwarn(() => 'خطأ في تجديد الحجوزات النشطة: $e');
    }
  }

  /// إعدادات المزامنة التفاضلية
  Future<bool> isDeltaSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_deltaSyncEnabledKey) ?? true;
  }

  Future<void> setDeltaSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_deltaSyncEnabledKey, enabled);
    if (enabled) {
      await _startDeltaSyncTimer();
    } else {
      _deltaSyncTimer?.cancel();
    }
    dlog(() => '🔧 المزامنة التفاضلية: ${enabled ? 'مفعلة' : 'معطلة'}');
  }

  Future<bool> isGoogleDriveDeltaSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_googleDriveDeltaSyncEnabledKey) ?? false;
  }

  Future<void> setGoogleDriveDeltaSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_googleDriveDeltaSyncEnabledKey, enabled);
    dlog(() => '🔧 مزامنة Google Drive التفاضلية: ${enabled ? 'مفعلة' : 'معطلة'}');
  }

  /// تعيين وضع النسخ الاحتياطي
  Future<void> setBackupMode(BackupMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    _currentMode = mode;
    await prefs.setInt(_backupModeKey, _currentMode.index);
    await prefs.setBool(_deltaSyncEnabledKey, true);
    dlog(() => '🔧 وضع النسخ الاحتياطي: ${_currentMode.name}');
  }

  BackupMode get currentBackupMode => _currentMode;

  /// الحصول على حالة المزامنة التفاضلية
  Future<Map<String, dynamic>> getDeltaSyncStatus() async {
    return {
      'delta_sync_enabled': await isDeltaSyncEnabled(),
      'google_drive_enabled': await isGoogleDriveDeltaSyncEnabled(),
      'appwrite_enabled': true, // ✅ مفعّل دائماً عبر AppwriteSyncManager
      'is_syncing': _isDeltaSyncing,
      'backup_mode': _currentMode.name,
      'google_drive_status': _googleDriveDeltaSync != null ? await _googleDriveDeltaSync!.getStatus() : null,
    };
  }

  /// الحصول على عدد التغييرات المعلقة
  int get pendingChangesCount => _pendingChanges;

  /// التحقق من حالة النسخ الجارية
  bool get isBackingUp => _isBackingUp;

  /// الحصول على معرف الجهاز
  String? get deviceId => _deviceId;
}
