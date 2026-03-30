import 'dart:async';

import 'package:flutter/foundation.dart';

import '../appwrite_delta_sync.dart';
import '../appwrite_service.dart';
import '../local_db.dart';
import '../../providers/smart_init/delta_sync_init_state.dart';
import 'backoff_calculator.dart';
import 'network_monitor.dart';

/// مُهيئ Delta Sync الذكي — Service منفصل عن AppwriteDeltaSync.
///
/// المسؤوليات:
/// 1. مراقبة حالة الشبكة عبر [NetworkMonitor].
/// 2. محاولة تهيئة AppwriteDeltaSync تلقائياً عند توفر الشبكة.
/// 3. إعادة المحاولة مع exponential backoff عند الفشل.
/// 4. نشر حالة التهيئة عبر [stateStream] لاستهلاك UI.
///
/// **لا يُعدّل** AppwriteDeltaSync أو AppwriteService أو DatabaseManager.
class DeltaSyncInitializer {
  DeltaSyncInitializer._();
  static final DeltaSyncInitializer instance = DeltaSyncInitializer._();

  // ─── Dependencies ──────────────────────────────────────────

  final NetworkMonitor _monitor = NetworkMonitor.instance;

  // ─── State ──────────────────────────────────────────────────

  bool _isRunning = false;
  bool _isInitializing = false;
  int _retryCount = 0;
  DateTime? _lastAttemptAt;

  /// Stream لنشر حالة التهيئة (idle/waiting/initializing/ready/failed).
  final StreamController<DeltaSyncInitState> _stateController =
      StreamController<DeltaSyncInitState>.broadcast();

  Timer? _retryTimer;
  final List<StreamSubscription<void>> _subscriptions = [];

  // ─── Public API ─────────────────────────────────────────────

  /// Stream تفاعلي لحالة التهيئة.
  Stream<DeltaSyncInitState> get stateStream => _stateController.stream;

  /// قراءة متزامنة للحالة الحالية.
  DeltaSyncInitState _currentState = DeltaSyncInitState.idle;
  DeltaSyncInitState get currentState => _currentState;

  /// بدء المراقبة (idempotent — آمن للاستدعاء المتعدد).
  ///
  /// يبدأ:
  /// - مراقبة الشبكة.
  /// - محاولة تهيئة فورية إذا كانت الشبكة متوفرة.
  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _monitor.start();

    // الاستماع لعودة الشبكة
    _subscriptions.add(
      _monitor.onNetworkRestored.listen((_) => _onNetworkRestored()),
    );

    // محاولة أولى — لا تنتظر
    _tryInitialize();
  }

  /// إيقاف المراقبة وتنظيف جميع الموارد.
  void stop() {
    _isRunning = false;
    _retryTimer?.cancel();
    _retryTimer = null;

    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  /// إعادة المحاولة فوراً (من UI مثلاً).
  ///
  /// يعيد [true] إذا بدأت محاولة، [false] إذا كانت جارية أو النظام جاهز.
  Future<bool> retryNow() async {
    if (_isInitializing) return false;

    final delta = AppwriteDeltaSync.instance;
    if (delta.isInitialized) return false;

    _retryCount = 0; // إعادة تعيين العداد
    return _tryInitialize();
  }

  /// إعادة تعيين الحالة بالكامل (لاختبار).
  @visibleForTesting
  void reset() {
    stop();
    _isInitializing = false;
    _retryCount = 0;
    _lastAttemptAt = null;
    _currentState = DeltaSyncInitState.idle;
  }

  // ─── Private Methods ────────────────────────────────────────

  /// يُستدعى عند انتقال الشبكة من offline → online.
  void _onNetworkRestored() {
    if (kDebugMode) {
      debugPrint('🌐 [SmartInit] Network restored — attempting init');
    }
    // إعادة تعيين العداد عند عودة الشبكة
    _retryCount = 0;
    _retryTimer?.cancel();
    _tryInitialize();
  }

  /// محاولة تهيئة AppwriteDeltaSync.
  ///
  /// يعيد [true] إذا بدأت محاولة فعلية.
  Future<bool> _tryInitialize() async {
    final delta = AppwriteDeltaSync.instance;
    if (delta.isInitialized) {
      _emitState(DeltaSyncInitState.ready);
      return false;
    }

    // فحص الشبكة أولاً
    final hasNetwork = await _monitor.checkNow();
    if (!hasNetwork) {
      _emitState(DeltaSyncInitState.waitingNetwork);
      return false;
    }

    // منع المحاولات المتزامنة
    if (_isInitializing) return false;
    _isInitializing = true;
    _lastAttemptAt = DateTime.now();
    _emitState(DeltaSyncInitState.initializing);

    try {
      // إنشاء AppwriteService جديد (آمن — يحتوي على فحص _initialized)
      final service = AppwriteService();
      await service.initialize();

      // تهيئة Delta Sync مع قاعدة البيانات
      final database = DatabaseManager.instance;
      await delta.initialize(service, database);

      _isInitializing = false;
      _retryCount = 0;
      _retryTimer?.cancel();
      _emitState(DeltaSyncInitState.ready);

      if (kDebugMode) {
        debugPrint('✅ [SmartInit] Delta Sync initialized successfully');
      }
      return true;
    } catch (e) {
      _isInitializing = false;
      _retryCount++;

      if (kDebugMode) {
        debugPrint('⚠️ [SmartInit] Init failed (attempt $_retryCount): $e');
      }

      // التحقق من الأخطاء القاتلة
      if (_isFatalError(e)) {
        _emitState(DeltaSyncInitState.failed);
        if (kDebugMode) {
          debugPrint('🛑 [SmartInit] Fatal error — stopping retries: $e');
        }
        return false;
      }

      _emitState(DeltaSyncInitState.failed);
      _scheduleRetry();
      return false;
    }
  }

  /// جدولة إعادة المحاولة مع exponential backoff.
  void _scheduleRetry() {
    _retryTimer?.cancel();

    final delay = BackoffCalculator.calculateDuration(_retryCount);
    final nextAttemptAt = DateTime.now().add(delay);

    if (kDebugMode) {
      debugPrint(
        '⏰ [SmartInit] Retry #$_retryCount in '
        '${delay.inSeconds}s (at ${nextAttemptAt.toIso8601String()})',
      );
    }

    _retryTimer = Timer(delay, () {
      if (!_isRunning) return;
      _tryInitialize();
    });
  }

  /// هل الخطأ قاتل (لا فائدة من إعادة المحاولة)؟
  bool _isFatalError(Object error) {
    final errorString = error.toString().toLowerCase();

    // خطأ غير متوقع في بنية البيانات
    if (errorString.contains('database') && errorString.contains('corrupt')) {
      return true;
    }

    // إذا كان DeltaSync مهيأ فعلاً — هذا في الحقيقة نجاح
    if (AppwriteDeltaSync.instance.isInitialized) {
      return true;
    }

    return false;
  }

  /// نشر حالة جديدة على جميع المستمعين.
  void _emitState(DeltaSyncInitState state) {
    _currentState = state;
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }

  /// تنظيف الموارد (يُستدعى عند إغلاق StreamController).
  void dispose() {
    stop();
    if (!_stateController.isClosed) {
      _stateController.close();
    }
  }
}
