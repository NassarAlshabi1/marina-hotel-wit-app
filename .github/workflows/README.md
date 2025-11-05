# 🚀 GitHub Actions للاختبارات التلقائية | GitHub Actions for Automated Testing

## 📋 نظرة عامة | Overview

يتم تشغيل اختبارات Supabase تلقائياً على GitHub Actions عند:
- Push إلى فرع `Ali` أو `main`
- إنشاء Pull Request
- التشغيل اليدوي من GitHub UI

---

## ⚙️ إعداد GitHub Secrets

لتشغيل الاختبارات، يجب إضافة Secrets التالية:

### الخطوات:

1. **انتقل إلى GitHub Repository**
   ```
   https://github.com/NassarAlshabi1/marina-hotel-wit-app
   ```

2. **افتح Settings**
   ```
   Settings > Secrets and variables > Actions
   ```

3. **أضف الـ Secrets التالية:**

#### 🔑 Secret 1: SUPABASE_URL
```
Name: SUPABASE_URL
Value: https://your-project-id.supabase.co
```
- **كيفية الحصول عليه:**
  - Supabase Dashboard > Settings > API > Project URL

#### 🔑 Secret 2: SUPABASE_ANON_KEY
```
Name: SUPABASE_ANON_KEY
Value: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```
- **كيفية الحصول عليه:**
  - Supabase Dashboard > Settings > API > Project API keys > anon public

#### 🔑 Secret 3: SUPABASE_SERVICE_ROLE_KEY
```
Name: SUPABASE_SERVICE_ROLE_KEY
Value: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```
- **كيفية الحصول عليه:**
  - Supabase Dashboard > Settings > API > Project API keys > service_role
- ⚠️ **تحذير:** هذا المفتاح سري جداً! لا تشاركه أبداً

#### 🔑 Secret 4: TEST_EMAIL
```
Name: TEST_EMAIL
Value: test@marina-hotel.com
```
- البريد الإلكتروني لمستخدم الاختبار في Supabase

#### 🔑 Secret 5: TEST_PASSWORD
```
Name: TEST_PASSWORD
Value: test_password_123
```
- كلمة مرور مستخدم الاختبار في Supabase

---

## 🎯 كيفية التشغيل | How to Run

### 1️⃣ تشغيل تلقائي عند Push
```bash
git push origin Ali
```
سيتم تشغيل الاختبارات تلقائياً ✅

### 2️⃣ تشغيل يدوي من GitHub
1. انتقل إلى: **Actions** tab
2. اختر: **Supabase Sync Tests**
3. انقر: **Run workflow**
4. اختر الفرع وانقر **Run workflow**

### 3️⃣ عند إنشاء Pull Request
عند إنشاء PR، سيتم:
- تشغيل الاختبارات تلقائياً ✅
- إضافة تعليق بالنتيجة 💬
- رفع نتائج الاختبار 📤

---

## 📊 Jobs في الـ Workflow

### Job 1: Run Tests (الاختبارات الرئيسية)

**الخطوات:**
1. ✅ سحب الكود (Checkout)
2. ✅ تثبيت Flutter
3. ✅ تثبيت المكتبات (`flutter pub get`)
4. ✅ تكوين Credentials من Secrets
5. ✅ تشغيل الاختبارات
6. ✅ رفع النتائج
7. ✅ التعليق على PR (إذا كان PR)

### Job 2: Check Configuration (فحص الإعدادات)

**الخطوات:**
1. ✅ التحقق من Placeholder values
2. ✅ عرض قائمة بالـ Secrets المطلوبة
3. ✅ تقديم تعليمات الإعداد

---

## 📋 الاختبارات المُشغلة | Tests Run

- ✅ **Push Tests** (4 اختبارات)
  - CREATE operation
  - UPDATE operation
  - DELETE operation
  - Batch operations

- ✅ **Pull Tests** (4 اختبارات)
  - Pull all changes
  - Pull incremental changes
  - Verify entity types
  - Verify operation types

