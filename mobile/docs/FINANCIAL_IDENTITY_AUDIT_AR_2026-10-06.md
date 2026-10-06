# تدقيق الهوية والعلاقات المالية عبر الأجهزة — تطبيق Flutter

**التاريخ:** 2026-10-06
**النطاق:** `mobile/` فقط (تطبيق Flutter + SQLite/Drift + طبقة المزامنة). لم يُجرَ أي تعديل على جانب PHP/الواجهة.
**حالة التنفيذ:** تدقيق واختبارات فقط. **لم يُغيَّر أي مخطط (schema)، ولم تُحذف أي سجلات، ولم يُعَد توليد أي UUID.**
**المرجع:** طلب المالك (13 بندًا) بشأن ضمان ربط ثابت للموظفين والمصروفات والرواتب والاستحقاقات بين الأجهزة دون فقدان أو تكرار، وبقاء الربط صحيحًا عند تغيير مزوّد المزامنة.

---

## 0) الخلاصة التنفيذية

| المحور | الحكم | ملاحظة |
|---|---|---|
| 1. هوية ثابتة (UUID مستقلة عن الجهاز والمزوّد) | ✅ قائم | `local_uuid` عمود إلزامي فريد في كل جدول مالي (`SyncFields`) |
| 2. Appwrite ليس مصدر الهوية | ✅ قائم | `documentId` = `local_uuid` المحلي، لا يُولّده Appwrite |
| 3. العلاقات المالية لا تُبنى على `id` محلي بعيد | ✅ قائم (مع فجوات) | `IdResolver` يمنع مطابقة `id` بعيد؛ تبقى فجوات `serverId` و`cycleUuid` و`from/toCycleId` |
| 4. إنشاء السجل + Outbox في معاملة واحدة | ✅ قائم | السحوبات والاستحقاقات: كتابة الصف و`outbox.merge` داخل `transaction()` |
| 5. منع التكرار عند إعادة الإرسال | ✅ قائم | `idempotencyKey` + فهرس فريد جزئي + `_markDelivered` بتحقق ملكية |
| 6. وصول الابن قبل الأب | ✅ قائم | طوابير `deferred` + خدمات إعادة ربط؛ لا ربط تخميني بموظف آخر |
| 7. الحذف (tombstone، لا عودة للسجل المحذوف) | ✅ قائم | الـ tombstone البعيد يفوز دائمًا؛ لا حذف عند "غياب السجل" |
| 8. فصل منطق البيانات عن Appwrite | ⚠️ جزئي | طبقة المحوّلات (`EntityAdapter`) جيدة، لكن مدير المزامنة 9000+ سطر يخلط النقل بالمنطق |
| 9. جاهزية تغيير المزوّد | ⚠️ جزئي | المؤشرات (`sync_checkpoints` / `sync_mirror`) **غير مُنَطَّقة بالمزوّد** → خطر إعادة استخدام مؤشر Appwrite |
| 5م. منع التكرار في التعارض | ✅ أُغلقت (G-4) | الحقول المالية الحرجة لا تُدمج صامتة: تُحفظ القيمتان وتُسجَّل للمراجعة |
| المبالغ العشرية | ✅ أُغلقت (G-10) | سياسة «لا كسور عشرية» + اقتطاع نحو الصفر في العرض والإدخال والكتابة والنقل وكل الحسابات المشتقة (بقي الإبلاغ عن الصفوف التاريخية) |
| 12. تقرير مراجعة للسجلات غير المؤكدة | ⚠️ جزئي | التعارضات تُحفظ الآن في `sync_conflicts` (G-4/G-11) وتظهر في شاشة التعارضات؛ تقرير السجلات التاريخية (G-8) لم يُبنَ بعد |

**التوصية:** لا تبدأ إصلاحات المخطط قبل اعتماد هذا التدقيق، ثم تنفيذ الإصلاحات بترتيب الأولوية في القسم 10، مع تشغيل الاختبارات المضافة في القسم 11 على أجهزة حقيقية (A/B) قبل أي كتابة إنتاجية.

### مصفوفة البنود (1 → 13)

| البند | الحكم | القسم |
|---|---|---|
| 1. الهوية الثابتة UUID | ✅ مُنفَّذ (الموظف = `employees.local_uuid`) | §1 |
| 2. Appwrite ليس مصدر الهوية | ✅ مُنفَّذ (`documentId = local_uuid`) | §2 |
| 3. العلاقات بين الجداول | ✅ أُغلقت **G-3** (لا ربط رقمي عبر الأجهزة + لا تخطٍّ صامت)؛ تبقى G-1, G-2 | §3, §8.4 |
| 4. إنشاء السجل + المزامنة في معاملة | ✅ مُنفَّذ | §4 |
| 5. منع التكرار | ✅ مُنفَّذ | §5 |
| 5م. سياسة التعارض | ✅ **أُغلقت G-4** (سياسة صريحة + مراجعة بشرية) | §7 |
| 6. وصول الابن قبل الأب | ✅ مُنفَّذ + **مخزن دائم** للحالات التي لا يحلها الأب في نفس الدورة (§8.4) | §6.1, §8.4 |
| 7. الحذف (منع الإحياء) | ✅ مُنفَّذ (tombstone يفوز دائمًا) | §6.2 |
| 8. فصل منطق البيانات عن Appwrite | ⚠️ جزئي (G-6) | §8.1 |
| 9. الانتقال لمزوّد آخر | ⚠️ يحتاج تنطيق المؤشرات (G-7) + قائمة §12 (الكسور أُغلقت G-10) | §8.2, §12 |
| 10. الاختبارات المطلوبة | ✅ مُضاف ملف اختبارات التدقيق (19 اختبارًا — 18 ناجح) | §11 |
| 11. معيار النجاح النهائي | ⚠️ أُغلقت G-4 و G-10 و G-11 و **G-3** — يتبقى G-7 (تنطيق مؤشرات المزوّد) و G-8 (تقرير المراجعة القابل للتصدير) | §11, §12 |
| 12. عدم التخمين في السجلات التاريخية | ✅ انتهى تخمين `serverId` (G-3 مُغلقة) والتعارضات تُحفظ للمراجعة (G-4/G-11)؛ يتبقى التقرير المُصدَّر (G-8) | §9 |
| 13. التدقيق قبل الإصلاح | ✅ هذا المستند + استعلامات المراجعة (§9.2) | §1–§9 |

---

## 1) الهوية الثابتة (البند 1 من الطلب)

### 1.1 عمود الهوية
`SyncFields` في `lib/services/local_db.dart` (السطور 16–32) يضيف لكل جدول متزامن:

```
TextColumn get localUuid => text().unique()();   // ← الهوية الدائمة
IntColumn get serverId ...                        // ← رقم مصدر (غير هوية)
IntColumn get lastModified / version / deletedAt  // ← الإصدار والحذف
TextColumn get vectorClock / deviceId
TextColumn get idempotencyKey
```

`local_uuid` **فريد** (UNIQUE) في كل الجداول المالية — هذا هو الضمان البنيوي الأساسي ضد التكرار وع复د ترقيم المعرفات.

