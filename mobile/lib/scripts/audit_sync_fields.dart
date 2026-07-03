// ignore_for_file: avoid_print, sort_constructors_first, prefer_const_declarations

// lib/scripts/audit_sync_fields.dart
//
// ✅ سكربت تدقيق فعلي — يطابق PayloadMapper مع مخطط Appwrite Cloud
// الاستخدام: dart run lib/scripts/audit_sync_fields.dart
//
// يعمل السكربت على فحص كل دالة XxxToRemote في PayloadMapper ويستخرج
// أسماء الحقول التي تُسند إلى الـ Map. ثم يقارنها مع مخطط Appwrite
// Cloud الفعلي (validFieldsPerCollection). أي حقل غير موجود في المخطط
// يُسجَّل كـ issue حتى لو كان sanitizePayload سيُزيله صامتاً — لأن وجوده
// يشير إلى عدم تطابق بين الكود والمخطط ويجب إصلاحه في المصدر.
//
// ⚠️ السكربت لا يستورد PayloadMapper أو AppwriteSyncUtils مباشرةً
// لأنهما يسحبان Flutter SDK (لا يمكن تشغيله بـ `dart run` بشكل نقي).
// بدلاً من ذلك:
// - مخطط المجموعات (collection -> Set<field>) مُضمَّن هنا كـ const.
// - أسماء الحقول المُرسلة تُستخرج من payload_mapper.dart كنص.

import 'dart:io';

void main() {
  final audit = SyncFieldsAudit();
  final result = audit.run();

  print('\n${'=' * 60}');
  print('  Sync Fields Audit Report');
  print('${'=' * 60}\n');

  if (result.issues.isEmpty) {
    print('✅ No issues found! All fields are properly mapped.');
  } else {
    print('❌ Issues found: ${result.issues.length}');
    print('\nSome fields will be filtered before reaching Appwrite Cloud.');
    print('Fix before merging!\n');

    for (final issue in result.issues) {
      print('  ⚠️  ${issue.collection}.${issue.field}');
      print('      ${issue.description}');
    }
  }

  print('\nCollections checked: ${result.collectionsChecked}');
  print('Fields checked: ${result.fieldsChecked}');
  print('Total issues: ${result.issues.length}');

  if (result.issues.isNotEmpty) {
    print('\n❌ Audit FAILED — fix the issues above before merging.');
    throw Exception('Sync fields audit failed with ${result.issues.length} issues');
  }
  print('\n✅ Audit passed.');
}

/// تدقيق حقول المزامنة — يقارن PayloadMapper مع مخطط Appwrite Cloud.
///
/// يعتمد التدقيق على قراءة ملف payload_mapper.dart كنص واستخراج أسماء
/// الحقول المُسندة في كل دالة XxxToRemote، ثم مطابقتها مع مخطط
/// Appwrite Cloud المُضمَّن أدناه.
class SyncFieldsAudit {
  AuditResult run() {
    final result = AuditResult();

    final schema = _appwriteCloudSchema;
    for (final entry in schema.entries) {
      result.collectionsChecked++;
      result.fieldsChecked += entry.value.length;
    }

    final mapperFieldsByCollection = _extractMapperFieldsByCollection();

    for (final entry in mapperFieldsByCollection.entries) {
      final collection = entry.key;
      final mapperFields = entry.value;
      final validFields = schema[collection];

      if (validFields == null) {
        result.issues.add(AuditIssue(
          collection: collection,
          field: '(whole collection)',
          description:
              'Collection "$collection" has a mapper but is not present in '
              '_appwriteCloudSchema. Either add it to the schema or '
              'remove the mapper.',
        ));
        continue;
      }

      for (final field in mapperFields) {
        if (!validFields.contains(field)) {
          result.issues.add(AuditIssue(
            collection: collection,
            field: field,
            description:
                'Field "$field" is sent by PayloadMapper but is NOT in the '
                'Appwrite Cloud schema for "$collection". '
                'sanitizePayload may strip it silently, but the mismatch '
                'should be fixed at the source.',
          ));
        }
      }
    }

    return result;
  }

