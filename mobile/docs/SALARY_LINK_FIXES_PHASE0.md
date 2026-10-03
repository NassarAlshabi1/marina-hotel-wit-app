# مسودة: ما تم إصلاحه — المرحلة 0 لحماية ربط الموظفين والمصروفات والرواتب

> **الحالة:** منفّذ ومختبر محلياً على الفرع `refactor/performance-fixes-v2`. لم يُنشر بعد في إصدار للتطبيق.
> **التاريخ:** 2026-10-03
> **المرجع:** `docs/EMPLOYEE_EXPENSE_SALARY_LINK_DRAFT.md` (أرقام المخاطر R1…R18 والقسم 11 من هناك)
> **مهم:** كل التعديلات في **كود التطبيق** فقط. **لم يُكتب أي شيء في Appwrite Cloud**، والسجلات المُفسدة سابقاً في السحابة ما زالت كما هي (انظر §4).

---

## 1. الهدف

إيقاف أي فقدان أو ربط خاطئ **جديد** لبيانات الرواتب، مع بقاء المزامنة الحالية (Appwrite) تعمل. لا ترحيل لقاعدة البيانات (schema) في هذه المرحلة.

## 2. الإصلاحات

### 2.1 R1 — إيقاف الحذف النهائي لسجلات الرواتب اليتيمة بعد المزامنة
- **الملف:** `lib/services/appwrite_sync_manager.dart` → `_performPostSyncIntegrityCheck`
- **قبل:** كل سجل في `salary_withdrawals` / `salary_cycles` / `salary_payments` يفشل في `PRAGMA foreign_key_check` كان يُحذف بـ `DELETE` (بلا tombstone ولا outbox). أي سجل لم يُرفع بعد يضيع نهائياً.
- **بعد:** السجل يبقى ويُسجَّل تحذير `🛡️ سجل رواتب يتيم ... أُبقي دون حذف`. أُضيف `salary_carry_over_logs` لنفس الحماية.
- **لم يتغير:** معالجة `payments` / `debts` / `booking_nights` (تصفير الربط أو soft delete) كما كانت.
- **Commit:** `bb545a95`

### 2.2 R2 / R14 — إزالة "الطريقة 2" ومنع تخمين الموظف
- **الملفات:** `lib/services/appwrite_sync_manager.dart` (`_syncSalaryWithdrawals`، `_syncSalaryCycles`)، و`lib/services/adapters/id_resolver.dart`
- **قبل:**
  - "الطريقة 2" تطابق `employeeId` القادم من جهاز آخر مع `employees.id` المحلي، فتنسب الراتب لموظف خاطئ على الأجهزة الجديدة. الدمج `07c26a65` أعادها بعد أن أزالها الإصلاح `1c83e916`.
  - بعد الحل كان يُستبدل `data['employeeId']` بالـ id المحلي، فيطابق الـ adapter لاحقاً `serverId == id محلي`، وهو ربط خاطئ ثانٍ محتمل.
  - `IdResolver`: إذا تكرر `serverId` يختار "النشط ثم الأصغر"، وإذا لم يوجد الـ UUID يسقط إلى `serverId`.
- **بعد:**
  - حل الموظف في الـ manager يمر عبر `IdResolver.resolveEmployee(uuid, serverId, fromRemote: true)` فقط، ولم يعد `data['employeeId']` يُستبدل.
  - `IdResolver` للمصدر البعيد:
    - `serverId` مكرر → `null` (يبقى يتيماً بلا تخمين).
    - UUID مُمرَّر وغير موجود محلياً → `null` (لا سقوط إلى `serverId`).
  - المصدر المحلي يحتفظ بالسلوك القديم (النشط ثم الأصغر).
  - نفس قاعدة "لا تخمين عند التكرار" طُبّقت على `resolveSalaryCycle`.
- **السبب العملي:** فحص Appwrite الفعلي (§11 في المسودة) أظهر موظفَين بـ `serverId=1` وموظفَين بـ `serverId=10`، وأظهر أن قاعدة "النشط أولاً" تنسب رواتب لموظف خاطئ.
- **Commit:** `8badc46e`

