import 'dart:async';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/mongodb_config.dart';
import '../models/guest_sync_model.dart';
import 'local_db.dart';
import 'repositories/bookings_repository.dart';

class FlutterMongoSyncService {
  static FlutterMongoSyncService? _instance;
  Db? _db;
  DbCollection? _guestsCollection;
  DbCollection? _bookingsCollection;
  String? _deviceId;
  Timer? _syncTimer;
  final _storage = const FlutterSecureStorage();
  final AppDatabase localDb;
  
  bool _isConnected = false;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  
  final _syncStatusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;

  FlutterMongoSyncService._(this.localDb);

  static FlutterMongoSyncService getInstance(AppDatabase db) {
    _instance ??= FlutterMongoSyncService._(db);
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
      
      await _guestsCollection!.createIndex(key: 'guest_id', unique: true);
      await _bookingsCollection!.createIndex(key: 'booking_id', unique: true);
      
      _isConnected = true;
      debugPrint('✅ Flutter: تم الاتصال بـ MongoDB بنجاح');
      
      await _storage.write(key: 'mongodb_password', value: password);
      
      _updateStatus(SyncStatus.connected);
      
    } catch (e) {
      _isConnected = false;
      debugPrint('❌ Flutter: خطأ في الاتصال بـ MongoDB: $e');
      _updateStatus(SyncStatus.error, message: e.toString());
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
      deviceId = 'flutter_${androidInfo.id}';
    } catch (e) {
      deviceId = 'flutter_${DateTime.now().millisecondsSinceEpoch}';
    }

