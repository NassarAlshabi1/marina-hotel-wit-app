import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/enhanced_payment_models.dart';
import 'local_db.dart';
import 'providers.dart';

/// خدمة Firebase Realtime Database للتزامن الفوري والتتبع المباشر
class FirebaseRealtimeDatabaseService {
  static const String _hotelDataPath = 'marina_hotel_data';
  static const String _roomsPath = '$_hotelDataPath/rooms';
  static const String _bookingsPath = '$_hotelDataPath/bookings';
  static const String _paymentsPath = '$_hotelDataPath/payments';
  static const String _expensesPath = '$_hotelDataPath/expenses';
  static const String _employeesPath = '$_hotelDataPath/employees';
  static const String _cashTransactionsPath = '$_hotelDataPath/cash_transactions';
  static const String _syncStatePath = '$_hotelDataPath/sync_state';
  
  static FirebaseRealtimeDatabaseService? _instance;
  static FirebaseRealtimeDatabaseService get instance {
    _instance ??= FirebaseRealtimeDatabaseService._internal();
    return _instance!;
  }
  
  FirebaseRealtimeDatabaseService._internal();

  FirebaseDatabase? _database;
  final List<StreamSubscription> _subscriptions = [];
  
  /// تهيئة Firebase Database
  Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
      _database = FirebaseDatabase.instance;
      
      // تكوين Firebase للعمل في وضع Offline
      _database!.setPersistenceEnabled(true);
      _database!.setPersistenceCacheSizeBytes(10000000); // 10MB cache
      
