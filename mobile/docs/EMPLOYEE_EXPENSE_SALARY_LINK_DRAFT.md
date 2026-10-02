# مسودة: تحصين الربط بين الموظفين والمصروفات ومسحوبات الرواتب

> **الحالة:** مسودة للنقاش — لم يُنفَّذ أي تغيير في الكود بعد.
> **الفرع:** `refactor/performance-fixes-v2`
> **التاريخ:** 2026-10-02
> **الهدف:** ألا تُفقد أي بيانات رواتب أو مصروفات مستقبلاً، وألا تُنسب لموظف خاطئ، عبر كل المسارات: الإدخال، التعديل، الحذف، المزامنة (Appwrite)، النسخ الاحتياطي والاستعادة (محلي / Google Drive / Cloudflare D1).

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
| Cloudflare D1 | المفتاح الأساسي = `local_uuid` بدل `id` (R17) |

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

## 5. ترتيب التنفيذ المقترح

1. **المرحلة 0** (PR صغير لكل بند، مع اختبار) — يوقف الفقدان الحالي فوراً.
2. **المرحلة 1 + 2** معاً (Migration 68 + الخدمة الذرية).
3. **المرحلة 4** (pending_links).
4. **المرحلة 3 + 5**.
5. **المرحلة 6** بالتوازي مع ما سبق.

## 6. الاختبارات المطلوبة (توسيع الموجود في `test/services/`)

- جهازان: مصروف راتب id=5 على A، ومصروف غير مرتبط id=5 على B → حذف مصروف B لا يمس مرآة A (R3).
- سحب مسحوب قبل موظفه → يُحفظ في `pending_links` ثم يُربط في الدورة التالية، لا يُحذف (R1, R5).
- فشل إدراج المرآة → لا يُحفظ المصروف (R4).
- استعادة Drive كاملة → كل `expense_id`/`related_id` يطابق الـ UUID (R10).
- تغيير موظف المصروف → المرآة تحمل `employeeUuid` الجديد (R12).
- جهاز جديد: موظف بـ id=3 محلياً ≠ الموظف ذو id=3 في جهاز المصدر → لا ربط خاطئ (R2).
- Drive delta يطبق تغييرات `salary_withdrawals` (R7).

## 7. أسئلة مفتوحة

1. هل نعتمد جدول عزل (`orphan_quarantine`) أم نكتفي بترك اليتيم مع تحذير في المرحلة 0؟
2. هل توجد بيانات إنتاجية في السحابة تحتاج سكربت backfill لـ `expenseUuid` (على غرار سكربت `employeeUuid` في `b5e3a2c4`)؟
3. هل نُبقي `reason='exp_N'` للتوافق مع إصدارات قديمة من التطبيق ما زالت مثبتة على أجهزة أخرى؟ (المقترح: نعم، قراءة فقط، لفترة انتقالية).
4. هل Cloudflare D1 مستخدم كنسخة احتياطية حقيقية أم للتقارير فقط؟ (يحدد أولوية R17).

---

## ملحق: مراجع

- `scripts/SALARY_WITHDRAWALS_SYNC_REPORT.md`، `scripts/EXPENSES_SYNC_REPORT.md`
- `docs/REFACTORING_ANALYSIS_2026-07-12.md` (§ الفهارس)
- `docs/FOREIGN_KEY_SYNC_FIX.md` (يغطي payments/debts فقط)
- Commits: `1c83e916` (إصلاح FK للرواتب)، `07c26a65` (الدمج الذي ألغاه)، `146e2f67` (Migration 67)، `b5e3a2c4`، `2f3e5aa6`
- اختبارات قائمة: `salary_mirror_cross_device_test.dart`، `salary_mirror_edit_duplication_test.dart`، `employee_link_consistency_test.dart`، `salary_withdrawal_attribution_test.dart`
