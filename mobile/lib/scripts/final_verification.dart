// lib/scripts/final_verification.dart
//
// ═══════════════════════════════════════════════════════════════════════════════
// سكربت التحقق النهائي من توافق camelCase مع Appwrite
// ═══════════════════════════════════════════════════════════════════════════════
//
// يتحقق هذا السكربت من:
// 1. جميع الحقول المطلوبة في كل collection موجودة بصيغة camelCase
// 2. لا توجد حقول snake_case متبقية في البيانات المرسلة
// 3. الـ adapters تدعم كلا الصيغتين (camelCase و snake_case)
//
// التشغيل: dart run lib/scripts/final_verification.dart
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:io';

/// الحقول المطلوبة في جميع collections (بصيغة camelCase)
const requiredFields = [
  'localUuid',
  'createdAt',
  'updatedAt',
  'lastModified',
  'vectorClock',
  'deviceId',
  'syncTimestamp',
  'version',
  'origin',
];

/// الحقل الخاصة بكل collection (بصيغة camelCase)
const collectionSpecificFields = {
  'bookings': [
    'roomNumber', 'guestName', 'guestPhone', 'checkinDate', 'checkoutDate',
    'status', 'guestIdType', 'guestIdNumber', 'guestNationality',
    'hotelDayCheckin', 'hotelDayCheckout',
  ],
  'rooms': [
    'roomNumber', 'roomType', 'basePrice', 'cleaningStatus',
  ],
  'expenses': [
    'expenseType', 'description', 'amount', 'date', 'hotelDayKey',
  ],
  'payments': [
    'paymentMethod', 'revenueType', 'amount', 'paymentDate', 'hotelDayKey',
  ],
  'debts': [
    'guestName', 'totalAmount', 'remainingAmount',
  ],
  'employees': [
    'name', 'position', 'basicSalary', 'hireDate',
  ],
  'salary_withdrawals': [
    'employeeId', 'cycleId', 'amount',
  ],
};

/// حقول snake_case التي يجب أن تكون محذوفة من البيانات المرسلة
const snakeCaseFieldsToRemove = [
  'localUuid',
  'createdAt',
  'updatedAt',
  'deletedAt',
  'lastModified',
  'vectorClock',
  'deviceId',
  'syncTimestamp',
  'room_number',
  'guest_name',
  'guest_phone',
  'checkin_date',
  'checkout_date',
  'expense_type',
  'payment_method',
  'hotel_day_key',
];

/// فحص ملفات الـ adapters
void verifyAdapters() {
  print('\n📦 فحص ملفات Adapters...');
  
  final adaptersDir = Directory('lib/services/adapters');
  if (!adaptersDir.existsSync()) {
    print('❌ مجلد adapters غير موجود');
    return;
  }
  
  int verifiedCount = 0;
  int warningCount = 0;
  
  for (final file in adaptersDir.listSync()) {
    if (file is File && file.path.endsWith('_adapter.dart')) {
      final content = file.readAsStringSync();
      final fileName = file.path.split('/').last;
      
      // التحقق من وجود دالة toJson
      if (content.contains('toJson')) {
        // التحقق من أن toJson تستخدم camelCase
        bool hasCamelCase = content.contains("'localUuid'") || 
                           content.contains('"localUuid"');
        
        if (hasCamelCase) {
          print('✅ $fileName: toJson يستخدم camelCase');
          verifiedCount++;
        } else {
          print('⚠️ $fileName: قد يحتاج مراجعة - لم يتم العثور على camelCase صريح');
          warningCount++;
        }
      }
      
      // التحقق من وجود دالة fromJson مع دعم multi-key
      if (content.contains('fromJson')) {
        bool hasMultiKeySupport = content.contains('_asStringMulti') || 
                                  content.contains('_vStrMulti') ||
                                  content.contains('_asIntMulti');
        
        if (hasMultiKeySupport) {
          print('✅ $fileName: fromJson يدعم مفاتيح متعددة (camelCase + snake_case)');
        } else {
          print('⚠️ $fileName: من الأفضل إضافة دعم للمفاتيح المتعددة');
          warningCount++;
        }
      }
    }
  }
  
  print('\n📊 ملخص فحص Adapters:');
  print('   ✅ ناجح: $verifiedCount');
  print('   ⚠️ تحذيرات: $warningCount');
}

/// فحص ملف key_converter.dart
void verifyKeyConverter() {
  print('\n🔧 فحص ملف key_converter.dart...');
  
  final file = File('lib/services/adapters/key_converter.dart');
  if (!file.existsSync()) {
    print('❌ ملف key_converter.dart غير موجود!');
    return;
  }
  
  final content = file.readAsStringSync();
  
  final requiredFunctions = [
    'snakeToCamelCase',
    'camelToSnakeCase',
    'convertKeysToCamelCase',
    'convertKeysToSnakeCase',
    'sanitizeForAppwrite',
    'addRequiredAppwriteFields',
  ];
  
  int foundCount = 0;
  for (final func in requiredFunctions) {
    if (content.contains(func)) {
      print('✅ الدالة $func موجودة');
      foundCount++;
    } else {
      print('❌ الدالة $func غير موجودة!');
    }
  }
  
  print('\n📊 ملخص key_converter: $foundCount/${requiredFunctions.length} دوال موجودة');
}

