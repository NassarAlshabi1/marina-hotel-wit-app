import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/id.dart';
import '../../utils/time.dart';
import '../adapters/adapter_registry.dart';
import '../adapters/source.dart';
import '../appwrite_service.dart';
import '../appwrite_sync_utils.dart';
import '../booking_derived_fields_service.dart';
import '../booking_price_adjustment_service.dart';
import '../crashlytics_service.dart';
import '../daos/outbox_dao.dart';
import '../local_db.dart';
import '../repositories/bookings_repository.dart';
import '../repositories/rooms_repository.dart';
import '../sync_constants.dart';
import 'sync_error_service.dart';
import '../appwrite_logger.dart';
import '../appwrite_error_handler.dart';

/// خدمة دفع التغييرات المحلية إلى Appwrite Cloud
/// مسؤولة عن معالجة outbox لكل الكيانات ورفعها إلى السحابة
class SyncPushService {

  final AppwriteService appwriteService;
  final AppDatabase database;
  final OutboxDao outboxDao;
  late final AdapterRegistry _adapterRegistry;
  late final BookingsRepository _bookingsRepository;
  late final RoomsRepository _roomsRepository;
  final AppwriteLogger _logger;
  final AppwriteErrorHandler _errorHandler;
  final SyncErrorService _err;
  double _adaptiveBatchSize = 50;

