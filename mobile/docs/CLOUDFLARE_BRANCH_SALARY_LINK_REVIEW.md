# مسودة: مراجعة ربط الموظفين والمصروفات والرواتب في الفرع `feat/cloudflare-sync-execution`

> **الحالة:** مراجعة للقراءة فقط — لم يُعدَّل أي شيء في ذلك الفرع.
> **التاريخ:** 2026-10-03
> **النسخة المراجَعة:** `origin/feat/cloudflare-sync-execution` @ `78c17381` (مجلد `mobile/` + `worker/`)
> **المراجع:** `docs/EMPLOYEE_EXPENSE_SALARY_LINK_DRAFT.md` (المخاطر R1…R18 + §11 فحص Appwrite)، و`docs/SALARY_LINK_FIXES_PHASE0.md` (ما أُصلح في `refactor/performance-fixes-v2`)
> **ملاحظة:** الفرعان متباعدان جداً (2109 commit فوق الأساس المشترك). إصلاحات المرحلة 0 **لا تُنقل بالدمج المباشر**، بل يجب إعادة تطبيقها يدوياً في هذا الفرع.

---

## 1. المعمارية في هذا الفرع

```
[التطبيق: Drift] ──outbox──▶ POST /api/sync/push ──▶ [Worker: worker/src/sync.ts, database.ts] ──▶ [D1: marina-hotel-db]
[التطبيق] ◀── GET /api/sync/pull?cursor=updated_at ──┘
```

- **Appwrite أُوقف فعلياً:** `appwrite_sync_manager.dart` صار سطراً واحداً (`export 'cloudflare_sync_manager.dart';`)، و`typedef AppwriteSyncManager = CloudflareSyncManager` (`cloudflare_sync_manager.dart:4314`). لا حزمة `appwrite` في `pubspec.yaml`.
- **الرفع:** outbox مرتب بـ `clientTs` فقط → الـ Worker (`handlePush` في `sync.ts:395`، و`executeOperationAtomically` في `database.ts:1244`).
- **السحب:** المؤشر هو `updated_at` الفريد عبر `sync_clock`، وليس `server_seq`.
  - الصفوف تُطبَّق بـ SQL خام في `_applyChange`.
  - الروابط تُحل في `_resolveForeignKeysForRecord` حسب `sync/fk_rules.dart`.
  - **الـ adapters و`IdResolver` لا تُستخدم في السحب من Cloudflare**، بل فقط في مسارات الاستعادة المحلية/Drive.
- **الترحيل:** `cloudflare_migration_service.dart` يرفع **قاعدة الجهاز المحلية** إلى D1 بـ `INSERT OR REPLACE`. يعمل تلقائياً عند الإقلاع على كل جهاز لم يُعلَّم `cf_migration_complete` (`main.dart:468-483`).
- **الحذف:** tombstone دائماً على الخادم، والحذف يغلب أي تعديل لاحق.

## 2. مخطط D1 (`worker/schema.sql`)

| الجدول | المفتاح | روابط رقمية | روابط UUID |
|---|---|---|---|
| `employees` | `id` تلقائي في D1، و`local_uuid` UNIQUE | — | — |
| `expenses` | كذلك | `related_id`، `cash_transaction_id` | `employee_uuid` |
| `salary_withdrawals` | كذلك | `employee_id NOT NULL`، `expense_id` | `employee_uuid` (0006) — **لا `expense_uuid`** |
| `salary_cycles` | كذلك | `employee_id NOT NULL` + **`UNIQUE(employee_id, cycle_key)`** | `employee_uuid` (0007) |
| `salary_payments` | كذلك | `cycle_id NOT NULL` | `employee_uuid` — **لا `cycle_uuid`** |
| `salary_carry_over_logs` | كذلك | `employee_id NOT NULL` | **لا شيء** |

- لا FK في D1 (مقصود)، وsoft delete و`version` و`vector_clock` موجودة. هذا جيد.
- **كل الأعمدة الرقمية تحمل id المحلي في جهاز المصدر**، لا id في D1. الـ Worker لا يترجمها (تعليقات `schema.sql:209-210` و`0006` تقرّ بذلك).

