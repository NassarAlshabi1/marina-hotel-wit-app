/// Sync Orchestrator
/// منسق المزامنة - يدير عملية المزامنة الكاملة
/// Pull → Resolve → Push → Notify

import 'dart:async';
import 'dart:developer' as developer;

import '../models/sync_models.dart';
import '../vector_clock.dart';
import '../delta_sync_engine.dart';
import '../processors/outbox_processor.dart';

/// منسق المزامنة الرئيسي
/// يدور حول النمط: Pull → Resolve → Push → Notify
class SyncOrchestrator {
  final DeltaSyncEngine _syncEngine;
  final OutboxProcessor _outbox;
  // ignore: unused_field
  final VectorClockManager _clockManager;
  final SyncConfiguration _config;
  // ignore: unused_field
  final List<SyncStrategy> _strategies;

  final _stateController = StreamController<SyncState>.broadcast();
  final _progressController = StreamController<SyncProgress>.broadcast();
  final _conflictController = StreamController<SyncConflict>.broadcast();

  Timer? _autoSyncTimer;
  bool _isInitialized = false;
  
  // ✅ CHANGED: استخدام SyncState مركزي بدلاً من متغيرات منفصلة لضمان الاتساق (Single Source of Truth)
  // PRIORITY: P0
  SyncState _currentSyncState = SyncState.initial();

  SyncOrchestrator({
    required DeltaSyncEngine syncEngine,
    required OutboxProcessor outbox,
    required VectorClockManager clockManager,
    required SyncConfiguration config,
    List<SyncStrategy>? strategies,
  })  : _syncEngine = syncEngine,
        _outbox = outbox,
        _clockManager = clockManager,
        _config = config,
        _strategies = strategies ?? [];

  /// Stream لحالة المزامنة
  Stream<SyncState> get stateStream => _stateController.stream;

  /// Stream لتقدم المزامنة
  Stream<SyncProgress> get progressStream => _progressController.stream;

  /// Stream للتعارضات
  Stream<SyncConflict> get conflictStream => _conflictController.stream;

  /// الحالة الحالية
  SyncState get currentState => _currentSyncState;

  /// تهيئة المنسق
  Future<void> initialize() async {
    if (_isInitialized) return;

    developer.log('Initializing SyncOrchestrator', name: 'Sync');

    // الاستماع لأحداث المحرك
    _syncEngine.events.listen(_handleSyncEvent);

    // تهيئة Outbox
    await _outbox.initialize();

    _isInitialized = true;
    
    // ✅ CHANGED: تحديث الحالة الأولية
    _currentSyncState = _currentSyncState.copyWith(status: SyncStatus.idle);
    _emitState();

    developer.log('SyncOrchestrator initialized', name: 'Sync');
  }

  /// بدء المزامنة التلقائية
  void startAutoSync() {
    if (!_config.enabled || !_config.backgroundSyncEnabled) return;

    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(
      _config.autoSyncInterval,
      (_) => syncIfNeeded(),
    );

    developer.log('Auto sync started: ${_config.autoSyncInterval}', name: 'Sync');
  }

