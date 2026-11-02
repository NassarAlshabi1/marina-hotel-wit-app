# مقارنة مزامنة Appwrite: الالتزام `b1d29fa` ← الالتزام الحالي `8dda3d7`

> **الفرع:** `refactor/performance-fixes-v2`
> **المقارنة:** `b1d29fac6410a77ff0bca5e53fdff8ad1972fed8` (2026‑10‑22، `fix(auth): honor explicit action permissions`)
> ← `8dda3d757b6295871f4cedcd5d735acefc7ae245` (2026‑11‑02، `chore: fix all analyzer issues (82) and verify full test suite green`)
> **المدى:** 32 التزاماً، 79 ملفاً، `+7116 / −1368` سطراً.
> **نطاق هذه الوثيقة:** push / pull / delta sync / full sync / التعارضات / checkpoint — أي ما يخصّ مزامنة Appwrite تحديداً.
> **ملاحظة منهجية:** لم يُشغَّل أي اختبار أو بناء؛ المقارنة مبنية على فرق الشجرة (`git diff`) وقراءة الكود في الطرفين.

---

## 0) ملخص تنفيذي (سبع نقاط تكفي)

1. **لم تتغيّر معمارية المزامنة**: نفس محرك السحب الموحّد (`UnifiedPullEngine`) ونفس `sync_checkpoints` لكل مجموعة، ونفس دلتا `$updatedAt` بنافذة أمان 5 دقائق، ونفس السحب الكامل القابل للاستئناف لليالي (`booking_nights`). التغيير كله في **دلالات الفشل** و**هوية الحقول المرفوعة** و**شفافية النتيجة**.
2. **أكبر إصلاح: عقد «لا يتقدّم المؤشر فوق الفشل»**. قبل: أي فشل تطبيق مستند كان يُبتلع بتحذير، فيتقدّم مؤشر المجموعة إلى أقصى `$updatedAt` للمستندات **المُحضَّرة** (لا المطبَّقة) → المستند يخرج من كل دلتا لاحقة **إلى الأبد** (فقدان صامت). بعد: تأجيل ثم رمي `StateError` → المجموعة تُسجَّل في `failedCollections` → لا `commit` → إعادة محاولة في الدورة التالية.
3. **تشمل الحماية الآن 13 من 23 دالة تطبيق** (rooms, bookings, employees, payments, debts, salary_cycles, salary_payments, salary_withdrawals, salary_carry_over_logs, booking_notes, booking_nights, inventory_transactions, booking_price_adjustments). **10 ما زالت تبتلع الفشل** (أهمها `expenses` و`cash_transactions` و`guest_infos`).
4. **إزالة معرفات FK الرقمية المحلية من الرفع ومن حساب التعارض**: `relatedId` / `cashTransactionId` / `employeeId` / `expenseId` / `bookingId` / `cycleId` لم تعد تُرفع ولا تُقارن ولا تُدمج — بديلها أعمدة `*Uuid`. هذا يقتل «ping‑pong» تعارضات المصروفات ومصروفات الرواتب، ويمنع إعادة تطبيق سجلات لم تتغير فعلاً في كل دورة.
5. **الدفع الشامل صار شاملاً فعلاً**: `pushAllLocalData()` كان يفرّغ الـ Outbox فقط؛ الآن يرفع كل سجلات الأعمال، وأُضيفت 6 مجموعات كانت لا تُرفع أبداً (blacklist, price_adjustments, payment_voids, inventory_items, inventory_transactions, audit_logs).
6. **«النجاح الكاذب» انتهى**: `SyncResult` يحمل `failedCollections` وحالة `partial`، وزر السحب يعرض محجوب/جزئي/نجاح بصدق ويسجّل الحالة الفعلية في `sync_logs`.
7. **تغيير خطر غير محروس**: الانتقال إلى مشروع Appwrite جديد (`6a4408f3` → `6ae118bc`) في 2026‑10‑31 تم بتغيير إعدادات فقط، **بلا تصفير لمؤشرات `sync_checkpoints`** (`resetAll()` بلا أي مستدعٍ في الإنتاج). راجع القسم 9.

---

## 1) ما لم يتغيّر (خط الأساس المشترك بين الالتزامين)