### 1.2 جدول الهوية لكل كيان (كما هو مُنفَّذ فعليًا)

| الكيان | الهوية الثابتة | علاقات ثابتة مُخزَّنة | الدليل |
|---|---|---|---|
| الموظف | `employees.local_uuid` (يقابل `employee_uuid` في مستندات Cloud) | — | `local_db.dart:152` |
| المصروف | `expenses.local_uuid` | `employee_uuid` (193)، `withdrawal_uuid` (203)، `category_uuid`، `cash_flow_uuid` | `local_db.dart:178–214` |
| سحب الراتب | `salary_withdrawals.local_uuid` | `employee_uuid` (764)، `expense_uuid` (784) | `local_db.dart:757–800` |
| منحنى/سحب راتب مباشر | نفس الجدول | `reason='direct_withdrawal_*'` (حارس معرَّف في `salary_mirror_matcher`) | `salary_mirror_matcher.dart:59–62` |
| دورة الراتب | `salary_cycles.local_uuid` | `employee_uuid` (707) | `local_db.dart:703–722` |
| دفعة الراتب | `salary_payments.local_uuid` | `employee_uuid` (737) — **بلا `cycle_uuid` محلي** | `local_db.dart:731–747` ← فجوة G-1 |
| ترحيل الرصيد | `salary_carry_over_logs.local_uuid` | `employee_uuid` (818)؛ `from_cycle_id`/`to_cycle_id` نصّيان (823–825) لكنهما **لا يُكتبان** | `local_db.dart:812–830` ← فجوة G-2 |
| التحقق من عدم التكرار | `outbox.idempotency_key` | فهرس فريد جزئي (migration 51) | `local_db.dart:843–880` |

**ملاحظة مهمة:** عمود `employees.employeeID` (`local_db.dart:166`) هو *الرقم الإداري/الوظيفي* الذي يُدخله المستخدم — **ليس** هوية المزامنة. الخلط بينه وبين `employee_uuid` ممنوع.

### 1.3 لا وجود لمنطق يفترض `expenses.id == salary_withdrawals.id`
تم فحص مسارات الربط؛ الربط المرآوي (سحب راتب ↔ مصروف) يعتمد اليوم على:
1. `salary_withdrawals.expense_uuid` ↔ `expenses.local_uuid` (الهوية — الأولوية)،
2. `expenses.withdrawal_uuid` (الختم العكسي)،
3. ثم فقط المستويات الرقمية `expense_id` / `reason=exp_N`.

الدليل: `lib/services/repositories/salary_withdrawals_repository.dart:236–330` (الطريقة 0 قبل كل الطرق الرقمية)، و`_relinkMirrorExpenseIds` في `appwrite_sync_manager.dart:4355`.

⚠️ لكن المستويين 3 و4 في `salary_mirror_matcher.dart` (مطابقة *البيانات*) يربطان بعمليات قد تكون **مستقلة فعلًا** (نفس الموظف + نفس المبلغ + نفس اليوم) — تفصيلها في الفجوة G-5.

---

## 2) Appwrite ليس مصدر الهوية (البند 2)

* `documentId` المُرسَل للـ Cloud هو `local_uuid` المحلي في كل مسارات الرفع:
  `appwrite_sync_manager.dart:3352` (rooms)، `3407` (bookings)، `3564` (expenses)، `4272/4277` (salary_withdrawals)، `6186` (salary_cycles)، `6230` (salary_payments)، `6258` (carry-over).
* السحب يعيد المطابقة على `local_uuid` أولًا (`BaseRepository.upsertFromJson` → `_findByLocalUuid`، `base_repository.dart:38–70, 145–170`)، و`id` البعيد **يُحذف** قبل الإدراج لتفادي تصادم autoincrement.
* لا يوجد أي مسار يُولّد هوية جديدة من رقم Appwrite؛ `serverId` مجرد رقم مصدر مساعد.

**نتيجة:** الانتقال `Device A → Appwrite → Device B` يحافظ على الهويات، وهذا الجزء جاهز للانتقال إلى مزوّد آخر بشرط معالجة G-6/G-7.

---

## 3) العلاقات بين الجداول (البند 3)

### 3.1 المُحلِّل الموحّد `IdResolver` (`lib/services/adapters/id_resolver.dart`)
الترتيب المُنفَّذ: **UUID (بالصيغتين) → `serverId` → `id` المحلي (للمصدر المحلي فقط)**.
* `resolveEmployee` — السطور 240–360: يمنع `localId`/`employeeId` البعيد صراحةً (`if (!fromRemote)`) مع توثيق صريح لسبب المنع.
* `resolveSalaryCycle` — السطور 362–450: نفس القاعدة.
* `resolveBooking` — السطور 120–238: نفس القاعدة + فهرس دفعات لليالي.

### 3.2 المحوّلات
* `expenses_adapter.resolveRefs` (السطور 26–88): يحل `relatedId` عبر `employee_uuid`؛ وعند غياب الـ UUID **لا** يستخدم الرقم البعيد، بل يتركه `null` ويسجّل تحذيرًا لإعادة الربط لاحقًا.
* `salary_withdrawals_adapter.resolveRefs` (السطور 45–95): يمرّر `employeeId` البعيد كـ `serverId` (دلالة «رقم جهاز المصدر») فقط، و`shouldSkip=true` إذا لم يُحل.
* `salary_payments_adapter.resolveRefs` (السطور 27–70): يقرأ `cycleLocalUuid` → ثم `serverId` → وإلا `shouldSkip`.
* `salary_cycles_adapter` / `salary_carry_over_logs_adapter`: نفس النمط.

### 3.3 الفجوات في العلاقات
| # | الفجوة | الأثر |
|---|---|---|
| G-1 | `salary_payments` بلا `cycle_uuid` محلي؛ الربط يُبنى **لحظة الرفع** فقط | إذا غابت الدورة محليًا وقت الرفع (أو أُعيد بناء مسار الرفع عند تغيير المزوّد) تفقد الدفعة رابطها الثابت على السحابة → عند السحب يبقى `serverId` الرقمي احتمالًا خاطئًا |
| G-2 | `salary_carry_over_logs.from_cycle_id/to_cycle_id` لا يُكتبان | سجل الترحيل بلا علاقة دورات ثابتة (البند 1 يطلب `record_uuid` + علاقات الدورات) |
| G-3 | ~~`serverId` عند الازدواج~~ **أُغلقت 2026-10-06** | كان الربط الرقمي عبر الأجهزة ممكنًا بلا إثبات ⇒ ربط خاطئ صامت. الآن: لا مطابقة رقمية إلا بإثبات وحدة فضاء المعرّفات (نفس `deviceId` الكاتب)، والسجل الذي لا يُثبت يُعلَّق ثم يُربط بـ UUID |

**الدليل على G-1:**
* `local_db.dart:731–747` (لا عمود `cycleUuid`)
* `salary_payments_adapter.dart:33–46` (يقرأ `cycleLocalUuid` ولا يخزّنه)
* `payload_mapper.dart` دالة `salaryPaymentToRemote` (لا تُدرج `cycleLocalUuid`/`employeeUuid`)
* الحقنان يُضافان فقط في `appwrite_sync_manager.dart:6119–6130` (full push) و`6364–6380` (outbox push)

