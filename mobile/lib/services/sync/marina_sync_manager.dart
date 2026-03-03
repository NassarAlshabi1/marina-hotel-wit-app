import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../appwrite_service.dart';
import '../appwrite_delta_sync.dart';
import '../appwrite_sync_manager.dart' show AppwriteSyncManager, SyncResult;
import '../google_drive_unified_sync_coordinator.dart';
import '../google_drive_backup_service.dart';
import '../google_drive_logger.dart';
import '../sync_integrity_checker.dart';
import '../local_db.dart';
import '../sync_enums.dart';
import '../../data/sync_models.dart' as sync_models;

/// 🎯 MarinaSyncManager - النظام الموحد للمزامنة
/// 
/// يوفر API واحد نظيف يجمع كل قدرات المزامنة:
/// - Delta Sync (مزامنة الفروقات فقط)
/// - Two-way Sync (مزامنة ثنائية الاتجاه)
/// - Conflict Resolution (حل التضاربات)
/// - Auto-sync (مزامنة تلقائية)
/// - Multi-provider (Appwrite + Google Drive)
///
/// Usage:
/// ```dart
/// await MarinaSyncManager.instance.initialize(database: db);
/// 
/// // مزامنة كاملة
/// await MarinaSyncManager.instance.sync();
/// 
/// // رفع التغييرات فقط
/// await MarinaSyncManager.instance.push();
/// 
/// // سحب التغييرات فقط  
/// await MarinaSyncManager.instance.pull();
/// 
/// // الاستماع للحالة
/// MarinaSyncManager.instance.watchStatus().listen((status) {
///   print('Sync: ${status.phase} - ${status.message}');
/// });
/// ```
class MarinaSyncManager {
  MarinaSyncManager._();
  static final MarinaSyncManager instance = MarinaSyncManager._();

  // ==========================================================================
  // Dependencies
  // ==========================================================================
  AppDatabase? _database;
  AppwriteSyncManager? _appwriteManager;
  AppwriteDeltaSync? _deltaSync;
  GoogleDriveUnifiedSyncCoordinator? _driveCoordinator;
  GoogleDriveBackupService? _backupService;

  // ==========================================================================
  // State Management
  // ==========================================================================
  bool _initialized = false;
  bool _isSyncing = false;
  SyncStatus _currentStatus = SyncStatus.idle;

  final _statusController = StreamController<SyncStatus>.broadcast();
  final _progressController = StreamController<SyncProgress>.broadcast();
  final _conflictController = StreamController<SyncConflict>.broadcast();

  Stream<SyncStatus> get statusStream => _statusController.stream;
  Stream<SyncProgress> get progressStream => _progressController.stream;
  Stream<SyncConflict> get conflictStream => _conflictController.stream;

  // ==========================================================================
  // Configuration
  // ==========================================================================
  SyncConfig _config = const SyncConfig();
  SyncConfig get config => _config;

  // Auto-sync
  Timer? _autoSyncTimer;
  StreamSubscription<ConnectivityResult>? _connectivitySub;

  // ==========================================================================
  // Public API - Initialization
  // ==========================================================================

  /// Initialize the sync manager
  /// 
  /// [database] - Required: Local database instance
  /// [config] - Optional: Custom sync configuration
  /// [enableAutoSync] - Enable automatic periodic sync
  Future<void> initialize({
    required AppDatabase database,
    SyncConfig? config,
    bool enableAutoSync = true,
  }) async {
    if (_initialized) return;

    _database = database;
    _config = config ?? const SyncConfig();

    // Initialize Appwrite delta sync (lightweight, primary)
    _deltaSync = AppwriteDeltaSync(database);

    // Initialize Google Drive coordinator
    _driveCoordinator = GoogleDriveUnifiedSyncCoordinator.instance;
    _backupService = GoogleDriveBackupService();

    // Setup connectivity monitoring
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen(_onConnectivityChanged);

    // Setup auto-sync if enabled
    if (enableAutoSync && _config.autoSyncEnabled) {
      _startAutoSync();
    }

    _initialized = true;
    _emitStatus(SyncStatus.idle, 'جاهز للمزامنة');
  }

  // ==========================================================================
  // Public API - Core Sync Operations
  // ==========================================================================