### 2.3 R3 / R12 — حارس تصادم رقم المصروف بين الأجهزة
- **الملفات:** `lib/services/repositories/salary_withdrawals_repository.dart`، و`lib/screens/expenses/expenses_list.dart`
- **قبل:**
  - `saveFromExpense` و`deleteByExpenseId` يبحثان عن المسحوب بـ `expense_id` أو `reason='exp_N'` فقط.
  - المسحوبات القادمة من جهاز آخر تحمل رقم مصروف **ذلك** الجهاز. عند التصادم كان المسحوب الخطأ يُعدَّل (موظفه ومبلغه) أو يُحذف، وينتشر ذلك للسحابة. السحابة فيها فعلاً 6 أرقام `expenseId` مشتركة بين موظفين مختلفين.
  - تغيير موظف المصروف كان يُبقي `employee_uuid` القديم في المسحوب (R12).
- **بعد:**
  - `saveFromExpense(..., previousEmployeeId)`: المطابقة بالرقم (الطريقتان 1 و2) وجمع السجلات القديمة (stale) لا تقبل إلا مسحوباً:
    - `employeeId` فيه = الموظف الحالي أو السابق، **أو**
    - `employee_uuid` فيه = UUID الموظف الحالي.
  - الطريقة 1 تفحص كل الصفوف ذات نفس `expense_id` بدل `LIMIT 1` (أول صف قد يكون لموظف آخر).
  - عند التحديث يُكتب `employeeUuid` الجديد محلياً وفي payload الـ outbox.
  - `deleteByExpenseId(expenseId, employeeId:, employeeUuid:)`: عند تمرير أحدهما لا يُحذف إلا مسحوب هذا الموظف. بدونهما يبقى السلوك القديم (توافق).
  - شاشة المصروفات تمرّر `relatedId` و`employeeUuid` للمصروف عند الحذف، و`previousEmployeeId` عند التعديل.
- **Commit:** `9d2d9789`

### 2.4 R8 — عدم تخزين `relatedId` الخام لمصروفات الموظفين القادمة من السحابة
- **الملف:** `lib/services/adapters/expenses_adapter.dart`
- **قبل:**
  - عند فشل حل الـ UUID كان `fromJson` يرجع إلى `relatedId` الخام، أي id موظف في جهاز آخر، فيُحسب المصروف على موظف خاطئ.
  - `PayloadMapper.isSalaryExpenseType` لا يشمل `'سلفة'`، فالسلف لم تُحل بالـ UUID أصلاً.
- **بعد:**
  - دالة جديدة `ExpensesAdapter.isEmployeeLinked(type, employeeUuid)`، تُرجع صحيحاً إذا تحقق أي من: `isSalaryExpenseType`، أو `SalaryExpenseClassifier.isSalaryRelated` (يشمل السلفة والخصم والغياب)، أو وجود `employeeUuid` في الحمولة.
  - للمصروف المرتبط بموظف:
    - UUID محلول → `relatedId` = الموظف المحلي.
    - مصدر محلي → الـ id الخام (له معنى على نفس الجهاز).
    - مصدر بعيد غير محلول → `Value.absent()`: الإدراج يبقى `NULL`، والتحديث **لا يمسح** ربطاً محلياً صحيحاً.
  - المصروف العام (صيانة وغيرها) يحتفظ بـ `relatedId` كما هو.
- **ملاحظة:** لم يُعدَّل `PayloadMapper.isSalaryExpenseType` نفسه لأن له مستخدمين آخرين (`database_fixer`، `salary_fix_helper`).
- **Commit:** `645e0666`

