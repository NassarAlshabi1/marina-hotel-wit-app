import 'package:flutter/foundation.dart';
import 'package:ditto/ditto.dart';
import 'ditto_cloud_sync_service.dart';
import 'ditto_schema_mapper.dart';
import 'local_db.dart';

/// خدمة المزامنة الثنائية بين Ditto Cloud وقاعدة البيانات المحلية
/// 
/// تدير هذه الخدمة:
/// - رفع التغييرات المحلية إلى Ditto
/// - تنزيل التغييرات من Ditto إلى القاعدة المحلية
/// - حل التعارضات
/// - المزامنة في الوقت الفعلي
class DittoLocalSyncService {
  static final DittoLocalSyncService _instance = DittoLocalSyncService._internal();
  factory DittoLocalSyncService() => _instance;
  DittoLocalSyncService._internal();

  final _dittoService = DittoCloudSyncService();
  AppDatabase? _database;
  
  bool _isInitialized = false;
  bool _isSyncing = false;

  /// تهيئة خدمة المزامنة
  Future<bool> initialize(AppDatabase database) async {
    try {
      _database = database;
      
      // تهيئة Ditto
      final dittoInitialized = await _dittoService.initialize();
      if (!dittoInitialized) {
        debugPrint('❌ فشل في تهيئة Ditto');
        return false;
      }

      _isInitialized = true;
      debugPrint('✅ تم تهيئة خدمة المزامنة بنجاح');
      return true;
      
    } catch (e) {
      debugPrint('❌ خطأ في تهيئة خدمة المزامنة: $e');
      return false;
    }
  }

  /// مزامنة كاملة - رفع وتنزيل جميع البيانات
  Future<bool> fullSync() async {
    if (!_isInitialized || _database == null) {
      debugPrint('❌ خدمة المزامنة غير مهيئة');
      return false;
    }

    if (_isSyncing) {
      debugPrint('⚠️ المزامنة قيد التنفيذ بالفعل');
      return false;
    }

    _isSyncing = true;
    debugPrint('🔄 بدء المزامنة الكاملة...');

    try {
      // 1. رفع البيانات المحلية إلى Ditto
      await _pushLocalDataToDitto();
      
      // 2. تنزيل البيانات من Ditto إلى القاعدة المحلية
      await _pullDittoDataToLocal();
      
      debugPrint('✅ اكتملت المزامنة الكاملة بنجاح');
      return true;
      
    } catch (e) {
      debugPrint('❌ خطأ في المزامنة الكاملة: $e');
      return false;
    } finally {
      _isSyncing = false;
    }
  }

  /// رفع البيانات المحلية إلى Ditto
  Future<void> _pushLocalDataToDitto() async {
    debugPrint('📤 رفع البيانات المحلية إلى Ditto...');

    try {
      // مزامنة الغرف
      await _pushRoomsToDitto();
      
      // مزامنة الحجوزات
      await _pushBookingsToDitto();
      
      // مزامنة الموظفين
      await _pushEmployeesToDitto();
      
      // مزامنة المدفوعات
      await _pushPaymentsToDitto();
      
      // يمكن إضافة المزيد من الجداول هنا
      
      debugPrint('✅ تم رفع البيانات المحلية بنجاح');
      
    } catch (e) {
      debugPrint('❌ خطأ في رفع البيانات: $e');
      rethrow;
    }
  }

  /// رفع الغرف إلى Ditto
  Future<void> _pushRoomsToDitto() async {
    try {
      final rooms = await _database!.roomsDao.watchAll().first;
      final ditto = _dittoService._ditto;
      
      if (ditto == null) return;
      
      final collection = ditto.store.collection(DittoSchemaMapper.roomsCollection);
      
      for (final room in rooms) {
        final dittoDoc = DittoSchemaMapper.roomToDitto(room);
        await collection.upsert(dittoDoc);
      }
      
      debugPrint('✅ تم رفع ${rooms.length} غرفة إلى Ditto');
      
    } catch (e) {
      debugPrint('❌ خطأ في رفع الغرف: $e');
    }
  }

