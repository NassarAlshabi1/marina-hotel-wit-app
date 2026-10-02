# مسودة: تحصين الربط بين الموظفين والمصروفات ومسحوبات الرواتب

> **الحالة:** مسودة للنقاش — لم يُنفَّذ أي تغيير في الكود بعد.
> **الفرع:** `refactor/performance-fixes-v2`
> **التاريخ:** 2026-10-02 (تحديث 2: إضافة المزامنة عبر Cloudflare D1 + عقد الاستعلامات)
> **الهدف:** ألا تُفقد أي بيانات رواتب أو مصروفات مستقبلاً، وألا تُنسب لموظف خاطئ، عبر كل المسارات: الإدخال، التعديل، الحذف، المزامنة (Appwrite حالياً ← **Cloudflare D1** مستقبلاً)، النسخ الاحتياطي والاستعادة (محلي / Google Drive / D1)، والتقارير والاستعلامات.

---

## 1. الوضع الحالي باختصار

### 1.1 الجداول (`lib/services/local_db.dart` — `schemaVersion = 67`)

| الجدول | الربط بالموظف | الربط بالمصروف | ملاحظات |
|---|---|---|---|
| `employees` | — | — | `id` تلقائي محلي + `localUuid UNIQUE` + `serverId` (غير موثوق) |
| `expenses` | `relatedId` (id محلي، **بدون FK**) + `employeeUuid` (Migration 46) | — | `expenseType` نص حر يحدد إن كان "راتب" |
| `salary_withdrawals` | `employeeId` (FK إلى `employees.id`، بلا `ON DELETE`) + `employeeUuid` (Migration 67) | `expenseId` (id محلي، **بدون FK وغير فريد**) + `reason = 'exp_<id>'` | السحب المباشر: `expenseId = 0`، `reason = 'direct_withdrawal_<uuid>'` |
| `salary_cycles` / `salary_carry_over_logs` | `employeeId` (FK) + `employeeUuid` | — | `UNIQUE(employeeId, cycleKey)` في الدورات |

### 1.2 نمط "المرآة" (Mirror)
عند حفظ مصروف من نوع راتب/سحب/خصم/سلفة في شاشة المصروفات، يُنشأ صف مرآة في `salary_withdrawals`
يشير للمصروف عبر **الـ id المحلي للمصروف** (`expense_id` و`reason='exp_N'`).
المطابقة لاحقاً تتم على 4 مستويات (`salary_mirror_matcher.dart`)، آخرها **يتجاهل المبلغ**.

### 1.3 المشكلة الجذرية
**الروابط مبنية على معرّفات محلية رقمية (autoincrement) لا تعني الشيء نفسه على جهاز آخر أو بعد الاستعادة من Drive.**
الـ UUID موجود لكن استخدامه جزئي: بعض المسارات تكتبه وبعضها تتجاهله، والحسابات والتقارير تعتمد على الأرقام فقط.

---

## 2. مخاطر فقدان/إفساد البيانات المكتشفة (مرتبة حسب الخطورة)

> كل بند مدعوم بموقع في الكود. تم التحقق يدوياً من البنود المعلَّمة بـ ✔.

| # | الخطر | الموقع | الأثر |
|---|---|---|---|
| R1 ✔ | **حذف نهائي (hard delete) للسجلات اليتيمة بعد كل مزامنة** — `DELETE FROM salary_withdrawals/salary_cycles/salary_payments WHERE rowid=?` بلا tombstone ولا outbox | `appwrite_sync_manager.dart` ~8597-8620 (`_performPostSyncIntegrityCheck`) | فقدان نهائي لسجلات لم تُرفع بعد |
| R2 ✔ | **"الطريقة 2" عادت بعد دمج `07c26a65`**: مطابقة `employeeId` البعيد كأنه id محلي — يربط المسحوب بموظف خاطئ على الأجهزة الجديدة (الإصلاح الأصلي `1c83e916` أُلغي فعلياً) | `appwrite_sync_manager.dart` ~4043-4050 (مسحوبات) و ~7705-7720 (دورات) | نسب رواتب لموظف خاطئ |
| R3 ✔ | **تصادم `expense_id` بين الأجهزة**: المسحوب القادم من جهاز آخر يحمل id مصروف ذلك الجهاز؛ `deleteByExpenseId` لا يفلتر بالموظف | `salary_withdrawals_repository.dart` ~505-575 و ~298-336 (`saveFromExpense`) | حذف/تعديل مسحوب موظف آخر، وينتشر لكل الأجهزة (remote-delete-wins) |
| R4 | **حفظ المصروف + المرآة في معاملتين منفصلتين** (وكذلك الحذف) | `expenses_list.dart` ~862, ~1202-1220, ~1244-1275 | مصروف بلا مرآة، أو مرآة محذوفة ومصروف باقٍ |
| R5 | **نقطة التحقق (checkpoint) تتقدم رغم تخطي سجلات يتيمة** — لا تُجلب ثانية إلا إن تغيرت في السحابة | `sync_core/unified_pull_engine.dart` ~224-230 | سجلات مفقودة على الجهاز بصمت |
| R6 | **مسحوب يُزال من طابور الرفع إن لم يوجد موظفه محلياً** (`return true`) | `appwrite_sync_manager.dart` ~4234-4241 | لا يصل للسحابة أبداً |
| R7 ✔ | **مزامنة Drive Delta تتجاهل `salary_withdrawals` و`salary_carry_over_logs`** (لا يوجد `case` لهما في `_applyChange`) | `google_drive_delta_sync.dart` ~405-446 | تغييرات تُسقط بصمت |
| R8 ✔ | **محوّل المصروفات يخزن `relatedId` البعيد الخام** عند فشل حل الـ UUID؛ و`isSalaryExpenseType` لا يشمل `'سلفة'` | `adapters/expenses_adapter.dart` ~126-132، `payload_mapper.dart` ~928-940 | سلفة/راتب تُحسب على موظف خاطئ |
| R9 | **الدفع الكامل وما بعد الاستعادة يرفع مسحوبات بلا `employeeUuid`** وبـ `employeeId` مُعاد ترقيمه | `appwrite_sync_manager.dart` ~5933-5945 | يكتب فوق روابط صحيحة في السحابة |
| R10 | **استعادة Drive الكاملة تعيد الترقيم** ولا تعيد ربط `expense_id`/`relatedId` (فقط payments/debts) | `google_drive_backup_service.dart` ~1269-1830 | روابط مكسورة بعد الاستعادة |
| R11 | **الاستعادة المحلية JSON تمسح جدول `outbox`** ولا تمسح `sync_checkpoints` | `local_backup_service.dart` ~617-649 | ضياع تعديلات غير مرفوعة + عدم جلب ما استجد في السحابة |
| R12 | **`saveFromExpense` لا يحدّث `employeeUuid` عند تغيير موظف المصروف**، و`EmployeeLinkConsistencyService` يصلح `employeeId` فقط | `salary_withdrawals_repository.dart` ~301-316، `employee_link_consistency_service.dart` ~162-167 | UUID قديم ينتشر للسحابة |
| R13 | **مستوى المطابقة 4 يتجاهل المبلغ** + "تبنّي اليتيم" بالمبلغ واليوم | `salary_mirror_matcher.dart` ~93-110، `salary_withdrawals_repository.dart` ~435-490 | إخفاء مسحوب حقيقي أو اختطافه |
| R14 | **`employees.serverId` غير موثوق**: لا يُرسل في دفع الموظف العادي، ويُكتب محلياً فقط من دفع المسحوبات | `payload_mapper.dart` ~363-406، `appwrite_sync_manager.dart` ~4222 | تصادمات في الحل الاحتياطي |
| R15 | **الفهارس لا تُنشأ في التثبيت الجديد** (`List<Index> get indexes` يتجاهله Drift 2.x)؛ `idx_salary_withdrawals_employee` لا يُنشأ إطلاقاً | `local_db.dart` ~166, ~194, ~768 | بطء (ليس فقدان بيانات، لكنه يدفع لحلول التفافية) |
| R16 | **التصنيف بـ `contains`** (`خصم`، `رواتب`) والأقساط بـ `description.contains('قسط سلفة')` | `salary_expense_classifier.dart` ~50-68، `salary_entitlement_service.dart` ~129, ~547 | تعديل وصف يغيّر المحاسبة |
| R17 | **Cloudflare D1**: `INSERT OR REPLACE` على الـ id المحلي → أجهزة متعددة تكتب فوق بعضها | `cloudflare_d1_service.dart` ~343-352 | نسخة احتياطية سحابية غير موثوقة |
| R18 | **الاستيراد JSON للمصروفات يُسقط `employeeUuid` و`isAutoGenerated`** | `expenses_dao.dart` ~541-557 | فقدان الربط بعد الاستيراد |

