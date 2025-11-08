# تعليمات البناء السريع 🚀

## بناء APK محسّن (Release)

```bash
cd mobile

# 1. تنظيف المشروع
flutter clean

# 2. تحميل المكتبات
flutter pub get

# 3. بناء APK (split per ABI - أصغر حجم)
flutter build apk --release --split-per-abi
```

## التحقق من النتائج

```bash
# عرض أحجام APK المُنتجة
ls -lh build/app/outputs/flutter-apk/
```

**سترى ثلاثة ملفات:**
- `app-armeabi-v7a-release.apk` - للأجهزة القديمة (32-bit ARM)
- `app-arm64-v8a-release.apk` - للأجهزة الحديثة (64-bit ARM) ⭐ الأكثر استخداماً
- `app-x86_64-release.apk` - للمحاكيات والأجهزة x86

**للنشر:** استخدم `app-arm64-v8a-release.apk` (الأكثر شيوعاً)

## بناء APK واحد (Universal)

إذا كنت تريد APK واحد يعمل على جميع الأجهزة:

```bash
flutter build apk --release
```

**ملاحظة:** الحجم سيكون أكبر (يحتوي على جميع architectures)

## اختبار الأداء

### 1. قياس وقت البدء
- افتح التطبيق من حالة مغلقة
- قس الوقت من النقر حتى ظهور Login
- **المتوقع:** أقل من 2 ثانية ⚡

### 2. اختبار المزامنة
- سجّل الدخول
- أضف بيانات جديدة
- تحقق من المزامنة مع Supabase

### 3. اختبار Google Drive
- انتقل إلى الإعدادات → النسخ الاحتياطي
- جرّب إنشاء نسخة احتياطية
- تحقق من ظهورها في Google Drive

## مراقبة Logs

```bash
# عرض logs التطبيق فقط
adb logcat | grep -E "(✅|❌|⚠️|🔄|Marina)"
```

**يجب أن ترى:**
```
🔄 بدء تهيئة الخدمات الخلفية...
✅ تم تهيئة الخدمات الخلفية بنجاح
✅ تم تفعيل Realtime Subscriptions
```

## استكشاف الأخطاء

### مشكلة: التطبيق لا يعمل بعد البناء

1. **تحقق من ProGuard logs:**
```bash
cat mobile/build/app/outputs/mapping/release/usage.txt
```

2. **راجع قواعد ProGuard:**
```bash
cat mobile/android/app/proguard-rules.pro
```

### مشكلة: Google Drive لا يعمل

- تأكد من SHA-1 fingerprint في Google Cloud Console
- تحقق من `google-services.json`

### مشكلة: النسخ الاحتياطي التلقائي لا يعمل

- تحقق من أن WorkManager مُفعّل
- راجع logs للتأكد من تشغيل `AutoBackupTask`

## معلومات إضافية

راجع `PERFORMANCE_OPTIMIZATION.md` للتفاصيل الكاملة عن التحسينات.
