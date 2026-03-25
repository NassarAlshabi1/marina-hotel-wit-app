import 'package:appwrite/appwrite.dart';
import 'package:drift/drift.dart' as drift;
import 'appwrite_config.dart';
import 'appwrite_service.dart';
import 'local_db.dart';
import 'adapters/adapter_registry.dart';
import 'adapters/source.dart';
import 'appwrite_logger.dart';

/// ✅ خدمة السحب الشامل من Appwrite
/// تجلب جميع البيانات بدون أي فلترة - كل الجداول وكل الحقول
class AppwriteFullPull {
  static final AppwriteFullPull _instance = AppwriteFullPull._internal();
  factory AppwriteFullPull() => _instance;
  AppwriteFullPull._internal();

  AppwriteService? _appwriteService;
  AppDatabase? _database;
  AdapterRegistry? _adapterRegistry;
  final _logger = AppwriteLogger();

  /// حجم الدفعة الواحدة
  static const int _batchSize = 100;

  /// هل تم التهيئة
  bool get isInitialized =>
      _appwriteService != null &&
      _database != null &&
      _adapterRegistry != null;

  /// تهيئة الخدمة
  Future<void> initialize(AppwriteService service, AppDatabase db) async {
    _appwriteService = service;
    _database = db;
    _adapterRegistry = AdapterRegistry(db);
    _logger.info('تم تهيئة خدمة السحب الشامل', tag: 'FULL_PULL');
  }

  /// سحب جميع البيانات من Appwrite
  Future<FullPullResult> pullAll() async {
    if (!isInitialized) {
      return FullPullResult(
        success: false,
        message: 'الخدمة غير مهيأة',
      );
    }

    _logger.info('🚀 بدء السحب الشامل من Appwrite...', tag: 'FULL_PULL');

    final result = FullPullResult(
      success: true,
      message: 'تم السحب بنجاح',
    );

    // تعطيل FOREIGN KEY مؤقتاً
    await _database!.customStatement('PRAGMA foreign_keys=OFF');

    try {
      // ترتيب السحب حسب العلاقات
      final entities = _getEntitiesInOrder();

      for (final entity in entities) {
        try {
          final count = await _pullEntity(entity, result);
          result.counts[entity.name] = count;
          _logger.info(
            '✅ تم سحب $count سجل من ${entity.name}',
            tag: 'FULL_PULL',
          );
        } catch (e) {
          _logger.error(
            '❌ فشل سحب ${entity.name}: $e',
            tag: 'FULL_PULL',
          );
          result.failedEntities.add(entity.name);
        }
      }

      // تحديث حالة الإشغال للغرف
      if (result.totalPulled > 0) {
        await _refreshRoomOccupancy();
      }

      result.success = result.failedEntities.isEmpty;
      result.message = result.failedEntities.isEmpty
          ? 'تم سحب ${result.totalPulled} سجل من ${result.counts.length} جدول'
          : 'تم سحب ${result.totalPulled} سجل، فشل في: ${result.failedEntities.join(', ')}';

      _logger.info('✅ ${result.message}', tag: 'FULL_PULL');
    } finally {
      // إعادة تفعيل FOREIGN KEY
      await _database!.customStatement('PRAGMA foreign_keys=ON');
    }

    return result;
  }

  /// ترتيب الكيانات للسحب (حسب العلاقات)
  List<_PullEntity> _getEntitiesInOrder() {
    final reg = _adapterRegistry!;
    
    return [
      // 1. الغرف أولاً
      _PullEntity(
        name: 'rooms',
        collectionId: AppwriteConfig.roomsCollectionId,
        repo: reg.rooms,
      ),
      // 2. الموظفين
      _PullEntity(
        name: 'employees',
        collectionId: AppwriteConfig.employeesCollectionId,
        repo: reg.employees,
      ),
      // 3. الحجوزات
      _PullEntity(
        name: 'bookings',
        collectionId: AppwriteConfig.bookingsCollectionId,
        repo: reg.bookings,
      ),
      // 4. ليالي الحجز
      _PullEntity(
        name: 'booking_nights',
        collectionId: AppwriteConfig.bookingNightsCollectionId,
        repo: reg.nights,
      ),
      // 5. ملاحظات الحجز
      _PullEntity(
        name: 'booking_notes',
        collectionId: AppwriteConfig.bookingNotesCollectionId,
        repo: reg.bookingNotes,
      ),
      // 6. المدفوعات
      _PullEntity(
        name: 'payments',
        collectionId: AppwriteConfig.paymentsCollectionId,
        repo: reg.payments,
      ),
      // 7. المصروفات
      _PullEntity(
        name: 'expenses',
        collectionId: AppwriteConfig.expensesCollectionId,
        repo: reg.expenses,
      ),
      // 8. الديون
      _PullEntity(
        name: 'debts',
        collectionId: AppwriteConfig.debtsCollectionId,
        repo: reg.debts,
      ),
      // 9. المعاملات النقدية
      _PullEntity(
        name: 'cash_transactions',
        collectionId: AppwriteConfig.cashTransactionsCollectionId,
        repo: reg.cashTransactions,
      ),
      // 10. دورات الرواتب
      _PullEntity(
        name: 'salary_cycles',
        collectionId: AppwriteConfig.salaryCyclesCollectionId,
        repo: reg.salaryCycles,
      ),
      // 11. مدفوعات الرواتب
      _PullEntity(
        name: 'salary_payments',
        collectionId: AppwriteConfig.salaryPaymentsCollectionId,
        repo: reg.salaryPayments,
      ),
      // 12. سحوبات الرواتب
      _PullEntity(
        name: 'salary_withdrawals',
        collectionId: AppwriteConfig.salaryWithdrawalsCollectionId,
        repo: reg.salaryWithdrawals,
      ),
      // 13. ملاحظات الورديات
      _PullEntity(
        name: 'shift_notes',
        collectionId: AppwriteConfig.shiftNotesCollectionId,
        repo: reg.shiftNotes,
      ),
      // 14. تعديلات أسعار الحجوزات
      _PullEntity(
        name: 'booking_price_adjustments',
        collectionId: AppwriteConfig.bookingPriceAdjustmentsCollectionId,
        repo: reg.bookingPriceAdjustments,
      ),
    ];
  }

