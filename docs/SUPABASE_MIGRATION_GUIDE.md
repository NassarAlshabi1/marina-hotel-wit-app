# دليل الهجرة من PocketBase إلى Supabase
# Migration Guide from PocketBase to Supabase

## 📋 نظرة عامة | Overview

هذا الدليل يشرح بالتفصيل كيفية الهجرة من PocketBase إلى Supabase لتطبيق Marina Hotel.  
This guide explains in detail how to migrate from PocketBase to Supabase for the Marina Hotel app.

### لماذا Supabase؟ | Why Supabase?

- ✅ قاعدة بيانات PostgreSQL قوية وموثوقة | Powerful and reliable PostgreSQL database
- ✅ أمان محكم مع RLS (Row Level Security) | Strong security with RLS
- ✅ Edge Functions للمنطق من جانب السيرفر | Edge Functions for server-side logic
- ✅ مجاني حتى حد معقول | Free up to a reasonable limit
- ✅ قابل للتوسع | Scalable
- ✅ Realtime (اختياري) | Realtime (optional)

---

## 📦 المتطلبات الأساسية | Prerequisites

- حساب Supabase | Supabase account
- Flutter SDK
- Dart SDK
- مشروع PocketBase حالي | Existing PocketBase project

---

## 🗺️ خريطة الطريق | Roadmap

```
المرحلة 1: الإعداد (يوم واحد)
Stage 1: Setup (1 day)
    ├── إنشاء مشروع Supabase
    ├── تنفيذ DDL Scripts
    ├── تفعيل RLS
    └── نشر Edge Functions

المرحلة 2: تحديث الكود (2-3 أيام)
Stage 2: Code Update (2-3 days)
    ├── تثبيت supabase_flutter package
    ├── إنشاء supabase_sync_service.dart
    ├── تحديث الـ providers
    └── اختبار المزامنة

المرحلة 3: نقل البيانات (يوم واحد)
Stage 3: Data Migration (1 day)
    ├── استخراج البيانات من PocketBase
    ├── تحويل التنسيقات
    ├── رفع البيانات إلى Supabase
    └── التحقق من صحة البيانات

المرحلة 4: التبديل (نصف يوم)
Stage 4: Switch (half day)
    ├── اختبار شامل
    ├── التبديل من PocketBase إلى Supabase
    └── مراقبة الأخطاء

المرحلة 5: التحسين (مستمرة)
Stage 5: Optimization (ongoing)
    ├── إضافة indexes إضافية
    ├── تحسين أداء الاستعلامات
    └── إعداد النسخ الاحتياطية
```

---

## 🚀 المرحلة 1: الإعداد | Setup

### 1.1 إنشاء مشروع Supabase

