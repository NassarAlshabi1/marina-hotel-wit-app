# 🚀 دليل بناء نسخة Release
## GitHub Actions - Build Release Guide

---

## 📋 Workflows المتوفرة

### 1. **Build and Release APK (Ditto)** ⭐
**الملف:** `.github/workflows/build-release-ditto.yml`

**الاستخدام:**
- بناء Release APK + AAB
- إنشاء GitHub Release تلقائياً
- رفع الملفات للـ Release

**التشغيل:**

#### عبر Tag:
```bash
git tag v2.0.0
git push origin v2.0.0
```

#### يدوياً (Manual):
1. اذهب إلى **Actions** في GitHub
2. اختر **Build and Release APK (Ditto)**
3. اضغط **Run workflow**
4. أدخل رقم الإصدار (مثلاً: `v2.0.0`)
5. اضغط **Run workflow**

**المخرجات:**
- ✅ APK موقّع وجاهز للتوزيع
- ✅ AAB جاهز للنشر على Google Play
- ✅ GitHub Release مع التوثيق
- ✅ Artifacts للتحميل

---

### 2. **Quick Build Release APK** ⚡
**الملف:** `.github/workflows/quick-build-release.yml`

**الاستخدام:**
- بناء سريع لـ APK أو AAB
- بدون إنشاء Release
- للاختبار السريع

**التشغيل:**
1. اذهب إلى **Actions** في GitHub
2. اختر **Quick Build Release APK**
3. اضغط **Run workflow**
4. اختر نوع البناء:
   - `apk` - APK فقط
   - `aab` - AAB فقط
   - `both` - كلاهما
5. اضغط **Run workflow**

**المخرجات:**
- ✅ APK/AAB كـ Artifacts
- ✅ مدة الاحتفاظ: 7 أيام

---

### 3. **Build Flutter Release APK** (موجود مسبقاً)
**الملف:** `.github/workflows/flutter-apk-release.yml`

**الاستخدام:**
- يعمل تلقائياً على Pull Requests
- بناء APK للمراجعة

---

## 📦 الملفات المُنتجة

### APK
```
marina-hotel-v2.0.0-release.apk
```
- **الحجم:** ~20-30 MB
- **الاستخدام:** تثبيت مباشر على Android
- **التوافق:** Android 5.0+ (API 21)

### AAB (App Bundle)
```
marina-hotel-v2.0.0-release.aab
```
- **الحجم:** ~15-25 MB
- **الاستخدام:** النشر على Google Play Store
- **المميزات:** تحسين الحجم حسب الجهاز

---

## 🔧 إعداد الـ Keystore

### الملفات المطلوبة:
✅ `mobile/android/app/release.keystore` - موجود  
✅ `mobile/android/key.properties` - موجود

### معلومات التوقيع:
```
Store File: release.keystore
Store Password: Marina2025SecureKey
Key Alias: marina-hotel-app
Key Password: Marina2025SecureKey
SHA-1: 67:12:57:A2:9B:53:FA:71:AC:BC:0F:A8:C9:54:2F:3F:46:0B:A8:1C
```

---

## 📱 تنزيل الـ APK

### من GitHub Release:
1. اذهب إلى **Releases** في GitHub
2. اختر أحدث إصدار
3. قم بتحميل `marina-hotel-vX.X.X-release.apk`

### من Artifacts:
1. اذهب إلى **Actions** في GitHub
2. اختر الـ workflow run
3. قم بتحميل الـ artifact من الأسفل

---

## 🎯 خطوات الإصدار الكامل

### 1. التحضير
```bash
# تحديث رقم الإصدار في pubspec.yaml
cd mobile
vim pubspec.yaml
# version: 2.0.0+3 (2.0.0 هو رقم الإصدار، 3 هو build number)
```

### 2. Commit التغييرات
```bash
git add mobile/pubspec.yaml
git commit -m "chore: bump version to 2.0.0"
git push origin main
```

