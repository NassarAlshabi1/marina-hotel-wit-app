# دليل إعداد Firebase Cloud Messaging (FCM)

## الخطوة 1: إنشاء مشروع Firebase

1. افتح [Firebase Console](https://console.firebase.google.com)
2. اضغط على **Create a project** أو **Add project**
3. أدخل اسم المشروع: `Marina Hotel`
4. اختر إذا كنت تريد Google Analytics (اختياري)
5. اضغط **Create project**
6. انتظر حتى يتم إنشاء المشروع

---

## الخطوة 2: إضافة تطبيق Android

1. في صفحة المشروع، اضغط على أيقونة **Android** 🤖
2. املأ البيانات:
   - **Android package name:** `com.aden.marina`
   - **App nickname:** `Marina Hotel` (اختياري)
   - **Debug signing certificate SHA-1:** `67:12:57:A2:9B:53:FA:71:AC:BC:0F:A8:C9:54:2F:3F:46:0B:A8:1C`
3. اضغط **Register app**

---

## الخطوة 3: تحميل google-services.json

1. اضغط **Download google-services.json**
2. احفظ الملف
3. ضع الملف في المسار:
   ```
   mobile/android/app/google-services.json
   ```

---

## الخطوة 4: الحصول على Server Key

1. في Firebase Console، اذهب إلى **Project Settings** (أيقونة الترس ⚙️)
2. اختر تبويب **Cloud Messaging**
3. في قسم **Cloud Messaging API (V1)**:
   - إذا كان معطل، اضغط **Enable** (سيفتح Google Cloud Console)
   - فعّل الـ API واضغط Enable
4. ارجع لـ Firebase Console
5. في قسم **Server key** انسخ المفتاح (يبدأ بـ `AAAA...`)

> **ملاحظة:** إذا لم تجد Server key، استخدم **Service Account**:
> - Project Settings → Service accounts
> - Generate new private key
> - حمّل ملف JSON

---

## الخطوة 5: إعداد ملفات Android

### 5.1 تعديل `mobile/android/build.gradle`

أضف في قسم `buildscript > dependencies`:
```gradle
buildscript {
    dependencies {
        // ... existing dependencies
        classpath 'com.google.gms:google-services:4.4.0'
    }
}
```

### 5.2 تعديل `mobile/android/app/build.gradle`

أضف في نهاية الملف:
```gradle
apply plugin: 'com.google.gms.google-services'
```

---

## الخطوة 6: إضافة مكتبات Flutter

أضف في `mobile/pubspec.yaml`:
```yaml
dependencies:
  firebase_core: ^2.24.2
  firebase_messaging: ^14.7.10
```

ثم شغّل:
```bash
cd mobile
flutter pub get
```

---

## الخطوة 7: تهيئة Firebase في التطبيق

### 7.1 إنشاء ملف `lib/services/fcm_service.dart`:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  String? _fcmToken;

  String? get fcmToken => _fcmToken;

  Future<void> initialize() async {
    await Firebase.initializeApp();

    // طلب إذن الإشعارات
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    debugPrint('📱 FCM Permission: ${settings.authorizationStatus}');

    // الحصول على Token
    _fcmToken = await _messaging.getToken();
    debugPrint('📱 FCM Token: $_fcmToken');

    // الاستماع للرسائل عندما التطبيق مفتوح
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // الاستماع عند الضغط على الإشعار
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    // تحديث Token عند تغييره
    _messaging.onTokenRefresh.listen((token) {
      _fcmToken = token;
      debugPrint('📱 FCM Token refreshed: $token');
      // TODO: أرسل Token الجديد للسيرفر
    });
  }

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('📩 Foreground message: ${message.notification?.title}');
    // TODO: عرض إشعار محلي أو تحديث UI
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('📩 Message opened app: ${message.data}');
    // TODO: التنقل للصفحة المطلوبة
  }

  // الاشتراك في موضوع (لإرسال إشعارات جماعية)
  Future<void> subscribeToTopic(String topic) async {
    await _messaging.subscribeToTopic(topic);
    debugPrint('📱 Subscribed to topic: $topic');
  }

  // إلغاء الاشتراك
  Future<void> unsubscribeFromTopic(String topic) async {
    await _messaging.unsubscribeFromTopic(topic);
    debugPrint('📱 Unsubscribed from topic: $topic');
  }
}
```

### 7.2 تعديل `main.dart`:

```dart
import 'services/fcm_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // تهيئة FCM
  await FCMService().initialize();
  
  // ... باقي الكود
  runApp(const ProviderScope(child: App()));
}
```

---

## الخطوة 8: إنشاء Appwrite Function للإشعارات

### 8.1 إنشاء المجلد:
```
appwrite/
└── functions/
    └── send-notification/
        ├── package.json
        └── src/
            └── main.js