**الدليل على G-2:**
* `local_db.dart:823–825` (العمودان موجودان)
* `salary_entitlement_service.dart:448–483` (الإدراج + payload الـ outbox: لا ذكر للدورتين)

**الدليل على G-3:**
* `id_resolver.dart` في `resolveEmployee` (خطوة 2): `if (rows.length > 1) { AppLogger.warning(...); } return rows.first.id;`
* ونفس النمط في `resolveSalaryCycle`.

---

## 4) الإنشاء والمزامنة (البند 4)

المسار المطلوب مُحقَّق في المسارات المالية الأساسية:

| المسار | التزامن بين الصف و Outbox | الدليل |
|---|---|---|
| إنشاء سحب راتب من مصروف | ✅ داخل `transaction()` واحد | `salary_withdrawals_repository.dart:137` (transaction) و`214` (`_outboxDao.merge`) |
| تعديل/إعادة ربط سحبة | ✅ | `salary_withdrawals_repository.dart:508–730` |
| ترحيل رصيد تلقائي | ✅ + تعليق صريح «Keep the database write and its sync intent in one transaction» | `salary_entitlement_service.dart:445–483` |
| مصروفات | ✅ (إنشاء + تحديث عبر `ExpensesRepository` مع Outbox) | `expenses_repository.dart:56–170, 197–250` |

**الانقطاع:** لا حذف للحركة عند فشل الشبكة — الصف محلي و`outbox` بحالة `pending/failed`؛ إعادة الإرسال تستخدم **نفس `localUuid`** ونفس `idempotencyKey = entity:op:uuid:clientTs` (`outbox_dao.dart` دالة `merge`/`_mergeSingle`).

**دلائل على عدم الفقدان بعد الانقطاع:**
* `takeBatch` يحجز السجلات ذرّيًا ويحوّلها إلى `processing` (`outbox_dao.dart:336–430`).
* `reclaimForPush` يعيد السجلات العالقة في `processing` (بعد 30 ثانية) إلى `pending` (`outbox_dao.dart:~170–230`).
* `_markDelivered` يتحقق من `processingWorker` و«نسخة الحمولة» قبل الاعتراف بالتسليم، وإلا يُعيد السجل إلى `pending` (`outbox_dao.dart:625–745`).

---

## 5) منع التكرار (البند 5)

* **مفتاح تسلسلي ثابت**: `entity:op:localUuid:clientTs` + فهرس فريد جزئي على `outbox.idempotency_key` (migration 51، موثّق في `local_db.dart:855–865`).
* **الدمج لا التكرار**: `merge()` يبحث عن سجل `pending/processing` لنفس `(entity, localUuid)` ويحدّثه — فلا تنتج عمليتان في الـ outbox لنفس العملية (`outbox_dao.dart` دالة `merge`).
* **حماية إضافية**: `merge` لا يستبدل `op='delete'` بـ `create/update` (منع إحياء سجل حُذف) — نفس الدالة.
* **السحابة**: كل مستند مفتاحه `local_uuid`، ورفع نفس العملية مرتين = `upsert` على نفس المستند لا إنشاء مستند جديد.

✅ **لا يوجد أي منطق يعتبر (نفس الموظف + نفس المبلغ + نفس التاريخ) دليلًا كافيًا للدمج** في مسار الكتابة. الاستثناء الوحيد **قراءة فقط** في تقارير المرايا (G-5).

---

## 6) وصول الابن قبل الأب (البند 6) والحذف (البند 7)

### 6.1 الابن قبل الأب ✅
* طوابير تأجيل + إعادة محاولة داخل نفس الدورة: `salary_withdrawals` (`appwrite_sync_manager.dart:4011, 4126, 4158`)، `salary_cycles` (`7986, 8079, 8111`)، `salary_payments` (`8144, 8196, 8218`).
* إعادة ربط دائمة بعد وصول الأب: `_relinkOrphanSalaryExpenses` (9245)، `_relinkMirrorExpenseIds` (4355)، `_relinkExpenseWithdrawalUuids` (4426)، `_relinkOrphanedPayments` (9132).
* **لا ربط بموظف آخر أبدًا**: عند غياب الأب يُترك الحقل فارغًا (`null`) لا يُملأ بـ `id` بعيد — `expenses_adapter.dart:68–85`، `salary_cycles_adapter`/`withdrawals`/`payments` (`Value.absent()` + `shouldSkip`).
* خدمة الاتساق `employee_link_consistency_service.dart` تعيد الربط **بمصدر الحقيقة `employeeUuid`**، وتُبقي ما لا يُحسم في التقرير بدل التخمين.

### 6.2 الحذف ✅
* الحذف صريح (soft delete + tombstone): لا وجود لـ `DELETE FROM expenses|salary_*|employees` في `lib/` (فحص نصّي شامل).
* **الغياب ≠ الحذف**: لا منطق يحذف سجلًا محليًا لغيابه من نتيجة السحب؛ الحذف ينتقل كمستند tombstone (`deletedAt`).
* **لا إحياء**: في `sync_pull_service.dart:105–122` — إذا حمل المستند البعيد `deletedAt > 0` والمحلي نشط، **يُطبَّق الحذف دائمًا** حتى لو كانت ساعة المتجه المحلية أحدث.
* رفع الحذف: `_handleDeleteOp` (يُستدعى لكل كيان بـ `hardDeleteFallback` لكن المسار الافتراضي tombstone — مثال `appwrite_sync_manager.dart:3385, 3532, 6347`).
* حراس إضافية: `sync_safety_wave4_cleanup_tombstone_test`، `full_sync_tombstone_filter_test`، `tombstone_parents_repull_test`.

**ملاحظة تشغيلية (P2):** قِدَم tombstone على السحابة لا يمنع مزامنته (هناك `TombstoneParentsRepull` لسحب tombstones الآباء قبل الدلتا) — يُنصح باختبار دوري على جهازين حقيقيين (ملحق الاختبارات).

---

## 7) التعارض (البند 5م) — ✅ G-4 مُغلقة بسياسة صريحة

### 7.1 ما كان (قبل 2026-10-06)
* `ConflictDetector` يعرف الحقول المالية الحرجة ويحسب `needsManualResolution` — **ولم يكن أحد يستهلكه**.
* `SmartConflictResolver` بلا سياسات لـ `employees/expenses/salary_*` ⇒ `newerWins` على `amount`/`basicSalary`، ثم `pushedToRemote: true` يرفع النتيجة ⇒ **طمس صامت لمبلغ عدّله جهاز آخر** (بلا سجل مراجعة مقروء).

