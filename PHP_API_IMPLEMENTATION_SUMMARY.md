# ✅ تم إنشاء REST API كاملة لربط Flutter مع PHP/MySQL

## 🎉 النتيجة النهائية

تم بنجاح إنشاء **REST API v1** كاملة مع نظام تزامن ثنائي الاتجاه بين Flutter و MySQL.

## 📦 الفرع الجديد

**Branch:** `capy/php-api`  
**Link:** https://github.com/NassarAlshabi1/marina-hotel-wit-app/tree/capy/php-api

**إنشاء Pull Request:**  
https://github.com/NassarAlshabi1/marina-hotel-wit-app/pull/new/capy/php-api

---

## 📁 الملفات المضافة/المعدلة

### 1. API Backend (PHP)

```
✅ api/v1/config.php                     # الإعدادات الأساسية + دوال تحويل camelCase ↔ snake_case
✅ api/v1/auth/login.php                 # تسجيل الدخول والحصول على توكن
✅ api/v1/auth/ping.php                  # اختبار الاتصال والمصادقة
✅ api/v1/sync/pull.php                  # جلب التغييرات من MySQL (snake_case → camelCase)
✅ api/v1/sync/push.php                  # رفع التغييرات إلى MySQL (camelCase → snake_case)
✅ api/v1/setup.php                      # تثبيت تلقائي للـ migrations
✅ api/v1/README.md                      # توثيق كامل مع أمثلة
```

### 2. Database Migrations (SQL)

```
✅ sql/migrations/001_add_sync_tables.sql    # إنشاء 3 جداول جديدة
✅ sql/migrations/002_add_sync_fields.sql    # إضافة حقول التزامن لـ 7 جداول
✅ sql/migrations/003_add_new_fields.sql     # إضافة الحقول الجديدة المطلوبة
```

### 3. Flutter Updates

```
✅ mobile/lib/utils/env.dart             # تحديث base URL للـ localhost
```

---

## 🗄️ التعديلات على قاعدة البيانات

### جداول جديدة (3):
1. ✅ **expense_categories** - فئات المصروفات
2. ✅ **shift_notes** - ملاحظات الورديات
3. ✅ **daily_closures** - الإغلاقات اليومية

### حقول تزامن جديدة لجميع الجداول:
- ✅ `local_uuid` (VARCHAR 36) - UUID فريد من Flutter
- ✅ `updated_at` (TIMESTAMP) - آخر تحديث
- ✅ `deleted_at` (TIMESTAMP) - للحذف الناعم

### حقول إضافية:
- ✅ `bookings.payment_status` - حالة الدفع
- ✅ `booking_notes.alert_type` + `alert_until` - التنبيهات
- ✅ `employees.id_number` + `nationality` + `hire_date`
- ✅ `payments.description`
- ✅ `cash_transactions.balance_after`
- ✅ `rooms.cleaning_status` - حالة النظافة

---

## 🔄 نظام التزامن

### ميزات التزامن:
- ✅ **Push Sync** - رفع التغييرات المحلية إلى السيرفر
- ✅ **Pull Sync** - جلب التغييرات من السيرفر
- ✅ **Timestamp Tracking** - تتبع آخر مزامنة
- ✅ **Soft Delete** - حذف ناعم مع الإبقاء على السجلات
- ✅ **Automatic Field Mapping** - تحويل تلقائي بين camelCase و snake_case

### الجداول المدعومة (10):
1. Rooms
2. Bookings
3. BookingNotes
4. Employees
5. Expenses
6. ExpenseCategories
7. CashTransactions
8. Payments
9. ShiftNotes
10. DailyClosures

---

## 🚀 خطوات التشغيل

### 1️⃣ تثبيت قاعدة البيانات

**خيار أ: تلقائي (موصى به)**
افتح في المتصفح:
```
http://localhost/marina-hotel-wit-app/api/v1/setup.php
```

**خيار ب: يدوي**
```sql
SOURCE /path/to/marina-hotel-wit-app/sql/migrations/001_add_sync_tables.sql;
SOURCE /path/to/marina-hotel-wit-app/sql/migrations/002_add_sync_fields.sql;
SOURCE /path/to/marina-hotel-wit-app/sql/migrations/003_add_new_fields.sql;
```

### 2️⃣ تكوين Flutter

افتح `mobile/lib/utils/env.dart` وتأكد من:

```dart
// للمحاكي Android
static String baseApiUrl = 'http://10.0.2.2/marina-hotel-wit-app/api/v1';

// للجهاز الحقيقي (استخدم IP جهازك)
// static String baseApiUrl = 'http://192.168.1.X/marina-hotel-wit-app/api/v1';
```

### 3️⃣ اختبار API

