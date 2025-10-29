import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/enhanced_payment_models.dart';
import '../services/firebase_realtime_database_service.dart';
import '../services/local_db.dart';

/// حالة Firebase Realtime Database
class FirebaseRealtimeState {
  final bool isInitialized;
  final bool isSyncing;
  final String? lastSyncTime;
  final String? errorMessage;
  final Map<String, int> statistics;

  const FirebaseRealtimeState({
    this.isInitialized = false,
    this.isSyncing = false,
    this.lastSyncTime,
    this.errorMessage,
    this.statistics = const {},
  });

  FirebaseRealtimeState copyWith({
    bool? isInitialized,
    bool? isSyncing,
    String? lastSyncTime,
    String? errorMessage,
    Map<String, int>? statistics,
  }) {
    return FirebaseRealtimeState(
      isInitialized: isInitialized ?? this.isInitialized,
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      errorMessage: errorMessage ?? this.errorMessage,
      statistics: statistics ?? this.statistics,
    );
  }
}

/// Provider لخدمة Firebase Realtime Database
final firebaseRealtimeDatabaseServiceProvider = Provider<FirebaseRealtimeDatabaseService>((ref) {
  return FirebaseRealtimeDatabaseService.instance;
});

/// Provider لحالة Firebase Realtime Database
final firebaseRealtimeStateProvider = StateNotifierProvider<FirebaseRealtimeNotifier, FirebaseRealtimeState>((ref) {
  final service = ref.watch(firebaseRealtimeDatabaseServiceProvider);
  return FirebaseRealtimeNotifier(service);
});

class FirebaseRealtimeNotifier extends StateNotifier<FirebaseRealtimeState> {
  final FirebaseRealtimeDatabaseService _service;

  FirebaseRealtimeNotifier(this._service) : super(const FirebaseRealtimeState()) {
    _initialize();
  }

  /// تهيئة Firebase
  Future<void> _initialize() async {
    try {
      await _service.initialize();
      state = state.copyWith(isInitialized: true);
      
      // بدء مراقبة الإحصائيات
      _startWatchingStatistics();
      
      debugPrint('✅ تم تهيئة Firebase Realtime Database بنجاح');
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'خطأ في تهيئة Firebase: ${e.toString()}',
      );
      debugPrint('❌ خطأ في تهيئة Firebase: $e');
    }
  }

  /// مراقبة الإحصائيات المباشرة
  void _startWatchingStatistics() {
    _service.watchHotelStatistics().listen(
      (stats) {
        state = state.copyWith(statistics: stats);
      },
      onError: (error) {
        debugPrint('❌ خطأ في مراقبة الإحصائيات: $error');
      },
    );
  }

  /// مزامنة جميع البيانات مع Firebase
  Future<void> syncAllData() async {
    if (!state.isInitialized) {
      state = state.copyWith(errorMessage: 'Firebase غير مُهيأ');
      return;
    }

    state = state.copyWith(isSyncing: true, errorMessage: null);

    try {
      await _service.syncAllDataToFirebase();
      state = state.copyWith(
        isSyncing: false,
        lastSyncTime: DateTime.now().toIso8601String(),
      );
      debugPrint('🚀 تم مزامنة جميع البيانات مع Firebase');
    } catch (e) {
      state = state.copyWith(
        isSyncing: false,
        errorMessage: 'خطأ في المزامنة: ${e.toString()}',
      );
      debugPrint('❌ خطأ في مزامنة البيانات: $e');
    }
  }

  /// إضافة غرفة مع التزامن التلقائي
  Future<void> addRoom(Room room) async {
    if (!state.isInitialized) return;

    try {
      // إضافة إلى قاعدة البيانات المحلية
      final db = getDatabase();
      await db.into(db.rooms).insert(room);
      
      // إضافة إلى Firebase
      await _service.addRoomToFirebase(room);
      
      // تسجيل النشاط
      await _service.logActivity('add_room', {
        'room_id': room.id,
        'room_number': room.roomNumber,
        'floor': room.floor,
      });
      
      debugPrint('✅ تم إضافة الغرفة ${room.roomNumber} محلياً وفي Firebase');
    } catch (e) {
      debugPrint('❌ خطأ في إضافة الغرفة: $e');
      rethrow;
    }
  }

  /// إضافة حجز مع التزامن التلقائي
  Future<void> addBooking(Booking booking) async {
    if (!state.isInitialized) return;

    try {
      // إضافة إلى قاعدة البيانات المحلية
      final db = getDatabase();
      await db.into(db.bookings).insert(booking);
      
      // إضافة إلى Firebase
      await _service.addBookingToFirebase(booking);
      
      // تسجيل النشاط
      await _service.logActivity('add_booking', {
        'booking_id': booking.id,
        'guest_name': booking.guestName,
        'room_id': booking.roomId,
        'check_in': booking.checkInDate.toIso8601String(),
      });
      
      debugPrint('✅ تم إضافة الحجز ${booking.id} محلياً وفي Firebase');
    } catch (e) {
      debugPrint('❌ خطأ في إضافة الحجز: $e');
      rethrow;
    }
  }

  /// إضافة دفعة مع التزامن التلقائي
  Future<void> addPayment(Payment payment) async {
    if (!state.isInitialized) return;

    try {
      // إضافة إلى قاعدة البيانات المحلية
      final db = getDatabase();
      await db.into(db.payments).insert(payment);
      
      // إضافة إلى Firebase
      await _service.addPaymentToFirebase(payment);
      
      // تسجيل النشاط
      await _service.logActivity('add_payment', {
        'payment_id': payment.id,
        'amount': payment.amount,
        'booking_id': payment.bookingId,
        'method': payment.paymentMethod,
      });
      
      debugPrint('✅ تم إضافة الدفعة ${payment.id} محلياً وفي Firebase');
    } catch (e) {
      debugPrint('❌ خطأ في إضافة الدفعة: $e');
      rethrow;
    }
  }

  /// تفعيل/إيقاف المراقبة المباشرة
  void toggleRealtimeMonitoring(bool enabled) {
    if (enabled) {
      _service.enableRealtimeMonitoring();
    } else {
      _service.disableRealtimeMonitoring();
    }
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}

/// Providers للبيانات المباشرة من Firebase
final firebaseRoomsStreamProvider = StreamProvider.autoDispose<List<Room>>((ref) {
  final service = ref.watch(firebaseRealtimeDatabaseServiceProvider);
  return service.watchRoomsChanges();
});

final firebaseBookingsStreamProvider = StreamProvider.autoDispose<List<Booking>>((ref) {
  final service = ref.watch(firebaseRealtimeDatabaseServiceProvider);
  return service.watchBookingsChanges();
});

final firebasePaymentsStreamProvider = StreamProvider.autoDispose<List<Payment>>((ref) {
  final service = ref.watch(firebaseRealtimeDatabaseServiceProvider);
  return service.watchPaymentsChanges();
});

final firebaseStatisticsStreamProvider = StreamProvider.autoDispose<Map<String, int>>((ref) {
  final service = ref.watch(firebaseRealtimeDatabaseServiceProvider);
  return service.watchHotelStatistics();
});

final firebaseActiveBookingsStreamProvider = StreamProvider.autoDispose<List<Booking>>((ref) {
  final service = ref.watch(firebaseRealtimeDatabaseServiceProvider);
  return service.watchActiveBookings();
});

/// Provider لمراقبة غرفة محددة
final firebaseRoomStreamProvider = StreamProvider.autoDispose.family<Room?, int>((ref, roomId) {
  final service = ref.watch(firebaseRealtimeDatabaseServiceProvider);
  return service.watchRoom(roomId);
});