  /// يبني خريطة collection -> Set<field> باستخراج أسماء الحقول من
  /// ملف payload_mapper.dart لكل method XxxToRemote.
  Map<String, Set<String>> _extractMapperFieldsByCollection() {
    final mapperToCollection = _buildMapperToCollectionMap();

    final sourceFile = File(_payloadMapperPath);
    if (!sourceFile.existsSync()) {
      throw const FileSystemException(
        'PayloadMapper source not found',
        _payloadMapperPath,
      );
    }
    final source = sourceFile.readAsStringSync();

    final result = <String, Set<String>>{};

    for (final entry in mapperToCollection.entries) {
      final methodName = entry.key;
      final collection = entry.value;
      final fields = _extractFieldsForMethod(source, methodName);
      if (fields.isEmpty) continue;
      result.putIfAbsent(collection, () => <String>{}).addAll(fields);
    }

    return result;
  }

  /// خريطة methodName -> collectionName.
  /// أكثر موثوقية من الـ parsing التلقائي لأن أسماء الـ methods قد لا
  /// تتطابق تماماً مع أسماء المجموعات (مثلاً: blacklistToRemote -> shift_notes).
  Map<String, String> _buildMapperToCollectionMap() {
    return {
      'roomToRemote': 'rooms',
      'bookingToRemote': 'bookings',
      'expenseToRemote': 'expenses',
      'paymentToRemote': 'payments',
      'debtToRemote': 'debts',
      'employeeToRemote': 'employees',
      'bookingNoteToRemote': 'booking_notes',
      'bookingNightToRemote': 'booking_nights',
      'cashTransactionToRemote': 'cash_transactions',
      'salaryCycleToRemote': 'salary_cycles',
      'salaryPaymentToRemote': 'salary_payments',
      'shiftNoteToRemote': 'shift_notes',
      'priceAdjustmentToRemote': 'price_adjustments',
      'blacklistToRemote': 'shift_notes',
      'guestInfoToRemote': 'guest_infos',
      'salaryWithdrawalToRemote': 'salary_withdrawals',
      'bookingPriceAdjustmentToRemote': 'booking_price_adjustments',
      'salaryCarryOverLogToRemote': 'salary_carry_over_logs',
      'paymentVoidToRemote': 'payment_voids',
    };
  }

  /// يستخرج أسماء الحقول من body الـ method المُحدّدة. يعتمد على regex
  /// بسيط لكشف الأنماط الثلاثة الشائعة في PayloadMapper:
  ///   1. 'fieldName': value          (داخل map literal)
  ///   2. data['fieldName'] = value   (إسناد مباشر)
  ///   3. putIfNotNull(data, 'fieldName', ...) أو putIfStringNotEmpty
  Set<String> _extractFieldsForMethod(String source, String methodName) {
    final methodStartPattern = RegExp(
      r'Map<String,\s*dynamic>\s+' + RegExp.escape(methodName) + r'\s*\([^)]*\)\s*\{',
    );
    final startMatch = methodStartPattern.firstMatch(source);
    if (startMatch == null) return const {};

    final afterStart = source.substring(startMatch.end);
    // نهاية body عند أول `return ...` (إما sanitizePayload أو return data;)
    final returnPattern = RegExp(r'return\s+(?:AppwriteSyncUtils\.sanitizePayload\(|data;)');
    final returnMatch = returnPattern.firstMatch(afterStart);
    final body = returnMatch != null
        ? afterStart.substring(0, returnMatch.start)
        : afterStart.substring(0, afterStart.length > 5000 ? 5000 : afterStart.length);

    final fields = <String>{};

    final p1 = RegExp(r"'([a-zA-Z_][a-zA-Z0-9_]*)'\s*:");
    for (final m in p1.allMatches(body)) {
      fields.add(m.group(1)!);
    }

    final p2 = RegExp(r"data\['([a-zA-Z_][a-zA-Z0-9_]*)'\]\s*=");
    for (final m in p2.allMatches(body)) {
      fields.add(m.group(1)!);
    }

    final p3 = RegExp(r"putIf(?:NotNull|StringNotEmpty)\(data,\s*'([a-zA-Z_][a-zA-Z0-9_]*)'");
    for (final m in p3.allMatches(body)) {
      fields.add(m.group(1)!);
    }

    return fields;
  }