## 3. مقارنة بالمخاطر التي أُصلحت في `refactor/performance-fixes-v2`

| البند | موجود هنا؟ | الموقع | النقل |
|---|---|---|---|
| R1 حذف اليتيم نهائياً بعد المزامنة | ❌ لا | لا `_performPostSyncIntegrityCheck`. فحوص `foreign_key_check` تعدّ وتسجّل فقط | غير لازم |
| R2 "الطريقة 2" (id بعيد = id محلي) | ❌ بصيغتها القديمة | — | غير لازم، لكن له **نسخة Cloudflare** (R2-cf أدناه) |
| R14 `IdResolver`: تخمين عند تكرار `serverId` + سقوط من UUID إلى `serverId` | ✅ نعم | `adapters/id_resolver.dart:179-199`، و`resolveSalaryCycle` حول `:283-302` | **يُنقل كما هو** (يؤثر على الاستعادة المحلية/Drive فقط) |
| R3/R12 `saveFromExpense` / `deleteByExpenseId` بلا فلتر موظف، ولا تحديث `employeeUuid` | ✅ نعم | `repositories/salary_withdrawals_repository.dart:287` (`LIMIT 1`)، `:309-336`، `:383-398`، `:526-549`. المستدعون: `expenses_list.dart:857, 1248, 1314, 1326`، و`salary_advance_installments_service.dart:49, 103` | **يُنقل كما هو**. الخطر **أشد** هنا لأن `expense_id` يُسحب بلا أي ترجمة |
| R8 `relatedId` خام في `ExpensesAdapter` + غياب `'سلفة'` | ✅ نعم | `adapters/expenses_adapter.dart:126-132`، و`sync/payload_mapper.dart:932-943` | **يُنقل كما هو** + نسخة Cloudflare (R8-cf) |
| R6 حذف المسحوب من الطابور عند غياب الموظف | ❌ لا | الرفع عام عبر `payload_normalizer.dart` | غير لازم |
| R7 Drive delta بلا جداول الرواتب | ❌ الملف غير موجود | — | غير لازم |
| سكربت `backfill_salary_withdrawals_employee_uuid.js` | ❌ غير موجود | — | غير لازم. **لكن** مكافئه على الخادم موجود (CF-3) |
| مفاتيح Appwrite مضمّنة في `scripts/` | ✅ 22 ملفاً | مثل `scripts/appwrite/check_employees.js:8` | تُلغى المفاتيح وتُزال |

## 4. مخاطر خاصة بمسار Cloudflare (مرتبة حسب الخطورة)

> ✔ = تحققت منه يدوياً في الكود.

### CF-1 ✔ شاشة تقرير المسحوبات تحذف مسحوبات حقيقية soft-delete وتنشر الحذف للجميع
- **الموقع:** `screens/reports/salary_withdrawals_report_screen.dart:189` يستدعي `dedupeMirrorDuplicates` (~`:878-990`) **في كل مرة يُفتح فيها التقرير**.
- **الآلية:**
  - يحل كل مسحوب إلى "مصروفه" عبر `SalaryMirrorMatcher.resolveLinkedExpenseId`، أي `expense_id` / `exp_N`، وهي أرقام محلية في جهاز آخر لم تُترجم عند السحب.
  - مسحوبان من جهازين مختلفين يتصادف رقماهما يُعتبران "مكررين": يُحذف أحدهما (`deletedAt`) ويُرسل للـ outbox، فيصل الحذف إلى D1 وكل الأجهزة.
  - يحذف كذلك "المرايا اليتيمة" (رابط لا يشير لمصروف محلي).
- **الأثر:** فقدان مسحوبات حقيقية من التقارير على كل الأجهزة. الحذف soft فقط، فهو قابل للاسترجاع من D1.
- **الإصلاح المقترح (عاجل):** إيقاف الحذف التلقائي عند فتح التقرير. إزالة التكرار تكون **للعرض فقط**، ولا تُكتب في القاعدة. أي دمج فعلي يتم يدوياً بعد `expense_uuid`.

