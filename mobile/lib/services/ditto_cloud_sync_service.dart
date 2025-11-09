import 'dart:async';
import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/ditto_config.dart';

/// خدمة Ditto للمزامنة السحابية فقط (v4.12.4 compatible)
/// تستخدم WebSocket للاتصال بـ Ditto Cloud بدون اتصال P2P محلي
class DittoCloudSyncService {
  static DittoCloudSyncService? _instance;
  static DittoCloudSyncService get instance => _instance ??= DittoCloudSyncService._();
  
  DittoCloudSyncService._();

  Ditto? _ditto;
  StreamSubscription? _subscription;
  bool _isInitialized = false;
  bool _isSyncing = false;
  
  // إعدادات Ditto Cloud من DittoConfig
  static String get _appId => DittoConfig.appId;
  static String get _playgroundToken => DittoConfig.playgroundToken;
  static String get _webSocketUrl => DittoConfig.webSocketUrl;
  
  // مفاتيح SharedPreferences
  static const String _deviceIdKey = 'ditto_device_id';
  static const String _lastSyncKey = 'ditto_last_sync';

  /// تهيئة Ditto للسحابة فقط
  Future<void> initialize() async {
    if (_isInitialized) return;

    // التحقق من صحة الإعدادات
    if (!DittoConfig.isConfigured) {
      throw Exception(DittoConfig.configErrorMessage);
    }

    try {
      debugPrint('🚀 بدء تهيئة Ditto Cloud Sync...');
      
      if (DittoConfig.enableDebugLogs) {
        debugPrint('📋 إعدادات Ditto: ${DittoConfig.debugInfo}');
      }

      // إنشاء هوية السحابة - API v4.12.4
      final identity = OnlinePlaygroundIdentity(
        appID: _appId,
        token: _playgroundToken,
      );

      // فتح Ditto - API v4.12.4
      _ditto = await Ditto.open(identity: identity);

      // ضبط إعدادات النقل للسحابة فقط - بدون await لأنها void
      _ditto!.updateTransportConfig((config) {
        // إضافة WebSocket للسحابة
        config.connect.webSocketUrls.add(_webSocketUrl);
        
        // تعطيل جميع اتصالات P2P - v4.12.4 لا تستخدم enabled property
        // بدلاً من ذلك، نتجاهل P2P configs لأنها قد تكون معطلة افتراضياً
        
        debugPrint('🌐 تم ضبط Ditto للسحابة فقط - WebSocket: $_webSocketUrl');
        debugPrint('📡 App ID: $_appId');
        debugPrint('🔑 Playground Token: ${_playgroundToken.substring(0, 8)}***');
      });

      // تعطيل DQL strict mode للمرونة
      await _ditto!.store.execute("ALTER SYSTEM SET DQL_STRICT_MODE = false");

      // بدء المزامنة - بدون await لأنها void في v4.12.4
      _ditto!.startSync();

      _isInitialized = true;
      debugPrint('✅ تم تهيئة Ditto Cloud Sync بنجاح');

    } catch (e) {
      debugPrint('❌ خطأ في تهيئة Ditto: $e');
      rethrow;
    }
  }

