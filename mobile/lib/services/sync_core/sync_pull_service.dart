// ignore_for_file: unused_field, unused_element, deprecated_member_use, directives_ordering, prefer_final_fields, close_sinks, sort_constructors_first
import 'dart:async';
import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:drift/drift.dart' as drift;
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/time.dart';
import '../../utils/secure_storage.dart';
import '../adapters/adapter_registry.dart';
import '../adapters/source.dart';
import '../appwrite_logger.dart';
import '../appwrite_error_handler.dart';
import '../appwrite_service.dart';
import '../booking_derived_fields_service.dart';
import '../crashlytics_service.dart';
import '../daos/outbox_dao.dart';
import '../local_db.dart';
import '../repositories/bookings_repository.dart';
import '../repositories/rooms_repository.dart';
import '../sync_enums.dart';
import 'sync_error_service.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import '../appwrite_config.dart';
import '../appwrite_models.dart';
import '../../utils/status_utils.dart';
import '../adapters/salary_withdrawals_adapter.dart';

/// خدمة سحب التغييرات من Appwrite Cloud إلى القاعدة المحلية
class SyncPullService {

  final AppwriteService appwriteService;
  final AppDatabase database;
  final OutboxDao outboxDao;
  late final AdapterRegistry _adapterRegistry;
  late final BookingsRepository _bookingsRepository;
  late final RoomsRepository _roomsRepository;
  final AppwriteLogger _logger;
  final AppwriteErrorHandler _errorHandler;
  final SyncErrorService _err;
  SyncStatus _currentStatus = SyncStatus.idle;
  final _syncController = StreamController<SyncStatus>.broadcast();
  bool? _remoteEpochIsMillis;
  Stream<SyncStatus> get syncStatusStream => _syncController.stream;

  SyncPullService({
    required this.appwriteService,
    required this.database,
    required this.outboxDao,
    AdapterRegistry? adapterRegistry,
    BookingsRepository? bookingsRepository,
    RoomsRepository? roomsRepository,
    SyncErrorService? errorService,
    AppwriteLogger? logger,
    AppwriteErrorHandler? errorHandler,
  })  : _adapterRegistry = adapterRegistry ?? AdapterRegistry(database),
        _bookingsRepository = bookingsRepository ?? BookingsRepository(database),
        _roomsRepository = roomsRepository ?? RoomsRepository(database),
        _err = errorService ?? SyncErrorService(tag: 'PULL'),
        _logger = logger ?? AppwriteLogger(),
        _errorHandler = errorHandler ?? AppwriteErrorHandler();

  // ── Helper Methods ─────────────────────────────────────────────────────

  int _asInt(dynamic value, {int fallback = 0}) {
    final result = _asIntNullable(value);
    return result ?? fallback;
  }

  int? _asIntNullable(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String && value.isNotEmpty) {
      final parsedInt = int.tryParse(value);
      if (parsedInt != null) return parsedInt;
      final parsedDouble = double.tryParse(value);
      if (parsedDouble != null) return parsedDouble.toInt();
    }
    return null;
  }

  int? _asIntSafe(Map<String, dynamic> data, String key) {
    final value = data[key];
    return _asIntNullable(value);
  }


Future<bool> isRemoteEpochMillis() async {
  final cached = _remoteEpochIsMillis;
  if (cached != null) {
    return cached;
  }
  try {
    final info = appwriteService.getProjectInfo();
    final dbId = info['databaseId'] ?? AppwriteConfig.databaseId;

    final list = await appwriteService.databases.listDocuments(
      databaseId: dbId,
      collectionId: AppwriteConfig.roomsCollectionId,
      queries: [Query.limit(1)],
    );

    if (list.documents.isEmpty) {
      _remoteEpochIsMillis = false;
      return false;
    }

    final data = list.documents.first.data;
    final raw =
        data['lastModified'] ?? data['last_modified'] ?? data['last_modified_epoch'];

    final value = raw is int
        ? raw
        : raw is num
        ? raw.toInt()
        : raw is String
        ? int.tryParse(raw)
        : null;

    final isMillis = value != null && value > 10000000000;
    _remoteEpochIsMillis = isMillis;
    return isMillis;
  } catch (_) {
    _remoteEpochIsMillis = false;
    return false;
  }
}

Future<List<String>> buildDeltaQueries(int lastPullTs) async {
  if (lastPullTs <= 0) {
    return [];
  }
  final cutoffSeconds = lastPullTs - 5;
  final isMillis = await isRemoteEpochMillis();
  if (isMillis) {
    return [Query.greaterThan('lastModified', cutoffSeconds * 1000)];
  }
  return [Query.greaterThan('lastModified', cutoffSeconds)];
}

/// تهيئة المزامنة

List<String> bookingNightsDeltaQueries(
  int lastPullTs, {
  required bool remoteEpochIsMillis,
}) {
  if (lastPullTs > 0) {
    final cutoff = lastPullTs - 5;
    if (remoteEpochIsMillis) {
      return [Query.greaterThan('lastModified', cutoff * 1000)];
    }
    return [Query.greaterThan('lastModified', cutoff)];
  }
  return []; // full fetch
}

/// تنظيف outbox بعد سحب البيانات من السحابة بنجاح.
/// يحذف عناصر outbox التي تتطابق مع بيانات تم سحبها فعلياً (بنفس entity + localUuid).
/// المنطق: إذا السحابة أرسلت هذا السجل فلا حاجة لإعادة إرساله عبر outbox.
/// ✅ فصل هندسي: يحذف فقط عناصر source='local' — لا يمس عناصر 'restore'
/// ✅ تنظيف outbox بعد السحب: يحذف فقط عناصر outbox التي تم سحب
/// بياناتها المطابقة من السحابة. لا يحذف عناصر outbox للبيانات
/// التي لم تُسحب (حماية التغييرات المحلية المشروعة).
///
/// المنطق: إذا تم سحب بيانات من Appwrite وكان lastModified البعيد
/// أكبر من أو يساوي المحلي، فهذا يعني أن السحابة لديها نفس
/// البيانات أو أحدث، وبالتالي لا حاجة لإعادة إرسالها.

bool _isRemoteDataNewer(
  Map<String, dynamic> remoteData,
  int? localLastModified, {
  int? localDeletedAt,
}) {
  // ✅ إصلاح: إذا حُذف السجل محلياً (soft delete) وكان الحذف أحدث
  // من البيانات البعيدة، لا نكتب فوق الحذف المحلي — نحمي الحذف
  if (localDeletedAt != null) {
    final remoteDeletedAt = _asIntNullable(remoteData['deletedAt']) ??
        _asIntNullable(remoteData['deleted_at']);
    // إذا كانت البيانات البعيدة أيضاً محذوفة → نتابع (كلاهما محذوف)
    if (remoteDeletedAt != null) {
      return true; // كلاهما محذوف — نسمح بالتحديث
    }
    // البيانات البعيدة غير محذوفة لكن المحلي محذوف — نرفض الكتابة فوق الحذف
    // الحذف المحلي متعمد ويجب أن يكون له أولوية أعلى
    return false;
  }

  if (localLastModified == null) {
    // لا يوجد سجل محلي — البيانات البعيدة "أحدث" (جديدة)
    return true;
  }

  final remoteLastModified = _asIntNullable(remoteData['lastModified']) ??
      _asIntNullable(remoteData['last_modified']) ??
      _asIntNullable(remoteData['lastModifiedEpoch']);

  if (remoteLastModified == null) {
    // لا نعرف عمر البيانات البعيدة — نتابع بالتحديث احتياطاً
    return true;
  }

  // البيانات البعيدة أحدث فقط إذا كان lastModified أكبر من المحلي
  return remoteLastModified > localLastModified;
}


Future<int> _syncRooms(List<models.Document> documents) async {
  if (documents.isEmpty) return 0;
  var processed = 0;
  for (final doc in documents) {
    try {
      final data = Map<String, dynamic>.from(doc.data);
      data['localUuid'] ??= doc.$id;

      // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
      final localUuid = (data['localUuid'] as String?) ?? '';
      final existingRoom = await (database.select(database.rooms)
            ..where((r) => r.localUuid.equals(localUuid))
            ..limit(1))
          .getSingleOrNull();

      if (!_isRemoteDataNewer(data, existingRoom?.lastModified, localDeletedAt: existingRoom?.deletedAt)) {
        continue; // البيانات مطابقة أو السجل محذوف محلياً
      }

      await _adapterRegistry.rooms.upsertFromJson(data, src: Source.appwrite);
      processed++;
    } catch (e) {
      _logger.warning('Failed to sync room ${doc.$id}: $e', tag: 'SYNC');
    }
  }
  return processed;
}