    await _storage.write(key: 'device_id', value: deviceId);
    return deviceId;
  }

  void startAutoSync({Duration interval = const Duration(minutes: 1)}) {
    if (!_isConnected) {
      debugPrint('⚠️ غير متصل بـ MongoDB. لن يتم تفعيل المزامنة التلقائية.');
      return;
    }

    _syncTimer?.cancel();
    
    _syncTimer = Timer.periodic(interval, (timer) async {
      if (_isConnected && !_isSyncing) {
        await syncAll();
      }
    });
    
    debugPrint('✅ تم تفعيل المزامنة التلقائية كل ${interval.inMinutes} دقيقة');
  }

  void stopAutoSync() {
    _syncTimer?.cancel();
    debugPrint('⏹️ تم إيقاف المزامنة التلقائية');
  }

  Future<SyncResult> syncAll() async {
    if (!_isConnected) {
      return SyncResult(
        success: false,
        message: 'غير متصل بـ MongoDB',
      );
    }

    if (_isSyncing) {
      return SyncResult(
        success: false,
        message: 'المزامنة قيد التنفيذ بالفعل',
      );
    }

    _isSyncing = true;
    _updateStatus(SyncStatus.syncing);

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        throw Exception('لا يوجد اتصال بالإنترنت');
      }

      await _pushLocalDataToMongo();
      
      await _pullMongoDataToLocal();
      
      _lastSyncTime = DateTime.now();
      await _storage.write(
        key: 'last_sync_time',
        value: _lastSyncTime!.toIso8601String(),
      );

      _updateStatus(SyncStatus.connected);
      _isSyncing = false;

      debugPrint('✅ Flutter: المزامنة مكتملة بنجاح');
      
      return SyncResult(
        success: true,
        message: 'تمت المزامنة بنجاح',
        timestamp: _lastSyncTime!,
      );

    } catch (e) {
      _isSyncing = false;
      _updateStatus(SyncStatus.error, message: e.toString());
      debugPrint('❌ Flutter: خطأ في المزامنة: $e');
      
      return SyncResult(
        success: false,
        message: 'فشلت المزامنة: $e',
      );
    }
  }

  Future<void> _pushLocalDataToMongo() async {
    try {
      final guestsQuery = await localDb.select(localDb.guests).get();
      
      int pushedCount = 0;
      
      for (final guest in guestsQuery) {
        final guestSync = GuestSync(
          guestId: guest.id.toString(),
          fullName: guest.fullName,
          phone: guest.phone ?? '',
          email: guest.email,
          idNumber: guest.idNumber,
          nationality: guest.nationality,
          createdAt: guest.createdAt ?? DateTime.now(),
          updatedAt: DateTime.now(),
          deviceId: _deviceId!,
        );

        await _guestsCollection!.replaceOne(
          where.eq('guest_id', guestSync.guestId),
          guestSync.toMongo(),
          upsert: true,
        );
        
        pushedCount++;
      }

      debugPrint('📤 تم رفع $pushedCount نزيل إلى MongoDB');

      final bookingsRepo = BookingsRepository(localDb);
      final bookings = await bookingsRepo.getAllBookings();
      
      int pushedBookingsCount = 0;
      
      for (final booking in bookings) {
        final bookingSync = BookingSync(
          bookingId: booking.id.toString(),
          guestName: booking.guestName ?? 'غير محدد',
          roomNumber: booking.roomNumber ?? 'غير محدد',
          status: booking.status,
          checkInDate: booking.checkInDate,
          checkOutDate: booking.checkOutDate,
          totalAmount: booking.totalCost,
          paidAmount: booking.totalPayments,
          createdAt: booking.createdAt ?? DateTime.now(),
          updatedAt: DateTime.now(),
          deviceId: _deviceId!,
        );

        await _bookingsCollection!.replaceOne(
          where.eq('booking_id', bookingSync.bookingId),
          bookingSync.toMongo(),
          upsert: true,
        );
        
        pushedBookingsCount++;
      }

      debugPrint('📤 تم رفع $pushedBookingsCount حجز إلى MongoDB');

    } catch (e) {
      debugPrint('❌ خطأ في رفع البيانات: $e');
      rethrow;
    }
  }

  Future<void> _pullMongoDataToLocal() async {
    try {
      final mongoGuests = await _guestsCollection!
          .find()
          .map((doc) => GuestSync.fromMongo(doc))
          .toList();

      int pulledCount = 0;

      for (final guestSync in mongoGuests) {
        if (guestSync.deviceId != _deviceId) {
          final existingGuest = await (localDb.select(localDb.guests)
                ..where((g) => g.phone.equals(guestSync.phone)))
              .getSingleOrNull();

          if (existingGuest == null) {
            await localDb.into(localDb.guests).insert(
              GuestsCompanion.insert(
                fullName: guestSync.fullName,
                phone: d.Value(guestSync.phone),
                email: d.Value(guestSync.email),
                idNumber: d.Value(guestSync.idNumber),
                nationality: d.Value(guestSync.nationality),
                createdAt: d.Value(guestSync.createdAt),
              ),
            );
            
            pulledCount++;
          } else {
            final mongoUpdateTime = guestSync.updatedAt;
            final localUpdateTime = existingGuest.updatedAt ?? existingGuest.createdAt ?? DateTime(2000);

            if (mongoUpdateTime.isAfter(localUpdateTime)) {
              await (localDb.update(localDb.guests)
                    ..where((g) => g.id.equals(existingGuest.id)))
                  .write(
                GuestsCompanion(
                  fullName: d.Value(guestSync.fullName),
                  phone: d.Value(guestSync.phone),
                  email: d.Value(guestSync.email),
                  idNumber: d.Value(guestSync.idNumber),
                  nationality: d.Value(guestSync.nationality),
                  updatedAt: d.Value(DateTime.now()),
                ),
              );
              
              pulledCount++;
            }
          }
        }
      }

      debugPrint('📥 تم جلب وتحديث $pulledCount نزيل من MongoDB');

    } catch (e) {
      debugPrint('❌ خطأ في جلب البيانات: $e');
      rethrow;
    }
  }

  void _updateStatus(SyncStatus status, {String? message}) {
    _syncStatusController.add(status.copyWith(
      lastSync: _lastSyncTime,
      message: message,
    ));
  }

  Future<Map<String, dynamic>> getStats() async {
    try {
      final localGuestsCount = await localDb.select(localDb.guests).get().then((list) => list.length);
      final mongoGuestsCount = await _guestsCollection?.countDocuments() ?? 0;
      
      final lastSyncStr = await _storage.read(key: 'last_sync_time');
      final lastSync = lastSyncStr != null ? DateTime.parse(lastSyncStr) : null;

      return {
        'local_guests': localGuestsCount,
        'mongo_guests': mongoGuestsCount,
        'last_sync': lastSync?.toIso8601String() ?? 'لم تتم المزامنة بعد',
        'is_connected': _isConnected,
        'device_id': _deviceId,
      };
    } catch (e) {
      return {
        'error': e.toString(),
      };
    }
  }

  void dispose() {
    _syncTimer?.cancel();
    _syncStatusController.close();
    _db?.close();
  }
}

class SyncStatus {
  final String status;
  final String? message;
  final DateTime? lastSync;

  const SyncStatus({
    required this.status,
    this.message,
    this.lastSync,
  });

  static const connected = SyncStatus(status: 'connected');
  static const disconnected = SyncStatus(status: 'disconnected');
  static const syncing = SyncStatus(status: 'syncing');
  static const error = SyncStatus(status: 'error');

  SyncStatus copyWith({
    String? status,
    String? message,
    DateTime? lastSync,
  }) {
    return SyncStatus(
      status: status ?? this.status,
      message: message ?? this.message,
      lastSync: lastSync ?? this.lastSync,
    );
  }
}

class SyncResult {
  final bool success;
  final String message;
  final DateTime? timestamp;

  SyncResult({
    required this.success,
    required this.message,
    this.timestamp,
  });
}