| البند | الوضع في الطرفين |
|---|---|
| الدفع (push) | Outbox هو مصدر الحقيقة: `_pushAllEntities` + `_process{Room,Booking,Expense,Payment,Debt,GuestInfo,SalaryWithdrawal}Entry`، مع فحص OCC (`_occCheckAndMerge`) قبل الكتابة، ونشر tombstones، وdebounce، وحجم دفعات متكيّف. |
| السحب (pull) | مسار واحد: `sync(pull: true)` و`pullRemoteChanges()` كلاهما عبر `_unifiedPull.run(_buildPullTasks())`. |
| نطاق السحب | 23 مهمة بنفس الترتيب الآمن للـ FK: `rooms → employees → inventory_items → inventory_transactions → bookings → cash_transactions → expenses → booking_nights → booking_notes → payments → debts → salary_cycles → salary_payments → salary_withdrawals → guest_infos → booking_price_adjustments → shift_notes → blacklist → price_adjustments → audit_logs → payment_voids → salary_carry_over_logs` (+`app_settings` اختيارية وغير حرجة). **لم تُضف/تُحذف أي مجموعة في هذه الفترة.** |
| Delta vs Full | لكل مجموعة: `full_sync_complete == 0 أو sinceTs <= 0` ⇒ Full، وإلا Delta. الدلتا = `Query.greaterThan('$updatedAt', cutoffISO)` حيث `cutoff = lastPullTs − 300 ثانية` (نافذة أمان). |
| Full | كلاسيكي أحادي الطلب لمعظم المجموعات؛ لـ`booking_nights` سحب تدفّقي قابل للاستئناف: صفحة 100 → تطبيق → `cursor = docs.last.$id` → الصفحة التالية، وسقف أمان 5000 صفحة. |
| تثبيت المؤشر | `commit(collection, maxUpdatedAtSec: max($updatedAt))` **بعد** نجاح `apply` فقط — والاستثناء يمنع `commit`. |
| التعارضات | `ConflictDetector` + `SmartConflictResolver` (3‑way مع `AncestorCacheDao`) + `vectorClock` + أسبقية tombstone البعيد + حماية الحذف المحلي. |
| بوّابة السحب | `OutboxPullPolicy`: لا سحب فوق تغييرات محلية غير مُسلَّمة. |

**الخلاصة:** الشكل العام واحد؛ ما تغيّر هو **ماذا يحدث عند فشل مستند**، و**أي حقول تُرفع/تُقارن**، و**ماذا يرى المستخدم**.

---

## 2) جدول الفروق المختصر

| المحور | `b1d29fa` (قبل) | `8dda3d7` (بعد) | الأثر |
|---|---|---|---|
| فشل تطبيق مستند في السحب | `_logger.warning` ثم متابعة | تأجيل (FK/NOT NULL) + إعادة محاولة + `StateError` بعد بقاء فشل | لا يتقدّم المؤشر، لا فقدان صامت |
| `upsertFromJson` يعيد `-1` (أب غير محلول) | يُتجاهل تماماً | تأجيل ثم فشل صريح | لا يمرّ «نجاح» كاذب |
| `_syncEmployeesWithRetry` بعد استنفاد المحاولات | يعيد `lastCount` مبتلعاً | يعيد رمي الخطأ | مؤشر employees لا يتقدّم فوق موظف مفقود |
| نتيجة المزامنة | `success/failed/idle` فقط | + `partial` + `failedCollections` + `hasPullFailures` | تشخيص حقيقي |
| زر السحب في اللوحة | «✅ تم السحب بنجاح» دائماً | محجوب / جزئي / نجاح — وسجل `sync_logs` مطابق | لا نجاح كاذب |
| حقول الهوية المرفوعة | `relatedId`, `cashTransactionId`, `employeeId`, `expenseId` رقمية | أُزيلت — `*Uuid` فقط | لا تشويه للمستند السحابي |
| `employeeUuid` للمصروفات | مسار outbox فقط | دالة موحّدة للمسارين + اشتقاق طازج من `relatedId` | لا مصروفات رواتب يتيمة |
| حساب «الحقول المتغيّرة» في التعارض | يشمل FK الرقمية | يستثنيها (`_deviceLocalIdFields`) | نهاية ping‑pong |
| مقارنة المحتوى في السحب | تشمل FK الرقمية | يستثنيها أيضاً | لا إعادة تطبيق/إشعارات مكررة |
| دمج بلا تغيير فعلي | `version+1` وإعادة رفع | `localWins` بلا رفع | لا وقود دوراني |
| `pushAllLocalData()` | `pushLocalChanges()` (Outbox فقط) | رفع شامل لكل سجلات الأعمال | إغلاق «سجلات محلية لم تُرفع أبداً» |
| مشروع/قاعدة Appwrite | `6a4408f3… / 6a4409b5…` | `6ae118bc… / 6ae119d7…` | ترحيل 8,708 سجلاً (2026‑10‑31) |
| `guest_infos.entryDate` | غير موجود في المخطط/الرفع | عمود + دلتا + backfill | تاريخ دخول الضيف يعبر الأجهزة |
| نسخة Appwrite الاحتياطية | مجلد التطبيق، v1.0 | تخزين خارجي، v1.1 | تبقى بعد إلغاء التثبيت |
| رفع D1 | `ON CONFLICT DO NOTHING` فقط | + خيار `overwrite` (`DO UPDATE`) | تحديث فوق القديم عند الطلب |