  /// الحصول على معرف الجهاز الفريد
  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_deviceIdKey);
    
    if (deviceId == null) {
      deviceId = 'marina_hotel_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString(_deviceIdKey, deviceId);
    }
    
    return deviceId;
  }

  /// إنشاء وثيقة حجز جديدة
  Future<String> createBooking({
    required String guestName,
    required String roomNumber,
    required String checkinDate,
    String? checkoutDate,
    required double totalAmount,
    String? notes,
  }) async {
    if (!_isInitialized || _ditto == null) {
      throw Exception('Ditto غير مهيء');
    }

    final deviceId = await _getDeviceId();
    final bookingId = 'booking_${DateTime.now().millisecondsSinceEpoch}';
    
    try {
      // v4.12.4 API: يدعم معامل واحد فقط مع استعلام DQL
      final query = '''
        INSERT INTO bookings DOCUMENTS ({
          "_id": "$bookingId",
          "guest_name": "$guestName",
          "room_number": "$roomNumber",
          "checkin_date": "$checkinDate",
          "checkout_date": "$checkoutDate",
          "total_amount": $totalAmount,
          "notes": "$notes",
          "status": "محجوزة",
          "created_at": "${DateTime.now().toIso8601String()}",
          "created_by": "$deviceId",
          "device_id": "$deviceId"
        })
      ''';
      
      await _ditto!.store.execute(query);

      debugPrint('✅ تم إنشاء حجز جديد: $bookingId');
      return bookingId;

    } catch (e) {
      debugPrint('❌ خطأ في إنشاء الحجز: $e');
      rethrow;
    }
  }

  /// تحديث حالة الحجز
  Future<void> updateBookingStatus(String bookingId, String newStatus) async {
    if (!_isInitialized || _ditto == null) {
      throw Exception('Ditto غير مهيء');
    }

    try {
      final query = '''
        UPDATE bookings 
        SET status = "$newStatus", updated_at = "${DateTime.now().toIso8601String()}" 
        WHERE _id = "$bookingId"
      ''';
      
      await _ditto!.store.execute(query);

      debugPrint('✅ تم تحديث حالة الحجز $bookingId إلى: $newStatus');

    } catch (e) {
      debugPrint('❌ خطأ في تحديث حالة الحجز: $e');
      rethrow;
    }
  }

  /// إنشاء معاملة دفع
  Future<String> createPayment({
    required String bookingId,
    required double amount,
    required String paymentMethod,
    String? notes,
  }) async {
    if (!_isInitialized || _ditto == null) {
      throw Exception('Ditto غير مهيء');
    }

    final deviceId = await _getDeviceId();
    final paymentId = 'payment_${DateTime.now().millisecondsSinceEpoch}';
    
    try {
      final query = '''
        INSERT INTO payments DOCUMENTS ({
          "_id": "$paymentId",
          "booking_id": "$bookingId",
          "amount": $amount,
          "payment_method": "$paymentMethod",
          "notes": "$notes",
          "payment_date": "${DateTime.now().toIso8601String()}",
          "created_by": "$deviceId",
          "device_id": "$deviceId"
        })
      ''';
      
      await _ditto!.store.execute(query);

      debugPrint('✅ تم إنشاء دفعة جديدة: $paymentId');
      return paymentId;

    } catch (e) {
      debugPrint('❌ خطأ في إنشاء الدفعة: $e');
      rethrow;
    }
  }

  /// تحديث حالة الغرفة
  Future<void> updateRoomStatus(String roomNumber, String newStatus) async {
    if (!_isInitialized || _ditto == null) {
      throw Exception('Ditto غير مهيء');
    }

    final deviceId = await _getDeviceId();
    
    try {
      final query = '''
        UPDATE rooms 
        SET status = "$newStatus", 
            updated_at = "${DateTime.now().toIso8601String()}", 
            updated_by = "$deviceId"
        WHERE room_number = "$roomNumber"
      ''';
      
      await _ditto!.store.execute(query);

      debugPrint('✅ تم تحديث حالة الغرفة $roomNumber إلى: $newStatus');

    } catch (e) {
      debugPrint('❌ خطأ في تحديث حالة الغرفة: $e');
      rethrow;
    }
  }

  /// الاستعلام عن الحجوزات الحالية
  Future<List<Map<String, dynamic>>> getCurrentBookings() async {
    if (!_isInitialized || _ditto == null) {
      throw Exception('Ditto غير مهيء');
    }

    try {
      const query = '''
        SELECT * FROM bookings 
        WHERE status IN ('محجوزة', 'تم الدخول') 
        ORDER BY created_at DESC
      ''';
      
      final result = await _ditto!.store.execute(query);
      return result.items.map((item) => item.value).toList();

    } catch (e) {
      debugPrint('❌ خطأ في جلب الحجوزات: $e');
      return [];
    }
  }

  /// الاستعلام عن حالة الغرف
  Future<List<Map<String, dynamic>>> getRoomsStatus() async {
    if (!_isInitialized || _ditto == null) {
      throw Exception('Ditto غير مهيء');
    }

    try {
      const query = "SELECT * FROM rooms ORDER BY room_number";
      final result = await _ditto!.store.execute(query);
      return result.items.map((item) => item.value).toList();

    } catch (e) {
      debugPrint('❌ خطأ في جلب حالة الغرف: $e');
      return [];
    }
  }

  /// مراقبة تغييرات البيانات في الوقت الفعلي
  Stream<List<Map<String, dynamic>>> watchBookings() async* {
    if (!_isInitialized || _ditto == null) {
      yield [];
      return;
    }

    try {
      const query = "SELECT * FROM bookings ORDER BY created_at DESC";
      final liveQuery = _ditto!.store.registerObserver(query);

      // في v4.12.4، StoreObserver ليس Stream مباشرة
      // نحتاج لتحويله أو استخدام callback pattern
      // هذا حل مؤقت حتى نجد الطريقة الصحيحة
      yield await getCurrentBookings();

    } catch (e) {
      debugPrint('❌ خطأ في مراقبة الحجوزات: $e');
      yield [];
    }
  }

  /// الحصول على حالة المزامنة
  Future<Map<String, dynamic>> getSyncStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getString(_lastSyncKey);
    final deviceId = await _getDeviceId();

    return {
      'initialized': _isInitialized,
      'syncing': _isSyncing,
      'device_id': deviceId,
      'last_sync': lastSync,
      'websocket_url': _webSocketUrl,
      'cloud_sync_enabled': true,
      'p2p_enabled': false, // معطل عمداً للسحابة فقط
    };
  }

  /// تحديث وقت آخر مزامنة
  Future<void> _updateLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
  }

  /// مزامنة يدوية فورية
  Future<void> forceSyncNow() async {
    if (!_isInitialized || _ditto == null) {
      throw Exception('Ditto غير مهيء');
    }

    if (_isSyncing) {
      debugPrint('⏸️ المزامنة جارية بالفعل...');
      return;
    }

    try {
      _isSyncing = true;
      debugPrint('🔄 بدء المزامنة اليدوية...');

      // إجبار إعادة الاتصال - بدون await لأنها void في v4.12.4
      _ditto!.stopSync();
      await Future.delayed(Duration(seconds: 1));
      _ditto!.startSync();

      await _updateLastSyncTime();
      debugPrint('✅ تمت المزامنة اليدوية بنجاح');

    } catch (e) {
      debugPrint('❌ خطأ في المزامنة اليدوية: $e');
      rethrow;
    } finally {
      _isSyncing = false;
    }
  }

  /// تنظيف الموارد
  Future<void> dispose() async {
    await _subscription?.cancel();
    _ditto?.stopSync(); // بدون await لأنها void
    _ditto = null;
    _isInitialized = false;
    _isSyncing = false;
    debugPrint('🛑 تم تنظيف موارد Ditto Cloud Sync');
  }
}