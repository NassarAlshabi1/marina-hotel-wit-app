// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Script لإضافة الحقول الجديدة إلى Appwrite Cloud
///
/// الاستخدام:
/// ```bash
/// dart run lib/scripts/add_discount_fields_to_appwrite.dart <API_KEY>
/// ```
///
/// للحصول على API Key:
/// 1. افتح Appwrite Console: https://cloud.appwrite.io/console
/// 2. اذهب إلى Settings → API Keys
/// 3. أنشئ API Key جديد مع صلاحيات: databases.write

const String endpoint = 'https://fra.cloud.appwrite.io/v1';
const String projectId = '690ff0da0025518570c1';
const String databaseId = 'hotel_db';
const String collectionId = 'bookings';

Future<void> main(List<String> args) async {
  print('🚀 إضافة حقول التخفيض إلى Appwrite Cloud');
  print('═══════════════════════════════════════════════');

  // التحقق من وجود API Key
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
    print('3. أنشئ API Key جديد مع صلاحيات: databases.write');
    print('\nثم شغل الأمر:');
    print(
      'dart run lib/scripts/add_discount_fields_to_appwrite.dart <API_KEY>',
    );
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
    // 1. إضافة حقل discountType
    print('1️⃣ إضافة حقل discountType...');
    final result1 = await addStringAttribute(
      client: client,
      apiKey: apiKey,
      attributeKey: 'discountType',
      size: 20,
      required: false,
      defaultValue: 'per_night',
    );

    if (result1) {
      print('   ✅ تم إضافة discountType بنجاح');
    } else {
      print('   ⚠️ فشل إضافة discountType (قد يكون موجود مسبقاً)');
    }

    // انتظار قليلاً قبل إضافة الحقل الثاني
    await Future.delayed(const Duration(seconds: 2));

    // 2. إضافة حقل discountStartDate
    print('\n2️⃣ إضافة حقل discountStartDate...');
    final result2 = await addStringAttribute(
      client: client,
      apiKey: apiKey,
      attributeKey: 'discountStartDate',
      size: 50,
      required: false,
    );

    if (result2) {
      print('   ✅ تم إضافة discountStartDate بنجاح');
    } else {
      print('   ⚠️ فشل إضافة discountStartDate (قد يكون موجود مسبقاً)');
    }

    print('\n═══════════════════════════════════════════════');
    print('✅ اكتمل التحديث!');
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

Future<bool> addStringAttribute({
  required http.Client client,
  required String apiKey,
  required String attributeKey,
  required int size,
  required bool required,
  String? defaultValue,
}) async {
  final url = Uri.parse(
    '$endpoint/databases/$databaseId/collections/$collectionId/attributes/string',
  );

  final body = {
    'key': attributeKey,
    'size': size,
    'required': required,
    if (defaultValue != null) 'default': defaultValue,
  };

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
      return true;
    } else if (response.statusCode == 409) {
      // Attribute already exists
      print('   ℹ️ الحقل موجود مسبقاً');
      return false;
    } else {
      print('   ❌ خطأ HTTP ${response.statusCode}: ${response.body}');
      return false;
    }
  } catch (e) {
    print('   ❌ خطأ في الاتصال: $e');
    return false;
  }
}