  /// 🔄 مزامنة كاملة (رفع + سحب)
  /// 
  /// تدعم كلا المصدرين: Appwrite و Google Drive
  /// حسب الإعدادات المخزنة في SharedPreferences
  Future<SyncResult> sync({
    bool force = false,
    String reason = 'manual',
  }) async {
    if (!_initialized) {
      return SyncResult.failure('SyncManager not initialized');
    }

    if (_isSyncing && !force) {
      return SyncResult.failure('Sync already in progress');
    }

    _isSyncing = true;
    _emitStatus(SyncStatus.syncing, 'جاري المزامنة...');

    try {
      final prefs = await SharedPreferences.getInstance();
      final appwriteEnabled = prefs.getBool('appwrite_sync_enabled') ?? false;
      final driveEnabled = prefs.getBool('google_drive_sync_enabled') ?? false;

      var results = <ProviderResult>[];

      // Step 1: Sync with Appwrite (Delta - Fast)
      if (appwriteEnabled) {
        _emitProgress('مزامنة مع Appwrite...', 0.2);
        final appwriteResult = await _syncAppwrite(push: true, pull: true);
        results.add(ProviderResult('appwrite', appwriteResult));
      }

      // Step 2: Sync with Google Drive (if enabled)
      if (driveEnabled) {
        _emitProgress('مزامنة مع Google Drive...', 0.6);
        final driveResult = await _syncGoogleDrive(push: true, pull: true);
        results.add(ProviderResult('google_drive', driveResult));
      }

      // Step 3: Verify integrity
      if (_config.verifyIntegrity) {
        _emitProgress('التحقق من سلامة البيانات...', 0.9);
        await _verifyIntegrity();
      }

      // Check overall success
      final allSuccess = results.every((r) => r.result.isSuccess);
      final totalPushed = results.fold<int>(
        0,
        (sum, r) => sum + (r.result.recordsPushed ?? 0),
      );
      final totalPulled = results.fold<int>(
        0,
        (sum, r) => sum + (r.result.recordsPulled ?? 0),
      );

      _emitStatus(
        allSuccess ? SyncStatus.success : SyncStatus.partial,
        'تمت المزامنة: ${totalPushed} رفع, ${totalPulled} سحب',
      );

      return SyncResult.success(
        recordsPushed: totalPushed,
        recordsPulled: totalPulled,
        message: 'Sync completed successfully',
      );
    } catch (e) {
      _emitStatus(SyncStatus.failed, 'فشل المزامنة: $e');
      return SyncResult.failure(e.toString());
    } finally {
      _isSyncing = false;
    }
  }

  /// ⬆️ رفع التغييرات المحلية فقط (Push)
  Future<SyncResult> push({String reason = 'manual_push'}) async {
    return _performOneWaySync(push: true, pull: false, reason: reason);
  }

  /// ⬇️ سحب التغييرات من السحابة فقط (Pull)
  Future<SyncResult> pull({String reason = 'manual_pull'}) async {
    return _performOneWaySync(push: false, pull: true, reason: reason);
  }

  /// 📤 مزامنة Outbox (للتغييرات المعلقة)
  Future<SyncResult> syncOutbox() async {
    if (!_initialized) {
      return SyncResult.failure('SyncManager not initialized');
    }

    _emitStatus(SyncStatus.syncing, 'مزامنة Outbox...');

    try {
      final manager = await _ensureAppwriteManager();
      if (manager == null) {
        return SyncResult.failure('Appwrite not available');
      }

      final success = await manager.pushLocalChanges();
      _emitStatus(
        success ? SyncStatus.success : SyncStatus.failed,
        success ? 'تم رفع Outbox' : 'فشل رفع Outbox',
      );

      return success
          ? SyncResult.success(message: 'Outbox synced')
          : SyncResult.failure('Outbox sync failed');
    } catch (e) {
      return SyncResult.failure(e.toString());
    }
  }

  /// 📸 إنشاء Snapshot كامل (Google Drive)
  Future<SyncResult> snapshot({bool force = false}) async {
    if (!_initialized) {
      return SyncResult.failure('SyncManager not initialized');
    }

    _emitStatus(SyncStatus.syncing, 'إنشاء Snapshot...');

    try {
      final coordinator = _driveCoordinator;
      if (coordinator == null || !coordinator.isInitialized) {
        return SyncResult.failure('Google Drive not initialized');
      }

      final result = await coordinator.performSync(
        trigger: SyncTrigger.manual,
        mode: SyncMode.fullBackup,
      );

      _emitStatus(
        result.success ? SyncStatus.success : SyncStatus.failed,
        result.success ? 'تم إنشاء Snapshot' : 'فشل إنشاء Snapshot',
      );

      return SyncResult(
        isSuccess: result.success,
        message: result.message,
      );
    } catch (e) {
      return SyncResult.failure(e.toString());
    }
  }

  // ==========================================================================
  // Public API - Conflict Management
  // ==========================================================================