```

### 8.2 ملف `package.json`:
```json
{
  "name": "send-notification",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "node-appwrite": "^12.0.0",
    "firebase-admin": "^12.0.0"
  }
}
```

### 8.3 ملف `src/main.js`:
```javascript
import { Client, Databases, Query } from 'node-appwrite';
import admin from 'firebase-admin';

// تهيئة Firebase Admin
const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

export default async ({ req, res, log, error }) => {
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const databases = new Databases(client);

  try {
    const event = req.headers['x-appwrite-event'];
    const payload = req.body;

    if (!event || !payload) {
      return res.json({ success: false, message: 'No event' });
    }

    // تحديد نوع الحدث والـ collection
    const eventParts = event.split('.');
    const collection = eventParts[3];
    const eventType = eventParts[5]; // create, update, delete

    // تحديد عنوان ومحتوى الإشعار
    let title, body;
    switch (collection) {
      case 'bookings':
        title = 'حجز جديد';
        body = `حجز جديد للغرفة ${payload.roomNumber}`;
        break;
      case 'payments':
        title = 'دفعة جديدة';
        body = `تم استلام دفعة بقيمة ${payload.amount}`;
        break;
      default:
        title = 'تحديث';
        body = `تم تحديث ${collection}`;
    }

    // جلب جميع أجهزة المستخدمين
    const devices = await databases.listDocuments(
      process.env.APPWRITE_DATABASE_ID,
      'devices',
      [Query.isNotNull('fcmToken')]
    );

    // إرسال الإشعار لجميع الأجهزة
    const tokens = devices.documents
      .map(d => d.fcmToken)
      .filter(t => t && t !== payload.device_id);

    if (tokens.length === 0) {
      return res.json({ success: true, message: 'No devices to notify' });
    }

    const message = {
      notification: { title, body },
      data: {
        collection,
        documentId: payload.$id,
        eventType,
      },
      tokens,
    };

    const response = await admin.messaging().sendEachForMulticast(message);
    log(`Sent ${response.successCount}/${tokens.length} notifications`);

    return res.json({
      success: true,
      sent: response.successCount,
      failed: response.failureCount,
    });
  } catch (err) {
    error(`Error: ${err.message}`);
    return res.json({ success: false, error: err.message }, 500);
  }
};
```

---

## الخطوة 9: إعداد Appwrite Function

### 9.1 ملف `appwrite/appwrite.json`:
```json
{
  "projectId": "690ff0da0025518570c1",
  "functions": [
    {
      "name": "send-notification",
      "id": "send-notification",
      "runtime": "node-18.0",
      "path": "functions/send-notification",
      "entrypoint": "src/main.js",
      "events": [
        "databases.*.collections.bookings.documents.*",
        "databases.*.collections.payments.documents.*"
      ],
      "timeout": 15,
      "enabled": true
    }
  ]
}
```

### 9.2 Environment Variables في Appwrite Console:
```
APPWRITE_API_KEY=your-appwrite-api-key
APPWRITE_DATABASE_ID=hotel_db
FIREBASE_SERVICE_ACCOUNT={"type":"service_account",...}
```

### 9.3 Deploy:
```bash
npm install -g appwrite-cli
appwrite login
cd appwrite
appwrite deploy function
```

---

## الخطوة 10: تحديث جدول devices

أضف حقل `fcmToken` لجدول `devices` في Appwrite:
- **Key:** `fcmToken`
- **Type:** String
- **Size:** 500
- **Required:** No

---

## الخطوة 11: حفظ FCM Token

عند تسجيل الجهاز، احفظ الـ FCM Token:

```dart
// في التطبيق بعد التسجيل
final fcmToken = FCMService().fcmToken;
await appwriteService.updateDocument(
  'devices',
  deviceId,
  {'fcmToken': fcmToken},
);
```

---

## اختبار الإشعارات

1. شغّل التطبيق على جهازين
2. أنشئ حجز من الجهاز الأول
3. يجب أن يصل إشعار للجهاز الثاني

---

## ملخص الملفات المطلوبة

| الملف | الموقع |
|-------|--------|
| google-services.json | mobile/android/app/ |
| Firebase Service Account | Appwrite Function Environment |
| fcm_service.dart | mobile/lib/services/ |
| Appwrite Function | appwrite/functions/send-notification/ |

---

## روابط مفيدة

- [Firebase Console](https://console.firebase.google.com)
- [FCM Documentation](https://firebase.google.com/docs/cloud-messaging)
- [Appwrite Functions](https://appwrite.io/docs/products/functions)
