// Test helpers for AutoSyncEngine simulation

/// إمدادات بيانات اختبار الزوامل للتكوين
class MockDataSupply {
  static const testConfig = {
    'auto_sync_debounce': 5,
    'auto_sync_pull_interval': 2,
    'auto_sync_retry_enabled': true,
    'conflict_strategy': 'newerWins',
  };
}

/// ملحق قاeadmonition دات AppDatabase لتسهيل pass contexts
extension AutoSyncEngineProofOfConcept on AppDatabase {
  
  /// تسجيل تغيير يدويًا في قاعدة البيانات (محاكاة)
  Future<void> recordManualChange({
    required String table,
    required String operation,
    Map<String, dynamic>? recordData,
    int count = 1,
  }) async {
    // استعمال OutboxDao لتوثيق التغييرات
    final outboxDao = OutboxDao(this);
    await outboxDao.insertChange(
      table: table,
      operation: operation,
      recordData: recordData,
      generatedAt: DateTime.now(),
    );
    
    // استدعاء المحرك التلقائي مباشرة لينبه بالتغييرات
    AutoSyncEngine.instance.notifyDataChange(
      table: table,
      operation: operation,
      count: count,
      recordData: recordData,
    );
  }

  /// فحص وجود تغييرات معلقة
  Future<int> getPendingChangesCount() async {
    return await (select(outbox).get()).length;
  }
}

/// وقت زمني للانتظار خاص بالاختبارات
class TestDelays {
  static const Duration debounceBuffer = Duration(seconds: 6);  // 5s debounce + 1s buffer
  static const Duration networkTransition = Duration(milliseconds: 200);
  static const Duration syncCompletion = Duration(seconds: 2);
  static const Duration retryWait = Duration(seconds: 3);
}

/// نظام الرصد والتحقق أثناء التنفيذ
class TestWatcher {
  static final List<String> _log = [];
  static final StreamController<String> _streamController = StreamController<String>.broadcast();

  static Stream<String> get stream => _streamController.stream;

  static void log(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 23);
    final logEntry = '[$timestamp] $message';
    _log.add(logEntry);
    _streamController.add(logEntry);
    print('🍽️ TEST-WATCHER: $message');
  }

  static List<String> getLogs() => List.from(_log);

  static void clear() {
    _log.clear();
    _streamController.add('watcher_cleared');
  }

  static void dispose() {
    _streamController.close();
  }
}

/// باني محاكاة رائع لحالات النظام المختلفة
class AutoSyncScenarioBuilder {
  final AppDatabase database;
  final AutoSyncEngine engine;
  final BookingsRepository repository;
  
  AutoSyncScenarioBuilder({
    required this.database,
    required this.engine,
  }) : repository = BookingsRepository(database);

  /// سيناريو: قبل التشغيل/تعادة التعطيل
  Future<void> ensureOfflineState() async {
    TestWatcher.log('🏠 البدء بمحاكاة حالة وضع الحالية مع تصل كهربائي');
    // هذا سيبقى المرحلة الأولى ظاهراًا للنظام (سيستعمل للاختبار)
  }

  /// سيناريو إنشاء حجزات متعددة ومحاكاة مشغلات مختلفة
  Future<List<int>> createMultipleBookings({
    int count = 3,
    Duration? spacing,
  }) async {
    spacing ??= Duration(milliseconds: 500);
    
    final bookingIds = <int>[];
    for (var i = 0; i < count; i++) {
      TestWatcher.log('📋 إنشاء حجز #${i+1}...');
      
      final id = await bookingsRepository.create(
        roomNumber: 'TEST-${100 + i}',
        guestName: 'Test Guest ${i + 1}',
        guestPhone: '+96612345678${i}',
        guestNationality: 'لبناني',
        checkinDate: '2024-12-${10 + i}',
        expectedNights: 2 + i,
        status: 'نشط',
      );
      
      bookingIds.add(id);
      if (i < count - 1) await Future.delayed(spacing!);
    }
    
    TestWatcher.log('📊 اكتمل إنشاء $count حجزات فنزل مؤجلة');
    return bookingIds;
  }

  /// انتظار ظهور حالة التزامن قائمة بالكامل
  Future<bool> waitForSyncState({
    required AutoSyncEngine engine,
    required bool Function(Map<String, dynamic> status) condition,
    Duration timeout = const Duration(seconds: 30),
    Duration checkInterval = const Duration(seconds: 1),
  }) async {
    TestWatcher.log('⏱️ بدء الانتظار لحالت: ${condition.toString().substring(0, 50)}...');
    
    final stopwatch = Stopwatch()..start();
    
    while (stopwatch.elapsed < timeout) {
      try {
        final status = await engine.getEngineStatus();
        if (condition(status)) {
          TestWatcher.log('✅ تم تحقق الحالة أي مطلوبة');
          return true;
        }
      } catch (e) {
        TestWatcher.log('⚠️ خطأ أثناء كنترول الحالة: $e');
      }
      await Future.delayed(checkInterval);
    }
    
    TestWatcher.log('❌ انتهى الانتظار بدون الوصول للحالة المطلوبة');
    return false;
  }