### 3. إنشاء Tag
```bash
git tag -a v2.0.0 -m "Release v2.0.0 - Ditto Edition"
git push origin v2.0.0
```

### 4. انتظار البناء
- GitHub Actions ستبني APK + AAB تلقائياً
- ستنشئ Release جديد
- مدة البناء: ~10-15 دقيقة

### 5. المراجعة
- راجع الـ Release Notes
- حمّل الـ APK واختبره
- تأكد من التوقيع الصحيح

### 6. النشر
- شارك رابط الـ Release مع المستخدمين
- أو ارفع الـ AAB إلى Google Play

---

## 🔍 التحقق من البناء

### فحص الـ APK:
```bash
# معلومات APK
aapt dump badging app-release.apk

# التوقيع
apksigner verify --print-certs app-release.apk

# SHA-1
keytool -list -v -keystore release.keystore
```

### المعلومات المتوقعة:
- Package: `com.aden.marina`
- Version Name: `2.0.0`
- Version Code: `3`
- Min SDK: `21` (Android 5.0)
- Target SDK: `36`
- SHA-1: `67:12:57:A2:9B:53:FA:71:AC:BC:0F:A8:C9:54:2F:3F:46:0B:A8:1C`

---

## 📊 مراقبة البناء

### GitHub Actions UI:
1. **Actions** tab
2. اختر الـ workflow
3. شاهد الـ logs الحية
4. راجع الـ Summary

### Log Files:
- Build logs متاحة لمدة 90 يوم
- Artifacts متاحة حسب الإعدادات (7-90 يوم)

---

## 🐛 حل المشاكل

### Build Failed: "Keystore not found"
**الحل:**
```bash
# تحقق من وجود الملفات
ls -la mobile/android/app/release.keystore
ls -la mobile/android/key.properties
```

### Build Failed: "Dependency not found"
**الحل:**
```bash
# تنظيف وإعادة البناء
cd mobile
flutter clean
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter build apk --release
```

### Build Failed: "Ditto SDK error"
**الحل:**
```bash
# تحقق من Ditto في pubspec.yaml
grep "ditto:" mobile/pubspec.yaml

# يجب أن يظهر:
# ditto: ^4.8.0
```

### APK Size Too Large
**الحل:**
```bash
# استخدم AAB بدلاً من APK
flutter build appbundle --release

# أو قلل حجم APK
flutter build apk --release --split-per-abi
```

---

## 📚 الموارد

### التوثيق:
- [Flutter Build Modes](https://docs.flutter.dev/testing/build-modes)
- [Android App Bundle](https://developer.android.com/guide/app-bundle)
- [GitHub Actions](https://docs.github.com/en/actions)

### ملفات المشروع:
- `DITTO_MIGRATION_GUIDE.md` - دليل التحويل
- `DITTO_QUICK_START.md` - البدء السريع
- `MIGRATION_SUMMARY.md` - ملخص التحويل

---

## ✅ قائمة التحقق قبل الإصدار

- [ ] تحديث رقم الإصدار في `pubspec.yaml`
- [ ] اختبار التطبيق محلياً
- [ ] مراجعة التغييرات الأخيرة
- [ ] تحديث Release Notes
- [ ] إنشاء Git Tag
- [ ] انتظار نجاح البناء
- [ ] اختبار الـ APK المُنتج
- [ ] التحقق من التوقيع
- [ ] نشر الـ Release
- [ ] إعلام المستخدمين

---

## 🎉 الخلاصة

### لبناء Release سريع:
```bash
# في GitHub Actions
Actions → Quick Build Release APK → Run workflow → Select APK → Run
```

### لإصدار كامل:
```bash
# في Terminal
git tag v2.0.0
git push origin v2.0.0

# GitHub Actions ستتولى الباقي!
```

---

**آخر تحديث:** نوفمبر 2025  
**الإصدار:** 2.0.0  
**الحالة:** ✅ جاهز للاستخدام