1. اذهب إلى [supabase.com](https://supabase.com)
2. سجّل الدخول أو أنشئ حساباً جديداً
3. انقر على "New Project"
4. املأ المعلومات:
   - **Project Name**: marina-hotel
   - **Database Password**: (كلمة مرور قوية)
   - **Region**: اختر أقرب منطقة (Middle East إن وُجد)
   - **Pricing Plan**: Free (للبداية)
5. انقر على "Create new project"
6. انتظر حتى يكتمل الإعداد (1-2 دقيقة)

### 1.2 الحصول على معلومات الاتصال

1. اذهب إلى **Project Settings** > **API**
2. احفظ المعلومات التالية:
   - **Project URL**: `https://xxxxxxxxxxx.supabase.co`
   - **anon public key**: المفتاح العام (للاستخدام في التطبيق)
   - **service_role key**: مفتاح الخادم (للاستخدام في Edge Functions فقط)

⚠️ **تحذير**: لا تشارك `service_role key` في الكود العام!

### 1.3 تنفيذ DDL Scripts

#### الطريقة 1: عبر SQL Editor (موصى بها)

1. اذهب إلى **SQL Editor** في لوحة تحكم Supabase
2. انقر على "New query"
3. انسخ محتويات `supabase/migrations/001_initial_schema.sql`
4. الصق في المحرر واضغط "Run"
5. انتظر حتى تظهر رسالة "Success ✓"
6. كرر نفس العملية لـ `supabase/migrations/002_rls_policies.sql`

#### الطريقة 2: عبر Supabase CLI

```bash
# تثبيت Supabase CLI
npm install -g supabase

# تسجيل الدخول
supabase login

# ربط المشروع
supabase link --project-ref YOUR_PROJECT_ID

# تنفيذ Migrations
supabase db push
```

### 1.4 التحقق من الجداول

1. اذهب إلى **Table Editor**
2. تحقق من وجود الجداول التالية:
   - ✓ rooms
   - ✓ bookings
   - ✓ booking_notes
   - ✓ employees
   - ✓ expenses
   - ✓ cash_transactions
   - ✓ payments
   - ✓ debts
   - ✓ outbox
   - ✓ sync_state

### 1.5 نشر Edge Functions

#### تثبيت Deno (مطلوب لـ Edge Functions)

```bash
# macOS/Linux
curl -fsSL https://deno.land/x/install/install.sh | sh

# Windows
irm https://deno.land/install.ps1 | iex
```

#### نشر Functions

```bash
# الانتقال إلى مجلد المشروع
cd /path/to/marina-hotel-wit-app

# نشر sync-push function
supabase functions deploy sync-push --project-ref YOUR_PROJECT_ID

# نشر sync-pull function
supabase functions deploy sync-pull --project-ref YOUR_PROJECT_ID
```

#### التحقق من Functions

```bash
# اختبار sync-push
curl -X POST \
  'https://YOUR_PROJECT_ID.supabase.co/functions/v1/sync-push' \
  -H 'Authorization: Bearer YOUR_ANON_KEY' \
  -H 'Content-Type: application/json' \
  -d '{"changes": []}'

# يجب أن ترى: {"success":true,"data":{"results":[]}}
```

---

## 🔧 المرحلة 2: تحديث الكود | Code Update

### 2.1 تثبيت supabase_flutter package

في ملف `mobile/pubspec.yaml`، أضف:

```yaml
dependencies:
  supabase_flutter: ^2.0.0
```

ثم نفذ:

```bash
cd mobile
flutter pub get
```

### 2.2 تحديث supabase_config.dart

افتح `mobile/lib/utils/supabase_config.dart` وحدّث:

```dart
class SupabaseConfig {
  static const String supabaseUrl = 'https://YOUR_PROJECT_ID.supabase.co';
  static const String supabaseAnonKey = 'YOUR_ANON_KEY';
  // ...
}
```

### 2.3 تهيئة Supabase في main.dart

```dart
import 'package:flutter/material.dart';
import 'utils/supabase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // تهيئة Supabase
  await SupabaseConfig.initialize();
  
  runApp(MyApp());
}
```

### 2.4 إنشاء مستخدم للاختبار

في **Authentication** > **Users** في لوحة تحكم Supabase:

1. انقر على "Add user" > "Create new user"
2. املأ:
   - Email: test@marina-hotel.com
   - Password: (كلمة مرور قوية)
3. انقر "Create user"

### 2.5 تسجيل الدخول في التطبيق

```dart
// في شاشة تسجيل الدخول
await SupabaseConfig.signInWithEmail(
  email: 'test@marina-hotel.com',
  password: 'your_password',
);
```

### 2.6 استبدال SyncService بـ SupabaseSyncService

في ملف `providers.dart`، استبدل:

```dart
// القديم - Old
final syncServiceProvider = Provider<SyncService>(
  (ref) => SyncService(ref.read(databaseProvider))
);

// الجديد - New
final syncServiceProvider = Provider<SupabaseSyncService>(
  (ref) => SupabaseSyncService(ref.read(databaseProvider))
);
```

### 2.7 اختبار المزامنة الأولى

```dart
// في أي مكان في التطبيق
final syncService = ref.read(supabaseSyncServiceProvider);
await syncService.runSync();

// إذا لم تحدث أخطاء، فالمزامنة تعمل! ✅
```

---

## 📊 المرحلة 3: نقل البيانات | Data Migration

### 3.1 استخدام سكريبت migrate_data.dart

```bash
# تأكد من تحديث المتغيرات في scripts/migrate_data.dart
# Make sure to update variables in scripts/migrate_data.dart

cd marina-hotel-wit-app
dart run scripts/migrate_data.dart
```

### 3.2 المتابعة اليدوية (اختياري)

إذا كنت تفضل نقل البيانات يدوياً:

#### خطوة 1: تصدير من PocketBase

```bash
# استخدم PocketBase Admin UI
# Export collections as JSON
```

#### خطوة 2: تحويل البيانات

استخدم سكريبت Python/Dart لتحويل:
- TEXT UUID → UUID
- INTEGER timestamps → TIMESTAMPTZ
- Foreign keys

#### خطوة 3: استيراد إلى Supabase

```sql
-- مثال على استيراد الغرف
INSERT INTO rooms (room_number, type, price, status, local_uuid)
VALUES 
  ('101', 'مفردة', 100.00, 'شاغرة', '123e4567-e89b-12d3-a456-426614174000'),
  ('102', 'مزدوجة', 150.00, 'شاغرة', '223e4567-e89b-12d3-a456-426614174001');
```

### 3.3 التحقق من البيانات

```sql
-- التحقق من عدد السجلات
SELECT 'rooms' as table_name, COUNT(*) as count FROM rooms WHERE deleted_at IS NULL
UNION ALL
SELECT 'bookings', COUNT(*) FROM bookings WHERE deleted_at IS NULL
UNION ALL
SELECT 'employees', COUNT(*) FROM employees WHERE deleted_at IS NULL;
```

---

## 🔄 المرحلة 4: التبديل | Switch

### 4.1 اختبار شامل قبل التبديل

قائمة الاختبار:

- [ ] إنشاء غرفة جديدة ✓
- [ ] تحديث غرفة موجودة ✓
- [ ] حذف غرفة ✓
- [ ] إنشاء حجز جديد ✓
- [ ] تحديث حجز موجود ✓
- [ ] إضافة دفعة ✓
- [ ] إضافة موظف ✓
- [ ] إضافة مصروف ✓
- [ ] Push changes (التحقق من Outbox) ✓
- [ ] Pull changes (التحقق من التحديثات) ✓
- [ ] Conflict resolution ✓

### 4.2 خطة التبديل

```dart
// 1. إيقاف PocketBase sync
// final syncService = ref.read(syncServiceProvider); // PocketBase
// await syncService.runSync();

// 2. بدء Supabase sync
final supabaseSync = ref.read(supabaseSyncServiceProvider);
await supabaseSync.runSync();

// 3. حذف/تعليق كود PocketBase القديم
// Remove/comment old PocketBase code
```

### 4.3 مراقبة الأخطاء

راقب الأخطاء في:
- Console logs
- Supabase Dashboard > Logs
- Edge Functions logs

### 4.4 Rollback Plan (خطة الرجوع)

إذا حدثت مشاكل:

1. أوقف Supabase sync
2. ارجع إلى PocketBase sync
3. حلل المشكلة
4. أصلح وحاول مرة أخرى

```dart
// للرجوع السريع
// Quick rollback
final pbSync = ref.read(pocketbaseSyncServiceProvider); // القديم
await pbSync.runSync();
```

---

## ⚡ المرحلة 5: التحسين | Optimization

### 5.1 إضافة Indexes إضافية

```sql
-- Indexes للاستعلامات المتكررة
-- Indexes for frequent queries

-- بحث الحجوزات حسب التاريخ
CREATE INDEX IF NOT EXISTS idx_bookings_dates 
ON bookings(checkin_date, checkout_date) 
WHERE deleted_at IS NULL;

-- بحث الدفعات حسب التاريخ
CREATE INDEX IF NOT EXISTS idx_payments_date_method 
ON payments(payment_date, payment_method) 
WHERE deleted_at IS NULL;

-- بحث المصروفات حسب النوع والتاريخ
CREATE INDEX IF NOT EXISTS idx_expenses_type_date 
ON expenses(expense_type, date) 
WHERE deleted_at IS NULL;
```

### 5.2 تحسين RLS Policies

إذا كنت تريد صلاحيات أكثر دقة:

```sql
-- إنشاء جدول للأدوار
CREATE TABLE user_roles (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id),
  role TEXT NOT NULL CHECK (role IN ('admin', 'manager', 'employee')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- تحديث سياسة الموظفين للمدراء فقط
DROP POLICY IF EXISTS "employees_update_policy" ON employees;
CREATE POLICY "employees_update_policy" ON employees
  FOR UPDATE
  USING (
    auth.uid() IN (
      SELECT user_id FROM user_roles WHERE role IN ('admin', 'manager')
    )
  );
```

### 5.3 إعداد النسخ الاحتياطية التلقائية

في Supabase Dashboard:

1. اذهب إلى **Database** > **Backups**
2. فعّل **Automated backups**
3. اختر الجدول الزمني (يومي موصى به)

### 5.4 مراقبة الأداء

استخدم **Supabase Dashboard** > **Reports**:

- Database size
- API requests per second
- Function invocations
- Error rates

### 5.5 إعداد Rate Limiting

```typescript
// في Edge Functions، أضف rate limiting
import { RateLimiter } from 'https://deno.land/x/rate_limiter/mod.ts';

const limiter = new RateLimiter({
  tokensPerInterval: 100,
  interval: 'minute',
});

// في كل function
if (!await limiter.removeTokens(1)) {
  return new Response('Rate limit exceeded', { status: 429 });
}
```

---

## 🔍 استكشاف الأخطاء | Troubleshooting

### مشكلة: "User not authenticated"

**الحل:**

```dart
// تأكد من تسجيل الدخول أولاً
if (!SupabaseConfig.isLoggedIn) {
  await SupabaseConfig.signInWithEmail(
    email: 'your@email.com',
    password: 'your_password',
  );
}
```

### مشكلة: "RLS policy violation"

**الحل:**

تحقق من أن المستخدم مسجل دخول وأن RLS policies صحيحة:

```sql
-- التحقق من RLS
SELECT schemaname, tablename, policyname 
FROM pg_policies 
WHERE schemaname = 'public';
```

### مشكلة: "Function not found"

**الحل:**

تأكد من نشر Edge Functions:

```bash
supabase functions list
supabase functions deploy sync-push
supabase functions deploy sync-pull
```

### مشكلة: "Connection timeout"

**الحل:**

زد المهلة الزمنية في `supabase_sync_service.dart`:

```dart
final response = await _supabase.functions
  .invoke('sync-push', body: {...})
  .timeout(Duration(seconds: 60)); // زيادة إلى 60 ثانية
```

### مشكلة: "UUID format error"

**الحل:**

تأكد من تحويل UUIDs بشكل صحيح:

```dart
// استخدم ensureUUID helper في Edge Functions
const ensureUUID = (uuid: string): string => {
  const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (uuidPattern.test(uuid)) return uuid;
  // ... تحويل أو إنشاء UUID جديد
};
```

---

## 📚 الموارد الإضافية | Additional Resources

### الوثائق الرسمية | Official Documentation

- [Supabase Documentation](https://supabase.com/docs)
- [Supabase Flutter Documentation](https://supabase.com/docs/reference/dart/introduction)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)

### الأدوات المفيدة | Useful Tools

- [Supabase CLI](https://github.com/supabase/cli)
- [pgAdmin](https://www.pgadmin.org/) - PostgreSQL GUI
- [Postman](https://www.postman.com/) - API testing

### المجتمع | Community

- [Supabase Discord](https://discord.supabase.com/)
- [GitHub Discussions](https://github.com/supabase/supabase/discussions)

---

## ✅ قائمة التحقق النهائية | Final Checklist

قبل إطلاق التطبيق في الإنتاج، تأكد من:

- [ ] جميع الجداول موجودة وصحيحة
- [ ] RLS policies مفعّلة ومختبرة
- [ ] Edge Functions منشورة وتعمل
- [ ] البيانات منقولة بالكامل
- [ ] المزامنة تعمل (Push & Pull)
- [ ] Conflict resolution يعمل
- [ ] النسخ الاحتياطية مفعّلة
- [ ] المراقبة والتنبيهات مفعّلة
- [ ] الأداء مرضي
- [ ] الاختبار الشامل مكتمل
- [ ] التوثيق محدّث
- [ ] الفريق مدرّب على النظام الجديد

---

## 🎉 تهانينا! | Congratulations!

أنت الآن جاهز لاستخدام Supabase في تطبيق Marina Hotel! 🚀

You're now ready to use Supabase in your Marina Hotel app! 🚀

للدعم والمساعدة، راجع:
- `docs/` مجلد التوثيق
- `test/supabase_sync_test.dart` للأمثلة

For support and help, check:
- `docs/` documentation folder
- `test/supabase_sync_test.dart` for examples

---

**آخر تحديث | Last updated:** 2024-11-04  
**الإصدار | Version:** 1.0.0  
**المؤلف | Author:** Marina Hotel Team