أرقام الملفات الأكثر صلة:

```
mobile/lib/services/appwrite_sync_manager.dart        +859 / −173
mobile/lib/services/comprehensive_appwrite_backup_service.dart +140 / −8
mobile/lib/widgets/dashboard_sync_button.dart         +104 / −27
mobile/lib/services/sync_core/conflict_detector.dart   +40 / −0
mobile/lib/services/sync_core/sync_pull_service.dart   +17 / −0
mobile/lib/services/sync_core/smart_conflict_resolver.dart +13 / −0
mobile/lib/services/sync/payload_mapper.dart           +18 / −4
mobile/lib/services/appwrite_config.dart                 +8 / −4
```

---

## 3) الدفع (Push) — ما تغيّر فعلياً

### 3.1 إزالة المعرفات الرقمية من الحمولة
`payload_mapper.dart`:

* `expenseToRemote`: أُزيل `relatedId` و`cashTransactionId`.
* `salaryWithdrawalToRemote`: أُزيل `employeeId` و`expenseId` (وبقي `employeeUuid` / `employeeLocalUuid` / `expenseUuid`).
* السبب الموثّق في الكود: هذه أعمدة `autoincrement` محلية، تعني شيئاً مختلفاً على كل جهاز، ورفعها كان يشوّه المستند السحابي ويغذّي الدمج الدوراني.

> ⚠️ أثر توافقي: أي مستهلك سحابي (تقارير، سكربتات، تطبيق ويب) كان يقرأ `relatedId`/`employeeId` من مستندات Appwrite لن يجدها بعد الآن. الاعتماد يجب أن يكون على `employeeUuid` / `expenseUuid` / `cashFlowUuid` / `categoryUuid`.

### 3.2 توحيد إثراء `employeeUuid` للمصروفات
دالة جديدة `_expenseToRemoteWithEmployeeLink` تُستخدم في **مسارَي** الرفع (Outbox + الرفع الشامل):
اشتقاق طازج من `relatedId` الحالي عند توفّر صف الموظف محلياً، وإبقاء قيمة العمود كما هي عند تعذّر الحل (لا إسقاط رابط صالح).

قبل: المسار الشامل كان يرفع قيمة العمود فقط ⇒ صفوف قديمة (عمود فارغ) تُرفع بلا رابط ⇒ يتيمة على الأجهزة الأخرى لا يمكن لـ`_relinkOrphanSalaryExpenses` ربطها (لا UUID)؛ وصفوف متقادمة تُرفع برابط خاطئ.

### 3.3 `pushAllLocalData()` صار رفعاً شاملاً حقيقياً
قبل:
```dart
Future<void> pushAllLocalData() async { await pushLocalChanges(); } // Outbox فقط
```
بعد:
```dart
Future<Map<String, int>> pushAllLocalData() =>
    pushAllLocalDataToAppwrite(skipDeleted: false);
```
وأُضيفت إلى `pushAllLocalDataToAppwrite`: `blacklist`, `price_adjustments`, `payment_voids`, `inventory_items`, `inventory_transactions`, `audit_logs` — مع ترتيب يحترم الآباء (أصناف المخزون قبل حركاته، سجلات التدقيق أخيراً). كذلك `salary_carry_over_logs` صار يحترم `skipDeleted`.

### 3.4 ما لم يتغيّر في الدفع
الـ Outbox، وOCC، ونشر tombstones، وdebounce، وإعادة المحاولة — كلها كما هي. أي أن **مسار «الرفع السريع» لم يُلمس منطقياً** عدا الحمولات أعلاه.

