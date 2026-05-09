// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// سكريبت لإضافة جدول booking_price_adjustments إلى Appwrite Cloud
///
/// الاستخدام:
/// ```bash
/// dart run lib/scripts/add_booking_price_adjustments_to_appwrite.dart <API_KEY>
/// ```
///
/// للحصول على API Key:
/// 1. افتح Appwrite Console: https://cloud.appwrite.io/console
/// 2. اذهب إلى Settings → API Keys
/// 3. أنشئ API Key جديد مع صلاحيات: databases.write, collections.write

const String endpoint = 'https://fra.cloud.appwrite.io/v1';
const String projectId = '690ff0da0025518570c1';
const String databaseId = 'hotel_db';
const String collectionId = 'booking_price_adjustments';

final List<Map<String, dynamic>> attributes = [
  {'key': 'localUuid', 'type': 'string', 'size': 36, 'required': true},
  {'key': 'bookingLocalUuid', 'type': 'string', 'size': 36, 'required': true},
  {'key': 'bookingLocalId', 'type': 'integer', 'required': false},
  {'key': 'adjustmentType', 'type': 'integer', 'required': true},
  {'key': 'adjustmentMode', 'type': 'string', 'size': 20, 'required': false, 'default': 'per_night'},
  {'key': 'amount', 'type': 'double', 'required': true},
  {'key': 'effectiveHotelDay', 'type': 'string', 'size': 10, 'required': true},
  {'key': 'endHotelDay', 'type': 'string', 'size': 10, 'required': false},
  {'key': 'isActive', 'type': 'boolean', 'required': false, 'default': true},
  {'key': 'reason', 'type': 'string', 'size': 500, 'required': false},
  {'key': 'appliedBy', 'type': 'string', 'size': 100, 'required': false},
  {'key': 'cancelledAt', 'type': 'string', 'size': 30, 'required': false},
  {'key': 'cancelledBy', 'type': 'string', 'size': 100, 'required': false},
  // Sync Fields
  {'key': 'serverId', 'type': 'integer', 'required': false},
  {'key': 'createdAt', 'type': 'integer', 'required': true},
  {'key': 'updatedAt', 'type': 'integer', 'required': true},
  {'key': 'deletedAt', 'type': 'integer', 'required': false},
  {'key': 'lastModified', 'type': 'integer', 'required': true},
  {'key': 'createdAtIso', 'type': 'string', 'size': 50, 'required': false},
  {'key': 'updatedAtIso', 'type': 'string', 'size': 50, 'required': false},
  {'key': 'deletedAtIso', 'type': 'string', 'size': 50, 'required': false},
  {'key': 'createdAtEpoch', 'type': 'integer', 'required': false, 'default': 0},
  {'key': 'lastModifiedEpoch', 'type': 'integer', 'required': false, 'default': 0},
  {'key': 'version', 'type': 'integer', 'required': false, 'default': 1},
  {'key': 'origin', 'type': 'string', 'size': 20, 'required': false, 'default': 'local'},
  {'key': 'vectorClock', 'type': 'string', 'size': 1000, 'required': false, 'default': '{}'},
];