---

## 3. المبادئ المقترحة (العقد الجديد)

1. **الـ UUID هو المفتاح الوحيد العابر للأجهزة.** الأرقام المحلية (`id`, `employeeId`, `relatedId`, `expenseId`) مجرد cache محلي يُعاد حسابه من الـ UUID — ولا يُرسل للسحابة كرابط ولا يُقرأ منها كرابط.
2. **لا حذف نهائي لبيانات مالية أبداً.** كل حذف = soft delete (`deletedAt`) + outbox. السجل اليتيم يُعزل (quarantine) ولا يُحذف.
3. **كل عملية متعددة الجداول = معاملة واحدة.** (مصروف + مرآة، حذف مصروف + مرآة، تعديل موظف + إصلاح روابط).
4. **السجل الذي لا يمكن ربطه يُحتفظ به ويُعاد محاولته** — لا يُتخطى بصمت ولا تتقدم نقطة التحقق فوقه.
5. **الربط صريح لا استدلالي.** لا مطابقة بالمبلغ/اليوم/النص إلا كمسار ترحيل لمرة واحدة مع سجل تدقيق.

---

## 4. التغييرات المقترحة

### المرحلة 0 — إيقاف النزيف (عاجل، تغييرات صغيرة وآمنة)

| # | التغيير | يعالج |
|---|---|---|
| P0.1 | استبدال `DELETE` في `_performPostSyncIntegrityCheck` بنقل السجل إلى جدول عزل `orphan_quarantine` (JSON كامل + سبب + تاريخ) أو على الأقل ترك السجل وتسجيل تحذير | R1 |
| P0.2 | حذف "الطريقة 2" (id بعيد = id محلي) من `_syncSalaryWithdrawals` و`_syncSalaryCycles` وإعادة تطبيق `1c83e916` (الاعتماد على `IdResolver.resolveEmployee(fromRemote: true)`) | R2 |
| P0.3 | `deleteByExpenseId` و`saveFromExpense`: إضافة شرط `employee_uuid = ?` (أو `employee_id`) + تجاهل المسحوبات ذات `origin='remote'` في المطابقة بالـ id المحلي | R3 |
| P0.4 | في `expenses_adapter.fromJson`: عدم الرجوع لـ `relatedId` الخام للمصروفات المرتبطة بموظف — `null` إن فشل حل الـ UUID؛ وإضافة `'سلفة'` إلى `isSalaryExpenseType` | R8 |
| P0.5 | `return true` في رفع المسحوب عند غياب الموظف → `return false` (يبقى في الطابور) + تسجيل | R6 |
| P0.6 | إضافة `case 'salary_withdrawals'` و`case 'salary_carry_over_logs'` في `GoogleDriveDeltaSync._applyChange` | R7 |

### المرحلة 1 — ربط المصروف بالمسحوب عبر UUID

**Migration 68:**
```sql
ALTER TABLE salary_withdrawals ADD COLUMN expense_uuid TEXT;   -- = expenses.local_uuid
CREATE INDEX IF NOT EXISTS idx_sw_expense_uuid   ON salary_withdrawals(expense_uuid);
CREATE INDEX IF NOT EXISTS idx_sw_employee_uuid  ON salary_withdrawals(employee_uuid);
CREATE INDEX IF NOT EXISTS idx_sw_employee_id    ON salary_withdrawals(employee_id);
CREATE INDEX IF NOT EXISTS idx_exp_employee_uuid ON expenses(employee_uuid);
-- مرآة واحدة فقط لكل مصروف نشط:
CREATE UNIQUE INDEX IF NOT EXISTS ux_sw_expense_uuid_active
  ON salary_withdrawals(expense_uuid)
  WHERE expense_uuid IS NOT NULL AND deleted_at IS NULL;
```

**Backfill (لمرة واحدة، محلياً فقط):**
1. للمسحوبات المحلية المنشأ (`origin` محلي) ذات `expense_id > 0`: `expense_uuid = (SELECT local_uuid FROM expenses WHERE id = expense_id)`.
2. للمسحوبات القادمة من السحابة: **لا** تُملأ بالـ id — تُترك `NULL` حتى تصل من السحابة قيمة `expenseUuid` صحيحة من الجهاز المنشئ (الذي يملك المصروف الحقيقي).
3. تسجيل كل ما لم يُحل في تقرير (لا حذف).

**المزامنة:**
- `salaryWithdrawalToRemote`: إرسال `expenseUuid` و`employeeUuid` **دائماً من عمود الصف نفسه** (لا من معامل اختياري).
- `SalaryWithdrawalsAdapter.fromJson`: حل `expense_uuid` → `expense_id` محلي إن وُجد المصروف، وإلا `expense_id = NULL` (لا الرقم البعيد).
- إضافة `expenseUuid` لمخطط Appwrite (`appwrite_schema_verifier.dart`) و D1.
- `salaryCycleToRemote` و`salaryCarryOverLogToRemote`: إضافة `employeeUuid`.

**الاستعلامات:** `deleteByExpenseId`، `saveFromExpense`، `SalaryMirrorMatcher` تعتمد على `expense_uuid` أولاً. المطابقة بالنص `exp_N` تبقى قراءة فقط للسجلات القديمة. **حذف المستوى 4** (تجاهل المبلغ) من المطابق.

### المرحلة 2 — معاملات ذرية

إنشاء خدمة واحدة `SalaryExpenseService` (Deep module) تكون **الطريق الوحيد** لكتابة مصروف راتب:

```dart
Future<void> saveSalaryExpense(ExpenseDraft draft);   // مصروف + مرآة + outbox × 2 في _db.transaction واحدة
Future<void> deleteSalaryExpense(String expenseUuid); // soft-delete للاثنين + outbox في معاملة واحدة
Future<void> reassignEmployee(String expenseUuid, String newEmployeeUuid); // يحدّث relatedId + employeeUuid في الطرفين
```
- كل القراءات (البحث عن المرآة) داخل المعاملة نفسها.
- الإشعارات تُطلق **بعد** نجاح المعاملة (`afterCommit`)، لا داخلها.
- `expenses_list.dart` و`settings_employees.dart` يستدعيان الخدمة فقط.
- نفس النمط المطبق حالياً في `SalaryAdvanceInstallmentsService.createInstallmentAdvance`.

### المرحلة 3 — الموظف والحذف

- حذف الموظف: soft delete فقط (كما هو) + **منع** `hardDelete` إن وُجدت أي سجلات مالية (حتى المحذوفة soft).
- `EmployeeLinkConsistencyService`: يحدّث `employeeUuid` أيضاً عند إنقاذ اليتيم، ويُصلح `salary_cycles` و`salary_carry_over_logs` لا أن يعدّها فقط.
- الحسابات والتقارير (`salary_entitlement_service.dart` ~106, ~667؛ `salary_withdrawals_report_screen.dart` ~310, ~374): التجميع بـ `employee_uuid` مع fallback لـ `employee_id`.
- إرسال `serverId`/`id` المنشئ في `employeeToRemote` أو — أفضل — التخلي عن `serverId` كمسار حل للموظفين نهائياً بعد اكتمال backfill الـ UUID في السحابة.

### المرحلة 4 — المزامنة: لا تخطٍّ صامت

- جدول `pending_links (table, local_uuid, missing_parent_uuid, payload_json, attempts, first_seen)`.
- عند فشل حل الأب أثناء السحب: حفظ الـ payload في `pending_links` بدلاً من `continue`.
- بعد سحب `employees`/`expenses` في كل دورة: إعادة محاولة `pending_links`.
- نقطة التحقق لا تتقدم فوق أقدم سجل معلّق — أو (أبسط) إعادة المحاولة من `pending_links` تغني عن إعادة الجلب.