Future<int> _syncBookings(List<models.Document> documents) async {
  if (documents.isEmpty) return 0;
  var processed = 0;
  final affectedRoomNumbers = <String>{};

  for (final doc in documents) {
    try {
      final data = Map<String, dynamic>.from(doc.data);
      data['localUuid'] ??= doc.$id;

      // ✅ حفظ حالة الحجز القديمة قبل التحديث لمقارنتها
      final localUuid = (data['localUuid'] as String?) ?? '';
      final existingBooking = await (database.select(database.bookings)
            ..where((b) => b.localUuid.equals(localUuid)))
          .getSingleOrNull();
      final oldStatus = existingBooking?.status;
      final oldRoomNumber = existingBooking?.roomNumber;

      // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
      if (!_isRemoteDataNewer(data, existingBooking?.lastModified, localDeletedAt: existingBooking?.deletedAt)) {
        continue; // البيانات مطابقة أو السجل محذوف محلياً
      }

      // ✅ تسجيل تشخيصي: تسجيل الحقول الحرجة عند السحب من Appwrite
      final remoteStatus = data['status']?.toString();
      final remoteActualCheckout = data['actualCheckout']?.toString();
      final remoteLastModified = data['lastModified'];
      _logger.info(
        '📥 Pull booking ${localUuid.substring(0, 8)}... '
        'status=$remoteStatus '
        'actualCheckout=$remoteActualCheckout '
        'lastModified=$remoteLastModified '
        'existing=${existingBooking != null ? 'yes(status=${existingBooking.status})' : 'no'}',
        tag: 'SYNC',
      );

      await _adapterRegistry.bookings.upsertFromJson(
        data,
        src: Source.appwrite,
      );

      // TRIGGER POST-SYNC PROCESSING
      // 1. Resolve local ID from UUID
      final booking = await (database.select(database.bookings)
            ..where((b) => b.localUuid.equals(localUuid)))
          .getSingleOrNull();

      if (booking != null) {
        // ✅ تسجيل تشخيصي بعد السحب: التحقق من حفظ الحقول الحرجة محلياً
        if (remoteStatus != null && booking.status != remoteStatus) {
          _logger.error(
            '❌ بعد upsert: status محلي=${booking.status} ≠ بعيد=$remoteStatus '
            'booking=${localUuid.substring(0, 8)}... — فقدان بيانات!',
            tag: 'SYNC',
          );
        }
        if (remoteActualCheckout != null &&
            booking.actualCheckout != remoteActualCheckout) {
          _logger.error(
            '❌ بعد upsert: actualCheckout محلي=${booking.actualCheckout} ≠ بعيد=$remoteActualCheckout '
            'booking=${localUuid.substring(0, 8)}... — فقدان بيانات!',
            tag: 'SYNC',
          );
        }

        // 2. Convert legacy discount to adjustments
        await _bookingsRepository.syncLegacyDiscountToAdjustments(booking.id);

        // 3. Recalculate derived fields (nightly rates, total due)
        await _bookingsRepository.derivedFields.refreshForBookingId(booking.id);

        // ✅ 4. تتبع الغرف المتأثرة بتغيير حالة الحجز
        // إذا تغيرت الحالة من نشطة إلى غير نشطة (مثل تسجيل الخروج)
        // نحتاج لإعادة حساب حالة الإشغال للغرفة
        final newStatus = booking.status;
        final newRoomNumber = booking.roomNumber;

        final statusChanged = oldStatus != null && oldStatus != newStatus;
        final wasActive = oldStatus != null &&
            StatusUtils.isActiveBooking(oldStatus);
        final isNowActive = StatusUtils.isActiveBooking(newStatus);

        if (statusChanged && wasActive != isNowActive) {
          // الحالة تغيرت بين نشطة وغير نشطة - أضف الغرفة للقائمة
          if (oldRoomNumber != null && oldRoomNumber.isNotEmpty) {
            affectedRoomNumbers.add(oldRoomNumber);
          }
          if (newRoomNumber.isNotEmpty) {
            affectedRoomNumbers.add(newRoomNumber);
          }
        } else if (existingBooking == null) {
          // حجز جديد من المزامنة - أضف الغرفة للقائمة
          if (newRoomNumber.isNotEmpty) {
            affectedRoomNumbers.add(newRoomNumber);
          }
        }
      }

      processed++;
    } catch (e) {
      _logger.warning('Failed to sync booking ${doc.$id}: $e', tag: 'SYNC');
    }
  }

  // ✅ إعادة حساب حالة الإشغال للغرف المتأثرة فقط (تحسين الأداء)
  if (affectedRoomNumbers.isNotEmpty) {
    try {
      for (final roomNumber in affectedRoomNumbers) {
        await _refreshSingleRoomOccupancy(roomNumber);
      }
      _logger.debug(
        '🔄 تم تحديث حالة ${affectedRoomNumbers.length} غرفة متأثرة بتغييرات الحجوزات',
        tag: 'SYNC',
      );
    } catch (e) {
      _logger.warning(
        '⚠️ فشل تحديث حالة الغرف المتأثرة: $e',
        tag: 'SYNC',
      );
    }
  }

  return processed;
}

/// ✅ إعادة حساب حالة إشغال غرفة واحدة بناءً على الحجوزات النشطة
/// يستخدم RoomsRepository لضمان تحديث version و lastModified

Future<void> _refreshSingleRoomOccupancy(String roomNumber) async {
  try {
    // التحقق من وجود حجز نشط للغرفة
    final activeBooking = await _bookingsRepository.getActiveBookingForRoom(
      roomNumber,
    );

    final room = await (database.select(database.rooms)
          ..where((r) => r.roomNumber.equals(roomNumber))
          ..limit(1))
        .getSingleOrNull();

    if (room == null || room.deletedAt != null) return;

    final shouldBeOccupied = activeBooking != null;
    final isCurrentlyOccupied = StatusUtils.isRoomOccupied(room.status);
    final isCurrentlyAvailable = StatusUtils.isRoomAvailable(room.status);

    if (shouldBeOccupied && !isCurrentlyOccupied) {
      await _roomsRepository.updateByRoomNumber(
        roomNumber,
        status: StatusUtils.roomStatusForOccupancy(true),
        originIsServer: true,
      );
    } else if (!shouldBeOccupied && !isCurrentlyAvailable) {
      await _roomsRepository.updateByRoomNumber(
        roomNumber,
        status: StatusUtils.roomStatusForOccupancy(false),
        originIsServer: true,
      );
    }
  } catch (e) {
    _logger.warning(
      '⚠️ فشل تحديث حالة الغرفة $roomNumber: $e',
      tag: 'SYNC',
    );
  }
}


Future<int> _syncEmployees(List<models.Document> documents) async {
  if (documents.isEmpty) return 0;
  var processed = 0;
  for (final doc in documents) {
    try {
      final data = Map<String, dynamic>.from(doc.data);
      data['localUuid'] ??= doc.$id;

      // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
      final localUuid = (data['localUuid'] as String?) ?? '';
      final existing = await (database.select(database.employees)
            ..where((e) => e.localUuid.equals(localUuid))
            ..limit(1))
          .getSingleOrNull();
      if (!_isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt)) {
        continue;
      }

      // ✅ تخزين remote id كـ serverId — يسمح بحل FK عبر الأجهزة
      // salary_withdrawals و salary_cycles يستخدمان employeeId البعيد
      // الذي يساوي id الموظف على جهاز المصدر. بتخزينه في serverId
      // يمكن حل FK بالبحث عن serverId = remoteEmployeeId
      final remoteId = _asIntSafe(data, 'id');
      if (remoteId != null && data['serverId'] == null) {
        data['serverId'] = remoteId;
      }

      await _adapterRegistry.employees.upsertFromJson(
        data,
        src: Source.appwrite,
      );
      processed++;
    } catch (e) {
      _logger.warning('Failed to sync employee ${doc.$id}: $e', tag: 'SYNC');
    }
  }
  return processed;
}


Future<int> _syncExpenses(List<models.Document> documents) async {
  if (documents.isEmpty) return 0;
  var processed = 0;
  for (final doc in documents) {
    try {
      final data = Map<String, dynamic>.from(doc.data);
      data['localUuid'] ??= doc.$id;

      // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
      final localUuid = (data['localUuid'] as String?) ?? '';
      final existing = await (database.select(database.expenses)
            ..where((e) => e.localUuid.equals(localUuid))
            ..limit(1))
          .getSingleOrNull();
      if (!_isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt)) {
        continue;
      }

      await _adapterRegistry.expenses.upsertFromJson(
        data,
        src: Source.appwrite,
      );
      processed++;
    } catch (e) {
      _logger.warning('Failed to sync expense ${doc.$id}: $e', tag: 'SYNC');
    }
  }
  return processed;
}


Future<int> _syncPayments(List<models.Document> documents) async {
  if (documents.isEmpty) return 0;
  var processed = 0;
  final deferred = <models.Document>[];

  // المرحلة الأولى: معالجة الدفعات
  for (final doc in documents) {
    try {
      final data = Map<String, dynamic>.from(doc.data);
      data['localUuid'] ??= doc.$id;

      // ✅ إصلاح: التحقق من الحذف الناعم + عدم تجاوز البيانات المحلية الأحدث
      final localUuid = (data['localUuid'] as String?) ?? '';
      final existingPayment = await _getPaymentByLocalUuid(localUuid);

      // منع إعادة إحياء السجلات المحذوفة softly
      if (existingPayment != null && existingPayment.deletedAt != null) {
        final remoteDeletedAt = _asIntNullable(data['deletedAt']) ??
            _asIntNullable(data['deleted_at']);
        if (remoteDeletedAt == null) {
          // السجل محذوف محلياً لكن البعيد غير محذوف — نرفض الإحياء
          _logger.debug(
            'Skipping payment ${doc.$id}: locally soft-deleted, refusing revival',
            tag: 'SYNC',
          );
          processed++;
          continue;
        }
        // كلاهما محذوف — نسمح بالتحديث إذا كان البعيد أحدث
      }

      // Financial immutability: if local payment exists and is newer, keep local
      final incomingLastModified = _asInt(data['lastModified']);
      if (existingPayment != null && existingPayment.lastModified > incomingLastModified) {
        _logger.debug(
          'Skipping payment ${doc.$id}: local is newer (financial immutability)',
          tag: 'SYNC',
        );
        processed++;
        continue;
      }

      await _adapterRegistry.payments.upsertFromJson(
        data,
        src: Source.appwrite,
      );
      processed++;
    } catch (e) {
      // ✅ تأجيل الدفعة فقط إذا كان الخطأ FOREIGN KEY أو NOT NULL constraint
      // (بيانات مفقودة مثل bookingLocalId) — لا نشمل 'constraint failed' عام
      // لأنه يطابق UNIQUE و CHECK أيضاً ويؤدي لتأجيل خاطئ لسجلات مكررة
      final errStr = e.toString();
      if (errStr.contains('FOREIGN KEY constraint failed') ||
          errStr.contains('NOT NULL constraint failed')) {
        _logger.debug(
          'Deferring payment ${doc.$id}: FK/NOT NULL constraint (missing booking)',
          tag: 'SYNC',
        );
        deferred.add(doc);
      } else {
        _logger.warning('Failed to sync payment ${doc.$id}: $e', tag: 'SYNC');
      }
    }
  }

  // المرحلة الثانية: إعادة محاولة الدفعات المؤجلة
  if (deferred.isNotEmpty) {
    _logger.info(
      'Retrying ${deferred.length} deferred payments after all bookings synced',
      tag: 'SYNC',
    );

    for (final doc in deferred) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;
        await _adapterRegistry.payments.upsertFromJson(
          data,
          src: Source.appwrite,
        );
        processed++;
      } catch (e) {
        _logger.warning(
          'Failed to sync deferred payment ${doc.$id} after retry: $e',
          tag: 'SYNC',
        );
      }
    }
  }

  return processed;
}


