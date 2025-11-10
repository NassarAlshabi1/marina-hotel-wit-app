# دليل إعداد Ditto Cloud للتطبيق

## 📋 نظرة عامة

Ditto هو نظام قاعدة بيانات موزعة تعمل بدون اتصال (offline-first) وتدعم المزامنة في الوقت الفعلي بين الأجهزة المختلفة. يتيح لك Ditto:

- **المزامنة التلقائية**: تزامن البيانات تلقائياً عبر جميع الأجهزة
- **العمل بدون اتصال**: يعمل التطبيق بشكل كامل بدون إنترنت
- **استعلامات DQL**: لغة استعلام قوية مشابهة لـ SQL
- **نقل متعدد**: Bluetooth LE, WiFi, LAN, Cloud

---

## 🚀 الخطوة 1: إنشاء حساب Ditto

1. افتح المتصفح وانتقل إلى: **https://portal.ditto.live**
2. انقر على **Sign Up** لإنشاء حساب جديد
3. أدخل معلوماتك وأكمل التسجيل
4. تحقق من بريدك الإلكتروني وفعّل الحساب

---

## 📱 الخطوة 2: إنشاء تطبيق جديد

1. بعد تسجيل الدخول، انقر على **Create New App**
2. أدخل اسم التطبيق: `Marina Hotel`
3. اختر نوع التطبيق:
   - للتطوير: **Online Playground** (مجاني، سهل الإعداد)
   - للإنتاج: **Production** (يتطلب اشتراك مدفوع)

---

## 🔑 الخطوة 3: الحصول على بيانات الاعتماد

بعد إنشاء التطبيق، ستحصل على:

### للتطوير (Online Playground):
- **App ID**: معرف فريد للتطبيق (مثل: `670a1b2c3d4e5f6789abcdef`)
- **Playground Token**: مفتاح الوصول (مثل: `your-playground-token-here`)

### للإنتاج (Production):
- **App ID**: معرف التطبيق
- **License Token**: مفتاح الترخيص

---

## ⚙️ الخطوة 4: إعداد التطبيق

### الطريقة 1: تحديث ملف `env.dart` (موصى به للتطوير)

افتح الملف: `/mobile/lib/utils/env.dart`

```dart
class Env {
  // ... بقية الإعدادات ...
  
  // Ditto Cloud Configuration
  static String dittoAppId = const String.fromEnvironment(
    'DITTO_APP_ID',
    defaultValue: '670a1b2c3d4e5f6789abcdef', // 👈 ضع App ID هنا
  );
  
  static String dittoPlaygroundToken = const String.fromEnvironment(
    'DITTO_PLAYGROUND_TOKEN',
    defaultValue: 'your-playground-token-here', // 👈 ضع Token هنا
  );
  
  static bool dittoUsePlayground = const bool.fromEnvironment(
    'DITTO_USE_PLAYGROUND',
    defaultValue: true, // true للتطوير، false للإنتاج
  );
}
```

### الطريقة 2: استخدام Environment Variables (موصى به للإنتاج)

عند بناء التطبيق، مرر المتغيرات:

```bash
# للتطوير
flutter run \
  --dart-define=DITTO_APP_ID=your_app_id_here \
  --dart-define=DITTO_PLAYGROUND_TOKEN=your_token_here \
  --dart-define=DITTO_USE_PLAYGROUND=true

# للإنتاج
flutter build apk \
  --dart-define=DITTO_APP_ID=your_app_id_here \
  --dart-define=DITTO_LICENSE_TOKEN=your_license_here \
  --dart-define=DITTO_USE_PLAYGROUND=false
```

---

## 📦 الخطوة 5: تثبيت المكتبات

قم بتحديث المكتبات:

```bash
cd mobile
flutter pub get
```

إذا ظهرت أخطاء تتعلق بـ Ditto SDK:
```bash
flutter clean
flutter pub get
```

---

## 🔧 الخطوة 6: إعدادات Android (مطلوبة)

### 1. تحديث `AndroidManifest.xml`

افتح: `/mobile/android/app/src/main/AndroidManifest.xml`

أضف الأذونات التالية داخل `<manifest>`:

```xml
<!-- Ditto Permissions -->
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

<!-- Android 12+ Bluetooth Permissions -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
```

### 2. تحديث `build.gradle`

افتح: `/mobile/android/app/build.gradle`

تأكد من أن `minSdkVersion` لا يقل عن 21:

```gradle
android {
    defaultConfig {
        minSdkVersion 21  // أو أعلى
        targetSdkVersion 33
    }
}
```

---

## 🍎 الخطوة 7: إعدادات iOS (إذا كنت تستهدف iOS)

### تحديث `Info.plist`

افتح: `/mobile/ios/Runner/Info.plist`

أضف:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>يستخدم التطبيق Bluetooth للمزامنة مع الأجهزة القريبة</string>