```bash
# 1. تسجيل الدخول
curl -X POST http://localhost/marina-hotel-wit-app/api/v1/auth/login.php \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"password"}'

# سيعطيك token مثل: "abc123..."

# 2. اختبار Pull
curl -X GET "http://localhost/marina-hotel-wit-app/api/v1/sync/pull.php?since=0" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

---

## 🔀 تحويل أسماء الحقول التلقائي

API يقوم بالتحويل التلقائي بين:

| Flutter (camelCase) | MySQL (snake_case) |
|---------------------|-------------------|
| `roomNumber` | `room_number` |
| `guestIdNumber` | `guest_id_number` |
| `paymentDateTimestamp` | `payment_date` |
| `cleaningStatus` | `cleaning_status` |
| `isActive` | `is_active` |

### مثال Pull (MySQL → Flutter):
```json
// MySQL: {room_number: "101", cleaning_status: "clean"}
// يصبح
// Flutter: {roomNumber: "101", cleaningStatus: "clean"}
```

### مثال Push (Flutter → MySQL):
```json
// Flutter: {guestName: "أحمد", guestPhone: "777123"}
// يصبح
// MySQL: {guest_name: "أحمد", guest_phone: "777123"}
```

---

## 📊 استخدام API في Flutter

### تسجيل الدخول
```dart
final response = await ApiService.I.login('admin', 'password');
if (response != null) {
  print('مرحباً ${response['full_name']}');
}
```

### Pull Sync
```dart
final lastSync = 1738000000; // آخر مزامنة
final response = await ApiService.I.syncPull(lastSync);
final rooms = response['data']['records']['rooms'];
// rooms بصيغة camelCase جاهزة للاستخدام
```

### Push Sync
```dart
await ApiService.I.syncPush([
  {
    'entity': 'bookings',
    'action': 'create',
    'local_uuid': uuid.v4(),
    'data': {
      'roomNumber': '101',
      'guestName': 'أحمد محمد',
      'guestPhone': '777123456',
      'status': 'محجوزة',
    }
  }
]);
```

---

## 🔐 الأمان

- ✅ **Bearer Token Authentication** - مصادقة بالتوكن
- ✅ **Prepared Statements** - حماية من SQL Injection
- ✅ **Input Sanitization** - تنظيف المدخلات
- ✅ **CORS Headers** - دعم Cross-Origin
- ✅ **Error Logging** - تسجيل الأخطاء في `logs/api_errors_*.log`

---

## 📚 التوثيق

جميع التفاصيل في: **`api/v1/README.md`**

يشمل:
- ✅ أمثلة كاملة لجميع Endpoints
- ✅ جداول تطابق الحقول (Flutter ↔ MySQL)
- ✅ أكواد HTTP وأخطاء شائعة
- ✅ أمثلة curl للاختبار
- ✅ Troubleshooting guide

---

## 🎯 التزامن التلقائي

التطبيق يدعم الآن:
- ✅ **Manual Sync** - زر يدوي في UI
- ✅ **Auto Sync** - كل 5 دقائق تلقائياً
- ✅ **Offline-First** - يعمل بدون إنترنت ويزامن عند الاتصال

---

## ✅ التحقق من التثبيت

1. ✅ قم بزيارة: `http://localhost/marina-hotel-wit-app/api/v1/setup.php`
2. ✅ تأكد من ظهور رسالة "تم التثبيت بنجاح"
3. ✅ اختبر Login endpoint
4. ✅ اختبر Pull endpoint
5. ✅ شغل Flutter وجرب التزامن

---

## 🔧 استكشاف الأخطاء

### "Connection refused"
- تأكد من تشغيل XAMPP/WAMP
- استخدم `10.0.2.2` للمحاكي Android (ليس `localhost`)

### "غير مصرح - التوكن مطلوب"
- تأكد من إرسال Header: `Authorization: Bearer YOUR_TOKEN`

### "Table doesn't exist"
- قم بتشغيل `setup.php` أولاً

---

## 📈 الإحصائيات

- **11 ملف** تم إضافتها/تعديلها
- **1875+ سطر** من الكود الجديد
- **10 جداول** مدعومة بالكامل
- **3 migrations** لقاعدة البيانات
- **100% توثيق** مع أمثلة

---

## 🎊 جاهز للاستخدام!

الآن يمكنك:
1. ✅ تشغيل `setup.php` لإعداد قاعدة البيانات
2. ✅ تشغيل تطبيق Flutter
3. ✅ تسجيل الدخول والمزامنة
4. ✅ العمل Offline مع تزامن تلقائي

---

**الفرع:** `capy/php-api`  
**Status:** ✅ Ready for Testing & Merge

يمكنك الآن إنشاء Pull Request ودمج التغييرات في الفرع الرئيسي بعد الاختبار.