### 2.5 R6 — عدم حذف المسحوب من طابور الرفع عند غياب موظفه
- **الملف:** `lib/services/appwrite_sync_manager.dart` (رفع `salary_withdrawals`)
- **قبل:** إذا لم يوجد الموظف محلياً → `return true`، فيُزال العنصر من الطابور ولا يصل المسحوب للسحابة أبداً.
- **بعد:**
  - الموظف موجود → يُرفع بـ UUID الموظف (كما كان).
  - غير موجود لكن المسحوب يحمل `employee_uuid` → يُرفع بهذا الـ UUID (Appwrite بلا FK).
  - لا هذا ولا ذاك → `return false`: يبقى في الطابور مع تحذير `⏸️ تأجيل`.
- **Commit:** `96f312b6`

### 2.6 R7 — مزامنة Google Drive التزايدية
- **الملف:** `lib/services/google_drive_delta_sync.dart` → `_applyChange`
- **قبل:**
  - `DeltaSyncService` يُنتج تغييرات `salary_withdrawals` و`salary_carry_over_logs`، لكن `_applyChange` بلا `case` لهما، فكانت تُسقط بصمت.
  - عملية `delete` كانت تحذف نهائياً أي كيان.
- **بعد:**
  - `case 'salary_withdrawals'` و`case 'salary_carry_over_logs'` عبر `upsertFromJson(src: Source.drive)`.
  - `default` يسجّل تحذيراً لأي كيان غير مدعوم بدل الإسقاط الصامت.
  - `delete` لـ `employees` / `expenses` / `salary_*` يُتجاهل مع تحذير (الحذف فيها soft عبر `update`).
- **Commit:** `35c4a723`

### 2.7 تعطيل سكربت التعبئة السحابي الخاطئ
- **الملف:** `scripts/appwrite/backfill_salary_withdrawals_employee_uuid.js`
- **السبب:** قاعدته (`employeeUuid` = الموظف ذو `serverId == employeeId`) خاطئة. 373 مسحوباً عُدّلت يوم 2026-09-19 تتبعها حرفياً، وكثير منها منسوب لموظف خاطئ.
- **بعد:**
  - `--apply` يُنهي التشغيل برسالة خطأ. يعمل كـ dry-run فقط.
  - أُزيل مفتاح Appwrite API المضمّن، والمفتاح يُقرأ من `APPWRITE_API_KEY` فقط.
- **Commit:** `9ee07247`

### 2.8 أداة فحص للقراءة فقط (أُضيفت قبل الإصلاح)
- **الملف:** `scripts/appwrite/readonly_export_salary_links.py`: تصدير GET فقط لمجموعات الموظفين والمصروفات والرواتب إلى `/tmp/appwrite_snapshot`، والمفتاح من متغيرات البيئة.
- **Commit:** `8e382af7`

## 3. الاختبارات

| الملف | المحتوى |
|---|---|
| `test/services/salary_link_protection_test.dart` (جديد، 7 اختبارات) | R3: `saveFromExpense` لا يعيد كتابة مسحوب موظف آخر بنفس الرقم · R3: `deleteByExpenseId` لا يحذف مسحوب موظف آخر · المطابقة عبر `employeeUuid` مع `relatedId` قديم · R12: انتقال المرآة للموظف الجديد بلا تكرار ومع UUID الجديد · R8: سلفة بلا UUID → `relatedId = null` · سلفة بـ UUID → الموظف الصحيح · مصروف عام يحتفظ بـ `relatedId` |
| `test/unit/id_resolver_cross_device_test.dart` (محدَّث) | `serverId` مكرر: بعيد → null، محلي → الاختيار الحتمي · UUID بعيد غير موجود → لا سقوط إلى `serverId` |

**النتائج (Flutter 3.44.4، Dart 3.12.2):**
- `flutter analyze` على الملفات المعدلة: **لا مشاكل**. `dart format`: لا تغييرات.
- `flutter test test/unit test/services`: **844 ناجحة، 0 فاشلة**.
- فشلت اختبارات أخرى خارج هذين المجلدين لأسباب لا علاقة لها بالتعديلات:
  - قياسات السرعة في `test/performance` (بيئة العمل بطيئة).
  - `delete_404_handling_test` (يتصل بخادم Appwrite حقيقي عبر الشبكة).
  - `restore_fix_service_test` (حد زمني: 17.9 ثانية مقابل 4 ثوانٍ).
