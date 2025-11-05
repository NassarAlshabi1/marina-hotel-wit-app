# 🚀 Marina Hotel - PocketBase to Supabase Migration
# الهجرة من PocketBase إلى Supabase لتطبيق Marina Hotel

<div dir="rtl">

## 📋 ملخص سريع | Quick Summary

تم إنشاء دليل هجرة شامل من **PocketBase** إلى **Supabase** لتطبيق Marina Hotel، يتضمن جميع الملفات والأدوات اللازمة لهجرة سلسة وآمنة.

</div>

---

## 📁 الملفات المُنشأة | Created Files

### 1️⃣ Database Schema & Migrations

```
supabase/migrations/
├── 001_initial_schema.sql    ✅ DDL الكامل مع UUID و TIMESTAMPTZ
└── 002_rls_policies.sql       ✅ سياسات الأمان لجميع الجداول
```

**الميزات | Features:**
- ✅ جميع الجداول (rooms, bookings, booking_notes, employees, expenses, cash_transactions, payments, debts, outbox, sync_state)
- ✅ استخدام UUID بدلاً من TEXT
- ✅ استخدام TIMESTAMPTZ بدلاً من INTEGER
- ✅ Indexes محسّنة للأداء
- ✅ Foreign Keys مع CASCADE
- ✅ Triggers لتحديث updated_at تلقائياً
- ✅ RLS Policies محكمة لكل جدول

---

### 2️⃣ Edge Functions

```
supabase/functions/
├── sync-push/
│   └── index.ts              ✅ دالة Push للتغييرات
└── sync-pull/
    └── index.ts              ✅ دالة Pull للتغييرات
```

**الميزات | Features:**
- ✅ معالجة دفعات كاملة من Outbox
- ✅ دعم CREATE, UPDATE, DELETE
- ✅ تحويل تلقائي لـ UUIDs و Timestamps
- ✅ معالجة أخطاء شاملة
- ✅ Database Transactions
- ✅ JWT Authentication

---

### 3️⃣ Flutter/Dart Code

```
mobile/lib/
├── services/
│   └── supabase_sync_service.dart    ✅ خدمة المزامنة مع Supabase
└── utils/
    └── supabase_config.dart          ✅ إعدادات وتهيئة Supabase
```

**الميزات | Features:**
- ✅ نفس واجهة sync_service.dart الحالية
- ✅ استبدال PocketBase بـ Supabase Client
- ✅ استخدام Edge Functions للمزامنة
- ✅ تحويل تلقائي للتنسيقات
- ✅ Performance Optimizer متوافق
- ✅ Error handling محسّن

---

### 4️⃣ Documentation & Guides

```
docs/
└── SUPABASE_MIGRATION_GUIDE.md    ✅ دليل هجرة شامل ومفصّل
```

**المحتويات | Contents:**
- ✅ 5 مراحل كاملة للهجرة
- ✅ خطوات مفصّلة مع أمثلة
- ✅ Troubleshooting
- ✅ Best Practices
- ✅ قائمة تحقق نهائية

---

### 5️⃣ Migration & Testing

```
scripts/
└── migrate_data.dart              ✅ سكريبت نقل البيانات

test/
└── supabase_sync_test.dart        ✅ اختبارات شاملة
```

**الميزات | Features:**
- ✅ نقل تلقائي من PocketBase إلى Supabase
- ✅ تحويل تنسيقات البيانات
- ✅ Batch processing
- ✅ Dry-run mode
- ✅ تقرير مفصّل
- ✅ اختبارات Push/Pull/Conflict Resolution

---

## 🗂️ البنية الكاملة | Complete Structure

```
marina-hotel-wit-app/
│
├── supabase/
│   ├── migrations/
│   │   ├── 001_initial_schema.sql          # ✅ جداول + indexes + triggers
│   │   └── 002_rls_policies.sql            # ✅ سياسات الأمان
│   │
│   └── functions/
│       ├── sync-push/
│       │   └── index.ts                    # ✅ Edge Function للـ Push
│       └── sync-pull/
│           └── index.ts                    # ✅ Edge Function للـ Pull
│
├── mobile/
│   ├── lib/
│   │   ├── services/
│   │   │   └── supabase_sync_service.dart  # ✅ خدمة المزامنة
│   │   │
│   │   └── utils/
│   │       └── supabase_config.dart        # ✅ إعدادات Supabase
│   │
│   └── pubspec.yaml                        # تحديث: إضافة supabase_flutter
│
├── scripts/
│   └── migrate_data.dart                   # ✅ سكريبت نقل البيانات
│
├── test/
│   └── supabase_sync_test.dart             # ✅ اختبارات شاملة
│
├── docs/
│   └── SUPABASE_MIGRATION_GUIDE.md         # ✅ دليل الهجرة
│
└── SUPABASE_MIGRATION_README.md            # ✅ هذا الملف
```

