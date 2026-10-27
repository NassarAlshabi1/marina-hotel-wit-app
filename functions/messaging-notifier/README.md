# Marina Hotel — Messaging Notifier Function

> Appwrite Function جديدة تستخدم **Appwrite Messaging API** بدلاً من Firebase Admin SDK المباشر، كبديل محسّن لـ `fcm-notifier`.

## 🎯 لماذا هذه Function؟

| | `fcm-notifier` (القديمة) | `messaging-notifier` (الجديدة) |
|---|---|---|
| **SDK المستخدم** | `firebase-admin` | `node-appwrite` Messaging |
| **متغيرات البيئة** | 8 (3 منها Firebase secrets) | 4 فقط |
| **serviceAccount.json** | مطلوب | غير مطلوب |
| **سجل التسليم** | Logs فقط | Logs + Console UI |
| **إدارة الأجهزة** | collection `devices` فقط | Targets API + collection |
| **Topics** | لا يدعم | يدعم |

## 📦 المتطلبات

- Node.js 18+
- Appwrite Cloud project `6a2b01d0000752ce97e7`
- Messaging مُفعّل مع FCM Provider (انظر `docs/APPWRITE_MESSAGING_SETUP.md`)

## 🚀 الإعداد

### الخطوة 1: نشر Function

```bash
# عبر Appwrite CLI
appwrite functions create \
  --function-id=messaging-notifier \
  --name="Messaging Notifier" \
  --runtime=node-18.0 \
  --entrypoint=src/main.js

# رفع الكود
cd functions/messaging-notifier
zip -r messaging-notifier.zip src package.json
appwrite functions deploy --function-id=messaging-notifier --code=messaging-notifier.zip
```

أو يدوياً عبر Console:
1. Functions → Create Function
2. الاسم: `messaging-notifier`
3. Runtime: **Node.js 18.0**
4. Entry Point: `src/main.js`
5. ارفع الكود (ملفات `src/` و `package.json` فقط، بدون `node_modules/`)

### الخطوة 2: متغيرات البيئة

في Console → Function → **Settings → Variables**:

| المتغير | القيمة | ملاحظة |
|---|---|---|
| `APPWRITE_ENDPOINT` | `https://fra.cloud.appwrite.io/v1` | |
| `APPWRITE_FUNCTION_PROJECT_ID` | `6a2b01d0000752ce97e7` | |
| `APPWRITE_API_KEY` | `standard_...` | صلاحيات: `messaging.write` + `documents.read` |
| `APPWRITE_DATABASE_ID` | `6a2b030d000445596163` | |
| `APPWRITE_DEVICES_COLLECTION` | `devices` | |
| `APPWRITE_MESSAGING_PROVIDER_ID` | (يظهر بعد تفعيل FCM) | اذهب لـ Messaging → Providers لمعرفة الـ ID |

### الخطوة 3: ربط الأحداث (Events)

في Function → **Settings → Events**:

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

### الخطوة 4: اختبار

1. اضغط **"Execute Manually"** في Console
2. Payload:

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

3. تحقق من Logs:

```
🚀 Messaging Notifier function triggered
📥 Event payload keys: event
📋 Event: databases...bookings.rows.create
   Table: bookings, Operation: create
   Sender device: test-device
📱 Found N recipient devices
✅ Message sent via Messaging API: <message-id>
✅ Done: success
```

## 🔧 كيف تعمل

```
موظف يُنشئ حجز في التطبيق
    ↓
Appwrite DB يحفظ السجل
    ↓
Appwrite يُطلق messaging-notifier مع event payload
    ↓
الـ Function:
  1. تُحلل الحدث (table, operation, senderDevice)
  2. تقرأ الأجهزة النشطة من collection "devices" (عدا المُرسِل)
  3. تبني نص الإشعار حسب نوع الجدول
  4. تستدعي messaging.createPush() لإرسال الإشعار
    ↓
Appwrite Messaging يُرسل الإشعار عبر FCM Provider المُكوّن
    ↓
أجهزة الموظفين الآخرين تتلقى الإشعار
    ↓
AppwriteMessagingService في التطبيق يُشغّل المزامنة تلقائياً
```

## 📊 مقارنة مع النظام القديم

### النظام القديم (fcm-notifier)

```javascript
// يتطلب 3 متغيرات Firebase حساسة:
const serviceAccount = {
  projectId: process.env.FIREBASE_PROJECT_ID,
  clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
  privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
};
initializeApp({ credential: cert(serviceAccount) });
const messaging = getMessaging();
await messaging.sendEachForMulticast(message);
```

### النظام الجديد (messaging-notifier)

```javascript
// لا يتطلب أي معلومات Firebase — Appwrite Messaging يديرها!
const messaging = new Messaging(client);
await messaging.createPush(
  undefined, title, body,
  [], [], targetIds, dataPayload,
  ...
);
```

## 🛠️ الاختبار المحلي

```bash
cd functions/messaging-notifier
npm install

# تشغيل مباشر (محاكاة)
APPWRITE_API_KEY=standard_xxx \
APPWRITE_DATABASE_ID=6a2b030d000445596163 \
APPWRITE_MESSAGING_PROVIDER_ID=fcm \
node -e "
  import('./src/main.js').then(async ({ default: main }) => {
    await main({
      req: {
        bodyJson: JSON.stringify({
          event: {
            type: 'databases.X.tables.bookings.rows.create',
            data: { roomNumber: '101', guestName: 'Test', deviceId: 'dev1' }
          }
        }),
        headers: {}
      },
      res: { json: (data, code = 200) => console.log(JSON.stringify(data, null, 2)) },
      log: console.log,
      error: console.error
    });
  });
"
```

## 🔒 الأمان

- ✅ لا `serviceAccount.json` في الـ Function
- ✅ لا مفاتيح Firebase حساسة في الـ environment
- ✅ صلاحيات API Key محدودة (`messaging.write` + `documents.read`)
- ✅ لا تسرّب للمفاتيح في Logs

## 📁 بنية الملفات

```
functions/messaging-notifier/
├── package.json
├── README.md           # هذا الملف
└── src/
    └── main.js         # الكود الرئيسي
```

## 🔄 الترقية من fcm-notifier

1. انشر `messaging-notifier` كـ Function جديدة (لا تُلغِ القديمة)
2. اربط نفس الـ Events للجديدة
3. اختبر بإنشاء حجز جديد — يجب أن يصلك إشعار من **كلتا** الـ Functions (مكرر)
4. راجع Logs للتأكد من عمل الجديدة بشكل صحيح
5. أوقف الـ Events من القديمة (Settings → Events → احذف الكل)
6. اختبر — يجب أن يصلك إشعار من الجديدة فقط
7. احذف `fcm-notifier` نهائياً بعد 7 أيام من المراقبة

## 🆘 استكشاف الأخطاء

### `APPWRITE_MESSAGING_PROVIDER_ID not set`

**الحل:** اذهب لـ Messaging → Providers، انسخ الـ ID الصحيح.

### `missing scope: messaging.write`

**الحل:** أعد إنشاء API Key مع صلاحية `messaging.write` مُفعّلة.

### `No recipients`

**الحل:**
1. تأكد من وجود أجهزة في collection `devices` بحالة `active`
2. تأكد من وجود `fcmToken` لكل جهاز
3. شغّل التطبيق على الأقل مرة ليسجّل الجهاز

### Function لا تعمل

1. تحقق من Logs في Console → Functions → messaging-notifier → Logs
2. تأكد من ربط Events بشكل صحيح
3. تأكد من تثبيت dependencies: `npm install` محلياً قبل الرفع