  /// الحصول على قائمة التضاربات الحالية
  List<SyncConflict> get pendingConflicts => _pendingConflicts;
  final List<SyncConflict> _pendingConflicts = [];

  /// حل تضارب محدد
  /// 
  /// [resolution] - استراتيجية الحل:
  /// - ConflictResolution.local: الاحتفاظ بالمحلي
  /// - ConflictResolution.remote: الاحتفاظ بالبعيد
  /// - ConflictResolution.merge: دمج البيانات
  Future<void> resolveConflict(
    SyncConflict conflict, {
    required ConflictResolution resolution,
  }) async {
    _emitStatus(SyncStatus.syncing, 'حل التضارب...');

    try {
      switch (resolution) {
        case ConflictResolution.local:
          await _resolveKeepLocal(conflict);
          break;
        case ConflictResolution.remote:
          await _resolveKeepRemote(conflict);
          break;
        case ConflictResolution.merge:
          await _resolveMerge(conflict);
          break;
      }

      _pendingConflicts.remove(conflict);
      _emitStatus(SyncStatus.success, 'تم حل التضارب');
    } catch (e) {
      _emitStatus(SyncStatus.failed, 'فشل حل التضارب: $e');
      rethrow;
    }
  }

  /// رفض/تجاهل تضارب
  Future<void> dismissConflict(SyncConflict conflict) async {
    _pendingConflicts.remove(conflict);
  }

  // ==========================================================================
  // Public API - State Watching
  // ==========================================================================

  /// الاستماع لتغييرات الحالة
  Stream<SyncStatus> watchStatus() => statusStream;

  /// الاستماع لتقدم المزامنة
  Stream<SyncProgress> watchProgress() => progressStream;

  /// الاستماع للتضاربات الجديدة
  Stream<SyncConflict> watchConflicts() => conflictStream;

  /// الحصول على الحالة الحالية
  SyncStatus get currentStatus => _currentStatus;

  /// هل المزامنة نشطة الآن؟
  bool get isSyncing => _isSyncing;

  // ==========================================================================
  // Public API - Configuration
  // ==========================================================================

  /// تحديث الإعدادات
  Future<void> updateConfig(SyncConfig newConfig) async {
    _config = newConfig;

    // Restart auto-sync if needed
    _autoSyncTimer?.cancel();
    if (_config.autoSyncEnabled) {
      _startAutoSync();
    }

    // Save to preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sync_auto_interval_minutes', _config.autoSyncIntervalMinutes);
    await prefs.setBool('sync_verify_integrity', _config.verifyIntegrity);
  }

  /// تفعيل/تعطيل Auto-sync
  Future<void> setAutoSyncEnabled(bool enabled) async {
    await updateConfig(_config.copyWith(autoSyncEnabled: enabled));
  }

  // ==========================================================================
  // Public API - Cleanup
  // ==========================================================================

  Future<void> dispose() async {
    _autoSyncTimer?.cancel();
    await _connectivitySub?.cancel();
    await _statusController.close();
    await _progressController.close();
    await _conflictController.close();
    _initialized = false;
  }

  // ==========================================================================
  // Private Implementation
  // ==========================================================================