Future<int> _syncDebts(List<models.Document> documents) async {
  if (documents.isEmpty) return 0;
  var processed = 0;
  final deferred = <models.Document>[];

  // المرحلة الأولى: معالجة الديون
  for (final doc in documents) {
    try {
      final data = Map<String, dynamic>.from(doc.data);
      data['localUuid'] ??= doc.$id;

      // ✅ إصلاح: التحقق من الحذف الناعم + عدم تجاوز البيانات المحلية الأحدث
      final localUuid = (data['localUuid'] as String?) ?? '';
      final existingDebt = await _getDebtByLocalUuid(localUuid);

      // منع إعادة إحياء السجلات المحذوفة softly
      if (existingDebt != null && existingDebt.deletedAt != null) {
        final remoteDeletedAt = _asIntNullable(data['deletedAt']) ??
            _asIntNullable(data['deleted_at']);
        if (remoteDeletedAt == null) {
          // السجل محذوف محلياً لكن البعيد غير محذوف — نرفض الإحياء
          _logger.debug(
            'Skipping debt ${doc.$id}: locally soft-deleted, refusing revival',
            tag: 'SYNC',
          );
          processed++;
          continue;
        }
        // كلاهما محذوف — نسمح بالتحديث إذا كان البعيد أحدث
      }

      // Financial immutability: if local debt exists and is newer, keep local
      final incomingLastModified = _asInt(data['lastModified']);
      if (existingDebt != null && existingDebt.lastModified > incomingLastModified) {
        _logger.debug(
          'Skipping debt ${doc.$id}: local is newer (financial immutability)',
          tag: 'SYNC',
        );
        processed++;
        continue;
      }

      await _adapterRegistry.debts.upsertFromJson(data, src: Source.appwrite);
      processed++;
    } catch (e) {
      // ✅ تأجيل الدين فقط إذا كان الخطأ FOREIGN KEY أو NOT NULL constraint
      final errStr = e.toString();
      if (errStr.contains('FOREIGN KEY constraint failed') ||
          errStr.contains('NOT NULL constraint failed')) {
        _logger.debug(
          'Deferring debt ${doc.$id}: FK/NOT NULL constraint (missing booking)',
          tag: 'SYNC',
        );
        deferred.add(doc);
      } else {
        _logger.warning('Failed to sync debt ${doc.$id}: $e', tag: 'SYNC');
      }
    }
  }

  // المرحلة الثانية: إعادة محاولة الديون المؤجلة
  if (deferred.isNotEmpty) {
    _logger.info(
      'Retrying ${deferred.length} deferred debts after all bookings synced',
      tag: 'SYNC',
    );

    for (final doc in deferred) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;
        await _adapterRegistry.debts.upsertFromJson(
          data,
          src: Source.appwrite,
        );
        processed++;
      } catch (e) {
        _logger.warning(
          'Failed to sync deferred debt ${doc.$id} after retry: $e',
          tag: 'SYNC',
        );
      }
    }
  }

  return processed;
}


Future<int> _syncGuestInfos(List<models.Document> documents) async {
  if (documents.isEmpty) return 0;
  var processed = 0;
  for (final doc in documents) {
    try {
      final data = Map<String, dynamic>.from(doc.data);
      data['localUuid'] ??= doc.$id;

      // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
      final localUuid = (data['localUuid'] as String?) ?? '';
      final existing = await (database.select(database.guestInfos)
            ..where((t) => t.localUuid.equals(localUuid))
            ..limit(1))
          .getSingleOrNull();
      if (!_isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt)) {
        continue;
      }

      await _adapterRegistry.guestInfos.upsertFromJson(
        data,
        src: Source.appwrite,
      );
      processed++;
    } catch (e) {
      _logger.warning(
        'Failed to sync guest_info ${doc.$id}: $e',
        tag: 'SYNC',
      );
    }
  }
  return processed;
}


Future<int> _syncSalaryWithdrawals(List<models.Document> documents) async {
  if (documents.isEmpty) return 0;
  var processed = 0;
  final deferred = <Map<String, dynamic>>[];

  for (final doc in documents) {
    try {
      final data = Map<String, dynamic>.from(doc.data);
      data['localUuid'] ??= doc.$id;

      // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
      final localUuid = (data['localUuid'] as String?) ?? '';
      final existing = await (database.select(database.salaryWithdrawals)
            ..where((t) => t.localUuid.equals(localUuid))
            ..limit(1))
          .getSingleOrNull();
      if (!_isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt)) {
        continue;
      }

      // ✅ حل FK الموظف بثلاث مستويات: UUID → id → serverId
      final remoteEmployeeId = _asIntSafe(data, 'employeeId') ??
          _asIntSafe(data, 'employee_id');
      final employeeUuid = (data['employeeUuid'] as String?) ??
          (data['employee_uuid'] as String?) ??
          (data['employeeLocalUuid'] as String?) ??
          (data['employee_local_uuid'] as String?);

      Employee? employee;

      // الطريقة 1: البحث بالـ UUID (الأكثر موثوقية عبر الأجهزة)
      if (employeeUuid != null && employeeUuid.isNotEmpty) {
        employee = await (database.select(database.employees)
              ..where((e) => e.localUuid.equals(employeeUuid))
              ..limit(1))
            .getSingleOrNull();
      }

      // الطريقة 2: البحث بالـ id البعيد كـ id محلي (يعمل إذا تطابقت المعرفات)
      if (employee == null && remoteEmployeeId != null) {
        employee = await (database.select(database.employees)
              ..where((e) => e.id.equals(remoteEmployeeId))
              ..limit(1))
            .getSingleOrNull();
      }

      // الطريقة 3: البحث بالـ serverId (id الأصلي من جهاز المصدر)
      if (employee == null && remoteEmployeeId != null) {
        employee = await (database.select(database.employees)
              ..where((e) => e.serverId.equals(remoteEmployeeId))
              ..limit(1))
            .getSingleOrNull();
      }

      if (employee == null) {
        _logger.warning(
          '⏭️ تخطي salary_withdrawal ${doc.$id}: الموظف $remoteEmployeeId (uuid=$employeeUuid) غير موجود محلياً (سجل يتيم)',
          tag: 'SYNC',
        );
        continue;
      }

      // ✅ استبدال employeeId البعيد بالمعرف المحلي للموظف
      // هذا يضمن أن FK يشير للمعرف المحلي الصحيح
      data['employeeId'] = employee.id;

      final insertedId = await _adapterRegistry.salaryWithdrawals.upsertFromJson(
        data,
        src: Source.appwrite,
      );

      // ✅ كتابة expense_id في العمود الخام (Migration 40+)
      // العمود ليس في الـ data class المُولّد لذلك نكتبه يدوياً
      final remoteExpenseId = _asIntSafe(data, 'expenseId');
      if (remoteExpenseId != null && remoteExpenseId > 0) {
        final swAdapter = _adapterRegistry.salaryWithdrawals.adapter;
        if (swAdapter is SalaryWithdrawalsAdapter) {
          await swAdapter.writeExpenseIdRaw(database, insertedId, remoteExpenseId);
        }
      }

      processed++;
    } on SqliteException catch (e) {
      if (e.resultCode == 787) {
        // FK constraint failed - تأجيل السجل لإعادة المحاولة لاحقاً
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;
        deferred.add(data);
        _logger.warning(
          '⏳ تأجيل salary_withdrawal ${doc.$id}: FK constraint failed - سيتم إعادة المحاولة',
          tag: 'SYNC',
        );
      } else {
        _logger.warning(
          'Failed to sync salary_withdrawal ${doc.$id}: $e',
          tag: 'SYNC',
        );
      }
    } catch (e) {
      _logger.warning(
        'Failed to sync salary_withdrawal ${doc.$id}: $e',
        tag: 'SYNC',
      );
    }
  }

  // ✅ إعادة محاولة السجلات المؤجلة بعد اكتمال باقي السجلات
  if (deferred.isNotEmpty) {
    _logger.info(
      '🔄 إعادة محاولة ${deferred.length} سجل salary_withdrawals مؤجل...',
      tag: 'SYNC',
    );
    for (final data in deferred) {
      try {
        final deferredInsertedId = await _adapterRegistry.salaryWithdrawals.upsertFromJson(
          data,
          src: Source.appwrite,
        );
        // ✅ كتابة expense_id في العمود الخام
        final deferredExpenseId = _asIntSafe(data, 'expenseId');
        if (deferredExpenseId != null && deferredExpenseId > 0) {
          final swAdapter = _adapterRegistry.salaryWithdrawals.adapter;
          if (swAdapter is SalaryWithdrawalsAdapter) {
            await swAdapter.writeExpenseIdRaw(database, deferredInsertedId, deferredExpenseId);
          }
        }
        processed++;
      } catch (e) {
        _logger.warning(
          '⏭️ فشل نهائي لـ salary_withdrawal (يتيم): الموظف ${data['employeeId'] ?? data['employee_id']} غير موجود - $e',
          tag: 'SYNC',
        );
      }
    }
  }

  return processed;
}


Future<int> getBookingNightsPullTs() async {
  final prefs = await SharedPreferences.getInstance();
  final ts = prefs.getInt('sync_last_pull_booking_nights') ?? 0;
  if (ts > 10000000000) {
    return ts ~/ 1000;
  }
  return ts;
}

/// تحديث آخر timestamp خاص بـ booking_nights

Future<void> updateBookingNightsPullTs(int ts) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('sync_last_pull_booking_nights', ts);
}

/// بناء delta queries خاصة بـ booking_nights

Future<int> _cleanupOutboxAfterPull() async {
  int totalRemoved = 0;

  // الكيانات الرئيسية التي يتم مزامنتها مع جدول UUID المقابل
  const entityUuidMap = {
    'rooms': 'rooms',
    'bookings': 'bookings',
    'employees': 'employees',
    'expenses': 'expenses',
    'payments': 'payments',
    'debts': 'debts',
    'guest_infos': 'guest_infos',
    'salary_withdrawals': 'salary_withdrawals',
    'booking_price_adjustments': 'booking_price_adjustments',
    'shift_notes': 'shift_notes',
    'blacklist': 'blacklist',
    'booking_notes': 'booking_notes',
    'booking_nights': 'booking_nights',
    'cash_transactions': 'cash_transactions',
    'salary_cycles': 'salary_cycles',
    'salary_payments': 'salary_payments',
    'price_adjustments': 'price_adjustments',
    'audit_logs': 'audit_logs',
    'payment_voids': 'payment_voids',
  };

  for (final entity in entityUuidMap.keys) {
    try {
      // جلب عناصر outbox المعلقة فقط (pending أو failed)
      // لا نحذف العناصر في حالة 'processing' لأنها قيد الرفع حالياً
      final outboxEntries = await (database.select(database.outbox)
            ..where((t) =>
                t.entity.equals(entity) &
                t.source.equals('local') &
                t.processingStatus.isIn(['pending', 'failed'])))
          .get();

      if (outboxEntries.isEmpty) continue;

      // ✅ فحص كل عنصر: هل البيانات المحلية لا تزال أقدم من السحابة؟
      // إذا كان outbox entry يمثل تغييراً محلياً لم يُرفع بعد،
      // والسحابة ليس لديها بيانات أحدث لهذا localUuid،
      // يجب إبقاء العنصر في outbox.
      final uuidsToRemove = <String>[];
      for (final entry in outboxEntries) {
        // التحقق من وجود بيانات محلية أحدث من السحابة
        // إذا كانت البيانات المحلية لا تزال تحتاج رفع، نبقي العنصر
        final localData = await _getLocalLastModified(entity, entry.localUuid);
        if (localData == null) {
          // لا يوجد سجل محلي — ربما تم حذفه، نحذف outbox entry
          uuidsToRemove.add(entry.localUuid);
          continue;
        }

        if (localData > entry.clientTs) {
          // البيانات المحلية أحدث من outbox entry — السحب حدّثها
          // لا حاجة لإبقاء العنصر القديم
          uuidsToRemove.add(entry.localUuid);
        } else if (localData == entry.clientTs) {
          // ✅ عندما يتساوى lastModified المحلي مع clientTs في outbox،
          // نحتاج لتمييز حالتين:
          // 1) التغيير محلي ولم يُرفع بعد → نبقي العنصر
          // 2) البيانات قادمة من السيرفر (origin='server') →
          //    السيرفر لديها نفس البيانات، لا حاجة لإعادة الرفع
          final origin = await _getLocalOrigin(entity, entry.localUuid);
          if (origin == 'server') {
            // البيانات كانت قادمة من السيرفر → السيرفر لديها بالفعل
            // لا حاجة لإبقاء عنصر outbox
            uuidsToRemove.add(entry.localUuid);
          }
          // إذا origin == 'local' → التغيير المحلي لم يُرفع بعد → نبقي العنصر
        }
        // إذا كان localData < clientTs، التغيير المحلي لا يزال صالحاً
        // يجب إبقاء العنصر ليُرفع
      }

      if (uuidsToRemove.isEmpty) continue;

      final removed =
          await outboxDao.removePulledEntities(uuidsToRemove, entity: entity);
      totalRemoved += removed;
    } catch (e) {
      _logger.warning('فشل تنظيف outbox للكيان $entity: $e', tag: 'SYNC');
    }
  }

  return totalRemoved;
}