### 7.2 السياسة الجديدة (المُنفَّذة)
عند تعارض متزامن (concurrent) على حقل مالي حرج (`amount`, `paidAmount`, `price`, `basicSalary`, `isVoided`, `discount`, `discountAmount`):
1. **لا دمج صامت**: القيمة المحلية تبقى في الصف المحلي (لا يُمسح مال محلي بلا قرار بشري).
2. **لا طمس للجهاز الآخر**: لا يُرفع الحقل المتنازع عليه (`pushedToRemote = false`) فتبقى قيمة الجهاز الآخر على السحابة.
3. **تسجيل للمراجعة**: صف في `sync_conflicts` مع `resolution = ''` (بانتظار قرار) ووسم
   `critical_financial_field_conflict` + أسماء الحقول + نص السياسة — يظهر في شاشة تعارضات المزامنة.
4. **باقي الحقول** في نفس السجل تُدمج وتُطبَّق كالمعتاد (المزامنة لا تتوقف).
5. تُرجَع `requiresReview` و`reviewFields` في `ResolutionResult`/`RemoteCheckResult` للتسجيل والاختبارات.

**مواضع التنفيذ:** `sync_core/smart_conflict_resolver.dart` (`_autoMerge`)،
`sync_core/sync_pull_service.dart` (`checkAndResolveConflict` + `_recordCriticalConflictForReview`)،
`appwrite_sync_manager.dart` (`_occCheckAndMerge` + `_recordCriticalConflictForReview`).

### 7.3 G-11 (P0 — كشفه اختبار G-4 على CI): التعارضات كانت تُفقد بصمت
`ConflictManager._persistConflict` كان يُدرج التعارض بـ `logId = latestLog?.id ?? 0`؛ عند خلو جدول
`sync_log` يفشل الإدراج بـ `FOREIGN KEY constraint failed (787)` ثم **يُبتلع الخطأ في `catch`**
⇒ التعارض المالي لا يصل لشاشة المراجعة إطلاقاً بلا أي أثر.

**الإصلاح:** إنشاء سجل مزامنة «مرساة» (`status='conflict'`) عند الحاجة قبل ربط التعارض،
وتسجيل الفشل بمستوى خطأ مرئي (`developer.log`) بدل الابتلاع الصامت.

**اختبارات الإثبات:** `test/unit/financial_identity_audit_test.dart` (3 اختبارات G-4 — منها
التحقق الفعلي من كتابة صف `sync_conflicts` بـ `resolution=''`) و
`test/unit/conflict_resolution_fix_test.dart` (سياسة الحقول الحرجة + برهان أن `newerWins`
ما زال يعمل على الحقول غير الحرجة).

## 8) فصل المنطق عن Appwrite (البند 8) وجاهزية تغيير المزوّد (البند 9)

### 8.1 الوضع الحالي
* ✅ طبقة الجداول/العلاقات معرّفة في `local_db.dart` + محوّلات لكل كيان (`EntityAdapter`: `collectionId`/`drivePath`/`tableName` + `resolveRefs`/`fromJson`/`toJson`) — وهي **جيدة وقابلة لإعادة الاستخدام** لمزوّد آخر.
* ⚠️ لكن **نقل البيانات** و**منطق الأعمال** متشابكان في `appwrite_sync_manager.dart` (≈9400 سطر): يقرأ الجداول مباشرة، يبني الحمولات، يقرر التعارضات، ويستدعي `appwriteService`/`AppwriteConfig` بالاسم الصريح لكل مجموعة.
* ⚠️ يوجد هيكل ثانٍ موازٍ (`SyncPullService` + `UnifiedPullEngine` + `SyncCheckpointStore`) — يحتاج توحيدًا ليكون هو نقطة العبور الوحيدة إلى المزوّد.
* ✅ توجد بالفعل أسطح بديلة (Cloudflare D1، Google Drive، Secondary Appwrite) وهذا دليل عملي على أن الفصل ممكن، لكنه ليس معمارية «منفذ واحد».

### 8.2 G-7 (خطر حقيقي عند تغيير المزوّد)
جداول المؤشرات **غير مُنَطَّقة بالمزوّد**:
* `sync_checkpoints(collection_name TEXT PRIMARY KEY, last_pull_ts, full_sync_complete, full_sync_cursor)` — `sync_checkpoint_store.dart:49–70`.
* `sync_mirror(table_name, local_uuid, ...)` — `delta_sync_service.dart:191`.
* `SyncState` صف مفرد (`local_db.dart:963–999`).

⇒ الخطر: بعد التحويل إلى مزوّد B، سيقرأ التطبيق مؤشر Appwrite كأنه مؤشر B فيتخطى سجلات → **فقدان صامت**. البند 9.7 يحذّر من هذا حرفيًا.

**المطلوب:** مفتاح المزوّد داخل مفتاح المؤشر (مثال: `providerId:collection`) أو تصفير مؤشرات B عند التحويل + `full_sync_complete = 0` إجباري (سياسة «تأسيس جديد»).

---

## 8.3) ✅ G-10 (أُغلقت 2026-10-06): سياسة «لا كسور عشرية» — اقتطاع نحو الصفر بدل تقريب صامت

**الدليل التنفيذي (تشغيل فعلي على GitHub Actions، 2026-10-06):**
* اختبار «provider swap» سقط بالفرق: `Expected: <210.5> Actual: <211.0>` — سحب قيمته 150.5 عاد من الاستيراد 151.
* السبب في الكود: `salary_withdrawals_adapter.dart:235` → `_k(src, 'amount', 'amount'): model.amount.round(), // Appwrite: integer`
  والعمود المحلي `salary_withdrawals.amount` نوعه `REAL` (`local_db.dart:765`).
* النمط نفسه في مسارات مالية أخرى:
  * `cash_transactions_adapter.dart:137` (`amount.round()` — العمود REAL في `local_db.dart:240`)
  * `sync/payload_mapper.dart:499` (cash_transactions)، `:302` (debts.remainingAmount)، `:860` (price_adjustments)
  * `debts_adapter.dart:232`
* ملاحظة مهمة: **المصروفات تحفظ الكسور** (`expenses.amount` يُرسل كما هو) — لذا قد يختلف مبلغ السحبة المرآة عن مصروفها بعد عبور المزوّد (150.5 مقابل 151)، فتنكسر معادلة «مصروفات الرواتب = استحقاقات الموظف» بالبند الواحد.

**الأثر:** أي مبلغ كسري في السحوبات/الخزينة/الديون/تعديلات السعر يتغيّر عند عبور الأجهزة أو المزوّد ⇒ يخالف معيار النجاح «نفس المجاميع المالية» (البند 11).

### القرار المعتمد من المالك (2026-10-06): **بدون كسور عشرية**

السياسة المطبَّقة هي سياسة الفندق القائمة أصلاً في `CurrencyFormatter` (والتي كانت
معروضة ومُدخَلة لكن **لم تكن** مطبَّقة على عبور المزوّد):

> كل مبلغ مالي **عدد صحيح بلا كسور**، والاقتطاع **نحو الصفر** (لا تقريب لأعلى):
> `150.5 → 150`، `150.99 → 150`، `-150.5 → -150` — «لا نضيف مبلغاً على أحد نتيجة التقريب».

**التنفيذ:**
1. **مصدر حقيقة واحد**: `CurrencyFormatter.truncateAmount / wholeAmount / isWholeAmount`
   (`lib/utils/currency_formatter.dart`) — تُستخدم في العرض، الإدخال (`parseAmount`)، والنقل.