  /// رفع الحجوزات إلى Ditto
  Future<void> _pushBookingsToDitto() async {
    try {
      final bookings = await _database!.bookingsDao.watchAll().first;
      final ditto = _dittoService._ditto;
      
      if (ditto == null) return;
      
      final collection = ditto.store.collection(DittoSchemaMapper.bookingsCollection);
      
      for (final booking in bookings) {
        final dittoDoc = DittoSchemaMapper.bookingToDitto(booking);
        await collection.upsert(dittoDoc);
      }
      
      debugPrint('✅ تم رفع ${bookings.length} حجز إلى Ditto');
      
    } catch (e) {
      debugPrint('❌ خطأ في رفع الحجوزات: $e');
    }
  }

  /// رفع الموظفين إلى Ditto
  Future<void> _pushEmployeesToDitto() async {
    try {
      final employees = await _database!.employeesDao.watchAll().first;
      final ditto = _dittoService._ditto;
      
      if (ditto == null) return;
      
      final collection = ditto.store.collection(DittoSchemaMapper.employeesCollection);
      
      for (final employee in employees) {
        final dittoDoc = DittoSchemaMapper.employeeToDitto(employee);
        await collection.upsert(dittoDoc);
      }
      
      debugPrint('✅ تم رفع ${employees.length} موظف إلى Ditto');
      
    } catch (e) {
      debugPrint('❌ خطأ في رفع الموظفين: $e');
    }
  }

  /// رفع المدفوعات إلى Ditto
  Future<void> _pushPaymentsToDitto() async {
    try {
      final payments = await _database!.paymentsDao.watchAll().first;
      final ditto = _dittoService._ditto;
      
      if (ditto == null) return;
      
      final collection = ditto.store.collection(DittoSchemaMapper.paymentsCollection);
      
      for (final payment in payments) {
        final dittoDoc = DittoSchemaMapper.paymentToDitto(payment);
        await collection.upsert(dittoDoc);
      }
      
      debugPrint('✅ تم رفع ${payments.length} مدفوعة إلى Ditto');
      
    } catch (e) {
      debugPrint('❌ خطأ في رفع المدفوعات: $e');
    }
  }

  /// تنزيل البيانات من Ditto إلى القاعدة المحلية
  Future<void> _pullDittoDataToLocal() async {
    debugPrint('📥 تنزيل البيانات من Ditto...');

    try {
      // تنزيل الغرف
      await _pullRoomsFromDitto();
      
      // تنزيل الحجوزات
      await _pullBookingsFromDitto();
      
      // تنزيل الموظفين
      await _pullEmployeesFromDitto();
      
      // تنزيل المدفوعات
      await _pullPaymentsFromDitto();
      
      debugPrint('✅ تم تنزيل البيانات من Ditto بنجاح');
      
    } catch (e) {
      debugPrint('❌ خطأ في تنزيل البيانات: $e');
      rethrow;
    }
  }

  /// تنزيل الغرف من Ditto
  Future<void> _pullRoomsFromDitto() async {
    try {
      final ditto = _dittoService._ditto;
      if (ditto == null) return;
      
      final collection = ditto.store.collection(DittoSchemaMapper.roomsCollection);
      final docs = await collection.findAll().exec();
      
      for (final doc in docs) {
        final data = doc.value;
        
        // التحقق من صحة البيانات
        if (!DittoSchemaMapper.validateDittoDocument(data, 'rooms')) {
          continue;
        }
        
        // تحويل إلى Drift Companion
        final roomCompanion = DittoSchemaMapper.dittoToRoomCompanion(data);
        
        // إدراج أو تحديث في القاعدة المحلية
        try {
          await _database!.into(_database!.rooms).insert(
            roomCompanion,
            mode: InsertMode.insertOrReplace,
          );
        } catch (e) {
          debugPrint('⚠️ خطأ في إدراج الغرفة: $e');
        }
      }
      
      debugPrint('✅ تم تنزيل ${docs.length} غرفة من Ditto');
      
    } catch (e) {
      debugPrint('❌ خطأ في تنزيل الغرف: $e');
    }
  }