### المرحلة 5 — النسخ الاحتياطي والاستعادة

| المسار | التغيير |
|---|---|
| JSON محلي | **لا** يمسح `outbox`؛ يمسح `sync_checkpoints` بعد الاستعادة لإجبار سحب كامل؛ الاستيراد يحفظ `employeeUuid` و`expenseUuid` و`isAutoGenerated` (R18) |
| Drive كامل | بعد الاستعادة: خطوة إعادة ربط عامة تعيد حساب كل الأعمدة الرقمية (`employee_id`, `related_id`, `expense_id`) من أعمدة الـ UUID |
| Drive delta | دعم جداول الرواتب (P0.6) + فحص الأحدث يفوز (`lastModified`) قبل الكتابة |
| بعد الاستعادة → السحابة | `pushAllLocalDataToAppwrite` يرسل الروابط بالـ UUID فقط |
| Comprehensive Appwrite | إضافة `salary_withdrawals` و`salary_carry_over_logs`؛ عدم الكتابة فوق مستند أحدث (مقارنة `lastModified`) |
| Cloudflare D1 | يصبح هو مسار المزامنة نفسه: الاستعادة = سحب كامل من `server_seq = 0` إلى قاعدة فارغة، والأرقام المحلية تُشتق من الـ UUID (القسم 5). النسخة الاحتياطية الحالية ذات المفتاح `id` تُنقل لقاعدة منفصلة، أو تُوقف (R17) |

### المرحلة 6 — شبكة أمان دائمة

- **فحص سلامة دوري (قراءة فقط)** يعرض في شاشة الصيانة:
  - مصروفات راتب نشطة بلا مرآة نشطة / مرايا نشطة بلا مصروف.
  - سجلات بـ `employee_uuid` لا يطابق أي موظف.
  - تعارض بين `employee_id` و`employee_uuid` في نفس الصف.
  - أكثر من مرآة نشطة لنفس `expense_uuid`.
- **نسخة احتياطية تلقائية قبل أي migration** على جداول الرواتب.
- **سجل تدقيق** لكل إصلاح تلقائي (من، متى، القيمة القديمة/الجديدة).
- إصلاح الفهارس: الانتقال إلى `@TableIndex` أو إنشاؤها في `onCreate` + `beforeOpen` بـ `IF NOT EXISTS` (R15).

---

## 5. المزامنة عبر Cloudflare D1: السلوك الأفضل

> **السياق:** المزامنة تنتقل إلى Cloudflare D1.
> **الوضع الحالي في الكود:** D1 مستخدم الآن **للرفع في اتجاه واحد فقط** (نسخة احتياطية) — `cloudflare_d1_service.dart` + `cloudflare_d1_tab.dart`:
> - ينسخ مخطط SQLite المحلي كما هو (المفتاح الأساسي = `id` المحلي).
> - يكتب بـ `INSERT OR REPLACE` من نتيجة `SELECT *`.
> - لا يوجد سحب، ولا حذف، ولا حل تعارضات.
>
> هذا التصميم **لا يصلح للمزامنة كما هو**. القسم التالي يصف السلوك المطلوب من البداية حتى لا نكرر أخطاء Appwrite (R1–R14).

### 5.1 أخطاء المسار الحالي التي يجب ألا تنتقل للمزامنة

| # | السلوك الحالي | لماذا يُفقد البيانات في المزامنة |
|---|---|---|
| D1-1 | المفتاح الأساسي في D1 = `id` المحلي | جهازان لهما `employees.id = 3` لشخصين مختلفين → الثاني **يكتب فوق** الأول |
| D1-2 | `INSERT OR REPLACE` | `REPLACE` في SQLite = حذف الصف ثم إدراجه من جديد. أي عمود لم يُرسل يضيع، ونسخة قديمة تكتب فوق نسخة أحدث بلا أي فحص |
| D1-3 | `employee_id` و`related_id` و`expense_id` تُرفع كأرقام محلية | لا معنى لها على أي جهاز آخر |
| D1-4 | لا يوجد مؤشر تغيّر من جهة الخادم | لا يمكن سحب "ما تغيّر منذ آخر مرة" بشكل موثوق، و`last_modified` يعتمد على ساعة الجهاز |
| D1-5 | توكن Cloudflare API (صلاحية كتابة على الحساب) مخزّن في التطبيق | أي جهاز مسروق أو APK مفكوك = تحكم كامل في قاعدة البيانات |
| D1-6 | الحذف المحلي لا يصل إلى D1 | السجل المحذوف يعود عند الاستعادة أو السحب |

### 5.2 المعمارية المقترحة

```
[التطبيق] ──HTTPS + توكن جهاز──▶ [Cloudflare Worker /sync] ──binding──▶ [D1: hotel_sync]
                                         │
                                         └── batch() = معاملة ذرية + params آمنة
```

- **Worker وسيط (موصى به بقوة)** بدل نداء REST API مباشرة من التطبيق:
  - يحل D1-5: التطبيق يحمل توكن جهاز قابل للإلغاء، لا توكن الحساب.
  - `env.DB.batch([...])` ينفذ كل عبارات الدفعة **في معاملة واحدة**، ويقبل `params`. يزيل قيد REST الحالي ("params with multiple statements is not supported") والحاجة لبناء SQL حرفي.
  - فيه يُطبَّق التحقق من الروابط وقاعدة "الأحدث يفوز" مرة واحدة لكل الأجهزة.
- **قاعدة D1 منفصلة للمزامنة** (`hotel_sync`) عن قاعدة النسخ الاحتياطي الحالية. لا نخلط الجداول ذات المفتاح `id` بجداول المزامنة ذات المفتاح `uuid`.
- **مسار احتياطي:** إن تأخر إنشاء الـ Worker، يمكن تطبيق نفس القواعد عبر REST بعبارات حرفية — بشرط تطبيق 5.3 و5.4 حرفياً، وقبول بقاء خطر التوكن (D1-5).

### 5.3 مخطط D1 لجداول المزامنة (العقد)

```sql
-- عدّاد تسلسلي من جهة الخادم: مؤشر السحب لا يعتمد على ساعات الأجهزة
CREATE TABLE sync_seq (id INTEGER PRIMARY KEY CHECK (id = 1), seq INTEGER NOT NULL);
INSERT INTO sync_seq VALUES (1, 0);

CREATE TABLE employees (
  uuid          TEXT PRIMARY KEY,            -- = local_uuid
  name          TEXT NOT NULL,
  basic_salary  REAL NOT NULL,
  status        TEXT NOT NULL,
  -- ... باقي الحقول الوصفية
  version       INTEGER NOT NULL,
  last_modified INTEGER NOT NULL,
  device_id     TEXT NOT NULL,
  deleted_at    INTEGER,                     -- tombstone، لا DELETE أبداً
  server_seq    INTEGER NOT NULL,            -- يعيّنه الـ Worker
  server_ts     INTEGER NOT NULL
);

CREATE TABLE expenses (
  uuid          TEXT PRIMARY KEY,
  expense_kind  TEXT NOT NULL,               -- انظر 6.4
  expense_type  TEXT NOT NULL,               -- النص المعروض فقط
  employee_uuid TEXT,                        -- إلزامي إن كان expense_kind من عائلة الرواتب
  amount REAL NOT NULL, date TEXT NOT NULL, hotel_day_key TEXT,
  description TEXT, is_auto_generated INTEGER NOT NULL DEFAULT 0,
  version INTEGER NOT NULL, last_modified INTEGER NOT NULL, device_id TEXT NOT NULL,
  deleted_at INTEGER, server_seq INTEGER NOT NULL, server_ts INTEGER NOT NULL
);

CREATE TABLE salary_withdrawals (
  uuid          TEXT PRIMARY KEY,
  employee_uuid TEXT NOT NULL,               -- لا يُقبل مسحوب بلا موظف
  expense_uuid  TEXT,                        -- NULL = سحب مباشر من شاشة الموظفين
  amount REAL NOT NULL, withdraw_date TEXT, hotel_day_key TEXT,
  withdrawal_type TEXT, description TEXT, recorder_name TEXT,
  version INTEGER NOT NULL, last_modified INTEGER NOT NULL, device_id TEXT NOT NULL,
  deleted_at INTEGER, server_seq INTEGER NOT NULL, server_ts INTEGER NOT NULL
);
-- salary_cycles / salary_payments / salary_carry_over_logs بنفس النمط: employee_uuid (وcycle_uuid) بدل الأرقام

CREATE INDEX ix_emp_seq   ON employees(server_seq);
CREATE INDEX ix_exp_seq   ON expenses(server_seq);
CREATE INDEX ix_exp_emp   ON expenses(employee_uuid);
CREATE INDEX ix_sw_seq    ON salary_withdrawals(server_seq);
CREATE INDEX ix_sw_emp    ON salary_withdrawals(employee_uuid);
CREATE UNIQUE INDEX ux_sw_expense_active
  ON salary_withdrawals(expense_uuid) WHERE expense_uuid IS NOT NULL AND deleted_at IS NULL;
```