### CF-2 ✔ (R2-cf) ربط الموظف عبر `server_id` يخلط فضاءين للمعرفات
- **الموقع:** `cloudflare_sync_manager.dart:2788-2805` (`_resolveForeignKeysForRecord`)، مع `:2929-2932`.
- **الآلية:**
  - `employees.server_id` محلياً = id الموظف **في D1**.
  - لكن `salary_withdrawals.employee_id` القادم من D1 = id الموظف **في جهاز المصدر**.
  - الخطوة 2 تطابق `server_id == employee_id`، أي رقمين من فضاءين مختلفين.
  - تُستخدم هذه الخطوة عندما يغيب `employee_uuid` أو لا يُحل.
  - في `salary_payments.cycle_id` و`salary_carry_over_logs.employee_id` هي **المسار الوحيد** (لا UUID).
- **أشد من ذلك:** إذا طابقت الخطوة 2 خطأً **على صف موجود**، فإنها تكتب فوق ربط محلي صحيح، لأن "احتفظ بالموجود" (الخطوة 4) لا يُطبَّق إلا عند عدم وجود أي مطابقة.
- **و`_lookupLocalParentId`** (`:2694`): `SELECT id ... LIMIT 1` بلا `ORDER BY`، فإذا تكرر `server_id` يُختار صف عشوائي.
- **الإصلاح المقترح:**
  - إذا كان `uuidCacheColumn` معرّفاً والـ UUID موجوداً في الصف لكن لم يُحل → **تأجيل** (لا سقوط إلى `server_id`).
  - إذا كان الصف موجوداً محلياً → لا يُكتب فوق ربطه إلا بمطابقة UUID.
  - التكرار → لا تخمين.
  - إضافة `cycle_uuid` لـ `salary_payments` و`employee_uuid` لـ `salary_carry_over_logs` (D1 + Drift).

### CF-3 ✔ قيم `employee_uuid` المُفسدة تُعامل كحقيقة وتنتشر
- **المصادر:**
  - قيم `employeeUuid` الخاطئة الموروثة من عهد Appwrite (§11 في المسودة الرئيسية: ~144 حالة واضحة، ~957,200).
  - هجرة الخادم `worker/migrations/0006`: `SET employee_uuid = (SELECT e.local_uuid … WHERE e.server_id = salary_withdrawals.employee_id LIMIT 1)`، وهي **نفس قاعدة السكربت الخاطئ** بلا فحص تفرّد.
  - `0007`: تعتمد مرشحاً فريداً، لكن آخر خطوة فيها `e.id = employee_id` (id في D1 مقابل id محلي)، والخطوة 5(أ) تقارن `sc.id = cycle_id` بنفس الخلط.
  - الهجرتان تملآن `NULL` فقط، فخطأ `0006` لا يُصحَّح أبداً.
- **الأثر:** لأن الـ UUID أولاً في السحب، فالربط الخاطئ يُطبَّق **بشكل حتمي على كل جهاز**.
- **الإصلاح المقترح:** لا تُشغَّل `0006` / `0007` على قاعدة جديدة. والتصحيح يتم من مصدر حقيقة فقط (نسخة احتياطية قبل 2026-09-12، أو قاعدة الجهاز المنشئ).

### CF-4 ✔ الترحيل التلقائي بـ `INSERT OR REPLACE` من كل جهاز
- **الموقع:** `cloudflare_migration_service.dart:420`، ويُستدعى من `main.dart:468-483` إذا لم يكن `cf_migration_complete` معلَّماً.
- **الآلية:**
  - يرفع كل جداول الجهاز بـ `updated_at` جديد، و`REPLACE` = حذف ثم إدراج في D1.
  - النتيجة: id جديد في D1، ومسح أعمدة الخادم وتعبئات الهجرات، والكتابة فوق تعديلات أحدث من أجهزة أخرى (ثم تُسحب كأنها الأحدث).
  - في `salary_cycles`: `REPLACE` على `UNIQUE(employee_id, cycle_key)` **يحذف دورة موظف آخر** إذا تصادف رقما الموظفين المحليين بين جهازين.
  - يُستدعى بـ `syncManager.token!`، فإذا كان التوكن null عند أول تشغيل يُرمى استثناء ويبقى العلم غير معلَّم، ويُعاد الترحيل لاحقاً.