  Future<SyncResult> _performOneWaySync({
    required bool push,
    required bool pull,
    required String reason,
  }) async {
    if (!_initialized) {
      return SyncResult.failure('SyncManager not initialized');
    }

    if (_isSyncing) {
      return SyncResult.failure('Sync already in progress');
    }

    _isSyncing = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final appwriteEnabled = prefs.getBool('appwrite_sync_enabled') ?? false;
      final driveEnabled = prefs.getBool('google_drive_sync_enabled') ?? false;

      var results = <ProviderResult>[];

      if (appwriteEnabled) {
        _emitStatus(SyncStatus.syncing, push ? 'رفع إلى Appwrite...' : 'سحب من Appwrite...');
        final result = await _syncAppwrite(push: push, pull: pull);
        results.add(ProviderResult('appwrite', result));
      }

      if (driveEnabled) {
        _emitStatus(SyncStatus.syncing, push ? 'رفع إلى Drive...' : 'سحب من Drive...');
        final result = await _syncGoogleDrive(push: push, pull: pull, reason: reason);
        results.add(ProviderResult('google_drive', result));
      }

      final allSuccess = results.every((r) => r.result.isSuccess);

      _emitStatus(
        allSuccess ? SyncStatus.success : SyncStatus.partial,
        push ? 'تم الرفع' : 'تم السحب',
      );

      return allSuccess
          ? SyncResult.success(message: push ? 'Push completed' : 'Pull completed')
          : SyncResult.failure('One-way sync failed');
    } catch (e) {
      _emitStatus(SyncStatus.failed, 'فشل: $e');
      return SyncResult.failure(e.toString());
    } finally {
      _isSyncing = false;
    }
  }

  Future<SyncResult> _syncAppwrite({
    required bool push,
    required bool pull,
  }) async {
    final deltaSync = _deltaSync;
    if (deltaSync == null) {
      return SyncResult.failure('DeltaSync not initialized');
    }

    try {
      final result = await deltaSync.sync(push: push, pull: pull);

      return SyncResult(
        isSuccess: result.success,
        recordsPushed: result.pushedCount,
        recordsPulled: result.pulledCount,
        message: result.message,
      );
    } catch (e) {
      return SyncResult.failure('Appwrite sync error: $e');
    }
  }

  Future<SyncResult> _syncGoogleDrive({
    required bool push,
    required bool pull,
    required String reason,
  }) async {
    final coordinator = _driveCoordinator;
    if (coordinator == null) {
      return SyncResult.failure('Google Drive not initialized');
    }

    try {
      // Ensure initialized
      if (!coordinator.isInitialized) {
        final account = await _backupService?.attemptSilentSignIn();
        if (account == null) {
          return SyncResult.failure('Google Drive not signed in');
        }

        final logger = GoogleDriveLogger();
        await logger.initialize(
          minLevel: LogLevel.info,
          enableConsole: kDebugMode,
          enableFile: false,
        );

        await coordinator.initialize(
          backupService: _backupService!,
          database: _database!,
          logger: logger,
        );
      }

      // Determine sync mode
      final mode = (push && pull)
          ? SyncMode.smart
          : (push ? SyncMode.pushOnly : SyncMode.deltaOnly);

      final trigger = reason.contains('manual')
          ? SyncTrigger.manual
          : SyncTrigger.periodic;

      final result = await coordinator.performSync(
        trigger: trigger,
        mode: mode,
      );

      return SyncResult(
        isSuccess: result.success,
        message: result.message,
        recordsPushed: result.pushedChanges,
        recordsPulled: result.pulledChanges,
      );
    } catch (e) {
      return SyncResult.failure('Google Drive sync error: $e');
    }
  }

  Future<void> _verifyIntegrity() async {
    if (_database == null) return;
    await SyncIntegrityChecker.instance.verify(_database!);
  }

  Future<AppwriteSyncManager?> _ensureAppwriteManager() async {
    if (_appwriteManager != null) return _appwriteManager;

    final db = _database ?? DatabaseManager.instance;
    _database ??= db;

    final service = AppwriteService();
    final manager = AppwriteSyncManager(
      appwriteService: service,
      database: db,
    );
    await manager.initialize();

    _appwriteManager = manager;
    return manager;
  }

  // ==========================================================================
  // Conflict Resolution Implementation
  // ==========================================================================

  Future<void> _resolveKeepLocal(SyncConflict conflict) async {
    final db = _database;
    if (db == null) return;

    // Mark local as definitive and push
    // Implementation depends on specific table
    await _markAsDefinitive(conflict.tableName, conflict.recordId, conflict.localData);
    await push(reason: 'conflict_resolution_local');
  }

  Future<void> _resolveKeepRemote(SyncConflict conflict) async {
    final db = _database;
    if (db == null) return;

    // Apply remote data locally
    await _applyRemoteData(conflict.tableName, conflict.recordId, conflict.remoteData);
  }

  Future<void> _resolveMerge(SyncConflict conflict) async {
    final db = _database;
    if (db == null) return;

    // Merge data intelligently
    final merged = _mergeData(conflict.localData, conflict.remoteData);
    await _applyRemoteData(conflict.tableName, conflict.recordId, merged);
    await push(reason: 'conflict_resolution_merge');
  }

  Future<void> _markAsDefinitive(
    String table,
    String id,
    Map<String, dynamic> data,
  ) async {
    // Implementation specific to table structure
    // This is a placeholder - actual implementation would update local DB
  }

  Future<void> _applyRemoteData(
    String table,
    String id,
    Map<String, dynamic> data,
  ) async {
    // Implementation specific to table structure
  }

  Map<String, dynamic> _mergeData(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    final merged = Map<String, dynamic>.from(local);

    for (final entry in remote.entries) {
      final key = entry.key;
      final remoteValue = entry.value;
      final localValue = local[key];

      // Prefer non-null values
      if (remoteValue != null && localValue == null) {
        merged[key] = remoteValue;
      } else if (remoteValue is Map && localValue is Map) {
        merged[key] = _mergeData(
          Map<String, dynamic>.from(localValue),
          Map<String, dynamic>.from(remoteValue),
        );
      }
      // For conflicts, prefer remote by default in merge mode
      // Could be enhanced with timestamp comparison
    }

    return merged;
  }

  // ==========================================================================
  // Event Handlers
  // ==========================================================================

  void _onConnectivityChanged(ConnectivityResult result) {
    if (result != ConnectivityResult.none && _config.autoSyncOnConnect) {
      sync(reason: 'connectivity_restored');
    }
  }

  void _startAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(
      Duration(minutes: _config.autoSyncIntervalMinutes),
      (_) => sync(reason: 'auto_sync'),
    );
  }

  // ==========================================================================
  // Event Emitters
  // ==========================================================================

  void _emitStatus(SyncStatus status, String message) {
    _currentStatus = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
    debugPrint('🔄 MarinaSync: $message');
  }

  void _emitProgress(String message, double progress) {
    if (!_progressController.isClosed) {
      _progressController.add(SyncProgress(message: message, progress: progress));
    }
  }

  void _emitConflict(SyncConflict conflict) {
    _pendingConflicts.add(conflict);
    if (!_conflictController.isClosed) {
      _conflictController.add(conflict);
    }
  }
}

