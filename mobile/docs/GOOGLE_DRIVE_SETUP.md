# إعداد Google Drive API للنسخ الاحتياطي

## خطوات التكوين المطلوبة:

### 1. إعداد Firebase Console
1. الذهاب إلى [Firebase Console](https://console.firebase.google.com/)
2. اختيار مشروع `ahlan-hotel-manager`
3. الذهاب إلى Authentication > Sign-in method
4. تفعيل Google Sign-in
5. إضافة OAuth client ID للـ Android App

### 2. إعداد Google Cloud Console
1. الذهاب إلى [Google Cloud Console](https://console.cloud.google.com/)
2. اختيار نفس المشروع
3. تفعيل Google Drive API:
   - الذهاب إلى APIs & Services > Library
   - البحث عن "Google Drive API"
   - النقر على Enable

### 3. إنشاء OAuth 2.0 Client ID
1. الذهاب إلى APIs & Services > Credentials
2. النقر على "Create Credentials" > "OAuth 2.0 Client ID"
3. اختيار "Android" كنوع التطبيق
4. تعبئة البيانات:
   - Name: Marina Hotel Android
   - Package name: `com.sky.marina.firebase`
   - SHA-1 certificate fingerprint: (يمكن الحصول عليه من Android Studio أو keystore)

### 4. تحديث google-services.json
بعد إنشاء OAuth client، سيتم تحديث google-services.json تلقائياً لتشمل:

```json
"oauth_client": [
  {
    "client_id": "YOUR_CLIENT_ID_HERE.apps.googleusercontent.com",
    "client_type": 1,
    "android_info": {
      "package_name": "com.sky.marina.firebase",
      "certificate_hash": "SHA1_HASH_HERE"
    }
  }
]
```

### 5. الحصول على SHA-1 Certificate Fingerprint

#### من Android Studio:
1. فتح Terminal في Android Studio
2. تشغيل:
```bash
./gradlew signingReport
```

#### من Keystore (للإصدار النهائي):
```bash
keytool -list -v -keystore /path/to/marina-hotel-keystore.jks -alias marina-hotel
```

### 6. اختبار التكامل
بعد التكوين، يمكن اختبار:
1. تسجيل الدخول في Google Drive
2. إنشاء نسخة احتياطية
3. عرض قائمة النسخ المتاحة
4. استعادة نسخة احتياطية
5. تفعيل النسخ التلقائي

### 7. Scopes المطلوبة
التطبيق يستخدم الـ scope التالي:
- `https://www.googleapis.com/auth/drive.file`: للوصول فقط للملفات التي ينشئها التطبيق

### 8. هيكل النسخة الاحتياطية
```json
{
  "metadata": {
    "app_version": "1.2.0+3",
    "database_version": 3,
    "backup_timestamp": "2025-10-22T14:30:00Z",
    "total_records": 1250,
    "device_info": "Android"
  },
  "rooms": [...],
  "bookings": [...],
  "booking_notes": [...],
  "employees": [...],
  "expenses": [...],
  "cash_transactions": [...],
  "payments": [...],
  "sync_state": {...}
}
```

### 9. ملاحظات مهمة
- جدول `Outbox` لا يتم نسخه لأنه للتتبع المؤقت فقط
- البيانات الحساسة مثل كلمات المرور لا يتم حفظها في النسخ الاحتياطية
- النسخ التلقائي يعمل فقط عند توفر اتصال بالإنترنت
- يتطلب تسجيل دخول نشط في Google Drive

### 10. استكشاف الأخطاء
- التأكد من تطابق package name في google-services.json مع build.gradle
- التأكد من صحة SHA-1 fingerprint
- التحقق من تفعيل Google Drive API
- فحص صلاحيات المستخدم في Google Drive