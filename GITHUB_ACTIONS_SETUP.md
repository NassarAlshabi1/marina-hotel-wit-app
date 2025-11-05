# 🚀 دليل إعداد GitHub Actions للاختبارات التلقائية

**المدة المتوقعة:** 10-15 دقيقة  
**المستوى:** سهل

---

## 📋 نظرة عامة سريعة | Quick Overview

تم إعداد GitHub Actions workflow يقوم تلقائياً بـ:
- ✅ تثبيت Flutter
- ✅ تثبيت المكتبات
- ✅ تكوين Supabase credentials
- ✅ تشغيل 14 اختبار
- ✅ رفع النتائج
- ✅ التعليق على PRs

**كل ما تحتاجه:** إضافة 5 secrets في GitHub!

---

## 🎯 الخطوات (10 دقائق)

### الخطوة 1: افتح GitHub Repository (1 دقيقة)

1. انتقل إلى:
   ```
   https://github.com/NassarAlshabi1/marina-hotel-wit-app
   ```

2. انقر على **Settings** (⚙️ في الشريط العلوي)

3. في القائمة اليسرى، انقر على:
   ```
   Secrets and variables > Actions
   ```

---

### الخطوة 2: أضف Supabase Secrets (5 دقائق)

#### 🔑 Secret #1: SUPABASE_URL

1. انقر **New repository secret**
2. املأ:
   - **Name:** `SUPABASE_URL`
   - **Secret:** `https://your-project-id.supabase.co`
     *(احصل عليه من: Supabase Dashboard > Settings > API > Project URL)*
3. انقر **Add secret**

#### 🔑 Secret #2: SUPABASE_ANON_KEY

1. انقر **New repository secret**
2. املأ:
   - **Name:** `SUPABASE_ANON_KEY`
   - **Secret:** `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...`
     *(احصل عليه من: Settings > API > anon public)*
3. انقر **Add secret**

#### 🔑 Secret #3: SUPABASE_SERVICE_ROLE_KEY

1. انقر **New repository secret**
2. املأ:
   - **Name:** `SUPABASE_SERVICE_ROLE_KEY`
   - **Secret:** `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...`
     *(احصل عليه من: Settings > API > service_role)*
3. انقر **Add secret**
4. ⚠️ **مهم جداً:** هذا مفتاح سري - لا تشاركه أبداً!

#### 🔑 Secret #4: TEST_EMAIL

1. انقر **New repository secret**
2. املأ:
   - **Name:** `TEST_EMAIL`
   - **Secret:** `test@marina-hotel.com`
     *(أو البريد الذي أنشأته في Supabase Authentication)*
3. انقر **Add secret**

#### 🔑 Secret #5: TEST_PASSWORD

1. انقر **New repository secret**
2. املأ:
   - **Name:** `TEST_PASSWORD`
   - **Secret:** `test_password_123`
     *(كلمة مرور المستخدم في Supabase)*
3. انقر **Add secret**

---

### الخطوة 3: تحقق من الـ Secrets (1 دقيقة)

يجب أن ترى الآن 5 secrets:
- ✅ `SUPABASE_URL`
- ✅ `SUPABASE_ANON_KEY`
- ✅ `SUPABASE_SERVICE_ROLE_KEY`
- ✅ `TEST_EMAIL`
- ✅ `TEST_PASSWORD`

---

### الخطوة 4: شغّل الـ Workflow (2 دقيقة)

#### طريقة 1: Push للفرع Ali
```bash
# على جهازك المحلي
git pull origin Ali
git push origin Ali
```

#### طريقة 2: تشغيل يدوي من GitHub
1. انتقل إلى: **Actions** tab
2. اختر: **Supabase Sync Tests** من القائمة اليسرى
3. انقر: **Run workflow** (زر أزرق)
4. اختر الفرع: **Ali**
5. انقر: **Run workflow** (زر أخضر)

---

### الخطوة 5: شاهد النتائج (1 دقيقة)

1. في **Actions** tab، سترى workflow يعمل 🔄
2. انقر عليه لمشاهدة التفاصيل
3. انتظر حتى ينتهي (2-3 دقائق)
4. النتيجة:
   - ✅ أخضر = نجحت جميع الاختبارات! 🎉
   - ❌ أحمر = بعض الاختبارات فشلت

---

## 📊 ما سيحدث تلقائياً | What Happens Automatically

### عند كل Push:
```
1. GitHub Actions يبدأ التشغيل
2. يثبت Flutter
3. يثبت المكتبات (flutter pub get)
4. يطبق credentials من Secrets
5. يشغل 14 اختبار
6. يرفع النتائج
7. يعطيك ✅ أو ❌
```

### عند إنشاء Pull Request:
```
1. كل الخطوات السابقة +
2. يضيف تعليق تلقائي على PR بالنتيجة
3. يظهر status check (✅/❌)
```

---

## 🔍 عرض التفاصيل | View Details