- **الإصلاح المقترح:**
  - الترحيل يدوي من جهاز واحد مختار فقط، لا تلقائياً عند الإقلاع.
  - الكتابة عبر مسار الـ push العادي (upsert مشروط بالـ version). لا `INSERT OR REPLACE`.
  - إذا تقرر إبقاؤه تلقائياً: علم على الخادم (`sync_meta`) يمنع أي جهاز ثانٍ من الترحيل.

### CF-5 ✔ (R8-cf) المصروف يحتفظ بـ `related_id` الأجنبي
- **الموقع:** `cloudflare_sync_manager.dart:2751-2762`: `related_id` يُستبدل فقط إذا نجح حل `employee_uuid`، وإلا يبقى الرقم الخام لجهاز آخر. لا توجد قاعدة FK للمصروفات، فلا تأجيل.
- **وأيضاً:** `expenses_repository.dart:127-150` (`createAutoGenerated` للسلف والأقساط) **لا يكتب `employeeUuid`** أبداً، فهذه المصروفات تصل دائماً بلا UUID.
- **الإصلاح المقترح:**
  - للمصروف المرتبط بموظف: UUID غير محلول → `related_id = NULL` للإدراج، وعدم المساس بالقيمة الموجودة للتحديث.
  - كتابة `employeeUuid` في `createAutoGenerated`.

### CF-6 ✔ (من الكود) `null` يمسح القيم في D1
- **الموقع:** `worker/src/database.ts:1111` (`buildUpdateStatement` يقبل كل مفتاح `!== undefined`)، و`expenses_adapter.toJson` يرسل `'employeeUuid': null` صراحة.
- **الأثر:**
  - جهاز يحمل مصروفاً بلا UUID يمسح `employee_uuid` الصحيح في D1 عند أي تعديل.
  - كل تعديل يكتب فوق `related_id` و`cash_transaction_id` في D1 بأرقام هذا الجهاز المحلية.
- **الإصلاح المقترح:**
  - في التطبيق: لا تُرسل حقول الربط الفارغة (`putIfStringNotEmpty`).
  - في الـ Worker: تجاهل `null` لأعمدة الربط (`employee_uuid`، و`expense_uuid` لاحقاً)، إلا إذا صدر مسح صريح بعلم خاص.

### CF-7 (من الكود) طرد السجلات من الحجر بعد 300
- **الموقع:** `pull_quarantine.dart:63, 69, 317, 344-360`.
- **الآلية:** السجل الذي لم يُحل أبوه يمر بالانتظار ثم الحجر، وكلاهما بسقف 300. ما يزيد يُطرد **مع الـ payload**. ولأن المؤشر تقدّم، لا يعود إلا إذا عُدِّل على الخادم أو دُوّر الـ epoch.
- **الإصلاح المقترح:** لا طرد لسجلات الجداول المالية، أو حفظ المطرود في جدول محلي دائم مع زر "إعادة جلب".

### CF-8 (محتمل) حارس حذف الموظف قد يعدّ أقل من الحقيقة
- **الموقع:** `worker/src/database.ts:1563-1596` (`employeeFinancialHistoryCount`) يرجع إلى `w.employee_id = e.id` (خلط فضاءين)، ويعدّ سجلات الترحيل بـ `employee_id` فقط.
- **الأثر:** قد يسمح بحذف موظف له تاريخ مالي. الحذف tombstone، فهو قابل للاسترجاع.
- **الإصلاح المقترح:** العدّ بـ `employee_uuid` أولاً، ثم `employee_id` مع `device_id` المنشئ إن وُجد.

### CF-9 (منخفض) لا ترتيب الآباء أولاً في الرفع
- outbox مرتب بـ `clientTs` فقط (`cloudflare_sync_manager.dart:1345`)، والـ Worker لا يتحقق من وجود الأب. الأيتام تُقبل بصمت، ولا تظهر إلا في التأجيل/الحجر عند السحب.