---

## 4) السحب (Pull) — قلب التغيير

### 4.1 المشكلة قبل الإصلاح (ثلاثة مسارات فقدان صامت)
الموثّق في تعليقات الكود واختبارات الانحدار:

* **(A)** استثناء تطبيق مستند يُبتلع بتحذير داخل حلقة المستندات ⇒ `apply` تعود «ناجحة» ⇒ `commit` يثبّت المؤشر على `max($updatedAt)` **للمستندات المُحضَّرة**، والمستند الفاشل يفلت من كل دلتا لاحقة (`$updatedAt < المؤشر`) إلى الأبد.
* **(B)** `BaseRepository.shouldSkip` يعيد `-1` عند تعذّر حل الأب (`FK`) وكانت دوال السحب **تتجاهل قيمة الإرجاع** ⇒ لا استثناء أصلاً، فقط «نجاح» صامت ومؤشر يتقدّم فوق المستند.
* **(C)** يتيم الموظف في `salary_cycles` كان يُتخطّى بـ`continue` — بلا طابور يتامى دائم (بعكس `salary_withdrawals`).

### 4.2 الحل بعد الإصلاح
لكل مجموعة مغطّاة:

```
مرحلة 1: لكل مستند
  - فشل FK / NOT NULL  →  deferred  (ليس فشلاً)
  - فشل آخر / -1       →  failed
مرحلة 2: إعادة محاولة deferred بعد اكتمال الدفعة (ربما وصل الأب ضمن نفس الدفعة)
  - نجاح → processed++
  - بقاء فشل / -1 → failed
بعد الحلقة: failed غير فارغة ⇒ throw StateError('... checkpoint must not advance ...')
```

وأثر الرمي:
`UnifiedPullEngine.run` يلتقطه ⇒ إن كانت المهمة `critical` تُضاف إلى `PullRunResult.failedCollections` ⇒ **لا `commit` لهذه المجموعة** ⇒ `sinceTs` يبقى كما هو ⇒ الدورة التالية تعيد سحب نفس النطاق (upsert idempotent) حتى يُشفى السبب.
وبقية المهام تواصل العمل (فشل مهمة لا يوقف الدورة).

### 4.3 تغطية العقد الآن

| مغطّى (يرمي) | ما زال يبتلع الفشل |
|---|---|
| rooms | expenses |
| bookings | cash_transactions |
| employees (+`_syncEmployeesWithRetry` يعيد الرمي) | guest_infos |
| payments | shift_notes |
| debts | blacklist |
| salary_cycles | price_adjustments |
| salary_payments | audit_logs |
| salary_withdrawals (عدا طابور اليتامى الدائم المقصود) | payment_voids |
| salary_carry_over_logs | inventory_items |
| booking_notes | app_settings (غير حرجة أساساً) |
| booking_nights + صفوف fallback داخل `db.batch` | |
| inventory_transactions | |
| booking_price_adjustments | |

**13 مغطاة / 10 غير مغطاة.** ملاحظة مهمة: `expenses` — وهي مركز شكوى «التعارضات» — عولجت فقط من جهة **التعارض والحمولة**، لا من جهة **الفشل عند التطبيق**؛ فشل تطبيق مصروف ما زال يتقدّم بالمؤشر فوقه.

### 4.4 تفاصيل إضافية في السحب
* `_isRemoteDataNewer` / `checkAndResolveConflict` كما هو (لم يُلمس) — لكن قائمة الحقول المستثناة في مقارنة المحتوى (`SyncPullService._contentEquals`) توسّعت لتشمل FK الرقمية، فلا يُعاد تطبيق سجل «لم يتغيّر فعلاً» ولا تُطلق إشعارات تغيير مكررة.
* مقارنة المحتوى تبقى محصّنة ضد تغيير القيم مع تطابق `vectorClock` (كما كانت).
* `booking_nights`: لم يتغيّر منطق الاستئناف (نفس الصفحة/المؤشر/الحد الأقصى 5000 صفحة)، لكن **صف الـ fallback الفاشل داخل دفعة `db.batch`** كان يُسجَّل كتحذير فقط؛ الآن يُضاف إلى `failed` (مع تسمية uuid الصف في السجل) فلا يتقدّم مؤشر الليالي فوقه.

