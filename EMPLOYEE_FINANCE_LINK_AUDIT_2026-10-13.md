# تدقيق ربط الموظفين بالمصروفات والسحوبات والاستحقاقات

**التاريخ:** 2026-10-13  
**المشروع:** Marina Hotel / Appwrite Cloud (`690ff0da0025518570c1`)  
**قاعدة البيانات:** `hotel_db`

## النتيجة التنفيذية

- **المصروفات المرتبطة بالرواتب:** 759 سجلًا في النسخة المصدّرة، وجميعها تحتوي `employeeUuid` صالحًا يطابق موظفًا موجودًا.
- **سحوبات الرواتب:** 739 سجلًا؛ 738 تحتوي `employeeUuid` صالحًا، وسجل واحد قديم يفتقد UUID.
- **الموظفون:** 16 سجلًا في النسخة المصدّرة.
- **الاستحقاقات/دورات الرواتب:** كان مسار الرفع يعتمد على `employeeId` المحلي، كما أن فلترة الحمولة لا تسمح بحقول `employeeUuid` و`employeeLocalUuid` في `salary_cycles`؛ وهذا يسبب فقدان الربط عند اختلاف أرقام SQLite بين الأجهزة.

## الإصلاح البرمجي

1. إضافة `employeeUuid` و`employeeLocalUuid` إلى قائمة الحقول المسموح بها ومخطط الحمولة لكيان `salary_cycles`.
2. إضافة UUID عند الرفع الكامل لدورات الرواتب، مع الإبقاء على `employeeId` للتوافق مع الإصدارات القديمة.
3. إنشاء `scripts/appwrite/repair_employee_links.js`:
   - يعمل افتراضيًا بوضع **dry-run**.
   - يصلح فقط عند وجود موظف واحد مطابق لـ `serverId`.
   - لا يربط الحالات الغامضة أو التي لا تملك موظفًا مطابقًا.
   - ينشئ سمات UUID المطلوبة لـ `salary_cycles` عند استخدام `--apply` وينتظر جاهزيتها.

## حالة Appwrite Cloud

تعذر تنفيذ التدقيق/الإصلاح السحابي أثناء هذه الجلسة لأن Appwrite أعاد:

> Project is paused due to inactivity. Please restore it from the console to resume operations.

لذلك **لم تُعدّل أي بيانات سحابية**. بعد استعادة المشروع من Appwrite Console، شغّل أولًا:

```bash
APPWRITE_ENDPOINT=https://fra.cloud.appwrite.io/v1 \
APPWRITE_PROJECT_ID=690ff0da0025518570c1 \
APPWRITE_DATABASE_ID=hotel_db \
APPWRITE_API_KEY='...' \
node scripts/appwrite/repair_employee_links.js
```

ثم راجع التقرير. للتطبيق الفعلي استخدم `--apply` فقط بعد التأكد من النتائج:

```bash
APPWRITE_API_KEY='...' node scripts/appwrite/repair_employee_links.js --apply
```

## الاختبارات المنفذة

- `node --check scripts/appwrite/repair_employee_links.js` — ناجح.
- `git diff --check` — ناجح.
- تدقيق CSV مستقل — لا توجد مصروفات رواتب ذات `employeeUuid` مفقود، ولا توجد UUIDs غير صالحة في السحوبات ذات UUID الموجود.
- لم تتوفر أدوات Flutter/Dart في بيئة التنفيذ، لذلك لم يُشغّل `flutter analyze`.