**قواعد المخطط:**
- **لا أعمدة `id` / `employee_id` / `related_id` / `expense_id` في D1 إطلاقاً.** هذه أرقام محلية تُشتق على كل جهاز (انظر 6.1). يحل D1-1 وD1-3.
- **لا FOREIGN KEY في D1.** الأب والابن قد يصلان في دفعات مختلفة، وFK سيرفض الابن أو يحذفه. السلامة المرجعية تُراقَب عبر view (انظر 5.7) ولا تُفرض بالحذف.
- **لا `DELETE` من جداول المزامنة أبداً.** الحذف = `deleted_at` + زيادة `version`. يحل D1-6.

### 5.4 الرفع (Push)

1. **المصدر:** جدول `outbox` المحلي فقط (لا `SELECT *` من الجداول). كل عنصر يحمل `uuid` و`version` و`idempotency_key`.
2. **الترتيب:** `employees` → `expenses` → `salary_cycles` → `salary_withdrawals` → `salary_payments` → `salary_carry_over_logs`. هذا الترتيب داخل الدفعة الواحدة أيضاً.
3. **تحويل الروابط قبل الإرسال:** `employee_id` → `employee_uuid`، `expense_id` → `expense_uuid` (من الجداول المحلية لحظة الرفع). إن لم يُعرف الـ UUID **لا يُرسل السجل ويبقى في الطابور** مع خطأ ظاهر — لا يُحذف من الطابور (عكس R6).
4. **الكتابة في D1 = upsert مشروط، لا REPLACE** (يحل D1-2):
   ```sql
   INSERT INTO salary_withdrawals (uuid, employee_uuid, expense_uuid, amount, ..., version, last_modified, device_id, deleted_at, server_seq, server_ts)
   VALUES (?1, ?2, ?3, ?4, ..., ?v, ?lm, ?dev, ?del, :seq, :now)
   ON CONFLICT(uuid) DO UPDATE SET
     employee_uuid = excluded.employee_uuid,
     expense_uuid  = excluded.expense_uuid,
     amount        = excluded.amount,
     -- ...
     version = excluded.version, last_modified = excluded.last_modified,
     device_id = excluded.device_id, deleted_at = excluded.deleted_at,
     server_seq = excluded.server_seq, server_ts = excluded.server_ts
   WHERE excluded.version > salary_withdrawals.version
      OR (excluded.version = salary_withdrawals.version
          AND excluded.last_modified > salary_withdrawals.last_modified)
      OR (excluded.version = salary_withdrawals.version
          AND excluded.last_modified = salary_withdrawals.last_modified
          AND excluded.device_id > salary_withdrawals.device_id);
   ```
   - `:seq` يأتي من `UPDATE sync_seq SET seq = seq + 1 RETURNING seq` داخل نفس الـ `batch`.
   - **قاعدة الحذف:** إن كان السجل في D1 محذوفاً (`deleted_at` غير فارغ) والوارد غير محذوف بنفس الـ version أو أقل → يُرفض (الحذف لا يتراجع بنسخة قديمة). الاستعادة المقصودة من الحذف تتطلب `version` أعلى صراحةً.
5. **التأكيد قبل إفراغ الطابور:** الـ Worker يرجع لكل `uuid` الحالة: `applied` أو `stale` (في D1 نسخة أحدث) أو `rejected` (+ السبب). عنصر الـ outbox لا يُعلَّم "تم" إلا مع `applied` أو `stale`. حالة `stale` تطلق سحباً فورياً لذلك السجل.
6. **التحقق في الـ Worker قبل الكتابة:**
   - `salary_withdrawals.employee_uuid` غير فارغ.
   - المصروف من عائلة الرواتب له `employee_uuid`.
   - `expense_uuid` لا يتكرر لمسحوبين نشطين (الفهرس `ux_sw_expense_active` يضمن ذلك؛ التعارض يرجع `rejected: duplicate_mirror`).
   - **لا يُرفض السجل لأن الأب لم يصل بعد** — فقط يُسجَّل في `v_orphans`.

### 5.5 السحب (Pull)

1. **مؤشر لكل جدول = `server_seq`** (لا `updated_at`، لا ساعة الجهاز):
   ```sql
   SELECT * FROM salary_withdrawals WHERE server_seq > ?cursor ORDER BY server_seq LIMIT 500;
   ```
2. **الترتيب:** نفس ترتيب الرفع (الآباء أولاً).
3. **التطبيق المحلي لكل دفعة في معاملة Drift واحدة:**
   - upsert بالـ `local_uuid` مع نفس قاعدة "الأحدث يفوز" (version ← last_modified ← device_id).
   - **اشتقاق الأرقام المحلية من الـ UUID:** `employee_id = (SELECT id FROM employees WHERE local_uuid = employee_uuid)`، ونفس الشيء لـ `related_id` و`expense_id`.
   - إن لم يوجد الأب محلياً: **يُحفظ السجل في `pending_links`** (المرحلة 4)، لا يُتخطى ولا يُحذف. لأنه محفوظ محلياً يمكن أن يتقدم المؤشر بأمان (يحل R5).
   - **تحديث المؤشر داخل نفس المعاملة.** إن فشلت المعاملة لا يتقدم المؤشر ولا يُفقد شيء.
4. **بعد كل سحب لـ `employees` أو `expenses`:** إعادة محاولة `pending_links`.
5. **الحذف القادم من D1 (`deleted_at`) → soft delete محلي فقط.** لا يُطلق أي `DELETE` محلي.
6. **لا يوجد "فحص سلامة بعد المزامنة يحذف اليتيم"** في المسار الجديد (يحل R1).

### 5.6 الانتقال من Appwrite إلى D1 (مرة واحدة)

1. **قبل الانتقال، على كل جهاز:**
   - تشغيل backfill الـ UUID محلياً (`employee_uuid` و`expense_uuid`، المرحلة 1).
   - نسخة احتياطية محلية كاملة.
   - تقرير "سجلات بلا UUID" يجب أن يكون صفراً، أو مراجعاً يدوياً.
2. **البذر (seed):** الجهاز الأكمل بيانات يرفع كل جداوله عبر نفس مسار الـ push (upsert مشروط بالـ uuid). لا مسار رفع خاص.
3. **باقي الأجهزة:** ترفع ما لديها (الـ upsert المشروط يدمج ولا يكتب فوق ما هو أحدث)، ثم تسحب كل شيء من `server_seq = 0`.
4. **فترة انتقالية:** Appwrite للقراءة فقط (لا كتابة) مع مفتاح إيقاف في Remote Config. لا مزامنة مزدوجة كتابةً في نفس الوقت.
5. **المقارنة:** عدد السجلات ومجموع المبالغ لكل موظف (`v_employee_salary_totals`) بين Appwrite وD1 وكل جهاز. لا يُوقف Appwrite قبل التطابق.

### 5.7 مراقبة السلامة في D1 (قراءة فقط)