/// ✅ تنظيف سجلات Outbox للكيانات المحذوفة (soft-delete أو hard-delete)
/// 1. يجمع localUuid لجميع عناصر outbox الحالية
/// 2. يتحقق من وجودها محلياً ومن حالة الحذف
/// 3. يزيل سجلات outbox المُكتملة للكيانات المحذوفة softly
/// 4. يزيل سجلات outbox المعلقة/الفاشلة للكيانات المحذوفة نهائياً

Future<int> _cleanupOutboxForDeletedEntities() async {
  int totalRemoved = 0;

  try {
    // جلب جميع عناصر outbox غير المُعالجة حالياً
    final entries = await (database.select(database.outbox)
          ..where((t) => t.processingStatus.isIn(['pending', 'failed', 'completed'])))
        .get();

    if (entries.isEmpty) return 0;

    final softDeletedUuids = <String, int?>{};
    final missingUuids = <String>[];

    for (final entry in entries) {
      final deletedAt = await _getLocalEntityDeletedAt(entry.entity, entry.localUuid);
      if (deletedAt == null) {
        // الكيان غير موجود محلياً (hard-delete)
        if (entry.processingStatus != 'completed') {
          missingUuids.add(entry.localUuid);
        }
      } else if (deletedAt > 0) {
        // الكيان محذوف softly — نظّف سجل outbox المُكتمل فقط
        softDeletedUuids[entry.localUuid] = deletedAt;
      }
    }

    // تنظيف سجلات outbox المُكتملة للكيانات المحذوفة softly
    if (softDeletedUuids.isNotEmpty) {
      totalRemoved += await outboxDao.cleanupForSoftDeletedEntities(softDeletedUuids);
    }

    // تنظيف سجلات outbox المعلقة/الفاشلة للكيانات غير الموجودة
    if (missingUuids.isNotEmpty) {
      totalRemoved += await outboxDao.cleanupForMissingEntities(missingUuids);
    }
  } catch (e) {
    _logger.warning('فشل تنظيف outbox للكيانات المحذوفة: $e', tag: 'SYNC');
  }

  return totalRemoved;
}

/// جلب deletedAt لكيان محلي بناءً على entity و localUuid
/// يُعيد null إذا الكيان غير موجود، أو 0 إذا موجود وغير محذوف

Future<int> getLastPullTs() async {
  try {
    final state = await (database.select(database.syncState)
          ..where((t) => t.id.equals(1)))
        .getSingleOrNull();
    final ts = state?.lastPullTs ?? 0;
    if (ts > 10000000000) {
      return ts ~/ 1000;
    }
    return ts;
  } catch (_) {
    _logger.warning('Failed to read lastPullTs, using 0', tag: 'SYNC');
    return 0;
  }
}

/// تحديث آخر timestamp لسحب البيانات في جدول SyncState
/// ✅ نستخدم insertOnConflictUpdate بدلاً من update فقط
/// لأن صف SyncState (id=1) قد لا يكون موجوداً بعد، مما يجعل UPDATE
/// لا يؤثر على أي صف — وبالتالي lastPullTs يبقى 0 للأبد،
/// وكل مزامنة تسحب كل البيانات بدلاً من التغييرات فقط (delta).

Future<void> updateLastPullTs(int ts) async {
  try {
    await database.into(database.syncState).insertOnConflictUpdate(
          SyncStateCompanion(
            id: const drift.Value(1),
            lastPullTs: drift.Value(ts),
          ),
        );
  } catch (e) {
    _logger.warning('Failed to update lastPullTs: $e', tag: 'SYNC');
  }
}


/// الحصول على قائمة الأجهزة المسجلة
/// [limit] عدد الأجهزة المطلوبة (افتراضياً 2)
/// يحاول الترتيب من الخادم أولاً، وإذا فشل (لا يوجد فهرس) يرجع للترتيب المحلي
Future<List<AppwriteDevice>> getRegisteredDevices({int limit = 2}) async {
  try {
    // محاولة جلب آخر الأجهزة مرتبة من الخادم (يتطلب فهرس على lastSeen)
    final devices = await appwriteService.listDevices(
      queries: [
        Query.orderDesc('lastSeen'),
        Query.limit(limit),
      ],
      useCache: false,
    );
    return devices.map((doc) => AppwriteDevice.fromJson(doc.data)).toList();
  } catch (e) {
    // إذا فشل الترتيب (مثلاً لا يوجد فهرس على lastSeen)، نستخدم الطريقة البديلة
    _logger.warning(
      'orderDesc(lastSeen) failed, falling back to local sort: $e',
      tag: 'SYNC',
    );
    try {
      final devices = await appwriteService.listDevices(useCache: false);
      final mapped = devices
          .map((doc) => AppwriteDevice.fromJson(doc.data))
          .toList();
      mapped.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
      return mapped.take(limit).toList();
    } catch (e2) {
      _logger.error(
        'Failed to get registered devices',
        error: e2,
        tag: 'SYNC',
      );
      return [];
    }
  }
}

/// رفع التغييرات المحلية إلى Appwrite فوراً

Future<int> _syncBlacklist(List<models.Document> documents) async {
  if (documents.isEmpty) return 0;
  var processed = 0;
  for (final doc in documents) {
    try {
      final data = Map<String, dynamic>.from(doc.data);
      final localUuid = (data['localUuid'] as String?) ?? doc.$id;
      final name = (data['name'] as String?) ?? '';

      // تحويل بيانات Appwrite إلى صيغة shift_notes المحلية
      final content = jsonEncode({
        'nationality': (data['nationality'] as String?) ?? '',
        'nationalId': (data['nationalId'] as String?) ?? '',
        'phone': (data['phone'] as String?) ?? '',
        'reason': (data['reason'] as String?) ?? '',
        'notes': (data['notes'] as String?) ?? '',
        'reportedBy': (data['reportedBy'] as String?) ?? 'police',
        'active': (data['active'] as bool?) ?? true,
      });

      // Appwrite blacklist: createdAt/updatedAt/deletedAt هي STRING (ISO)
      final createdAtIso = (data['createdAt'] as String?) ??
          (data['createdAtIso'] as String?) ??
          DateTime.now().toIso8601String();
      final updatedAtIso = (data['updatedAt'] as String?) ??
          (data['updatedAtIso'] as String?) ??
          createdAtIso;

      // تحويل ISO إلى epoch seconds لقاعدة البيانات المحلية
      int? createdAtEpoch;
      try {
        createdAtEpoch = DateTime.parse(createdAtIso).millisecondsSinceEpoch ~/ 1000;
      } catch (_) {
        createdAtEpoch = Time.nowEpoch();
      }
      int? updatedAtEpoch;
      try {
        updatedAtEpoch = DateTime.parse(updatedAtIso).millisecondsSinceEpoch ~/ 1000;
      } catch (_) {
        updatedAtEpoch = Time.nowEpoch();
      }

      final lastModified = _asInt(data['lastModified']);
      final serverId = _asIntNullable(data['serverId']);

      // معالجة الحذف الناعم
      final deletedAtVal = data['deletedAt'];
      int? deletedAtEpoch;
      if (deletedAtVal != null) {
        final deletedAtStr = deletedAtVal as String?;
        if (deletedAtStr != null && deletedAtStr.isNotEmpty) {
          try {
            deletedAtEpoch = DateTime.parse(deletedAtStr).millisecondsSinceEpoch ~/ 1000;
          } catch (_) {
            deletedAtEpoch = _asIntNullable(deletedAtVal);
          }
        } else {
          deletedAtEpoch = _asIntNullable(deletedAtVal);
        }
      }

      // إذا كان السجل محذوفاً، نحذفه محلياً
      if (deletedAtEpoch != null && deletedAtEpoch > 0) {
        final existing = await (database.select(database.shiftNotes)
              ..where((t) => t.localUuid.equals(localUuid)))
            .getSingleOrNull();
        if (existing != null) {
          await (database.delete(database.shiftNotes)
                ..where((t) => t.localUuid.equals(localUuid)))
              .go();
        }
        processed++;
        continue;
      }

      final companion = ShiftNotesCompanion(
        title: drift.Value(name),
        content: drift.Value(content),
        priority: const drift.Value('high'),
        shiftType: const drift.Value('all'),
        createdAt: drift.Value(createdAtEpoch),
        createdAtIso: drift.Value(createdAtIso),
        updatedAt: drift.Value(updatedAtEpoch),
        lastModified: drift.Value(lastModified),
        expiresAt: const drift.Value(null),
        isRead: const drift.Value(0),
        createdBy: const drift.Value('blacklist'),
        localUuid: drift.Value(localUuid),
        serverId: serverId != null
            ? drift.Value(serverId)
            : const drift.Value(null),
      );

      // upsert: البحث عن سجل موجود بنفس localUuid
      final existing = await (database.select(database.shiftNotes)
            ..where((t) => t.localUuid.equals(localUuid)))
          .getSingleOrNull();

      if (existing != null) {
        await (database.update(database.shiftNotes)
              ..where((t) => t.localUuid.equals(localUuid)))
            .write(companion);
      } else {
        await database.into(database.shiftNotes).insert(companion);
      }

      processed++;
    } catch (e) {
      _logger.warning(
        'Failed to sync blacklist ${doc.$id}: $e',
        tag: 'SYNC',
      );
    }
  }
  return processed;
}


Future<int> _syncShiftNotes(List<models.Document> documents) async {
  if (documents.isEmpty) return 0;
  var processed = 0;
  for (final doc in documents) {
    try {
      final data = Map<String, dynamic>.from(doc.data);
      data['localUuid'] ??= doc.$id;

      // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
      final localUuid = (data['localUuid'] as String?) ?? '';
      final existing = await (database.select(database.shiftNotes)
            ..where((t) => t.localUuid.equals(localUuid))
            ..limit(1))
          .getSingleOrNull();
      if (!_isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt)) {
        continue;
      }

      await _adapterRegistry.shiftNotes.upsertFromJson(
        data,
        src: Source.appwrite,
      );
      processed++;
    } catch (e) {
      _logger.warning(
        'Failed to sync shift note ${doc.$id}: $e',
        tag: 'SYNC',
      );
    }
  }
  return processed;
}


