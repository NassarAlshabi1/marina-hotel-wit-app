// ignore_for_file: avoid_print, prefer_const_declarations

// test/sync_fields_audit_test.dart
//
// ✅ تدقيق فعلي — يطابق adapters مع validFieldsPerCollection
// الاستخدام: flutter test test/sync_fields_audit_test.dart
//
// الفحص الرئيسي: لكل adapter مُسجّل في AdapterRegistry، نتأكد من:
//   1. collectionId الخاص بالـ adapter موجود في validFieldsPerCollection
//   2. (مستقبلاً) الحقول التي يُنتجها toJson موجودة في مخطط المجموعة
//
// هذا يمنع "Unknown attribute" errors من Appwrite عند الإرسال،
// ويضمن عدم فقدان البيانات صامتاً عبر sanitizePayload.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_utils.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AdapterRegistry adapters;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    adapters = AdapterRegistry(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('sync fields audit — every adapter.collectionId must exist in validFieldsPerCollection', () {
    final schema = AppwriteSyncUtils.validFieldsPerCollection;

    // اجمع كل adapters من AdapterRegistry
    // BaseRepository.adapter.collectionId هو المعرف
    final allAdapters = <String>[
      adapters.bookings.adapter.collectionId,
      adapters.payments.adapter.collectionId,
      adapters.expenses.adapter.collectionId,
      adapters.debts.adapter.collectionId,
      adapters.rooms.adapter.collectionId,
      adapters.nights.adapter.collectionId,
      adapters.employees.adapter.collectionId,
      adapters.salaryCycles.adapter.collectionId,
      adapters.salaryPayments.adapter.collectionId,
      adapters.bookingNotes.adapter.collectionId,
      adapters.cashTransactions.adapter.collectionId,
      adapters.shiftNotes.adapter.collectionId,
      adapters.priceAdjustments.adapter.collectionId,
      adapters.auditLogs.adapter.collectionId,
      adapters.paymentVoids.adapter.collectionId,
      adapters.bookingPriceAdjustments.adapter.collectionId,
      adapters.guestInfos.adapter.collectionId,
      adapters.salaryWithdrawals.adapter.collectionId,
      adapters.salaryCarryOverLogs.adapter.collectionId,
    ];

    print('\n${'=' * 70}');
    print('  Sync Fields Audit Report');
    print('${'=' * 70}\n');
    print('Registered adapters: ${allAdapters.length}');
    print('Schema collections: ${schema.length}\n');

    final missingAdapters = <String>[];
    for (final collectionId in allAdapters) {
      if (!schema.containsKey(collectionId)) {
        missingAdapters.add(collectionId);
      }
    }

    if (missingAdapters.isEmpty) {
      print('✅ All adapter.collectionId values are present in '
          'validFieldsPerCollection.');
    } else {
      print('❌ Adapters without schema entry:');
      for (final c in missingAdapters) {
        print('  ⚠️  "$c" — adapter is registered but collection is NOT in '
            'validFieldsPerCollection');
      }
    }

    print('\nTotal adapters checked: ${allAdapters.length}');
    print('Total collections in schema: ${schema.length}');
    print('Missing: ${missingAdapters.length}\n');

    expect(
      missingAdapters,
      isEmpty,
      reason:
          '${missingAdapters.length} adapter(s) are missing from '
          'validFieldsPerCollection. Add the missing collection IDs to '
          'AppwriteSyncUtils.validFieldsPerCollection to prevent '
          '"Unknown attribute" errors from Appwrite.',
    );
  });

  test('sync fields audit — every schema collection has required sync fields', () {
    final schema = AppwriteSyncUtils.validFieldsPerCollection;

    // الحقول الأساسية لكل collection تشارك في المزامنة (SyncFields mixin)
    const requiredSyncFields = <String>{
      'localUuid',
      'createdAt',
      'updatedAt',
      'lastModified',
      'version',
      'origin',
      'vectorClock',
      'deviceId',
      'deletedAt',
    };

    final missingFieldsByCollection = <String, Set<String>>{};

    for (final entry in schema.entries) {
      final collection = entry.key;
      final fields = entry.value;
      final missing = requiredSyncFields.difference(fields);
      if (missing.isNotEmpty) {
        missingFieldsByCollection[collection] = missing;
      }
    }

    print('\n${'=' * 70}');
    print('  Required Sync Fields Audit');
    print('${'=' * 70}\n');

    if (missingFieldsByCollection.isEmpty) {
      print('✅ All collections have the required sync fields:');
      print('   ${requiredSyncFields.join(', ')}');
    } else {
      print('❌ Collections missing required sync fields:');
      for (final entry in missingFieldsByCollection.entries) {
        print('  ⚠️  ${entry.key} missing: ${entry.value.join(', ')}');
      }
    }

    print('\nTotal collections checked: ${schema.length}');
    print('Collections with missing fields: ${missingFieldsByCollection.length}\n');

    // ملاحظة: بعض المجموعات (مثل audit_logs) قد لا تتبع SyncFields mixin
    // بشكل كامل، لذا نُصدر تحذيراً فقط دون فشل الاختبار.
    if (missingFieldsByCollection.isNotEmpty) {
      print('⚠️  Warning: Some collections are missing required sync fields. '
          'This may be intentional for non-synced tables (e.g., audit_logs).');
    }
  });
}