### CF-10 التقارير تجمّع بالأرقام المحلية
- `salary_entitlement_service.dart:104, 473` (`relatedId.equals(employee.id)`)، و`:557, 574` (`employeeId`).
- `expenses_report_screen.dart:275, 314, 464`.
- `salary_withdrawals_report_screen.dart:180, 206`.
- بعد CF-2 وCF-5 قد تحمل هذه الأرقام ربطاً خاطئاً، فتُحسب الرواتب على موظف خاطئ. الحل هو القسم 6 من المسودة الرئيسية (`employee_uuid` + `v_salary_movements`).

## 5. ما هو جيد في هذا الفرع

- Worker وسيط (لا توكن الحساب في التطبيق)، ومعاملات ذرية، و`idempotency_log`.
- Soft delete وtombstones، والحذف لا يتراجع بنسخة قديمة.
- تحديث مشروط بالـ version (`WHERE local_uuid=? AND version=?`) في مسار الـ push العادي.
- لا حذف نهائي لليتيم بعد المزامنة (R1 غير موجود).
- تأجيل السجل الذي لم يصل أبوه، بدل حذفه، ضمن حدود (CF-7).
- المؤشر لا يتقدم إلا عند نجاح الدورة.

## 6. خطة الإصلاح المقترحة لهذا الفرع

### عاجل (يوقف الفقدان الجديد)
1. **CF-1:** إيقاف الحذف في `dedupeMirrorDuplicates`، فيصبح للعرض فقط.
2. **CF-4:** إيقاف الترحيل التلقائي عند الإقلاع، أو قفله بعلم على الخادم، واستبدال `INSERT OR REPLACE`.
3. **CF-2:** في `_resolveForeignKeysForRecord`: UUID موجود وغير محلول → تأجيل، ولا كتابة فوق ربط موجود إلا بمطابقة UUID، و`LIMIT 1` بلا ترتيب عند التكرار → لا تخمين.
4. **CF-5 / R8:** لا `related_id` خام للمصروف المرتبط بموظف، و`'سلفة'` في التصنيف، و`employeeUuid` في `createAutoGenerated`.
5. **CF-6:** عدم إرسال `employeeUuid: null`، وتجاهل `null` لأعمدة الربط في الـ Worker.
6. **R3/R12 و R14:** نقل إصلاحات المرحلة 0 كما هي (`saveFromExpense` / `deleteByExpenseId` / `IdResolver`) مع تعديل المستدعين الإضافيين في `salary_advance_installments_service.dart`.

### بعد ذلك
7. **عمود `expense_uuid`** في Drift (Migration 69) وD1 (`worker/migrations/00xx`) + ترجمته في الرفع والسحب، ومعه `cycle_uuid` و`employee_uuid` للترحيل.
8. **CF-7:** لا طرد للجداول المالية من الحجر.
9. **CF-3:** تصحيح بيانات `employee_uuid` في D1 من مصدر حقيقة، مع تقرير مراجعة يدوية. لا تشغيل لـ `0006` / `0007` على قواعد جديدة.
10. **CF-10:** التقارير بـ `employee_uuid` و`v_salary_movements`.
11. **CF-8 و CF-9.**

## 7. أسئلة مفتوحة

1. هل شُغّل الترحيل (`cloudflare_migration_service`) فعلاً على أكثر من جهاز في الإنتاج؟ (يحدد حجم CF-4).
2. هل هجرتا `0006` / `0007` مطبّقتان على قاعدة D1 الإنتاجية؟
3. هل تريد تطبيق الإصلاحات العاجلة (1–6) على فرع `feat/cloudflare-sync-execution` مباشرة؟ لا أستطيع التبديل إلى ذلك الفرع من هذه الجلسة. يلزم فتح جلسة عليه، أو استخدام `/rebase`.
4. هل يمكن فحص D1 الإنتاجي (للقراءة فقط، كما فعلنا مع Appwrite) لقياس CF-1 وCF-3 بالأرقام؟
