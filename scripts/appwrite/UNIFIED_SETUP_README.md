# سكربت Appwrite الموحّد — Unified Appwrite Setup

`unified_appwrite_setup.js` — سكربت **واحد** يُهيّئ أي وجهة Appwrite (الأساسية
Primary أو الثانوية Secondary) إلى **نفس المخطط بالضبط**: قاعدة البيانات + كل
المجموعات + كل الحقول + الفهارس.

> لماذا؟ نجاح المزامنة والنسخ الاحتياطي والـ failover يتطلب أن تكون الوجهة الثانوية
> مطابقة للأساسية حقلاً بحقل. هذا السكربت يضمن ذلك من مصدر حقيقة واحد.

## مصدر الحقيقة

كائن `SCHEMA` داخل السكربت **منقول حرفياً** من:

```
mobile/lib/services/appwrite_sync_utils.dart  →  collectionSchema
```

يغطّي السكربت جميع الكيانات الـ21 التي يزامنها/ينسخها التطبيق
(`AppwriteConfig._entityToCollection`)، أي الـ19 مجموعة الموجودة في
`collectionSchema` (بأنواعها المطابقة) + `app_settings` + `blacklist`.

> ملاحظة: `devices` و`sync_logs` و`sync_state` و`app_users` ليست ضمن مسار
> المزامنة (outbox/backup) لذا هي خارج نطاق هذا السكربت الموحّد عمداً.

## الاستخدام

```bash
# الوجهة الأساسية (القيم الافتراضية: fra.cloud / hotel_db)
APPWRITE_API_KEY=xxxxx npm run appwrite:setup

# الوجهة الثانوية (endpoint/project/db مختلفة — نفس السكربت)
APPWRITE_ENDPOINT=https://sfo.cloud.appwrite.io/v1 \
APPWRITE_PROJECT_ID=xxxxxxxxxxxx \
APPWRITE_DATABASE_ID=hotel_db \
APPWRITE_API_KEY=yyyyy \
npm run appwrite:setup

# فحص فقط (بدون كتابة): يقارن الفعلي بالمطلوب ويطبع النواقص
APPWRITE_API_KEY=xxxxx npm run appwrite:verify

# مجموعة/مجموعات محددة فقط
APPWRITE_API_KEY=xxxxx node scripts/appwrite/unified_appwrite_setup.js --only=bookings,payments
```

## متغيّرات البيئة

| المتغيّر | الافتراضي | الوصف |
|---|---|---|
| `APPWRITE_API_KEY` | — (مطلوب) | مفتاح API بصلاحيات databases/collections/attributes/indexes |
| `APPWRITE_ENDPOINT` | `https://fra.cloud.appwrite.io/v1` | عنوان الخادم |
| `APPWRITE_PROJECT_ID` | `690ff0da0025518570c1` | معرّف المشروع |
| `APPWRITE_DATABASE_ID` | `hotel_db` | معرّف قاعدة البيانات |
| `APPWRITE_DATABASE_NAME` | `Hotel DB` | اسم قاعدة البيانات عند إنشائها |

## الخصائص

- **Idempotent**: يتخطّى ما هو موجود (409) — آمن لإعادة التشغيل أكثر من مرّة.
- **موحّد**: نفس السكربت لكلا الوجهتين عبر متغيّرات البيئة.
- **آمن للمزامنة الجزئية**: فقط `localUuid` مطلوب (required)؛ بقية الحقول اختيارية
  حتى لا تُرفض حمولات المزامنة التي تحذف حقولاً فارغة.
- **فهارس قياسية** لكل مجموعة: `idx_local_uuid` (فريد) + `idx_last_modified` +
  `idx_sync_ts` + `idx_deleted_at` (حين توجد الحقول).
- **صلاحيات**: `audit_logs` للقراءة/الإنشاء فقط (سجلات دائمة)؛ الباقي CRUD كامل.

## المزامنة مع التطبيق

عند تعديل `collectionSchema` في التطبيق، حدّث `SCHEMA` في السكربت ثم شغّل
`npm run appwrite:verify` على كل وجهة للتأكّد من عدم وجود فروق.