### 4.5 التكلفة الجديدة (Side Effect مهم)
عندما يفشل مستند **فشلاً دائماً** (بيانات تالفة، أب مفقود لا يصل أبداً)، يصبح مؤشر المجموعة **محجوباً**:
* كل دورة تعيد سحب نفس نافذة الدلتا من آخر مؤشر ناجح، ويتضخّم النطاق تدريجياً؛
* سجل الأخطاء يتكرّر كل دورة؛
* المجموعة تبقى `partial` في كل مزامنة (لن تُعلَن success).

هذا **مقصود** (فشل مرئي أفضل من فقدان صامت)، لكنه بلا صمام: لا عدّاد محاولات ولا طابور dead‑letter ولا تصفير للمؤشر بعد N فشل. راجع التوصيات.

---

## 5) التعارضات و«ping‑pong» المصروفات ومصروفات الرواتب

ثلاث طبقات مترابطة:

1. **`ConflictDetector._deviceLocalIdFields`** — تُستثنى من حساب «الحقول المتغيّرة»:
   `id, relatedId, related_id, cashTransactionId, cash_transaction_id, employeeId, employee_id, expenseId, expense_id, bookingId, booking_id, cycleId, cycle_id`.
   قبل: كل دمج 3‑way يرى هذه الحقول «متغيّرة» (لأن قيمها تختلف حتماً بين جهازين) ⇒ `version+1` ورفع ⇒ الجهاز الآخر يدمج ويرفع معرّفاته ⇒ دورة لا تنتهي.
2. **`SyncPullService._contentEquals`** — نفس الاستثناءات في مقارنة المحتوى ⇒ لا إعادة تطبيق ولا إشعارات لكل سجل في كل دورة.
3. **`SmartConflictResolver`** — درع إضافي: إذا كانت `localChangedFields` و`remoteChangedFields` فارغتين معاً (تعارض «متزامن» بلا تغيير حقيقي) ⇒ `localWins` بلا رفع.

> ملاحظة: `serverId` / `serverBookingId` **لم** تُستثنَ — فهي معرفات سحابية ذات معنى عبر الأجهزة (موثّق في الكود).

---

## 6) سطح المراقبة والواجهة

* `SyncResult` أصبح: `failedCollections: List<String>` + `hasPullFailures`.
* `synced` يتحوّل إلى `SyncStatus.partial` عند وجود `failedCollections` (بدل `success`).
* `sync_logs`: حالة `blocked` / `partial` / `success` + رسالة الخطأ/المجموعات الفاشلة.
* زر السحب في اللوحة: ثلاث حالات بصرية (برتقالي محجوب مع «رفع الآن» / برتقالي جزئي بأسماء المجموعات / أخضر نجاح).
* `lastPullTs` القديم (جدول SyncState) و`markFullSyncComplete` لا يُحدَّثان إلا عند خلوّ `failedCollections` — كان كذلك سابقاً، لكنه الآن **فعّال فعلاً** بعد أن صارت `failedCollections` تُملأ.

**أثر رجعي على المستهلكين:** أي كود/شاشة تعتبر `status == success` مرادفاً لـ«كل البيانات وصلت» صار يحصل على `partial` أكثر مما قبل. يجب فحص مستهلكي `SyncResult` خارج زر اللوحة (مزامنة تلقائية عند الفتح، المؤقتات، شريط الحالة).

---

## 7) خارج نطاق المزامنة لكنه تغيّر معها

| البند | التغيير |
|---|---|
| نسخة Appwrite الاحتياطية (`comprehensive_appwrite_backup_service`) | تُحفظ الآن في `/storage/emulated/0/Documents/MarinaHotelBackups/Appwrite` مع طلب `MANAGE_EXTERNAL_STORAGE` والتراجع الآمن لمجلد التطبيق؛ نسخة الملف `1.1`؛ الرسائل تبيّن مكان الحفظ. |
| تصدير CSV | خدمة جديدة `appwrite_csv_export_service` + بطاقة في شاشة إعدادات Appwrite، قراءة فقط، UTF‑8 مع BOM، اختيار مجلد الحفظ. |
| رفع Cloudflare D1 | خيار `overwrite` (`ON CONFLICT DO UPDATE`) مع إبقاء `id` خارج `SET`؛ الافتراضي ما زال `DO NOTHING`. لا علاقة له بـOutbox/Appwrite. |
| `guest_infos.entryDate` | عمود محلي (`local_db` + migration)، رفع `entryDate` في `PayloadMapper`، قراءة في `guest_infos_adapter` (مفتاح بديل `entry_date`)، حفاظ المستودع على القيمة عند التحرير، شاشة + خدمة backfill للسحابة، وسكربت مخطط `scripts/appwrite/add_guest_entrydate_attribute.py` (attribute نصي اختياري، حجم 10). |

