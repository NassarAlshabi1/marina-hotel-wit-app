# 🚀 مرجع سريع - مزامنة Ditto

## جدول البيانات المزامنة

| # | Collection | الاسم العربي | عدد الحقول الرئيسية | الاستخدام الرئيسي |
|---|------------|--------------|---------------------|-------------------|
| 1️⃣ | `rooms` | الغرف | 5 | إدارة غرف الفندق وحالتها |
| 2️⃣ | `bookings` | الحجوزات | 20+ | تسجيل وإدارة حجوزات النزلاء |
| 3️⃣ | `booking_notes` | ملاحظات الحجز | 5 | إضافة ملاحظات على الحجوزات |
| 4️⃣ | `employees` | الموظفون | 8 | إدارة بيانات الموظفين |
| 5️⃣ | `expenses` | المصروفات | 8 | تتبع مصروفات الفندق |
| 6️⃣ | `cash_transactions` | المعاملات النقدية | 9 | إدارة حركة الخزنة |
| 7️⃣ | `payments` | الدفعات | 7 | تسجيل دفعات النزلاء |
| 8️⃣ | `debts` | الديون | 9 | تتبع الذمم المستحقة |
| 9️⃣ | `shift_notes` | ملاحظات الوردية | 6 | تواصل بين الورديات |

---

## الحقول المشتركة في كل مستند

```
✓ _id              - المعرف الفريد
✓ server_id        - معرف السيرفر (اختياري)
✓ created_at       - تاريخ الإنشاء
✓ updated_at       - تاريخ آخر تحديث
✓ deleted_at       - تاريخ الحذف (soft delete)
✓ last_modified    - آخر تعديل
✓ version          - رقم الإصدار
✓ origin           - المصدر (local/server)
```

---

## أوامر المزامنة السريعة

```dart
// تهيئة الخدمة
await DittoLocalSyncService().initialize(database);

// بدء المزامنة الفورية
await DittoLocalSyncService().startSync();

// إيقاف المزامنة
await DittoLocalSyncService().stopSync();

// رفع البيانات المحلية
final pushSummary = await DittoLocalSyncService().pushLocalData();

// سحب البيانات البعيدة
final pullSummary = await DittoLocalSyncService().pullRemoteData();

// مزامنة كاملة (Push + Pull)
await DittoLocalSyncService().fullSync();

// إحصائيات المزامنة
final stats = await DittoLocalSyncService().getSyncStats();
```

---

## DQL Queries المستخدمة

### Push (رفع البيانات)
```sql
INSERT INTO {collection} DOCUMENTS (:doc) ON ID CONFLICT DO UPDATE
```

### Pull (سحب البيانات)
```sql
SELECT * FROM {collection} WHERE !DELETED
```

### Subscription (الاشتراك)
```sql
SELECT * FROM COLLECTION {collection}
```

---

## مثال عملي كامل

```dart
// 1. تهيئة Ditto
final dittoService = DittoLocalSyncService();
final initialized = await dittoService.initialize(database);

if (!initialized) {
  print('فشل تهيئة Ditto');
  return;
}

// 2. بدء المزامنة الفورية
await dittoService.startSync();
print('🛰️ بدأت المزامنة الفورية');

// 3. مزامنة كاملة أولية
final success = await dittoService.fullSync();
if (success) {
  print('✅ اكتملت المزامنة بنجاح');
  
  // 4. عرض الإحصائيات
  final stats = await dittoService.getSyncStats();
  print('📊 الإحصائيات:');
  print('- الغرف: ${stats['rooms_in_local']}');
  print('- الحجوزات: ${stats['bookings_in_local']}');
  print('- الموظفون: ${stats['employees_in_local']}');
  print('- آخر مزامنة: ${stats['last_sync']}');
} else {
  print('❌ فشلت المزامنة');
  print('الخطأ: ${dittoService.lastError}');
}

// 5. عند الخروج من التطبيق
await dittoService.dispose();
```

---

## حالات الاستخدام الشائعة

### ✅ مزامنة تلقائية عند فتح التطبيق
```dart
await DittoLocalSyncService().maybeAutoSync(database);
```

### ✅ مزامنة يدوية من زر في الواجهة
```dart
onPressed: () async {
  showLoadingDialog();
  final success = await DittoLocalSyncService().fullSync();
  hideLoadingDialog();
  
  if (success) {
    showSuccessSnackbar('تمت المزامنة بنجاح');
  } else {
    showErrorSnackbar('فشلت المزامنة');
  }
}
```

### ✅ مزامنة فورية لكل التغييرات
```dart
// عند بدء التطبيق
await DittoLocalSyncService().startSync();

// الآن كل التغييرات تتزامن فوراً! 🚀
```

---

## إعدادات Ditto (env.dart)

```dart
static String dittoAppId = '1507d904-d3ed-4ac3-824c-249c18170eee';
static String dittoPlaygroundToken = 'dbae5191-2cb5-4fb5-8aca-9f9d85e0409a';
static String dittoApiToken = 'Vc4wt9ruMMtlf9zS1wh8RSoqT8HN9aB8CYfeDY95KC4kKSEtkfmgHOupZBkO';
static String dittoCloudWebhook = 'https://i83inp.cloud.dittolive.app/1507d904-d3ed-4ac3-824c-249c18170eee';
static bool dittoUsePlayground = true;
```

---

## نصائح للأداء الأمثل

| النصيحة | الفائدة |
|---------|---------|
| 🔹 استخدم `includeDeleted: false` | يسرع عملية المزامنة |
| 🔹 فعّل Auto Sync فقط عند الحاجة | يوفر استهلاك البيانات |
| 🔹 استخدم Soft Delete | يحافظ على سلامة المزامنة |
| 🔹 راجع `last_error` عند الفشل | يساعد في حل المشاكل |
| 🔹 نفذ Full Sync دورياً | يضمن تطابق البيانات |

---

## استكشاف الأخطاء الشائعة

| الخطأ | السبب | الحل |
|-------|-------|------|
| `DittoLocalSyncService غير مهيأ` | لم يتم استدعاء initialize() | استدعِ initialize() أولاً |
| `فشل طلب المصادقة` | خطأ في tokens | تحقق من env.dart |
| `Network error` | لا يوجد إنترنت | تحقق من الاتصال |
| `Version conflict` | تعارض في الإصدارات | سيتم الحل تلقائياً |

---

## الملفات ذات الصلة

```
mobile/
├── lib/
│   ├── services/
│   │   ├── ditto_local_sync_service.dart    ← الخدمة الرئيسية
│   │   ├── ditto_schema_mapper.dart         ← تحويل البيانات
│   │   └── daos/                            ← Data Access Objects
│   │       ├── rooms_dao.dart
│   │       ├── bookings_dao.dart
│   │       ├── employees_dao.dart
│   │       ├── expenses_dao.dart
│   │       ├── cash_transactions_dao.dart
│   │       ├── payments_dao.dart
│   │       ├── debts_dao.dart
│   │       └── shift_notes_dao.dart
│   └── utils/
│       ├── ditto_config.dart                ← إعدادات Ditto
│       └── env.dart                         ← متغيرات البيئة
├── pubspec.yaml                             ← ditto_live: 4.10.2
└── DITTO_SYNC_DATA_DOCUMENTATION.md         ← التوثيق الكامل
```

---

**للتوثيق الكامل، راجع:** [DITTO_SYNC_DATA_DOCUMENTATION.md](DITTO_SYNC_DATA_DOCUMENTATION.md)