- ✅ **Full Cycle Tests** (2 اختبار)
  - Complete push-pull cycle
  - Conflict resolution

- ✅ **Error Handling** (3 اختبارات)
  - Invalid entities
  - Missing fields
  - Empty arrays

- ✅ **Performance Tests** (1 اختبار)
  - Large batch (50 items)

**المجموع:** 14 اختبار شامل

---

## 🔍 عرض النتائج | Viewing Results

### في Actions Tab:
1. انتقل إلى: **Actions**
2. اختر: **Supabase Sync Tests**
3. اختر آخر run
4. شاهد:
   - ✅ الخطوات والنتائج
   - 📊 Test summary
   - 📥 Downloaded artifacts

### في Pull Request:
- سيظهر تعليق تلقائي بالنتيجة
- ✅ إذا نجحت جميع الاختبارات
- ❌ إذا فشل أي اختبار

---

## ⚠️ استكشاف الأخطاء | Troubleshooting

### خطأ: "Missing authorization header"
**السبب:** Secrets غير مكوّنة  
**الحل:** أضف جميع الـ Secrets المطلوبة

### خطأ: "Function not found"
**السبب:** Edge Functions غير منشورة  
**الحل:** 
```bash
supabase functions deploy sync-push
supabase functions deploy sync-pull
```

### خطأ: "Table not found"
**السبب:** قاعدة البيانات غير مهيأة  
**الحل:** راجع `SUPABASE_SETUP_GUIDE.md`

### Tests تم تخطيها (Skipped)
**السبب:** Credentials غير صحيحة  
**الحل:** تحقق من القيم في GitHub Secrets

---

## 📚 الوثائق ذات الصلة | Related Documentation

- [SUPABASE_TEST_REPORT.md](../../SUPABASE_TEST_REPORT.md) - تقرير الاختبارات المفصل
- [SUPABASE_SETUP_GUIDE.md](../../SUPABASE_SETUP_GUIDE.md) - دليل إعداد Supabase
- [SUPABASE_INTEGRATION_README.md](../../SUPABASE_INTEGRATION_README.md) - نظرة عامة
- [run_supabase_tests.sh](../../run_supabase_tests.sh) - سكريبت محلي

---

## 🎯 Best Practices

### ✅ نعم (Do):
- احفظ Secrets بشكل آمن في GitHub Secrets
- استخدم مشروع Supabase منفصل للاختبار
- راقب نتائج الاختبارات في Actions
- تحقق من التعليقات على PRs

### ❌ لا (Don't):
- لا تضع Credentials في الكود
- لا تشارك SERVICE_ROLE_KEY
- لا تستخدم production database للاختبار
- لا تتجاهل فشل الاختبارات

---

## 🔄 Workflow Triggers

### عند Push:
```yaml
on:
  push:
    branches: [ Ali, main ]
    paths:
      - 'mobile/**'
      - 'test/**'
      - 'supabase/**'
```

### عند PR:
```yaml
on:
  pull_request:
    branches: [ Ali, main ]
```

### يدوياً:
```yaml
on:
  workflow_dispatch:
```

---

## 📊 Badge للـ README

أضف هذا Badge إلى README.md الرئيسي:

```markdown
[![Supabase Tests](https://github.com/NassarAlshabi1/marina-hotel-wit-app/actions/workflows/supabase-sync-tests.yml/badge.svg)](https://github.com/NassarAlshabi1/marina-hotel-wit-app/actions/workflows/supabase-sync-tests.yml)
```

---

## 📞 الدعم | Support

إذا واجهت مشاكل:
1. تحقق من logs في Actions tab
2. راجع `SUPABASE_TEST_REPORT.md` (قسم Troubleshooting)
3. تأكد من تكوين جميع Secrets بشكل صحيح
4. تحقق من نشر Edge Functions

---

**تم إنشاؤه بواسطة | Created by:** Capy AI  
**التاريخ | Date:** 2025-11-04  
**الإصدار | Version:** 1.0