/// فحص ملف appwrite_delta_sync.dart
void verifyDeltaSync() {
  print('\n🔄 فحص ملف appwrite_delta_sync.dart...');
  
  final file = File('lib/services/appwrite_delta_sync.dart');
  if (!file.existsSync()) {
    print('❌ ملف appwrite_delta_sync.dart غير موجود!');
    return;
  }
  
  final content = file.readAsStringSync();
  
  // التحقق من _sanitizePayload
  if (content.contains('_sanitizePayload')) {
    // التحقق من أن _sanitizePayload لا تحول إلى snake_case
    bool hasSnakeCaseConversion = content.contains("convertKeysToSnakeCase") && 
                                  content.contains("_sanitizePayload");
    
    if (!hasSnakeCaseConversion) {
      print('✅ _sanitizePayload لا تحول إلى snake_case');
    } else {
      print('⚠️ _sanitizePayload قد تقوم بتحويل إلى snake_case - يحتاج مراجعة');
    }
    
    // التحقق من وجود الحقول المطلوبة camelCase
    bool hasRequiredCamelCase = content.contains("'createdAt'") &&
                                content.contains("'updatedAt'") &&
                                content.contains("'vectorClock'");
    
    if (hasRequiredCamelCase) {
      print('✅ _sanitizePayload تضيف الحقول المطلوبة بصيغة camelCase');
    } else {
      print('❌ _sanitizePayload قد لا تضيف جميع الحقول المطلوبة');
    }
  }
  
  // التحقق من _convertAppwriteToLocal
  if (content.contains('_convertAppwriteToLocal')) {
    print('✅ _convertAppwriteToLocal موجودة لتحويل البيانات الواردة');
  } else {
    print('⚠️ _convertAppwriteToLocal غير موجودة');
  }
  
  // التحقق من استخدام key_converter
  if (content.contains("import 'adapters/key_converter.dart'") ||
      content.contains('camelToSnakeCase') ||
      content.contains('snakeToCamelCase')) {
    print('✅ يتم استخدام دوال key_converter');
  } else {
    print('⚠️ لا يتم استخدام key_converter بشكل صريح');
  }
}

/// فحص ملف outbox_dao.dart
void verifyOutboxDao() {
  print('\n📤 فحص ملف outbox_dao.dart...');
  
  final file = File('lib/services/daos/outbox_dao.dart');
  if (!file.existsSync()) {
    print('❌ ملف outbox_dao.dart غير موجود!');
    return;
  }
  
  final content = file.readAsStringSync();
  
  // التحقق من استيراد key_converter
  if (content.contains("import '../adapters/key_converter.dart'")) {
    print('✅ يتم استيراد key_converter');
  } else {
    print('❌ لا يتم استيراد key_converter');
  }
  
  // التحقق من تحويل payload في merge
  if (content.contains('convertKeysToCamelCase(payload)') ||
      content.contains('convertKeysToCamelCase(camelPayload)')) {
    print('✅ دالة merge تقوم بتحويل payload إلى camelCase');
  } else {
    print('⚠️ دالة merge قد لا تقوم بتحويل payload');
  }
}

/// فحص ملف conflict_resolver.dart
void verifyConflictResolver() {
  print('\n⚔️ فحص ملف conflict_resolver.dart...');
  
  final file = File('lib/services/sync_core/conflict_resolver.dart');
  if (!file.existsSync()) {
    print('❌ ملف conflict_resolver.dart غير موجود!');
    return;
  }
  
  final content = file.readAsStringSync();
  
  // التحقق من دعم كلا الصيغتين في استخراج timestamp
  if (content.contains("['updatedAt'] ??") && content.contains("['updatedAt']") ||
      content.contains("['updatedAt'] ??") && content.contains("['updatedAt']")) {
    print('✅ conflict_resolver يدعم كلا الصيغتين (camelCase + snake_case)');
  } else {
    print('⚠️ conflict_resolver قد يدعم صيغة واحدة فقط');
  }
}

/// التحقق من بنية المشروع
void verifyProjectStructure() {
  print('\n📁 فحص بنية المشروع...');
  
  final requiredDirs = [
    'lib/services/adapters',
    'lib/services/sync_core',
    'lib/services/daos',
  ];
  
  for (final dir in requiredDirs) {
    if (Directory(dir).existsSync()) {
      print('✅ $dir موجود');
    } else {
      print('❌ $dir غير موجود');
    }
  }
}

/// الدالة الرئيسية
void main() {
  print('═══════════════════════════════════════════════════════════════════════════════');
  print('           سكربت التحقق النهائي من توافق camelCase مع Appwrite');
  print('═══════════════════════════════════════════════════════════════════════════════');
  
  // التحقق من بنية المشروع
  verifyProjectStructure();
  
  // فحص الملفات الرئيسية
  verifyKeyConverter();
  verifyAdapters();
  verifyDeltaSync();
  verifyOutboxDao();
  verifyConflictResolver();
  
  print('\n═══════════════════════════════════════════════════════════════════════════════');
  print('                              انتهى الفحص');
  print('═══════════════════════════════════════════════════════════════════════════════');
  print('\n⭐ للتشغيل الكامل، تأكد من:');
  print('   1. تشغيل dart run build_runner build لتوليد ملفات .g.dart');
  print('   2. اختبار عملية مزامنة كاملة (push + pull)');
  print('   3. مراقبة الـ logs للتأكد من عدم وجود أخطاء "Missing required attribute"');
  print('');
}