### في Actions Tab:

```
Actions > Supabase Sync Tests > [آخر run]
```

ستشاهد:
- 📋 **Check Configuration** - فحص الإعدادات
- 🧪 **Run Tests** - تشغيل الاختبارات
  - Setup Flutter
  - Install dependencies
  - Configure credentials
  - Run tests
  - Upload results
  - Comment on PR

### في Pull Request:

سيظهر تعليق مثل:
```
## ✅ Supabase Sync Tests passed

**Branch:** Ali
**Commit:** a1b2c3d

✅ All Supabase sync tests passed successfully!

### 📋 Test Coverage
- ✅ Push Tests (CREATE, UPDATE, DELETE)
- ✅ Pull Tests
- ✅ Full Cycle Tests
...
```

---

## ⚠️ استكشاف المشاكل | Troubleshooting

### المشكلة: Workflow لا يعمل
**الأسباب المحتملة:**
- ✅ تأكد من إضافة جميع الـ 5 secrets
- ✅ تأكد من تفعيل Actions في Settings

**الحل:**
```
Settings > Actions > General > Actions permissions
✅ Allow all actions and reusable workflows
```

### المشكلة: Tests failed
**الأسباب المحتملة:**
- ❌ Credentials خاطئة في Secrets
- ❌ Edge Functions غير منشورة
- ❌ قاعدة البيانات غير مهيأة
- ❌ مستخدم الاختبار غير موجود

**الحل:**
1. راجع logs في Actions tab
2. تحقق من Supabase Dashboard
3. راجع `SUPABASE_TEST_REPORT.md` (قسم Troubleshooting)

### المشكلة: "Missing authorization header"
**الحل:**
- تأكد من `TEST_EMAIL` و `TEST_PASSWORD` صحيحة
- تأكد من وجود المستخدم في Supabase Authentication

---

## 📸 صور توضيحية | Visual Guide

### 1. مكان الـ Secrets:
```
Repository > Settings > Secrets and variables > Actions
                                                    ↓
                                       [New repository secret]
```

### 2. تشغيل Workflow:
```
Repository > Actions > Supabase Sync Tests > Run workflow
                                                    ↓
                                          [Select branch: Ali]
                                                    ↓
                                            [Run workflow ✅]
```

### 3. مشاهدة النتائج:
```
Actions > [آخر run] > Run Tests
                         ↓
               [Check logs for each step]
                         ↓
               [✅ All tests passed! أو ❌ Some failed]
```

---

## 🎯 Checklist سريع | Quick Checklist

قبل التشغيل، تأكد من:

- [ ] ✅ أضفت جميع الـ 5 secrets في GitHub
- [ ] ✅ Supabase project موجود ويعمل
- [ ] ✅ Edge Functions منشورة (sync-push & sync-pull)
- [ ] ✅ قاعدة البيانات مهيأة (جداول + RLS)
- [ ] ✅ مستخدم اختبار موجود في Authentication

---

## 🎉 اختبار النجاح | Success Test

لاختبار أن كل شيء يعمل:

1. قم بتعديل بسيط في الكود:
   ```bash
   echo "# Test" >> README.md
   ```

2. اعمل commit و push:
   ```bash
   git add README.md
   git commit -m "Test GitHub Actions"
   git push origin Ali
   ```

3. انتقل إلى Actions tab

4. شاهد الـ workflow يعمل! 🚀

5. إذا نجح ✅ = كل شيء مضبوط!

---

## 💡 نصائح | Tips

### للتطوير:
- استخدم مشروع Supabase منفصل للاختبار
- لا تستخدم production credentials
- راقب usage في Supabase Dashboard

### للأمان:
- ⚠️ لا تشارك SERVICE_ROLE_KEY أبداً
- استخدم Secrets فقط - لا hardcode
- قم بتدوير المفاتيح بشكل دوري

### للكفاءة:
- Workflow يعمل فقط عند تغيير ملفات معينة:
  - `mobile/**`
  - `test/**`
  - `supabase/**`
- هذا يوفر GitHub Actions minutes

---

## 📚 موارد إضافية | Additional Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Supabase Documentation](https://supabase.com/docs)
- `.github/workflows/README.md` - تفاصيل الـ workflow
- `SUPABASE_TEST_REPORT.md` - تقرير الاختبارات
- `SUPABASE_SETUP_GUIDE.md` - إعداد Supabase

---

## 🎊 تهانينا! | Congratulations!

إذا وصلت هنا، يعني:
- ✅ GitHub Actions مُعد بنجاح
- ✅ Secrets مكوّنة بشكل صحيح
- ✅ Workflow يعمل تلقائياً
- ✅ الاختبارات تعمل على كل push/PR

**الآن لديك CI/CD للاختبارات التلقائية! 🚀**

---

**تم إنشاؤه بواسطة | Created by:** Capy AI  
**التاريخ | Date:** 2025-11-04  
**الإصدار | Version:** 1.0