Future<int> _syncBookingNotes(List<models.Document> documents) async {
  if (documents.isEmpty) return 0;
  var processed = 0;
  for (final doc in documents) {
    try {
      final data = Map<String, dynamic>.from(doc.data);
      data['localUuid'] ??= doc.$id;

      // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
      final localUuid = (data['localUuid'] as String?) ?? '';
      final existing = await (database.select(database.bookingNotes)
            ..where((t) => t.localUuid.equals(localUuid))
            ..limit(1))
          .getSingleOrNull();
      if (!_isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt)) {
        continue;
      }

      await _adapterRegistry.bookingNotes.upsertFromJson(
        data,
        src: Source.appwrite,
      );
      processed++;
    } catch (e) {
      _logger.warning(
        'Failed to sync booking note ${doc.$id}: $e',
        tag: 'SYNC',
      );
    }
  }
  return processed;
}


Future<int> _syncBookingNights(List<models.Document> documents) async {
  if (documents.isEmpty) return 0;
  var processed = 0;
  final deferred = <models.Document>[];

  // المرحلة الأولى: معالجة الليالي
  for (final doc in documents) {
    try {
      final data = Map<String, dynamic>.from(doc.data);
      data['localUuid'] ??= doc.$id;

      // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
      final localUuid = (data['localUuid'] as String?) ?? '';
      final existing = await (database.select(database.bookingNights)
            ..where((t) => t.localUuid.equals(localUuid))
            ..limit(1))
          .getSingleOrNull();
      if (!_isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt)) {
        continue;
      }

      await _adapterRegistry.nights.upsertFromJson(
        data,
        src: Source.appwrite,
      );
      processed++;
    } catch (e) {
      // ✅ تأجيل الليالي فقط إذا كان الخطأ FOREIGN KEY أو NOT NULL constraint
      // bookingLocalId هو NOT NULL في booking_nights، لذا إذا فشل resolveBooking
      // سيحدث خطأ NOT NULL constraint بدلاً من FK constraint
      // لا نشمل 'constraint failed' عام لأنه يطابق UNIQUE أيضاً
      final errStr = e.toString();
      if (errStr.contains('FOREIGN KEY constraint failed') ||
          errStr.contains('NOT NULL constraint failed')) {
        _logger.debug(
          'Deferring booking night ${doc.$id}: FK/NOT NULL constraint (missing booking)',
          tag: 'SYNC',
        );
        deferred.add(doc);
      } else {
        _logger.warning(
          'Failed to sync booking night ${doc.$id}: $e',
          tag: 'SYNC',
        );
      }
    }
  }

  // المرحلة الثانية: إعادة محاولة الليالي المؤجلة
  if (deferred.isNotEmpty) {
    _logger.info(
      'Retrying ${deferred.length} deferred booking nights after all bookings synced',
      tag: 'SYNC',
    );

    for (final doc in deferred) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;
        await _adapterRegistry.nights.upsertFromJson(
          data,
          src: Source.appwrite,
        );
        processed++;
      } catch (e) {
        _logger.warning(
          'Failed to sync deferred booking night ${doc.$id} after retry: $e',
          tag: 'SYNC',
        );
      }
    }
  }

  return processed;
}


Future<int> _syncCashTransactions(List<models.Document> documents) async {
  if (documents.isEmpty) return 0;
  var processed = 0;
  for (final doc in documents) {
    try {
      final data = Map<String, dynamic>.from(doc.data);
      data['localUuid'] ??= doc.$id;

      // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
      final localUuid = (data['localUuid'] as String?) ?? '';
      final existing = await (database.select(database.cashTransactions)
            ..where((t) => t.localUuid.equals(localUuid))
            ..limit(1))
          .getSingleOrNull();
      if (!_isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt)) {
        continue;
      }

      await _adapterRegistry.cashTransactions.upsertFromJson(
        data,
        src: Source.appwrite,
      );
      processed++;
    } catch (e) {
      _logger.warning(
        'Failed to sync cash transaction ${doc.$id}: $e',
        tag: 'SYNC',
      );
    }
  }
  return processed;
}


Future<int> _syncSalaryCycles(List<models.Document> documents) async {
  if (documents.isEmpty) return 0;
  var processed = 0;
  final deferred = <Map<String, dynamic>>[];

  for (final doc in documents) {
    try {
      final data = Map<String, dynamic>.from(doc.data);
      data['localUuid'] ??= doc.$id;

      // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
      final localUuid = (data['localUuid'] as String?) ?? '';
      final existing = await (database.select(database.salaryCycles)
            ..where((t) => t.localUuid.equals(localUuid))
            ..limit(1))
          .getSingleOrNull();
      if (!_isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt)) {
        continue;
      }

      // ✅ حل FK الموظف بثلاث مستويات: UUID → id → serverId
      final remoteEmployeeId =
          _asIntSafe(data, 'employeeId') ?? _asIntSafe(data, 'employee_id');
      final employeeUuid = (data['employeeUuid'] as String?) ??
          (data['employee_uuid'] as String?) ??
          (data['employeeLocalUuid'] as String?) ??
          (data['employee_local_uuid'] as String?);

      Employee? employee;

      // الطريقة 1: البحث بالـ UUID (الأكثر موثوقية عبر الأجهزة)
      if (employeeUuid != null && employeeUuid.isNotEmpty) {
        employee = await (database.select(database.employees)
              ..where((e) => e.localUuid.equals(employeeUuid))
              ..limit(1))
            .getSingleOrNull();
      }

      // الطريقة 2: البحث بالـ id البعيد كـ id محلي
      if (employee == null && remoteEmployeeId != null) {
        employee = await (database.select(database.employees)
              ..where((e) => e.id.equals(remoteEmployeeId))
              ..limit(1))
            .getSingleOrNull();
      }

      // الطريقة 3: البحث بالـ serverId (id الأصلي من جهاز المصدر)
      if (employee == null && remoteEmployeeId != null) {
        employee = await (database.select(database.employees)
              ..where((e) => e.serverId.equals(remoteEmployeeId))
              ..limit(1))
            .getSingleOrNull();
      }

      if (employee == null) {
        _logger.warning(
          '⏭️ تخطي salary_cycle ${doc.$id}: الموظف $remoteEmployeeId (uuid=$employeeUuid) غير موجود محلياً (سجل يتيم)',
          tag: 'SYNC',
        );
        continue;
      }

      // ✅ استبدال employeeId البعيد بالمعرف المحلي الصحيح
      data['employeeId'] = employee.id;

      await _adapterRegistry.salaryCycles.upsertFromJson(
        data,
        src: Source.appwrite,
      );
      processed++;
    } on SqliteException catch (e) {
      if (e.resultCode == 787) {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;
        deferred.add(data);
        _logger.warning(
          '⏳ تأجيل salary_cycle ${doc.$id}: FK constraint failed',
          tag: 'SYNC',
        );
      } else {
        _logger.warning(
          'Failed to sync salary cycle ${doc.$id}: $e',
          tag: 'SYNC',
        );
      }
    } catch (e) {
      _logger.warning(
        'Failed to sync salary cycle ${doc.$id}: $e',
        tag: 'SYNC',
      );
    }
  }

  // ✅ إعادة محاولة السجلات المؤجلة
  if (deferred.isNotEmpty) {
    _logger.info(
      '🔄 إعادة محاولة ${deferred.length} سجل salary_cycles مؤجل...',
      tag: 'SYNC',
    );
    for (final data in deferred) {
      try {
        await _adapterRegistry.salaryCycles.upsertFromJson(
          data,
          src: Source.appwrite,
        );
        processed++;
      } catch (e) {
        _logger.warning(
          '⏭️ فشل نهائي لـ salary_cycle (يتيم): $e',
          tag: 'SYNC',
        );
      }
    }
  }

  return processed;
}


Future<int> _syncSalaryPayments(List<models.Document> documents) async {
  if (documents.isEmpty) return 0;
  var processed = 0;
  final deferred = <Map<String, dynamic>>[];

  for (final doc in documents) {
    try {
      final data = Map<String, dynamic>.from(doc.data);
      data['localUuid'] ??= doc.$id;

      // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
      final localUuid = (data['localUuid'] as String?) ?? '';
      final existing = await (database.select(database.salaryPayments)
            ..where((t) => t.localUuid.equals(localUuid))
            ..limit(1))
          .getSingleOrNull();
      if (!_isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt)) {
        continue;
      }

      // ✅ إصلاح: ترك المحول يحل FK لدورة الراتب عبر UUID → localId → serverId
      // الفحص المسبق السابق كان يبحث فقط بـ c.id.equals(remoteCycleId) ويتخطى
      // السجلات الصالحة التي يمكن للمحول حلها عبر UUID أو serverId
      // المحول (SalaryPaymentsAdapter.resolveRefs) يعالج 3 مستويات من البحث
      // وإذا فشل يستخدم d.Value.absent() مما يسبب NOT NULL constraint
      // الذي يتم التقاطه في on SqliteException أدناه ويُؤجل السجل

      await _adapterRegistry.salaryPayments.upsertFromJson(
        data,
        src: Source.appwrite,
      );
      processed++;
    } on SqliteException catch (e) {
      if (e.resultCode == 787) {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;
        deferred.add(data);
        _logger.warning(
          '⏳ تأجيل salary_payment ${doc.$id}: FK constraint failed',
          tag: 'SYNC',
        );
      } else {
        _logger.warning(
          'Failed to sync salary payment ${doc.$id}: $e',
          tag: 'SYNC',
        );
      }
    } catch (e) {
      _logger.warning(
        'Failed to sync salary payment ${doc.$id}: $e',
        tag: 'SYNC',
      );
    }
  }

  // ✅ إعادة محاولة السجلات المؤجلة
  if (deferred.isNotEmpty) {
    _logger.info(
      '🔄 إعادة محاولة ${deferred.length} سجل salary_payments مؤجل...',
      tag: 'SYNC',
    );
    for (final data in deferred) {
      try {
        await _adapterRegistry.salaryPayments.upsertFromJson(
          data,
          src: Source.appwrite,
        );
        processed++;
      } catch (e) {
        _logger.warning(
          '⏭️ فشل نهائي لـ salary_payment (يتيم): $e',
          tag: 'SYNC',
        );
      }
    }
  }

  return processed;
}