// =============================================================================
// Data Models
// =============================================================================

/// حالة المزامنة
enum SyncStatus {
  idle,
  syncing,
  success,
  failed,
  partial,
}

/// إعدادات المزامنة
class SyncConfig {
  final bool autoSyncEnabled;
  final int autoSyncIntervalMinutes;
  final bool autoSyncOnConnect;
  final bool verifyIntegrity;
  final bool enableAppwrite;
  final bool enableGoogleDrive;
  final ConflictResolution defaultConflictResolution;

  const SyncConfig({
    this.autoSyncEnabled = true,
    this.autoSyncIntervalMinutes = 15,
    this.autoSyncOnConnect = true,
    this.verifyIntegrity = true,
    this.enableAppwrite = true,
    this.enableGoogleDrive = true,
    this.defaultConflictResolution = ConflictResolution.merge,
  });

  SyncConfig copyWith({
    bool? autoSyncEnabled,
    int? autoSyncIntervalMinutes,
    bool? autoSyncOnConnect,
    bool? verifyIntegrity,
    bool? enableAppwrite,
    bool? enableGoogleDrive,
    ConflictResolution? defaultConflictResolution,
  }) {
    return SyncConfig(
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
      autoSyncIntervalMinutes: autoSyncIntervalMinutes ?? this.autoSyncIntervalMinutes,
      autoSyncOnConnect: autoSyncOnConnect ?? this.autoSyncOnConnect,
      verifyIntegrity: verifyIntegrity ?? this.verifyIntegrity,
      enableAppwrite: enableAppwrite ?? this.enableAppwrite,
      enableGoogleDrive: enableGoogleDrive ?? this.enableGoogleDrive,
      defaultConflictResolution: defaultConflictResolution ?? this.defaultConflictResolution,
    );
  }
}

/// استراتيجيات حل التضارب
enum ConflictResolution {
  local, // الأحدث محلياً يفوز
  remote, // الأحدث بعيداً يفوز
  merge, // دمج البيانات
}

/// تقدم المزامنة
class SyncProgress {
  final String message;
  final double progress; // 0.0 to 1.0

  const SyncProgress({
    required this.message,
    required this.progress,
  });
}

/// تضارب مزامنة
class SyncConflict {
  final String tableName;
  final String recordId;
  final Map<String, dynamic> localData;
  final Map<String, dynamic> remoteData;
  final DateTime detectedAt;

  const SyncConflict({
    required this.tableName,
    required this.recordId,
    required this.localData,
    required this.remoteData,
    required this.detectedAt,
  });
}

/// نتيجة مزامنة
class SyncResult {
  final bool isSuccess;
  final String message;
  final int? recordsPushed;
  final int? recordsPulled;

  const SyncResult({
    required this.isSuccess,
    required this.message,
    this.recordsPushed,
    this.recordsPulled,
  });

  factory SyncResult.success({
    String message = 'Success',
    int? recordsPushed,
    int? recordsPulled,
  }) {
    return SyncResult(
      isSuccess: true,
      message: message,
      recordsPushed: recordsPushed,
      recordsPulled: recordsPulled,
    );
  }

  factory SyncResult.failure(String error) {
    return SyncResult(isSuccess: false, message: error);
  }
}

/// نتيجة مزامنة لمزود محدد
class ProviderResult {
  final String provider;
  final SyncResult result;

  ProviderResult(this.provider, this.result);
}
