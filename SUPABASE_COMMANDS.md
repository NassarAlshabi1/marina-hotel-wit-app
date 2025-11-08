# 🔧 Supabase Commands Cheatsheet
# دليل الأوامر السريعة لـ Supabase

<div dir="rtl">

## دليل شامل لجميع الأوامر التي ستحتاجها
## Complete guide for all commands you'll need

</div>

---

## 📦 التثبيت | Installation

### Supabase CLI

```bash
# macOS/Linux
brew install supabase/tap/supabase

# Windows (Scoop)
scoop bucket add supabase https://github.com/supabase/scoop-bucket.git
scoop install supabase

# Windows (Chocolatey)
choco install supabase

# npm (جميع المنصات)
npm install -g supabase

# التحقق من التثبيت
supabase --version
```

### Deno (للـ Edge Functions)

```bash
# macOS/Linux
curl -fsSL https://deno.land/x/install/install.sh | sh

# Windows (PowerShell)
irm https://deno.land/install.ps1 | iex

# التحقق من التثبيت
deno --version
```

---

## 🔐 المصادقة | Authentication

```bash
# تسجيل الدخول
supabase login

# تسجيل الخروج
supabase logout

# التحقق من حالة تسجيل الدخول
supabase projects list
```

---

## 🚀 إدارة المشاريع | Project Management

```bash
# إنشاء مشروع جديد (عبر Dashboard)
# https://app.supabase.com

# عرض جميع المشاريع
supabase projects list

# ربط مشروع محلي بمشروع على Supabase
supabase link --project-ref YOUR_PROJECT_ID

# إلغاء ربط المشروع
supabase unlink

# عرض معلومات المشروع
supabase projects api-keys --project-ref YOUR_PROJECT_ID

# الحصول على Connection String
supabase db remote commit --project-ref YOUR_PROJECT_ID
```

---

## 🗄️ إدارة قاعدة البيانات | Database Management

### البدء المحلي | Local Development

```bash
# بدء Supabase محلياً (يتطلب Docker)
supabase start

# إيقاف Supabase المحلي
supabase stop

# إعادة تشغيل Supabase المحلي
supabase restart

# حالة Supabase المحلي
supabase status

# حذف جميع البيانات المحلية
supabase db reset
```

### Migrations

```bash
# إنشاء migration جديد
supabase migration new migration_name

# تطبيق migrations محلياً
supabase db reset

# رفع migrations إلى السيرفر
supabase db push

# سحب schema من السيرفر
supabase db pull

# عرض قائمة migrations
supabase migration list

# التراجع عن آخر migration (محلي)
supabase migration repair --status reverted
```

### SQL

```bash
# تنفيذ SQL من ملف
supabase db execute --file path/to/file.sql

# تنفيذ SQL مباشرة
supabase db execute --sql "SELECT * FROM rooms;"

# عرض الـ Schema
supabase db dump -f schema.sql --schema public

# نسخ احتياطية
supabase db dump -f backup.sql --data-only

# استعادة من نسخة احتياطية
supabase db restore backup.sql
```

---

## ⚡ Edge Functions

### الإنشاء | Creation

```bash
# إنشاء function جديدة
supabase functions new function-name

# مثال: إنشاء sync-push
supabase functions new sync-push
```

### النشر | Deployment

```bash
# نشر function واحدة
supabase functions deploy function-name

# نشر جميع functions
supabase functions deploy

# نشر مع متغيرات بيئية
supabase functions deploy function-name --no-verify-jwt

# مثال: نشر sync functions
supabase functions deploy sync-push
supabase functions deploy sync-pull
```

### الاختبار | Testing

```bash
# تشغيل function محلياً
supabase functions serve function-name

# تشغيل جميع functions محلياً
supabase functions serve

# اختبار function بـ curl
curl -i --location --request POST \
  'http://localhost:54321/functions/v1/function-name' \
  --header 'Authorization: Bearer YOUR_ANON_KEY' \
  --header 'Content-Type: application/json' \
  --data '{"key":"value"}'
```

### الإدارة | Management

```bash
# عرض قائمة functions
supabase functions list

# حذف function
supabase functions delete function-name

# عرض logs
supabase functions logs function-name

# عرض logs مباشرة
supabase functions logs function-name --follow
```

### متغيرات البيئة | Environment Variables

