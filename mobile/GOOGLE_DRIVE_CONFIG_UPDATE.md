# تحديث تكوين Google Drive API

تم تحديث التكوين بنجاح لاستخدام المشروع الجديد:

## التحديثات المطبقة:

### 1. تحديث google-services.json
- **Project ID الجديد**: `aden-flutter`
- **Package Name الجديد**: `com.aden.marina`  
- **OAuth Clients**: تم تكوين 3 OAuth clients بنجاح
- **API Key**: `AIzaSyC-CN6zs4Cr37j2ZPMTYBnhosGC42yt42k`

### 2. تحديث build.gradle
- **namespace**: تم تغييره إلى `com.aden.marina`
- **applicationId**: تم تغييره إلى `com.aden.marina`

### 3. OAuth Clients المُعدة:
1. **Client 1**: للـ Debug keystore 
   - Certificate Hash: `3d915e726608dbbecf373af4e8c2ad2278f49236`
2. **Client 2**: للـ Release keystore
   - Certificate Hash: `711c33d04ba8549d1afdee843fed655b13b2bdd5`
3. **Client 3**: Web OAuth client (نوع 3)

## التأكيد من التكوين:

### ✅ متطلبات مُحققة:
- Google Drive API مُفعل في المشروع
- OAuth 2.0 clients مُعدة للـ Debug والـ Release
- Package names متطابقة في جميع الملفات
- Certificate hashes موجودة (Debug & Release)

### 📋 خطوات الاختبار:

1. **تشغيل التطبيق في وضع Debug:**
```bash
flutter run --debug
```

2. **اختبار تسجيل الدخول في Google Drive:**
   - الذهاب إلى الإعدادات > النسخ الاحتياطي
   - النقر على "تسجيل الدخول" في قسم Google Drive
   - يجب أن تظهر شاشة اختيار حساب Google

3. **اختبار إنشاء نسخة احتياطية:**
   - بعد تسجيل الدخول بنجاح
   - النقر على "إنشاء نسخة احتياطية الآن"
   - متابعة تقدم العملية

### 🔧 في حالة مواجهة مشاكل:

**خطأ في تسجيل الدخول:**
- التأكد من تشغيل التطبيق على نفس keystore المُعد في OAuth client
- للـ Debug: استخدام debug keystore الافتراضي
- للـ Release: استخدام keystore المُعد مسبقاً

**خطأ في صلاحيات Drive:**
- التأكد من تفعيل Google Drive API في Console
- التحقق من Scopes في OAuth consent screen

### 📱 للبناء النهائي (Release):
```bash
# تنظيف المشروع
flutter clean
flutter pub get

# بناء APK
flutter build apk --release

# أو بناء App Bundle
flutter build appbundle --release
```

## حالة التكوين: ✅ جاهز للاختبار

يمكنك الآن اختبار ميزة النسخ الاحتياطي مع Google Drive. جميع التكوينات مُعدة بشكل صحيح ومتطابقة مع google-services.json المُرسل.