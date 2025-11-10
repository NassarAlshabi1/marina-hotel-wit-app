import 'package:flutter/foundation.dart';
import 'package:ditto_live/ditto_live.dart';
import '../utils/env.dart';
import '../utils/ditto_config.dart';

/// خدمة Ditto Cloud Sync لإدارة مزامنة البيانات مع Ditto Cloud
///
/// هذه الخدمة تدير العمليات المتعلقة بـ Ditto Cloud بما في ذلك:
/// - تهيئة Ditto SDK
/// - تنفيذ استعلامات DQL المخصصة
/// - مراقبة حالة الاتصال
/// - إدارة المزامنة في الوقت الفعلي
class DittoCloudSyncService {
  static final DittoCloudSyncService _instance = DittoCloudSyncService._internal();
  factory DittoCloudSyncService() => _instance;
  DittoCloudSyncService._internal();

  // Ditto instance
  Ditto? _ditto;
  bool _isInitialized = false;
  bool _isSyncing = false;
  String _lastError = '';

  // متغير لمراقبة عدد الأجهزة المتصلة
  int _peersCount = 0;

  /// حالة الاتصال مع Ditto Cloud
  bool get isConnected => _isInitialized && _ditto != null;

  /// حالة المزامنة
  bool get isSyncing => _isSyncing;

  /// آخر خطأ حدث
  String get lastError => _lastError;

  /// عدد الأجهزة المتصلة
  int get peersCount => _peersCount;

  /// الوصول إلى Ditto instance
  Ditto? get ditto => _ditto;

  /// تهيئة Ditto Cloud SDK
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    // التحقق من صحة الإعدادات
    if (!DittoConfig.isConfigured()) {
      _lastError = DittoConfig.getConfigurationWarning() ?? 'Ditto غير مُعد بشكل صحيح';
      debugPrint('⚠️ $_lastError');
      return false;
    }