```sql
CREATE VIEW v_orphans AS
  SELECT 'salary_withdrawals' AS tbl, uuid, employee_uuid AS missing
    FROM salary_withdrawals sw
   WHERE deleted_at IS NULL
     AND NOT EXISTS (SELECT 1 FROM employees e WHERE e.uuid = sw.employee_uuid)
  UNION ALL
  SELECT 'expenses', uuid, employee_uuid
    FROM expenses x
   WHERE deleted_at IS NULL AND employee_uuid IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM employees e WHERE e.uuid = x.employee_uuid)
  UNION ALL
  SELECT 'salary_withdrawals(expense)', uuid, expense_uuid
    FROM salary_withdrawals sw
   WHERE deleted_at IS NULL AND expense_uuid IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM expenses x WHERE x.uuid = sw.expense_uuid AND x.deleted_at IS NULL);
```
> ملاحظة: الكود الحالي سجّل فشل compound SELECT (UNION) عند 6 عناصر عبر REST. الـ view بثلاثة عناصر، ويُستعلم عنه من الـ Worker. إن ظهرت المشكلة نفسها نقسمه إلى ثلاثة views.

- يُعرض العدد في شاشة الصيانة. **لا إصلاح تلقائي بالحذف أبداً.**

---

## 6. عقد الربط الجديد في التقارير والاستعلامات

### 6.1 القاعدة الذهبية

| العمود | الدور الجديد | يُرسل للمزامنة؟ | يُقرأ من المزامنة؟ |
|---|---|---|---|
| `employee_uuid` | **مصدر الحقيقة الوحيد** لربط أي سجل مالي بالموظف | نعم | نعم |
| `expense_uuid` (جديد) | مصدر الحقيقة لربط المسحوب بالمصروف | نعم | نعم |
| `employee_id` | **cache محلي** مشتق من `employee_uuid` لتسريع الـ JOIN وللـ FK المحلي | لا | لا |
| `related_id` (expenses) | **cache محلي** مشتق من `employee_uuid` للمصروفات المرتبطة بموظف. يبقى لمعناه القديم فقط في غير ذلك (مثل الحجز) | لا | لا |
| `expense_id` / `reason='exp_N'` | قديم: قراءة فقط للسجلات قبل Migration 68 | لا | لا |

- **دالة واحدة فقط تكتب الأعمدة المشتقة:** `LocalLinkResolver.relink({tables, uuids})`. تُستدعى بعد كل سحب، وبعد الاستعادة، وبعد إنشاء موظف. أي كود آخر يكتب `employee_id` أو `related_id` من مصدر غير الـ UUID = خطأ في المراجعة.
- **قيد محلي (Migration 68):** trigger يمنع إدراج أو تعديل سجل مالي من عائلة الرواتب بـ `employee_uuid` فارغ. وtrigger يُبقي `employee_id` متسقاً مع `employee_uuid` عند تغيّر أي منهما.

### 6.2 مساعد استعلام موحد (للفترة الانتقالية)

حتى يكتمل الـ backfill، كل استعلام "سجلات الموظف X" يمر عبر مساعد واحد بدل تكرار الشروط:

```dart
/// lib/services/queries/employee_scope.dart (مقترح)
Expression<bool> salaryWithdrawalOf(Employee e, $SalaryWithdrawalsTable t) =>
    t.employeeUuid.equals(e.localUuid) |
    (t.employeeUuid.isNull() & t.employeeId.equals(e.id));

Expression<bool> expenseOf(Employee e, $ExpensesTable t) =>
    t.employeeUuid.equals(e.localUuid) |
    (t.employeeUuid.isNull() & t.relatedId.equals(e.id));
```
- بعد اكتمال الـ backfill (تقرير "بلا UUID" = 0) يُحذف الشق الثاني ويصبح الشرط `employee_uuid = ?` فقط.
- `EmployeesDao.countFinancialRecords` (`employees_dao.dart` ~264-281) يطبق هذا النمط تقريباً. يُعمَّم منه.

### 6.3 مصدر واحد لحركات الرواتب (إنهاء المطابقة الاستدلالية)

اليوم كل تقرير يجمع `expenses` و`salary_withdrawals` ثم يحاول إزالة التكرار بـ `SalaryMirrorMatcher` (4 مستويات، آخرها يتجاهل المبلغ). البديل: **view محلي واحد** (ونسخة مطابقة في D1):

```sql
CREATE VIEW v_salary_movements AS
SELECT sw.local_uuid AS uuid,
       sw.employee_uuid,
       sw.amount,
       COALESCE(sw.hotel_day_key, x.hotel_day_key) AS hotel_day_key,
       COALESCE(x.expense_kind, 'direct_withdrawal') AS kind,
       sw.expense_uuid,
       CASE WHEN sw.expense_uuid IS NULL THEN 0 ELSE 1 END AS via_expense
  FROM salary_withdrawals sw
  LEFT JOIN expenses x ON x.local_uuid = sw.expense_uuid AND x.deleted_at IS NULL
 WHERE sw.deleted_at IS NULL;
```

| السؤال | المصدر الوحيد |
|---|---|
| كم صُرف للموظف من راتبه؟ (الاستحقاق، تقرير المسحوبات) | `v_salary_movements` فقط |
| كم خرج من الصندوق نقداً؟ (تقرير المصروفات، الدخل والخرج) | `expenses` فقط (المسحوبات المباشرة تظهر بـ `cash_transactions` أو كبند منفصل صريح) |
| لا يجوز | جمع `expenses` + `salary_withdrawals` معاً ثم إزالة التكرار بالمطابقة |

- **مصروف راتب بلا مسحوب** (أو العكس) لا يُخفى ولا يُخمَّن. يظهر في فحص السلامة كتنبيه.
- `SalaryMirrorMatcher` ومستويات المطابقة بالمبلغ واليوم تُستبدل بهذا الـ view. يبقى منها فقط سكربت ترحيل لمرة واحدة يملأ `expense_uuid` للسجلات القديمة، مع سجل تدقيق.

### 6.4 تصنيف صريح بدل `contains()`

- عمود جديد `expenses.expense_kind` بقيم ثابتة: `salary_withdrawal` | `salary_deduction` | `advance` | `advance_installment` | `payroll` | `general`.
- يُحدَّد عند الإنشاء من اختيار المستخدم، لا من النص. `expense_type` يبقى للعرض فقط.
- Migration 68 يملؤه مرة واحدة من `SalaryExpenseClassifier` الحالي ومن `description LIKE 'قسط سلفة%'`، ويُراجَع يدوياً.
- يحل R16، ويحل غياب `'سلفة'` من `isSalaryExpenseType` (R8).

### 6.5 خريطة التعديلات على الاستعلامات الحالية

| الملف | الموقع (تقريبي) | الحالي | الجديد |
|---|---|---|---|
| `salary_entitlement_service.dart` | ~106، ~527 | `expenses.relatedId == employee.id` | `v_salary_movements.employee_uuid = ?` (أو `expenseOf` في الفترة الانتقالية) |
| `salary_entitlement_service.dart` | ~491، ~667، ~729، ~746 | `employeeId.equals(employeeId)` | توقيع الدالة يأخذ `Employee` أو `employeeUuid`، والفلتر بـ `salaryWithdrawalOf` |
| `salary_entitlement_service.dart` | ~129، ~547 | `description.contains('قسط سلفة')` | `expense_kind = 'advance_installment'` |
| `expenses_report_screen.dart` | ~280-487 | خرائط `relatedId` و`employeeId` + مطابقة 3 طرق | `expenses` للصندوق، و`v_salary_movements` لقسم الرواتب. الخريطة `employeeMap` بمفتاح `localUuid` |
| `expenses_report_screen.dart` | ~1045 | يعرض `'موظف #relatedId'` عند الفشل | يعرض "موظف غير معروف (uuid…)" + رابط لفحص السلامة |
| `salary_withdrawals_report_screen.dart` | ~115، ~310، ~374 | مفتاح التجميع `sw.employeeId` | `sw.employeeUuid` |
| `income_expense_report_screen.dart` | ~391-400 | دمج مسحوبات ومصروفات بالمطابقة | `expenses` فقط للخرج النقدي (6.3) |
| `optimized_queries.dart` | ~184-198 | `salary_cycles.employee_id = e.id` | `sc.employee_uuid = e.local_uuid` |
| `gemini_service.dart` | ~1226، ~1246، ~3047-3052 | تجميع بـ `employeeId` | تجميع بـ `employeeUuid` |
| `hotel_day_key_fix_service.dart` | ~291، ~323 | مفتاح `relatedId_day` / `employeeId_day` | `employeeUuid_day`، أو يُلغى بعد `expense_uuid` |
| `salary_fix_helper.dart` / `database_fixer.dart` | كامل | إصلاح `related_id` من المسحوب بالاستدلال | يُستبدل بـ `LocalLinkResolver.relink` (اشتقاق من UUID فقط) + تقرير. لا تصفير ولا تخمين |
| `employee_link_consistency_service.dart` | ~150-197 | إنقاذ بـ `expenseId` قد يكون أجنبياً | يُستبدل بـ `relink` |
| `salary_advance_installments_service.dart` | ~18-105 | يأخذ `int employeeId` | يأخذ `employeeUuid`، ويكتب `employee_uuid` + `expense_kind` |
| `expenses_list.dart` | ~206، ~960-981، ~1202-1277 | اختيار الموظف بـ `id` وإزالة التكرار بالاسم | الاختيار بـ `localUuid`، والكتابة عبر `SalaryExpenseService` (المرحلة 2) |
| `settings_employees.dart` | ~1467-1480 | `expenseId: 0` و`reason: 'direct_withdrawal_<uuid>'` | `expense_uuid = NULL` + `employee_uuid` |
| `payload_mapper.dart` / adapters | — | ترسل وتستقبل `employeeId` و`relatedId` و`expenseId` | لا تُرسل ولا تُقرأ. الـ UUID فقط (5.4 و5.5) |