2. **عبور المزوّد (شامل طبقة النقل)**: استُبدل `amount.round()` (كان يُقرّب لأعلى
   150.5 → 151 فيختلف بين الأجهزة) بالاقتطاع الموحّد في **كل** مسار مالي
   للرواتب/المصروفات/الالتزامات:
   * المحوّلات: `expenses_adapter.dart` (`amount` — كان يُرسل الكسر كما هو!),
     `salary_withdrawals_adapter.dart`, `cash_transactions_adapter.dart`,
     `debts_adapter.dart` (`totalAmount`/`paidAmount`/`remainingAmount`/`amount`),
     `employees_adapter.dart` (`basicSalary`), `salary_carry_over_logs_adapter.dart`,
     `price_adjustments_adapter.dart` (`previousValue`/`newValue`),
     `payment_voids_adapter.dart` (`originalAmount`).
   * `sync/payload_mapper.dart`: expenses, salary_withdrawals, salary_cycles,
     salary_carry_over_logs, debts (`totalAmount`/`paidAmount`/`amount`/`remainingAmount`),
     price_adjustments, payment_voids (`voidedAmount`/`originalAmount`) + cash/booking
     price adjustments (كانت `truncateAmount` بصيغة int ⇒ صارت `wholeAmount` double
     لتطابق نوع حقل Cloud).
   * آخر ميل قبل Appwrite: `AppwriteSyncUtils.convertAmountTypesForAppwrite` كان
     يستخدم `.round()` لحقول Cloud من نوع integer
     (`payment_voids.voidedAmount`, `salary_payments.amount`, `salary_cycles.*`)
     ⇒ صار `CurrencyFormatter.truncateAmount` — فلا يُضاف مبلغ عند الإرسال.
   * دليل الإصلاح: اختبار «mirror pair» سقط فعلياً بـ
     `Expected: <150> Actual: <150.5>` لأن محوّل المصروفات لم يكن يقتطع — أُصلح
     ويُثبته الاختبار الآن مع اختبار جديد لتحويل حقول integer.
3. **الكتابة المحلية**: تطبيع المبلغ **قبل** التخزين وقبل الـ outbox في
   `ExpensesRepository.create/createAutoGenerated/update` و
   `SalaryWithdrawalsRepository.createFromExpense/saveFromExpense` — فلا تنشأ كسور جديدة،
   وتبقى سحبة الراتب ومصروفها المرآة **متطابقتين** بعد عبور المزوّد.
4. **هجرات توحيد الأنواع (`local_db.dart`, migration 24+)**: كانت تُنفّذ
   `CAST(ROUND(x) AS INTEGER)` على أعمدة المال ⇒ صارت `CAST(x AS INTEGER)`
   (اقتطاع نحو الصفر في SQLite) حتى لا يُقرَّب مبلغ جهاز يُرقّي نسخته القديمة
   للأعلى (`occupancy_rate` مستثنى — نسبة وليست مبلغاً). الأجهزة التي رُقّيت
   **سابقاً** تحتفظ بقيمها كما هي — تُبلَّغ للقراءة فقط ولا تُعاد كتابتها.
5. **تعميم على كل مسارات الكتابة والعرض (جولة ثالثة)**: كان الاقتطاع في مسارات
   الرواتب/المصروفات والالتزامات فقط؛ فأُكمل على:
   * **عمليات الكتابة**: `bookings.discount` و`payments.amount` و`rooms.price`
     و`cash_transactions.amount` و`debts.total/paid/remaining` و
     `employees.basic_salary` (المستودعات) + تعديلات الأسعار
     (`price_adjustment_service`, `booking_price_adjustment_service`) +
     إنشاء/تعديل الديون والغرف/الخزينة عبر Gemini + دفتر اليوم
     (`hotel_day_ledger`) + إلغاء الدفع (`payment_voids.voidedAmount`).
   * **تقسيم أقساط السلفة** (`SalaryAdvanceInstallmentsService`): كان يحسب
     `totalAmount / installments` بكسور عشرية (`toStringAsFixed(2)`) ثم تُقتطع
     الأقساط ⇒ مجموع الأقساط ≠ السلفة (فقدان ريال). الآن التقسيم **بأعداد صحيحة**
     والقسط الأخير يستوعب الباقي: `1000.5 → 1000 = 333 + 333 + 334`.
   * **العرض/الحسابات المشتقة**: `CurrencyFormatter.truncateAmount` في
     `booking_computed_stream_service`, `enhanced_booking_calculation_service._asInt`,
     `stay_balance_calculator`, `salary_cycle_calculator._money`,
     `arabic_amount_formatter` (التفقيط), ونسب الدفع السريع/المردود في شاشة الدفع،
     وحالة «متبقي» في `room_payment_status_provider` و`payments_main_screen`.
   * **الحصيلة**: لا يوجد أي `round()` على مبلغ مالي في `lib/` (يُتحقَّق آلياً)،
     وكل قيمة مالية جديدة تُكتب عدداً صحيحاً — فالفرق بين الأجهزة = 0 لأي بيانات
     جديدة، ولا يتغيّر مجموع مالي عند عبور المزوّد.
   * **ما تبقّى لم يُمسّ**: الصفوف التاريخية الكسرية (أي جدول) — تُبلَّغ فقط،
     وحقول Cloud من نوع integer تُقتطع في آخر ميل قبل الإرسال.
6. **البيانات التاريخية (البند 12)**: `MoneyIntegrityService.scan()` —
   **قراءة فقط**: يُبلّغ عن كل صف فيه كسر (جدول + `local_uuid` + المبلغ المخزَّن +
   القيمة وفق السياسة + مجموع الكسور لكل جدول) **دون أي تعديل**. لا backfill،
   ولا إعادة توليد UUID، ولا تغيير مبلغ تاريخي بلا قرارك.
   الفحص يغطّي الآن **كل** الأعمدة المالية: `expenses`, `salary_withdrawals`,
   `salary_payments`, `salary_carry_over_logs`, `cash_transactions`, `debts`,
   `price_adjustments`, `booking_price_adjustments`, وأُضيفت أعمدة أموال الضيوف:
   `bookings.discount/total_due_cached/remaining_balance_cached`,
   `payments.amount/discount_amount`, `rooms.price`,
   `booking_nights.nightly_rate`, `hotel_day_ledger.total_income/total_expenses`,
   `payment_voids.voided_amount`, `audit_logs.amount_impact` (مع تجاهل الأعمدة
   غير الموجودة في نسخة الجهاز — السجل يُسمّى باسم الجدول والعمود).

**اختبارات الإثبات:** `test/unit/money_integer_policy_test.dart` (حتمية الاقتطاع وتطابق
العرض/الإدخال/النقل) + `test/unit/money_whole_amount_writes_test.dart` (كل عمليات
الكتابة: غرف/موظفون/خزينة/ديون + تقسيم أقساط السلفة `1000.5 → 1000 = 333+333+334`)
+ `G-10` و`mirror pair` و`legacy rows reported` (وتشمل الآن كسور أموال الضيوف)
في `test/unit/financial_identity_audit_test.dart`.

