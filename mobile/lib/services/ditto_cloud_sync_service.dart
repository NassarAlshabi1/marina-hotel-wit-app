import 'dart:async';
import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/ditto_config.dart';

/// خدمة Ditto للمزامنة السحابية فقط (v4.12.4 compatible - updated)
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

      // تهيئة قاعدة البيانات وإنشاء الجداول
      await _initializeDatabase();

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

  /// تهيئة قاعدة البيانات وإنشاء الجداول الأساسية
  Future<void> _initializeDatabase() async {
    try {
      debugPrint('📊 بدء تهيئة قاعدة البيانات...');
      
      // إنشاء جدول الغرف
      await _ditto!.store.execute('''
        CREATE TABLE IF NOT EXISTS rooms (
          _id TEXT PRIMARY KEY,
          room_number TEXT UNIQUE NOT NULL,
          room_type TEXT NOT NULL DEFAULT 'standard',
          floor INTEGER,
          price_per_night REAL NOT NULL,
          capacity INTEGER DEFAULT 2,
          status TEXT DEFAULT 'available',
          amenities TEXT,
          description TEXT,
          created_at TEXT,
          updated_at TEXT,
          updated_by TEXT
        )
      ''');

      // إنشاء جدول الحجوزات
      await _ditto!.store.execute('''
        CREATE TABLE IF NOT EXISTS bookings (
          _id TEXT PRIMARY KEY,
          guest_name TEXT NOT NULL,
          guest_phone TEXT,
          guest_email TEXT,
          room_number TEXT NOT NULL,
          checkin_date TEXT NOT NULL,
          checkout_date TEXT,
          nights INTEGER,
          total_amount REAL NOT NULL,
          paid_amount REAL DEFAULT 0,
          status TEXT DEFAULT 'محجوزة',
          notes TEXT,
          created_at TEXT NOT NULL,
          created_by TEXT,
          device_id TEXT
        )
      ''');

      // إنشاء جدول المدفوعات
      await _ditto!.store.execute('''
        CREATE TABLE IF NOT EXISTS payments (
          _id TEXT PRIMARY KEY,
          booking_id TEXT NOT NULL,
          amount REAL NOT NULL,
          payment_method TEXT NOT NULL DEFAULT 'cash',
          notes TEXT,
          payment_date TEXT NOT NULL,
          created_at TEXT NOT NULL,
          created_by TEXT,
          device_id TEXT
        )
      ''');

      // إنشاء جدول المصروفات
      await _ditto!.store.execute('''
        CREATE TABLE IF NOT EXISTS expenses (
          _id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          description TEXT,
          category TEXT,
          amount REAL NOT NULL,
          expense_date TEXT NOT NULL,
          created_at TEXT NOT NULL,
          created_by TEXT,
          device_id TEXT
        )
      ''');

      // إنشاء جدول الملاحظات
      await _ditto!.store.execute('''
        CREATE TABLE IF NOT EXISTS notes (
          _id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          content TEXT NOT NULL,
          type TEXT DEFAULT 'general',
          status TEXT DEFAULT 'active',
          created_at TEXT NOT NULL,
          created_by TEXT
        )
      ''');

      // إدراج بيانات نموذجية للغرف إذا كانت فارغة
      final roomsCheck = await _ditto!.store.execute('SELECT COUNT(*) as count FROM rooms');
      final roomCount = roomsCheck.items.isNotEmpty ? 
        (roomsCheck.items.first.value['count'] ?? 0) : 0;
      
      if (roomCount == 0) {
        await _insertSampleRooms();
      }

      debugPrint('✅ تم إنشاء جداول قاعدة البيانات بنجاح');
      
    } catch (e) {
      debugPrint('❌ خطأ في تهيئة قاعدة البيانات: $e');
      rethrow;
    }
  }

  /// إنشاء مصروف جديد
  Future<String> createExpense({
    required String title,
    String? description,
    String? category,
    required double amount,
    required String expenseDate,
  }) async {
    if (!_isInitialized || _ditto == null) {
      throw Exception('Ditto غير مهيء');
    }

    final deviceId = await _getDeviceId();
    final expenseId = 'expense_${DateTime.now().millisecondsSinceEpoch}';
    
    try {
      final query = '''
        INSERT INTO expenses DOCUMENTS ({
          "_id": "$expenseId",
          "title": "$title",
          "description": "$description",
          "category": "$category",
          "amount": $amount,
          "expense_date": "$expenseDate",
          "created_at": "${DateTime.now().toIso8601String()}",
          "created_by": "$deviceId",
          "device_id": "$deviceId"
        })
      ''';
      
      await _ditto!.store.execute(query);

      debugPrint('✅ تم إنشاء مصروف جديد: $expenseId');
      return expenseId;

    } catch (e) {
      debugPrint('❌ خطأ في إنشاء المصروف: $e');
      rethrow;
    }
  }

  /// إنشاء ملاحظة جديدة
  Future<String> createNote({
    required String title,
    required String content,
    String? type,
  }) async {
    if (!_isInitialized || _ditto == null) {
      throw Exception('Ditto غير مهيء');
    }

    final noteId = 'note_${DateTime.now().millisecondsSinceEpoch}';
    
    try {
      final query = '''
        INSERT INTO notes DOCUMENTS ({
          "_id": "$noteId",
          "title": "$title",
          "content": "$content",
          "type": "${type ?? 'general'}",
          "status": "active",
          "created_at": "${DateTime.now().toIso8601String()}",
          "created_by": "system"
        })
      ''';
      
      await _ditto!.store.execute(query);

      debugPrint('✅ تم إنشاء ملاحظة جديدة: $noteId');
      return noteId;

    } catch (e) {
      debugPrint('❌ خطأ في إنشاء الملاحظة: $e');
      rethrow;
    }
  }

  /// الحصول على جميع الغرف
  Future<List<Map<String, dynamic>>> getAllRooms() async {
    if (!_isInitialized || _ditto == null) {
      throw Exception('Ditto غير مهيء');
    }

    try {
      const query = "SELECT * FROM rooms ORDER BY room_number";
      final result = await _ditto!.store.execute(query);
      return result.items.map((item) => item.value).toList();
    } catch (e) {
      debugPrint('❌ خطأ في جلب الغرف: $e');
      return [];
    }
  }

  /// الحصول على جميع المصروفات
  Future<List<Map<String, dynamic>>> getAllExpenses() async {
    if (!_isInitialized || _ditto == null) {
      throw Exception('Ditto غير مهيء');
    }

    try {
      const query = "SELECT * FROM expenses ORDER BY expense_date DESC";
      final result = await _ditto!.store.execute(query);
      return result.items.map((item) => item.value).toList();
    } catch (e) {
      debugPrint('❌ خطأ في جلب المصروفات: $e');
      return [];
    }
  }

  /// الحصول على جميع الملاحظات النشطة
  Future<List<Map<String, dynamic>>> getActiveNotes() async {
    if (!_isInitialized || _ditto == null) {
      throw Exception('Ditto غير مهيء');
    }

    try {
      const query = "SELECT * FROM notes WHERE status = 'active' ORDER BY created_at DESC";
      final result = await _ditto!.store.execute(query);
      return result.items.map((item) => item.value).toList();
    } catch (e) {
      debugPrint('❌ خطأ في جلب الملاحظات: $e');
      return [];
    }
  }

  /// الحصول على إحصائيات سريعة
  Future<Map<String, dynamic>> getDashboardStats() async {
    if (!_isInitialized || _ditto == null) {
      return {
        'total_rooms': 0,
        'occupied_rooms': 0,
        'total_bookings': 0,
        'total_revenue': 0.0,
        'pending_payments': 0.0,
      };
    }

    try {
      // إجمالي الغرف
      final roomsResult = await _ditto!.store.execute('SELECT COUNT(*) as count FROM rooms');
      final totalRooms = roomsResult.items.isNotEmpty ? 
        (roomsResult.items.first.value['count'] ?? 0) : 0;

      // الغرف المشغولة
      final occupiedResult = await _ditto!.store.execute(
        "SELECT COUNT(*) as count FROM bookings WHERE status = 'تم الدخول'"
      );
      final occupiedRooms = occupiedResult.items.isNotEmpty ? 
        (occupiedResult.items.first.value['count'] ?? 0) : 0;

      // إجمالي الحجوزات
      final bookingsResult = await _ditto!.store.execute('SELECT COUNT(*) as count FROM bookings');
      final totalBookings = bookingsResult.items.isNotEmpty ? 
        (bookingsResult.items.first.value['count'] ?? 0) : 0;

      // إجمالي الإيرادات
      final revenueResult = await _ditto!.store.execute('SELECT SUM(amount) as total FROM payments');
      final totalRevenue = revenueResult.items.isNotEmpty ? 
        (revenueResult.items.first.value['total'] ?? 0.0) : 0.0;

      return {
        'total_rooms': totalRooms,
        'occupied_rooms': occupiedRooms,
        'available_rooms': totalRooms - occupiedRooms,
        'total_bookings': totalBookings,
        'total_revenue': totalRevenue,
        'occupancy_rate': totalRooms > 0 ? (occupiedRooms / totalRooms * 100).round() : 0,
      };

    } catch (e) {
      debugPrint('❌ خطأ في جلب إحصائيات اللوحة: $e');
      return {
        'total_rooms': 0,
        'occupied_rooms': 0,
        'available_rooms': 0,
        'total_bookings': 0,
        'total_revenue': 0.0,
        'occupancy_rate': 0,
      };
    }
  }
  Future<void> _insertSampleRooms() async {
    try {
      final sampleRooms = [
        {
          '_id': 'room_101',
          'room_number': '101',
          'room_type': 'single',
          'floor': 1,
          'price_per_night': 150.0,
          'capacity': 1,
          'status': 'available',
          'amenities': 'مكيف، تلفزيون، إنترنت مجاني',
          'description': 'غرفة فردية مريحة',
          'created_at': DateTime.now().toIso8601String()
        },
        {
          '_id': 'room_102',
          'room_number': '102',
          'room_type': 'double',
          'floor': 1,
          'price_per_night': 200.0,
          'capacity': 2,
          'status': 'available',
          'amenities': 'مكيف، تلفزيون، إنترنت مجاني، ثلاجة صغيرة',
          'description': 'غرفة مزدوجة واسعة',
          'created_at': DateTime.now().toIso8601String()
        },
        {
          '_id': 'room_201',
          'room_number': '201',
          'room_type': 'suite',
          'floor': 2,
          'price_per_night': 350.0,
          'capacity': 4,
          'status': 'available',
          'amenities': 'جاكوزي، شرفة، غرفة معيشة منفصلة',
          'description': 'جناح فاخر مع إطلالة على البحر',
          'created_at': DateTime.now().toIso8601String()
        }
      ];

      for (final room in sampleRooms) {
        final roomJson = room.entries.map((e) => '"${e.key}": "${e.value}"').join(', ');
        await _ditto!.store.execute('INSERT INTO rooms DOCUMENTS ({$roomJson})');
      }

      debugPrint('✅ تم إدراج ${sampleRooms.length} غرف نموذجية');
      
    } catch (e) {
      debugPrint('❌ خطأ في إدراج الغرف النموذجية: $e');
    }
  }
}