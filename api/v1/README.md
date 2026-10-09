# PHP/MySQL REST API للتزامن مع Flutter

هذا المجلد يحتوي على REST API كاملة لربط تطبيق Flutter مع قاعدة بيانات MySQL.

## 🏗️ هيكل API

```
api/v1/
├── config.php              # الإعدادات الأساسية والوظائف المشتركة
├── auth/
│   ├── login.php          # تسجيل الدخول والحصول على توكن
│   └── ping.php           # اختبار الاتصال والمصادقة
├── sync/
│   ├── push.php           # رفع التغييرات من Flutter إلى MySQL
│   └── pull.php           # جلب التغييرات من MySQL إلى Flutter
└── entities/
    ├── rooms.php          # إدارة الغرف (CRUD)
    ├── bookings.php       # إدارة الحجوزات (CRUD)
    └── ... (10 جداول)
```

## 📋 الجداول المدعومة

1. **Rooms** - الغرف
2. **Bookings** - الحجوزات
3. **BookingNotes** - ملاحظات الحجوزات
4. **Employees** - الموظفين
5. **Expenses** - المصروفات
6. **ExpenseCategories** - فئات المصروفات
7. **CashTransactions** - معاملات الخزينة
8. **Payments** - المدفوعات
9. **ShiftNotes** - ملاحظات الورديات
10. **DailyClosures** - الإغلاقات اليومية

## 🚀 التشغيل

### 1. تثبيت قاعدة البيانات

قم بتشغيل ملفات Migration بالترتيب:

```bash
# في phpMyAdmin أو MySQL CLI
source sql/migrations/001_add_sync_tables.sql
source sql/migrations/002_add_sync_fields.sql
source sql/migrations/003_add_new_fields.sql
```

أو استخدم الأمر المباشر:

```sql
USE hotel_db;
SOURCE /path/to/marina-hotel-wit-app/sql/migrations/001_add_sync_tables.sql;
SOURCE /path/to/marina-hotel-wit-app/sql/migrations/002_add_sync_fields.sql;
SOURCE /path/to/marina-hotel-wit-app/sql/migrations/003_add_new_fields.sql;
```

### 2. تكوين الاتصال

تأكد من إعدادات قاعدة البيانات في `includes/config.php`:

```php
define('DB_HOST', 'localhost');
define('DB_USER', 'root');
define('DB_PASS', '');
define('DB_NAME', 'hotel_db');
```

### 3. إعداد Flutter

قم بتحديث `mobile/lib/utils/env.dart`:

```dart
// للمحاكي Android
static String baseApiUrl = 'http://10.0.2.2/marina-hotel-wit-app/api/v1';

// للجهاز الحقيقي (استخدم IP جهازك)
static String baseApiUrl = 'http://192.168.1.5/marina-hotel-wit-app/api/v1';
```

## 🔑 المصادقة

### تسجيل الدخول

```bash
POST /api/v1/auth/login.php
Content-Type: application/json

{
  "username": "admin",
  "password": "your_password"
}
```

**الاستجابة:**

```json
{
  "success": true,
  "data": {
    "token": "abc123...",
    "user": {
      "id": 1,
      "username": "admin",
      "full_name": "مدير النظام",
      "role": "admin"
    }
  },
  "server_time": 1738569600
}
```

### استخدام التوكن

أرسل التوكن في جميع الطلبات:

```
Authorization: Bearer abc123...
```

## 🔄 التزامن

### Pull (جلب التغييرات)

```bash
GET /api/v1/sync/pull.php?since=1738569600
Authorization: Bearer abc123...
```

**الاستجابة:**

```json
{
  "success": true,
  "data": {
    "records": {
      "rooms": [...],
      "bookings": [...],
      ...
    },
    "deleted": {
      "rooms": [
        {"localUuid": "xxx", "deletedAt": 1738569700}
      ]
    },
    "syncTimestamp": 1738569800
  }
}
```

### Push (رفع التغييرات)

