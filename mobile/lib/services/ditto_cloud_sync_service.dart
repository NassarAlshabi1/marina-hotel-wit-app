import 'dart:async';
import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/ditto_config.dart';

/// خدمة Ditto للمزامنة السحابية فقط (v4.7.1 compatible)
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

      // إنشاء هوية السحابة - API v4.7.1
      final identity = OnlinePlaygroundIdentity(
        appId: _appId,
        token: _playgroundToken,
        enableDittoCloudSync: false, // حسب التوثيق
      );

      // فتح Ditto - API v4.7.1
      _ditto = await Ditto.open(identity: identity);

      // ضبط إعدادات النقل للسحابة فقط
      _ditto!.updateTransportConfig((config) {
        // إضافة WebSocket للسحابة
        config.connect.webSocketUrls.add(_webSocketUrl);
        
        // تعطيل جميع اتصالات P2P
        config.peerToPeer.lan.enabled = false;
        config.peerToPeer.awdl.enabled = false;
        
        // تعطيل TCP listening
        config.listen.tcp.enabled = false;
        config.listen.http.enabled = false;
        
        debugPrint('🌐 تم ضبط Ditto للسحابة فقط - WebSocket: $_webSocketUrl');
      });

      // تعطيل DQL strict mode للمرونة
      await _ditto!.store.execute("ALTER SYSTEM SET DQL_STRICT_MODE = false");

      // بدء المزامنة
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
      await _ditto!.store.execute('''
        INSERT INTO bookings DOCUMENTS (:booking)
      ''', {
        'booking': {
          '_id': bookingId,
          'guest_name': guestName,
          'room_number': roomNumber,
          'checkin_date': checkinDate,
          'checkout_date': checkoutDate,
          'total_amount': totalAmount,
          'notes': notes,
          'status': 'محجوزة',
          'created_at': DateTime.now().toIso8601String(),
          'created_by': deviceId,
          'device_id': deviceId,
        }
      });

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
      await _ditto!.store.execute('''
        UPDATE bookings 
        SET status = :status, updated_at = :updated_at 
        WHERE _id = :booking_id
      ''', {
        'status': newStatus,
        'updated_at': DateTime.now().toIso8601String(),
        'booking_id': bookingId,
      });

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
      await _ditto!.store.execute('''
        INSERT INTO payments DOCUMENTS (:payment)
      ''', {
        'payment': {
          '_id': paymentId,
          'booking_id': bookingId,
          'amount': amount,
          'payment_method': paymentMethod,
          'notes': notes,
          'payment_date': DateTime.now().toIso8601String(),
          'created_by': deviceId,
          'device_id': deviceId,
        }
      });

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
      await _ditto!.store.execute('''
        UPDATE rooms 
        SET status = :status, updated_at = :updated_at, updated_by = :updated_by
        WHERE room_number = :room_number
      ''', {
        'status': newStatus,
        'updated_at': DateTime.now().toIso8601String(),
        'updated_by': deviceId,
        'room_number': roomNumber,
      });

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
      final result = await _ditto!.store.execute('''
        SELECT * FROM bookings 
        WHERE status IN ('محجوزة', 'تم الدخول') 
        ORDER BY created_at DESC
      ''');

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
      final result = await _ditto!.store.execute('''
        SELECT * FROM rooms 
        ORDER BY room_number
      ''');

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
      final liveQuery = _ditto!.store.registerObserver('''
        SELECT * FROM bookings 
        ORDER BY created_at DESC
      ''');

      await for (final result in liveQuery) {
        yield result.items.map((item) => item.value).toList();
      }

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

      // إجبار إعادة الاتصال
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
    _ditto?.stopSync();
    _ditto = null;
    _isInitialized = false;
    _isSyncing = false;
    debugPrint('🛑 تم تنظيف موارد Ditto Cloud Sync');
  }
}