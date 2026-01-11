# Flutter Auto Fix Workflows 🔧

يوفر هذا المستودع workflows تلقائية لتطبيق إصلاحات Dart/Flutter على جميع المشاريع.

## 📋 Workflows المتاحة

### 1. Flutter Auto Fix (dart-auto-fix.yml)
يعمل تلقائياً على Pull Requests عند تعديل ملفات Dart.

**متى يعمل:**
- عند إنشاء أو تحديث PR يحتوي على ملفات `*.dart`
- عند تعديل `pubspec.yaml` أو `analysis_options.yaml`
- يمكن تشغيله يدوياً من تبويب Actions

**ما يفعله:**
1. يكتشف تلقائياً جميع مشاريع Flutter/Dart في المستودع
2. يشغل `flutter pub get` على كل مشروع
3. يفحص المشاكل القابلة للإصلاح باستخدام `dart fix --dry-run`
4. يطبق الإصلاحات تلقائياً
5. يرفع التغييرات إلى نفس الفرع
6. يضيف تعليق على PR بالتفاصيل

**التشغيل اليدوي:**
```bash
# من واجهة GitHub Actions
Actions → Flutter Auto Fix → Run workflow
```

---

### 2. Scheduled Flutter Fix (scheduled-flutter-fix.yml)
فحص دوري أسبوعي لجميع الفروع.

**متى يعمل:**
- تلقائياً كل يوم أحد الساعة 2 صباحاً UTC
- يمكن تشغيله يدوياً في أي وقت

**ما يفعله:**
1. يفحص جميع مشاريع Flutter في الفرع المستهدف (افتراضياً `main`)
2. يطبق `dart fix --apply` على جميع المشاريع
3. ينشئ PR تلقائياً بالإصلاحات (اختياري)
4. يولد تقرير مفصل بالتغييرات

**التشغيل اليدوي:**
```bash
# من واجهة GitHub Actions
Actions → Scheduled Flutter Fix → Run workflow

# الخيارات:
# - target_branch: الفرع المستهدف (افتراضي: main)
# - create_pr: إنشاء PR؟ (افتراضي: true)
```

---

## 🔧 أنواع الإصلاحات التلقائية

الـ workflows تطبق إصلاحات Dart القياسية:

### ✅ إزالة الكود غير المستخدم
- `unused_import` - حذف imports غير المستخدمة
- `unused_local_variable` - حذف متغيرات غير مستخدمة
- `unused_field` - حذف حقول غير مستخدمة
- `unused_element` - حذف عناصر غير مستخدمة
- `unused_catch_stack` - حذف stack trace غير المستخدم

### ✅ تحسينات الأداء
- `unnecessary_cast` - إزالة type casts غير الضرورية
- `unnecessary_const` - إزالة const غير الضرورية
- `unnecessary_new` - إزالة كلمة new غير الضرورية
- `unnecessary_null_comparison` - تبسيط مقارنات null

### ✅ تحسينات الكود
- `prefer_const_constructors` - استخدام const حيث ممكن
- `prefer_final_fields` - استخدام final للحقول
- `prefer_is_empty` - استخدام isEmpty بدلاً من length == 0
- `avoid_empty_else` - حذف else فارغة

---

**Created by:** GitHub Actions Bot  
**Last Updated:** 2026-01-11  
**Version:** 1.0.0
