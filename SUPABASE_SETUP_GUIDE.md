# 🚀 دليل إعداد Supabase - Supabase Setup Guide

**المدة المتوقعة:** 30-60 دقيقة  
**المستوى:** متوسط

---

## 📑 جدول المحتويات | Table of Contents

1. [إنشاء مشروع Supabase](#1-إنشاء-مشروع-supabase)
2. [إعداد قاعدة البيانات](#2-إعداد-قاعدة-البيانات)
3. [تكوين المصادقة](#3-تكوين-المصادقة)
4. [نشر Edge Functions](#4-نشر-edge-functions)
5. [تحديث ملفات التطبيق](#5-تحديث-ملفات-التطبيق)
6. [اختبار الإعداد](#6-اختبار-الإعداد)

---

## 1. إنشاء مشروع Supabase

### الخطوات:

1. **التسجيل في Supabase**
   - انتقل إلى https://supabase.com
   - انقر على "Start your project"
   - سجل دخول باستخدام GitHub أو Email

2. **إنشاء مشروع جديد**
   - انقر على "New Project"
   - املأ التفاصيل:
     - **Organization**: اختر أو أنشئ واحدة
     - **Name**: `marina-hotel` أو أي اسم تريده
     - **Database Password**: اختر كلمة مرور قوية (احفظها!)
     - **Region**: اختر أقرب region لك (مثل `eu-central-1` لأوروبا)
     - **Pricing Plan**: Free tier كافٍ للاختبار

3. **انتظر إنشاء المشروع** (1-2 دقيقة)

4. **احصل على بيانات الاعتماد**
   - بعد إنشاء المشروع، انتقل إلى:
     **Settings > API**
   
   - انسخ:
     - **Project URL**: `https://xxxxxxxx.supabase.co`
     - **anon public key**: `eyJhbGc...` (مفتاح طويل)
     - **service_role key**: `eyJhbGc...` (⚠️ سري جداً - للسيرفر فقط)

5. **احفظ البيانات في ملف آمن**
   ```
   Project URL: https://abcdefgh.supabase.co
   Anon Key: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
   Service Role Key: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
   Database Password: your-db-password
   ```

---

## 2. إعداد قاعدة البيانات

### الخطوات:

1. **افتح SQL Editor**
   - في Supabase Dashboard، انتقل إلى:
     **SQL Editor** (في القائمة اليسرى)

2. **أنشئ جدول sync_state**
   ```sql
   -- جدول حالة المزامنة
   CREATE TABLE IF NOT EXISTS public.sync_state (
     id SERIAL PRIMARY KEY,
     last_pull_ts TIMESTAMPTZ DEFAULT NOW(),
     device_info JSONB,
     created_at TIMESTAMPTZ DEFAULT NOW(),
     updated_at TIMESTAMPTZ DEFAULT NOW()
   );

   -- فهرس على last_pull_ts
   CREATE INDEX IF NOT EXISTS idx_sync_state_last_pull 
     ON public.sync_state(last_pull_ts);
   ```

3. **أنشئ جدول rooms**
   ```sql
   -- جدول الغرف
   CREATE TABLE IF NOT EXISTS public.rooms (
     id SERIAL PRIMARY KEY,
     uuid UUID UNIQUE NOT NULL DEFAULT gen_random_uuid(),
     room_number VARCHAR(50) UNIQUE NOT NULL,
     type VARCHAR(50),
     price DECIMAL(10,2),
     status VARCHAR(50),
     image_url TEXT,
     floor_number INTEGER,
     created_at TIMESTAMPTZ DEFAULT NOW(),
     updated_at TIMESTAMPTZ DEFAULT NOW(),
     deleted_at TIMESTAMPTZ
   );

   -- فهارس
   CREATE INDEX IF NOT EXISTS idx_rooms_uuid ON public.rooms(uuid);
   CREATE INDEX IF NOT EXISTS idx_rooms_status ON public.rooms(status);
   CREATE INDEX IF NOT EXISTS idx_rooms_updated ON public.rooms(updated_at);
   ```

4. **أنشئ جدول bookings**
   ```sql
   -- جدول الحجوزات
   CREATE TABLE IF NOT EXISTS public.bookings (
     id SERIAL PRIMARY KEY,
     uuid UUID UNIQUE NOT NULL DEFAULT gen_random_uuid(),
     room_id INTEGER REFERENCES public.rooms(id),
     guest_name VARCHAR(255) NOT NULL,
     guest_phone VARCHAR(50),
     guest_id_number VARCHAR(50),
     check_in TIMESTAMPTZ NOT NULL,
     check_out TIMESTAMPTZ NOT NULL,
     total_price DECIMAL(10,2),
     status VARCHAR(50),
     notes TEXT,
     created_at TIMESTAMPTZ DEFAULT NOW(),
     updated_at TIMESTAMPTZ DEFAULT NOW(),
     deleted_at TIMESTAMPTZ
   );

   -- فهارس
   CREATE INDEX IF NOT EXISTS idx_bookings_uuid ON public.bookings(uuid);
   CREATE INDEX IF NOT EXISTS idx_bookings_room ON public.bookings(room_id);
   CREATE INDEX IF NOT EXISTS idx_bookings_status ON public.bookings(status);
   CREATE INDEX IF NOT EXISTS idx_bookings_updated ON public.bookings(updated_at);
   ```

5. **أنشئ باقي الجداول**
   ```sql
   -- جدول ملاحظات الحجوزات
   CREATE TABLE IF NOT EXISTS public.booking_notes (
     id SERIAL PRIMARY KEY,
     uuid UUID UNIQUE NOT NULL DEFAULT gen_random_uuid(),
     booking_id INTEGER REFERENCES public.bookings(id),
     note TEXT NOT NULL,
     created_by VARCHAR(255),
     created_at TIMESTAMPTZ DEFAULT NOW(),
     updated_at TIMESTAMPTZ DEFAULT NOW(),
     deleted_at TIMESTAMPTZ
   );

   -- جدول الموظفين
   CREATE TABLE IF NOT EXISTS public.employees (
     id SERIAL PRIMARY KEY,
     uuid UUID UNIQUE NOT NULL DEFAULT gen_random_uuid(),
     name VARCHAR(255) NOT NULL,
     phone VARCHAR(50),
     position VARCHAR(100),
     salary DECIMAL(10,2),
     hire_date DATE,
     created_at TIMESTAMPTZ DEFAULT NOW(),
     updated_at TIMESTAMPTZ DEFAULT NOW(),
     deleted_at TIMESTAMPTZ
   );

   -- جدول المصروفات
   CREATE TABLE IF NOT EXISTS public.expenses (
     id SERIAL PRIMARY KEY,
     uuid UUID UNIQUE NOT NULL DEFAULT gen_random_uuid(),
     expense_type VARCHAR(100),
     amount DECIMAL(10,2) NOT NULL,
     description TEXT,
     expense_date DATE,
     created_by VARCHAR(255),
     created_at TIMESTAMPTZ DEFAULT NOW(),
     updated_at TIMESTAMPTZ DEFAULT NOW(),
     deleted_at TIMESTAMPTZ
   );

   -- جدول المعاملات النقدية
   CREATE TABLE IF NOT EXISTS public.cash_transactions (
     id SERIAL PRIMARY KEY,
     uuid UUID UNIQUE NOT NULL DEFAULT gen_random_uuid(),
     transaction_type VARCHAR(50),
     amount DECIMAL(10,2) NOT NULL,
     description TEXT,
     transaction_date TIMESTAMPTZ,
     created_by VARCHAR(255),
     created_at TIMESTAMPTZ DEFAULT NOW(),
     updated_at TIMESTAMPTZ DEFAULT NOW(),
     deleted_at TIMESTAMPTZ
   );

   -- جدول الدفعات
   CREATE TABLE IF NOT EXISTS public.payments (
     id SERIAL PRIMARY KEY,
     uuid UUID UNIQUE NOT NULL DEFAULT gen_random_uuid(),
     booking_id INTEGER REFERENCES public.bookings(id),
     amount DECIMAL(10,2) NOT NULL,
     payment_method VARCHAR(50),
     payment_date TIMESTAMPTZ,
     notes TEXT,
     created_at TIMESTAMPTZ DEFAULT NOW(),
     updated_at TIMESTAMPTZ DEFAULT NOW(),
     deleted_at TIMESTAMPTZ
   );

   -- جدول الديون
   CREATE TABLE IF NOT EXISTS public.debts (
     id SERIAL PRIMARY KEY,
     uuid UUID UNIQUE NOT NULL DEFAULT gen_random_uuid(),
     debtor_name VARCHAR(255) NOT NULL,
     debtor_phone VARCHAR(50),
     amount DECIMAL(10,2) NOT NULL,
     due_date DATE,
     status VARCHAR(50),
     notes TEXT,
     created_at TIMESTAMPTZ DEFAULT NOW(),
     updated_at TIMESTAMPTZ DEFAULT NOW(),
     deleted_at TIMESTAMPTZ
   );
   ```

6. **تفعيل Row Level Security (RLS)**
   ```sql
   -- تفعيل RLS على جميع الجداول
   ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;
   ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;
   ALTER TABLE public.booking_notes ENABLE ROW LEVEL SECURITY;
   ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
   ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;
   ALTER TABLE public.cash_transactions ENABLE ROW LEVEL SECURITY;
   ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
   ALTER TABLE public.debts ENABLE ROW LEVEL SECURITY;
   ALTER TABLE public.sync_state ENABLE ROW LEVEL SECURITY;

   -- سياسات RLS (للمستخدمين المصادَق عليهم فقط)
   CREATE POLICY "Allow authenticated users full access to rooms"
     ON public.rooms FOR ALL
     TO authenticated
     USING (true)
     WITH CHECK (true);

   CREATE POLICY "Allow authenticated users full access to bookings"
     ON public.bookings FOR ALL
     TO authenticated
     USING (true)
     WITH CHECK (true);

   CREATE POLICY "Allow authenticated users full access to booking_notes"
     ON public.booking_notes FOR ALL
     TO authenticated
     USING (true)
     WITH CHECK (true);

   CREATE POLICY "Allow authenticated users full access to employees"
     ON public.employees FOR ALL
     TO authenticated
     USING (true)
     WITH CHECK (true);

   CREATE POLICY "Allow authenticated users full access to expenses"
     ON public.expenses FOR ALL
     TO authenticated
     USING (true)
     WITH CHECK (true);

   CREATE POLICY "Allow authenticated users full access to cash_transactions"
     ON public.cash_transactions FOR ALL
     TO authenticated
     USING (true)
     WITH CHECK (true);

   CREATE POLICY "Allow authenticated users full access to payments"
     ON public.payments FOR ALL
     TO authenticated
     USING (true)
     WITH CHECK (true);

   CREATE POLICY "Allow authenticated users full access to debts"
     ON public.debts FOR ALL
     TO authenticated
     USING (true)
     WITH CHECK (true);

   CREATE POLICY "Allow authenticated users full access to sync_state"
     ON public.sync_state FOR ALL
     TO authenticated
     USING (true)
     WITH CHECK (true);
   ```

7. **تحقق من الجداول**
   ```sql
   -- عرض جميع الجداول
   SELECT table_name 
   FROM information_schema.tables 
   WHERE table_schema = 'public';
   ```

---

## 3. تكوين المصادقة

### الخطوات:

1. **افتح Authentication**
   - في Supabase Dashboard:
     **Authentication > Users**

2. **إنشاء مستخدم للاختبار**
   - انقر على "Add user" > "Create new user"
   - املأ:
     - **Email**: `test@marina-hotel.com`
     - **Password**: `test_password_123`
     - **Auto Confirm User**: ✅ نعم
   
   - انقر على "Create user"

3. **إنشاء مستخدمين إضافيين (اختياري)**
   - يمكنك إنشاء مستخدمين للتطوير:
     - `dev@marina-hotel.com`
     - `admin@marina-hotel.com`

4. **تكوين إعدادات Auth (اختياري)**
   - **Authentication > Settings**
   - تأكد من:
     - **Enable Email Confirmations**: ❌ معطل للاختبار
     - **Enable Phone Confirmations**: ❌ معطل

---

## 4. نشر Edge Functions

### المتطلبات:
- Node.js 16+ مثبت
- npm أو yarn

### الخطوات:

1. **تثبيت Supabase CLI**
   ```bash
   npm install -g supabase
   ```

2. **تسجيل الدخول في Supabase CLI**
   ```bash
   supabase login
   ```
   - سيفتح متصفح لتسجيل الدخول
   - صرّح للتطبيق

3. **ربط المشروع**
   ```bash
   cd /path/to/marina-hotel-wit-app
   
   supabase link --project-ref YOUR_PROJECT_REF
   ```
   
   **ملاحظة:** احصل على `PROJECT_REF` من:
   - Supabase Dashboard > Settings > General > Reference ID
   - أو من URL: `https://app.supabase.com/project/[PROJECT_REF]`

4. **تحديد متغيرات البيئة للـ Functions**
   ```bash
   supabase secrets set SUPABASE_URL=https://your-project.supabase.co
   supabase secrets set SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
   ```

5. **نشر sync-push Function**
   ```bash
   supabase functions deploy sync-push
   ```
   
   يجب أن ترى:
   ```
   Deploying sync-push...
   ✓ Successfully deployed sync-push
   Function URL: https://your-project.supabase.co/functions/v1/sync-push
   ```

6. **نشر sync-pull Function**
   ```bash
   supabase functions deploy sync-pull
   ```

7. **التحقق من النشر**
   ```bash
   supabase functions list
   ```
   
   يجب أن ترى:
   ```
   sync-push    deployed
   sync-pull    deployed
   ```

8. **اختبار Edge Function يدوياً (اختياري)**
   ```bash
   curl -X POST \
     https://your-project.supabase.co/functions/v1/sync-push \
     -H "Authorization: Bearer YOUR_ANON_KEY" \
     -H "Content-Type: application/json" \
     -d '{"changes": []}'
   ```
   
   يجب أن ترى:
   ```json
   {"success": true, "data": {"results": []}}
   ```

---

## 5. تحديث ملفات التطبيق

### الخطوات:

1. **تحديث supabase_config.dart**
   ```bash
   cd mobile/lib/utils
   nano supabase_config.dart
   # أو استخدم أي محرر نصوص
   ```
   
   استبدل:
   ```dart
   static const String supabaseUrl = 'YOUR_SUPABASE_URL';
   static const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';
   static const String supabaseServiceRoleKey = 'YOUR_SERVICE_ROLE_KEY';
   ```
   
   بـ:
   ```dart
   static const String supabaseUrl = 'https://abcdefgh.supabase.co';
   static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6...';
   static const String supabaseServiceRoleKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6...';
   ```

2. **تحديث test config**
   ```bash
   cd ../../../test
   nano supabase_sync_test.dart
   ```
   
   استبدل في `TestConfig` (السطور 21-26):
   ```dart
   class TestConfig {
     static const String supabaseUrl = 'https://abcdefgh.supabase.co';
     static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6...';
     static const String testEmail = 'test@marina-hotel.com';
     static const String testPassword = 'test_password_123';
   }
   ```

3. **إنشاء ملف .env (اختياري - أفضل للأمان)**
   ```bash
   cd ..
   nano .env
   ```
   
   أضف:
   ```
   SUPABASE_URL=https://abcdefgh.supabase.co
   SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6...
   SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6...
   TEST_EMAIL=test@marina-hotel.com
   TEST_PASSWORD=test_password_123
   ```
   
   ثم أضف إلى `.gitignore`:
   ```bash
   echo ".env" >> .gitignore
   ```

4. **تثبيت المكتبات**
   ```bash
   cd mobile
   flutter pub get
   ```

---

## 6. اختبار الإعداد

### الخطوات:

1. **اختبار الاتصال بـ Supabase**
   ```bash
   cd mobile
   flutter test test/supabase_sync_test.dart --name "Should pull changes"
   ```

2. **اختبار Push**
   ```bash
   flutter test test/supabase_sync_test.dart --name "Should push CREATE"
   ```

3. **تشغيل جميع الاختبارات**
   ```bash
   flutter test ../test/supabase_sync_test.dart
   ```

4. **التحقق من النتائج**
   - يجب أن تمر جميع الاختبارات ✅
   - تحقق من البيانات في Supabase Dashboard > Table Editor

---

## 🎉 تهانينا!

لقد أكملت إعداد Supabase بنجاح! 🚀

### الخطوات التالية:

1. **دمج مع التطبيق الرئيسي**
   - استخدم `SupabaseSyncService` بدلاً من `SyncService`
   - تحديث `main.dart` لتهيئة Supabase

2. **المراقبة**
   - راقب Edge Functions من Supabase Dashboard > Edge Functions > Logs
   - راقب قاعدة البيانات من Table Editor

3. **الأمان**
   - ⚠️ لا تشارك `service_role_key` أبداً
   - استخدم متغيرات بيئة في الإنتاج
   - فعّل MFA في حساب Supabase

---

## 🆘 المساعدة

### إذا واجهت مشاكل:

1. **تحقق من الـ Logs**
   ```bash
   supabase functions logs sync-push --tail
   ```

2. **تواصل مع الدعم**
   - Supabase Discord: https://discord.supabase.com
   - Supabase Docs: https://supabase.com/docs

3. **مراجعة الأكواد**
   - راجع `SUPABASE_TEST_REPORT.md` للمشاكل الشائعة

---

**تم إنشاء هذا الدليل بواسطة:** Capy AI  
**التاريخ:** 2025-11-04