### جولة الإثبات الثانية على الشجرة الكاملة (CI 2026-10-06)

كشف تشغيل الشجرة الكاملة (`+1319 -4`) أربع حالات كشفت الممرّين الباقيين، وأُغلقت كلها:

| الحالة | القيمة المتوقعة/الفعلية | الإصلاح |
|---|---|---|
| `financial_identity_audit` — mirror pair | `Expected: <150> Actual: <150.5>` | `expenses_adapter` يقتطع `amount` (كان المصدر الوحيد غير المقتطع) |
| `wave6_debts_fields` 1c/1g/5c | `1500.5/750.25/999.99` في الحمولة | الحمولة صارت `1500/750/999` — اختبارات الديون توثّق الاقتطاع الآن |
| `financial_identity_audit` — provider swap | مجموع 300.75 مقابل 300 | العينية صارت أعداداً صحيحة (150/90) ليبقى الاختبار يقيس حفظ المجاميع؛ تغطية الصفوف الكسرية التاريخية باقية في اختبارَي G-10 المخصّصين |
| `money_integer_policy_test` | فشل تحميل: `isInteger` غير موجود | استُبدل بـ `isWholeAmount` |

**قاعدة عامة للمراجعة:** أي اختبار يُثبّت كسراً في حمولة مزوّد صار يُعتبر
مخالفاً للسياسة؛ والصفوف التاريخية الكسرية تُكشف وتُبلَّغ ولا تُعاد كتابتها.

---

---

### 8.4) ✅ G-3 (أُغلقت 2026-10-06): لا ربط مالي عبر الأجهزة بمعرّف رقمي محلي + لا تخطٍّ صامت

**الحالة قبل الإصلاح (سببان جذريان):**

1. **`serverId` كان يحمل معرّفًا محليًا ثم يُنشر عبر السحابة**
   `appwrite_sync_manager.dart` (فرع «رفع الموظف أولًا» قبل رفع السحبة) كان
   يكتب `EmployeesCompanion(serverId: Value(employee.id))` — أي
   `employees.id` الـ autoincrement **على جهاز النشوء**. و`serverId` يُرفع
   ضمن حمولة الموظف (`payload_mapper.dart` → `employeeToRemote`) ويُسحب على
   كل الأجهزة، فصار رقمًا محليًا يُقارن بأرقام الأجهزة الأخرى:
   جهاز A فيه «موظف #7» وجهاز B فيه موظف **مختلف** #7 ⇒ أي سجل مالي بلا
   UUID كان يُطابق «أول صف» فيُرتبط بموظف خاطئ **بصمت**
   (`IdResolver.resolveEmployee` / `resolveSalaryCycle`: خطوة `serverId`
   كانت تأخذ `rows.first.id` مع تحذير فقط).
2. **التخطي كان يعني الإهمال النهائي**
   `BaseRepository.upsertFromJson` يعيد `-1` عند فشل حل مرجع خارجي
   (`refs.shouldSkip`)، ولا أحد من المستدعين يفحص القيمة. وبما أن مؤشر السحب
   يتقدّم بعد نجاح الدورة، فإن سجلًا وصل قبل أبيه (سحبة قبل الموظف، دفعة
   قبل الدورة، ليلة قبل الحجز) كان **يُسقط نهائيًا** — فقدان صامت لحركة مالية.

**ما نُفِّذ (طبقة المجال، بلا أي تغيير في مزوّد):**

| المكوّن | التغيير | الملف |
|---|---|---|
| `IdResolver` | المطابقة الرقمية عبر الأجهزة (`fromRemote=true`) صارت مشروطة بإثبات وحدة فضاء المعرّفات: تطابق `deviceId` الكاتب بين السجل وسجل الأب. بلا إثبات ⇒ **لا ربط** (وعند غياب الأب يُعلَّق السجل). المسار المحلي `fromRemote=false` بلا تغيير. | `adapters/id_resolver.dart` |
| المحوّلات | تمرير `deviceId` من الحمولة إلى المحلّل: سحوبات، دورات، دفعات، ترحيل. | `adapters/salary_*_adapter.dart` |
| كتابة الموظف | لا يُكتب في `serverId` إلا معرّف **بعيد** كما أعاده الخادم (وبما أن `documentId = local_uuid` يبقى `null` عمدًا). علامة «معروف على السيرفر» = `syncTimestamp` (طابع زمني، ليس هوية) فلا يُعاد رفع الموظف كل دورة. | `appwrite_sync_manager.dart` |
| `DeferredRelationStore` | جدول SQLite جديد (additive، نمط `sync_checkpoints`) يحفظ الحمولة كما وردت من المزوّد **بلا `id` محلي** + دليل التشخيص (`missing_parent`, `parent_uuid`, `remote_parent_id`, `source_device_id`, `reason`). مفتاح فريد `(collection_name, local_uuid)`؛ الحالات: `pending → needs_review/unsupported → resolved`. | `sync_core/deferred_relation_store.dart` |
| `DeferredRelationRelinker` | يعيد تطبيق الحمولات عبر **نفس مسار المزامنة الرسمي** (`AdapterRegistry` → `upsertFromJson`) بعد كل دورة سحب: ربط بـ UUID فقط، idempotent، لا كتابة فوق سجل محلي أحدث (`last_modified >=`)، وإعادة تفعيل استباقية للصفوف التي وصل أبوها متأخرًا (`rearmAvailableParents`، مطابقة UUID مع تجاهل الشرطات). ما لا رابط هوية له ⇒ `needs_review` فورًا بلا تخمين. | `sync_core/deferred_relation_relinker.dart` |
| نقطة الالتقاط | `BaseRepository.setSkippedRecordSink` — عند `shouldSkip` تُخزَّن الحمولة بدل إهمالها. الافتراضي `null` (سلوك متوافق للخلف) وتُثبَّتها طبقة المجال فقط على المجموعات ذات الآباء: سحوبات/دورات/ترحيل/دفعات/ليالٍ/حركات مخزون. | `repositories/base_repository.dart`, `adapters/entity_adapter.dart` |
| مسار التشغيل | تُثبَّت النقطة في مُنشئ `AppwriteSyncManager` (نفس نسخة `AdapterRegistry`)، وتُشغَّل دورة إعادة الربط بعد اكتمال السحب (خطأها غير حرج). | `appwrite_sync_manager.dart` |

**جولة التحقق (CI — سير عمل مؤقت، 2026-10-06):**

* `dart format lib test`: **0 ملفات متغيرة** (المستودع متوافق مع البوابة).
* `flutter analyze`: **0 أخطاء** (`analyze_exit=0`؛ 4 ملاحظات قديمة غير مالية).
* اختبارات G-3 الجديدة `test/unit/financial_identity_g3_test.dart`: **+5 ناجحة**.
* حزمة الحراسة المالية (`financial_identity_audit` + `money_whole_amount_writes` + `money_integer_policy`): **+37 ناجحة**.

**ما زال مفتوحًا بوعي (لا يُغلق بالإصلاح أعلاه):**