### 6.6 الفهارس المحلية المطلوبة للاستعلامات الجديدة

تُنشأ في `beforeOpen` بـ `IF NOT EXISTS` (لأن `List<Index> get indexes` لا يُطبَّق، R15):

```sql
CREATE INDEX IF NOT EXISTS idx_exp_employee_uuid ON expenses(employee_uuid) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_exp_kind_day      ON expenses(expense_kind, hotel_day_key);
CREATE INDEX IF NOT EXISTS idx_sw_employee_uuid  ON salary_withdrawals(employee_uuid) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_sw_expense_uuid   ON salary_withdrawals(expense_uuid);
CREATE INDEX IF NOT EXISTS idx_sc_employee_uuid  ON salary_cycles(employee_uuid);
CREATE INDEX IF NOT EXISTS idx_emp_local_uuid    ON employees(local_uuid); -- موجود ضمنياً عبر UNIQUE
```
- يُقاس أثرها بـ `EXPLAIN QUERY PLAN` على جهاز ضعيف قبل وبعد (`docs/PERFORMANCE.md` §3 "قياس لا تخمين").

---

## 7. ترتيب التنفيذ المقترح

1. **المرحلة 0** (PR صغير لكل بند، مع اختبار): يوقف الفقدان الحالي في Appwrite فوراً، لأنه ما زال يعمل حتى اكتمال الانتقال.
2. **Migration 68 محلياً:** `expense_uuid` + `expense_kind` + الفهارس + الـ triggers (المرحلة 1، و6.4، و6.6) + backfill وتقرير "بلا UUID".
3. **`SalaryExpenseService` الذري** (المرحلة 2) + **`LocalLinkResolver.relink`** (6.1).
4. **تحويل التقارير والاستعلامات** إلى `employee_uuid` و`v_salary_movements` (6.2، و6.3، و6.5). يمكن تنفيذه بالتوازي مع الخطوة 5 لأنه لا يعتمد على مصدر المزامنة.
5. **Worker + قاعدة `hotel_sync` في D1** (5.2، و5.3) + push وpull (5.4، و5.5) + `pending_links` (المرحلة 4).
6. **الانتقال** (5.6) مع المقارنة، ثم إيقاف Appwrite كتابةً.
7. **المرحلة 6** (فحص السلامة) + `v_orphans` في D1، بالتوازي مع ما سبق.

> **قبل الخطوة 1:** لقطة Appwrite (10.3-هـ)، وتعطيل مسارات الدفع الكامل (10.3-و). **في كل خطوة:** القواعد 10.3-أ إلى 10.3-ج.

## 8. الاختبارات المطلوبة (توسيع الموجود في `test/services/`)

- جهازان: مصروف راتب id=5 على A، ومصروف غير مرتبط id=5 على B → حذف مصروف B لا يمس مرآة A (R3).
- سحب مسحوب قبل موظفه → يُحفظ في `pending_links` ثم يُربط في الدورة التالية، لا يُحذف (R1, R5).
- فشل إدراج المرآة → لا يُحفظ المصروف (R4).
- استعادة Drive كاملة → كل `expense_id`/`related_id` يطابق الـ UUID (R10).
- تغيير موظف المصروف → المرآة تحمل `employeeUuid` الجديد (R12).
- جهاز جديد: موظف بـ id=3 محلياً ≠ الموظف ذو id=3 في جهاز المصدر → لا ربط خاطئ (R2).
- Drive delta يطبق تغييرات `salary_withdrawals` (R7).

**اختبارات مزامنة D1** (مقابل Worker محلي عبر `wrangler dev`، أو `MockClient`):
- جهازان لكل منهما `employees.id = 3` لشخصين مختلفين → في D1 سجلان منفصلان، ولا كتابة فوق (D1-1).
- رفع نسخة قديمة (version أقل) بعد نسخة أحدث → D1 يحتفظ بالأحدث ويرجع `stale` (D1-2).
- رفع مسحوب قبل موظفه → يُقبل في D1 ويظهر في `v_orphans`. يُسحب على جهاز آخر إلى `pending_links` ثم يُربط تلقائياً عند وصول الموظف.
- انقطاع الشبكة في منتصف دفعة → لا يتقدم المؤشر، ولا يُعلَّم أي عنصر outbox "تم" بلا تأكيد.
- حذف على جهاز A ثم تعديل قديم من B → يبقى محذوفاً. استعادة مقصودة بـ version أعلى → تنجح.
- قاعدة محلية فارغة + سحب كامل من `server_seq = 0` → مجموع رواتب كل موظف يطابق الجهاز المصدر (`v_salary_movements`).
- مصروف راتب بلا `employee_uuid` → يُرفض محلياً (trigger) وفي الـ Worker (`rejected`).

**اختبارات التقارير:**
- نفس البيانات بأرقام `id` مختلفة على جهازين → تقرير المسحوبات والاستحقاق متطابقان حرفياً.
- مصروف راتب + مسحوبه → يُحسب مرة واحدة في الاستحقاق، ومرة واحدة في خرج الصندوق.

## 9. أسئلة مفتوحة

1. هل نعتمد جدول عزل (`orphan_quarantine`) أم نكتفي بترك اليتيم مع تحذير في المرحلة 0؟
2. هل توجد بيانات إنتاجية في السحابة تحتاج سكربت backfill لـ `expenseUuid` (على غرار سكربت `employeeUuid` في `b5e3a2c4`)؟
3. هل نُبقي `reason='exp_N'` للتوافق مع إصدارات قديمة من التطبيق ما زالت مثبتة على أجهزة أخرى؟ (المقترح: نعم، قراءة فقط، لفترة انتقالية).
4. **Worker أم REST مباشر؟** المقترح: Worker (أمان التوكن + معاملات `batch` + params). هل لديكم صلاحية نشر Workers على نفس الحساب؟
5. **هل تبقى قاعدة النسخ الاحتياطي الحالية في D1** (المفتاح `id`) بعد الانتقال، أم تُوقف لأن قاعدة المزامنة نفسها تصبح النسخة السحابية؟
6. **Google Drive:** هل يبقى نسخة احتياطية دورية (لقطة كاملة) فقط، أم يُلغى؟ المقترح: يبقى كلقطة، دون مزامنة delta، لتقليل عدد مسارات الكتابة.
7. **التقارير على الخادم:** هل تريدون لاحقاً تقارير تُستعلم مباشرة من D1 (لوحة ويب)؟ إن نعم، فـ `v_salary_movements` في D1 يصبح واجهة رسمية يجب تثبيتها.

## 10. حماية سجلات Appwrite Cloud أثناء التنفيذ

> **السؤال:** هل تُفسد هذه الخطة السجلات الموجودة على Appwrite Cloud؟
> **الجواب المختصر:** لا، إن طُبّقت القواعد أدناه. معظم البنود محلية أو للقراءة فقط. لكن هناك **4 نقاط** قد تُفسد السحابة إن نُفّذت بلا انتباه.

