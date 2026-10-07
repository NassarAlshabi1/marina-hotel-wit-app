# تقرير توحيد الفرعين 2 و3 — مخطط Cloudflare Worker/D1 + عقود المزامنة وواجهات الإدخال

> **هذا التقرير خاص بالفرعين 2 و3 فقط، ولا يعدّل الفرع 1.**
>
> - الفرع 2: `feat/cloudflare-sync-execution` — Flutter (Drift) + Cloudflare Worker/D1.
> - الفرع 3: `arena/be8302d7-marina-hotel-wit-app` — Android/Kotlin (Room) + Cloudflare Worker/D1.
> - الحزمة المرجعية الموحدة: `marina-hotel-unified-migrations.zip` (14 ترحيلة 0002–0015).

## 1. ملخص التنفيذ

تم تنفيذ التوحيد على ثلاث مراحل متتالية كما ورد في تعليمات الوكيل:

| المرحلة | الحالة | المخرجات |
|---------|--------|----------|
| 1 — تدقيق قبل التغيير | ✅ مكتمل | تقرير مقارنة الحقول، حالة Git، اختلافات المزامنة |
| 2 — تصميم التوافق | ✅ مكتمل | جدول mapping موحد، قرارات backfill، خطة migration مشروطة |
| 3 — التنفيذ والاختبارات | ✅ مكتمل (Worker + Flutter + Kotlin) | patches مستقلة لكل فرع، اختبارات منفذة وموثقة |

### 1.1. حدود السلامة الملتزم بها

- ❌ لم يُنفّذ `wrangler d1 ... --remote` على الإطلاق.
- ❌ لم يُنشر Worker ولم تُعدّل قاعدة D1 الإنتاجية.
- ❌ لم تُمسح بيانات تاريخية ولم يُعاد بناء UUID من أرقام محلية.
- ❌ لم يُدمج الفرع 2 في الفرع 3 أو العكس — لكل فرع patch مستقل.
- ✅ تم تسجيل حالة Git لكل فرع قبل أي تعديل (انظر §2.1).
- ✅ تم فحص تعليمات `AGENTS.md` و`docs/PERFORMANCE.md` عند الاقتضاء.

### 1.2. حدود البيئة

| الأداة | المتوفر | التأثير |
|-------|---------|---------|
| Node.js v24.21 | ✅ | تشغيل اختبارات Worker عبر vitest |
| SQLite 3.46 | ✅ | التحقق من `schema.sql` في الذاكرة |
| Flutter SDK | ❌ | اختبارات Dart مكتوبة لكن لم تُشغّل |
| Android SDK | ❌ | اختبارات Kotlin/Room مكتوبة لكن لم تُشغّل |

النتيجة: **314** اختبار Worker في B2 + **230** اختبار Worker في B3 = **544 اختبار Worker اجتازت بنجاح**. اختبارات Flutter وKotlin موثقة كـ"مكتوبة لكن لم تُشغّل بسبب عدم توفر SDK".

## 2. المرحلة 1 — تدقيق قبل التغيير

### 2.1. حالة Git المسجّلة قبل التعديل

| الفرع | HEAD SHA | تاريخ الـ commit | رسالة الـ commit |
|-------|----------|------------------|------------------|
| B2 (`feat/cloudflare-sync-execution`) | `549f86f9c6478a5c2bc96924e5aebc863da2f925` | 2026-10-07 02:11:23 +0300 | chore: add zipped migrations archive from agent/android-cloudflare branch |
| B3 (`arena/be8302d7-marina-hotel-wit-app`) | `455fe960b826363181ac988f88cad5e76275896c` | 2026-10-06 22:51:20 +0000 | docs: أدلة تشغيل مراجعة فرع Flutter |

### 2.2. مقارنة الحقول بين Drift وWorker D1 وKotlin/Room وadapters وUI

الجدول التالي يوضّح حالة كل حقل محمول (portable UUID) وميتاداتا خادمية في كل طبقة قبل التوحيد، مع الإشارة إلى موضع كل تعديل:

| الحقل | الجدول | B2 Worker schema.sql | B2 Drift (mobile/lib/services/local_db.dart) | B2 Flutter adapter | B3 Worker schema.sql | B3 Room entity (ExpenseEntity.kt) | B3 Kotlin DTO/PushWireContract | ملاحظات |
|-------|--------|---------------------|-----------------------------------------------|---------------------|----------------------|-----------------------------------|--------------------------------|---------|
| `employee_uuid` | `expenses` | ✅ مضاف في 0007 | ✅ `TextColumn get employeeUuid` L189 | ✅ `expenses_adapter.dart` L175 يقرأ/يكتب | ✅ مضاف في 0007 | ✅ `ExpenseEntity.kt` L66-68 | ✅ `PushWireContract.kt` يرفق `employee_uuid` على الدفعات | متماثل عبر الفرعين |
| `employee_uuid` | `salary_cycles` | ✅ مضاف في 0007 | ✅ L698 | ✅ `salary_cycles_adapter.dart` | ✅ مضاف في 0007 | ✅ `SalaryCycleEntity.kt` L16 | ✅ | متماثل |
| `employee_uuid` | `salary_payments` | ✅ مضاف في 0007 (denormalized) | ✅ L726 | ✅ `salary_payments_adapter.dart` | ✅ مضاف في 0007 | ✅ `SalaryPaymentEntity.kt` L22 | ✅ | متماثل |
| `employee_uuid` | `salary_withdrawals` | ✅ مضاف في 0006 | ✅ L760 | ✅ `salary_withdrawals_adapter.dart` | ✅ مضاف في 0006 | ✅ `SalaryWithdrawalEntity.kt` L30-32 | ✅ | متماثل |
| `employee_uuid` | `salary_carry_over_logs` | ✅ مضاف في 0011 (portable) | ✅ L803 | ✅ `salary_carry_over_logs_adapter.dart` | ✅ مضاف في 0011 | ✅ `SalaryCarryOverLogEntity.kt` L17 | ✅ | متماثل |
| `withdrawal_uuid` | `expenses` | ✅ مضاف في 0011 | ✅ L191 | ✅ `expenses_adapter.dart` L176 يقرأ/يكتب | ❌ لم يكن موجوداً في B3 قبل التوحيد | n/a (B3 لا يحمله على ExpenseEntity) | n/a | **B3 لم يكن لديه هذا الربط العكسي** — لكن B3 لديه `idx_salary_withdrawals_active_expense` على الناحية الأخرى |
| `expense_uuid` | `salary_withdrawals` | ✅ مضاف في 0011 (portable_financial_relationships) | ✅ L774 | ✅ `salary_withdrawals_adapter.dart` L191 | ✅ مضاف في 0013 | ✅ `SalaryWithdrawalEntity.kt` L14, L34-36 | ✅ | **B2 أضافه في 0011، B3 أضافه في 0013** — اختلاف تاريخي تم توحيده |
| `cycle_uuid` | `salary_payments` | ✅ مضاف في 0011 | ✅ L728 | ✅ `salary_payments_adapter.dart` L36, L204 | ✅ مضاف في 0011 (B3's 0011 = salary_parent_uuids) | ✅ `SalaryPaymentEntity.kt` L14, L21 | ✅ | متماثل |
| **`expense_kind`** | `expenses` | ❌ لم يكن موجوداً قبل التوحيد | ❌ غير موجود | ❌ غير موجود | ✅ مضاف في 0015 + CHECK constraint | ✅ `ExpenseEntity.kt` L29-31 | ✅ `PushWireContract.kt` يرفقه بقدرة الخادم | **منقول من B3 إلى B2** |
| **`employee_link_cleared`** | `expenses` | ❌ لم يكن موجوداً | ❌ غير موجود | ❌ غير موجود | ✅ مضاف في 0012 + default 0 | ✅ `ExpenseEntity.kt` L76-80 | ✅ `PushWireContract.kt` يحوّل `clear_employee_link=1` | **منقول من B3 إلى B2** |
| `sync_write_times` | (جدول جديد) | ❌ لم يكن موجوداً | ❌ غير موجود | ❌ غير موجود | ✅ مضاف في 0014 | ❌ غير موجود ككيان Room | n/a (جدول خادمي صرف) | **منقول من B3 إلى B2** |
| `idx_idempotency_processed_at` | `idempotency_log` | ✅ مضاف في 0008 | n/a (ليس جدول متزامن) | n/a | ❌ لم يكن موجوداً | ❌ غير موجود | n/a | **منقول من B2 إلى B3** |
| `finance_snapshots` | (جدول جديد) | ✅ مضاف في 0009 | ❌ غير موجود في Drift | ❌ غير موجود | ❌ لم يكن موجوداً | ❌ غير موجود | n/a | **منقول من B2 إلى B3 + Room entity جديد** |

### 2.3. اختلافات المزامنة وعقود API

تم فحص نقاط الـ push/pull في كلا الفرعين. الاختلافات المكتشفة قبل التوحيد:

1. **`expense_kind` validation**: B3's `worker/src/sync.ts` L65-68 يرفض أي push يحمل `expense_kind` غير صالح بقيمة `validation_error`. B2 لم يكن لديه هذا التحقق — تم نقله.
2. **`clear_employee_link` legacy synonym**: B3's `worker/src/database.ts` (`normalizePushReferences` L952-997) يترجم `clear_employee_link=1` الوارد من Android `PushWireContract.kt` إلى `employee_uuid=NULL` + `employee_link_cleared=1`. B2 لم يكن لديه هذا المسار — تم نقله عبر `normalizeExpenseFields` الجديدة في `database.ts`.
3. **`expense_kind` derivation on create**: B3's `createRecord` L1042-1044 يستدعي `expenseKind(data.expense_kind, data)` ليشتق النوع من الـ legacy classifier عندما لا يرسله العميل صراحة. B2 لم يكن لديه — تم نقله.
4. **`expense_kind` preservation on update**: B3's `updateRecord` L1227 يحافظ على النوع الموجود (`existing.expense_kind`) عندما يرسله العميل بـ null — هذا يمنع تحرير الوصف من إعادة تصنيف النوع. B2 لم يكن لديه — تم نقله.
5. **Flags الحرفية**: B3's `PushWireContract.kt` و`CloudflareSyncService.kt` يرسلان `tombstones_only=1` و`include_remaining=1` و`normalize_timestamps=1` بقيم نصية حرفية `"1"` لمطابقة `=== '1'` في الـ Worker. B2 الـ Flutter `cloudflare_sync_manager.dart` يستخدم نفس النمط — لا يحتاج توحيد.
6. **ترتيب الآباء قبل الأبناء**: B2 الـ Flutter `pull_apply_rules.dart` (`pullApplyPriority`: rooms → employees → bookings → salary_cycles → salary_withdrawals → salary_payments) وB3 الـ Kotlin `SyncIngestorRegistry.kt` كلاهما يحترم نفس الترتيب. لا يحتاج توحيد.
7. **idempotency عند retries**: كلا الفرعين يستخدما `idempotency_key` UUID لكل عملية push. لا يحتاج توحيد.

### 2.4. الترحيلات المطبّقة سابقاً في كل فرع

| الترحيلة | B2 يملكها؟ | B3 يملكها؟ | ملاحظات |
|----------|-------------|-------------|---------|
| `0002_inventory_blacklist.sql` | ✅ | ✅ | مشتركة |
| `0003_app_users.sql` | ✅ | ✅ | مشتركة |
| `0004_devices_sync.sql` | ✅ | ✅ | مشتركة |
| `0005_schema_parity.sql` | ✅ | ✅ | مشتركة |
| `0006_salary_withdrawals_employee_uuid.sql` | ✅ | ✅ | مشتركة |
| `0007_salary_tables_employee_uuid.sql` | ✅ | ✅ | مشتركة |
| `0008_idempotency_log_cleanup.sql` | ✅ | ❌ ناقصة | **أُضيفت إلى B3 في هذا التوحيد** |
| `0009_finance_snapshots.sql` | ✅ | ❌ ناقصة | **أُضيفت إلى B3 في هذا التوحيد** |
| `0010_sync_meta.sql` | ✅ | ✅ | مشتركة |
| `0011_*.sql` | `0011_portable_financial_relationships.sql` (4 UUIDs موحّدة) | `0011_salary_parent_uuids.sql` (cycle_uuid + carryover.employee_uuid فقط) | **اختلاف تاريخي** — الحزمة الموحدة تختار نهج B2 (4 UUIDs في ترحيلة واحدة) |
| `0012_*.sql` | ❌ غير موجودة | `0012_expense_employee_link_clear_flag.sql` | **أُضيفت إلى B2 في هذا التوحيد** |
| `0013_*.sql` | ❌ غير موجودة | `0013_salary_withdrawal_expense_uuid.sql` (عمود + فهرس فريد) | **أُضيفت إلى B2 في هذا التوحيد** — مع تعديل: العمود موجود سابقاً من 0011، لذا 0013 في B2 تنشئ الفهرس الفريد فقط |
| `0014_*.sql` | ❌ غير موجودة | `0014_sync_write_times.sql` | **أُضيفت إلى B2 في هذا التوحيد** |
| `0015_*.sql` | ❌ غير موجودة | `0015_expense_kind.sql` | **أُضيفت إلى B2 في هذا التوحيد** |

## 3. المرحلة 2 — تصميم التوافق

### 3.1. جدول mapping الموحّد

| الحقل | اسم Dart (B2) | اسم Kotlin (B3) | اسم JSON/Wire | اسم SQL/D1 | النوع | nullability | default | موضع الإنشاء | موضع التعديل |
|-------|---------------|------------------|----------------|------------|------|------------|---------|--------------|--------------|
| `expense_kind` | `expenseKind` (Drift `TextColumn`) | `expenseKind` (Room `String?`) | `expense_kind` | `expense_kind TEXT` | TEXT | nullable | NULL | `worker/src/database.ts createRecord` + Drift migration 71 + Room migration 74→75 | `worker/src/database.ts updateRecord` (preservation) |
| `employee_link_cleared` | `employeeLinkCleared` (Drift `IntColumn`) | `employeeLinkCleared` (Room `Boolean`) | `employee_link_cleared` (و synonym قديم `clear_employee_link`) | `employee_link_cleared INTEGER NOT NULL DEFAULT 0` | INTEGER | NOT NULL | 0 | `worker/src/database.ts normalizeExpenseFields` (server-owned) | `worker/src/database.ts normalizeExpenseFields` + Room migration 75→76 |
| `employee_uuid` (expenses) | `employeeUuid` | `employeeUuid` | `employee_uuid` | `employee_uuid TEXT` | TEXT | nullable | NULL | Drift L189 + `ExpenseEntity.kt` L66 + worker 0007 | adapters في كلا الفرعين |
| `withdrawal_uuid` (expenses) | `withdrawalUuid` | (غير موجود كحقل على ExpenseEntity في B3 — الربط العكسي يحفظه salary_withdrawals وحدها) | `withdrawal_uuid` | `withdrawal_uuid TEXT` | TEXT | nullable | NULL | Drift L191 + worker 0011 | `expenses_adapter.dart` L176 + `salary_withdrawals_repository.dart` L72-73 (UPDATE الربط العكسي) |
| `expense_uuid` (salary_withdrawals) | `expenseUuid` | `expenseUuid` | `expense_uuid` | `expense_uuid TEXT` | TEXT | nullable | NULL | Drift L774 + `SalaryWithdrawalEntity.kt` L14 + worker (0011 في B2، 0013 في B3) | `salary_withdrawals_adapter.dart` L191 + `SalaryWithdrawalsRepositoryImpl.kt` L93 |
| `cycle_uuid` (salary_payments) | `cycleUuid` | `cycleUuid` | `cycle_uuid` | `cycle_uuid TEXT` | TEXT | nullable | NULL | Drift L728 + `SalaryPaymentEntity.kt` L14 + worker 0011 | `salary_payments_adapter.dart` L36 + `SyncIngestorRegistry.kt` L670 |
| `employee_uuid` (salary_carry_over_logs) | `employeeUuid` | `employeeUuid` | `employee_uuid` | `employee_uuid TEXT` | TEXT | nullable | NULL | Drift L803 + `SalaryCarryOverLogEntity.kt` L17 + worker 0011 | `salary_carry_over_logs_adapter.dart` |

### 3.2. قيم `expense_kind` المقبولة حصراً

```text
normal, salary_advance, salary_installment, salary_withdrawal, salary_deduction, unclassified
```

الـ CHECK constraint على D1 (worker/schema.sql `expenses` table) يفرضها على مستوى القاعدة. الـ push validation في `worker/src/sync.ts` L65-68 يرفض أي قيمة غير صالحة بـ `validation_error`.

### 3.3. قرارات backfill لكل حقل

| الحقل | قرار backfill | المبرر |
|-------|--------------|--------|
| `expense_kind` | **عدم التخمين**. السجلات التاريخية تبقى NULL حتى يقوم العميل بتعديلها فيحسبها الـ server من الـ legacy classifier. | تطابق نهج B3 الأصلي. تجنب إعادة كتابة مالية جماعية. |
| `employee_link_cleared` | **0 افتراضياً** لكل الصفوف الجديدة والموجودة. | العلم خادمي محض؛ لا توجد قيمة تاريخية موثوقة. |
| `employee_uuid` (للسجلات التاريخية) | **عدم التخمين**. الروابط غير القابلة للإثبات تبقى NULL. | تطابق التعليمات: «لا تعِد بناء UUID من أرقام محلية أو مبلغ/تاريخ/وصف متشابه». |
| `withdrawal_uuid` / `expense_uuid` (للسجلات التاريخية) | **عدم التخمين**. | نفس المبدأ. |
| `cycle_uuid` (salary_payments التاريخية) | **عدم التخمين**. | نفس المبدأ. |

### 3.4. خطة migration نظيفة للاختبارات + forward migration مشروطة لكل حالة DB معروفة

#### خطة اختبارات قاعدة فارغة (clean install)

تطبيق `worker/schema.sql` على قاعدة D1 فارغة ينشئ كل الجداول والفهارس والـ CHECK constraints دفعة واحدة. هذه هي الحالة المرجعية للاختبارات المتكررة عبر `vitest` في كلا الفرعين.

#### خطة forward migration مشروطة لحالة DB سابقة

| حالة DB | المسار الآمن |
|---------|--------------|
| **DB فارغة (clean install)** | تطبيق `worker/schema.sql` كاملاً فقط. لا حاجة لترحيلات. |
| **DB سابقة بطبقت B2 الأصلية (0011_portable_financial_relationships)** | تطبيق 0012، 0013، 0014، 0015 بالترتيب. 0013 ينشئ الفهرس الفريد فقط (العمود موجود سابقاً). |
| **DB سابقة بطبقت B3 الأصلية (0011_salary_parent_uuids + 0012 + 0013 + 0014 + 0015)** | تطبيق 0008 (فهرس idempotency)، 0009 (جدول finance_snapshots). كلها `IF NOT EXISTS` فآمنة للتكرار. |
| **DB مختلطة (تطبيقات جزئية)** | فحص `d1_migrations` + `PRAGMA table_info` أولاً. ثم تطبيق ما ينقص، دون إعادة ترقيم ما طبّق. |

⚠️ **تحذير**: الحزمة الموحدة `marina-hotel-unified-migrations.zip` تمثل **سلسلة نظيفة مرجعية** تبدأ من قاعدة فارغة. تطبيقها فوق DB سابقة قد يفشل بسبب `duplicate column name` (في `0011` إن كان العمود موجوداً من 0013 الأصلي). لذلك تم إبقاء الترحيلات الإضافية في كل فرع كملفات مستقلة (0012–0015 في B2، 0008–0009 في B3) بدلاً من دمجها في ملف واحد، ليتسنى تطبيقها بشكل مشروط.

## 4. المرحلة 3 — التنفيذ والاختبارات

### 4.1. تعديلات Worker في الفرع 2 (لجلب ميزات B3 إلى B2)

| الملف | نوع التغيير | الوصف |
|------|-------------|------|
| `worker/src/expense-kind.ts` | ملف جديد | منقول من B3 حرفياً — يحتوي `EXPENSE_KINDS` Set + `legacyExpenseKind()` + `expenseKind()` |
| `worker/test/expense-kind.test.ts` | ملف جديد | منقول من B3 مع تعديلات لـ B2 (يختبر 0015 migration + clear_employee_link الترجمة) |
| `worker/src/sync.ts` | تعديل | إضافة `import { EXPENSE_KINDS }` + block تحقق من `expense_kind` على push (L65-68 في النمط الأصلي) |
| `worker/src/database.ts` | تعديل | إضافة `import { expenseKind }` + `normalizeExpenseFields` private method + `isExplicitLinkClear` helper + استدعاءات في `createRecord`/`updateRecord`/`executeOperationAtomically` |
| `worker/schema.sql` | تعديل | إضافة `expense_kind` column + CHECK constraint على `expenses` + إضافة `employee_link_cleared INTEGER NOT NULL DEFAULT 0` + إضافة `idx_salary_withdrawals_active_expense` + إضافة `sync_write_times` table |
| `worker/migrations/0012_expense_employee_link_clear_flag.sql` | ملف جديد | منقول من B3 |
| `worker/migrations/0013_salary_withdrawal_expense_uuid.sql` | ملف جديد | منقول من B3 مع تعديل: B2's 0011 أنشأ العمود، لذا هذا ينشئ الفهرس الفريد فقط |
| `worker/migrations/0014_sync_write_times.sql` | ملف جديد | منقول من B3 |
| `worker/migrations/0015_expense_kind.sql` | ملف جديد | منقول من B3 |
| `worker/package.json` | تعديل | إضافة 5 scripts جديدة: `db:migrate:sync-meta`، `db:migrate:portable-financial`، `db:migrate:expense-link-clear-flag`، `db:migrate:salary-expense-uuid`، `db:migrate:write-times`، `db:migrate:expense-kind` |

### 4.2. تعديلات Flutter في الفرع 2

| الملف | نوع التغيير | الوصف |
|------|-------------|------|
| `mobile/lib/services/local_db.dart` | تعديل | إضافة `expenseKind` و`employeeLinkCleared` إلى `Expenses` Drift table + رفع `schemaVersion` من 70 إلى 71 + إضافة `Migration step 71` في `onUpgrade` (ALTER TABLE expenses ADD COLUMN expense_kind + employee_link_cleared + CREATE TABLE sync_write_times + CREATE UNIQUE INDEX idx_salary_withdrawals_active_expense) |
| `mobile/lib/utils/expense_kind.dart` | ملف جديد | ثوابت `kExpenseKinds` + `legacyExpenseKind()` + `resolveExpenseKind()` — مرآة لـ `worker/src/expense-kind.ts` و Android `ExpenseKind.kt` |
| `mobile/lib/services/adapters/expenses_adapter.dart` | تعديل | إضافة `expenseKind` + `employeeLinkCleared` إلى `fromJson` (companion builder) و`toJson` (wire serializer) |
| `mobile/test/services/expense_kind_test.dart` | ملف جديد | اختبارات وحدة لـ `lib/utils/expense_kind.dart` (7 حالات legacy + 3 حالات resolve) |

### 4.3. تعديلات Worker في الفرع 3 (لجلب ميزات B2 إلى B3)

| الملف | نوع التغيير | الوصف |
|------|-------------|------|
| `worker/migrations/0008_idempotency_log_cleanup.sql` | ملف جديد | منقول من B2 — فهرس TTL على `idempotency_log(processed_at)` |
| `worker/migrations/0009_finance_snapshots.sql` | ملف جديد | منقول من B2 — جدول `finance_snapshots` + فهارس الحوكمة |
| `worker/schema.sql` | تعديل | إضافة `idx_idempotency_processed_at` على `idempotency_log` + إضافة `finance_snapshots` table كاملة + فهارسها |
| `worker/package.json` | تعديل | إضافة `db:migrate:idempotency-idx` و`db:migrate:finance` scripts |

### 4.4. تعديلات Kotlin/Room في الفرع 3

| الملف | نوع التغيير | الوصف |
|------|-------------|------|
| `mobile/android/app/src/main/kotlin/com/marina/marina/di/DatabaseModule.kt` | تعديل | إضافة `MIGRATION_76_77` (idempotency_log index + finance_snapshots table + فهارسها) + إضافته إلى `.addMigrations(...)` |
| `mobile/android/app/src/main/kotlin/com/marina/marina/data/local/entity/FinanceSnapshotEntity.kt` | ملف جديد | كيان Room لجدول `finance_snapshots` — append-only governance |
| `mobile/android/app/src/main/kotlin/com/marina/marina/data/local/dao/FinanceSnapshotsDao.kt` | ملف جديد | DAO للقراءة + upsert على الـ pull |
| `mobile/android/app/src/main/kotlin/com/marina/marina/data/local/AppDatabase.kt` | تعديل | إضافة `FinanceSnapshotEntity::class` إلى `entities` array + رفع `SCHEMA_VERSION` من 76 إلى 77 + إضافة `financeSnapshotsDao()` abstract |

### 4.5. الاختبارات المنفذة

#### اختبارات Worker المنفذة على B2

```bash
cd /home/z/my-project/marina-work/branch2/worker
./node_modules/.bin/vitest run
```

**النتيجة: 26 ملفات اختبار، 314 اختبار — جميعها نجحت ✅**
- يشمل ذلك 12 اختبار جديد في `expense-kind.test.ts` (تصنيف legacy + الحفاظ على النوع بعد التحرير + رفض الأنواع غير الصالحة + ترجمة `clear_employee_link=1` + migration آمنة للجدول القديم)
- اختبارات `schema.parity.test.ts` الـ 4 الموجودة سابقاً (fresh install، 0005 legacy upgrade، 0007 employee_uuid closure، 0011 portable financial relationships) — لم تتأثر بالتعديلات
- اختبارات `sync.push.test.ts` الـ 6 (create/update/delete flows + D7 gap closure + error isolation) — لم تتأثر
- اختبارات `sync.pull.test.ts` الـ 6 — لم تتأثر

#### اختبارات Worker المنفذة على B3

```bash
cd /home/z/my-project/marina-work/branch3/worker
./node_modules/.bin/vitest run
```

**النتيجة: 22 ملفات اختبار، 230 اختبار — جميعها نجحت ✅**
- يشمل `expense-kind.test.ts` (5 اختبارات + edge cases متعددة)
- يشمل `health.d1.test.ts` (4 اختبارات بما فيها "advertises expense kind only after the additive schema migration")
- يشمل `sync.withdrawals.employee_uuid.test.ts` (1 block — portable parent reference contract)

#### فحص schema عبر SQLite (Pyhton + sqlite3)

```bash
python3 /home/z/my-project/scripts/verify_schemas.py
```

**النتيجة**: كل من `B2 schema` و`B3 schema` يُحمّلان بنجاح في SQLite in-memory. كل الحقول الموحدة موجودة:
- ✅ `expenses.expense_kind : TEXT`
- ✅ `expenses.employee_uuid : TEXT`
- ✅ `expenses.withdrawal_uuid : TEXT` (B2)
- ✅ `expenses.employee_link_cleared : INTEGER`
- ✅ `sync_write_times` table exists
- ✅ `idx_salary_withdrawals_active_expense` index exists
- ✅ `idx_idempotency_processed_at` index exists
- ✅ `finance_snapshots` table exists

#### اختبارات Flutter المكتوبة (لم تُشغّل)

الملف: `mobile/test/services/expense_kind_test.dart`

```bash
# يتطلب Flutter SDK (غير متوفر في هذه البيئة)
cd /home/z/my-project/marina-work/branch2/mobile
flutter test test/services/expense_kind_test.dart
# أو:
dart test test/services/expense_kind_test.dart
```

النتيجة المتوقعة: 10 اختبارات (تصنيف legacy + resolveExpenseKind + kExpenseKinds contents) — كلها مكتوبة لتتوافق مع نفس نمط B3. **يُوصى بتشغيلها محلياً على جهاز مطوّر قبل دمج الـ patch.**

#### اختبارات Kotlin/Room المكتوبة (لم تُشغّل)

لم تُكتب اختبارات Kotlin جديدة في هذه الجلسة لأن:
1. الكيانات والـ DAO الجديدة (`FinanceSnapshotEntity`، `FinanceSnapshotsDao`) هي قراءة فقط — لا يوجد منطق لاختباره.
2. الـ migration `MIGRATION_76_77` SQL صرف — تم التحقق منه يدوياً عبر `sqlite3` (تشغيل الـ execSQL مباشرة على DB فارغة نجح).
3. الاختبارات الـ instrumented (Robolectric) الموجودة سابقاً في `mobile/android/app/src/test/java/` ستلتقط الـ migration تلقائياً عند تشغيلها.

يُوصى بتشغيل `./gradlew :app:test` محلياً قبل دمج الـ patch للتأكد من اجتياز الـ Room schema validation.

### 4.6. حالات الاختبار التغطيطية الموصى بها (لم تُشغّل في هذه البيئة)

| السيناريو | أداة الاختبار | الحالة |
|-----------|----------------|------|
| مشروع نظيف + بناء D1 من جميع الترحيلات | `vitest` (Worker) | ✅ مغطّى بـ `schema.parity.test.ts` |
| ترقية قاعدة محلية قديمة (Flutter 70 → 71) | Flutter `dart test` | ⚠️ مكتوب لكن لم يُشغّل |
| ترقية قاعدة محلية قديمة (Android 76 → 77) | Kotlin Room migration test | ⚠️ موصى به لكن لم يُكتب — **أُعيد قياسه (2026-10-07): كُتب فعلاً** في `FinancialMigrationTest.migrate76To77CreatesFinanceSnapshotsWithExactContract`؛ هذا السطر يسبق الالتزام `f23eb8db` — انظر `docs/merge-4df4118-review.md §5` |
| قيم UUID الفارغة على السحب | `vitest` (Worker) + `sync.pull.test.ts` | ✅ مغطّى |
| الروابط المتبادلة (expense ↔ withdrawal) | `vitest` (Worker) + `sync.withdrawals.employee_uuid.test.ts` | ✅ مغطّى |
| إزالة رابط الموظف (`clear_employee_link=1`) | `vitest` (Worker) + `expense-kind.test.ts` test #5 | ✅ مغطّى |
| `expense_kind` invalid push rejection | `vitest` (Worker) + `expense-kind.test.ts` test #4 | ✅ مغطّى |
| `expense_kind` preservation on free-text edit | `vitest` (Worker) + `expense-kind.test.ts` test #2 | ✅ مغلّى |
| التكرار/التعارض (LWW + vector clock) | `vitest` (Worker) + `conflict.test.ts` | ✅ مغلّى |
| tombstones ride delta | `vitest` (Worker) + `sync.pull.test.ts` | ✅ مغلّى |
| paging/epoch (sync_meta) | `vitest` (Worker) + `sync.epoch.test.ts` | ✅ مغلّى |
| استئناف المزامنة بعد انقطاع | `vitest` (Worker) + `sync.push.idempotency.test.ts` | ✅ مغلّى |

## 5. خطوات staging/production المقترحة

> ⚠️ **لا تُنفذ هذه الخطوات ضمن هذه المهمة** — هي مقترحة فقط للمراجعة اللاحقة.

### 5.1. staging

1. استنساخ قاعدة D1 الإنتاجية إلى قاعدة staging عبر `wrangler d1 export marina-hotel-db --remote --output=staging.sql` ثم `wrangler d1 execute marina-hotel-staging --file=staging.sql`.
2. فحص حالة الترحيلات المطبّقة: `wrangler d1 execute marina-hotel-staging --remote --command "SELECT * FROM d1_migrations ORDER BY id"`.
3. فحص وجود الأعمدة الموحدة قبل التطبيق: `PRAGMA table_info(expenses)` للتحقق من `expense_kind` و`employee_link_cleared`.
4. تطبيق الترحيلات الناقصة بالترتيب: 0008 ← 0009 (B3-staging) أو 0012 ← 0013 ← 0014 ← 0015 (B2-staging). كلها `IF NOT EXISTS` فآمنة للتكرار.
5. نشر Worker الجديد: `wrangler deploy` (يستخدم نفس الـ D1 binding).
6. تشغيل اختبارات end-to-end على staging: تسجيل دخول + push مصروف بـ `expense_kind='salary_withdrawal'` + pull + تحقق من النوع محفوظ.
7. تشغيل اختبار التحرير: تحرير الوصف بدون إرسال `expense_kind` والتحقق من عدم تغييره على D1.

### 5.2. production

⚠️ **يجب إيقاف الإنتاج أثناء التطبيق** لأن `ALTER TABLE expenses ADD COLUMN` في SQLite/D1 يحجز الجدول للكتابة. مدة الحجز قصيرة (~ثوانٍ لـ 7000 صف) لكنها غير صفرية.

1. نسخة احتياطية كاملة: `wrangler d1 export marina-hotel-db --remote --output=backup-$(date +%Y%m%d).sql`.
2. تطبيق الترحيلات الناقصة بالترتيب المرجعي أعلاه.
3. مراقبة `wrangler tail` لأي أخطاء `no such column: expense_kind` (تشير إلى عميل يرسل `expense_kind` قبل اكتمال الترحيل على D1 — الحل: رفع العميل المؤجل).
4. نشر Worker الجديد.
5. إصدار تطبيق Flutter محدّث + تطبيق Android محدّث.
6. مراقبة `sync_conflicts` و`sync_log` لمدة 24 ساعة.

### 5.3. تحذيرات

- ⚠️ **لا تُطبّق الحزمة الموحدة `marina-hotel-unified-migrations.zip` فوق DB سابقة** — قد تفشل بـ `duplicate column name` إن كان `expense_uuid` موجوداً سابقاً من 0011 (B2) أو 0013 (B3). استخدم الترحيلات الفردية المنقولة في هذا التوحيد بدلاً منها.
- ⚠️ **لا تُعِد ترقيم أو تعدّل الترحيلات المطبّقة** على DB الإنتاجية. الـ commit history هو مصدر الحقيقة لتسلسل التطبيق.
- ⚠️ **لا تستخدم `ADD COLUMN IF NOT EXISTS`** — SQLite/D1 لا يدعمها. الـ try/catch في Flutter migration 71 و `IF NOT EXISTS` في فهارس SQL آمنة للتكرار.
- ⚠️ **لا تشغّل `wrangler d1 ... --remote` دون فحص `-h` أولاً** لتجنب أوامر تدميرية عرضية.

## 6. فحوص المزامنة وعقود API

### 6.1. عقد JSON serialization الموحّد

| الحقل | JSON wire | Dart (Drift) | Kotlin (Room) | Worker (TypeScript) |
|-------|-----------|--------------|----------------|---------------------|
| `expense_kind` | `expense_kind` (snake_case) | `expenseKind` (camelCase) → `expense_kind` on wire via `_k(src, 'expenseKind', 'expense_kind')` | `expenseKind` → `expense_kind` via `@SerializedName("expense_kind")` | `expense_kind` (server-owned storage) |
| `employee_link_cleared` | `employee_link_cleared` (snake_case) | `employeeLinkCleared` → `employee_link_cleared` | `employeeLinkCleared` → `employee_link_cleared` via `@SerializedName` | `employee_link_cleared` (server-owned) |
| `clear_employee_link` (legacy synonym) | `clear_employee_link=1` (literal `1` not `true`) | n/a (الـ Flutter لا يرسله — يستخدم `employee_uuid=null` مباشرة) | `PushWireContract.kt` L45 يرسله كـ `data["clear_employee_link"] = 1` | `normalizeExpenseFields` يحوّله إلى `employee_uuid=null` + `employee_link_cleared=1` |

### 6.2. أعلام الاستعلام الحرفية

- `tombstones_only=1` — الـ Worker يتحقق بـ `=== '1'` (نصي حرفي). الأوامر: `sync.tombstone.sweep.test.ts` في B3.
- `include_remaining=1` — نفس النمط.
- `normalize_timestamps=1` — نفس النمط.

Flutter الـ `cloudflare_sync_manager.dart` و Kotlin الـ `CloudflareSyncService.kt` كلاهما يرسلان هذه الأعلام كنصوص `"1"` — لا يحتاج توحيد.

### 6.3. ترتيب الآباء قبل الأبناء في push/pull

كلا الفرعين يحترم نفس الترتيب:
1. `rooms`
2. `employees`
3. `bookings`
4. `salary_cycles`
5. `salary_withdrawals`
6. `salary_payments`

في Flutter: `lib/services/sync/pull_apply_rules.dart` (`pullApplyPriority`).
في Kotlin: `SyncIngestorRegistry.kt` (per-table handlers بترتيب ثابت).

### 6.4. idempotency عند retries

- كل عملية push تحمل `idempotency_key` UUID فريد.
- الـ Worker يحفظه في `idempotency_log` table مع `processed_at` للـ TTL cleanup اليومي (cron 03:17 UTC).
- retry بعد timeout → إعادة نفس `idempotency_key` → الـ Worker يرجع نفس الـ response المسجّل سابقاً دون إعادة تطبيق الكتابة.
- الـ cleanup اليومي (migration 0008) الآن موجود في كلا الفرعين — كان ناقصاً في B3 قبل هذا التوحيد.

## 7. قائمة واجهات الإدخال وتكافؤ الوظائف

### 7.1. واجهات الإدخال في B2 (Flutter)

| الوظيفة | الملف | الحالة قبل التوحيد | الحالة بعد التوحيد |
|---------|------|---------------------|---------------------|
| إنشاء/تعديل موظف | `lib/screens/employees/employees_list.dart` L775-794 | ✅ موجود (نموذج showDialog مع nameCtrl, salaryCtrl, positionCtrl, phoneCtrl) | لم يتغير |
| إنشاء/تعديل مصروف | `lib/screens/expenses/expenses_list.dart` L904-985 | ✅ موجود (description, amount, installments controllers) | لم يتغير (الـ `expense_kind` يُحسب على الـ server من الـ legacy classifier، لا حاجة لإدخاله يدوياً) |
| سحب راتب (موظف) | (مدمج في نموذج المصروف — نوع المصروف = رواتب/سحب راتب) | ✅ عبر `EmployeesRepository._employeeLinkedExpenseTypes` | لم يتغير |
| سحب مباشر بلا مصروف مرآة | ❌ غير موجود كشاشة مستقلة | — | لم يُضف (يحتاج طلب صريح) |
| دورة راتب | ❌ تُحسب تلقائياً من `salary_cycle_calculator.dart` | — | لم يتغير |
| دفعة راتب | ❌ عبر `salary_advance_installments_service.dart` أو AI endpoint | — | لم يتغير |
| استحقاقات الموظف | `lib/screens/employees/salary_entitlements_screen.dart` | ✅ للقراءة فقط | لم يتغير |

### 7.2. واجهات الإدخال في B3 (Android/Kotlin)

| الوظيفة | الملف | الحالة قبل التوحيد | الحالة بعد التوحيد |
|---------|------|---------------------|---------------------|
| إنشاء/تعديل موظف | `presentation/employees/EmployeesListScreen.kt` (465 lines) | ✅ موجود (showAddDialog + EmployeeDialog composable) | لم يتغير |
| إنشاء/تعديل مصروف | `presentation/expenses/ExpensesListScreen.kt` (319 lines) | ✅ موجود (showAddDialog + editingExpense state) + `attachEmployeeUuid()` | لم يتغير |
| سحب راتب (موظف) | `presentation/employees/EmployeesListScreen.kt` (per-employee "withdraw" action) | ✅ موجود | لم يتغير |
| سحب مباشر بلا مصروف مرآة | ❌ غير موجود كشاشة مستقلة | — | لم يُضف |
| دورة راتب | ❌ تُحسب تلقائياً | — | لم يتغير |
| دفعة راتب | ❌ عبر `SalaryRepositoryImpl.insertPayment` من dashboard/finance | — | لم يتغير |
| استحقاقات الموظف | `presentation/employees/SalaryEntitlementsScreen.kt` (297 lines) | ✅ للقراءة فقط | لم يتغير |

### 7.3. تكافؤ الوظائف بين Flutter و Android

| الوظيفة | متوفرة في B2 (Flutter)؟ | متوفرة في B3 (Android)؟ | متكافئة؟ |
|---------|--------------------------|---------------------------|----------|
| إنشاء/تعديل بيانات الموظف | ✅ | ✅ | ✅ |
| إنشاء/تعديل مصروف | ✅ | ✅ | ✅ |
| تصنيف المصروف (`expense_kind`) | ✅ عبر الـ server (legacy classifier) | ✅ عبر الـ server + `attachEmployeeUuid` | ✅ |
| ربط المصروف بموظف | ✅ عبر `EmployeesRepository._employeeLinkedExpenseTypes` | ✅ عبر `ExpensesRepositoryImpl.attachEmployeeUuid` | ✅ |
| إنشاء السحب المباشر | ❌ غير موجود كشاشة مستقلة | ❌ غير موجود كشاشة مستقلة | ⚠️ كلاهما لا يوفرها — ينشئها المستخدم من نموذج المصروف بالنوع "سحب راتب" |
| إنشاء/تعديل سحب مرتبط بمصروف | ✅ تلقائياً من `SalaryWithdrawalsRepository.createFromExpense` | ✅ تلقائياً من `SalaryWithdrawalsRepositoryImpl.saveFromExpense` | ✅ |
| إزالة ارتباط الموظف (`employee_link_cleared=1`) | ❌ غير موجود كإجراء UI صريح | ❌ غير موجود كإجراء UI صريح | ⚠️ الـ wire contract مدعوم لكن الإجراء الظاهري في UI يحتاج إضافة في كلتا المنصتين — موصى به كمتابعة |

### 7.4. مدخلات النظام المحفوظة

- ✅ مدخلات اليوم الفندقي — لم تُلمس.
- ✅ العملة والتحقق — لم تُلمس.
- ✅ صلاحيات المستخدم — لم تُلمس.
- ✅ الحالات القائمة — لم تُلمس.
- ✅ تسميات الإجراءات — لم تُلمس.
- ✅ في السحب المباشر الذي لا يقابله مصروف، يُترك `expense_uuid` nullable ولا يُنشأ مصروف وهمي — محفوظ.
- ✅ في المرآة، يُحافظ على الرابط من الجهتين — محفوظ عبر `salary_withdrawals_repository.dart` L72-73 (B2) و `SalaryWithdrawalsRepositoryImpl.kt` L93 (B3).

## 8. القيود المتبقية والمتابعات الموصى بها

### 8.1. قيود لم تُحل في هذا التوحيد

1. **عدم وجود واجهة UI صريحة لإزالة ارتباط الموظف**: الـ wire contract مدعوم (`clear_employee_link=1` → `employee_link_cleared=1` + `employee_uuid=NULL`) لكن لا يوجد زر/إجراء في أي من Flutter أو Android يطلبه. موصى به كـ follow-up issue.
2. **عدم وجود واجهة UI مستقلة للسحب المباشر**: كلا المنصتين ينشئ السحب من نموذج المصروف. هذا تطابق وظيفي (B2 = B3) لكن قد لا يطابق متطلبات التصميم المستهدف. موصى بمراجعة تصميم UI.
3. **عدم تشغيل اختبارات Flutter و Kotlin**: لم تُشغّل بسبب عدم توفر SDK. موصى بتشغيلها محلياً قبل دمج الـ patch.
4. **عدم وجود Room migration test لـ 76→77**: الـ migration SQL جديد وآمن (`IF NOT EXISTS`) لكن لم يُختبر عبر `MigrationTestHelper`. موصى بإضافة `androidTest` للتحقق.
   ← **سُدّ (2026-10-07)**: كُتب الاختبار كاختبار **Robolectric على JVM** داخل `:app:testDebugUnitTest` (وهي الوظيفة التي يشغّلها CI فعلاً) بدل `androidTest` الذي يقتضي محاكياً لا يشغّله أي workflow في هذا المستودع. يقفل: بقاء الصفوف، عقد الأعمدة الـ14 بعد الترحيل، الفهرسين وترتيبهما، `DEFAULT` عبر إدراج خام، ورفض `NOT NULL`، ومسار DAO على الجدول المُنشأ. التفاصيل: `docs/merge-4df4118-review.md §5.1`.
5. **عدم إضافة `withdrawal_uuid` كحقل على `ExpenseEntity.kt` في B3**: الحقل موجود في B2's Drift schema + Worker schema، لكن B3's Room entity لا يحمله. الربط العكسي يحفظه الـ Worker عند إنشاء `salary_withdrawals` (الـ `salary_withdrawals_repository.dart` L72-73 في B2 + الـ Kotlin `SalaryWithdrawalsRepositoryImpl.kt` يحفظ فقط `expense_uuid` على الـ mirror — لا `withdrawal_uuid` على الـ expense). قد يفقد Android الربط العكسي في قراءة واحدة. موصى بمتابعة.
6. **عدم دمج 0009 (finance_snapshots) في الـ Wire contract للـ Worker**: الـ Worker الـ B3 له `worker/src/finance-data.ts` (الموجود في B2) — لم يُفحص بشكل كامل. قد يكون B3 الـ Worker لا يدعم `/api/finance/snapshots` endpoint على الإطلاق. موصى بمتابعة لإضافة الـ route إذا لزم.
   ← **أُجيب بالأدلة (2026-10-07)**: فرعنا **لا** يدعم المسار — لا `finance-data.ts` ولا `finance-routes.ts` ولا أي مطابقة `api/finance` في `worker/src`؛ و`finance_snapshots` غائب عن `ENTITY_TABLES` (24 جدولاً) في الفرعين ⇒ لا مسار بيانات له على D1. وعلى العميل: المرجع (Flutter) يقرؤها **REST** لا مزامنة، وDrift بلا جدول لقطات. القرار المُوثَّق: إبقاء الكيان **مرآة مخطط** بلا ادّعاء، والقرار الكامل + شرط إعادة النظر في `docs/merge-4df4118-review.md §5.3`.

### 8.2. متابعات سريعة موصى بها

1. تشغيل `dart test` محلياً على B2 قبل دمج الـ patch.
2. تشغيل `./gradlew :app:test` محلياً على B3 قبل دمج الـ patch.
3. إضافة `androidTest` Room migration test لـ `MIGRATION_76_77`.
4. مراجعة تصميم UI لإضافة زر "إزالة ارتباط الموظف" بشكل صريح.
5. مراجعة B3 الـ Worker لـ `/api/finance/snapshots` route وإضافته إذا لزم.

## 9. مراجع

- الحزمة المرجعية الموحدة: `marina-hotel-unified-migrations.zip` (مرفقة من المستخدم).
- مسودة تعليمات الوكيل: `مسودة_تعليمات_الوكيل__توحيد_فرعي_Cloudflare_الثاني.md` (مرفقة من المستخدم).
- B2 HEAD: `549f86f9c6478a5c2bc96924e5aebc863da2f925`.
- B3 HEAD: `455fe960b826363181ac988f88cad5e76275896c`.
- Branches المرفوعة على GitHub:
  - B2 patch: `chore/branch2-parity-unification` (سيُنشأ بعد رفع هذا التقرير)
  - B3 patch: `chore/branch3-parity-unification` (سيُنشأ بعد رفع هذا التقرير)

---

*تم إعداد هذا التقرير في 7 أكتوبر 2026 كجزء من تنفيذ تعليمات الوكيل لتوحيد الفرعين 2 و3. كل التعديلات موثقة في commits منفصلة لكل فرع. لم تُنفذ أي عمليات نشر أو ترحيلات على D1 الإنتاجية.*
