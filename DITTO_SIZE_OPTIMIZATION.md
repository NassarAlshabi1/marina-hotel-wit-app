# 📦 تحسين حجم التطبيق - Ditto SDK

## التحسينات المُطبّقة

### 1. ✅ استخدام ARM64 فقط
- **قبل:** 4 معماريات (ARM64, ARMv7, x86_64, x86)
- **بعد:** معمارية واحدة (ARM64-v8a)
- **التوفير:** 70% من حجم Ditto binaries

### 2. ✅ ضغط Native Libraries
- تفعيل `useLegacyPackaging = true`
- **التوفير:** 40-50% إضافية

### 3. ✅ App Bundle (AAB) محسّن
- Bundle splits حسب الكثافة والمعمارية
- Google Play يوزع حجم مخصص لكل جهاز

## الأحجام المتوقعة

| النوع | قبل التحسين | بعد التحسين | التوفير |
|-------|-------------|-------------|---------|
| **Release APK** | 25-30 MB | **12-15 MB** | 50-60% |
| **App Bundle** | 20-25 MB | **10-12 MB** | 50-60% |
| **حجم التنزيل (من Play Store)** | 20-25 MB | **8-10 MB** | 60% |

## متطلبات النظام

⚠️ **مهم:** التطبيق الآن يدعم فقط:
- Android 5.0+ (API 21+)
- معمارية ARM64-v8a (معظم الأجهزة من 2015 وما بعد)

### الأجهزة المدعومة:
- ✅ جميع هواتف Android الحديثة (2015+)
- ✅ معظم أجهزة Samsung, Huawei, Xiaomi, Oppo, etc.
- ✅ Google Pixel devices
- ❌ أجهزة x86 (محاكيات قديمة، بعض Chromebooks)
- ⚠️ أجهزة ARMv7 32-bit قديمة (قبل 2015)

## كيفية البناء

### للتوزيع عبر Google Play (موصى به):
```bash
cd mobile
flutter build appbundle --release
```

الملف: `build/app/outputs/bundle/release/app-release.aab`

### للتثبيت المباشر:
```bash
cd mobile
flutter build apk --release --target-platform android-arm64
```

الملف: `build/app/outputs/flutter-apk/app-release.apk`

## التحقق من التوافق

للتحقق من معمارية الجهاز:
```bash
adb shell getprop ro.product.cpu.abi
```

يجب أن يظهر: `arm64-v8a`

## المراجع
- [Ditto Bundle Size Optimization](https://docs.ditto.live/best-practices/optimizing-bundle-sizes-for-android)
- [Android App Bundle](https://developer.android.com/guide/app-bundle)