### 10.1 حقائق من الكود تحدد الخطر

| الحقيقة | الموقع | الأثر |
|---|---|---|
| الرفع = `updateDocument` جزئي (ثم `createDocument` إن لم يوجد) **بلا فحص version** | `appwrite_service.dart` ~595-700 (`_upsertDocumentOnce`) | آخر جهاز يرفع يفوز. أي سجل محلي يدخل الـ outbox يكتب فوق السحابة حتى لو كانت قيمته خاطئة |
| الحقول الفارغة لا تُرسل (`putIfNotNull` / `putIfStringNotEmpty`) | `payload_mapper.dart` ~181-197 | تصفير `relatedId` محلياً **لا يمسح** قيمته في السحابة |
| الحقول غير المعرّفة في مخطط Appwrite تُزال قبل الإرسال | `appwrite_sync_utils.dart` ~36، ~1886 (`filterPayloadForCollection`) | إضافة `expenseUuid` / `expenseKind` لا تسبب أخطاء رفع. لكنها لا تُخزَّن في Appwrite ما لم يُضف لها attribute |

### 10.2 تصنيف بنود الخطة حسب أثرها على السحابة

| البند | أثره على Appwrite |
|---|---|
| P0.1 (إيقاف الحذف النهائي لليتيم) | لا شيء: محلي فقط |
| P0.2 (حذف "الطريقة 2") | **يقلل** الإفساد: يمنع ربطاً خاطئاً قد يُرفع لاحقاً |
| P0.3 (فلتر الموظف في `deleteByExpenseId`) | **يقلل** الإفساد: يمنع soft-delete خاطئاً ينتشر للسحابة |
| P0.4 (`relatedId = null` عند فشل الحل) | آمن: الـ null لا يُرسل، فتبقى قيمة السحابة كما هي |
| P0.5 (إبقاء المسحوب في الطابور) | آمن: يُرفع لاحقاً بعد وصول موظفه |
| P0.6 (Drive delta) | لا شيء |
| القسم 6 (التقارير، والـ views، والفهارس، و`v_salary_movements`) | لا شيء: قراءة محلية |
| المرحلة 6 / `v_orphans` | لا شيء: قراءة فقط |
| 5.6 (الانتقال إلى D1) | لا شيء إن بقي Appwrite **للقراءة فقط** |
| ⚠️ Migration 68 + backfill + `relink` + `expense_kind` | **خطر** (10.3-أ) |
| ⚠️ إيقاف إرسال `employeeId` / `relatedId` | **خطر على الأجهزة القديمة** (10.3-ب) |
| ⚠️ إيقاف كتابة `reason='exp_N'` / `expenseId` | **خطر عرض** على الأجهزة القديمة (10.3-ج) |
| ⚠️ أجهزة لم تُحدَّث بعد إيقاف Appwrite | **تباعد** (10.3-د) |

### 10.3 القواعد الإلزامية

**أ) كل إصلاح أو backfill محلي = بلا outbox، وبلا رفع version، وبلا تغيير lastModified.**
- السبب: بعض الأجهزة تحمل اليوم ربطاً خاطئاً بسبب R2. لو أدخل الـ backfill كل الصفوف للـ outbox، فسيكتب `updateDocument` (بلا فحص version) هذا الربط الخاطئ فوق السحابة **لكل السجلات دفعة واحدة**.
- يشمل: Migration 68، وملء `expense_uuid` و`expense_kind`، و`LocalLinkResolver.relink`، وبديل `EmployeeLinkConsistencyService` (الحالي **يرفع** إصلاحاته، `employee_link_consistency_service.dart` ~150-190، ويجب إيقاف ذلك).
- الاستثناء الوحيد: إصلاح سحابي مقصود عبر سكربت منفصل، بعد مراجعة تقرير الفروق يدوياً (القاعدة هـ).

**ب) طوال فترة الانتقال، يستمر إرسال `employeeId` و`relatedId` و`employeeUuid` إلى Appwrite.**
- قاعدة "لا تُرسل الأرقام المحلية" في 6.1 تخص **D1 فقط**.
- السبب: الأجهزة غير المحدّثة تحل الموظف بـ `employeeId` / serverId. وثيقة جديدة بلا `employeeId` ستُتخطى عندها، والإصدارات القديمة فيها R1 (حذف اليتيم نهائياً) محلياً.
- `updateDocument` جزئي: حتى لو توقف الإرسال، لن تُمسح القيم الموجودة في الوثائق القديمة. الخطر فقط على الوثائق **الجديدة**.

**ج) طوال فترة الانتقال، تستمر كتابة `expense_id` و`reason='exp_N'` للمرايا الجديدة** إلى جانب `expense_uuid`.
- السبب: الأجهزة القديمة تعتمد عليها في إزالة التكرار. بدونها تُظهر تقاريرها المبلغ مرتين.
- هذا خطأ عرض لا إفساد بيانات، لكنه يربك المحاسبة.

**د) إيقاف Appwrite كتابةً يتم بإجبار التحديث، لا بمفتاح فقط.**
- `minimum_app_version` في Remote Config: الإصدار القديم يمنع المزامنة حتى يُحدَّث.
- مفتاح `appwrite_write_enabled = false` يمنع الرفع في الإصدار الجديد.
- بدون ذلك، جهاز قديم يواصل الكتابة في Appwrite ولا تصل تعديلاته إلى D1. لا تفسد السحابة، لكن البيانات تتباعد.

**هـ) قبل أي خطوة، لقطة كاملة من السحابة (قراءة فقط).**
- سكربت في `scripts/appwrite/` يصدّر `employees` و`expenses` و`salary_withdrawals` و`salary_cycles` و`salary_payments` و`salary_carry_over_logs` إلى JSON، مع `$id` و`$updatedAt`.
- تُحفظ اللقطة خارج Appwrite (Drive / D1 backup). هي المرجع للمقارنة في 5.6 وللتراجع إن حدث خطأ.

**و) لا تشغيل لمسارات "الدفع الكامل" أثناء التنفيذ.**
- `pushAllLocalDataToAppwrite` بعد استعادة Drive، و"استعادة Appwrite الشاملة" (`comprehensive_appwrite_backup_service.dart` ~305-330)، كلاهما يكتب فوق السحابة بلا فحص version (R9).
- تُعطَّل من الواجهة إلى أن يُطبَّق فحص "الأحدث يفوز"، أو إلى نهاية الانتقال.

### 10.4 ما لا تُصلحه الخطة في Appwrite (موجود مسبقاً)

- **السجلات المفسدة سابقاً تبقى كما هي:** 430 من 639 مسحوباً بلا `employeeUuid` (`b5e3a2c4`)، وربط خاطئ محتمل من R2. الخطة لا تمسها تلقائياً.
- **الطريق الآمن لها:** عند البذر إلى D1 (5.6) تُقارن بالـ UUID مع اللقطة (10.3-هـ) ومع بيانات الجهاز المنشئ. الفروق تُراجع يدوياً قبل أن تصبح D1 مصدر الحقيقة.
- **غياب فحص version في `updateDocument`** يبقى خطراً قائماً في Appwrite حتى إيقافه. القواعد (أ) و(و) تقلل التعرض له ولا تلغيه.

## 11. نتائج الفحص الفعلي لبيانات Appwrite Cloud (2026-10-02)

> **الطريقة:** تصدير للقراءة فقط (GET فقط) عبر `scripts/appwrite/readonly_export_salary_links.py`. اللقطة محفوظة خارج المستودع (`/tmp/appwrite_snapshot`)، ولم يُكتب أي شيء في السحابة.
> المعرّفات أدناه مختصرة (أول 8 أحرف من الـ UUID)، ولا تُذكر أسماء.

### 11.1 الأحجام

| المجموعة | الكل | نشط | محذوف (soft) |
|---|---|---|---|
| `employees` | 16 | 8 | 8 |
| `expenses` | 1539 | 1517 | 22 |
| `salary_withdrawals` | 733 | 715 | 18 |
| `salary_cycles` / `salary_payments` / `salary_carry_over_logs` | 0 | 0 | 0 |

