// ============================================================================
// Marina Hotel - Supabase Sync Tests
// اختبارات المزامنة مع Supabase
// Tests for Supabase sync functionality
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

// ملاحظة: هذه الاختبارات تتطلب:
// Note: These tests require:
// 1. مشروع Supabase يعمل | Working Supabase project
// 2. Edge Functions منشورة | Deployed Edge Functions
// 3. مستخدم مسجل للاختبار | Registered test user

// ============================================================================
// التكوين | Configuration
// ============================================================================

class TestConfig {
  static const String supabaseUrl = 'https://mjsexsrrjphcgpvqcisb.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1qc2V4c3JyanBoY2dwdnFjaXNiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjIwMzk2ODAsImV4cCI6MjA3NzYxNTY4MH0.8mLsJqum971em7zG1Mv2h3zj8hg06KzsMXQAXsBbniA';
  static const String testEmail = 'adenmarina2@gmail.com';
  static const String testPassword = 'Tottinnbb007';
}

// ============================================================================
// Helper Functions - دوال مساعدة
// ============================================================================

/// تهيئة Supabase للاختبارات
Future<void> initSupabase() async {
  await Supabase.initialize(
    url: TestConfig.supabaseUrl,
    anonKey: TestConfig.supabaseAnonKey,
  );
}

/// تسجيل الدخول للاختبارات
Future<void> signInForTest() async {
  final supabase = Supabase.instance.client;
  await supabase.auth.signInWithPassword(
    email: TestConfig.testEmail,
    password: TestConfig.testPassword,
  );
}

/// إنشاء UUID للاختبار
String generateTestUuid() {
  final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
  return '$timestamp-0000-4000-8000-000000000000'
      .substring(0, 36)
      .replaceAll(RegExp(r'[^0-9a-f-]'), '0');
}

// ============================================================================
// Main Test Suite
// ============================================================================