<key>NSBluetoothPeripheralUsageDescription</key>
<string>يستخدم التطبيق Bluetooth للمزامنة مع الأجهزة القريبة</string>

<key>NSLocalNetworkUsageDescription</key>
<string>يستخدم التطبيق الشبكة المحلية للمزامنة</string>

<key>NSBonjourServices</key>
<array>
    <string>_ditto._tcp</string>
</array>
```

---

## 🧪 الخطوة 8: اختبار التكامل

### 1. تشغيل التطبيق

```bash
cd mobile
flutter run
```

### 2. الوصول إلى شاشة Ditto Management

1. سجل دخول إلى التطبيق
2. من القائمة الجانبية، اختر **إدارة Ditto Cloud Sync**
3. انقر على **تهيئة Ditto**
4. يجب أن ترى رسالة: ✅ تم تهيئة Ditto بنجاح

### 3. اختبار الاستعلام المخصص

1. في قسم "الحجوزات ذات القيمة العالية"
2. أدخل مبلغ (مثلاً: 500)
3. انقر على "بحث"
4. ستظهر النتائج من قاعدة البيانات

---

## 📊 الخطوة 9: إعداد المجموعات (Collections)

في Ditto Portal، أنشئ المجموعات التالية:

### 1. Collection: `bookings`
```json
{
  "_id": "string",
  "room_number": "string",
  "guest_name": "string",
  "guest_phone": "string",
  "check_in_date": "string",
  "check_out_date": "string",
  "total_amount": "number",
  "status": "string",
  "created_at": "string",
  "updated_at": "string"
}
```

### 2. Collection: `rooms`
```json
{
  "_id": "string",
  "room_number": "string",
  "floor": "number",
  "room_type": "string",
  "status": "string",
  "price_per_night": "number"
}
```

### 3. Collection: `guests`
```json
{
  "_id": "string",
  "name": "string",
  "phone": "string",
  "email": "string",
  "national_id": "string"
}
```

---

## 🔍 استكشاف الأخطاء

### مشكلة: "Ditto غير مُعد بشكل صحيح"

**الحل:**
- تأكد من إدخال App ID و Playground Token بشكل صحيح
- تحقق من عدم وجود مسافات زائدة
- تأكد من أن القيم ليست القيم الافتراضية

### مشكلة: "فشل في تهيئة Ditto"

**الحل:**
- تحقق من اتصال الإنترنت
- تأكد من صلاحية Token
- راجع سجلات التصحيح في Android Studio/Xcode

### مشكلة: "لا توجد أذونات Bluetooth"

**الحل:**
- تأكد من إضافة الأذونات في AndroidManifest.xml
- على Android 12+، اطلب الأذونات في وقت التشغيل

### مشكلة: "لا توجد بيانات في الاستعلام"

**الحل:**
- تأكد من وجود بيانات في Collection على Ditto Portal
- جرب المزامنة القوية من الشاشة
- تحقق من أن اسم Collection صحيح

---

## 🎯 الميزات المتقدمة

### 1. تفعيل/تعطيل وسائل النقل

في `/mobile/lib/utils/ditto_config.dart`:

```dart
// تعطيل Bluetooth LE
static bool enableBluetoothLE = false;

// تعطيل المزامنة السحابية
static bool enableCloud = false;
```

### 2. سجلات التصحيح

```dart
// تفعيل السجلات التفصيلية
static bool enableDebugLogging = true;
```

### 3. مراقبة الأجهزة المتصلة

في الكود:
```dart
final service = DittoCloudSyncService();
final deviceInfo = await service.getDeviceInfo();
print('Connected peers: ${deviceInfo['peersCount']}');
```

---

## 📚 موارد إضافية

- **الوثائق الرسمية**: https://docs.ditto.live
- **Flutter SDK Guide**: https://docs.ditto.live/flutter/
- **DQL Reference**: https://docs.ditto.live/dql/
- **Community Forum**: https://community.ditto.live

---

## ✅ قائمة التحقق النهائية

- [ ] تم إنشاء حساب على Ditto Portal
- [ ] تم إنشاء تطبيق والحصول على App ID و Token
- [ ] تم تحديث ملف env.dart بالبيانات الصحيحة
- [ ] تم إضافة أذونات Android في AndroidManifest.xml
- [ ] تم تشغيل `flutter pub get`
- [ ] تم اختبار تهيئة Ditto في التطبيق
- [ ] تم اختبار الاستعلام المخصص
- [ ] تم التحقق من المزامنة بين جهازين

---

## 🆘 الدعم

إذا واجهت أي مشاكل:
1. راجع سجلات التطبيق: `flutter logs`
2. تحقق من Ditto Portal لمعرفة الأجهزة المتصلة
3. راجع الوثائق الرسمية
4. اتصل بفريق الدعم الفني

---

**تم إعداد هذا الدليل لمشروع Marina Hotel**
**التاريخ**: نوفمبر 2024
**الإصدار**: 1.0.0