  SyncPushService({
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
        _err = errorService ?? SyncErrorService(tag: 'PUSH'),
        _logger = logger ?? AppwriteLogger(),
        _errorHandler = errorHandler ?? AppwriteErrorHandler();

int _asInt(dynamic value, {int fallback = 0}) {
  final result = _asIntNullable(value);
  return result ?? fallback;
}

int? _asIntNullable(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String && value.isNotEmpty) {
    final parsedInt = int.tryParse(value);
    if (parsedInt != null) {
      return parsedInt;
    }
    final parsedDouble = double.tryParse(value);
    if (parsedDouble != null) {
      return parsedDouble.toInt();
    }
  }
  return null;
}

/// ✅ تحويل آمن للقيمة الرقمية من Map — يتعامل مع int/double/num/String
/// يُستخدم بدل `data['key'] as int?` الذي قد يرمي TypeError مع double
int? _asIntSafe(Map<String, dynamic> data, String key) {
  final value = data[key];
  return _asIntNullable(value);
}


Future<int> _pushAllEntities() async {
  // ✅ فحص الاتصال أولاً
  try {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      _logger.warning('⚠️ لا يوجد اتصال بالإنترنت - تم تأجيل الرفع', tag: 'SYNC');
      return 0;
    }
  } catch (_) {}

  int totalProcessed = 0;
  int consecutiveFailures = 0;

  while (true) {
    final batchSize = _adaptiveBatchSize.round();
    final entries = await outboxDao.takeBatch(batchSize, sources: const ['local']);
    if (entries.isEmpty) {
      break;
    }

    int processedInBatch = 0;
    for (final entry in entries) {
      try {
        final timeoutSeconds = 30;
        final success = await _processOutboxEntry(entry)
            .timeout(Duration(seconds: timeoutSeconds));
        if (success) {
          await outboxDao.removeById(entry.id);
          processedInBatch++;
        }
      } catch (e) {
        if (e is TimeoutException) {
          _logger.warning('⏱️ Timeout processing entry ${entry.id}', tag: 'SYNC');
        }
      }
    }

    // Adaptive batch size
    if (processedInBatch == entries.length) {
      _adaptiveBatchSize = (_adaptiveBatchSize * 1.3).clamp(10, 200);
      consecutiveFailures = 0;
    } else {
      _adaptiveBatchSize = (_adaptiveBatchSize * 0.6).clamp(5, 100);
      consecutiveFailures++;
    }

    totalProcessed += processedInBatch;

    if (consecutiveFailures >= 3) {
      _logger.warning('⛔ 3 دفعات فاشلة متتالية - إيقاف المزامنة', tag: 'SYNC');
      break;
    }

    if (entries.length < batchSize) {
      break;
    }
  }
  return totalProcessed;
}


Future<bool> _processOutboxEntry(OutboxData entry) async {
  try {
    switch (entry.entity) {
      case 'rooms':
        return await _processRoomEntry(entry);
      case 'bookings':
        return await _processBookingEntry(entry);
      case 'expenses':
        return await _processExpenseEntry(entry);
      case 'payments':
        return await _processPaymentEntry(entry);
      case 'salary_payments':
        return await _processSalaryPaymentEntry(entry);
      case 'cash_transactions':
        return await _processCashTransactionEntry(entry);
      case 'shift_notes':
        return await _processShiftNoteEntry(entry);
      case 'debts':
        return await _processDebtEntry(entry);
      case 'employees':
        return await _processEmployeeEntry(entry);
      case 'booking_notes':
        return await _processBookingNoteEntry(entry);
      case 'booking_nights':
        return await _processBookingNightEntry(entry);
      case 'salary_cycles':
        return await _processSalaryCycleEntry(entry);
      case 'booking_price_adjustments':
        return await _processBookingPriceAdjustmentEntry(entry);
      case 'guest_infos':
        return await _processGuestInfoEntry(entry);
      case 'salary_withdrawals':
        return await _processSalaryWithdrawalEntry(entry);
      case 'blacklist':
        return await _processBlacklistEntry(entry);
      case 'price_adjustments':
        return await _processPriceAdjustmentEntry(entry);
      default:
        _logger.warning(
          'Unknown outbox entity: ${entry.entity}',
          tag: 'SYNC',
        );
        // لا نحذف الإدخال — نُبقيه للتحقيق ونعيد false ليبقى في الطابور
        return false;
    }
  } catch (error, stackTrace) {
    final parsed = _errorHandler.handleError(
      error,
      context: 'push:${entry.entity}:${entry.op}',
      stackTrace: stackTrace,
    );
    await outboxDao.setError(entry.id, parsed.message, entry.attempts + 1);
    await outboxDao.markFailed([entry.id]);
    return false;
  }
}


Map<String, dynamic> _addIdempotencyKey(
  Map<String, dynamic> payload,
  OutboxData entry,
) {
  return {
    ...payload,
    'idempotencyKey':
        '${entry.entity}:${entry.op}:${entry.localUuid}:${entry.id}',
  };
}

/// تصفية الحمولة قبل الإرسال — إبقاء فقط الحقول الموجودة في مخطط Appwrite الفعلي
/// ⚠️ هذا يمنع خطأ "Unknown attribute" نهائياً

Future<bool> _processRoomEntry(OutboxData entry) async {
  if (entry.op == 'delete') {
    await _deleteSilently(() => appwriteService.deleteRoom(entry.localUuid));
    return true;
  }
  final room = await _getRoomByLocalUuid(entry.localUuid);
  if (room == null) {
    await _deleteSilently(() => appwriteService.deleteRoom(entry.localUuid));
    return true;
  }
  final payload = _roomToRemote(room);
  await appwriteService.upsertRoom(
    room.localUuid,
    _filterPayload('rooms', _addIdempotencyKey(payload, entry)),
  );
  return true;
}


Future<bool> _processBookingEntry(OutboxData entry) async {
  if (entry.op == 'delete') {
    await _deleteSilently(
      () => appwriteService.deleteBooking(entry.localUuid),
    );
    return true;
  }
  final booking = await _getBookingByLocalUuid(entry.localUuid);
  if (booking == null) {
    await _deleteSilently(
      () => appwriteService.deleteBooking(entry.localUuid),
    );
    return true;
  }
  final payload = _bookingToRemote(booking);

  // ✅ تسجيل تشخيصي: تسجيل الحقول الحرجة قبل الرفع
  _logger.info(
    '📤 Push booking ${booking.localUuid.substring(0, 8)}... '
    'status=${booking.status} '
    'actualCheckout=${booking.actualCheckout} '
    'calculatedNights=${booking.calculatedNights} '
    'lastModified=${booking.lastModified}',
    tag: 'SYNC',
  );

  // ✅ إزالة idempotencyKey إذا لم يكن في مخطط Appwrite
  // هذا الحقل غير موجود في مخطط Appwrite وقد يسبب فشل صامت في updateDocument
  // إذا كان التحقق من المخطط مفعّلاً على Appwrite Cloud
  final cleanPayload = Map<String, dynamic>.from(payload);
  // idempotencyKey يُضاف لاحقاً عبر _addIdempotencyKey

  final finalPayload = _addIdempotencyKey(cleanPayload, entry);

  try {
    await appwriteService.upsertBooking(
      booking.localUuid,
      _filterPayload('bookings', finalPayload),
    );

    // ✅ تحقق بعد الرفع: قراءة المستند من Appwrite والتأكد من حفظ الحقول الحرجة
    await _verifyPushedBooking(booking.localUuid, booking);
  } catch (e) {
    // ✅ إذا فشل الرفع بسبب حقل idempotencyKey غير موجود، نُعيد المحاولة بدونه
    if (e.toString().contains('attribute_not_found') ||
        e.toString().contains('Property not found') ||
        e.toString().contains('invalid_attribute')) {
      _logger.warning(
        '⚠️ إعادة محاولة رفع الحجز بدون idempotencyKey: $e',
        tag: 'SYNC',
      );
      await appwriteService.upsertBooking(
        booking.localUuid,
        _filterPayload('bookings', payload), // بدون idempotencyKey
      );
    } else {
      rethrow;
    }
  }
  return true;
}

/// ✅ تحقق من حفظ الحقول الحرجة بعد الرفع إلى Appwrite
/// يقرأ المستند من Appwrite ويقارن status و actualCheckout

Future<void> _verifyPushedBooking(
  String localUuid,
  Booking expected,
) async {
  try {
    final doc = await appwriteService.databases.getDocument(
      databaseId: AppwriteConfig.databaseId,
      collectionId: AppwriteConfig.bookingsCollectionId,
      documentId: localUuid,
    );
    final remoteStatus = doc.data['status']?.toString();
    final remoteActualCheckout = doc.data['actualCheckout']?.toString();

    if (remoteStatus != expected.status ||
        remoteActualCheckout != expected.actualCheckout) {
      _logger.error(
        '❌ تحقق بعد الرفع فشل! booking=${localUuid.substring(0, 8)}... '
        'expected: status=${expected.status}, actualCheckout=${expected.actualCheckout} '
        'remote: status=$remoteStatus, actualCheckout=$remoteActualCheckout',
        tag: 'SYNC',
      );
    } else {
      _logger.debug(
        '✅ تحقق بعد الرفع ناجح: booking=${localUuid.substring(0, 8)}... '
        'status=$remoteStatus, actualCheckout=$remoteActualCheckout',
        tag: 'SYNC',
      );
    }
  } catch (e) {
    // فشل التحقق ليس حرجاً — لا نوقف المزامنة
    _logger.warning(
      '⚠️ فشل التحقق بعد رفع الحجز $localUuid: $e',
      tag: 'SYNC',
    );
  }
}


Future<bool> _processExpenseEntry(OutboxData entry) async {
  if (entry.op == 'delete') {
    await _deleteSilently(
      () => appwriteService.deleteExpense(entry.localUuid),
    );
    return true;
  }
  final expense = await _getExpenseByLocalUuid(entry.localUuid);
  if (expense == null) {
    await _deleteSilently(
      () => appwriteService.deleteExpense(entry.localUuid),
    );
    return true;
  }
  final payload = _expenseToRemote(expense);
  // ✅ إضافة employeeUuid لمصروفات الرواتب لربط الموظف عبر الأجهزة
  if (expense.relatedId != null && _isSalaryExpenseType(expense.expenseType)) {
    final employee = await (database.select(database.employees)
          ..where((e) => e.id.equals(expense.relatedId!))
          ..limit(1))
        .getSingleOrNull();
    if (employee != null) {
      payload['employeeUuid'] = employee.localUuid;
    }
  }
  await appwriteService.upsertExpense(
    expense.localUuid,
    _filterPayload('expenses', _addIdempotencyKey(payload, entry)),
  );
  return true;
}


Future<bool> _processPaymentEntry(OutboxData entry) async {
  if (entry.op == 'delete') {
    await _deleteSilently(
      () => appwriteService.deletePayment(entry.localUuid),
    );
    return true;
  }
  final payment = await _getPaymentByLocalUuid(entry.localUuid);
  if (payment == null) {
    await _deleteSilently(
      () => appwriteService.deletePayment(entry.localUuid),
    );
    return true;
  }
  final payload = _paymentToRemote(payment);
  await appwriteService.upsertPayment(
    payment.localUuid,
    _filterPayload('payments', _addIdempotencyKey(payload, entry)),
  );
  return true;
}


Future<bool> _processDebtEntry(OutboxData entry) async {
  if (entry.op == 'delete') {
    await _deleteSilently(() => appwriteService.deleteDebt(entry.localUuid));
    return true;
  }
  final debt = await _getDebtByLocalUuid(entry.localUuid);
  if (debt == null) {
    await _deleteSilently(() => appwriteService.deleteDebt(entry.localUuid));
    return true;
  }
  final payload = _debtToRemote(debt);
  await appwriteService.upsertDebt(
    debt.localUuid,
    _filterPayload('debts', _addIdempotencyKey(payload, entry)),
  );
  return true;
}


Future<void> _deleteSilently(Future<void> Function() action) async {
  try {
    await action();
  } catch (error) {
    if (error is AppwriteError && error.code == 'NOT_FOUND') {
      _logger.debug(
        'Delete target not found (AppwriteError): ${error.message}',
        tag: 'SYNC',
      );
      return;
    }

    final message = error.toString().toLowerCase();
    if (message.contains('404') ||
        message.contains('not found') ||
        message.contains('not_found') ||
        message.contains('document_not_found')) {
      _logger.debug('Delete target not found: $message', tag: 'SYNC');
      return;
    }
    rethrow;
  }
}


Future<bool> _processGuestInfoEntry(OutboxData entry) async {
  if (entry.op == 'delete') {
    await _deleteSilently(
      () => appwriteService.deleteGuestInfo(entry.localUuid),
    );
    return true;
  }
  final info = await _getGuestInfoByLocalUuid(entry.localUuid);
  if (info == null) {
    await _deleteSilently(
      () => appwriteService.deleteGuestInfo(entry.localUuid),
    );
    return true;
  }
  final payload = _adapterRegistry.guestInfos.adapter.toJson(
    info,
    src: Source.appwrite,
  );
  await appwriteService.upsertDocument(
    collectionId: AppwriteConfig.guestInfosCollectionId,
    documentId: info.localUuid,
    data: _filterPayload('guest_infos', _addIdempotencyKey(payload, entry)),
  );
  return true;
}


Future<bool> _processSalaryWithdrawalEntry(OutboxData entry) async {
  if (entry.op == 'delete') {
    await _deleteSilently(
      () => appwriteService.deleteSalaryWithdrawal(entry.localUuid),
    );
    return true;
  }
  final withdrawal = await _getSalaryWithdrawalByLocalUuid(entry.localUuid);
  if (withdrawal == null) {
    await _deleteSilently(
      () => appwriteService.deleteSalaryWithdrawal(entry.localUuid),
    );
    return true;
  }

  // ✅ إصلاح FK constraint: التأكد أن الموظف موجود على Appwrite قبل الدفع
  // إذا لم يكن الموظف قد رُفع بعد، نرفعه أولاً لمنع فشل FK constraint
  final employee = await (database.select(database.employees)
        ..where((e) => e.id.equals(withdrawal.employeeId))
        ..limit(1))
      .getSingleOrNull();
  if (employee != null && employee.serverId == null) {
    // الموظف لم يُرفع بعد — نرفعه أولاً
    _logger.info(
      '🔄 رفع الموظف ${employee.id} أولاً لضمان FK constraint',
      tag: 'SYNC',
    );
    try {
      final empPayload = _adapterRegistry.employees.adapter.toJson(
        employee,
        src: Source.appwrite,
      );
      await appwriteService.upsertEmployee(
        employee.localUuid,
        _filterPayload('employees', _addIdempotencyKey(empPayload, entry)),
      );
      // تحديث serverId محلياً لمنع الرفع المكرر
      try {
        final remoteDoc = await appwriteService.getDocument(
          collectionId: AppwriteConfig.employeesCollectionId,
          documentId: employee.localUuid,
        );
        await (database.update(database.employees)
              ..where((e) => e.id.equals(employee.id)))
            .write(EmployeesCompanion(
          serverId: drift.Value(remoteDoc.$id.hashCode),
        ));
      } catch (_) {
        // فشل جلب المستند البعيد — نتجاوز، الأهم أن الموظف رُفع بنجاح
      }
    } catch (e) {
      _logger.warning(
        '⚠️ فشل رفع الموظف ${employee.id} — سيتم تأجيل سحب الراتب: $e',
        tag: 'SYNC',
      );
      // فشل رفع الموظف — لا نستطيع رفع السحب بدون FK
      // نُعيد false ليبقى في الطابور للمحاولة لاحقاً
      return false;
    }
  } else if (employee == null) {
    // الموظف غير موجود محلياً — سجل يتيم
    _logger.warning(
      '⏭️ تخطي salary_withdrawal: الموظف ${withdrawal.employeeId} غير موجود محلياً (سجل يتيم)',
      tag: 'SYNC',
    );
    // لا نستطيع رفع سحب راتب بدون موظف — نحذفه من الطابور
    return true;
  }

  final payload = _adapterRegistry.salaryWithdrawals.adapter.toJson(
    withdrawal,
    src: Source.appwrite,
  );
  // ✅ إضافة employeeUuid لربط السلف بالموضف عبر الأجهزة
  payload['employeeUuid'] = employee.localUuid;
  payload['employeeLocalUuid'] = employee.localUuid;
  await appwriteService.upsertDocument(
    collectionId: AppwriteConfig.salaryWithdrawalsCollectionId,
    documentId: withdrawal.localUuid,
    data: _filterPayload('salary_withdrawals', _addIdempotencyKey(payload, entry)),
  );
  return true;
}


Future<bool> _processSalaryPaymentEntry(OutboxData entry) async {
  if (entry.op == 'delete') {
    await _deleteSilently(
      () => appwriteService.deleteSalaryPayment(entry.localUuid),
    );
    return true;
  }
  final item = await _getSalaryPaymentByLocalUuid(entry.localUuid);
  if (item == null) {
    await _deleteSilently(
      () => appwriteService.deleteSalaryPayment(entry.localUuid),
    );
    return true;
  }
  final payload = outboxDao.adapters.salaryPayments.adapter.toJson(
    item,
    src: Source.appwrite,
  );
  await appwriteService.upsertSalaryPayment(
    item.localUuid,
    _filterPayload('salary_payments', _addIdempotencyKey(payload, entry)),
  );
  return true;
}


Future<bool> _processCashTransactionEntry(OutboxData entry) async {
  if (entry.op == 'delete') {
    await _deleteSilently(
      () => appwriteService.deleteCashTransaction(entry.localUuid),
    );
    return true;
  }
  final item = await _getCashTransactionByLocalUuid(entry.localUuid);
  if (item == null) {
    await _deleteSilently(
      () => appwriteService.deleteCashTransaction(entry.localUuid),
    );
    return true;
  }

  final payload = outboxDao.adapters.cashTransactions.adapter.toJson(
    item,
    src: Source.appwrite,
  );

  await appwriteService.upsertCashTransaction(
    item.localUuid,
    _filterPayload('cash_transactions', _addIdempotencyKey(payload, entry)),
  );
  return true;
}


Future<bool> _processShiftNoteEntry(OutboxData entry) async {
  if (entry.op == 'delete') {
    await _deleteSilently(
      () => appwriteService.deleteShiftNote(entry.localUuid),
    );
    return true;
  }
  final item = await _getShiftNoteByLocalUuid(entry.localUuid);
  if (item == null) {
    await _deleteSilently(
      () => appwriteService.deleteShiftNote(entry.localUuid),
    );
    return true;
  }

  final payload = outboxDao.adapters.shiftNotes.adapter.toJson(
    item,
    src: Source.appwrite,
  );

  await appwriteService.upsertShiftNote(
    item.localUuid,
    _filterPayload('shift_notes', _addIdempotencyKey(payload, entry)),
  );
  return true;
}


Future<bool> _processBlacklistEntry(OutboxData entry) async {
  if (entry.op == 'delete') {
    await _deleteSilently(
      () => appwriteService.deleteBlacklist(entry.localUuid),
    );
    return true;
  }
  final item = await _getBlacklistShiftNoteByLocalUuid(entry.localUuid);
  if (item == null) {
    await _deleteSilently(
      () => appwriteService.deleteBlacklist(entry.localUuid),
    );
    return true;
  }

  final payload = _blacklistToRemote(item);
  await appwriteService.upsertBlacklist(
    item.localUuid,
    _filterPayload('blacklist', _addIdempotencyKey(payload, entry)),
  );
  return true;
}


Future<bool> _processPriceAdjustmentEntry(OutboxData entry) async {
  if (entry.op == 'delete') {
    await _deleteSilently(
      () => appwriteService.deleteDocument(
        collectionId: AppwriteConfig.priceAdjustmentsCollectionId,
        documentId: entry.localUuid,
      ),
    );
    return true;
  }

  // جلب السجل المحلي للحصول على البيانات الكاملة
  final localRow = await (database.select(database.priceAdjustments)
        ..where((t) => t.localUuid.equals(entry.localUuid))
        ..limit(1))
      .getSingleOrNull();

  if (localRow == null) {
    // السجل غير موجود محلياً — نحذف من Appwrite أيضاً
    await _deleteSilently(
      () => appwriteService.deleteDocument(
        collectionId: AppwriteConfig.priceAdjustmentsCollectionId,
        documentId: entry.localUuid,
      ),
    );
    return true;
  }

  final payload = _priceAdjustmentToRemote(localRow);
  await appwriteService.upsertDocument(
    collectionId: AppwriteConfig.priceAdjustmentsCollectionId,
    documentId: localRow.localUuid,
    data: _filterPayload('price_adjustments', _addIdempotencyKey(payload, entry)),
  );
  return true;
}


Future<bool> _processEmployeeEntry(OutboxData entry) async {
  if (entry.op == 'delete') {
    // ✅ حذف ناعم: نبحث عن الموظف محلياً (بما فيه المحذوف ناعماً)
    // إذا وُجد (deletedAt != null)، نُحدّث Appwrite بحقل deletedAt بدل الحذف الفعلي
    // هذا يمنع فقدان الموظف على الأجهزة الأخرى وحل FK بشكل صحيح
    final item = await _getEmployeeByLocalUuid(entry.localUuid);
    if (item != null && item.deletedAt != null) {
      // ✅ حذف ناعم — إرسال deletedAt إلى Appwrite
      final payload = outboxDao.adapters.employees.adapter.toJson(
        item,
        src: Source.appwrite,
      );
      await appwriteService.upsertEmployee(
        item.localUuid,
        _filterPayload('employees', _addIdempotencyKey(payload, entry)),
      );
      return true;
    }
    // الموظف غير موجود محلياً إطلاقاً — حذف فعلي من Appwrite
    await _deleteSilently(
      () => appwriteService.deleteEmployee(entry.localUuid),
    );
    return true;
  }
  final item = await _getEmployeeByLocalUuid(entry.localUuid);
  if (item == null) {
    await _deleteSilently(
      () => appwriteService.deleteEmployee(entry.localUuid),
    );
    return true;
  }
  final payload = outboxDao.adapters.employees.adapter.toJson(
    item,
    src: Source.appwrite,
  );
  await appwriteService.upsertEmployee(
    item.localUuid,
    _filterPayload('employees', _addIdempotencyKey(payload, entry)),
  );
  return true;
}


Future<bool> _processBookingNoteEntry(OutboxData entry) async {
  if (entry.op == 'delete') {
    await _deleteSilently(
      () => appwriteService.deleteBookingNote(entry.localUuid),
    );
    return true;
  }
  final item = await _getBookingNoteByLocalUuid(entry.localUuid);
  if (item == null) {
    await _deleteSilently(
      () => appwriteService.deleteBookingNote(entry.localUuid),
    );
    return true;
  }
  final payload = outboxDao.adapters.bookingNotes.adapter.toJson(
    item,
    src: Source.appwrite,
  );
  // Note: booking notes often part of booking but if synced separately:
  await appwriteService.upsertBookingNote(
    item.localUuid,
    _filterPayload('booking_notes', _addIdempotencyKey(payload, entry)),
  );
  return true;
}


Future<bool> _processBookingNightEntry(OutboxData entry) async {
  if (entry.op == 'delete') {
    await _deleteSilently(
      () => appwriteService.deleteBookingNight(entry.localUuid),
    );
    return true;
  }
  final item = await _getBookingNightByLocalUuid(entry.localUuid);
  if (item == null) {
    await _deleteSilently(
      () => appwriteService.deleteBookingNight(entry.localUuid),
    );
    return true;
  }
  final payload = outboxDao.adapters.nights.adapter.toJson(
    item,
    src: Source.appwrite,
  );
  await appwriteService.upsertBookingNight(
    item.localUuid,
    _filterPayload('booking_nights', _addIdempotencyKey(payload, entry)),
  );
  return true;
}


Future<bool> _processSalaryCycleEntry(OutboxData entry) async {
  if (entry.op == 'delete') {
    await _deleteSilently(
      () => appwriteService.deleteSalaryCycle(entry.localUuid),
    );
    return true;
  }
  final item = await _getSalaryCycleByLocalUuid(entry.localUuid);
  if (item == null) {
    await _deleteSilently(
      () => appwriteService.deleteSalaryCycle(entry.localUuid),
    );
    return true;
  }
  final payload = outboxDao.adapters.salaryCycles.adapter.toJson(
    item,
    src: Source.appwrite,
  );
  // ✅ إضافة employeeUuid لربط دورة الراتب بالموظف عبر الأجهزة
  final employee = await (database.select(database.employees)
        ..where((e) => e.id.equals(item.employeeId))
        ..limit(1))
      .getSingleOrNull();
  if (employee != null) {
    payload['employeeUuid'] = employee.localUuid;
    payload['employeeLocalUuid'] = employee.localUuid;
  }
  await appwriteService.upsertSalaryCycle(
    item.localUuid,
    _filterPayload('salary_cycles', _addIdempotencyKey(payload, entry)),
  );
  return true;
}


Future<bool> _processBookingPriceAdjustmentEntry(OutboxData entry) async {
  if (entry.op == 'delete') {
    await _deleteSilently(
      () => appwriteService.deleteDocument(
        collectionId: AppwriteConfig.bookingPriceAdjustmentsCollectionId,
        documentId: entry.localUuid,
      ),
    );
    return true;
  }
  final item = await _getBookingPriceAdjustmentByLocalUuid(entry.localUuid);
  if (item == null) {
    await _deleteSilently(
      () => appwriteService.deleteDocument(
        collectionId: AppwriteConfig.bookingPriceAdjustmentsCollectionId,
        documentId: entry.localUuid,
      ),
    );
    return true;
  }
  final payload = outboxDao.adapters.bookingPriceAdjustments.adapter.toJson(
    item,
    src: Source.appwrite,
  );
  await appwriteService.upsertDocument(
    collectionId: AppwriteConfig.bookingPriceAdjustmentsCollectionId,
    documentId: item.localUuid,
    data: _filterPayload('booking_price_adjustments', _addIdempotencyKey(payload, entry)),
  );
  return true;
}


Future<bool> _pushAppSettingsToCloud() async {
  try {
    final prefs = await SharedPreferences.getInstance();

    // ⚠️ حقول app_settings الفعلية في Appwrite Cloud (25 حقل فقط — الحد الأقصى)
    // تم تدقيق كل حقل مقابل المخطط الفعلي في 2026-06-14
    // ❌ لا ترسل حقولاً غير موجودة — يسبب "Unknown attribute" خطأ 400
    final data = <String, dynamic>{
      'key': 'whatsapp_settings',
      'value': '',
      // ── فندق ──
      'hotel_name': prefs.getString('hotel_name') ?? 'فندق مارينا بلازا',
      'hotel_cutoff_hour': prefs.getInt('hotel_cutoff_hour') ?? 14,
      // ── مظهر ──
      'dark_mode': prefs.getBool('dark_mode') ?? false,
      // ── WhatsApp ──
      'wa_api_type': prefs.getString('wa_api_type') ?? 'greenapi',
      'wa_api_base_url': prefs.getString('wa_api_base_url') ?? '',
      'wa_api_instance_id': prefs.getString('wa_api_instance_id') ?? '',
      'wa_api_token': prefs.getString('wa_api_token') ?? '',
      'wa_custom_url_template': prefs.getString('wa_custom_url_template') ?? '',
      'wa_sendzen_api_key': prefs.getString('wa_sendzen_api_key') ?? '',
      'wa_sendzen_from_number': prefs.getString('wa_sendzen_from_number') ?? '',
      'wa_template': prefs.getString('whatsapp_template') ?? '',
      // ── Telegram ──
      'telegram_enabled': prefs.getBool('telegram_enabled') ?? false,
      'telegram_bot_token': prefs.getString('telegram_bot_token') ?? '',
      'telegram_chat_id': prefs.getString('telegram_chat_id') ?? '',
      'telegram_notifications_enabled': prefs.getBool('telegram_notifications_enabled') ?? false,
      'telegram_daily_report_enabled': prefs.getBool('telegram_daily_report_enabled') ?? false,
      'telegram_daily_report_time': prefs.getString('telegram_daily_report_time') ?? '',
      // ── Lark ──
      'lark_enabled': prefs.getBool('lark_enabled') ?? false,
      'lark_app_id': prefs.getString('lark_app_id') ?? '',
      'lark_app_secret': prefs.getString('lark_app_secret') ?? '',
      'lark_webhook_url': prefs.getString('lark_webhook_url') ?? '',
      'lark_daily_report_enabled': prefs.getBool('lark_daily_report_enabled') ?? false,
      'lark_daily_report_time': prefs.getString('lark_daily_report_time') ?? '08:00',
      'lark_daily_report_chat_id': prefs.getString('lark_daily_report_chat_id') ?? '',
      // ── مزامنة ──
      'appwrite_sync_interval': prefs.getInt('appwrite_sync_interval') ?? 15,
    };

    const docId = 'whatsapp_settings';
    const collectionId = 'app_settings';

    // محاولة تحديث، إذا لم يكن موجوداً ننشئه
    try {
      await appwriteService.updateDocument(
        collectionId: collectionId,
        documentId: docId,
        data: _filterPayload('app_settings', data),
      );
    } catch (_) {
      await appwriteService.createDocument(
        collectionId: collectionId,
        documentId: docId,
        data: _filterPayload('app_settings', data),
      );
    }

    return true;
  } catch (e) {
    _logger.warning('Failed to push app_settings: $e', tag: 'SYNC');
    return false;
  }
}

/// مزامنة إعدادات المراسلة (واتساب + تلجرام) من Appwrite → SharedPreferences

void _putIfStringNotEmpty(
  Map<String, dynamic> map,
  String key,
  String? value,
) {
  if (value != null && value.isNotEmpty) {
    map[key] = value;
  }
}

/// هل نوع المصروف مرتبط بالرواتب
static bool _isSalaryExpenseType(String type) {
  const salaryKeywords = ['رواتب', 'سحب راتب', 'سحب من الراتب', 'خصم راتب', 'خصم من الراتب'];
  for (final keyword in salaryKeywords) {
    if (type.contains(keyword)) return true;
  }
  return false;
}

// ─── Delta Sync ────────────────────────────────────────────────────────

/// قراءة آخر timestamp خاص بـ booking_nights من SharedPreferences

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