  /// سحب كيان واحد - جميع السجلات بدون فلترة
  Future<int> _pullEntity(_PullEntity entity, FullPullResult result) async {
    if (entity.collectionId == null) {
      _logger.warning(
        '⚠️ لا يوجد collectionId لـ ${entity.name}',
        tag: 'FULL_PULL',
      );
      return 0;
    }

    int totalCount = 0;
    int offset = 0;

    // حلقة لجلب جميع السجلات على دفعات
    while (true) {
      try {
        // ✅ استعلام بسيط - بدون أي فلترة بالوقت
        final response = await _appwriteService!.databases.listDocuments(
          databaseId: AppwriteConfig.databaseId,
          collectionId: entity.collectionId!,
          queries: [
            Query.limit(_batchSize),
            Query.offset(offset),
          ],
        );

        final documents = response.documents;

        if (documents.isEmpty) {
          break; // لا مزيد من السجلات
        }

        _logger.debug(
          '📦 جلب ${documents.length} سجل من ${entity.name} (offset: $offset)',
          tag: 'FULL_PULL',
        );

        // معالجة كل سجل
        for (final doc in documents) {
          try {
            // نسخ جميع البيانات كما هي
            final remoteData = Map<String, dynamic>.from(doc.data);

            // استخدام document ID كـ localUuid إذا لم يكن موجوداً
            remoteData['localUuid'] = remoteData['localUuid']?.toString() ??
                remoteData['local_uuid']?.toString() ??
                doc.$id;

            // حفظ السجل (upsert)
            await entity.repo!.upsertFromJson(remoteData, src: Source.appwrite);
            totalCount++;
          } catch (e) {
            _logger.warning(
              '⚠️ فشل حفظ سجل من ${entity.name}: $e',
              tag: 'FULL_PULL',
            );
          }
        }

        offset += documents.length;

        // إذا كانت الدفعة أقل من الحجم المحدد، انتهت البيانات
        if (documents.length < _batchSize) {
          break;
        }
      } catch (e) {
        _logger.error(
          '❌ خطأ في جلب دفعة من ${entity.name}: $e',
          tag: 'FULL_PULL',
        );
        break;
      }
    }

    result.totalPulled += totalCount;
    return totalCount;
  }

  /// تحديث حالة إشغال الغرف
  Future<void> _refreshRoomOccupancy() async {
    try {
      final bookings = await _database!.select(_database!.bookings).get();

      final occupiedRooms = <String>{};
      for (final booking in bookings) {
        if (booking.deletedAt == null &&
            (booking.status == 'checkin' || booking.status == 'checked_in')) {
          occupiedRooms.add(booking.roomNumber);
        }
      }

      final rooms = await _database!.select(_database!.rooms).get();

      for (final room in rooms) {
        if (room.deletedAt != null) continue;

        final shouldBeOccupied = occupiedRooms.contains(room.roomNumber);
        final newStatus = shouldBeOccupied ? 'مشغولة' : 'شاغرة';

        if (room.status != newStatus) {
          final query = _database!.update(_database!.rooms)
            ..where((t) => t.id.equals(room.id));
          await query.write(RoomsCompanion(status: drift.Value(newStatus)));
        }
      }

      _logger.info('🔄 تم تحديث حالة إشغال الغرف', tag: 'FULL_PULL');
    } catch (e) {
      _logger.warning('⚠️ فشل تحديث حالة الإشغال: $e', tag: 'FULL_PULL');
    }
  }
}

/// كيان للسحب
class _PullEntity {
  final String name;
  final String? collectionId;
  final dynamic repo; // BaseRepository<dynamic, dynamic>

  _PullEntity({
    required this.name,
    this.collectionId,
    this.repo,
  });
}

/// نتيجة السحب الشامل
class FullPullResult {
  FullPullResult({
    required this.success,
    required this.message,
  });

  bool success;
  String message;
  int totalPulled = 0;

  /// عدد السجلات لكل جدول
  Map<String, int> counts = {};

  /// الجداول التي فشل سحبها
  List<String> failedEntities = [];

  /// ملخص النتيجة
  Map<String, dynamic> toMap() {
    return {
      'success': success,
      'message': message,
      'totalPulled': totalPulled,
      'counts': counts,
      'failedEntities': failedEntities,
    };
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('FullPullResult:');
    buffer.writeln('  success: $success');
    buffer.writeln('  totalPulled: $totalPulled');
    buffer.writeln('  counts:');
    for (final entry in counts.entries) {
      buffer.writeln('    ${entry.key}: ${entry.value}');
    }
    if (failedEntities.isNotEmpty) {
      buffer.writeln('  failedEntities: ${failedEntities.join(', ')}');
    }
    return buffer.toString();
  }
}