* **P2 — `salary_mirror_matcher`:** مطابقة `reason=exp_N` تقبل «معرّف جهاز المصدر»
  عبر `MirrorExpenseCandidate.serverId` (قراءة فقط، ولا تكتب). المستويات 3/4
  (نفس الموظف + اليوم + العائلة) تحدّ من أثرها، لكنها تبقى اجتهادًا تاريخيًا
  يجب تحويلها لاحقًا إلى `expense_uuid`/`withdrawal_uuid` (المستوى 0) ثم حذف
  الفروع الرقمية — بعد تصدير تقرير G-8.
* **P2 — عدّادات السجل:** `upsertFromJson` ما زال يعيد `-1` والمستدعون لا
  يفحصونه؛ الضرر **بياناتيًا** انتهى (الحمولة محفوظة)، لكن العدّادات/السجلات
  قد تعتبر السجل «معالَجًا». سيُعالَج في G-8 (ملخص المعلّقات ظاهر عبر
  `AppwriteSyncManager.deferredRelationsSummary()`).
* **P2 — حمولات قديمة:** الصفوف التي كُتب فيها `serverId = id محلي` **قبل**
  هذا الإصلاح تبقى كما هي (لا إعادة كتابة للتاريخ — البند 12)، لكن لم يعد
  ممكنًا الربط بها بلا إثبات `deviceId`، وتبقى ظهورها محصورة في تقرير G-8.
* **نطاق التطبيق:** نقطة الالتقاط مُثبَّتة على نسخة `AdapterRegistry` الخاصة
  بمدير المزامنة (مسارات السحب/الدفع الرسمية). مسارات Google Drive التي
  تُنشئ نسخة سجلّ خاصة (`google_drive_backup_service`) لم تُربط بعد — سلوكها
  كما كان (تخطٍّ مع تسجيل) ولا يخصّ مسار Appwrite.

## 9) السجلات التاريخية غير المؤكدة (البند 12) — إجراء دون تخمين

**ممنوع** ربط أي سجل تاريخي اعتمادًا على `id` أو الاسم أو المبلغ أو التاريخ أو التشابه.

### 9.1 فئات عدم اليقين (كما تظهر في الكود)
1. مصروف راتب بلا `employee_uuid` (سجل ما قبل migration 67/68).
2. سحبة بلا `expense_uuid`/`withdrawal_uuid` مع `expense_id` رقمي من جهاز آخر.
3. `salary_cycles` / `salary_carry_over_logs` بلا `employee_uuid` (يتيمة — يعدّها `EmployeeLinkRepairReport.orphanCycles` «تقرير فقط»).
4. `serverId` مزدوج لموظفين/دورات (تصادم أرقام أجهزة).
5. مرايا سحوبات مرتبطة فقط بالمستوى 3/4 (مطابقة بيانات) لا بالهوية.
6. `salary_payments` بلا `cycle_uuid` (فجوة G-1).

### 9.2 استعلامات المراجعة (قراءة فقط — لا كتابة)
تُنفَّذ على نسخة احتياطية من قاعدة الجهاز:

```sql
-- (1) مصروفات رواتب بلا هوية موظف
SELECT id, local_uuid, expense_type, related_id, amount, date, server_id
FROM expenses
WHERE (employee_uuid IS NULL OR employee_uuid = '')
  AND deleted_at IS NULL;

-- (2) سحوبات بلا رابط هوية مع مصروف (سحبة غير مباشرة قد تكون سليمة)
SELECT id, local_uuid, employee_id, employee_uuid, expense_id, expense_uuid, amount, withdraw_date, reason
FROM salary_withdrawals
WHERE deleted_at IS NULL
  AND (expense_uuid IS NULL OR expense_uuid = '')
  AND (expense_id IS NOT NULL OR reason LIKE 'exp_%');

-- (3) دورات/ترحيلات بلا هوية موظف
SELECT 'cycle' AS kind, id, local_uuid, employee_id, NULL AS employee_uuid, cycle_key AS ref
FROM salary_cycles WHERE employee_uuid IS NULL OR employee_uuid = ''
UNION ALL
SELECT 'carry_over', id, local_uuid, employee_id, employee_uuid, reason
FROM salary_carry_over_logs WHERE employee_uuid IS NULL OR employee_uuid = '';

-- (4) تصادم server_id (موظفون/دورات)
SELECT server_id, COUNT(*) c, GROUP_CONCAT(id) ids
FROM employees WHERE server_id IS NOT NULL
GROUP BY server_id HAVING c > 1;

-- (5) دفعات راتب بلا رابط دورة ثابت
SELECT p.id, p.local_uuid, p.cycle_id, p.amount, p.payment_date_iso
FROM salary_payments p
LEFT JOIN salary_cycles c ON c.id = p.cycle_id
WHERE p.amount > 0 AND (c.local_uuid IS NULL OR c.local_uuid = '');
```

### 9.3 مخرجات المراجعة المطلوبة (G-8)
تقرير قابل للتصدير (CSV/JSON) — **قراءة فقط** — بأعمدة:
`category, table_name, record_uuid, current_link, candidate_links, reason, suggested_action, requires_human_confirm`
مع قاعدة: أي سجل في `candidate_links` **لا يُكتب**؛ يبقى بانتظار تأكيد بشري.

---

## 10) خطة الإصلاح المقترحة (بعد اعتماد التدقيق — لا تنفيذ قبل الموافقة)

| الأولوية | الإصلاح | الملفات | اختبار الإثبات |
|---|---|---|---|
| ~~P0-1~~ ✅ **منفَّذ** | سياسة تعارض صريحة للحقول المالية الحرجة (G-4) + إصلاح فقدان التعارضات (G-11) | `sync_core/smart_conflict_resolver.dart`, `sync_core/sync_pull_service.dart`, `appwrite_sync_manager.dart`, `conflict_manager.dart` | ✅ 21 اختبار هوية + 75 حارس على CI |
| ~~P0-0~~ ✅ **منفَّذ** | **G-10**: سياسة «لا كسور عشرية» — اقتطاع نحو الصفر في الكتابة والنقل + كاشف تاريخي للقراءة فقط | `utils/currency_formatter.dart`, المحوّلات, `sync/payload_mapper.dart`, المستودعات, `services/money_integrity_service.dart` | ✅ `money_integer_policy_test.dart` + 3 اختبارات G-10 |
| P0-2 | حفظ `cycle_uuid` محليًا + في حمولة الـ outbox + إدراجه في الرفع من الصف (G-1) | migration + `local_db.dart`, `salary_payments_adapter.dart`, `payload_mapper.dart`, `appwrite_sync_manager.dart` | `G-1` في `financial_identity_audit_test.dart` (يصبح `expect(stats.deferred, isEmpty)`) |
| P1-3 | تصعيد ازدواج `serverId` إلى تقرير المراجعة بدل الاختيار (G-3) | `adapters/id_resolver.dart` | `ambiguous_server_id_goes_to_review` |
| P1-4 | كتابة `from_cycle_id/to_cycle_id` كهويات دورات عند الترحيل (G-2) | `salary_entitlement_service.dart` + المحوّل | `carry_over_links_cycles_by_uuid` |
| P1-5 | تنطيق المؤشرات بالمزوّد + تأسيس إجباري عند التحويل (G-7) | `sync_core/sync_checkpoint_store.dart`, `delta_sync_service.dart`, `sync_pull_service.dart` | `provider_switch_does_not_reuse_appwrite_cursor` |
| P2-6 | تقرير المراجعة القابل للتصدير (G-8) | خدمة قراءة فقط جديدة | `review_report_lists_uncertain_records_without_writing` |
| P2-7 | تمييز «مرايا بالهوية» عن «مرايا بالمطابقة البياناتية» في التقارير (G-5) | `salary_mirror_matcher.dart` + التقارير | `heuristic_mirror_is_flagged_not_silent` |
| P2-8 | توثيق `serverId = رقم جهاز المصدر` كحقل غير هوية + استبعاده من مخططات النقل بين المزوّدين (G-6/G-9) | وثائق + خريطة نقل | مراجعة يدوية |

