import 'dart:async';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/mongodb_config.dart';
import '../models/guest_sync_model.dart';

class MongoDBSyncService {
  static MongoDBSyncService? _instance;
  Db? _db;
  DbCollection? _guestsCollection;
  DbCollection? _bookingsCollection;
  String? _deviceId;
  Timer? _syncTimer;
  final _storage = const FlutterSecureStorage();
  
  final _guestsStreamController = StreamController<List<GuestSync>>.broadcast();
  final _bookingsStreamController = StreamController<List<BookingSync>>.broadcast();
  
  Stream<List<GuestSync>> get guestsStream => _guestsStreamController.stream;
  Stream<List<BookingSync>> get bookingsStream => _bookingsStreamController.stream;

  MongoDBSyncService._();

  static MongoDBSyncService get instance {
    _instance ??= MongoDBSyncService._();
    return _instance!;
  }

  Future<void> initialize(String password) async {
    try {
      _deviceId = await _getDeviceId();
      
      final connectionString = MongoDBConfig.getConnectionString(password);
      _db = await Db.create(connectionString);
      await _db!.open();
      
      _guestsCollection = _db!.collection(MongoDBConfig.guestsCollection);
      _bookingsCollection = _db!.collection(MongoDBConfig.bookingsCollection);
      
      debugPrint('✅ تم الاتصال بـ MongoDB بنجاح');
      
      await _startRealtimeSync();
      
    } catch (e) {
      debugPrint('❌ خطأ في الاتصال بـ MongoDB: $e');
      rethrow;
    }
  }

  Future<String> _getDeviceId() async {
    String? savedId = await _storage.read(key: 'device_id');
    if (savedId != null) return savedId;

    final deviceInfo = DeviceInfoPlugin();
    String deviceId;

    try {
      final androidInfo = await deviceInfo.androidInfo;
      deviceId = androidInfo.id;
    } catch (e) {
      deviceId = DateTime.now().millisecondsSinceEpoch.toString();
    }

    await _storage.write(key: 'device_id', value: deviceId);
    return deviceId;
  }

  Future<void> _startRealtimeSync() async {
    _syncTimer?.cancel();
    
    _syncTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      await _fetchLatestGuests();
      await _fetchLatestBookings();
    });
    
    await _fetchLatestGuests();
    await _fetchLatestBookings();
  }

  Future<void> _fetchLatestGuests() async {
    try {
      final guests = await _guestsCollection!
          .find()
          .map((doc) => GuestSync.fromMongo(doc))
          .toList();
      
      _guestsStreamController.add(guests);
      debugPrint('📥 تم جلب ${guests.length} نزيل من MongoDB');
    } catch (e) {
      debugPrint('❌ خطأ في جلب النزلاء: $e');
    }
  }

  Future<void> _fetchLatestBookings() async {
    try {
      final bookings = await _bookingsCollection!
          .find()
          .map((doc) => BookingSync.fromMongo(doc))
          .toList();
      
      _bookingsStreamController.add(bookings);
      debugPrint('📥 تم جلب ${bookings.length} حجز من MongoDB');
    } catch (e) {
      debugPrint('❌ خطأ في جلب الحجوزات: $e');
    }
  }

  Future<void> syncGuest(GuestSync guest) async {
    try {
      final guestWithDevice = guest.copyWith(
        deviceId: _deviceId,
        updatedAt: DateTime.now(),
      );

      final existingGuest = await _guestsCollection!.findOne(
        where.eq('guest_id', guest.guestId),
      );

      if (existingGuest != null) {
        await _guestsCollection!.update(
          where.eq('guest_id', guest.guestId),
          guestWithDevice.toMongo(),
        );
        debugPrint('✅ تم تحديث النزيل: ${guest.fullName}');
      } else {
        await _guestsCollection!.insert(guestWithDevice.toMongo());
        debugPrint('✅ تم إضافة النزيل: ${guest.fullName}');
      }

      await _fetchLatestGuests();
    } catch (e) {
      debugPrint('❌ خطأ في مزامنة النزيل: $e');
      rethrow;
    }
  }

  Future<void> syncBooking(BookingSync booking) async {
    try {
      final bookingWithDevice = booking.copyWith(
        deviceId: _deviceId,
        updatedAt: DateTime.now(),
      );

      final existingBooking = await _bookingsCollection!.findOne(
        where.eq('booking_id', booking.bookingId),
      );

      if (existingBooking != null) {
        await _bookingsCollection!.update(
          where.eq('booking_id', booking.bookingId),
          bookingWithDevice.toMongo(),
        );
        debugPrint('✅ تم تحديث الحجز: ${booking.guestName}');
      } else {
        await _bookingsCollection!.insert(bookingWithDevice.toMongo());
        debugPrint('✅ تم إضافة الحجز: ${booking.guestName}');
      }

      await _fetchLatestBookings();
    } catch (e) {
      debugPrint('❌ خطأ في مزامنة الحجز: $e');
      rethrow;
    }
  }

  Future<List<GuestSync>> getAllGuests() async {
    try {
      final guests = await _guestsCollection!
          .find()
          .map((doc) => GuestSync.fromMongo(doc))
          .toList();
      return guests;
    } catch (e) {
      debugPrint('❌ خطأ في جلب جميع النزلاء: $e');
      return [];
    }
  }

  Future<List<BookingSync>> getAllBookings() async {
    try {
      final bookings = await _bookingsCollection!
          .find()
          .map((doc) => BookingSync.fromMongo(doc))
          .toList();
      return bookings;
    } catch (e) {
      debugPrint('❌ خطأ في جلب جميع الحجوزات: $e');
      return [];
    }
  }

  Future<void> deleteGuest(String guestId) async {
    try {
      await _guestsCollection!.remove(where.eq('guest_id', guestId));
      debugPrint('✅ تم حذف النزيل');
      await _fetchLatestGuests();
    } catch (e) {
      debugPrint('❌ خطأ في حذف النزيل: $e');
      rethrow;
    }
  }

  void dispose() {
    _syncTimer?.cancel();
    _guestsStreamController.close();
    _bookingsStreamController.close();
    _db?.close();
  }
}

extension BookingSyncExtension on BookingSync {
  BookingSync copyWith({
    ObjectId? id,
    String? bookingId,
    String? guestName,
    String? roomNumber,
    String? status,
    DateTime? checkInDate,
    DateTime? checkOutDate,
    double? totalAmount,
    double? paidAmount,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? deviceId,
  }) {
    return BookingSync(
      id: id ?? this.id,
      bookingId: bookingId ?? this.bookingId,
      guestName: guestName ?? this.guestName,
      roomNumber: roomNumber ?? this.roomNumber,
      status: status ?? this.status,
      checkInDate: checkInDate ?? this.checkInDate,
      checkOutDate: checkOutDate ?? this.checkOutDate,
      totalAmount: totalAmount ?? this.totalAmount,
      paidAmount: paidAmount ?? this.paidAmount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deviceId: deviceId ?? this.deviceId,
    );
  }
}
