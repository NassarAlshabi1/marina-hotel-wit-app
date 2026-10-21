# دليل دمج Appwrite في تطبيق Marina Hotel Mobile

## 📋 نظرة عامة

تم دمج نظام Appwrite كامل في تطبيق Marina Hotel Mobile مع شاشة إعدادات متقدمة للمزامنة السحابية، التخزين المؤقت، ومعالجة الأخطاء.

## ✅ المكونات المُضافة

### 1. الخدمات الأساسية (lib/services/)

#### ملفات النظام الأساسي:
- ✅ `appwrite_config.dart` - إعدادات Appwrite المركزية
- ✅ `appwrite_service.dart` - خدمة CRUD الأساسية
- ✅ `appwrite_models.dart` - نماذج البيانات (Room, Booking, Payment, إلخ)
- ✅ `appwrite_sync_manager.dart` - مدير المزامنة الثنائية
- ✅ `appwrite_cache_manager.dart` - نظام التخزين المؤقت الذكي
- ✅ `appwrite_error_handler.dart` - معالج الأخطاء المركزي
- ✅ `appwrite_logger.dart` - نظام التسجيل المتقدم

### 2. Riverpod Providers (lib/providers/)
- ✅ `appwrite_providers.dart` - جميع مزودات النظام

### 3. الشاشات (lib/screens/settings/)
- ✅ `appwrite_settings_screen.dart` - شاشة الإعدادات الرئيسية
- ✅ `appwrite_logs_screen.dart` - شاشة عرض السجلات
- ✅ `appwrite_sync_stats_screen.dart` - شاشة إحصائيات المزامنة

### 4. التعديلات على الملفات الموجودة
- ✅ `lib/screens/settings/settings_screen.dart` - إضافة رابط الإعدادات
- ✅ `lib/main.dart` - تهيئة النظام عند بدء التطبيق
- ✅ `pubspec.yaml` - إضافة dependency: `appwrite: ^12.0.3`

## 🚀 خطوات التفعيل

### 1. إنشاء مشروع Appwrite