  /// إيقاف المزامنة التلقائية
  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    developer.log('Auto sync stopped', name: 'Sync');
  }

  /// المزامنة إذا لزم الأمر (حسب الإعدادات)
  Future<void> syncIfNeeded() async {
    if (!_config.enabled) return;
    if (_currentSyncState.isSyncing) return;

    // التحقق من وجود تغييرات معلقة
    final pendingCount = await _outbox.pendingCount;
    if (pendingCount == 0 && _currentSyncState.lastSyncAt != null) {
      // لا يوجد تغييرات وتمت المزامنة مؤخراً
      final timeSinceLastSync = DateTime.now().difference(_currentSyncState.lastSyncAt!);
      if (timeSinceLastSync < _config.autoSyncInterval) {
        return;
      }
    }

    await performFullSync();
  }

  /// تنفيذ مزامنة كاملة
  /// النمط: Pull → Resolve → Push → Notify
  Future<DeltaSyncResult> performFullSync({
    SyncDirection direction = SyncDirection.bidirectional,
  }) async {
    if (_currentSyncState.isSyncing) {
      throw SyncAlreadyInProgressException();
    }

    // ✅ CHANGED: تحديث الحالة المركزية لبدء المزامنة
    _currentSyncState = _currentSyncState.copyWith(status: SyncStatus.syncing, isSyncing: true, error: null);
    _emitState();

    final stopwatch = Stopwatch()..start();
    final progress = SyncProgress(
      phase: SyncPhase.pull,
      message: 'جاري سحب التغييرات...',
    );
    _progressController.add(progress);

    developer.log('Starting full sync', name: 'Sync');

    try {
      // ⬇️ المرحلة 1: Pull - سحب التغييرات من السيرفر
      _progressController.add(progress.copyWith(
        phase: SyncPhase.pull,
        message: 'جاري سحب التغييرات من السيرفر...',
      ));

      final pullResult = await _syncEngine.sync(direction: SyncDirection.download);

      // إشعار بالتعارضات المكتشفة
      for (final conflict in pullResult.conflicts) {
        _conflictController.add(conflict);
      }

      // ⏸️ المرحلة 2: Resolve - حل التعارضات
      if (pullResult.conflicts.isNotEmpty) {
        _progressController.add(progress.copyWith(
          phase: SyncPhase.resolve,
          message: 'جاري حل ${pullResult.conflicts.length} تعارض...',
          conflictsFound: pullResult.conflicts.length,
        ));
      }

      // ⬆️ المرحلة 3: Push - رفع التغييرات المحلية
      final pendingCount = await _outbox.pendingCount;
      if (pendingCount > 0) {
        _progressController.add(progress.copyWith(
          phase: SyncPhase.push,
          message: 'جاري رفع $pendingCount تغيير...',
          pendingToPush: pendingCount,
        ));

        final pushResult = await _syncEngine.sync(direction: SyncDirection.upload);

        // ✅ ADDED: استخدام Batch Operations لتحديث حالة المزامنة في Outbox
        // PRIORITY: P1 Performance
        if (pushResult.success && pushResult.uploadedIds.isNotEmpty) {
          await _outbox.markBatchAsSynced(pushResult.uploadedIds);
        }

        // دمج النتائج
        final combinedResult = DeltaSyncResult(
          success: pullResult.success && pushResult.success,
          uploadedCount: pushResult.uploadedCount,
          downloadedCount: pullResult.downloadedCount,
          conflictCount: pullResult.conflictCount,
          errorCount: pullResult.errorCount + pushResult.errorCount,
          conflicts: pullResult.conflicts,
          errors: [...pullResult.errors, ...pushResult.errors],
          timestamp: DateTime.now(),
        );

        final now = DateTime.now();
        stopwatch.stop();

        _progressController.add(progress.copyWith(
          phase: SyncPhase.completed,
          message: 'اكتملت المزامنة بنجاح',
          completed: true,
          uploaded: combinedResult.uploadedCount,
          downloaded: combinedResult.downloadedCount,
          conflicts: combinedResult.conflictCount,
          durationMs: stopwatch.elapsedMilliseconds,
        ));

        // ✅ CHANGED: تحديث الحالة المركزية عند النجاح
        _currentSyncState = _currentSyncState.copyWith(status: SyncStatus.synced, lastSyncAt: now, isSyncing: false);
        _emitState();

        developer.log(
          'Sync completed: ${combinedResult.downloadedCount} down, '
          '${combinedResult.uploadedCount} up, ${combinedResult.conflictCount} conflicts',
          name: 'Sync',
        );

        return combinedResult;
      } else {
        // لا يوجد تغييرات للرفع
        final now = DateTime.now();
        stopwatch.stop();

        _progressController.add(progress.copyWith(
          phase: SyncPhase.completed,
          message: 'اكتملت المزامنة',
          completed: true,
          downloaded: pullResult.downloadedCount,
          conflicts: pullResult.conflictCount,
          durationMs: stopwatch.elapsedMilliseconds,
        ));

        // ✅ CHANGED: تحديث الحالة المركزية عند النجاح (بدون رفع)
        _currentSyncState = _currentSyncState.copyWith(status: SyncStatus.synced, lastSyncAt: now, isSyncing: false);
        _emitState();

        return pullResult;
      }
    } catch (e, stackTrace) {
      stopwatch.stop();

      _progressController.add(progress.copyWith(
        phase: SyncPhase.failed,
        message: 'فشلت المزامنة: $e',
        error: e.toString(),
      ));

      // ✅ CHANGED: تحديث الحالة المركزية عند الفشل
      _currentSyncState = _currentSyncState.copyWith(status: SyncStatus.failed, error: e.toString(), isSyncing: false);
      _emitState();

      developer.log(
        'Sync failed: $e',
        name: 'Sync',
        error: e,
        stackTrace: stackTrace,
      );

      rethrow;
    } finally {
      _currentSyncState = _currentSyncState.copyWith(isSyncing: false);
      _emitState();
    }
  }

  /// مزامنة اتجاه واحد فقط
  Future<DeltaSyncResult> syncDirection(SyncDirection direction) async {
    return await performFullSync(direction: direction);
  }

  /// سحب التغييرات فقط (Pull)
  Future<DeltaSyncResult> pullOnly() async {
    return await syncDirection(SyncDirection.download);
  }

  /// رفع التغييرات فقط (Push)
  Future<DeltaSyncResult> pushOnly() async {
    return await syncDirection(SyncDirection.upload);
  }

  /// التحقق من وجود تغييرات معلقة
  Future<bool> hasPendingChanges() async {
    return await _outbox.pendingCount > 0;
  }

  /// إضافة تغيير محلي للمزامنة
  Future<String> queueLocalChange({
    required String table,
    required String uuid,
    required SyncOperation operation,
    required Map<String, dynamic> data,
  }) async {
    final id = await _outbox.enqueue(
      table: table,
      uuid: uuid,
      operation: operation,
      payload: data,
    );

    developer.log('Queued change: $table/$uuid ($operation)', name: 'Sync');

    return id;
  }

  /// إضافة مجموعة تغييرات
  Future<List<String>> queueBatchChanges(List<ChangeRequest> requests) async {
    final ids = await _outbox.enqueueBatch(requests);
    developer.log('Queued ${ids.length} changes in batch', name: 'Sync');
    return ids;
  }

  /// معالجة حدث من SyncEngine
  void _handleSyncEvent(SyncEvent event) {
    developer.log('Sync event: ${event.type}', name: 'Sync');

    switch (event.type) {
      case SyncEventType.conflictDetected:
        // تم إشعار التعارض في stream مخصص
        break;
      case SyncEventType.syncFailed:
        _currentSyncState = _currentSyncState.copyWith(status: SyncStatus.failed);
        _emitState();
        break;
      case SyncEventType.syncStarted:
        _currentSyncState = _currentSyncState.copyWith(status: SyncStatus.syncing, isSyncing: true);
        _emitState();
        break;
      case SyncEventType.syncCompleted:
        _currentSyncState = _currentSyncState.copyWith(status: SyncStatus.synced, lastSyncAt: DateTime.now(), isSyncing: false);
        _emitState();
        break;
      default:
        break;
    }
  }

  /// إصدار حالة جديدة
  void _emitState() {
    _stateController.add(_currentSyncState);
  }

  /// التخلص من الموارد
  void dispose() {
    stopAutoSync();
    _stateController.close();
    _progressController.close();
    _conflictController.close();
    _outbox.dispose();
    _syncEngine.dispose();
  }
}