Future<int> _syncBookingPriceAdjustments(
  List<models.Document> documents,
) async {
  if (documents.isEmpty) return 0;
  var processed = 0;
  final deferred = <models.Document>[];

  // المرحلة الأولى: معالجة تعديلات الأسعار
  for (final doc in documents) {
    try {
      final data = Map<String, dynamic>.from(doc.data);
      data['localUuid'] ??= doc.$id;
      // إزالة id عند السحب من Appwrite لتجنب تعارض autoIncrement
      data.remove('id');

      // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
      final localUuid = (data['localUuid'] as String?) ?? '';
      final existing = await (database.select(database.bookingPriceAdjustments)
            ..where((t) => t.localUuid.equals(localUuid))
            ..limit(1))
          .getSingleOrNull();
      if (!_isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt)) {
        continue;
      }

      final result = await _adapterRegistry.bookingPriceAdjustments.upsertFromJson(
        data,
        src: Source.appwrite,
      );
      
      // Refresh calculations for the affected booking
      if (result > 0) {
         final adj = await (database.select(database.bookingPriceAdjustments)
          ..where((t) => t.id.equals(result)))
          .getSingleOrNull();
         
         if (adj != null && adj.bookingLocalId != null) {
            await _bookingsRepository.derivedFields.refreshForBookingId(adj.bookingLocalId!);
         }
      }
      
      processed++;
    } catch (e) {
      // ✅ تأجيل تعديل السعر فقط إذا كان الخطأ FOREIGN KEY أو NOT NULL constraint
      // لا نشمل 'constraint failed' عام لأنه يطابق UNIQUE أيضاً
      final errStr = e.toString();
      if (errStr.contains('FOREIGN KEY constraint failed') ||
          errStr.contains('NOT NULL constraint failed')) {
        _logger.debug(
          'Deferring booking price adjustment ${doc.$id}: FK/NOT NULL constraint (missing booking)',
          tag: 'SYNC',
        );
        deferred.add(doc);
      } else {
        _logger.warning(
          'Failed to sync booking price adjustment ${doc.$id}: $e',
          tag: 'SYNC',
        );
      }
    }
  }

  // المرحلة الثانية: إعادة محاولة التعديلات المؤجلة
  if (deferred.isNotEmpty) {
    _logger.info(
      'Retrying ${deferred.length} deferred booking price adjustments after all bookings synced',
      tag: 'SYNC',
    );

    for (final doc in deferred) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;
        data.remove('id');

        final result = await _adapterRegistry.bookingPriceAdjustments.upsertFromJson(
          data,
          src: Source.appwrite,
        );
        
        if (result > 0) {
          final adj = await (database.select(database.bookingPriceAdjustments)
            ..where((t) => t.id.equals(result)))
            .getSingleOrNull();
          
          if (adj != null && adj.bookingLocalId != null) {
            await _bookingsRepository.derivedFields.refreshForBookingId(adj.bookingLocalId!);
          }
        }
        
        processed++;
      } catch (e) {
        _logger.warning(
          'Failed to sync deferred booking price adjustment ${doc.$id} after retry: $e',
          tag: 'SYNC',
        );
      }
    }
  }

  return processed;
}

// ─── PriceAdjustments ──────────────────────────────────────────────────


Future<int> _syncPriceAdjustments(List<models.Document> documents) async {
   if (documents.isEmpty) return 0;
   var processed = 0;
   // ✅ P1-13 إصلاح: تم نقل إنشاء الخدمة خارج الحلقة
   final derivedFieldsService = BookingDerivedFieldsService(database);
   for (final doc in documents) {
     try {
       final data = Map<String, dynamic>.from(doc.data);
       data['localUuid'] ??= doc.$id;

       // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
       final localUuid = (data['localUuid'] as String?) ?? '';
       final existing = await (database.select(database.priceAdjustments)
             ..where((t) => t.localUuid.equals(localUuid))
             ..limit(1))
           .getSingleOrNull();
       if (!_isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt)) {
         continue;
       }

       await _adapterRegistry.priceAdjustments.upsertFromJson(
         data,
         src: Source.appwrite,
       );

       // ✅ إعادة حساب الحجوزات المتأثرة بعد سحب تغيير سعر الغرفة
       final targetType = data['targetType'] as String? ?? '';
       final targetUuid = data['targetUuid'] as String? ?? '';
       if (targetType == 'room' && targetUuid.isNotEmpty) {
         try {
           // تحديث سعر الغرفة المحلي
           final room = await (database.select(database.rooms)
                 ..where((r) => r.localUuid.equals(targetUuid))
                 ..limit(1))
               .getSingleOrNull();
           if (room != null) {
             final newValue = data['newValue'];
             if (newValue != null) {
               await (database.update(database.rooms)
                     ..where((r) => r.localUuid.equals(targetUuid)))
                   .write(RoomsCompanion(
                     price: drift.Value((newValue as num).toDouble()),
                     updatedAt: drift.Value(Time.nowEpoch()),
                     lastModified: drift.Value(Time.nowEpoch()),
                   ),);
             }
             // إعادة حساب الحجوزات النشطة للغرفة
             final activeBookings = await (database.select(database.bookings)
                   ..where((b) => b.roomNumber.equals(room.roomNumber))
                   ..where((b) => b.deletedAt.isNull())
                   ..where((b) => b.actualCheckout.isNull()))
                 .get();
             for (final booking in activeBookings) {
               await derivedFieldsService
                   .refreshForBookingId(booking.id, forceRebuild: true);
             }
           }
         } catch (e) {
           _logger.warning(
             'فشل إعادة حساب الحجوزات بعد سحب price_adjustment $localUuid: $e',
             tag: 'SYNC',
           );
         }
       }

       processed++;
     } catch (e) {
       _logger.warning(
         'Failed to sync price adjustment ${doc.$id}: $e',
         tag: 'SYNC',
       );
     }
   }
   return processed;
 }

// ─── AuditLogs ────────────────────────────────────────────────────────


Future<int> _syncAuditLogs(List<models.Document> documents) async {
  if (documents.isEmpty) return 0;
  var processed = 0;
  for (final doc in documents) {
    try {
      final data = Map<String, dynamic>.from(doc.data);
      data['localUuid'] ??= doc.$id;

      // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
      // AuditLog لا يحتوي على lastModified — نستخدم timestamp للمقارنة
      final localUuid = (data['localUuid'] as String?) ?? '';
      final existing = await (database.select(database.auditLogs)
            ..where((t) => t.localUuid.equals(localUuid))
            ..limit(1))
          .getSingleOrNull();
      if (!_isRemoteDataNewer(data, existing?.timestamp)) {
        continue;
      }

      await _adapterRegistry.auditLogs.upsertFromJson(
        data,
        src: Source.appwrite,
      );
      processed++;
    } catch (e) {
      _logger.warning(
        'Failed to sync audit log ${doc.$id}: $e',
        tag: 'SYNC',
      );
    }
  }
  return processed;
}

// ─── PaymentVoids ─────────────────────────────────────────────────────

/// رفع كل الإعدادات المحلية من SharedPreferences → Appwrite

Future<int> _syncAppSettings(List<models.Document> documents) async {
  if (documents.isEmpty) return 0;
  var processed = 0;
  final prefs = await SharedPreferences.getInstance();
  final deviceId = await _getDeviceIdForPrefs();

  for (final doc in documents) {
    try {
      final data = doc.data;

      // ── WhatsApp fields ──
      const waStringFields = {
        'wa_api_type': 'wa_api_type',
        'wa_api_base_url': 'wa_api_base_url',
        'wa_api_instance_id': 'wa_api_instance_id',
        'wa_custom_url_template': 'wa_custom_url_template',
        'wa_sendzen_api_key': 'wa_sendzen_api_key',
        'wa_sendzen_from_number': 'wa_sendzen_from_number',
      };

      for (final entry in waStringFields.entries) {
        final value = data[entry.key];
        if (value != null && value.toString().isNotEmpty) {
          await prefs.setString(entry.value, value.toString());
        }
      }

      // ✅ P0-7 إصلاح: فك تشفير wa_api_token قبل الحفظ
      final waToken = data['wa_api_token']?.toString();
      if (waToken != null && waToken.isNotEmpty) {
        final key = SecureStorage.getEncryptionKey(null);
        final decryptedToken = SecureStorage.decryptValue(waToken, key);
        await prefs.setString('wa_api_token', decryptedToken);
      }

      // wa_template → whatsapp_template (مفتاح مختلف في prefs)
      final template = data['wa_template'];
      if (template != null && template.toString().isNotEmpty) {
        await prefs.setString('whatsapp_template', template.toString());
      }

      // ── Telegram fields ──
      const tgStringFields = {
        'telegram_chat_id': 'telegram_chat_id',
        'telegram_daily_report_time': 'telegram_daily_report_time',
      };

      for (final entry in tgStringFields.entries) {
        final value = data[entry.key];
        if (value != null && value.toString().isNotEmpty) {
          await prefs.setString(entry.value, value.toString());
        }
      }

      // ✅ P0-7 إصلاح: فك تشفير telegram_bot_token قبل الحفظ
      final tgToken = data['telegram_bot_token']?.toString();
      if (tgToken != null && tgToken.isNotEmpty) {
        final key = SecureStorage.getEncryptionKey(null);
        final decryptedToken = SecureStorage.decryptValue(tgToken, key);
        await prefs.setString('telegram_bot_token', decryptedToken);
      }

      const tgBoolFields = {
        'telegram_enabled': 'telegram_enabled',
        'telegram_notifications_enabled': 'telegram_notifications_enabled',
        'telegram_daily_report_enabled': 'telegram_daily_report_enabled',
      };

      for (final entry in tgBoolFields.entries) {
        final value = data[entry.key];
        if (value != null) {
          await prefs.setBool(entry.value, value as bool);
        }
      }

      // ── Lark fields (non-sensitive) ──
      const larkStringFields = {
        'lark_app_id': 'lark_app_id',
        'lark_webhook_url': 'lark_webhook_url',
        'lark_daily_report_time': 'lark_daily_report_time',
        'lark_daily_report_chat_id': 'lark_daily_report_chat_id',
      };

      for (final entry in larkStringFields.entries) {
        final value = data[entry.key];
        if (value != null && value.toString().isNotEmpty) {
          await prefs.setString(entry.value, value.toString());
        }
      }

      // ✅ P0-7 إصلاح: فك تشفير lark_app_secret قبل الحفظ
      final larkSecret = data['lark_app_secret']?.toString();
      if (larkSecret != null && larkSecret.isNotEmpty) {
        final key = SecureStorage.getEncryptionKey(null);
        final decryptedSecret = SecureStorage.decryptValue(larkSecret, key);
        await prefs.setString('lark_app_secret', decryptedSecret);
      }

      const larkBoolFields = {
        'lark_enabled': 'lark_enabled',
        'lark_daily_report_enabled': 'lark_daily_report_enabled',
      };

      for (final entry in larkBoolFields.entries) {
        final value = data[entry.key];
        if (value != null) {
          await prefs.setBool(entry.value, value as bool);
        }
      }

      processed++;
      _logger.debug('AppSettings synced: ${doc.$id}', tag: 'SYNC');
    } catch (e) {
      _logger.warning(
        'Failed to sync app_settings ${doc.$id}: $e',
        tag: 'SYNC',
      );
    }
  }
  return processed;
}

Future<String> _getDeviceIdForPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('appwrite_delta_device_id') ?? 'default';
}


