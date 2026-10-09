# 📨 دليل ضبط Appwrite Messaging — فندق مارينا

> **الهدف:** استبدال نظام FCM المباشر (Legacy Server Key + Firebase Admin SDK منفصل) بخدمة **Appwrite Messaging** المدمجة، التي تُدير الأجهزة والإشعارات من مكان واحد في Appwrite Console.

**تاريخ الإنشاء:** 2026-07-15
**المشروع:** `6a2b01d0000752ce97e7`
**قاعدة البيانات:** `6a2b030d000445596163`

---

## 🎯 لماذا Appwrite Messaging؟

| الميزة | النظام القديم (FCM مباشر) | Appwrite Messaging |
|---|---|---|
| **إدارة الأجهزة** | يدوي في collection `devices` | تلقائي عبر Targets API |
| **إرسال الإشعارات** | Firebase Admin SDK في Function | Messaging API مباشرة |
| **واجهة إدارة** | لا توجد | UI كامل في Console |
| **Topics** | لا يدعم | يدعم Topics و Users و Targets |
| **سجل التسليم** | لا يوجد | Logs مفصّلة لكل رسالة |
| **الأمان** | Server Key في التطبيق | بدون مفاتيح في التطبيق |
| **عدد Functions** | Function + Firebase Admin | Function واحدة فقط |

---

## 📋 المتطلبات المسبقة

1. ✅ حساب Appwrite Cloud مع مشروع `6a2b01d0000752ce97e7`
2. ✅ Firebase Project `aden-flutter` مُفعّل فيه Cloud Messaging
3. ✅ Service Account JSON من Firebase Console
4. ✅ صلاحيات Admin على Appwrite Project

---

## 🚀 خطوات الضبط

### الخطوة 1: تفعيل Messaging في Appwrite Console

1. اذهب إلى: https://fra.cloud.appwrite.io/console/project-6a2b01d0000752ce97e7/messaging
2. إذا ظهر زر **"Enable Messaging"** اضغط عليه
3. انتظر حتى يكتمل التفعيل (يستغرق ~30 ثانية)

---

### الخطوة 2: إضافة FCM Provider (للأندرويد)

Appwrite Messaging يحتاج ربط مع Firebase Cloud Messaging لإرسال لأجهزة Android.

#### 2.1 احصل على Service Account JSON