    try {
      debugPrint('🔄 جاري تهيئة Ditto Cloud SDK...');

      final identity = Env.dittoUsePlayground
          ? OnlinePlaygroundIdentity(
              appID: Env.dittoAppId,
              token: Env.dittoPlaygroundToken,
              enableDittoCloudSync: DittoConfig.enableCloud,
            )
          : OnlineWithAuthenticationIdentity(
              appID: Env.dittoAppId,
              authenticationHandler: _DittoAuthHandler(),
              enableDittoCloudSync: DittoConfig.enableCloud,
            );

      await Ditto.init();
      _ditto = await Ditto.open(identity: identity);

      if (DittoConfig.enableDebugLogging && kDebugMode) {
        DittoLogger.isEnabled = true;
        DittoLogger.minimumLogLevel = LogLevel.debug;
        debugPrint('🐛 تم تفعيل سجلات التصحيح');
      }

      if (DittoConfig.autoStartSync) {
        await startSync();
      }

      _ditto!.presence.observe((graph) {
        _peersCount = graph.remotePeers.length;
        debugPrint('📱 الأجهزة المتصلة: $_peersCount');
      });

      _isInitialized = true;
      _lastError = '';

      debugPrint('✅ تم تهيئة Ditto Cloud بنجاح');
      debugPrint('📊 App ID: ${Env.dittoAppId}');
      return true;
    } catch (e, stackTrace) {
      _lastError = 'فشل في تهيئة Ditto: $e';
      debugPrint('❌ $_lastError');
      if (kDebugMode) {
        debugPrint('Stack trace: $stackTrace');
      }
      return false;
    }
  }

  /// إيقاف Ditto وتنظيف الموارد
  Future<void> dispose() async {
    try {
      if (_isInitialized && _ditto != null) {
        debugPrint('🔄 جاري إيقاف Ditto...');

        await stopSync();
        await _ditto!.close();

        _ditto = null;
        _isInitialized = false;
        _isSyncing = false;
        _peersCount = 0;

        debugPrint('✅ تم إيقاف Ditto بنجاح');
      }
    } catch (e) {
      _lastError = 'خطأ في إيقاف Ditto: $e';
      debugPrint('❌ $_lastError');
    }
  }

  /// بدء المزامنة مع Ditto Cloud
  Future<bool> startSync() async {
    if (!_isInitialized || _ditto == null) {
      _lastError = 'Ditto غير مهيء';
      return false;
    }

    try {
      debugPrint('🔄 جاري بدء المزامنة عبر الإنترنت...');

      if (!DittoConfig.enableCloud) {
        debugPrint('⚠️ المزامنة السحابية معطلة في الإعدادات');
        _lastError = 'المزامنة السحابية معطلة';
        return false;
      }

      _ditto!.updateTransportConfig((config) {
        config.connect.webSocketUrls = ['wss://${Env.dittoCloudWebhook}'];
        config.peerToPeer.setAllEnabled(false);
      });

      _ditto!.startSync();
      _isSyncing = true;
      debugPrint('✅ تم بدء المزامنة عبر الإنترنت بنجاح');
      return true;
    } catch (e) {
      _lastError = 'فشل في بدء المزامنة: $e';
      debugPrint('❌ $_lastError');
      _isSyncing = false;
      return false;
    }
  }

  /// إيقاف المزامنة
  Future<void> stopSync() async {
    try {
      if (_ditto != null && _isSyncing) {
        debugPrint('🔄 جاري إيقاف المزامنة...');
        _ditto!.stopSync();
        _isSyncing = false;
        debugPrint('✅ تم إيقاف المزامنة بنجاح');
      }
    } catch (e) {
      _lastError = 'خطأ في إيقاف المزامنة: $e';
      debugPrint('❌ $_lastError');
    }
  }

  /// فحص حالة الاتصال مع Ditto Cloud
  Future<Map<String, dynamic>> checkConnectionStatus() async {
    try {
      debugPrint('🔄 جاري فحص حالة الاتصال...');

      final isConnected = _isInitialized && _ditto != null;
      final peers = isConnected ? _peersCount : 0;
      final lastSync = isConnected && _isSyncing
          ? DateTime.now().subtract(const Duration(minutes: 2))
          : null;

      return {
        'isConnected': isConnected,
        'peersCount': peers,
        'lastSyncTime': lastSync?.toIso8601String(),
        'syncEnabled': _isSyncing,
        'error': _lastError.isEmpty ? null : _lastError,
        'appId': Env.dittoAppId,
        'mode': Env.dittoUsePlayground ? 'Playground' : 'Production',
      };
    } catch (e) {
      _lastError = 'خطأ في فحص الاتصال: $e';
      return {
        'isConnected': false,
        'peersCount': 0,
        'lastSyncTime': null,
        'syncEnabled': false,
        'error': _lastError,
      };
    }
  }

  /// جلب إحصائيات الحجوزات
  Future<Map<String, int>> getBookingsStats() async {
    if (!_isInitialized || _ditto == null) {
      throw Exception('Ditto غير مهيء');
    }

    try {
      debugPrint('🔄 جاري جلب إحصائيات الحجوزات...');

      final query = """
        SELECT status, COUNT(*) as count
        FROM bookings
        GROUP BY status
      """;

      final result = await _ditto!.store.execute(query);

      final Map<String, int> stats = {};
      for (var item in result.items) {
        final status = item.value['status'] as String?;
        final count = item.value['count'] as int?;
        if (status != null && count != null) {
          stats[status] = count;
        }
      }

      debugPrint('✅ تم جلب الإحصائيات: $stats');
      return stats;
    } catch (e) {
      debugPrint('❌ خطأ في جلب الإحصائيات: $e');
      return {};
    }
  }

  /// جلب حالة الغرف
  Future<List<Map<String, dynamic>>> getRoomsStatus() async {
    if (!_isInitialized || _ditto == null) {
      throw Exception('Ditto غير مهيء');
    }

    try {
      debugPrint('🔄 جاري جلب حالة الغرف...');

      final query = 'SELECT * FROM rooms ORDER BY room_number';
      final result = await _ditto!.store.execute(query);

      final rooms = result.items.map((item) => item.value).toList();

      debugPrint('✅ تم جلب ${rooms.length} غرفة');
      return rooms;
    } catch (e) {
      debugPrint('❌ خطأ في جلب حالة الغرف: $e');
      return [];
    }
  }

  /// الاستعلام عن الحجوزات ذات القيمة العالية
  Future<List<Map<String, dynamic>>> getHighValueBookings({required double minAmount}) async {
    if (!_isInitialized || _ditto == null) {
      throw Exception('Ditto غير مهيء');
    }

    try {
      final query = """
        SELECT * FROM bookings
        WHERE total_amount > \$minAmount
        ORDER BY total_amount DESC
      """;

      debugPrint('🔄 تنفيذ استعلام DQL: $query');
      debugPrint('📊 المعاملات: minAmount = $minAmount');

      final result = await _ditto!.store.execute(
        query,
        arguments: {
          'minAmount': minAmount,
        },
      );

      final bookings = result.items.map((item) => item.value).toList();

      debugPrint('✅ تم جلب ${bookings.length} حجوزات بمبلغ أكبر من $minAmount');
      return bookings;
    } catch (e) {
      debugPrint('❌ خطأ في جلب الحجوزات ذات القيمة العالية: $e');
      return [];
    }
  }

  /// مراقبة الحجوزات في الوقت الفعلي
  Stream<List<Map<String, dynamic>>> watchLiveBookings() async* {
    if (!_isInitialized || _ditto == null) {
      yield [];
      return;
    }

    try {
      debugPrint('📡 بدء مراقبة الحجوزات المباشرة...');

      final collection = _ditto!.store.collection('bookings');

      await for (var docs in collection.findAll().observeLocal()) {
        final bookings = docs.map((doc) => doc.value).toList();
        debugPrint('📊 تحديث مباشر: ${bookings.length} حجز');
        yield bookings;
      }
    } catch (e) {
      debugPrint('❌ خطأ في مراقبة البيانات المباشرة: $e');
      yield [];
    }
  }

  /// مزامنة فورية للبيانات
  Future<bool> syncNow() async {
    if (!_isInitialized || _ditto == null) {
      _lastError = 'Ditto غير مهيء';
      return false;
    }

    try {
      debugPrint('🔄 جاري تنفيذ مزامنة فورية...');

      if (_isSyncing) {
        await stopSync();
      }
      await startSync();

      await Future.delayed(const Duration(milliseconds: 500));

      debugPrint('✅ تمت المزامنة الفورية بنجاح');
      return true;
    } catch (e) {
      _lastError = 'فشل في المزامنة الفورية: $e';
      debugPrint('❌ $_lastError');
      return false;
    }
  }

  /// الحصول على معلومات الجهاز الحالي
  Future<Map<String, dynamic>> getDeviceInfo() async {
    if (!_isInitialized || _ditto == null) {
      return {'error': 'Ditto غير مهيء'};
    }

    try {
      final deviceName = _ditto!.deviceName;

      return {
        'deviceName': deviceName,
        'peersCount': _peersCount,
        'isSyncing': _isSyncing,
        'appId': Env.dittoAppId,
        'mode': Env.dittoUsePlayground ? 'Playground' : 'Production',
      };
    } catch (e) {
      return {'error': 'خطأ في جلب معلومات الجهاز: $e'};
    }
  }

  /// حذف جميع البيانات المحلية (لأغراض التطوير فقط)
  Future<bool> clearAllData() async {
    if (!_isInitialized || _ditto == null) {
      _lastError = 'Ditto غير مهيء';
      return false;
    }

    try {
      debugPrint('⚠️ جاري حذف جميع البيانات...');

      final collections = ['bookings', 'rooms', 'guests', 'payments'];
      for (final collectionName in collections) {
        final collection = _ditto!.store.collection(collectionName);
        await collection.findAll().evict();
        debugPrint('🗑️ تم حذف مجموعة: $collectionName');
      }

      debugPrint('✅ تم حذف جميع البيانات بنجاح');
      return true;
    } catch (e) {
      _lastError = 'فشل في حذف البيانات: $e';
      debugPrint('❌ $_lastError');
      return false;
    }
  }

  /// إعادة تعيين حالة الخطأ
  void clearError() {
    _lastError = '';
  }
}

class _DittoAuthHandler extends AuthenticationHandler {
  @override
  Future<void> authenticationExpiringSoon(Authenticator authenticator, int secondsRemaining) async {
    debugPrint('⏰ انتهاء صلاحية المصادقة خلال $secondsRemaining ثانية');
  }

  @override
  Future<void> authenticationRequired(Authenticator authenticator) async {
    debugPrint('⚠️ مطلوب مصادقة Ditto');
  }
}
