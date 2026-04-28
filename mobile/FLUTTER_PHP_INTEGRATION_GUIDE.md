# دليل ربط Flutter مع PHP/MySQL API

## الملفات المضافة

### 1. `lib/services/api_config_service.dart`
خدمة إدارة إعدادات API:
- حفظ وتحميل إعدادات الاتصال
- إدارة قائمة السيرفرات المحفوظة
- دعم التبديل بين السيرفرات
- إعدادات المهلة والسجلات

### 2. `lib/utils/field_mapper.dart`
محول الحقول بين Flutter و PHP:
- تحويل أسماء الحقول من camelCase إلى snake_case
- تحويل البيانات بين صيغة Flutter و PHP
- دعم جميع الكيانات (rooms, bookings, payments, etc.)
- التحقق من الحقول المطلوبة

### 3. `lib/services/php_api_service.dart`
خدمة الاتصال بـ PHP API:
- تسجيل الدخول والخروج
- CRUD لجميع الكيانات
- دعم المزامنة (push/pull)
- رفع الصور
- سجل الطلبات للتتبع

### 4. `lib/screens/settings/php_api_settings_screen.dart`
شاشة إعدادات PHP API:
- إعداد رابط API ومفتاح الوصول
- إدارة السيرفرات المحفوظة
- اختبار الاتصال
- عرض سجل الطلبات

## كيفية الاستخدام

### 1. تهيئة الخدمات عند بدء التطبيق
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiConfigService.instance.initialize();
  runApp(MyApp());
}
```

### 2. استخدام PhpApiService
```dart
// تسجيل الدخول
final result = await PhpApiService.instance.login('admin', 'password');
if (result.success) {
  print('مرحباً ${result.data?['full_name']}');
}

// جلب قائمة الغرف
final rooms = await PhpApiService.instance.list('rooms');
if (rooms.success) {
  for (final room in rooms.data!) {
    print('غرفة: ${room['roomNumber']}');
  }
}

// إنشاء حجز جديد
final booking = await PhpApiService.instance.create('bookings', {
  'roomNumber': '101',
  'guestName': 'محمد أحمد',
  'guestPhone': '0501234567',
  'guestNationality': 'سعودي',
  'checkinDate': '2026-02-04',
  'status': 'active',
});

// مزامنة التغييرات
final sync = await PhpApiService.instance.syncPush([
  {'entity': 'rooms', 'action': 'update', 'data': {...}},
]);
```

### 3. تحويل الحقول يدوياً
```dart
// من Flutter إلى PHP
final phpData = FieldMapper.toPhpMap('bookings', flutterData);

// من PHP إلى Flutter
final flutterData = FieldMapper.toFlutterMap('bookings', phpData);
```

## الكيانات المدعومة
- `rooms` - الغرف
- `bookings` - الحجوزات
- `booking_notes` - ملاحظات الحجوزات
- `employees` - الموظفين
- `expenses` - المصروفات
- `cash_transactions` - المعاملات النقدية
- `payments` - المدفوعات
- `system_settings` - إعدادات النظام
- `users` - المستخدمين

## متطلبات PHP Backend

### نقاط النهاية المطلوبة
```
POST   /auth/login.php          - تسجيل الدخول
GET    /auth/ping.php           - اختبار الاتصال
GET    /info.php                - معلومات السيرفر

GET    /{entity}.php            - قائمة العناصر
GET    /{entity}.php/{id}       - عنصر واحد
POST   /{entity}.php            - إنشاء عنصر
PUT    /{entity}.php/{id}       - تحديث عنصر
DELETE /{entity}.php/{id}       - حذف عنصر

POST   /sync/push.php           - دفع التغييرات
GET    /sync/pull.php?since=    - سحب التغييرات

POST   /uploads/rooms.php       - رفع صور الغرف
```

### صيغة الاستجابة
```json
{
  "success": true,
  "data": {...},
  "message": "رسالة اختيارية"
}
```

### صيغة الخطأ
```json
{
  "success": false,
  "message": "وصف الخطأ",
  "errors": {
    "field_name": ["رسالة الخطأ"]
  }
}
```

## ملاحظات
- يتم حفظ إعدادات API في SharedPreferences
- يتم حفظ token المصادقة في FlutterSecureStorage
- يدعم النظام إعادة المحاولة التلقائية عند أخطاء الشبكة
- يمكن الوصول للشاشة من: الإعدادات ← إعدادات PHP API