- مصروفات من عائلة الرواتب (نشطة): **743** (`سحب راتب` 730، `سحب من الراتب` 9، `خصم من الراتب` 3، `رواتب` 1).

### 11.2 ما هو سليم

- **كل مصروفات الرواتب النشطة تحمل `employeeUuid`** يشير لموظف موجود (575 لموظف نشط، و168 لموظف منتهٍ/محذوف soft).
- **714 من 715 مسحوباً نشطاً تحمل `employeeUuid`** يشير لموظف موجود. مسحوب واحد فقط بلا UUID (`employeeId=3`، مبلغ 10,000، `exp_668`)، ولا يوجد موظف `serverId=3` لحله.
- السجلات التي تشير لموظف محذوف (292 مسحوباً) ليست خطأً بحد ذاتها: هي رواتب تاريخية لموظفين أنهيت خدمتهم.

### 11.3 ⚠️ ما هو مُفسد فعلاً

**أ) `employees.serverId` متصادم (يؤكد R14):**
- `serverId=1` لموظفَين (`0ba49b07` محذوف، و`40035809` نشط).
- `serverId=10` لموظفَين نشطَين (`63858f13`، و`91066357`).
- 3 موظفين بلا `serverId`.

**ب) المسحوب والمصروف المقابل له منسوبان لموظفين مختلفين:**

| الفحص | النتيجة |
|---|---|
| خانات (يوم فندقي + مبلغ) فيها مصروف راتب واحد ومسحوب واحد فقط (مطابقة لا لبس فيها) | 343 خانة |
| — نفس الموظف | 199 |
| — **موظف مختلف** | **144 خانة، بمجموع 957,200** |
| مطابقة أوسع (نفس المبلغ ونفس اليوم بعد استبعاد المطابق بنفس الموظف) | ~298 زوجاً، بمجموع ~1,251,200 |

**ج) السبب الأرجح: سكربت backfill السحابي (`scripts/appwrite/backfill_salary_withdrawals_employee_uuid.js`، commit `25778da3`):**
- يملأ `employeeUuid` للمسحوب بالبحث عن موظف `serverId == employeeId`.
- لكن `employeeId` في المسحوب = **id محلي في جهاز المصدر**، و`serverId` غير موثوق ومتصادم (أ). القاعدة إذن غير صحيحة.
- **الدليل:**
  - 424 مسحوباً نشطاً آخر تعديل لها يوم **2026-09-19**، و**373** منها تتبع حرفياً قاعدة "`employeeUuid` = الموظف ذو `serverId == employeeId`".
  - في 133 من الـ 144 خانة المتعارضة، المسحوب منسوب للموظف الذي `serverId` = `employeeId` المسحوب.
  - الأزواج المتعارضة تتركز في موظفين منتهين: `9b2b001c` (serverId=8)، `29afb23b` (serverId=12)، وغيرهما.
- لا نستطيع الجزم بأن السكربت نفسه هو من شُغِّل بـ `--apply` (قد يكون منطق مماثل في التطبيق، كالطريقة 2 أو حل serverId في `IdResolver`). لكن النتيجة واحدة: **ربط بالأرقام المحلية كُتب في السحابة**.

**د) جانب المصروفات أيضاً لُمس جماعياً:**
- 327 مصروف راتب آخر تعديل لها 2026-09-22، و359 في 2026-10-01.
- في الخانات المتعارضة، موظف جانب المسحوب كان على رأس عمله في تاريخ السجل في 109 من 144 حالة، وموظف جانب المصروف في 79 من 144 فقط.
- لذلك **لا يمكن افتراض أن جانب المصروف هو الصحيح دائماً**، ولا العكس. (قد تكون تواريخ التعيين نفسها غير دقيقة).
- `expense.relatedId == sw.employeeId` في 2 فقط من 298 زوجاً، رغم أن المصروف ومرآته يُنشآن على نفس الجهاز. هذا يعني أن أحد الطرفين أُعيدت كتابته لاحقاً في معظم الحالات.

**هـ) تصادمات `expenseId` (تؤكد R3):**
- 6 قيم `expenseId` (510، 706، 848، 855، 1156، 1246) يشير كل منها لمسحوبين نشطين لموظفين مختلفين.
- على أي جهاز توجد فيه مصروفات بهذه الأرقام المحلية، `deleteByExpenseId` أو `saveFromExpense` قد يمس المسحوب الخطأ.

**و) تكرار محتمل:**
- 32 مجموعة (موظف + يوم + مبلغ) فيها أكثر من مسحوب نشط، أي 36 صفاً زائداً بمجموع 127,000.
- معظمها بـ `expenseId` مختلفة، فقد يكون بعضها سحوبات حقيقية متعددة في نفس اليوم. **يحتاج مراجعة يدوية**، لا حذفاً آلياً.

**ز) أخرى:**
- 628 من 715 مسحوباً بلا `deviceId`، و187 مصروفاً بلا `deviceId`. لا يمكن معرفة الجهاز المنشئ من السحابة وحدها.
- مجموعة `audit_logs` فارغة (0 سجل)، فلا يوجد سجل تاريخي في السحابة لاستعادة القيم الأصلية.

### 11.4 ما يعنيه هذا للخطة

1. **منع أي backfill أو إصلاح يعتمد على `serverId` أو `employeeId` أو `relatedId`**، محلياً أو سحابياً. يُضاف لقواعد 10.3: **السكربت `backfill_salary_withdrawals_employee_uuid.js` لا يُشغَّل مرة أخرى**، ويُعلَّم كخطر أو يُحذف.
2. **لا نُصلح السحابة آلياً الآن.** السحابة وحدها لا تكفي لمعرفة الصواب: لا `deviceId`، ولا audit، والطرفان كلاهما معدَّل.
3. **مصادر الحقيقة المحتملة للاستعادة**، بالترتيب:
   1. **نسخ احتياطية سابقة لـ 2026-09-12**: Google Drive، أو JSON محلي، أو **نسخة Cloudflare D1** إن رُفعت قبل ذلك (مسبارات D1 مؤرخة 2026-09-04/05). أي نسخة من الجهاز المنشئ تحتوي `expenses.related_id` + `employees.id ↔ local_uuid` لنفس الجهاز، فتعطي الربط الصحيح.
   2. **قاعدة الجهاز المنشئ الحالية:** المصروف ومرآته على نفس الجهاز بنفس `related_id` / `employee_id` المحليين قبل أي سحب.
   3. **مراجعة يدوية** من الإدارة للخانات المتعارضة (144 خانة واضحة، وقائمة مولّدة من اللقطة).
4. **عند البذر إلى D1 (5.6):** يُرفع ربط الموظف بعد تصحيحه من مصدر حقيقة (البند 3) فقط. قائمة الخانات المتعارضة تُرفق كتقرير مراجعة، ولا تُنقل كما هي على أنها صحيحة.
5. **التقارير الحالية على الأجهزة** تعرض اليوم أرقاماً مبنية على هذا الربط المفسد. الاستحقاق والمسحوبات لكل موظف قد تكون خاطئة لـ ~1.25 مليون من المبالغ. يجب إبلاغ الإدارة بذلك قبل الاعتماد على تقارير الرواتب.

---

## ملحق: مراجع

- `scripts/SALARY_WITHDRAWALS_SYNC_REPORT.md`، `scripts/EXPENSES_SYNC_REPORT.md`
- `docs/REFACTORING_ANALYSIS_2026-07-12.md` (§ الفهارس)
- `docs/FOREIGN_KEY_SYNC_FIX.md` (يغطي payments/debts فقط)
- Commits: `1c83e916` (إصلاح FK للرواتب)، `07c26a65` (الدمج الذي ألغاه)، `146e2f67` (Migration 67)، `b5e3a2c4`، `2f3e5aa6`
- D1 الحالي: `lib/services/cloudflare_d1_service.dart`، `lib/screens/settings/backup/tabs/cloudflare_d1_tab.dart`، `docs/CLOUDFLARE_D1_UPLOAD_FIELDS_AUDIT.md`، `test/unit/cloudflare_d1_upload_fields_test.dart`
- اختبارات قائمة: `salary_mirror_cross_device_test.dart`، `salary_mirror_edit_duplication_test.dart`، `employee_link_consistency_test.dart`، `salary_withdrawal_attribution_test.dart`