```bash
# تعيين متغير بيئة
supabase secrets set KEY=value

# تعيين عدة متغيرات
supabase secrets set KEY1=value1 KEY2=value2

# عرض جميع المتغيرات
supabase secrets list

# حذف متغير
supabase secrets unset KEY
```

---

## 🔒 المصادقة والأمان | Auth & Security

```bash
# عرض إعدادات Auth
supabase projects api-keys --project-ref YOUR_PROJECT_ID

# إعادة تعيين JWT secret (⚠️ خطير)
# يتم عبر Dashboard فقط

# تفعيل/تعطيل Email confirmations
# يتم عبر Dashboard > Authentication > Settings
```

---

## 📊 المراقبة والتقارير | Monitoring & Reports

```bash
# عرض حالة المشروع
supabase projects list

# عرض استهلاك الموارد
# يتم عبر Dashboard > Project Settings > Usage

# عرض logs
supabase functions logs function-name

# عرض Database logs
# يتم عبر Dashboard > Database > Logs
```

---

## 🔧 أوامر Flutter | Flutter Commands

### التثبيت | Installation

```bash
# الانتقال إلى مجلد mobile
cd mobile

# إضافة supabase_flutter
flutter pub add supabase_flutter

# أو يدوياً في pubspec.yaml
# dependencies:
#   supabase_flutter: ^2.0.0

# تحديث packages
flutter pub get
```

### الاختبار | Testing

```bash
# تشغيل الاختبارات
flutter test

# تشغيل اختبارات Supabase محددة
flutter test test/supabase_sync_test.dart

# تشغيل مع تفاصيل
flutter test --verbose

# تشغيل في وضع watch
flutter test --watch
```

### التشغيل | Running

```bash
# تشغيل التطبيق
flutter run

# تشغيل مع hot reload
flutter run --hot

# تشغيل على جهاز محدد
flutter run -d device_id

# عرض الأجهزة المتاحة
flutter devices
```

---

## 📝 أوامر Dart | Dart Commands

### تشغيل السكريبتات | Running Scripts

```bash
# تشغيل سكريبت نقل البيانات
dart run scripts/migrate_data.dart

# تشغيل مع arguments
dart run scripts/migrate_data.dart --dry-run

# compile وتشغيل
dart compile exe scripts/migrate_data.dart -o migrate
./migrate
```

---

## 🐳 Docker (للتطوير المحلي) | Docker (Local Dev)

```bash
# بدء Supabase محلياً (يتطلب Docker)
supabase start

# إيقاف
supabase stop

# عرض containers
docker ps | grep supabase

# عرض logs
docker logs supabase_db_marina-hotel

# حذف كل شيء (⚠️ يحذف البيانات)
supabase db reset
docker system prune -a
```

---

## 🔄 الهجرة الكاملة | Full Migration Workflow

```bash
# ===== المرحلة 1: الإعداد =====
# 1. إنشاء مشروع على supabase.com
# 2. ربط المشروع
supabase link --project-ref YOUR_PROJECT_ID

# 3. تنفيذ schema
supabase db push

# أو يدوياً عبر Dashboard:
# SQL Editor > New query > Paste 001_initial_schema.sql > Run
# SQL Editor > New query > Paste 002_rls_policies.sql > Run

# ===== المرحلة 2: Edge Functions =====
# 1. نشر functions
supabase functions deploy sync-push
supabase functions deploy sync-pull

# 2. اختبار functions
curl -X POST 'https://YOUR_PROJECT_ID.supabase.co/functions/v1/sync-push' \
  -H 'Authorization: Bearer YOUR_ANON_KEY' \
  -H 'Content-Type: application/json' \
  -d '{"changes":[]}'

# ===== المرحلة 3: تحديث الكود =====
cd mobile
flutter pub add supabase_flutter

# تحديث supabase_config.dart
# تحديث main.dart

# ===== المرحلة 4: نقل البيانات =====
# تحديث migrate_data.dart
dart run scripts/migrate_data.dart

# ===== المرحلة 5: الاختبار =====
flutter test test/supabase_sync_test.dart

# ===== المرحلة 6: التشغيل =====
flutter run

# ✅ Done!
```

---

## 🆘 استكشاف الأخطاء | Troubleshooting

### مشاكل الاتصال | Connection Issues

```bash
# اختبار الاتصال
curl https://YOUR_PROJECT_ID.supabase.co/rest/v1/

# اختبار مع authentication
curl https://YOUR_PROJECT_ID.supabase.co/rest/v1/rooms \
  -H "apikey: YOUR_ANON_KEY" \
  -H "Authorization: Bearer YOUR_ANON_KEY"
```