Future<int> _syncPaymentVoids(List<models.Document> documents) async {
  if (documents.isEmpty) return 0;
  var processed = 0;
  for (final doc in documents) {
    try {
      final data = Map<String, dynamic>.from(doc.data);
      data['localUuid'] ??= doc.$id;

      // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
      final localUuid = (data['localUuid'] as String?) ?? '';
      final existing = await (database.select(database.paymentVoids)
            ..where((t) => t.localUuid.equals(localUuid))
            ..limit(1))
          .getSingleOrNull();
      if (!_isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt)) {
        continue;
      }

      await _adapterRegistry.paymentVoids.upsertFromJson(
        data,
        src: Source.appwrite,
      );
      processed++;
    } catch (e) {
      _logger.warning(
        'Failed to sync payment void ${doc.$id}: $e',
        tag: 'SYNC',
      );
    }
  }
  return processed;
}


Future<void> _performPostSyncIntegrityCheck() async {
  try {
    // 1. فحص انتهاكات المفاتيح الأجنبية (Foreign Key Violations)
    final violations = await database.customSelect(
      'PRAGMA foreign_key_check',
      readsFrom: Set.unmodifiable({}),
    ).get();

    if (violations.isNotEmpty) {
      _logger.warning(
        '⚠️ تم اكتشاف ${violations.length} انتهاك للمفاتيح الأجنبية بعد المزامنة',
        tag: 'SYNC_INTEGRITY',
      );
      
      for (final row in violations) {
        final table = row.data['table']?.toString() ?? '';
        final rowId = row.data['rowid']?.toString() ?? '';
        final parent = row.data['parent']?.toString() ?? '';
        _logger.debug(
          'FK Violation: Table=$table, RowId=$rowId, Parent=$parent',
          tag: 'SYNC_INTEGRITY',
        );

        // ✅ إصلاح تلقائي: حذف السجلات اليتيمة (التي تشير لآباء غير موجودين)
        try {
          if (table == 'salary_withdrawals' || table == 'salary_cycles') {
            // حذف السجل الذي يشير لموظف غير موجود
            await database.customStatement(
              'DELETE FROM $table WHERE rowid = ?',
              [int.tryParse(rowId)],
            );
            _logger.info(
              '🧹 تم حذف سجل يتيم من $table (rowid=$rowId)',
              tag: 'SYNC_INTEGRITY',
            );
          } else if (table == 'salary_payments') {
            // حذف السجل الذي يشير لدورة راتب غير موجودة
            await database.customStatement(
              'DELETE FROM $table WHERE rowid = ?',
              [int.tryParse(rowId)],
            );
            _logger.info(
              '🧹 تم حذف سجل يتيم من $table (rowid=$rowId)',
              tag: 'SYNC_INTEGRITY',
            );
          } else if (table == 'payments' && parent == 'bookings') {
            // دفعة تشير لحجز غير موجود - إزالة FK فقط (لأن bookingLocalId nullable)
            await database.customStatement(
              'UPDATE payments SET booking_local_id = NULL, booking_uuid_cache = NULL WHERE rowid = ?',
              [int.tryParse(rowId)],
            );
            _logger.info(
              '🧹 تم إزالة ربط الدفعة اليتيمة بالحجز (rowid=$rowId)',
              tag: 'SYNC_INTEGRITY',
            );
          } else if (table == 'debts' && parent == 'bookings') {
            // دين يشير لحجز غير موجود - إزالة FK فقط (لأن bookingLocalId nullable)
            await database.customStatement(
              'UPDATE debts SET booking_local_id = NULL WHERE rowid = ?',
              [int.tryParse(rowId)],
            );
            _logger.info(
              '🧹 تم إزالة ربط الدين اليتيم بالحجز (rowid=$rowId)',
              tag: 'SYNC_INTEGRITY',
            );
          }
        } catch (fixError) {
          _logger.warning(
            '⚠️ فشل إصلاح سجل يتيم في $table: $fixError',
            tag: 'SYNC_INTEGRITY',
          );
        }
      }

      // تسجيل الأخطاء في Crashlytics للمراقبة
      await CrashlyticsService.instance.recordSyncError(
        operation: 'post_sync_integrity_check',
        error: 'Foreign key violations detected and auto-fixed: ${violations.length} rows',
        context: {'violations_count': violations.length.toString()},
      );

      // ✅ إصلاح تلقائي: حذف السجلات التي تشير إلى آباء غير موجودين
      // هذه سجلات أيتيمة نتجت عن حجوزات محذوفة على أجهزة أخرى
      // نستخدم soft delete (تعيين deletedAt) بدلاً من الحذف الفعلي
      try {
        for (final row in violations) {
          final table = row.data['table']?.toString();
          final rowId = row.data['rowid'];

          if (table == null || rowId == null) continue;

          _logger.info(
            '🔧 إصلاح تلقائي: حذف سجل يتيم من $table (rowId=$rowId)',
            tag: 'SYNC_INTEGRITY',
          );

          try {
            final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
            if (table == 'payments') {
              await (database.update(database.payments)
                    ..where((t) => t.id.equals(rowId as int)))
                  .write(PaymentsCompanion(
                deletedAt: drift.Value(nowEpoch),
              ));
            } else if (table == 'debts') {
              await (database.update(database.debts)
                    ..where((t) => t.id.equals(rowId as int)))
                  .write(DebtsCompanion(
                deletedAt: drift.Value(nowEpoch),
              ));
            } else if (table == 'booking_nights') {
              await (database.update(database.bookingNights)
                    ..where((t) => t.id.equals(rowId as int)))
                  .write(BookingNightsCompanion(
                deletedAt: drift.Value(nowEpoch),
              ));
            } else if (table == 'booking_price_adjustments') {
              await (database.update(database.bookingPriceAdjustments)
                    ..where((t) => t.id.equals(rowId as int)))
                  .write(BookingPriceAdjustmentsCompanion(
                deletedAt: drift.Value(nowEpoch),
              ));
            }
          } catch (fixError) {
            _logger.warning(
              '⚠️ فشل إصلاح سجل يتيم في $table (rowId=$rowId): $fixError',
              tag: 'SYNC_INTEGRITY',
            );
          }
        }
      } catch (e) {
        _logger.warning('⚠️ فشل إصلاح انتهاكات FK: $e', tag: 'SYNC_INTEGRITY');
      }
    }

    // 2. التحقق من السجلات اليتيمة - باستخدام JOIN بدل الأعمدة غير الموجودة
    // ✅ إصلاح: استخدام LEFT JOIN للتحقق من وجود الحجز بدلاً من booking_uuid_cache
    // (booking_uuid_cache موجود فقط في جدول payments وليس في جدول debts)
    final orphanPayments = await database.customSelect('''
      SELECT COUNT(*) as count FROM payments p
      LEFT JOIN bookings b ON p.booking_local_id = b.id
      WHERE p.booking_local_id IS NOT NULL AND b.id IS NULL AND p.deleted_at IS NULL
    ''').getSingle();
    
    final orphanPayCount = orphanPayments.read<int>('count');
    if (orphanPayCount > 0) {
      _logger.warning(
        '⚠️ يوجد $orphanPayCount دفعة يتيمة (بدون ربط بحجز موجود)',
        tag: 'SYNC_INTEGRITY',
      );
    }

    // 3. التحقق من سحوبات الرواتب اليتيمة
    final orphanWithdrawals = await database.customSelect('''
      SELECT COUNT(*) as count FROM salary_withdrawals sw
      LEFT JOIN employees e ON sw.employee_id = e.id
      WHERE e.id IS NULL AND sw.deleted_at IS NULL
    ''').getSingle();

    final orphanWdCount = orphanWithdrawals.read<int>('count');
    if (orphanWdCount > 0) {
      _logger.warning(
        '⚠️ يوجد $orphanWdCount سحب راتب يتيم (بدون موظف موجود)',
        tag: 'SYNC_INTEGRITY',
      );
    }

    // 4. التحقق من دورات الرواتب اليتيمة
    final orphanCycles = await database.customSelect('''
      SELECT COUNT(*) as count FROM salary_cycles sc
      LEFT JOIN employees e ON sc.employee_id = e.id
      WHERE e.id IS NULL AND sc.deleted_at IS NULL
    ''').getSingle();

    final orphanCycleCount = orphanCycles.read<int>('count');
    if (orphanCycleCount > 0) {
      _logger.warning(
        '⚠️ يوجد $orphanCycleCount دورة راتب يتيمة (بدون موظف موجود)',
        tag: 'SYNC_INTEGRITY',
      );
    }

    _logger.info('✅ اكتمل فحص سلامة البيانات بعد المزامنة', tag: 'SYNC_INTEGRITY');
  } catch (e, st) {
    _logger.error(
      '❌ فشل إجراء فحص سلامة البيانات',
      error: e,
      stackTrace: st,
      tag: 'SYNC_INTEGRITY',
    );
  }
}