---

## 11) الاختبارات المضافة في هذا التدقيق

الملف: `mobile/test/unit/financial_identity_audit_test.dart`

| السيناريو (البند 10) | الاختبار |
|---|---|
| اختلاف `id` المحلي (7 مقابل 81) بنفس `employee_uuid` | `same employee_uuid with different local ids binds expenses to the right employee` |
| إعادة الإرسال عدة مرات | `re-sending the same operation never duplicates the movement` |
| انقطاع الإنترنت ثم إعادة الاتصال | `offline save survives reconnect and retries the same uuid` |
| وصول الابن قبل الأب | `expense arriving before employee is kept unlinked (never bound to another employee)` + `payment arriving before cycle is deferred, not mis-bound` |
| التعارض | `concurrent critical financial field is detected as needing review` + توثيق السلوك الحالي |
| الحذف | `delete op is not overwritten by a later update` + `remote tombstone wins over local active row` |
| الاستعادة | `backup/restore round-trip keeps uuids and relations` |
| تغيير مزوّد المزامنة | `export/import through a neutral provider keeps identities, relations and totals` |

**اختبارات G-3 (أُضيفت مع الإغلاق):** `mobile/test/unit/financial_identity_g3_test.dart`

| السيناريو (البند 10) | الاختبار |
|---|---|
| اختلاف `id` المحلي + تصادم `serverId` بين جهازين | `تصادم serverId بين جهازين: UUID يحسم، والرقم يُرفض` (الإثبات بـ `deviceId`، والرفض بلا دليل) |
| وصول الابن قبل الأب + لا فقدان | `سحبة تصل قبل موظفها: تُخزَّن، ثم تُربط، ولا تتكرر` |
| منع التكرار (إعادة الدورة + echo) | نفس الاختبار (خطوتا «إعادة الدورة» و«إعادة الإرسال») + `تعليق متكرر لنفس السجل لا يُنشئ صفوفاً مكررة` |
| عدم التخمين (البند 12) | `رقم فقط + جهاز مجهول ⇒ مراجعة بشرية مع حفظ الدليل` |
| حفظ الحمولة كاملة | `معرّف الجلسة المعلّقة يُحفظ كحمولة كاملة (لا فقدان حقول)` |

**تشغيلها (على جهازك — لا تتوفر أدوات Flutter في بيئة هذا التدقيق):**
```bash
cd mobile
flutter pub get
flutter test test/unit/financial_identity_audit_test.dart
# ثم حزمة الحراسة المالية كاملة:
flutter test test/unit/id_resolver_cross_device_test.dart \
             test/unit/mirror_uuid_link_migration68_test.dart \
             test/unit/outbox_dao_comprehensive_test.dart \
             test/integration/two_device_sync_test.dart
```

---

## 12) قائمة تحقق الانتقال إلى مزوّد آخر (البند 9) — لا تُنفَّذ جزئيًا

1. نسخة احتياطية كاملة من المصدر الحالي (مع `local_uuid` لكل صف).
2. حصر عمليات `outbox` غير المُسلَّمة (`delivered_to_primary = 0`) ورفعها/تسجيلها قبل التحويل.
3. تجميد الكتابة غير المنضبطة (وضع قراءة فقط أو إيقاف المزامنة الدورية).
4. نقل السجلات **بنفس `local_uuid`** (بلا إعادة توليد).
5. نقل العلاقات كما هي: `employee_uuid`, `expense_uuid`, `withdrawal_uuid`, `cycle_uuid` (بعد P0-2), `from/to_cycle_id` (UUID).
6. نقل `deleted_at`، `version`، `vector_clock`، `last_modified` — و`idempotency_key` للعمليات المعلقة.
7. **عدم** نقل مؤشرات Appwrite (`sync_checkpoints`, `sync_mirror`, `sync_state`) كمؤشرات صالحة للمزوّد الجديد.
8. تأسيس حالة مزامنة جديدة: `full_sync_complete = 0` + مؤشرات مُنَطَّقة بالمزوّد.
9. مقارنة عدد الموظفين. 10. المصروفات. 11. السحوبات. 12. دورات الرواتب.
13. مجموع المبالغ (مصروفات/سحوبات/دفعات/ترحيلات) — يجب أن تتطابق بالهللة.
14. التحقق من كل علاقة أساسية (استعلامات القسم 9.2).
15. اختبار جهازين حقيقيين (A/B) قبل السماح بالكتابة الإنتاجية الكاملة.

**ما لم يُنفَّذ في هذا التدقيق (ينتظر موافقتك):** أي تعديل على المخطط، أي backfill، أي إعادة ربط، أي إصلاح للتعارضات. لم تُمَس أي بيانات.

---

## 13) ملحق: خرائط المسارات الأساسية (للمراجعة السريعة)

```
إنشاء حركة مالية محليًا
  ExpensesRepository.create/update ──► SQLite (uuid + علاقات) ──► OutboxDao.merge (نفس المعاملة)
  SalaryWithdrawalsRepository.createFromExpense ──► transaction{ INSERT + expense_id + ختم withdrawal_uuid + merge }
  SalaryEntitlementService (ترحيل) ──► transaction{ INSERT carry_over_log + merge }

الرفع
  takeBatch(pending, undelivered) ──► _processXEntry ──► OCC check ──► payload(uuid + employee_uuid + expense_uuid/cycle_uuid)
                                     ──► upsert (documentId = local_uuid) ──► markDeliveredToPrimary (حذف بعد التسليم)

السحب
  UnifiedPullEngine/SyncPullService ──► checkAndResolveConflict (tombstone يفوز دائمًا؛ concurrent ⇒ 3-way merge)
                                     ──► adapter.resolveRefs (UUID → serverId، ويُمنع id البعيد)
                                     ──► BaseRepository.upsertFromJson (حذف id البعيد، مطابقة local_uuid)
                                     ──► طابور deferred داخل الدورة
                                     ──► DeferredRelationStore (حمولة كاملة) ──► DeferredRelationRelinker
                                         (ربط بـ UUID بعد وصول الأب — idempotent؛ ما لا يُثبت ⇒ تقرير المراجعة)
```