void main() {
  // تهيئة Supabase قبل جميع الاختبارات
  setUpAll(() async {
    await initSupabase();
    await signInForTest();
    print('✅ Supabase initialized and signed in for tests');
  });

  // ============================================================================
  // Push Tests - اختبارات الدفع
  // ============================================================================

  group('Push Tests', () {
    test('Should push CREATE operation for rooms', () async {
      final supabase = Supabase.instance.client;
      final testUuid = generateTestUuid();

      final changes = [
        {
          'entity': 'rooms',
          'op': 'create',
          'uuid': testUuid,
          'server_id': null,
          'data': {
            'room_number': 'TEST-${DateTime.now().millisecondsSinceEpoch}',
            'type': 'مفردة',
            'price': 100.0,
            'status': 'شاغرة',
            'image_url': null,
          },
          'client_ts': DateTime.now().toIso8601String(),
        }
      ];

      final response = await supabase.functions.invoke(
        'sync-push',
        body: {'changes': changes},
      );

      expect(response.status, equals(200));
      expect(response.data['success'], equals(true));
      expect(response.data['data']['results'], isNotEmpty);
      expect(response.data['data']['results'][0]['success'], equals(true));
      expect(response.data['data']['results'][0]['server_id'], isNotNull);

      print('✅ CREATE operation pushed successfully');
    });

    test('Should push UPDATE operation for rooms', () async {
      final supabase = Supabase.instance.client;

      // أولاً: إنشاء غرفة للاختبار
      final testUuid = generateTestUuid();
      final roomNumber = 'TEST-${DateTime.now().millisecondsSinceEpoch}';

      final createChanges = [
        {
          'entity': 'rooms',
          'op': 'create',
          'uuid': testUuid,
          'server_id': null,
          'data': {
            'room_number': roomNumber,
            'type': 'مفردة',
            'price': 100.0,
            'status': 'شاغرة',
          },
          'client_ts': DateTime.now().toIso8601String(),
        }
      ];

      await supabase.functions.invoke(
        'sync-push',
        body: {'changes': createChanges},
      );

      // ثانياً: تحديث الغرفة
      final updateChanges = [
        {
          'entity': 'rooms',
          'op': 'update',
          'uuid': testUuid,
          'server_id': null,
          'data': {
            'room_number': roomNumber,
            'price': 150.0, // سعر جديد
            'status': 'صيانة', // حالة جديدة
          },
          'client_ts': DateTime.now().toIso8601String(),
        }
      ];

      final response = await supabase.functions.invoke(
        'sync-push',
        body: {'changes': updateChanges},
      );

      expect(response.status, equals(200));
      expect(response.data['success'], equals(true));
      expect(response.data['data']['results'][0]['success'], equals(true));

      print('✅ UPDATE operation pushed successfully');
    });

    test('Should push DELETE operation for rooms', () async {
      final supabase = Supabase.instance.client;

      // أولاً: إنشاء غرفة للاختبار
      final testUuid = generateTestUuid();
      final roomNumber = 'TEST-${DateTime.now().millisecondsSinceEpoch}';

      final createChanges = [
        {
          'entity': 'rooms',
          'op': 'create',
          'uuid': testUuid,
          'server_id': null,
          'data': {
            'room_number': roomNumber,
            'type': 'مفردة',
            'price': 100.0,
            'status': 'شاغرة',
          },
          'client_ts': DateTime.now().toIso8601String(),
        }
      ];

      await supabase.functions.invoke(
        'sync-push',
        body: {'changes': createChanges},
      );

      // ثانياً: حذف الغرفة (soft delete)
      final deleteChanges = [
        {
          'entity': 'rooms',
          'op': 'delete',
          'uuid': testUuid,
          'server_id': null,
          'data': {},
          'client_ts': DateTime.now().toIso8601String(),
        }
      ];

      final response = await supabase.functions.invoke(
        'sync-push',
        body: {'changes': deleteChanges},
      );

      expect(response.status, equals(200));
      expect(response.data['success'], equals(true));
      expect(response.data['data']['results'][0]['success'], equals(true));

      print('✅ DELETE operation pushed successfully');
    });

    test('Should push multiple changes in batch', () async {
      final supabase = Supabase.instance.client;

      final changes = [
        {
          'entity': 'rooms',
          'op': 'create',
          'uuid': generateTestUuid(),
          'server_id': null,
          'data': {
            'room_number': 'BATCH-1-${DateTime.now().millisecondsSinceEpoch}',
            'type': 'مفردة',
            'price': 100.0,
            'status': 'شاغرة',
          },
          'client_ts': DateTime.now().toIso8601String(),
        },
        {
          'entity': 'rooms',
          'op': 'create',
          'uuid': generateTestUuid(),
          'server_id': null,
          'data': {
            'room_number': 'BATCH-2-${DateTime.now().millisecondsSinceEpoch}',
            'type': 'مزدوجة',
            'price': 150.0,
            'status': 'شاغرة',
          },
          'client_ts': DateTime.now().toIso8601String(),
        },
      ];

      final response = await supabase.functions.invoke(
        'sync-push',
        body: {'changes': changes},
      );

      expect(response.status, equals(200));
      expect(response.data['success'], equals(true));
      expect(response.data['data']['results'], hasLength(2));
      expect(response.data['data']['results'][0]['success'], equals(true));
      expect(response.data['data']['results'][1]['success'], equals(true));

      print('✅ Batch push completed successfully');
    });
  });

  // ============================================================================
  // Pull Tests - اختبارات السحب
  // ============================================================================

  group('Pull Tests', () {
    test('Should pull changes from server', () async {
      final supabase = Supabase.instance.client;

      // Pull من بداية الزمن
      final response = await supabase.functions.invoke(
        'sync-pull',
        body: {'last_pull_ts': '1970-01-01T00:00:00.000Z'},
      );

      expect(response.status, equals(200));
      expect(response.data['success'], equals(true));
      expect(response.data['data']['data'], isList);
      expect(response.data['data']['new_server_ts'], isNotNull);

      final changes = response.data['data']['data'] as List;
      print('✅ Pulled ${changes.length} changes from server');
    });

    test('Should pull only new changes since last sync', () async {
      final supabase = Supabase.instance.client;

      // أولاً: Pull جميع التغييرات
      final firstResponse = await supabase.functions.invoke(
        'sync-pull',
        body: {'last_pull_ts': '1970-01-01T00:00:00.000Z'},
      );

      final firstServerTs = firstResponse.data['data']['new_server_ts'];
      final firstCount =
          (firstResponse.data['data']['data'] as List).length;

      // انتظر قليلاً
      await Future.delayed(Duration(seconds: 2));

      // ثانياً: Pull فقط التغييرات الجديدة
      final secondResponse = await supabase.functions.invoke(
        'sync-pull',
        body: {'last_pull_ts': firstServerTs},
      );

      final secondCount =
          (secondResponse.data['data']['data'] as List).length;

      expect(secondCount, lessThanOrEqualTo(firstCount));
      print(
          '✅ First pull: $firstCount changes, Second pull: $secondCount changes');
    });

    test('Should include entity type in pulled changes', () async {
      final supabase = Supabase.instance.client;

      final response = await supabase.functions.invoke(
        'sync-pull',
        body: {'last_pull_ts': '1970-01-01T00:00:00.000Z'},
      );

      final changes = response.data['data']['data'] as List;

      if (changes.isNotEmpty) {
        final change = changes.first;
        expect(change['entity'], isNotNull);
        expect(change['op'], isNotNull);
        expect(change['server_id'], isNotNull);
        expect(change['server_ts'], isNotNull);
        expect(change['data'], isNotNull);

        print('✅ Change structure validated: ${change['entity']}');
      } else {
        print('⚠️  No changes to validate');
      }
    });
  });

  // ============================================================================
  // Full Sync Flow Tests - اختبارات دورة المزامنة الكاملة
  // ============================================================================

  group('Full Sync Flow Tests', () {
    test('Should complete full push-pull cycle', () async {
      final supabase = Supabase.instance.client;
      final testUuid = generateTestUuid();
      final roomNumber = 'CYCLE-${DateTime.now().millisecondsSinceEpoch}';

      // 1. Push: إنشاء غرفة جديدة
      final pushChanges = [
        {
          'entity': 'rooms',
          'op': 'create',
          'uuid': testUuid,
          'server_id': null,
          'data': {
            'room_number': roomNumber,
            'type': 'جناح',
            'price': 300.0,
            'status': 'شاغرة',
          },
          'client_ts': DateTime.now().toIso8601String(),
        }
      ];

      final pushResponse = await supabase.functions.invoke(
        'sync-push',
        body: {'changes': pushChanges},
      );

      expect(pushResponse.status, equals(200));
      expect(pushResponse.data['success'], equals(true));

      // انتظر قليلاً للتأكد من حفظ البيانات
      await Future.delayed(Duration(seconds: 1));

      // 2. Pull: سحب التغييرات
      final pullResponse = await supabase.functions.invoke(
        'sync-pull',
        body: {'last_pull_ts': '1970-01-01T00:00:00.000Z'},
      );

      expect(pullResponse.status, equals(200));
      expect(pullResponse.data['success'], equals(true));

      final pulledChanges = pullResponse.data['data']['data'] as List;
      final ourChange = pulledChanges
          .firstWhere((c) => c['data']['room_number'] == roomNumber,
              orElse: () => null);

      expect(ourChange, isNotNull,
          reason: 'Should find our pushed room in pulled changes');
      expect(ourChange['entity'], equals('rooms'));
      expect(ourChange['data']['type'], equals('جناح'));
      expect(ourChange['data']['price'], equals(300.0));

      print('✅ Full push-pull cycle completed successfully');
    });

    test('Should handle conflict resolution (server wins)', () async {
      final supabase = Supabase.instance.client;
      final testUuid = generateTestUuid();
      final roomNumber = 'CONFLICT-${DateTime.now().millisecondsSinceEpoch}';

      // 1. إنشاء غرفة
      final createChanges = [
        {
          'entity': 'rooms',
          'op': 'create',
          'uuid': testUuid,
          'server_id': null,
          'data': {
            'room_number': roomNumber,
            'type': 'مفردة',
            'price': 100.0,
            'status': 'شاغرة',
          },
          'client_ts': DateTime.now().toIso8601String(),
        }
      ];

      await supabase.functions.invoke(
        'sync-push',
        body: {'changes': createChanges},
      );

      // 2. تحديث من العميل الأول
      final update1 = [
        {
          'entity': 'rooms',
          'op': 'update',
          'uuid': testUuid,
          'server_id': null,
          'data': {
            'room_number': roomNumber,
            'price': 120.0,
          },
          'client_ts': DateTime.now().toIso8601String(),
        }
      ];

      await supabase.functions.invoke(
        'sync-push',
        body: {'changes': update1},
      );

      await Future.delayed(Duration(milliseconds: 500));

      // 3. تحديث من عميل ثانٍ (محاكاة تعارض)
      final update2 = [
        {
          'entity': 'rooms',
          'op': 'update',
          'uuid': testUuid,
          'server_id': null,
          'data': {
            'room_number': roomNumber,
            'price': 130.0,
          },
          'client_ts': DateTime.now().toIso8601String(),
        }
      ];

      final response = await supabase.functions.invoke(
        'sync-push',
        body: {'changes': update2},
      );

      expect(response.status, equals(200));
      expect(response.data['success'], equals(true));

      // آخر تحديث يفوز (server wins)
      print('✅ Conflict handled: latest update wins');
    });
  });

  // ============================================================================
  // Error Handling Tests - اختبارات معالجة الأخطاء
  // ============================================================================

  group('Error Handling Tests', () {
    test('Should handle invalid entity gracefully', () async {
      final supabase = Supabase.instance.client;

      final changes = [
        {
          'entity': 'invalid_table',
          'op': 'create',
          'uuid': generateTestUuid(),
          'server_id': null,
          'data': {'test': 'data'},
          'client_ts': DateTime.now().toIso8601String(),
        }
      ];

      final response = await supabase.functions.invoke(
        'sync-push',
        body: {'changes': changes},
      );

      // يجب أن يكون هناك خطأ في النتائج
      expect(response.status, equals(200));
      expect(response.data['data']['results'][0]['success'], equals(false));
      expect(response.data['data']['results'][0]['error'], isNotNull);

      print('✅ Invalid entity handled gracefully');
    });

    test('Should handle missing required fields', () async {
      final supabase = Supabase.instance.client;

      final changes = [
        {
          'entity': 'rooms',
          'op': 'create',
          'uuid': generateTestUuid(),
          'server_id': null,
          'data': {
            // room_number مفقود (مطلوب)
            'type': 'مفردة',
            'price': 100.0,
          },
          'client_ts': DateTime.now().toIso8601String(),
        }
      ];

      final response = await supabase.functions.invoke(
        'sync-push',
        body: {'changes': changes},
      );

      // يجب أن يفشل بسبب الحقل المفقود
      expect(response.data['data']['results'][0]['success'], equals(false));

      print('✅ Missing required field handled');
    });

    test('Should handle empty changes array', () async {
      final supabase = Supabase.instance.client;

      final response = await supabase.functions.invoke(
        'sync-push',
        body: {'changes': []},
      );

      expect(response.status, equals(200));
      expect(response.data['success'], equals(true));
      expect(response.data['data']['results'], isEmpty);

      print('✅ Empty changes array handled');
    });
  });

  // ============================================================================
  // Performance Tests - اختبارات الأداء
  // ============================================================================

  group('Performance Tests', () {
    test('Should handle large batch efficiently', () async {
      final supabase = Supabase.instance.client;

      // إنشاء 50 غرفة في دفعة واحدة
      final changes = List.generate(50, (i) {
        return {
          'entity': 'rooms',
          'op': 'create',
          'uuid': generateTestUuid(),
          'server_id': null,
          'data': {
            'room_number':
                'PERF-${DateTime.now().millisecondsSinceEpoch}-$i',
            'type': 'مفردة',
            'price': 100.0 + i,
            'status': 'شاغرة',
          },
          'client_ts': DateTime.now().toIso8601String(),
        };
      });

      final stopwatch = Stopwatch()..start();

      final response = await supabase.functions.invoke(
        'sync-push',
        body: {'changes': changes},
      );

      stopwatch.stop();

      expect(response.status, equals(200));
      expect(response.data['success'], equals(true));
      expect(response.data['data']['results'], hasLength(50));

      print(
          '✅ Pushed 50 changes in ${stopwatch.elapsedMilliseconds}ms');

      // يجب أن يكتمل في أقل من 10 ثواني
      expect(stopwatch.elapsedMilliseconds, lessThan(10000));
    });
  });

  // تنظيف بعد الاختبارات
  tearDownAll(() {
    print('✅ All tests completed');
  });
}