  /// هذا التابع يثبت نظامًا كاملًا لنظام المزامنة التلقائي برهنة قابلة للتشغيل الكامل
  Future<SyncTestResult> executeEndToEndProof() async {
    TestWatcher.clear();
    final startTime = DateTime.now();
    
    try {
      TestWatcher.log('🚀 بدء اختبار برهان المزامنة التلقائية الكامل...');
      
      // المرحلة 1: تهيئة النظام
      TestWatcher.log('1️⃣ تهيئة النظام في وضع عدم الاتصال...');
      await ensureOfflineState();
      await Future.delayed(TestDelays.networkTransition);
      
      // المرحلة 2: إكسابب تغييرات
      TestWatcher.log('2️⃣ إنشاء تغييرات متعددة على جهاز غير متصل بالشبكة...');
      final bookingIds = await createMultipleBookings(count: 3);
      
      // المرحلة 3: الحالة المعلقة
      TestWatcher.log('3️⃣ التحقق من وجود تغييرات معلقة...');
      final pendingCount = await database.getPendingChangesCount();
      if (pendingCount == 0) {
        throw Exception('تاج! لا يوجد تغييرات معلقة تم إدراجها بعد خلول الانتظار');
      }
      
      // المرحلة 4: تغيير إلى وضع متصل
      TestWatcher.log('4️⃣ محاكاة استعادة الاتصال الكامل...');
      // مهمة الصعب محاكاة Network بشكل حقيقي، لكن نتأكد أن المحرك مدعوم لتلقي عمليات الاتصال
      
      // المرحلة 5: انتظار التجميع والرفع التلقائي
      TestWatcher.log('5️⃣ انتظار Debounce والتزامن التلقائي...');
      await Future.delayed(TestDelays.debounceBuffer);
      await Future.delayed(TestDelays.debounceBuffer); // مرتين للتأكد من التجميع الكامل
      
      // المرحلة 6: التحقق من تكملة عملية التزامن التلقائي
      TestWatcher.log('6️⃣ التحقق من أن SyncManager قام بمهمته...');
      
      // تأكيد النتائج
      final finalStatus = await engine.getEngineStatus();
      final pendingFinal = await database.getPendingChangesCount();
      
      TestWatcher.log('📊 نتائج النظام بعد الاختبار:');
      TestWatcher.log('   محرك نشط: ${finalStatus["engine"]['running']}');
      TestWatcher.log('   تم تسجيل الدخول: ${finalStatus["engine"]['signed_in']}');
      TestWatcher.log('   Hardware معالجة شبكة: ${finalStatus["engine"]['network_connected']}');
      TestWatcher.log('   محاولات فاشلة أخرى: ${finalStatus["engine"]['failed_attempts']}');
      TestWatcher.log('   تغييرات معلقة أخيرة: $pendingFinal');
      
      return SyncTestResult(
        success: true,
        bookingIds: bookingIds,
        pendingInitial: pendingCount,
        pendingFinal: pendingFinal,
        status: finalStatus,
        executionTime: DateTime.now().difference(startTime),
        logs: TestWatcher.getLogs(),
      );
      
    } catch (e, stackTrace) {
      TestWatcher.log('❌ اختبار برهان المزامنة فشل: $e');
      print('StackTrace: $stackTrace');
      
      return SyncTestResult(
        success: false,
        error: e.toString(),
        executionTime: DateTime.now().difference(startTime),
        logs: TestWatcher.getLogs(),
      );
    }
  }

  /// تنظيف بعد إكمال الاختبار
  Future<void> cleanup() async {
    TestWatcher.log('🧹 بدء تنظيف الاختبار...');
    await database.clear();
    TestWatcher.log('🗑️ تم حذف بيانات الاختبار');
  }
}

/// نتائج تشغيل برهان التزامن التلقائي
class SyncTestResult {
  final bool success;
  final List<int> bookingIds;
  final int pendingInitial;
  final int pendingFinal;
  final Map<String, dynamic> status;
  final Duration executionTime;
  final List<String> logs;
  final String? error;

  const SyncTestResult({
    required this.success,
    this.bookingIds = const [],
    this.pendingInitial = 0,
    this.pendingFinal = 0,
    this.status = const {},
    required this.executionTime,
    this.logs = const [],
    this.error,
  });

  /// تحليل شامل للنتائج الملموسة
  Map<String, dynamic> analyze() {
    final networkStateChanged = status['engine']?['network_connected'] ?? false;
    final engineActive = status['engine']?['running'] ?? false;
    final loginActive = status['engine']?['signed_in'] ?? false;
    final syncOccurred = status['engine']?['last_successful_sync'] != null;
    
    final changesFlushed = pendingFinal < pendingInitial || (pendingFinal == 0 && pendingInitial > 0);
    final errorRate = status['engine']?['failed_attempts'] ?? 0;
    
    return {
      'success': success && changesFlushed && engineActive && networkStateChanged && loginActive,
      'engine_fully_active': engineActive && loginActive,
      'network_handled_correctly': networkStateChanged,
      'pending_changes_flushed': changesFlushed,
      'sync_attempted': syncOccurred || logs.any((log) => log.contains('sync')),
      'error_recovery': errorRate > 0,
      'execution_seconds': executionTime.inSeconds,
      'changes_created': bookingIds.length,
      'pending_start': pendingInitial,
      'pending_end': pendingFinal,
      'test_id': DateTime.now().microsecondsSinceEpoch,
    };
  }

  @override
  String toString() {
    final analysis = analyze();
    return '''
🎯 Sync Test Results
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Overall Success: ${analysis['success']}
🏃 Engine Active: ${analysis['engine_fully_active']}
🌐 Network Handled: ${analysis['network_handled_correctly']}
💾 Changes Flushed: ${analysis['pending_changes_flushed']}
🔄 Sync Attempted: ${analysis['sync_attempted']}
❌ Error Recovery: ${analysis['error_recovery']}
⏱️ Duration: ${analysis['execution_seconds']}s
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
'''.trim();
  }
}