---

## 8) مخاطر ترحيل المشروع (أهم فجوة تشغيلية)

* 2026‑10‑31 (`3b508e1cc`): `AppwriteConfig.projectId` من `6a4408f300217885fd7b` إلى `6ae118bc00263ddb1cd5`، و`databaseId` من `6a4409b50019dd39dde5` إلى `6ae119d7001046bbdb3e`.
* `SyncCheckpointStore` يخزّن `last_pull_ts` و`full_sync_complete` في جدول SQLite محلي **بلا أي بُعد خاص بالمشروع/القاعدة**.
* `resetAll()` موجود لكن **لا مستدعٍ له في `mobile/lib`** (بحث شامل)؛ لا شاشة «إعادة مزامنة كاملة»، ولا كشف لتغيّر `projectId` عند `reinitializeAfterConfigChange`.

**النتيجة المحتملة:** جهاز كان مؤشره `last_pull_ts = T` على المشروع القديم، ثم انتقل للمشروع الجديد: أي مستند في المشروع الجديد له `$updatedAt < T` **لن يُسحب أبداً** (المجموعة معلَّمة `full_sync_complete = 1` فلا Full). عملياً مستندات الترحيل أُنشئت في 2026‑10‑31 فمعظمها أحدث من المؤشرات، لكن هذا **حظّ توقيت لا ضمان**، ويصبح مؤكداً لأي قاعدة/مشروع يُرحَّل لاحقاً بلا إعادة كتابة `$updatedAt`.

**توصية P0:** تخزين `projectId` + `databaseId` في `sync_checkpoints` (أو prefs) ومقارنتهما في `initialize()`؛ عند الاختلاف ⇒ `resetAll()` + إشعار «سحب كامل». وإضافة زر صريح «إعادة مزامنة كاملة» في شاشة المزامنة.

---

## 9) فجوات وتوصيات مرتبة

### P0
1. **حرس تغيير المشروع/القاعدة** (القسم 8) — وإلا فسحب ناقص صامت بعد كل ترحيل.
2. **صمام للمؤشر المحجوب**: عمود `failed_cycles` في `sync_checkpoints`؛ بعد N دورات (مثلاً 5) لمجموعة فاشلة: تصفير مؤشرها (`reset`) + إشعار، أو نقل المستند إلى dead‑letter مع إبقاء التقدم. بدون هذا، مجموعة واحدة تالفة تُبقي التطبيق `partial` للأبد وتضخّم قراءات Appwrite.

### P1
3. **تعميم العقد على الـ10 المتبقية** — الأولوية: `expenses` ثم `cash_transactions` ثم `guest_infos`. `expenses` تحديداً: الإصلاح الحالي لا يمنع فقدان مصروف فشل تطبيقه.
4. **فحص مستهلكي `SyncStatus.partial`** (مزامنة الفتح التلقائي، المؤقتات، شريط الحالة) للتأكد من عدم وجود منطق يتعامل مع `partial` كـ`success` أو كـ`failed` بلا تمييز.
5. **إصلاح افتراضي سكربت المخطط**: `scripts/appwrite/add_guest_entrydate_attribute.py` يستخدم افتراضياً المشروع **القديم** `6a4408f300217885fd7b` والقاعدة القديمة؛ تشغيله بلا متغيّرات بيئة يضيف العمود في المشروع الخطأ (بينما التطبيق على `6ae118bc`).

