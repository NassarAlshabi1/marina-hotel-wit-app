import 'package:drift/drift.dart';

/// Serializer يسمح بالتعامل مع قيم null أو أنواع غير متوقعة أثناء تحويل JSON
/// لضمان التوافق مع النسخ الاحتياطية الأقدم.
class LenientValueSerializer extends ValueSerializer {
  const LenientValueSerializer();

  Type _typeOf<X>() => X;

  bool _isNullable<T>() => null is T;

  bool _isIntType<T>() {
    final type = _typeOf<T>();
    return type == int || type == _typeOf<int?>();
  }

  bool _isDoubleType<T>() {
    final type = _typeOf<T>();
    return type == double || type == _typeOf<double?>();
  }

  bool _isStringType<T>() {
    final type = _typeOf<T>();
    return type == String || type == _typeOf<String?>();
  }

  bool _isBoolType<T>() {
    final type = _typeOf<T>();
    return type == bool || type == _typeOf<bool?>();
  }

  @override
  T fromJson<T>(dynamic json) {
    final defaultSerializer = driftRuntimeOptions.defaultSerializer;

    if (json == null) {
      if (_isNullable<T>()) {
        return json as T;
      }
      if (_isIntType<T>()) {
        return 0 as T;
      }
      if (_isDoubleType<T>()) {
        return 0.0 as T;
      }
      if (_isBoolType<T>()) {
        return false as T;
      }
      if (_isStringType<T>()) {
        return '' as T;
      }
      return defaultSerializer.fromJson<T>(json);
    }

    if (_isIntType<T>()) {
      if (json is int) {
        return json as T;
      }
      if (json is double) {
        return json.toInt() as T;
      }
      if (json is num) {
        return json.toInt() as T;
      }
      if (json is String) {
        final trimmed = json.trim();
        if (trimmed.isEmpty) {
          return (_isNullable<T>() ? null : 0) as T;
        }
        // إذا كان النص يحتوي على UUID أو قيم غير رقمية، نعيد null أو 0
        if (trimmed.contains('-') || trimmed.length > 20) {
          return (_isNullable<T>() ? null : 0) as T;
        }
        final parsed = int.tryParse(trimmed);
        if (parsed == null) {
          return (_isNullable<T>() ? null : 0) as T;
        }
        return parsed as T;
      }
      if (json is bool) {
        return (json ? 1 : 0) as T;
      }
    }

    if (_isDoubleType<T>()) {
      if (json is double) {
        return json as T;
      }
      if (json is int) {
        return json.toDouble() as T;
      }
      if (json is num) {
        return json.toDouble() as T;
      }
      if (json is String) {
        final trimmed = json.trim();
        if (trimmed.isEmpty) {
          return 0.0 as T;
        }
        final parsed = double.tryParse(trimmed);
        return (parsed ?? 0.0) as T;
      }
      if (json is bool) {
        return (json ? 1.0 : 0.0) as T;
      }
    }

    if (_isBoolType<T>()) {
      if (json is bool) {
        return json as T;
      }
      if (json is num) {
        return (json != 0) as T;
      }
      if (json is String) {
        final lower = json.trim().toLowerCase();
        if (lower.isEmpty) {
          return false as T;
        }
        if (lower == '1' || lower == 'true') {
          return true as T;
        }
        if (lower == '0' || lower == 'false') {
          return false as T;
        }
      }
    }

    if (_isStringType<T>()) {
      if (json is String) {
        return json as T;
      }
      return json.toString() as T;
    }

    return defaultSerializer.fromJson<T>(json);
  }

  @override
  dynamic toJson<T>(T value) => value;
}

const lenientValueSerializer = LenientValueSerializer();

/// بناء خريطة بيانات النسخ الاحتياطي المشتركة بين Google Drive والنسخ المحلي
/// لتجنب تكرار كود تحويل الجداول إلى JSON
Map<String, dynamic> buildBackupDataMap({
  required Map<String, dynamic> metadata,
  required List<dynamic> roomsData,
  required List<dynamic> bookingsData,
  required List<dynamic> bookingNotesData,
  required List<dynamic> bookingNightsData,
  required List<dynamic> ledgerData,
  required List<dynamic> shiftNotesData,
  required List<dynamic> employeesData,
  required List<dynamic> expensesData,
  required List<dynamic> cashTransactionsData,
  required List<dynamic> paymentsData,
  required List<dynamic> debtsData,
  required List<dynamic> salaryCyclesData,
  required List<dynamic> salaryPaymentsData,
  required List<dynamic> priceAdjustmentsData,
  required List<dynamic> bookingPriceAdjData,
  required List<dynamic> auditLogsData,
  required List<dynamic> paymentVoidsData,
  required List<dynamic> guestInfosData,
  required List<dynamic> salaryWithdrawalsData,
  List<dynamic>? blacklistData,
  Map<String, dynamic>? whatsappSettings,
  Map<String, dynamic>? syncStateData,
}) {
  final backupData = <String, dynamic>{
    'metadata': metadata,
    'rooms': roomsData.map((room) => room.toJson()).toList(),
    'bookings': bookingsData.map((booking) => booking.toJson()).toList(),
    'booking_notes': bookingNotesData.map((note) => note.toJson()).toList(),
    'booking_nights': bookingNightsData
        .map((night) => night.toJson())
        .toList(),
    'hotel_day_ledger': ledgerData.map((entry) => entry.toJson()).toList(),
    'shift_notes': shiftNotesData.map((note) => note.toJson()).toList(),
    'employees': employeesData.map((employee) => employee.toJson()).toList(),
    'expenses': expensesData.map((expense) => expense.toJson()).toList(),
    'cash_transactions': cashTransactionsData
        .map((transaction) => transaction.toJson())
        .toList(),
    'payments': paymentsData.map((payment) => payment.toJson()).toList(),
    'debts': debtsData.map((debt) => debt.toJson()).toList(),
    'salary_cycles': salaryCyclesData
        .map((cycle) => cycle.toJson())
        .toList(),
    'salary_payments': salaryPaymentsData
        .map((payment) => payment.toJson())
        .toList(),
    'price_adjustments': priceAdjustmentsData
        .map((adj) => adj.toJson())
        .toList(),
    'booking_price_adjustments': bookingPriceAdjData
        .map((adj) => adj.toJson())
        .toList(),
    'audit_logs': auditLogsData.map((log) => log.toJson()).toList(),
    'payment_voids': paymentVoidsData.map((v) => v.toJson()).toList(),
    'guest_infos': guestInfosData.map((g) => g.toJson()).toList(),
    'salary_withdrawals': salaryWithdrawalsData
        .map((s) => s.toJson())
        .toList(),
  };

  // إعدادات الواتساب (اختياري)
  if (whatsappSettings != null && whatsappSettings.isNotEmpty) {
    backupData['whatsapp_settings'] = whatsappSettings;
  }

  // القائمة السوداء (اختياري)
  if (blacklistData != null) {
    backupData['blacklist'] = blacklistData.map((e) => e.toJson()).toList();
  }

  // حالة المزامنة (اختياري)
  if (syncStateData != null) {
    backupData['sync_state'] = syncStateData;
  }

  return backupData;
}