- لم يُختبر على جهاز حقيقي أو في مزامنة فعلية مع السحابة.

## 4. ما لم يُصلح (يحتاج قراراً أو مرحلة لاحقة)

| # | البند | السبب |
|---|---|---|
| 1 | **السجلات المُفسدة في Appwrite Cloud:** ~144 حالة واضحة (957,200)، و~298 بمطابقة أوسع (~1,251,200)، و36 صفاً مكرراً محتملاً (127,000) | لا يوجد مصدر حقيقة في السحابة (لا `deviceId` لمعظم السجلات، و`audit_logs` فارغة، والطرفان معدَّلان). نحتاج نسخة احتياطية من قبل 2026-09-12 أو قاعدة الجهاز المنشئ |
| 2 | رفع المسحوب يكتب `employees.serverId = employee.id` محلياً | هذا مصدر تكرار `serverId` (R14). إيقافه يحتاج بديلاً لشرط "هل رُفع الموظف؟" |
| 3 | `OutboxDao` يحذف العنصر بعد 10 محاولات فاشلة | المسحوب المؤجل (2.5) قد يخرج من الطابور في النهاية. يبقى في الجدول لكنه لا يُرفع |
| 4 | `writeExpenseIdRaw` ما زال يكتب `expense_id` الأجنبي للمسحوبات القادمة من السحابة | الحل الجذري `expense_uuid` (المرحلة 1، Migration 68). الحارس في 2.3 يحد من الضرر فقط |
| 5 | تبنّي المرآة اليتيمة بالمبلغ واليوم، ومستوى المطابقة 4 في التقارير | يُستبدل بـ `v_salary_movements` في المرحلة 1 والقسم 6 من المسودة |
| 6 | مفاتيح Appwrite API مكتوبة مباشرة في سكربتات أخرى داخل `scripts/` | يجب إلغاؤها من لوحة Appwrite وإزالتها من المستودع |
| 7 | الإصدارات القديمة من التطبيق على أجهزة أخرى | ما زالت تحمل السلوك القديم حتى تُحدَّث. يُنصح بإجبار التحديث (القسم 10.3-د في المسودة) |

## 5. التأثير على Appwrite Cloud

- لا كتابة مباشرة في السحابة من هذه التعديلات.
- التعديلات **تقلل** ما يُرفع خطأً: ربط أقل بموظف خاطئ، وحذف أقل لمسحوب خاطئ.
- السلوك الوحيد الجديد الذي يكتب في السحابة: رفع مسحوب بـ `employee_uuid` الخاص به عندما لا يوجد موظفه محلياً (2.5). هذا الـ UUID مأخوذ من نفس السجل، لا مُخمَّن.

## 6. قائمة الـ Commits

| Commit | الوصف |
|---|---|
| `bb545a95` | R1: إيقاف الحذف النهائي لسجلات الرواتب اليتيمة |
| `9d2d9789` | R3/R12: حارس تصادم `expense_id` + تحديث `employee_uuid` |
| `8badc46e` | R2/R14: إزالة "الطريقة 2" ومنع التخمين في `IdResolver` |
| `645e0666` | R8: `relatedId` في `ExpensesAdapter` + شمول السلف |
| `96f312b6` | R6: عدم حذف المسحوب من طابور الرفع |
| `35c4a723` | R7: Drive delta للمسحوبات والترحيل + منع الحذف النهائي |
| `9ee07247` | تعطيل `--apply` في سكربت التعبئة وإزالة المفتاح المضمّن |
| `9acfd2fa` | الاختبارات الجديدة + حالة التنفيذ في المسودة الرئيسية |

## 7. الخطوة التالية المقترحة

1. قرار بشأن البند 1 في §4 (مصدر الحقيقة لتصحيح السحابة).
2. المرحلة 1: Migration 68 (`expense_uuid`، `expense_kind`، الفهارس) + `SalaryExpenseService` الذري.
3. بناء إصدار تجريبي واختباره على جهازين مع مزامنة فعلية قبل النشر.