      debugPrint('✅ تم تهيئة Firebase Realtime Database');
    } catch (e) {
      debugPrint('❌ خطأ في تهيئة Firebase Database: $e');
      rethrow;
    }
  }

  /// رفع الغرف إلى Firebase
  Future<void> syncRoomsToFirebase(List<Room> rooms) async {
    if (_database == null) return;
    
    try {
      final roomsRef = _database!.ref(_roomsPath);
      final Map<String, dynamic> roomsData = {};
      
      for (final room in rooms) {
        roomsData[room.id.toString()] = room.toJson();
      }
      
      await roomsRef.set(roomsData);
      debugPrint('✅ تم رفع ${rooms.length} غرفة إلى Firebase');
    } catch (e) {
      debugPrint('❌ خطأ في رفع الغرف إلى Firebase: $e');
    }
  }

  /// رفع الحجوزات إلى Firebase
  Future<void> syncBookingsToFirebase(List<Booking> bookings) async {
    if (_database == null) return;
    
    try {
      final bookingsRef = _database!.ref(_bookingsPath);
      final Map<String, dynamic> bookingsData = {};
      
      for (final booking in bookings) {
        bookingsData[booking.id.toString()] = booking.toJson();
      }
      
      await bookingsRef.set(bookingsData);
      debugPrint('✅ تم رفع ${bookings.length} حجز إلى Firebase');
    } catch (e) {
      debugPrint('❌ خطأ في رفع الحجوزات إلى Firebase: $e');
    }
  }

  /// رفع المدفوعات إلى Firebase
  Future<void> syncPaymentsToFirebase(List<Payment> payments) async {
    if (_database == null) return;
    
    try {
      final paymentsRef = _database!.ref(_paymentsPath);
      final Map<String, dynamic> paymentsData = {};
      
      for (final payment in payments) {
        paymentsData[payment.id.toString()] = payment.toJson();
      }
      
      await paymentsRef.set(paymentsData);
      debugPrint('✅ تم رفع ${payments.length} دفعة إلى Firebase');
    } catch (e) {
      debugPrint('❌ خطأ في رفع المدفوعات إلى Firebase: $e');
    }
  }

  /// رفع المصروفات إلى Firebase
  Future<void> syncExpensesToFirebase(List<Expense> expenses) async {
    if (_database == null) return;
    
    try {
      final expensesRef = _database!.ref(_expensesPath);
      final Map<String, dynamic> expensesData = {};
      
      for (final expense in expenses) {
        expensesData[expense.id.toString()] = expense.toJson();
      }
      
      await expensesRef.set(expensesData);
      debugPrint('✅ تم رفع ${expenses.length} مصروف إلى Firebase');
    } catch (e) {
      debugPrint('❌ خطأ في رفع المصروفات إلى Firebase: $e');
    }
  }

  /// رفع الموظفين إلى Firebase
  Future<void> syncEmployeesToFirebase(List<Employee> employees) async {
    if (_database == null) return;
    
    try {
      final employeesRef = _database!.ref(_employeesPath);
      final Map<String, dynamic> employeesData = {};
      
      for (final employee in employees) {
        employeesData[employee.id.toString()] = employee.toJson();
      }
      
      await employeesRef.set(employeesData);
      debugPrint('✅ تم رفع ${employees.length} موظف إلى Firebase');
    } catch (e) {
      debugPrint('❌ خطأ في رفع الموظفين إلى Firebase: $e');
    }
  }

  /// رفع المعاملات النقدية إلى Firebase
  Future<void> syncCashTransactionsToFirebase(List<CashTransaction> transactions) async {
    if (_database == null) return;
    
    try {
      final transactionsRef = _database!.ref(_cashTransactionsPath);
      final Map<String, dynamic> transactionsData = {};
      
      for (final transaction in transactions) {
        transactionsData[transaction.id.toString()] = transaction.toJson();
      }
      
      await transactionsRef.set(transactionsData);
      debugPrint('✅ تم رفع ${transactions.length} معاملة نقدية إلى Firebase');
    } catch (e) {
      debugPrint('❌ خطأ في رفع المعاملات النقدية إلى Firebase: $e');
    }
  }

  /// رفع جميع البيانات إلى Firebase
  Future<void> syncAllDataToFirebase() async {
    if (_database == null) {
      await initialize();
    }

    try {
      final db = getDatabase();

      // جلب جميع البيانات من قاعدة البيانات المحلية
      final rooms = await db.select(db.rooms).get();
      final bookings = await db.select(db.bookings).get();
      final payments = await db.select(db.payments).get();
      final expenses = await db.select(db.expenses).get();
      final employees = await db.select(db.employees).get();
      final cashTransactions = await db.select(db.cashTransactions).get();

      // رفع البيانات بالتوازي لتحسين الأداء
      await Future.wait([
        syncRoomsToFirebase(rooms),
        syncBookingsToFirebase(bookings),
        syncPaymentsToFirebase(payments),
        syncExpensesToFirebase(expenses),
        syncEmployeesToFirebase(employees),
        syncCashTransactionsToFirebase(cashTransactions),
      ]);

      // تحديث حالة التزامن
      await updateLastSyncTime();
      
      debugPrint('🚀 تم رفع جميع البيانات إلى Firebase بنجاح');
    } catch (e) {
      debugPrint('❌ خطأ في رفع البيانات إلى Firebase: $e');
      rethrow;
    }
  }

  /// تحديث وقت آخر تزامن
  Future<void> updateLastSyncTime() async {
    if (_database == null) return;
    
    try {
      final syncRef = _database!.ref(_syncStatePath);
      await syncRef.set({
        'last_sync_timestamp': DateTime.now().toIso8601String(),
        'device_info': 'Mobile App',
        'sync_version': '1.2.0+3',
      });
    } catch (e) {
      debugPrint('❌ خطأ في تحديث حالة التزامن: $e');
    }
  }

  /// الاستماع للتغييرات في الغرف
  Stream<List<Room>> watchRoomsChanges() {
    if (_database == null) throw Exception('Firebase لم يتم تهيئته');
    
    return _database!.ref(_roomsPath).onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return <Room>[];
      
      return data.values
          .map((roomData) => Room.fromJson(Map<String, dynamic>.from(roomData)))
          .toList();
    });
  }

  /// الاستماع للتغييرات في الحجوزات
  Stream<List<Booking>> watchBookingsChanges() {
    if (_database == null) throw Exception('Firebase لم يتم تهيئته');
    
    return _database!.ref(_bookingsPath).onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return <Booking>[];
      
      return data.values
          .map((bookingData) => Booking.fromJson(Map<String, dynamic>.from(bookingData)))
          .toList();
    });
  }

  /// الاستماع للتغييرات في المدفوعات
  Stream<List<Payment>> watchPaymentsChanges() {
    if (_database == null) throw Exception('Firebase لم يتم تهيئته');
    
    return _database!.ref(_paymentsPath).onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return <Payment>[];
      
      return data.values
          .map((paymentData) => Payment.fromJson(Map<String, dynamic>.from(paymentData)))
          .toList();
    });
  }

  /// إضافة غرفة جديدة إلى Firebase
  Future<void> addRoomToFirebase(Room room) async {
    if (_database == null) return;
    
    try {
      final roomRef = _database!.ref('$_roomsPath/${room.id}');
      await roomRef.set(room.toJson());
      debugPrint('✅ تم إضافة غرفة ${room.roomNumber} إلى Firebase');
    } catch (e) {
      debugPrint('❌ خطأ في إضافة الغرفة إلى Firebase: $e');
    }
  }

  /// إضافة حجز جديد إلى Firebase
  Future<void> addBookingToFirebase(Booking booking) async {
    if (_database == null) return;
    
    try {
      final bookingRef = _database!.ref('$_bookingsPath/${booking.id}');
      await bookingRef.set(booking.toJson());
      debugPrint('✅ تم إضافة حجز ${booking.id} إلى Firebase');
    } catch (e) {
      debugPrint('❌ خطأ في إضافة الحجز إلى Firebase: $e');
    }
  }

  /// إضافة دفعة جديدة إلى Firebase
  Future<void> addPaymentToFirebase(Payment payment) async {
    if (_database == null) return;
    
    try {
      final paymentRef = _database!.ref('$_paymentsPath/${payment.id}');
      await paymentRef.set(payment.toJson());
      debugPrint('✅ تم إضافة دفعة ${payment.id} إلى Firebase');
    } catch (e) {
      debugPrint('❌ خطأ في إضافة الدفعة إلى Firebase: $e');
    }
  }

  /// حذف عنصر من Firebase
  Future<void> deleteFromFirebase(String path, String id) async {
    if (_database == null) return;
    
    try {
      final ref = _database!.ref('$path/$id');
      await ref.remove();
      debugPrint('✅ تم حذف $id من Firebase');
    } catch (e) {
      debugPrint('❌ خطأ في الحذف من Firebase: $e');
    }
  }

  /// تحديث عنصر في Firebase
  Future<void> updateInFirebase(String path, String id, Map<String, dynamic> data) async {
    if (_database == null) return;
    
    try {
      final ref = _database!.ref('$path/$id');
      await ref.update(data);
      debugPrint('✅ تم تحديث $id في Firebase');
    } catch (e) {
      debugPrint('❌ خطأ في التحديث في Firebase: $e');
    }
  }

  /// جلب إحصائيات مباشرة من Firebase
  Stream<Map<String, int>> watchHotelStatistics() {
    if (_database == null) throw Exception('Firebase لم يتم تهيئته');
    
    return _database!.ref(_hotelDataPath).onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) {
        return <String, int>{
          'total_rooms': 0,
          'total_bookings': 0,
          'total_payments': 0,
          'total_expenses': 0,
        };
      }
      
      return <String, int>{
        'total_rooms': (data['rooms'] as Map?)?.length ?? 0,
        'total_bookings': (data['bookings'] as Map?)?.length ?? 0,
        'total_payments': (data['payments'] as Map?)?.length ?? 0,
        'total_expenses': (data['expenses'] as Map?)?.length ?? 0,
      };
    });
  }

  /// البحث في البيانات باستخدام Firebase Query
  Future<List<Booking>> searchBookingsByDateRange(DateTime startDate, DateTime endDate) async {
    if (_database == null) throw Exception('Firebase لم يتم تهيئته');
    
    try {
      final bookingsRef = _database!.ref(_bookingsPath);
      final snapshot = await bookingsRef
          .orderByChild('check_in_date')
          .startAt(startDate.toIso8601String())
          .endAt(endDate.toIso8601String())
          .get();

      if (!snapshot.exists) return [];
      
      final data = snapshot.value as Map<dynamic, dynamic>;
      return data.values
          .map((bookingData) => Booking.fromJson(Map<String, dynamic>.from(bookingData)))
          .toList();
    } catch (e) {
      debugPrint('❌ خطأ في البحث في الحجوزات: $e');
      return [];
    }
  }

  /// البحث في المدفوعات حسب النوع
  Future<List<Payment>> getPaymentsByType(String paymentType) async {
    if (_database == null) throw Exception('Firebase لم يتم تهيئته');
    
    try {
      final paymentsRef = _database!.ref(_paymentsPath);
      final snapshot = await paymentsRef
          .orderByChild('payment_method')
          .equalTo(paymentType)
          .get();

      if (!snapshot.exists) return [];
      
      final data = snapshot.value as Map<dynamic, dynamic>;
      return data.values
          .map((paymentData) => Payment.fromJson(Map<String, dynamic>.from(paymentData)))
          .toList();
    } catch (e) {
      debugPrint('❌ خطأ في جلب المدفوعات: $e');
      return [];
    }
  }

  /// مراقبة التغييرات المباشرة لغرفة محددة
  Stream<Room?> watchRoom(int roomId) {
    if (_database == null) throw Exception('Firebase لم يتم تهيئته');
    
    return _database!.ref('$_roomsPath/$roomId').onValue.map((event) {
      if (!event.snapshot.exists) return null;
      
      final data = Map<String, dynamic>.from(event.snapshot.value as Map);
      return Room.fromJson(data);
    });
  }

  /// مراقبة التغييرات المباشرة للحجوزات النشطة
  Stream<List<Booking>> watchActiveBookings() {
    if (_database == null) throw Exception('Firebase لم يتم تهيئته');
    
    return _database!.ref(_bookingsPath).onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return <Booking>[];
      
      final activeBookings = <Booking>[];
      for (final bookingData in data.values) {
        final booking = Booking.fromJson(Map<String, dynamic>.from(bookingData));
        // فقط الحجوزات غير المكتملة
        if (booking.status != 'completed' && booking.status != 'cancelled') {
          activeBookings.add(booking);
        }
      }
      
      return activeBookings;
    });
  }

  /// حفظ log للعمليات المهمة
  Future<void> logActivity(String action, Map<String, dynamic> details) async {
    if (_database == null) return;
    
    try {
      final logsRef = _database!.ref('$_hotelDataPath/activity_logs').push();
      await logsRef.set({
        'timestamp': DateTime.now().toIso8601String(),
        'action': action,
        'details': details,
        'device_type': 'mobile',
      });
    } catch (e) {
      debugPrint('❌ خطأ في حفظ log النشاط: $e');
    }
  }

  /// تفعيل المراقبة المباشرة للبيانات الحرجة
  void enableRealtimeMonitoring() {
    if (_database == null) return;
    
    // مراقبة الحجوزات الجديدة
    final newBookingsSubscription = _database!
        .ref(_bookingsPath)
        .onChildAdded
        .listen((event) {
      debugPrint('🔔 حجز جديد تم إضافته: ${event.snapshot.key}');
    });
    
    // مراقبة المدفوعات الجديدة
    final newPaymentsSubscription = _database!
        .ref(_paymentsPath)
        .onChildAdded
        .listen((event) {
      debugPrint('💰 دفعة جديدة تمت: ${event.snapshot.key}');
    });
    
    _subscriptions.addAll([newBookingsSubscription, newPaymentsSubscription]);
  }

  /// إيقاف المراقبة المباشرة
  void disableRealtimeMonitoring() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    debugPrint('⏹️ تم إيقاف المراقبة المباشرة');
  }

  /// إعداد قواعد الأمان (للمرجع - يجب تطبيقها في Firebase Console)
  static String get securityRulesExample => '''
{
  "rules": {
    "marina_hotel_data": {
      ".read": "auth != null",
      ".write": "auth != null",
      "rooms": {
        ".indexOn": ["floor", "status", "room_number"]
      },
      "bookings": {
        ".indexOn": ["check_in_date", "check_out_date", "status", "guest_name"]
      },
      "payments": {
        ".indexOn": ["payment_date", "payment_method", "booking_id"]
      }
    }
  }
}
''';

  /// تنظيف الموارد
  void dispose() {
    disableRealtimeMonitoring();
    _instance = null;
  }
}