Future<void> main(List<String> args) async {
  print('🚀 إضافة جدول booking_price_adjustments إلى Appwrite Cloud');
  print('═══════════════════════════════════════════════════════════');

  String? apiKey;

  if (args.isEmpty) {
    print('📝 الرجاء إدخال API Key:');
    apiKey = stdin.readLineSync()?.trim();
  } else {
    apiKey = args[0];
  }

  if (apiKey == null || apiKey.isEmpty) {
    print('❌ خطأ: API Key مطلوب');
    print('\nللحصول على API Key:');
    print('1. افتح https://cloud.appwrite.io/console');
    print('2. اختر المشروع → Settings → API Keys');
    print('3. أنشئ API Key جديد مع صلاحيات: databases.write, collections.write');
    print('\nثم شغل الأمر:');
    print('dart run lib/scripts/add_booking_price_adjustments_to_appwrite.dart <API_KEY>');
    exit(1);
  }

  print('\n📊 المعلومات:');
  print('Endpoint: $endpoint');
  print('Project ID: $projectId');
  print('Database ID: $databaseId');
  print('Collection ID: $collectionId');
  print('\n');

  final client = http.Client();

  try {
    // 1. إنشاء الـ Collection
    print('1️⃣ إنشاء الـ Collection...');
    final collectionCreated = await createCollection(client, apiKey);
    
    if (!collectionCreated) {
      print('   ⚠️ الـ Collection قد يكون موجوداً بالفعل، نستمر بإضافة الحقول...');
    } else {
      print('   ✅ تم إنشاء الـ Collection بنجاح');
    }

    // 2. إضافة الحقول
    print('\n2️⃣ إضافة الحقول...');
    int successCount = 0;
    int skipCount = 0;
    int failCount = 0;

    for (final attr in attributes) {
      await Future.delayed(const Duration(milliseconds: 500));
      
      final result = await addAttribute(client, apiKey, attr);
      
      if (result == 'success') {
        successCount++;
        print('   ✅ ${attr['key']}');
      } else if (result == 'exists') {
        skipCount++;
        print('   ℹ️ ${attr['key']} (موجود)');
      } else {
        failCount++;
        print('   ❌ ${attr['key']} (فشل)');
      }
    }

    // 3. إنشاء الـ Index
    print('\n3️⃣ إنشاء الـ Indexes...');
    await createIndex(client, apiKey, 'idx_local_uuid', ['localUuid'], ['ASC'], 'unique');
    await createIndex(client, apiKey, 'idx_booking_uuid', ['bookingLocalUuid', 'isActive'], ['ASC', 'DESC'], 'key');
    await createIndex(client, apiKey, 'idx_dates', ['effectiveHotelDay', 'endHotelDay'], ['ASC', 'ASC'], 'key');

    print('\n═══════════════════════════════════════════════════════════');
    print('📊 النتائج:');
    print('   ✅ حقول ناجحة: $successCount');
    print('   ℹ️ حقول موجودة: $skipCount');
    print('   ❌ حقول فاشلة: $failCount');
    print('\n✅ اكتمل التحديث!');
    print('\nملاحظات:');
    print('• الحقول قد تحتاج بضع ثوانٍ لتكون جاهزة (Indexing)');
    print('• تحقق من Appwrite Console للتأكد');
    print('• يمكنك الآن استخدام التطبيق بشكل طبيعي');
  } catch (e) {
    print('\n❌ خطأ: $e');
    exit(1);
  } finally {
    client.close();
  }
}

Future<bool> createCollection(http.Client client, String apiKey) async {
  final url = Uri.parse('$endpoint/databases/$databaseId/collections');

  try {
    final response = await client.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'X-Appwrite-Project': projectId,
        'X-Appwrite-Key': apiKey,
      },
      body: json.encode({
        'collectionId': collectionId,
        'name': 'Booking Price Adjustments',
        'permissions': [
          'read("any")',
          'create("any")',
          'update("any")',
          'delete("any")',
        ],
        'documentSecurity': false,
      }),
    );

    return response.statusCode == 201;
  } catch (e) {
    print('   ❌ خطأ في إنشاء الـ Collection: $e');
    return false;
  }
}

Future<String> addAttribute(http.Client client, String apiKey, Map<String, dynamic> attr) async {
  final type = attr['type'] as String;
  final key = attr['key'] as String;
  final required = attr['required'] as bool? ?? false;
  
  String urlPath;
  final Map<String, dynamic> body = {
    'key': key,
    'required': required,
  };

  if (type == 'string') {
    urlPath = 'string';
    body['size'] = attr['size'] ?? 255;
    if (attr['default'] != null) body['default'] = attr['default'];
  } else if (type == 'integer') {
    urlPath = 'integer';
    if (attr['default'] != null) body['default'] = attr['default'];
  } else if (type == 'double') {
    urlPath = 'float';
    if (attr['default'] != null) body['default'] = attr['default'];
  } else if (type == 'boolean') {
    urlPath = 'boolean';
    if (attr['default'] != null) body['default'] = attr['default'];
  } else {
    return 'fail';
  }

  final url = Uri.parse(
    '$endpoint/databases/$databaseId/collections/$collectionId/attributes/$urlPath',
  );

  try {
    final response = await client.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'X-Appwrite-Project': projectId,
        'X-Appwrite-Key': apiKey,
      },
      body: json.encode(body),
    );

    if (response.statusCode == 201 || response.statusCode == 202) {
      return 'success';
    } else if (response.statusCode == 409) {
      return 'exists';
    } else {
      return 'fail';
    }
  } catch (e) {
    return 'fail';
  }
}

Future<void> createIndex(
  http.Client client,
  String apiKey,
  String indexKey,
  List<String> attributes,
  List<String> orders,
  String type,
) async {
  final url = Uri.parse(
    '$endpoint/databases/$databaseId/collections/$collectionId/indexes',
  );

  try {
    final response = await client.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'X-Appwrite-Project': projectId,
        'X-Appwrite-Key': apiKey,
      },
      body: json.encode({
        'key': indexKey,
        'type': type,
        'attributes': attributes,
        'orders': orders,
      }),
    );

    if (response.statusCode == 201 || response.statusCode == 202) {
      print('   ✅ Index: $indexKey');
    } else if (response.statusCode == 409) {
      print('   ℹ️ Index: $indexKey (موجود)');
    } else {
      print('   ❌ Index: $indexKey (فشل: ${response.statusCode})');
    }
  } catch (e) {
    print('   ❌ Index: $indexKey (خطأ: $e)');
  }
}