Future<Room?> _getRoomByLocalUuid(String localUuid) {
  return (database.select(
    database.rooms,
  )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
}


Future<Booking?> _getBookingByLocalUuid(String localUuid) {
  return (database.select(
    database.bookings,
  )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
}


Future<Expense?> _getExpenseByLocalUuid(String localUuid) {
  return (database.select(
    database.expenses,
  )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
}


Future<Payment?> _getPaymentByLocalUuid(String localUuid) {
  return (database.select(
    database.payments,
  )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
}


Future<Debt?> _getDebtByLocalUuid(String localUuid) {
  return (database.select(
    database.debts,
  )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
}

// ─── GuestInfos ──────────────────────────────────────────────────────────


Future<GuestInfo?> _getGuestInfoByLocalUuid(String localUuid) {
  return (database.select(
    database.guestInfos,
  )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
}

// ─── SalaryWithdrawals ──────────────────────────────────────────────────


Future<SalaryWithdrawal?> _getSalaryWithdrawalByLocalUuid(String localUuid) {
  return (database.select(
    database.salaryWithdrawals,
  )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
}


Future<int?> _getLocalEntityDeletedAt(String entity, String localUuid) async {
  try {
    switch (entity) {
      case 'bookings':
        final b = await _getBookingByLocalUuid(localUuid);
        return b?.deletedAt;
      case 'rooms':
        final r = await _getRoomByLocalUuid(localUuid);
        return r?.deletedAt;
      case 'employees':
        final e = await _getEmployeeByLocalUuid(localUuid);
        return e?.deletedAt;
      case 'expenses':
        final e = await _getExpenseByLocalUuid(localUuid);
        return e?.deletedAt;
      case 'payments':
        final p = await _getPaymentByLocalUuid(localUuid);
        return p?.deletedAt;
      case 'debts':
        final d = await _getDebtByLocalUuid(localUuid);
        return d?.deletedAt;
      default:
        return null;
    }
  } catch (_) {
    return null;
  }
}

/// جلب lastModified لسجل محلي بناءً على entity و localUuid

Future<int?> _getLocalLastModified(String entity, String localUuid) async {
  switch (entity) {
    case 'rooms':
      return _getLocalRoomLastModified(localUuid);
    case 'bookings':
      return _getLocalBookingLastModified(localUuid);
    case 'employees':
      return _getLocalEmployeeLastModified(localUuid);
    case 'expenses':
      return _getLocalExpenseLastModified(localUuid);
    case 'payments':
      return _getLocalPaymentLastModified(localUuid);
    case 'debts':
      return _getLocalDebtLastModified(localUuid);
    case 'guest_infos':
      return _getLocalGuestInfoLastModified(localUuid);
    case 'salary_withdrawals':
      return _getLocalSalaryWithdrawalLastModified(localUuid);
    case 'booking_price_adjustments':
      return _getLocalBookingPriceAdjustmentLastModified(localUuid);
    case 'shift_notes':
    case 'blacklist':
      return _getLocalShiftNoteLastModified(localUuid);
    case 'booking_notes':
      return _getLocalBookingNoteLastModified(localUuid);
    case 'booking_nights':
      return _getLocalBookingNightLastModified(localUuid);
    case 'cash_transactions':
      return _getLocalCashTransactionLastModified(localUuid);
    case 'salary_cycles':
      return _getLocalSalaryCycleLastModified(localUuid);
    case 'salary_payments':
      return _getLocalSalaryPaymentLastModified(localUuid);
    case 'price_adjustments':
      return _getLocalPriceAdjustmentLastModified(localUuid);
    case 'audit_logs':
      return _getLocalAuditLogLastModified(localUuid);
    case 'payment_voids':
      return _getLocalPaymentVoidLastModified(localUuid);
    default:
      // للكيانات غير المعروفة، نعيد null — الحذف الآمن
      return null;
  }
}

/// جلب حقل origin لسجل محلي بناءً على entity و localUuid
/// يُستخدم لتحديد ما إذا كانت البيانات قادمة من السيرفر ('server')
/// أو تم إنشاؤها محلياً ('local')

Future<String?> _getLocalOrigin(String entity, String localUuid) async {
  try {
    // استخدام استعلام SQL مباشر لتجنب مشاكل الأنواع العامة في Drift
    final tableName = _entityToTableName(entity);
    if (tableName == null) return null;

    final rows = await database.customSelect(
      'SELECT origin FROM $tableName WHERE local_uuid = ? LIMIT 1',
      variables: [drift.Variable.withString(localUuid)],
      readsFrom: Set.unmodifiable({}),
    ).get();

    if (rows.isEmpty) return null;
    return rows.first.data['origin']?.toString();
  } catch (e) {
    _logger.debug('Failed to get origin for $entity/$localUuid: $e', tag: 'SYNC');
    return null;
  }
}

/// تحويل اسم الكيان إلى اسم الجدول في قاعدة البيانات
String? _entityToTableName(String entity) {
  switch (entity) {
    case 'rooms':
      return 'rooms';
    case 'bookings':
      return 'bookings';
    case 'employees':
      return 'employees';
    case 'expenses':
      return 'expenses';
    case 'payments':
      return 'payments';
    case 'debts':
      return 'debts';
    case 'guest_infos':
      return 'guest_infos';
    case 'salary_withdrawals':
      return 'salary_withdrawals';
    case 'booking_price_adjustments':
      return 'booking_price_adjustments';
    case 'shift_notes':
    case 'blacklist':
      return 'shift_notes';
    case 'booking_notes':
      return 'booking_notes';
    case 'booking_nights':
      return 'booking_nights';
    case 'cash_transactions':
      return 'cash_transactions';
    case 'salary_cycles':
      return 'salary_cycles';
    case 'salary_payments':
      return 'salary_payments';
    case 'price_adjustments':
      return 'price_adjustments';
    case 'audit_logs':
      return null; // AuditLogs لا تحتوي على حقل origin
    case 'payment_voids':
      return 'payment_voids';
    default:
      return null;
  }
}


Future<int?> _getLocalRoomLastModified(String localUuid) async {
  final row = await (database.select(database.rooms)
        ..where((t) => t.localUuid.equals(localUuid))
        ..limit(1))
      .getSingleOrNull();
  return row?.lastModified;
}


Future<int?> _getLocalBookingLastModified(String localUuid) async {
  final row = await (database.select(database.bookings)
        ..where((t) => t.localUuid.equals(localUuid))
        ..limit(1))
      .getSingleOrNull();
  return row?.lastModified;
}


Future<int?> _getLocalEmployeeLastModified(String localUuid) async {
  final row = await (database.select(database.employees)
        ..where((t) => t.localUuid.equals(localUuid))
        ..limit(1))
      .getSingleOrNull();
  return row?.lastModified;
}


Future<int?> _getLocalExpenseLastModified(String localUuid) async {
  final row = await (database.select(database.expenses)
        ..where((t) => t.localUuid.equals(localUuid))
        ..limit(1))
      .getSingleOrNull();
  return row?.lastModified;
}


Future<int?> _getLocalPaymentLastModified(String localUuid) async {
  final row = await _getPaymentByLocalUuid(localUuid);
  return row?.lastModified;
}


Future<int?> _getLocalDebtLastModified(String localUuid) async {
  final row = await _getDebtByLocalUuid(localUuid);
  return row?.lastModified;
}


Future<int?> _getLocalGuestInfoLastModified(String localUuid) async {
  final row = await (database.select(database.guestInfos)
        ..where((t) => t.localUuid.equals(localUuid))
        ..limit(1))
      .getSingleOrNull();
  return row?.lastModified;
}


Future<int?> _getLocalSalaryWithdrawalLastModified(String localUuid) async {
  final row = await (database.select(database.salaryWithdrawals)
        ..where((t) => t.localUuid.equals(localUuid))
        ..limit(1))
      .getSingleOrNull();
  return row?.lastModified;
}


Future<int?> _getLocalBookingPriceAdjustmentLastModified(
  String localUuid,
) async {
  final row = await (database.select(database.bookingPriceAdjustments)
        ..where((t) => t.localUuid.equals(localUuid))
        ..limit(1))
      .getSingleOrNull();
  return row?.lastModified;
}


Future<int?> _getLocalShiftNoteLastModified(String localUuid) async {
  final row = await (database.select(database.shiftNotes)
        ..where((t) => t.localUuid.equals(localUuid))
        ..limit(1))
      .getSingleOrNull();
  return row?.lastModified;
}


Future<int?> _getLocalBookingNoteLastModified(String localUuid) async {
  final row = await (database.select(database.bookingNotes)
        ..where((t) => t.localUuid.equals(localUuid))
        ..limit(1))
      .getSingleOrNull();
  return row?.lastModified;
}


Future<int?> _getLocalBookingNightLastModified(String localUuid) async {
  final row = await (database.select(database.bookingNights)
        ..where((t) => t.localUuid.equals(localUuid))
        ..limit(1))
      .getSingleOrNull();
  return row?.lastModified;
}


Future<int?> _getLocalCashTransactionLastModified(String localUuid) async {
  final row = await (database.select(database.cashTransactions)
        ..where((t) => t.localUuid.equals(localUuid))
        ..limit(1))
      .getSingleOrNull();
  return row?.lastModified;
}


Future<int?> _getLocalSalaryCycleLastModified(String localUuid) async {
  final row = await (database.select(database.salaryCycles)
        ..where((t) => t.localUuid.equals(localUuid))
        ..limit(1))
      .getSingleOrNull();
  return row?.lastModified;
}


Future<int?> _getLocalSalaryPaymentLastModified(String localUuid) async {
  final row = await (database.select(database.salaryPayments)
        ..where((t) => t.localUuid.equals(localUuid))
        ..limit(1))
      .getSingleOrNull();
  return row?.lastModified;
}


Future<int?> _getLocalPriceAdjustmentLastModified(String localUuid) async {
  final row = await (database.select(database.priceAdjustments)
        ..where((t) => t.localUuid.equals(localUuid))
        ..limit(1))
      .getSingleOrNull();
  return row?.lastModified;
}


Future<int?> _getLocalAuditLogLastModified(String localUuid) async {
  final row = await (database.select(database.auditLogs)
        ..where((t) => t.localUuid.equals(localUuid))
        ..limit(1))
      .getSingleOrNull();
  // AuditLogs لا تحتوي على lastModified — نستخدم timestamp
  return row?.timestamp;
}


Future<int?> _getLocalPaymentVoidLastModified(String localUuid) async {
  final row = await (database.select(database.paymentVoids)
        ..where((t) => t.localUuid.equals(localUuid))
        ..limit(1))
      .getSingleOrNull();
  return row?.lastModified;
}

/// قراءة آخر timestamp لسحب البيانات من جدول SyncState

Future<SalaryPayment?> _getSalaryPaymentByLocalUuid(String uuid) {
  return (database.select(database.salaryPayments)
        ..where((t) => t.localUuid.equals(uuid))
        ..limit(1))
      .getSingleOrNull();
}


Future<CashTransaction?> _getCashTransactionByLocalUuid(String uuid) {
  return (database.select(database.cashTransactions)
        ..where((t) => t.localUuid.equals(uuid))
        ..limit(1))
      .getSingleOrNull();
}


Future<ShiftNote?> _getShiftNoteByLocalUuid(String uuid) {
  return (database.select(database.shiftNotes)
        ..where((t) => t.localUuid.equals(uuid))
        ..limit(1))
      .getSingleOrNull();
}

// ─── Blacklist ──────────────────────────────────────────────────────────


Future<ShiftNote?> _getBlacklistShiftNoteByLocalUuid(String uuid) {
  return (database.select(database.shiftNotes)
        ..where((t) =>
            t.localUuid.equals(uuid) &
            t.createdBy.equals('blacklist'),)
        ..limit(1))
      .getSingleOrNull();
}

// ─── PriceAdjustments ─────────────────────────────────────────────────


Future<Employee?> _getEmployeeByLocalUuid(String uuid) {
  return (database.select(database.employees)
        ..where((t) => t.localUuid.equals(uuid))
        ..limit(1))
      .getSingleOrNull();
}


Future<BookingNote?> _getBookingNoteByLocalUuid(String uuid) {
  return (database.select(database.bookingNotes)
        ..where((t) => t.localUuid.equals(uuid))
        ..limit(1))
      .getSingleOrNull();
}


Future<BookingNight?> _getBookingNightByLocalUuid(String uuid) {
  return (database.select(database.bookingNights)
        ..where((t) => t.localUuid.equals(uuid))
        ..limit(1))
      .getSingleOrNull();
}


Future<SalaryCycle?> _getSalaryCycleByLocalUuid(String uuid) {
  return (database.select(database.salaryCycles)
        ..where((t) => t.localUuid.equals(uuid))
        ..limit(1))
      .getSingleOrNull();
}


Future<BookingPriceAdjustment?> _getBookingPriceAdjustmentByLocalUuid(String uuid) {
  return (database.select(database.bookingPriceAdjustments)
        ..where((t) => t.localUuid.equals(uuid))
        ..limit(1))
      .getSingleOrNull();
}

/// تحميل جميع البيانات من الخادم

}