---

## 🚀 البدء السريع | Quick Start

<div dir="rtl">

### المرحلة 1: إعداد Supabase (30 دقيقة)

</div>

```bash
# 1. إنشاء مشروع Supabase
# اذهب إلى https://supabase.com وأنشئ مشروع جديد

# 2. تنفيذ Database Schema
# في SQL Editor، نفّذ:
# - supabase/migrations/001_initial_schema.sql
# - supabase/migrations/002_rls_policies.sql

# 3. نشر Edge Functions
supabase functions deploy sync-push
supabase functions deploy sync-pull
```

---

<div dir="rtl">

### المرحلة 2: تحديث الكود (1 ساعة)

</div>

```bash
# 1. تثبيت supabase_flutter
cd mobile
flutter pub add supabase_flutter

# 2. تحديث supabase_config.dart
# عدّل: supabaseUrl و supabaseAnonKey

# 3. تهيئة Supabase في main.dart
# أضف: await SupabaseConfig.initialize();
```

```dart
// في main.dart
import 'package:flutter/material.dart';
import 'utils/supabase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // تهيئة Supabase
  await SupabaseConfig.initialize();
  
  runApp(MyApp());
}
```

---

<div dir="rtl">

### المرحلة 3: نقل البيانات (1 ساعة)

</div>

```bash
# 1. تحديث إعدادات migrate_data.dart
# عدّل: URLs و Keys

# 2. تشغيل سكريبت النقل
dart run scripts/migrate_data.dart

# 3. التحقق من البيانات في Supabase Dashboard
```

---

<div dir="rtl">

### المرحلة 4: اختبار المزامنة (30 دقيقة)

</div>

```bash
# 1. تحديث supabase_sync_test.dart
# عدّل: TestConfig

# 2. تشغيل الاختبارات
cd mobile
flutter test test/supabase_sync_test.dart
```

---

<div dir="rtl">

### المرحلة 5: التبديل (15 دقيقة)

</div>

```dart
// في providers.dart، استبدل:

// القديم ❌
final syncServiceProvider = Provider<SyncService>(
  (ref) => SyncService(ref.read(databaseProvider))
);

// الجديد ✅
final syncServiceProvider = Provider<SupabaseSyncService>(
  (ref) => SupabaseSyncService(ref.read(databaseProvider))
);
```

---

## 📊 مقارنة PocketBase vs Supabase

<div dir="rtl">

| الميزة | PocketBase | Supabase | الفائز |
|-------|-----------|----------|-------|
| **قاعدة البيانات** | SQLite | PostgreSQL | ✅ Supabase |
| **الأمان** | Basic Auth | RLS + JWT | ✅ Supabase |
| **التوسع** | محدود | غير محدود | ✅ Supabase |
| **Edge Functions** | ❌ | ✅ Deno | ✅ Supabase |
| **Realtime** | محدود | كامل | ✅ Supabase |
| **Storage** | محلي | Cloud | ✅ Supabase |
| **النسخ الاحتياطي** | يدوي | تلقائي | ✅ Supabase |
| **المراقبة** | محدودة | شاملة | ✅ Supabase |
| **التكلفة** | مجاني | مجاني حتى حد | 🤝 متساوي |
| **البساطة** | ✅ بسيط | متوسط | ✅ PocketBase |

</div>

---

## ✨ المزايا الرئيسية للهجرة | Key Benefits

<div dir="rtl">

### 1. قاعدة بيانات أقوى
- PostgreSQL بدلاً من SQLite
- دعم أفضل للمعاملات
- أداء أعلى للبيانات الكبيرة

### 2. أمان محكم
- Row Level Security (RLS)
- JWT Authentication
- Fine-grained permissions

