# 📨 سكريبتات Appwrite Messaging — فندق مارينا

سكريبتات لإعداد واختبار Appwrite Messaging بدلاً من FCM المباشر.

## 📁 الملفات

| الملف | الوظيفة |
|---|---|
| `setup_messaging.js` | إعداد Messaging: فحص، إنشاء Topics، إرسال اختبار |
| `test_messaging.js` | اختبار شامل (config, providers, devices, send, delivery) |
| `package.json` | التبعيات |

## 🚀 البدء السريع

### 1. تثبيت التبعيات

```bash
cd scripts/messaging
npm install
```

### 2. تعيين متغيرات البيئة

```bash
export APPWRITE_ENDPOINT="https://fra.cloud.appwrite.io/v1"
export APPWRITE_PROJECT_ID="6a2b01d0000752ce97e7"
export APPWRITE_API_KEY="standard_your_key_here"
export APPWRITE_DATABASE_ID="6a2b030d000445596163"
export APPWRITE_DEVICES_COLLECTION="devices"
export APPWRITE_MESSAGING_PROVIDER_ID="fcm"
```

### 3. فحص الحالة

```bash
node setup_messaging.js --check
```

يعرض:
- Providers المُفعّلة
- Topics الموجودة
- آخر الرسائل
- عدد الأجهزة المسجّلة

### 4. إنشاء Topics

```bash
node setup_messaging.js --topics
```

ينشئ 6 Topics:
- `bookings_updates`
- `payments_updates`
- `expenses_updates`
- `rooms_updates`
- `staff_alerts`
- `sync_events`

### 5. اختبار شامل

```bash
node test_messaging.js
```

ينفّذ:
- فحص الإعدادات
- فحص Providers
- قراءة الأجهزة
- اختبار إنشاء Target
- إرسال رسالة فعلية
- فحص حالة التسليم
- تقرير نهائي

### 6. إرسال اختبار سريع

```bash
node setup_messaging.js --test
```

### 7. إحصائيات مفصّلة

```bash
node setup_messaging.js --status
```

## 📋 المتطلبات المسبقة

قبل تشغيل السكريبتات، تأكد من:

1. ✅ تفعيل Messaging في Appwrite Console
2. ✅ إضافة FCM Provider (برفع serviceAccount.json)
3. ✅ إنشاء API Key بصلاحيات:
   - `messaging.read`
   - `messaging.write`
   - `databases.read`
4. ✅ تشغيل التطبيق مرة واحدة على الأقل لتسجيل جهاز

راجع الدليل الكامل: `docs/APPWRITE_MESSAGING_SETUP.md`

## 🔧 استكشاف الأخطاء

### `missing scope: messaging.read`

API Key يحتاج صلاحية `messaging.read`. أعد إنشائه من Console.

### `missing scope: messaging.write`

API Key يحتاج صلاحية `messaging.write`. أعد إنشائه من Console.

### `No providers found`

اذهب إلى Console → Messaging → Providers → Enable FCM.

### `No devices registered`

شغّل التطبيق على جهاز حقيقي مرة واحدة ليسجّل الجهاز في collection `devices`.

### `Provider ID not set`

اضبط `APPWRITE_MESSAGING_PROVIDER_ID` — اذهب إلى Console → Messaging → Providers لمعرفة الـ ID.