  /// مخطط Appwrite Cloud الفعلي — يجب أن يبقى متزامناً مع
  /// `AppwriteSyncUtils.validFieldsPerCollection` في
  /// `lib/services/appwrite_sync_utils.dart`.
  ///
  /// ⚠️ إذا أضفت حقلاً في Appwrite Cloud، حدّث هذا المخطط أيضاً.
  /// يمكن مقارنة المخططين يدوياً بـ:
  ///   diff <(grep -oE "'[a-z_A-Z]+'" lib/services/appwrite_sync_utils.dart | sort -u) \
  ///        <(grep -oE "'[a-z_A-Z]+'" lib/scripts/audit_sync_fields.dart | sort -u)
  static const Map<String, Set<String>> _appwriteCloudSchema = {
    'rooms': {
      'roomNumber', 'type', 'price', 'status', 'localUuid', 'createdAt',
      'updatedAt', 'lastModified', 'version', 'origin', 'vectorClock',
      'deviceId', 'serverId', 'deletedAt', 'imageUrl', 'cleaningStatus',
      'lastCleanedHotelDay', 'lastOccupiedHotelDay', 'requiresMaintenance',
      'idempotencyKey', 'sync_origin',
    },
    'bookings': {
      'roomNumber', 'guestName', 'guestPhone', 'guestIdType', 'guestIdNumber',
      'guestNationality', 'checkinDate', 'status', 'expectedNights',
      'calculatedNights', 'localUuid', 'createdAt', 'updatedAt',
      'lastModified', 'version', 'origin', 'serverBookingId', 'serverId',
      'deletedAt', 'guestIdIssueDate', 'guestIdIssuePlace', 'guestEmail',
      'guestAddress', 'checkoutDate', 'actualCheckout', 'notes', 'discount',
      'discountType', 'discountStartDate', 'sync_origin', 'vectorClock',
      'deviceId', 'totalPaidCached', 'totalDueCached', 'idempotencyKey',
    },
    'expenses': {
      'description', 'amount', 'date', 'localUuid', 'createdAt', 'updatedAt',
      'lastModified', 'version', 'origin', 'sync_origin', 'deletedAt',
      'serverId', 'vectorClock', 'deviceId',
    },
    'payments': {
      'amount', 'date', 'localUuid', 'createdAt', 'updatedAt', 'lastModified',
      'version', 'origin', 'notes', 'sync_origin', 'deletedAt', 'serverId',
      'vectorClock', 'deviceId', 'bookingUuidCache', 'paymentMethod',
      'idempotencyKey', 'shiftId',
    },
    'debts': {
      'note', 'pledge', 'localUuid', 'createdAt', 'updatedAt', 'lastModified',
      'version', 'origin', 'sync_origin', 'deletedAt', 'serverId',
      'vectorClock', 'deviceId', 'bookingUuidCache', 'amount',
    },
    'employees': {
      'name', 'basicSalary', 'position', 'phone', 'hireDate', 'status',
      'localUuid', 'createdAt', 'updatedAt', 'lastModified', 'createdAtEpoch',
      'lastModifiedEpoch', 'version', 'origin', 'sync_origin', 'syncTimestamp',
      'vectorClock', 'deviceId', 'serverId', 'deletedAt', 'createdAtIso',
      'updatedAtIso', 'deletedAtIso', 'terminationDate', 'terminationReason',
      'EmployeeID', 'idempotencyKey',
    },
    'booking_notes': {
      'bookingId', 'noteText', 'alertType', 'isActive', 'localUuid',
      'createdAt', 'updatedAt', 'lastModified', 'version', 'origin',
      'sync_origin', 'deletedAt', 'vectorClock', 'deviceId', 'bookingUuidCache',
    },
    'booking_nights': {
      'localUuid', 'createdAt', 'updatedAt', 'lastModified', 'version',
      'origin', 'sync_origin', 'deletedAt', 'vectorClock', 'deviceId',
      'bookingUuidCache', 'hotelDate', 'isCompensated',
    },
    'cash_transactions': {
      'localUuid', 'createdAt', 'updatedAt', 'lastModified', 'version',
      'origin', 'sync_origin', 'deletedAt', 'vectorClock', 'deviceId',
      'type', 'amount', 'description', 'shiftId', 'employeeUuid',
    },
    'salary_cycles': {
      'localUuid', 'createdAt', 'updatedAt', 'lastModified', 'version',
      'origin', 'sync_origin', 'deletedAt', 'vectorClock', 'deviceId',
      'cycleName', 'startDate', 'endDate', 'isClosed',
    },
    'salary_payments': {
      'localUuid', 'createdAt', 'updatedAt', 'lastModified', 'version',
      'origin', 'sync_origin', 'deletedAt', 'vectorClock', 'deviceId',
      'employeeUuid', 'cycleUuid', 'amount', 'paymentDate', 'note',
    },
    'shift_notes': {
      'localUuid', 'createdAt', 'updatedAt', 'lastModified', 'version',
      'origin', 'sync_origin', 'deletedAt', 'vectorClock', 'deviceId',
      'hotelDate', 'content', 'shift', 'noteType',
    },
    'price_adjustments': {
      'localUuid', 'createdAt', 'updatedAt', 'lastModified', 'version',
      'origin', 'sync_origin', 'deletedAt', 'vectorClock', 'deviceId',
      'roomNumber', 'adjustmentType', 'amount', 'effectiveDate', 'note',
    },
    'guest_infos': {
      'localUuid', 'createdAt', 'updatedAt', 'lastModified', 'createdAtEpoch',
      'lastModifiedEpoch', 'version', 'origin', 'sync_origin', 'deletedAt',
      'vectorClock', 'deviceId', 'name', 'phone', 'idType', 'idNumber',
      'nationality', 'idIssueDate', 'idIssuePlace', 'governorate',
    },
    'salary_withdrawals': {
      'localUuid', 'createdAt', 'updatedAt', 'lastModified', 'version',
      'origin', 'sync_origin', 'deletedAt', 'vectorClock', 'deviceId',
      'employeeUuid', 'amount', 'date', 'note',
    },
    'booking_price_adjustments': {
      'localUuid', 'createdAt', 'updatedAt', 'lastModified', 'version',
      'origin', 'sync_origin', 'deletedAt', 'vectorClock', 'deviceId',
      'bookingUuidCache', 'adjustmentType', 'amount', 'note',
    },
    'salary_carry_over_logs': {
      'localUuid', 'createdAt', 'updatedAt', 'lastModified', 'version',
      'origin', 'sync_origin', 'deletedAt', 'vectorClock', 'deviceId',
      'employeeUuid', 'fromCycleUuid', 'toCycleUuid', 'amount',
    },
    'payment_voids': {
      'localUuid', 'createdAt', 'updatedAt', 'lastModified', 'version',
      'origin', 'sync_origin', 'deletedAt', 'vectorClock', 'deviceId',
      'paymentUuid', 'voidedAmount', 'voidReason', 'voidedAt', 'voidedBy',
    },
  };

  static const _payloadMapperPath = 'lib/services/sync/payload_mapper.dart';
}

class AuditResult {
  final List<AuditIssue> issues = [];
  int collectionsChecked = 0;
  int fieldsChecked = 0;
}

class AuditIssue {
  final String collection;
  final String field;
  final String description;

  const AuditIssue({
    required this.collection,
    required this.field,
    required this.description,
  });
}