1. انتقل إلى [Appwrite Cloud Console](https://cloud.appwrite.io)
2. أنشئ مشروعاً جديداً
3. سجّل معرف المشروع (Project ID)

### 2. إنشاء قاعدة البيانات والمجموعات

#### إنشاء قاعدة البيانات:
```
Database Name: marina_hotel_db
Database ID: marina_hotel_db
```

#### إنشاء المجموعات (Collections):

##### 1. Rooms Collection
```json
{
  "collectionId": "rooms",
  "name": "Rooms",
  "attributes": [
    {"key": "roomNumber", "type": "string", "size": 50, "required": true},
    {"key": "type", "type": "string", "size": 50, "required": true},
    {"key": "status", "type": "string", "size": 50, "required": true},
    {"key": "price", "type": "double", "required": true},
    {"key": "floor", "type": "integer", "required": true},
    {"key": "lastModified", "type": "datetime", "required": false},
    {"key": "lastModifiedBy", "type": "string", "size": 100, "required": false}
  ]
}
```

##### 2. Bookings Collection
```json
{
  "collectionId": "bookings",
  "name": "Bookings",
  "attributes": [
    {"key": "roomId", "type": "string", "size": 100, "required": true},
    {"key": "guestName", "type": "string", "size": 200, "required": true},
    {"key": "guestPhone", "type": "string", "size": 50, "required": true},
    {"key": "checkIn", "type": "datetime", "required": true},
    {"key": "checkOut", "type": "datetime", "required": true},
    {"key": "status", "type": "string", "size": 50, "required": true},
    {"key": "totalAmount", "type": "double", "required": true},
    {"key": "paidAmount", "type": "double", "required": true},
    {"key": "lastModified", "type": "datetime", "required": false},
    {"key": "lastModifiedBy", "type": "string", "size": 100, "required": false}
  ]
}
```

##### 3. Payments Collection
```json
{
  "collectionId": "payments",
  "name": "Payments",
  "attributes": [
    {"key": "bookingId", "type": "string", "size": 100, "required": true},
    {"key": "amount", "type": "double", "required": true},
    {"key": "paymentMethod", "type": "string", "size": 50, "required": true},
    {"key": "paymentDate", "type": "datetime", "required": true},
    {"key": "notes", "type": "string", "size": 500, "required": false},
    {"key": "lastModified", "type": "datetime", "required": false},
    {"key": "lastModifiedBy", "type": "string", "size": 100, "required": false}
  ]
}
```

##### 4. Expenses Collection
```json
{
  "collectionId": "expenses",
  "name": "Expenses",
  "attributes": [
    {"key": "category", "type": "string", "size": 100, "required": true},
    {"key": "amount", "type": "double", "required": true},
    {"key": "description", "type": "string", "size": 500, "required": true},
    {"key": "expenseDate", "type": "datetime", "required": true},
    {"key": "employeeId", "type": "string", "size": 100, "required": false},
    {"key": "lastModified", "type": "datetime", "required": false},
    {"key": "lastModifiedBy", "type": "string", "size": 100, "required": false}
  ]
}
```

##### 5. Employees Collection
```json
{
  "collectionId": "employees",
  "name": "Employees",
  "attributes": [
    {"key": "name", "type": "string", "size": 200, "required": true},
    {"key": "phone", "type": "string", "size": 50, "required": true},
    {"key": "position", "type": "string", "size": 100, "required": true},
    {"key": "salary", "type": "double", "required": true},
    {"key": "status", "type": "string", "size": 50, "required": true},
    {"key": "lastModified", "type": "datetime", "required": false},
    {"key": "lastModifiedBy", "type": "string", "size": 100, "required": false}
  ]
}
```

##### 6. Debts Collection
```json
{
  "collectionId": "debts",
  "name": "Debts",
  "attributes": [
    {"key": "bookingId", "type": "string", "size": 100, "required": true},
    {"key": "guestName", "type": "string", "size": 200, "required": true},
    {"key": "amount", "type": "double", "required": true},
    {"key": "status", "type": "string", "size": 50, "required": true},
    {"key": "dueDate", "type": "datetime", "required": true},
    {"key": "lastModified", "type": "datetime", "required": false},
    {"key": "lastModifiedBy", "type": "string", "size": 100, "required": false}
  ]
}
```

##### 7. Devices Collection
```json
{
  "collectionId": "devices",
  "name": "Devices",
  "attributes": [
    {"key": "deviceName", "type": "string", "size": 200, "required": true},
    {"key": "deviceModel", "type": "string", "size": 200, "required": true},
    {"key": "osVersion", "type": "string", "size": 100, "required": true},
    {"key": "lastSeen", "type": "datetime", "required": true},
    {"key": "status", "type": "string", "size": 50, "required": true},
    {"key": "createdAt", "type": "datetime", "required": true}
  ]
}
```

##### 8. Sync Logs Collection
```json
{
  "collectionId": "sync_logs",
  "name": "Sync Logs",
  "attributes": [
    {"key": "deviceId", "type": "string", "size": 100, "required": true},
    {"key": "syncType", "type": "string", "size": 50, "required": true},
    {"key": "startTime", "type": "datetime", "required": true},
    {"key": "endTime", "type": "datetime", "required": false},
    {"key": "status", "type": "string", "size": 50, "required": true},
    {"key": "recordsPushed", "type": "integer", "required": true},
    {"key": "recordsPulled", "type": "integer", "required": true},
    {"key": "conflicts", "type": "integer", "required": true},
    {"key": "errorMessage", "type": "string", "size": 1000, "required": false}
  ]
}
```

### 3. تكوين الصلاحيات

لكل مجموعة، قم بإعداد الصلاحيات التالية:

#### للقراءة (Read):
- Role: Any (للسماح بالقراءة بدون مصادقة)
- أو: استخدم API Key للوصول الآمن

#### للكتابة (Create/Update/Delete):
- Role: Any (للسماح بالكتابة)
- أو: استخدم API Key

### 4. تعيين Project ID في التطبيق

افتح ملف `lib/services/appwrite_config.dart` وعدّل:

```dart
// استبدل هذا
static const String projectId = 'YOUR_PROJECT_ID_HERE';

// بـ Project ID الخاص بك
static const String projectId = '67abc123def456';
```

### 5. تشغيل التطبيق

```bash
cd mobile
flutter pub get
flutter run
```

## 📱 استخدام الشاشات

### 1. الوصول إلى إعدادات Appwrite
```
الإعدادات > إعدادات Appwrite
```

### 2. اختبار الاتصال
1. افتح شاشة إعدادات Appwrite
2. اضغط على "اختبار الاتصال"
3. تأكد من ظهور "متصل بنجاح"

### 3. تفعيل المزامنة التلقائية
1. فعّل "تفعيل المزامنة التلقائية"
2. اختر فترة المزامنة (15 دقيقة افتراضياً)
3. اضغط "مزامنة الآن" لبدء المزامنة الفورية

### 4. إدارة التخزين المؤقت
- فعّل/عطّل التخزين المؤقت
- اختر مدة الصلاحية (6 ساعات افتراضياً)
- حدد الحد الأقصى للحجم (20 MB افتراضياً)
- امسح الذاكرة المؤقتة عند الحاجة

### 5. عرض السجلات
1. اضغط "عرض السجلات"
2. فلتر حسب المستوى (Debug, Info, Warning, Error, Critical)
3. ابحث في السجلات
4. صدّر أو شارك السجلات

### 6. عرض إحصائيات المزامنة
1. اضغط "التفاصيل" في قسم المزامنة
2. شاهد الرسوم البيانية والإحصائيات
3. راقب معدل النجاح والبيانات المنقولة

## ⚙️ الإعدادات المتقدمة

### إعدادات المزامنة (SharedPreferences)
```dart
'appwrite_sync_enabled': bool           // تفعيل المزامنة التلقائية
'appwrite_sync_interval': int           // الفترة بالدقائق (5, 10, 15, 30, 60)
'appwrite_auto_sync_on_connect': bool   // مزامنة عند الاتصال بالإنترنت
```

### إعدادات التخزين المؤقت
```dart
'appwrite_cache_enabled': bool          // تفعيل التخزين المؤقت
'appwrite_cache_ttl': int               // مدة الصلاحية بالساعات (1, 2, 6, 12, 24)
'appwrite_cache_max_size': int          // الحد الأقصى بالميجابايت (5, 10, 20, 50, 100)
```

### إعدادات السجلات
```dart
'appwrite_log_level': String            // debug, info, warning, error, critical
'appwrite_log_console': bool            // تسجيل في Console
'appwrite_log_file': bool               // تسجيل في الملفات
```

## 🔧 معالجة الأخطاء

النظام يتعامل تلقائياً مع الأخطاء التالية:

### أخطاء الشبكة
- **NETWORK_ERROR**: فشل الاتصال بالشبكة
- **TIMEOUT_ERROR**: انتهت مهلة الاتصال
- الحل: التحقق من الاتصال بالإنترنت

### أخطاء المصادقة
- **AUTH_ERROR**: خطأ في المصادقة
- **PERMISSION_ERROR**: لا توجد صلاحية
- الحل: التحقق من إعدادات الصلاحيات في Appwrite

### أخطاء الخادم
- **SERVER_ERROR**: خطأ في الخادم (500, 502, 503)
- **RATE_LIMIT**: تم تجاوز حد الطلبات
- الحل: الانتظار وإعادة المحاولة

### أخطاء المزامنة
- **CONFLICT_ERROR**: تضارب في البيانات
- الحل: يتم حل التضارب تلقائياً باستخدام "آخر تحديث يفوز"

## 📊 المميزات

### ✅ المزامنة الثنائية
- رفع البيانات المحلية إلى السحابة
- تحميل البيانات من السحابة
- كشف وحل التضارب تلقائياً
- مزامنة دورية قابلة للتخصيص

### ✅ التخزين المؤقت الذكي
- تقليل طلبات الشبكة
- تحسين الأداء
- إدارة تلقائية للذاكرة
- تنظيف دوري للبيانات منتهية الصلاحية

### ✅ معالجة الأخطاء المتقدمة
- تصنيف الأخطاء حسب النوع
- رسائل واضحة بالعربية
- محاولات إعادة تلقائية
- تسجيل تفصيلي للأخطاء

### ✅ نظام التسجيل
- مستويات متعددة (Debug, Info, Warning, Error, Critical)
- تسجيل في Console والملفات
- تصدير ومشاركة السجلات
- فلترة وبحث متقدم

### ✅ إحصائيات وتقارير
- معدل نجاح المزامنة
- عدد السجلات المرفوعة/المحملة
- التضارب المحلول
- رسوم بيانية تفاعلية

## 🔐 الأمان

### التوصيات الأمنية:
1. **لا تُدرج API Keys في الكود** - استخدم متغيرات البيئة
2. **استخدم HTTPS فقط** - Appwrite Cloud يستخدم HTTPS افتراضياً
3. **قيّد الصلاحيات** - امنح الحد الأدنى من الصلاحيات المطلوبة
4. **فعّل Rate Limiting** - لمنع الإساءة
5. **راجع السجلات بانتظام** - لاكتشاف الأنشطة المشبوهة

## 🐛 استكشاف الأخطاء

### المشكلة: "فشل الاتصال بـ Appwrite"
**الحلول:**
1. تحقق من Project ID في `appwrite_config.dart`
2. تحقق من اتصال الإنترنت
3. تحقق من إعدادات الصلاحيات في Appwrite Console

### المشكلة: "خطأ في المصادقة"
**الحلول:**
1. تحقق من إعدادات API Key
2. تحقق من صلاحيات المجموعات
3. تأكد من تفعيل الوصول للتطبيقات

### المشكلة: "لا توجد بيانات"
**الحلول:**
1. تحقق من وجود المجموعات في Database
2. تحقق من أسماء Collections IDs
3. جرّب المزامنة اليدوية

### المشكلة: "تضارب في البيانات"
**الحلول:**
1. النظام يحل التضارب تلقائياً
2. راجع سجل المزامنة لمعرفة التفاصيل
3. عند الحاجة، استخدم "إعادة تعيين المزامنة"

## 📝 التطوير المستقبلي

### الميزات المخطط لها:
- [ ] دمج كامل مع قاعدة بيانات Drift المحلية
- [ ] رفع وتحميل جميع البيانات (Push/Pull All)
- [ ] استراتيجيات حل تضارب متقدمة
- [ ] مزامنة انتقائية (Selective Sync)
- [ ] تشفير البيانات من طرف إلى طرف
- [ ] دعم المزامنة في الوضع غير المتصل (Offline Queue)
- [ ] إشعارات الوقت الفعلي (Realtime)
- [ ] نسخ احتياطي تلقائي إلى Appwrite Storage

## 📚 الموارد

### الوثائق:
- [Appwrite Documentation](https://appwrite.io/docs)
- [Flutter Appwrite SDK](https://pub.dev/packages/appwrite)
- [Appwrite Cloud Console](https://cloud.appwrite.io)

### الدعم:
- [Appwrite Discord](https://discord.gg/appwrite)
- [Appwrite GitHub](https://github.com/appwrite/appwrite)

## 👨‍💻 المساهمة

لتحسين النظام:
1. افتح Issue لمناقشة التغييرات المقترحة
2. Fork المشروع
3. أنشئ Branch جديد
4. قم بالتعديلات
5. افتح Pull Request

## 📄 الترخيص

هذا النظام جزء من تطبيق Marina Hotel Mobile ويخضع لنفس ترخيص المشروع.

---

**تم التطوير بواسطة:** فريق Marina Hotel Development Team  
**التاريخ:** نوفمبر 2025  
**الإصدار:** 1.0.0