  /// تنزيل الحجوزات من Ditto (مثال مبسط)
  Future<void> _pullBookingsFromDitto() async {
    try {
      final ditto = _dittoService._ditto;
      if (ditto == null) return;
      
      final collection = ditto.store.collection(DittoSchemaMapper.bookingsCollection);
      final docs = await collection.findAll().exec();
      
      debugPrint('✅ تم تنزيل ${docs.length} حجز من Ditto');
      
      // TODO: تحويل وإدراج الحجوزات في القاعدة المحلية
      
    } catch (e) {
      debugPrint('❌ خطأ في تنزيل الحجوزات: $e');
    }
  }

  /// تنزيل الموظفين من Ditto (مثال مبسط)
  Future<void> _pullEmployeesFromDitto() async {
    try {
      final ditto = _dittoService._ditto;
      if (ditto == null) return;
      
      final collection = ditto.store.collection(DittoSchemaMapper.employeesCollection);
      final docs = await collection.findAll().exec();
      
      debugPrint('✅ تم تنزيل ${docs.length} موظف من Ditto');
      
      // TODO: تحويل وإدراج الموظفين في القاعدة المحلية
      
    } catch (e) {
      debugPrint('❌ خطأ في تنزيل الموظفين: $e');
    }
  }

  /// تنزيل المدفوعات من Ditto (مثال مبسط)
  Future<void> _pullPaymentsFromDitto() async {
    try {
      final ditto = _dittoService._ditto;
      if (ditto == null) return;
      
      final collection = ditto.store.collection(DittoSchemaMapper.paymentsCollection);
      final docs = await collection.findAll().exec();
      
      debugPrint('✅ تم تنزيل ${docs.length} مدفوعة من Ditto');
      
      // TODO: تحويل وإدراج المدفوعات في القاعدة المحلية
      
    } catch (e) {
      debugPrint('❌ خطأ في تنزيل المدفوعات: $e');
    }
  }

  /// بدء المراقبة في الوقت الفعلي (Real-time Observation)
  Future<void> startRealtimeObservation() async {
    if (!_isInitialized) {
      debugPrint('❌ خدمة المزامنة غير مهيئة');
      return;
    }

    debugPrint('👀 بدء المراقبة في الوقت الفعلي...');

    // مراقبة التغييرات في الغرف
    _observeRoomsChanges();
    
    // مراقبة التغييرات في الحجوزات
    _observeBookingsChanges();
    
    // يمكن إضافة المزيد من المراقبات حسب الحاجة
  }

  /// مراقبة التغييرات في الغرف
  void _observeRoomsChanges() {
    final ditto = _dittoService._ditto;
    if (ditto == null) return;
    
    final collection = ditto.store.collection(DittoSchemaMapper.roomsCollection);
    
    collection.findAll().observeLocal().listen((docs) {
      debugPrint('🔄 تغيير في الغرف: ${docs.length} غرفة');
      // TODO: تحديث القاعدة المحلية تلقائياً
    });
  }

  /// مراقبة التغييرات في الحجوزات
  void _observeBookingsChanges() {
    final ditto = _dittoService._ditto;
    if (ditto == null) return;
    
    final collection = ditto.store.collection(DittoSchemaMapper.bookingsCollection);
    
    collection.findAll().observeLocal().listen((docs) {
      debugPrint('🔄 تغيير في الحجوزات: ${docs.length} حجز');
      // TODO: تحديث القاعدة المحلية تلقائياً
    });
  }

  /// الحصول على إحصائيات المزامنة
  Future<Map<String, dynamic>> getSyncStats() async {
    try {
      final ditto = _dittoService._ditto;
      if (ditto == null) {
        return {'error': 'Ditto غير مهيء'};
      }

      final roomsCount = await ditto.store
          .collection(DittoSchemaMapper.roomsCollection)
          .findAll()
          .exec()
          .then((docs) => docs.length);

      final bookingsCount = await ditto.store
          .collection(DittoSchemaMapper.bookingsCollection)
          .findAll()
          .exec()
          .then((docs) => docs.length);

      return {
        'rooms_in_ditto': roomsCount,
        'bookings_in_ditto': bookingsCount,
        'is_syncing': _isSyncing,
        'peers_count': _dittoService.peersCount,
      };
    } catch (e) {
      return {'error': 'خطأ في جلب الإحصائيات: $e'};
    }
  }
}