### P2
6. **توحيد قائمة الحقول المحلية**: `_deviceLocalIdFields` مكرّرة الآن في `ConflictDetector` و`SyncPullService` (وحمولة الرفع في `PayloadMapper`) — استخراجها إلى ثابت واحد يمنع انحرافها مستقبلاً (مصدر خطأ صامت كلاسيكي).
7. **`SyncCheckpointStore` غير موثّق في دليل المخطط**: جدول يُنشأ بـSQL خام (`_ensureTable`) خارج drift — يستحق توثيقاً في `docs/` كي لا يُحذف سهواً في تنظيف الجداول.
8. **تنظيف تعليقات**: معظم تعليقات الإصلاح مؤرخة **2026‑11‑03** داخل التزامات 2026‑11‑02 (فرق منطقة زمنية/صياغة) — لا أثر وظيفي، لكنه يشوّش التأريخ.
9. **`appwrite/appwrite.json`** يحمل `projectId = 690ff0da0025518570c1` (مشروع ثالث!) ولم يُحدَّث في هذه الفترة — يجب تحديثه أو حذفه لتفادي لبس عند `npm run appwrite:*`.

---

## 10) الاختبارات المرتبطة (مضاف/معدّل)

| ملف | الدور |
|---|---|
| `mobile/test/unit/bookings_pull_checkpoint_regression_test.dart` (جديد، 231 سطراً) | درع انحدار: فشل تطبيق حجز لا يتخطاه المؤشر |
| `mobile/test/unit/silent_loss_checkpoint_regression_test.dart` (جديد، 326 سطراً) | تعميم العقد: `booking_notes` (مسار `-1`) و`salary_cycles` (يتيم) + الشفاء الذاتي |
| `mobile/test/unit/expenses_device_local_ids_conflict_test.dart` (جديد، 697 سطراً) | إزالة FK الرقمية من الحمولة + إثراء `employeeUuid` + غياب ping‑pong |
| `mobile/test/services/appwrite_csv_export_test.dart` (جديد) | تصدير CSV (UTF‑8 BOM على مستوى البايت) |
| `mobile/test/unit/guest_entry_date_backfill_service_test.dart` (جديد) | backfill `entryDate` |
| `mobile/test/unit/resumable_full_sync_test.dart` (معدّل طفيف) | الاستئناف كما هو |
| `mobile/test/unit/pull_commit_visibility_test.dart` (معدّل طفيف) | رؤية الـcommit بعد السحب |
| `mobile/test/unit/sync_safety_wave4_cleanup_tombstone_test.dart`, `guest_infos_*`, `mirror_uuid_link_migration68_test.dart` … | تحديثات توافقية (تنسيق/تواقيع) |

لم يتغيّر سلوك محرك السحب نفسه (`unified_pull_engine.dart` و`sync_checkpoint_store.dart` **غير معدّلين** بين الالتزامين) — لذلك اختبارات delta/full القائمة بقيت صالحة.

---

## 11) كيف تتحقق بنفسك

```bash
# 1) نطاق المقارنة
git diff --stat b1d29fa 8dda3d7

# 2) ملفات المزامنة فقط
git diff b1d29fa 8dda3d7 -- \
  mobile/lib/services/appwrite_sync_manager.dart \
  mobile/lib/services/sync_core mobile/lib/services/sync \
  mobile/lib/services/comprehensive_appwrite_backup_service.dart

# 3) حصر عقد «لا يتقدّم المؤشر» ودواله
grep -n "checkpoint must not advance" mobile/lib/services/appwrite_sync_manager.dart

# 4) الكيانات التي ما زالت تبتلع الفشل
grep -n "Failed to sync" mobile/lib/services/appwrite_sync_manager.dart

# 5) اختبارات الانحدار
cd mobile && flutter test test/unit/bookings_pull_checkpoint_regression_test.dart \
  test/unit/silent_loss_checkpoint_regression_test.dart \
  test/unit/expenses_device_local_ids_conflict_test.dart \
  test/unit/resumable_full_sync_test.dart
```

---

## 12) خلاصة منصفة

* **ما تحسّن جوهرياً:** الفقدان الصامت في السحب (13 كياناً)، تشخيص المستخدم، هوية السجلات عبر الأجهزة، شمول الرفع، ونهاية دورة تعارضات المصروفات/الرواتب.
* **ما بقي مفتوحاً:** 10 كيانات بلا عقد الفشل (أهمها `expenses`)، غياب صمام للمؤشر المحجوب، وغياب حرس تغيير المشروع/القاعدة — وهو الأخطر لأن أثره «سحب ناقص صامت» شبيه بالمرض الذي عالجه هذا المدى.
* **لا تغيير** في تصميم delta/full أو تنسيق `sync_checkpoints` — أي أن أي خلل بنيوي في هذه الطبقة (لو وُجد) لا يعالجه هذا المدى.
