# Marina Hotel — FCM Notifier Appwrite Function

Appwrite Function تُرسل إشعارات FCM للأجهزة عند تغيير البيانات في قاعدة بيانات Appwrite. تستخدم Firebase Admin SDK لإرسال آمن (بدون كشف المفاتيح في التطبيق).

## 📋 المتطلبات

- Node.js 18+
- Appwrite Cloud project (projectId: `6a2b01d0000752ce97e7`)
- Firebase project (`aden-flutter`) مع تفعيل Cloud Messaging
- `serviceAccount.json` من Firebase Console

## 🚀 الإعداد

### الخطوة 1: احصل على Firebase Service Account

1. اذهب إلى [Firebase Console](https://console.firebase.google.com) → `aden-flutter`
2. **Project Settings → Service Accounts**
3. اضغط **"Generate new private key"** → يُنزّل ملف JSON
4. افتح الملف — ستحتاج 3 قيم منه:
   - `project_id`
   - `client_email`
   - `private_key` (يحتوي على `\n` — احتفظ بها كما هي)

### الخطوة 2: أنشئ Appwrite Function

1. اذهب إلى [Appwrite Console](https://fra.cloud.appwrite.io/console) → `6a2b01d0000752ce97e7`
2. **Functions → Create Function**
3. الاسم: `fcm-notifier`
4. Runtime: **Node.js 18.0**
5. Entry Point: `src/main.js`
6. ارفع الكود من مجلد `functions/fcm-notifier/` (بدون `node_modules/`)

### الخطوة 3: عيّن متغيرات البيئة

في Appwrite Console → Function → **Settings → Variables**، أضف:

| المتغير | القيمة |
|---|---|
| `APPWRITE_ENDPOINT` | `https://fra.cloud.appwrite.io/v1` |
| `APPWRITE_FUNCTION_PROJECT_ID` | `6a2b01d0000752ce97e7` |
| `APPWRITE_API_KEY` | (أنشئ API key مع `documents.read`) |
| `APPWRITE_DATABASE_ID` | `6a2b030d000445596163` |
| `APPWRITE_DEVICES_COLLECTION` | `devices` |
| `FIREBASE_PROJECT_ID` | `aden-flutter` |
| `FIREBASE_CLIENT_EMAIL` | (من serviceAccount.json) |
| `FIREBASE_PRIVATE_KEY` | (من serviceAccount.json — مع `\n` escapes) |

⚠️ **لا تضع serviceAccount.json كاملاً في متغير** — فقط الـ 3 حقول أعلاه.

### الخطوة 4: اربط الأحداث (Events)

في Function → **Settings → Events**، أضف:

```
databases.6a2b030d000445596163.tables.*.rows.*.create
databases.6a2b030d000445596163.tables.*.rows.*.update
databases.6a2b030d000445596163.tables.*.rows.*.delete
```

هذا يُطلق الدالة عند أي تغيير في أي جدول.

### الخطوة 5: اختبر

1. اضغط **"Execute Manually"** في Appwrite Console
2. استخدم هذا الـ payload (JSON):

```json
{
  "event": {
    "type": "databases.6a2b030d000445596163.tables.bookings.rows.create",
    "data": {
      "roomNumber": "101",
      "guestName": "أحمد",
      "deviceId": "test-device"
    }
  }
}
```

3. تحقق من Logs — يجب أن ترى:
   ```
   🚀 FCM Notifier function triggered
   ✅ Firebase Admin SDK initialized
   📋 Event: databases...bookings.rows.create
   📱 Found N recipient devices
   ✅ FCM sent: N success, 0 failure
   ```

## 🔧 كيف تعمل

```
موظف يُنشئ حجز في التطبيق
    ↓
Appwrite DB يحفظ السجل
    ↓
Appwrite يُطلق fcm-notifier function مع event payload
    ↓
الـ function:
  1. تُهيّئ Firebase Admin SDK (من env vars)
  2. تقرأ fcmToken لكل الأجهزة النشطة من collection "devices"
  3. تستثني جهاز المُرسِل (حتى لا يُرسل لنفسه)
  4. تُرسل FCM multicast عبر Firebase Admin SDK
    ↓
أجهزة الموظفين الآخرين تتلقى الإشعار
    ↓
FcmService في التطبيق يُشغّل المزامنة تلقائياً
```

## 📊 الأحداث المُتابعة

| الجدول | create | update | delete |
|---|---|---|---|
| bookings | ✅ "حجز جديد" | ✅ "تعديل حجز" | ✅ "حذف حجز" |
| payments | ✅ "دفعة جديدة" | — | — |
| expenses | ✅ "مصروف جديد" | — | — |
| debts | ✅ "دين جديد" | — | — |
| أخرى | ✅ "إضافة في [جدول]" | ✅ "تعديل في [جدول]" | ✅ "حذف في [جدول]" |

## 🛠️ الاختبار المحلي

```bash
cd functions/fcm-notifier
npm install
cp .env.example .env
# عدّل .env بالقيم الحقيقية
node src/main.js
```

## 🔒 الأمان

- ✅ `serviceAccount.json` لا يُخزّن في الكود أو المستودع
- ✅ المفاتيح تُحقن عبر Appwrite environment variables
- ✅ `.gitignore` يمنع commit الـ `.env` وملفات المفاتيح
- ⚠️ **أبطِل أي مفتاح تم تسريبه فوراً** عبر Firebase Console → Generate new key

## 📁 بنية الملفات

```
functions/fcm-notifier/
├── .gitignore          # يمنع commit المفاتيح
├── .env.example        # قالب المتغيرات (بدون قيم حقيقية)
├── package.json        # dependencies
├── README.md           # هذا الملف
└── src/
    └── main.js         # الكود الرئيسي
```

## 🔄 التحديث من Legacy Server Key

هذه الدالة **تستبدل** الـ Legacy Server Key approach (التي في `mobile/lib/services/fcm_sender.dart`):

| | Legacy (fcm_sender.dart) | Appwrite Function (هذا) |
|---|---|---|
| **المفتاح في التطبيق** | ✅ نعم (غير آمن) | ❌ لا (آمن) |
| **يعمل في الخلفية** | ❌ لا | ✅ نعم |
| **يحتاج اتصال بالخادم** | ❌ مباشر | ✅ عبر Appwrite |
| **التكلفة** | مجاني | مجاني (Appwrite free tier) |

بعد تفعيل هذه الدالة، يمكنك حذف `fcm_sender.dart` من التطبيق أو تركه كـ fallback.