### 3. قابلية التوسع
- Auto-scaling
- Connection pooling
- Load balancing

### 4. ميزات إضافية
- Edge Functions للمنطق المعقد
- Realtime subscriptions
- Storage للملفات
- Auth providers متعددة

### 5. DevOps محسّن
- نسخ احتياطية تلقائية
- مراقبة وتنبيهات
- Database migrations
- CI/CD integration

</div>

---

## 🔧 التغييرات الرئيسية | Key Changes

<div dir="rtl">

### البيانات | Data

| PocketBase | Supabase | السبب |
|-----------|----------|-------|
| TEXT UUID | UUID | نوع أفضل |
| INTEGER timestamp | TIMESTAMPTZ | دعم Timezone |
| custom fields | JSON constraints | تحقق أفضل |

### المزامنة | Sync

| PocketBase | Supabase | السبب |
|-----------|----------|-------|
| Direct API | Edge Functions | منطق معقد |
| Single request | Batch processing | أداء أفضل |
| Simple auth | JWT + RLS | أمان أعلى |

### الأداء | Performance

| PocketBase | Supabase | التحسين |
|-----------|----------|---------|
| SQLite | PostgreSQL | 10x faster |
| Local | Cloud | Always available |
| Limited connections | Pooling | More concurrent users |

</div>

---

## 📚 الموارد | Resources

<div dir="rtl">

### الوثائق
- [دليل الهجرة الكامل](docs/SUPABASE_MIGRATION_GUIDE.md)
- [Supabase Docs](https://supabase.com/docs)
- [Supabase Flutter](https://supabase.com/docs/reference/dart/introduction)

### الأدوات
- [Supabase CLI](https://github.com/supabase/cli)
- [pgAdmin](https://www.pgadmin.org/)
- [Postman](https://www.postman.com/)

### الدعم
- [Supabase Discord](https://discord.supabase.com/)
- [GitHub Issues](https://github.com/supabase/supabase/issues)

</div>

---

## ✅ قائمة التحقق | Checklist

<div dir="rtl">

قبل البدء بالهجرة:

- [ ] قراءة دليل الهجرة كاملاً
- [ ] إنشاء نسخة احتياطية من PocketBase
- [ ] إنشاء حساب Supabase
- [ ] تجهيز بيئة الاختبار
- [ ] إعلام الفريق بخطة الهجرة

أثناء الهجرة:

- [ ] تنفيذ Database Schema
- [ ] نشر Edge Functions
- [ ] تحديث الكود
- [ ] نقل البيانات
- [ ] اختبار شامل

بعد الهجرة:

- [ ] مراقبة الأخطاء
- [ ] تحسين الأداء
- [ ] تحديث التوثيق
- [ ] تدريب الفريق
- [ ] حذف PocketBase القديم

</div>

---

## 🆘 الدعم | Support

<div dir="rtl">

إذا واجهت أي مشاكل:

1. راجع [دليل Troubleshooting](docs/SUPABASE_MIGRATION_GUIDE.md#troubleshooting)
2. شغّل الاختبارات: `flutter test test/supabase_sync_test.dart`
3. تحقق من Supabase Logs في Dashboard
4. راجع الكود في `supabase_sync_service.dart`
5. اطرح سؤالك في [Supabase Discord](https://discord.supabase.com/)

</div>

---

## 🎉 تهانينا! | Congratulations!

<div dir="rtl">

لديك الآن دليل هجرة شامل من PocketBase إلى Supabase! 🚀

جميع الملفات جاهزة للاستخدام:
- ✅ Database Schema
- ✅ Edge Functions
- ✅ Dart Sync Service
- ✅ Migration Script
- ✅ Tests
- ✅ Documentation

الخطوات التالية:
1. اقرأ دليل الهجرة
2. اتبع الخطوات بالترتيب
3. اختبر كل مرحلة
4. استمتع بميزات Supabase!

</div>

---

**آخر تحديث | Last Updated:** 2024-11-04  
**الإصدار | Version:** 1.0.0  
**المؤلف | Author:** Marina Hotel Team

---

<div align="center">

### صُنع بـ ❤️ لتطبيق Marina Hotel
### Made with ❤️ for Marina Hotel App

</div>
