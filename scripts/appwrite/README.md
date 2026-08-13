# Appwrite Schema Scripts

## نقطة التشغيل الوحيدة

السكربت الرسمي الوحيد لإنشاء أو تحديث مخطط Appwrite هو:

```bash
APPWRITE_API_KEY=... npm run appwrite:setup
```

يعتمد السكربت [`unified_appwrite_setup.js`](./unified_appwrite_setup.js) كمصدر حقيقة واحد ويغطي قاعدة البيانات، جميع المجموعات، كل حقول المزامنة والحقول التجارية، والفهارس القياسية وفهارس الاستعلامات التشغيلية.

| الأمر | الاستخدام |
|---|---|
| `npm run appwrite:setup` | إنشاء أو إكمال القاعدة والمجموعات والحقول والفهارس بشكل idempotent. |
| `npm run appwrite:verify` | فحص المجموعات والحقول والأنواع **والفهارس** من دون كتابة. |
| `npm run appwrite:make-optional` | تحويل الحقول التجارية إلى اختيارية بأمان من دون حذف البيانات. |
| `npm run appwrite:repair-types` | إصلاح الحقول ذات النوع الخاطئ؛ عملية هدمية تتطلب `--confirm`. |
| `npm run appwrite:prune` | حذف الحقول غير الموجودة في المصدر الموحد؛ عملية هدمية تتطلب `--confirm`. |

لتهيئة مجموعة أو مجموعات فقط:

```bash
APPWRITE_API_KEY=... node scripts/appwrite/unified_appwrite_setup.js --only=bookings,payments
```

## قواعد الأمان

يستخدم السكربت متغيرات البيئة `APPWRITE_ENDPOINT` و`APPWRITE_PROJECT_ID` و`APPWRITE_DATABASE_ID` و`APPWRITE_API_KEY`. لا يُحفظ مفتاح Appwrite في ملفات المصدر. كما أن أوضاع `--prune` و`--fix-types` لا تُشغَّل ضمن الإعداد العادي لأنها قد تحذف بيانات حقول من السحابة.

## الملفات السابقة

الملفات الأخرى في هذا المجلد هي أدوات صيانة أو استعادة تاريخية. لا يجب استخدامها لتهيئة مخطط جديد أو لإضافة حقول/فهارس جديدة؛ أي تغيير جديد للمخطط يجب أن يدخل في `unified_appwrite_setup.js` فقط، ثم يُتحقق منه عبر `npm run appwrite:verify`.