```bash
POST /api/v1/sync/push.php
Authorization: Bearer abc123...
Content-Type: application/json

{
  "changes": [
    {
      "entity": "rooms",
      "action": "create",
      "local_uuid": "abc-123",
      "data": {
        "roomNumber": "101",
        "roomType": "standard",
        "price": 100.0,
        "status": "شاغرة",
        "cleaningStatus": "clean"
      }
    }
  ]
}
```

## 🔄 تحويل أسماء الحقول

API يقوم بالتحويل التلقائي بين:
- **Flutter (camelCase)**: `roomNumber`, `guestName`, `paymentStatus`
- **MySQL (snake_case)**: `room_number`, `guest_name`, `payment_status`

### مثال للتحويل:

| Flutter | MySQL |
|---------|-------|
| `roomNumber` | `room_number` |
| `guestIdNumber` | `guest_id_number` |
| `paymentDateTimestamp` | `payment_date` |
| `isActive` | `is_active` |

## 📝 أمثلة الاستخدام

### إنشاء حجز جديد

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
      'guestNationality': 'يمني',
      'checkinDate': '2024-02-01',
      'status': 'محجوزة',
      'expectedNights': 3,
    }
  }
]);
```

### تحديث حالة غرفة

```dart
await ApiService.I.syncPush([
  {
    'entity': 'rooms',
    'action': 'update',
    'local_uuid': 'room-uuid-here',
    'data': {
      'status': 'محجوزة',
      'cleaningStatus': 'needs_cleaning'
    }
  }
]);
```

## 🧪 اختبار API

يمكنك اختبار API باستخدام curl أو Postman:

```bash
# تسجيل الدخول
curl -X POST http://localhost/marina-hotel-wit-app/api/v1/auth/login.php \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"password"}'

# Pull
curl -X GET "http://localhost/marina-hotel-wit-app/api/v1/sync/pull.php?since=0" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Push
curl -X POST http://localhost/marina-hotel-wit-app/api/v1/sync/push.php \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "changes": [
      {
        "entity": "rooms",
        "action": "create",
        "local_uuid": "test-123",
        "data": {"roomNumber": "999", "roomType": "test", "price": 100, "status": "شاغرة"}
      }
    ]
  }'
```

## 📊 معالجة الأخطاء

جميع الاستجابات تتبع هذا الشكل:

```json
{
  "success": true|false,
  "data": {...},
  "error": "رسالة الخطأ إن وجدت",
  "server_time": 1738569600,
  "timestamp": "2024-02-03 12:00:00"
}
```

### أكواد HTTP:

- `200` - نجاح
- `201` - تم الإنشاء
- `400` - خطأ في البيانات
- `401` - غير مصرح
- `404` - غير موجود
- `405` - طريقة غير مدعومة
- `409` - تعارض (مثل: رقم غرفة مكرر)
- `500` - خطأ في السيرفر

## 🔒 الأمان

- ✅ المصادقة بـ Bearer Token
- ✅ تنظيف المدخلات (sanitization)
- ✅ Prepared Statements لمنع SQL Injection
- ✅ CORS headers للسماح بطلبات من Flutter
- ✅ تسجيل الأخطاء في `logs/api_errors_*.log`

## 🐛 استكشاف الأخطاء

### الخطأ: "غير مصرح - التوكن مطلوب"

تأكد من إرسال header:
```
Authorization: Bearer YOUR_TOKEN
```

### الخطأ: "Connection refused"

- تأكد من تشغيل XAMPP/WAMP
- تحقق من صحة الـ URL في `env.dart`
- للمحاكي Android استخدم `10.0.2.2` بدلاً من `localhost`

### الخطأ: "فشل الاتصال بقاعدة البيانات"

- تحقق من إعدادات `includes/config.php`
- تأكد من تشغيل MySQL
- تحقق من اسم قاعدة البيانات

## 📚 مصادر إضافية

- [Flutter Dio Documentation](https://pub.dev/packages/dio)
- [PHP MySQLi](https://www.php.net/manual/en/book.mysqli.php)
- [REST API Best Practices](https://restfulapi.net/)

## 🤝 المساهمة

هذا API تم تطويره خصيصاً لمشروع Marina Hotel.

## 📄 الترخيص

جميع الحقوق محفوظة © 2024 Marina Hotel