1. اذهب إلى [Firebase Console](https://console.firebase.google.com) → `aden-flutter`
2. **⚙️ Project Settings → Service Accounts**
3. اضغط **"Generate new private key"** → يُنزّل ملف JSON
4. افتح الملف — ستحتاج منه:
   - `project_id`
   - `client_email`
   - `private_key` (يحتوي على `\n` escapes)
   - **أو** رفع الملف JSON كاملاً

#### 2.2 أضف Provider في Appwrite

1. في Appwrite Console → **Messaging → Providers**
2. اضغط **FCM** → **Enable**
3. اختر طريقة المصادقة:
   - **Option A (مُوصى به):** ارفع ملف `serviceAccount.json` كاملاً
   - **Option B:** أدخل الحقول يدوياً (project_id, client_email, private_key)
4. اضغط **Save**
5. ✅ ستظهر حالة Provider كـ "Active"

---

### الخطوة 3: إضافة APNs Provider (للـ iOS — اختياري)

1. في Messaging → **Providers → APNs**
2. اضغط **Enable**
3. ارفع ملف `.p8` من Apple Developer Console
4. أدخل:
   - **Key ID**
   - **Team ID**
   - **Bundle ID** (مثل `com.aden.marina`)
5. اضغط **Save**

---

### الخطوة 4: إنشاء Topics للجداول الرئيسية

Topics تُتيح إرسال إشعارات لمجموعات محددة (مثلاً: موظفي الاستقبال فقط).

1. اذهب إلى **Messaging → Topics**
2. أنشئ المواضيع التالية:

| Topic ID | الاسم | الوصف |
|---|---|---|
| `bookings_updates` | تحديثات الحجوزات | إشعارات إنشاء/تعديل/حذف الحجوزات |
| `payments_updates` | تحديثات الدفعات | إشعارات الدفعات الجديدة |
| `expenses_updates` | تحديثات المصروفات | إشعارات المصروفات |
| `rooms_updates` | تحديثات الغرف | إشعارات حالة الغرف |
| `staff_alerts` | تنبيهات الموظفين | تنبيهات عاجلة |
| `sync_events` | أحداث المزامنة | إشعارات المزامنة العامة |

> **ملاحظة:** الـ Topic ID يجب أن يكون lowercase وحروف/أرقام/شرطات سفلية فقط.

---

### الخطوة 5: إنشاء API Key للمessaging

1. اذهب إلى **Overview → API Keys**
2. اضغط **Create API Key**
3. الاسم: `messaging-function-key`
4. الصلاحيات المطلوبة:
   - ✅ `messaging.read`
   - ✅ `messaging.write`
   - ✅ `databases.read` (لقراءة devices)
5. انسخ المفتاح — يبدأ بـ `standard_`

---

### الخطوة 6: نشر Appwrite Function الجديدة `messaging-notifier`

#### 6.1 ارفع الكود

```bash
cd /home/z/my-project/marina-hotel-wit-app/functions/messaging-notifier
npm install
# اضغط الكود يدوياً عبر Console أو استخدم Appwrite CLI:
appwrite functions create \
  --function-id=messaging-notifier \
  --name="Messaging Notifier" \
  --runtime=node-18.0 \
  --entrypoint=src/main.js
```

#### 6.2 عيّن متغيرات البيئة

في Console → Functions → `messaging-notifier` → Settings → Variables:

| المتغير | القيمة |
|---|---|
| `APPWRITE_ENDPOINT` | `https://fra.cloud.appwrite.io/v1` |
| `APPWRITE_FUNCTION_PROJECT_ID` | `6a2b01d0000752ce97e7` |
| `APPWRITE_API_KEY` | (المفتاح من الخطوة 5) |
| `APPWRITE_DATABASE_ID` | `6a2b030d000445596163` |
| `APPWRITE_DEVICES_COLLECTION` | `devices` |
| `APPWRITE_MESSAGING_PROVIDER_ID` | (يظهر بعد تفعيل FCM في الخطوة 2) |

> ⚠️ **لا حاجة لمتغيرات Firebase** — Appwrite Messaging يديرها بنفسه!

#### 6.3 اربط الأحداث (Events)

في Function → Settings → Events، أضف:

```
databases.6a2b030d000445596163.tables.bookings.rows.*.create
databases.6a2b030d000445596163.tables.bookings.rows.*.update
databases.6a2b030d000445596163.tables.bookings.rows.*.delete
databases.6a2b030d000445596163.tables.payments.rows.*.create
databases.6a2b030d000445596163.tables.payments.rows.*.update
databases.6a2b030d000445596163.tables.expenses.rows.*.create
databases.6a2b030d000445596163.tables.expenses.rows.*.update
databases.6a2b030d000445596163.tables.debtS.rows.*.create
databases.6a2b030d000445596163.tables.rooms.rows.*.update
```

---

### الخطوة 7: تحديث التطبيق Flutter

#### 7.1 تحديث `pubspec.yaml`

لا حاجة لإضافة packages جديدة — `appwrite: ^21.0.0` يدعم Messaging.

#### 7.2 تسجيل الجهاز في Appwrite Messaging

في `main.dart` بعد تهيئة Firebase:

```dart
import 'services/appwrite_messaging_service.dart';

// بعد FCM initialization:
final messagingService = AppwriteMessagingService();
await messagingService.initialize();
await messagingService.registerDevice();
await messagingService.subscribeToTopics([
  'bookings_updates',
  'payments_updates',
  'sync_events',
]);
```

#### 7.3 استقبال الإشعارات

`AppwriteMessagingService` يستقبل الإشعارات عبر **Appwrite Realtime** (WebSocket) بدلاً من FCM المباشر، مما يُتيح:

- ✅ عرض الإشعار في الـ foreground
- ✅ تشغيل المزامنة فوراً
- ✅ تحديث الـ UI

---

### الخطوة 8: اختبار الإرسال

#### 8.1 اختبار يدوي من Console

1. اذهب إلى **Messaging → Messages → Create Message**
2. اكتب عنوان ونص
3. اختر **Targets**: Users أو Topics
4. اضغط **Send**
5. تحقق من Logs

#### 8.2 اختبار آلي

```bash
cd /home/z/my-project/marina-hotel-wit-app/scripts/appwrite
node test_messaging.js
```

سيُرسل إشعار تجريبي لكل الأجهزة المسجّلة ويُظهر النتائج.

---

## 🔄 الترحيل من النظام القديم

### استراتيجية الترحيل التدريجي

```
المرحلة 1: تشغيل النظامين معاً (الأسبوع 1)
  - FCM المباشر: يعمل كـ fallback
  - Appwrite Messaging: يعمل بالتوازي
  - مراقبة Logs للتأكد من وصول الإشعارات

المرحلة 2: تعطيل FcmSender القديم (الأسبوع 2)
  - تعطيل fcm_sender.dart عبر Env
  - الاعتماد على Appwrite Messaging فقط

المرحلة 3: إزالة الكود القديم (الأسبوع 3)
  - حذف fcm_sender.dart
  - إزالة FCM_SERVER_KEY من env
  - تحديث دليل الإعداد
```

### الملفات المتأثرة

| الملف | الإجراء |
|---|---|
| `lib/services/fcm_sender.dart` | تعطيل ثم حذف |
| `lib/services/fcm_service.dart` | إبقاء جزء الاستقبال، تعطيل الإرسال |
| `lib/services/appwrite_messaging_service.dart` | جديد — الخدمة الرئيسية |
| `functions/fcm-notifier/` | إيقاف ثم حذف |
| `functions/messaging-notifier/` | جديد — Function رئيسية |

---

## 🛠️ استكشاف الأخطاء

### الإشعارات لا تصل

1. **تحقق من Provider** في Messaging → Providers
   - FCM: يجب أن يكون "Active"
2. **تحقق من Targets** في Messaging → Targets
   - الجهاز مُسجّل؟
   - الـ Token صحيح؟
3. **تحقق من Logs** في Messaging → Messages
   - حالة التسليم لكل target
4. **تحقق من Function Logs**
   - هل الـ Function تعمل؟
   - هل استدعت Messaging API بنجاح؟

### خطأ "Provider not configured"

```
Error: No FCM provider found
```

**الحل:** أعد تنفيذ الخطوة 2 — تأكد من رفع serviceAccount.json صحيح.

### خطأ "Target not found"

```
Error: No targets registered
```

**الحل:**
1. تأكد من تفعيل `AppwriteMessagingService.registerDevice()` في التطبيق
2. تحقق من إذن الإشعارات على الجهاز
3. أعد تشغيل التطبيق

### الإشعارات تتأخر

Appwrite Messaging يستخدم FCM بشكل داخلي، لكن قد يضيف ~1-2 ثانية. إذا كانت التأخيرات أكبر:

1. تحقق من Network Latency
2. فعّل `priority: 'high'` في إعدادات Message
3. استخدم Topics بدلاً من Individual Targets (أسرع)

---

## 📊 مراقبة الأداء

### مؤشرات مهمة في Console

1. **Messaging → Dashboard**
   - عدد الرسائل المُرسلة
   - معدل التسليم الناجح
   - متوسط زمن التسليم

2. **Messaging → Messages**
   - سجل كامل لكل رسالة
   - حالة كل target
   - Logs تفصيلية

3. **Functions → messaging-notifier → Logs**
   - تنفيذ الـ Function
   - الأخطاء (إن وجدت)

---

## 🔒 الأمان

### ما يجب فعله ✅

- استخدم API Keys مع صلاحيات محدودة (مبدأ أقل الصلاحية)
- فعّل Rate Limiting في Appwrite Settings
- راجع Logs دورياً للأنشطة المشبوهة
- استخدم متغيرات البيئة (لا تضع المفاتيح في الكود)

### ما يجب تجنّبه ❌

- لا تضع `serviceAccount.json` في المستودع
- لا تشارك API Keys في الدردشات
- لا تفعّل `messaging.write` في تطبيق العميل
- لا تستخدم Legacy Server Key بعد الترحيل

---

## 📚 مراجع

- [Appwrite Messaging Docs](https://appwrite.io/docs/products/messaging)
- [FCM Provider Setup](https://appwrite.io/docs/products/messaging/providers/fcm)
- [Messaging API Reference](https://appwrite.io/docs/references/cloud/server-node/messaging)
- [Flutter Messaging SDK](https://pub.dev/documentation/appwrite/latest/messaging/Messaging-class.html)

---

## ✅ Checklist الضبط النهائي

- [ ] تفعيل Messaging في Console
- [ ] إضافة FCM Provider (serviceAccount.json)
- [ ] إضافة APNs Provider (للـ iOS إن لزم)
- [ ] إنشاء 6 Topics
- [ ] إنشاء API Key بصلاحيات messaging.read + messaging.write
- [ ] نشر Function `messaging-notifier`
- [ ] تعيين متغيرات البيئة للـ Function
- [ ] ربط Events في الـ Function
- [ ] تحديث `main.dart` لاستخدام `AppwriteMessagingService`
- [ ] اختبار إرسال إشعار من Console
- [ ] اختبار تلقائي عبر `test_messaging.js`
- [ ] مراقبة Logs لمدة 24 ساعة
- [ ] تعطيل `fcm_sender.dart` بعد التأكد من عمل النظام الجديد