### مشاكل Functions

```bash
# عرض logs
supabase functions logs sync-push --follow

# إعادة نشر
supabase functions delete sync-push
supabase functions deploy sync-push

# اختبار محلي
supabase functions serve sync-push
# في terminal آخر:
curl -X POST http://localhost:54321/functions/v1/sync-push \
  -H 'Authorization: Bearer YOUR_ANON_KEY' \
  -d '{"changes":[]}'
```

### مشاكل Database

```bash
# التحقق من schema
supabase db dump -f schema.sql --schema public
cat schema.sql

# التحقق من tables
supabase db execute --sql "SELECT table_name FROM information_schema.tables WHERE table_schema='public';"

# التحقق من RLS
supabase db execute --sql "SELECT schemaname, tablename, policyname FROM pg_policies WHERE schemaname='public';"
```

### إعادة تعيين كل شيء | Reset Everything

```bash
# ⚠️ خطر: يحذف كل شيء محلياً
supabase stop
supabase db reset
supabase start

# ⚠️ خطر جداً: حذف من السيرفر
# يتم عبر Dashboard > Project Settings > Delete Project
```

---

## 📚 أوامر مفيدة إضافية | Additional Useful Commands

### Git

```bash
# commit التغييرات
git add .
git commit -m "feat: migrate to Supabase"
git push origin main

# إنشاء branch للهجرة
git checkout -b feature/supabase-migration
```

### Performance

```bash
# تحليل أداء Flutter
flutter run --profile

# بناء release
flutter build apk --release
flutter build ios --release

# تحليل حجم التطبيق
flutter build apk --analyze-size
```

### Database Optimization

```sql
-- التحقق من أداء الاستعلامات
EXPLAIN ANALYZE SELECT * FROM rooms WHERE deleted_at IS NULL;

-- إضافة index
CREATE INDEX idx_custom ON table_name(column_name);

-- عرض جميع indexes
SELECT * FROM pg_indexes WHERE schemaname = 'public';

-- تحليل الجدول
ANALYZE rooms;

-- vacuum الجدول
VACUUM FULL rooms;
```

---

## 🔗 روابط سريعة | Quick Links

```bash
# Dashboard
open https://app.supabase.com

# Documentation
open https://supabase.com/docs

# Status Page
open https://status.supabase.com

# مشروعك
open https://app.supabase.com/project/YOUR_PROJECT_ID
```

---

## 💡 نصائح | Tips

<div dir="rtl">

1. **استخدم aliases**: أضف إلى `.bashrc` أو `.zshrc`:
   ```bash
   alias sup='supabase'
   alias supstart='supabase start'
   alias supstop='supabase stop'
   alias suplog='supabase functions logs'
   ```

2. **اختصارات Flutter**:
   ```bash
   alias fr='flutter run'
   alias ft='flutter test'
   alias fpg='flutter pub get'
   ```

3. **اختبار سريع**:
   ```bash
   # إنشاء script للاختبار السريع
   echo 'supabase functions serve &
   sleep 5
   curl -X POST http://localhost:54321/functions/v1/sync-push \
     -H "Authorization: Bearer $ANON_KEY" \
     -d "{\"changes\":[]}"
   ' > test-functions.sh
   chmod +x test-functions.sh
   ```

4. **Backup تلقائي**:
   ```bash
   # إنشاء cron job للنسخ الاحتياطي
   0 0 * * * cd /path/to/project && supabase db dump -f backup-$(date +\%Y\%m\%d).sql
   ```

</div>

---

## ✅ قائمة تحقق الأوامر | Commands Checklist

```
☐ supabase login
☐ supabase link --project-ref YOUR_PROJECT_ID
☐ supabase db push
☐ supabase functions deploy sync-push
☐ supabase functions deploy sync-pull
☐ flutter pub add supabase_flutter
☐ dart run scripts/migrate_data.dart
☐ flutter test test/supabase_sync_test.dart
☐ flutter run
☐ ✅ كل شيء يعمل!
```

---

<div align="center">

### 🎉 جاهز للعمل! | Ready to Work!

**احفظ هذا الملف كمرجع سريع**  
**Save this file as a quick reference**

</div>

---

**آخر تحديث | Last Updated:** 2024-11-04  
**الإصدار | Version:** 1.0.0