/// حالة المزامنة
class SyncState {
  final SyncStatus status;
  final bool isSyncing;
  final DateTime? lastSyncAt;
  final String? error;

  SyncState({
    required this.status,
    required this.isSyncing,
    this.lastSyncAt,
    this.error,
  });

  // ✅ ADDED: دالة copyWith لتسهيل تحديث الحالة بشكل آمن (Immutable State Management)
  SyncState copyWith({
    SyncStatus? status,
    bool? isSyncing,
    DateTime? lastSyncAt,
    String? error,
  }) {
    return SyncState(
      status: status ?? this.status,
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      error: error ?? this.error,
    );
  }

  // ✅ ADDED: الحالة الأولية
  factory SyncState.initial() => SyncState(
        status: SyncStatus.idle,
        isSyncing: false,
      );

  bool get isIdle => !isSyncing;
  bool get hasError => error != null;
  bool get isSynced => status == SyncStatus.synced;

  @override
  String toString() =>
      'SyncState(status: $status, syncing: $isSyncing, lastSync: $lastSyncAt)';
}

/// تقدم المزامنة
class SyncProgress {
  final SyncPhase phase;
  final String message;
  final int? pendingToPush;
  final int? conflictsFound;
  final int? uploaded;
  final int? downloaded;
  final int? conflicts;
  final int? durationMs;
  final bool completed;
  final String? error;

  SyncProgress({
    required this.phase,
    required this.message,
    this.pendingToPush,
    this.conflictsFound,
    this.uploaded,
    this.downloaded,
    this.conflicts,
    this.durationMs,
    this.completed = false,
    this.error,
  });

  SyncProgress copyWith({
    SyncPhase? phase,
    String? message,
    int? pendingToPush,
    int? conflictsFound,
    int? uploaded,
    int? downloaded,
    int? conflicts,
    int? durationMs,
    bool? completed,
    String? error,
  }) {
    return SyncProgress(
      phase: phase ?? this.phase,
      message: message ?? this.message,
      pendingToPush: pendingToPush ?? this.pendingToPush,
      conflictsFound: conflictsFound ?? this.conflictsFound,
      uploaded: uploaded ?? this.uploaded,
      downloaded: downloaded ?? this.downloaded,
      conflicts: conflicts ?? this.conflicts,
      durationMs: durationMs ?? this.durationMs,
      completed: completed ?? this.completed,
      error: error ?? this.error,
    );
  }
}

/// مراحل المزامنة
enum SyncPhase {
  idle,
  pull,
  resolve,
  push,
  completed,
  failed,
}

/// استراتيجية مزامنة
abstract class SyncStrategy {
  /// تطبيق الاستراتيجية قبل المزامنة
  Future<void> beforeSync(SyncContext context);

  /// تطبيق الاستراتيجية بعد المزامنة
  Future<void> afterSync(SyncContext context, DeltaSyncResult result);
}

/// سياق المزامنة
class SyncContext {
  final SyncDirection direction;
  final DateTime? since;
  final Map<String, dynamic> metadata;

  SyncContext({
    required this.direction,
    this.since,
    this.metadata = const {},
  });
}

/// استثناء: المزامنة قيد التنفيذ
class SyncAlreadyInProgressException implements Exception {
  @override
  String toString() => 'Sync already in progress';
}
