# مراجعة فرع Flutter المرجعي `feat/cloudflare-sync-execution`

**تاريخ المراجعة:** 2026-10-06 (وقت الجلسة).
**المراجَع:** `origin/feat/cloudflare-sync-execution` @ **`ac283c6c`** — «Merge pull
request #613»، وهو نفس الرأس الذي بُنيت عليه كل مقارنات هذه الجلسة.
**الغرض:** تدقيق محرك سحب التغييرات في التطبيق المرجعي، وتحديد ما يجب أن يطابقه
تطبيق أندرويد، مع فصل **ما تحقّق فعلاً** عمّا لم يُتحقق.

## 0) منهج المراجعة وحدوده

- قراءة ساكنة كاملة للمسار المرجعي + `git grep` على كامل `mobile/lib` — لا تشغيل
  لـFlutter ولا بناء له (لا toolchain في بيئة الجلسة، والفرع لا يُبنى هنا إطلاقاً).
- كل ادعاء في هذا التقرير مسنود بمرجع `ملف:سطر` من الفرع نفسه، وكل مقارنة
  بأندرويد مسنودة باختبار أو تشغيل CI على فرع الجلسة.
- **ما لم يُتحقق:** سلوك على جهاز حقيقي، وبناء Flutter، وتشغيل اختبارات الفرع.

## 1) خريطة المسار المرجعي (ما يفعله الفرع فعلاً)

| المكوّن | الملف (الفرع) | الدور |
| --- | --- | --- |
| المنسّق | `mobile/lib/services/cloudflare_sync_manager.dart` (4,324 سطراً) | دورة السحب الكاملة: المؤشر، الدلتا، الرفع، epoch، المسح، الحراس |
| الحجر وسجل الانتظار | `mobile/lib/services/sync/pull_quarantine.dart` | تصنيف الصفوف غير القابلة للتطبيق إلى «انتظار» ثم «حجر»، وإعادة الحل من الحمولة |
| المحوّلات (21) | `mobile/lib/services/adapters/*.dart` | تعيين أسماء الحقول + بدائل لكل حقل (`fallback:`) + ترجمة المفاتيح |
| سياسة السحب مع outbox | `mobile/lib/services/sync/outbox_pull_policy.dart` | **كود ميت** — انظر النتيجة F1 |
| الـRealtime | `mobile/lib/services/cloudflare_realtime_sync.dart` | WebSocket إلى غرفة التزامن: debounce، cooldown، backoff، إعادة تسليح، heartbeat |
| الحارس | `mobile/lib/services/sync_guardian.dart` | مراقب رفع كل 5 دقائق + ضمانات الخلفية |
| الـWorker | `worker/src/{database,sync,index,sync-lock}.ts` | `pullChanges` / `handlePull` / حارس التزامن |

### ثوابت مُتحقَّق منها حرفياً

| الثابت | الفرع المرجعي | أندرويد عندنا |
| --- | --- | --- |
| debounce الحدث | 500ms — `cloudflare_realtime_sync.dart:150` | `REALTIME_DEBOUNCE_MS = 500` |
| تهدئة السحب | 15s — `:151` | `REALTIME_PULL_COOLDOWN_MS = 15_000` |
| تدرّج إعادة الاتصال | 1s..60s — `:152-153` | `1s shl n` بسقف `60_000` |
| محاولات الاتصال | 6 — `:156` | `REALTIME_MAX_RECONNECT_ATTEMPTS = 6` |
| إعادة التسليح | دقيقتان — `:161` | `REALTIME_REARM_INTERVAL_MS = 120_000` |
| نبضة | 30s — `:165` | `REALTIME_HEARTBEAT_MS = 30_000` |
| مهلة الاتصال | 15s — `:170` | `REALTIME_CONNECT_TIMEOUT_MS = 15_000` |
| مراقب الرفع | 5 دقائق — `sync_guardian.dart:180` | `PENDING_PUSH_MONITOR_MS = 5min` |
| عتبة الانتقال للحجر | 3 دورات — `pull_quarantine.dart:46` | لا طبقتين عندنا (انظر F3) |
| سقف سجل الانتظار | 300 — `:63` | — |
| سقف الحجر | 300 — `:69` | `PULL_QUARANTINE_CAP = 300` |
| سقف الشفاء/دورة | 100 — `:73` | `PULL_QUARANTINE_HEAL_LIMIT = 100` |

### نطاق السحب: الـ21 محوّلاً + 3 كيانات بمسار خاص

- الفرع: 21 محوّلاً في `adapter_registry.dart` (`inventory_adapter.dart` يضم
  محوّلَين: `inventory_items` و`inventory_transactions`)، لكن نطاق المزامنة
  عنده 24 كياناً مثلنا — `ENTITY_TABLES` في `worker/src/database.ts` **متطابقة
  حرفياً** في الفرعين (مقارنة آلية في هذه المراجعة).
- الكيانات الثلاثة بلا محوّل (`app_users`, `devices`, `blacklist`) تعالجها
  `cloudflare_sync_manager.dart` بمسارات خاصة: أعمدة `devices` تُبنى يدوياً
  (`_devicesPayload` l.938-1015)، و`blacklist` يُحوَّل إلى صفوف `shift_notes`
  موسومة `created_by='blacklist'` (l.2907-2913, 3453, 3602) لأنه «كيان سحابي
  بلا جدول محلي» عنده، و`app_users` عبر مسار `auth_local_store`.
- عندنا: 24 كياناً في `SyncIngestorRegistry.SYNC_ENTITY_TABLES`، ولكلٍّ جدول
  Room حقيقي — بما فيها `blacklist` → جدول `blacklist_entries` المستقل
  (لا حاجة لحيلة الوسم في `shift_notes`). أي أن أندرويد أوسع تغطيةً بنيوياً،
  والسلوك على السلك موحّد لأن اسم الكيان `blacklist` هو نفسه في الجانبين.
- افتراضيات `blacklist` عندنا من مُنشئ Room: `reported_by="police"`,
  `active=true` (لا يوجد حقل `status` في هذا الكيان) — مُثبتة في
  `SyncWireFields.entityDefaults`.

## 2) مصفوفة التكافؤ (ما حقّقناه بالدليل)

| البند | الفرع المرجعي | أندرويد (فرع الجلسة) | الدليل |
| --- | --- | --- | --- |
| تقدّم المؤشر مع صف غير قابل للتطبيق | يتقدم — `pull_quarantine.dart` (سياسة 2026-09-15) | يتقدم | `SyncWireFieldParityTest.unappliableRowDoesNotFreezeDeltaCursorAndIsCountedOnce` + `SyncIngestorRegistryTest.quarantinedPullAdvancesSavedCursorAndStaysRecoverable` |
| إعادة الحل من الحمولة المحفوظة | `collectHealCandidates()` — `:223` | `healQuarantinedBatch(100)` كل دورة | `quarantineHealsFromStoredPayloadOnceTheCauseDisappears` |
| سقف الحجر الأقدم-أولاً | `evictQuarantineOverflow()` — `:344` | `enforceQuarantineCap()` | `quarantineCapEvictsOldestRecords` |
| بدائل الحقول عند الغياب | `?? fallback` في المحوّلات | `SyncWireFields.entityDefaults` + درع الأعلام | `SyncWireFieldParityTest` (5 حالات حقول) |
| أسماء الحقول المخالفة | `quantity`/`movement_type`/`guest_*` | خرائط الاتجاهين في `SyncWireFields` | نفس الملف أعلاه |
| مسح الحذفيات مرة واحدة | `_sweepHistoricalTombstones` | `sweepHistoricalTombstones` | `SyncPullParityTest` (12 حالة) |
| حراس المؤشر المسموم | 3 طبقات | 3 طبقات | `SyncPullParityTest` + `PullSanityPolicyTest` |
| Realtime/الحراس الزمنية | الثوابت أعلاه | مطابقة حرفياً | `RealtimePolicyTest`, `RemoteSignalPolicyTest` |

**نتيجة CI المرجعية لنا:** `:app:testDebugUnitTest` = **372 حالة، 0 فشل، 0 خطأ**،
و`worker` (vitest + typecheck) أخضر — التشغيل `37539770608` على `899753cc`.

## 3) النتائج (Findings)

### F1 — `OutboxPullPolicy` كود ميت في الفرع، وسياسة أندرويد كانت تحجب السحب — **أُصلح**

- الفرع يعرّف `OutboxPullPolicy.canPull(...)` («لا سحب ما دام هناك غير مُسلَّم»)
  لكن **لا مستدعي له إطلاقاً** في `mobile/lib`: نتيجة
  `git grep -n "OutboxPullPolicy" origin/feat/cloudflare-sync-execution -- mobile/lib`
  = ملف التعريف وحده، ونفس الشيء لـ`blockedMessage`. ⇒ السحب في التطبيق المرجعي
  **لا يُحجب** بوجود تغييرات محلية غير مرفوعة.
- أندرويد كان يحجب زر «سحب التغييرات الآن» في الإعدادات عند `pendingCount() > 0`
  ويطلب «ارفع أولاً». الأثر العملي: جهاز فشل رفعه (شبكة/صلاحية/خطأ خادمي) **لا
  يستطيع السحب أبداً** — وهو عرض مطابق لشكوى «السحب لا يعمل».
- **التغيير:** الزر صار يُعلِم فقط («يوجد N تغييراً محلياً غير مرفوع — سيُرفع
  تلقائياً، ويجري الآن سحب تغييرات الخادم») ثم **يُكمل السحب**، مطابقةً للسلوك
  الفعلي في الفرع المرجعي.
- **لماذا لا خطر على البيانات المحلية:** التعديل غير المرفوع محفوظ كحمولة في صفّ
  `outbox` نفسه (يُرفع لاحقاً كما هو)، وتطبيق صف الخادم يخضع للأحدث-يفوز
  (`remoteLastModified >= existing.lastModified` في `SyncIngestorRegistry.applyRecord`).
- ملاحظة: مسارا الداشبورد والسحب التلقائي لم يكن فيهما هذا الحجب أصلاً؛ فالإصلاح
  يجعل الشاشات متسقة مع نفسها.

### F2 — الحجر عند الفرع **بطبقتين**، وعندنا بطبقة واحدة

- الفرع: «سجل انتظار» (`_blockedPending`، سقف 300) يُعادة حلّه في **بداية كل
  دورة** (`pendingForRetry()` — `:212`)، وبعد **3 دورات** (`:46`) يُنقل إلى الحجر
  (`promote` — `cloudflare_sync_manager.dart:2390`) ويستمر شفاؤه (`collectHealCandidates`).
- عندنا: طبقة واحدة — الصف يُعزل فوراً بحمولته، ويُعاد حلّه من الحمولة في كل دورة
  (شفاء بسقف 100)، ويُعاد فحصه أيضاً إن وصل ثانيةً في الدلتا.
- **الأثر:** متماثل في الضمان (المؤشر يتقدم، لا فقدان حمولة، إعادة محاولة كل دورة)،
  والفارق أن الفرع يوزّع العمل بين سجلين لتفادي إثقال الدورة بالصفوف الجديدة.
  الفرق مُوثَّق ولم يُنقل عن قصد — لا أثر وظيفي على تقارب البيانات.

### F3 — الفرع **يتخطى بسرعة** الصف المعزول عند وصوله في الدلتا

- `cloudflare_sync_manager.dart:2967`: `_quarantine.isQuarantined(...)` ⇒ تخطٍّ
  بلا محاولة تطبيق. عندنا: تُعاد المحاولة (يزيد العدّاد) ثم يعيد الشفاء المحاولة
  نفسها في الدورة. لا ضرر (لا كتابة ولا حجب)، والسلوك عندنا أكثر إلحاحاً على
  الشفاء لا أقل.

### F4 — حالة الحجر: `SharedPreferences` عند الفرع، وSQLite عندنا

- الفرع يستمرئ الحجر وسجل الانتظار في JSON داخل `SharedPreferences`
  (`_kQuarantinedKey`, `_kBlockedPendingKey` — `pull_quarantine.dart:43-45`)، بسقف
  300 لكل سجل.
- عندنا جدول `sync_quarantine` في Room (مفاتيح أولية `(entity, recordKey)`، عدّاد
  محاولات، وعمر أول عزل). لا نقل مطلوب: نفس السقوف ومعاملة الصفحة تحفظ الأدلة
  ذرّياً.

### F5 — **الـWorker ليس واحداً في الفرعين** (فارق جوهري في المراجعة)

مقارنة `worker/src` بين الفرع المرجعي وفرع الجلسة:

| البند | الفرع المرجعي | فرع الجلسة |
| --- | --- | --- |
| ملفات خاصة به | `finance.ts`, `finance-data.ts`, `finance-routes.ts`, `maintenance.ts` | `expense-kind.ts` |
| نشر الطوابع/المؤشر | تعليق `allocateUpdatedAt` القديم | `commitStamped` (إدراج + ساعة + تحديث + قراءة في دفعة D1 واحدة) + سقف `ceiling` لكل صفحة |
| قراءة الجداول في السحب | `Promise.all` على 24 جدولاً (تعليق «تسريع full sync») | مسح تسلسلي مع `boundClause` على السقف |
| `sync_write_times` | غير موجود | مستعمل (5 مواضع) |
| أعمدة `ENTITY_TABLES` | 24 (نفسها) | 24 (نفسها) |

- **التوافق مع العميل:** تحقّقنا أن الـWorker في **الفرعين** يقرأ نفس معاملات
  السحب (`tombstones_only`, `include_remaining`, `normalize_timestamps`,
  `exclude_device`) ⇒ عميل أندرويد يعمل مع أيٍّ منهما.
- **توصية نشر:** يجب توجيه التطبيق إلى نشر الـWorker المتوافق مع فرعه (فرع
  الجلسة)، لأن `commitStamped`/`sync_write_times` سلوك مؤشر لا يوجد في الفرع
  المرجعي؛ وخلط العميل بنشر الآخر يظل يعمل لكن بضمانات مؤشر مختلفة.
- الترحيلات: الفروق بين الفرعين مُدقَّقة بنداً-ببند في
  [`cloudflare-migrations-parity.md`](./cloudflare-migrations-parity.md) §5.

### F6 — بدائل الحقول: مطابقة القيم مُتحقَّق منها

| الحقل | قيمة الفرع (fallback) | عندنا |
| --- | --- | --- |
| `inventory_items.unit` | `'قطعة'` — `inventory_adapter.dart:57` | ✓ نفسها |
| `inventory_transactions.movement_type` | `'adjustment'` — `inventory_adapter.dart:229-231` | ✓ نفسها (`movement_type` + `transaction_type` معاً) |
| `employees.position` | `'موظف'` — `employees_adapter.dart:67` | ✓ نفسها (لا `'-employed'` المحلية) |
| `rooms.cleaning_status` | `'clean'` — `rooms_adapter.dart:70` | ✓ نفسها |
| `bookings.guest_id_type` | `'بطاقة شخصية'` — `bookings_adapter.dart:105` | ✓ نفسها |
| `bookings.discount_type` | `'per_night'` | ✓ نفسها |
| `bookings.expected_nights` | `1` | ✓ نفسها |
| `guest_infos.id_type` | `'بطاقة شخصية'` | ✓ نفسها |
| `salary_cycles.status` | `'draft'` — `salary_cycles_adapter.dart:165` | ✓ نفسها |
| `booking_notes.is_active` | `1` — `booking_notes_adapter.dart:87` | ✓ نفسها |
| `booking_price_adjustments.is_active` | `true` | ✓ نفسها |
| `price_adjustments.adjustment_mode` | `'per_night'` | ✓ نفسها |
| `shift_notes.{priority,shift_type,created_by,is_read}` | `'medium'/'all'/'user'/0` | ✓ نفسها |

### F7 — ملاحظات على الفرع نفسه (بلا إجراء علينا)

- `payments_adapter` يقرأ `amount` بلا بديل صريح (`_vDouble`)، فإن غاب العمود عن
  صفٍّ خادمي يصل NULL إلى Drift — الفرع يعتمد على أن D1 يعيد كل الأعمدة دائماً.
  عندنا نفس الاعتماد، لكن العمود `payments.amount` في D1 غير قابل للـnull (تحقّق
  آلي بـ`worker/schema.sql`)؛ والحقول التي قد تصل null فعلاً
  (`salary_withdrawals.withdrawal_type`, `blacklist.reported_by`) مُغطّاة عندنا
  بافتراضيات — **هذا فحص آلي جديد أُجري في هذه المراجعة** (انظر §4).
- `salary_withdrawals_adapter.dart:194` يستعمل `d.Value.absent()` لـ
  `withdrawalType` — أي «اترك العمود كما هو» لا «اكتب قيمة» (سلوك Drift يختلف عن
  Kotlin/Room)؛ لذلك افتراضيّتنا `'سحب راتب'` مأخوذة من مُنشئ Room لا من الفرع،
  والحقل في D1 قابل للـnull فعلاً فالتغطية ضرورية.

### F8 — استنتاج الكيان عند غياب وسم `_entity` — **كان نقصاً حقيقياً، أُصلح**

- الفرع: كل سجل يُوجَّه بـ`record['_entity'] as String? ?? _detectEntity(record)`
  (`cloudflare_sync_manager.dart:2122` و`3712`)، و`_detectEntity`
  (`:3798-3915`) يستنتج الكيان من **بصمة أعمدة السجل** (24 بصمة تغطي كل
  الكيانات)، وإن فشل الاستنتاج يُسقط السجل مع `debugPrint` فقط.
- عندنا قبل الإصلاح: `record["_entity"]` حصراً؛ فسجل بلا وسم — من نشر Worker
  أقدم من إضافة الوسم (`worker/src/database.ts:391-393` أضافها لاحقاً) أو سجل
  مقطوع — كان يُعزل `missing_entity` بحمولته ويُعاد كل دورة بلا أمل في النجاح.
- **الإصلاح:** `SyncIngestorRegistry.resolveEntity(record)` +
  `inferEntityFromRecord(record)` (جدول البصمات منقول حرفياً بحرفه وترتيبه
  من `_detectEntity`؛ أسماء `snake_case` فقط كما في المرجع لأن الخادم يرسل
  snake_case دائماً)، ويُستعملان في مسار الاستيعاب كله (`ingestPage` للمؤشرات
  والتشخيص، و`applyRecord` للتوجيه).
- **اختبارات التكافؤ:** `everySyncEntityHasAnInferenceSignatureIdenticalToDart`
  (يؤكد أن الـ24 كياناً كلها لها بصمة، ويرفض أي انحراف عنها)،
  `explicitEntityTagWinsOverColumnSignature` (الوسم الصريح يسبق البصمة — نفس
  ترتيب Dart)، `recordWithoutEntityTagIsRoutedByItsColumnSignature` (سجل
  بلا وسم يُطبَّق فعلاً بعد أن كان يُعزل)،
  `untaggedRecordWithUnknownSignatureStaysQuarantinedAsMissingEntity`.
- **فرق مقصود واحد:** حين تفشل البصمة أيضاً، Dart يُسقط السجل صامتاً ونحن
  نُعزله بحمولته (`missing_entity`) فيبقى قابلاً للاسترجاع إن تعلّم التطبيق
  الكيان لاحقاً — مغطّى باختبار ويُوثَّق هنا صراحةً بدل ادّعاء تطابق تام.

## 4) الفحص الآلي الجديد: «حقول Room غير القابلة للـnull مقابل مخطط D1»

أُجري فحص آلي في هذه المراجعة يقارن كل حقل Kotlin غير قابل للـnull (باسمه على
السلك) بأعمدة `worker/schema.sql`:

1. **لا حقول بلا عمود خادمي** بعد الإصلاحات الحالية — كل حقل إما عمود خادمي، أو
   مُغطّى بمرادف/افتراضي/درع أعلام.
2. **عمودان خادميان قابلان للـnull** يقابلان حقلين محليين غير قابلين للـnull:
   `salary_withdrawals.withdrawal_type` و`blacklist.reported_by` — وكلاهما مُغطّى
   في `entityDefaults`، فلا يمكن أن يُرفض صفٌّ بسببهما.

## 5) المتبقّي والقرارات المطلوبة

1. **`inventory_transactions.movement_type → 'adjustment'`** — ✅ **نُفِّذ**
   (`SyncWireFields.entityDefaults`): يُملأ المفتاحان `movement_type` (السلك)
   و`transaction_type` (المحلي) معاً، لأن `applyLocalAliases` ينسخ من السلك
   إلى المحلي فقط إن وُجد مفتاح السلك. اختبار:
   `SyncWireFieldParityTest.inventoryTransactionWithoutMovementTypeFallsBackToAdjustmentLikeDart`.
   **ملاحظة صدق:** `worker/schema.sql` يقول `movement_type TEXT NOT NULL` — لا
   `DEFAULT` خادمي (تصحيح لصياغة سابقة في هذا الملف)، فالافتراضي دفاعي بحت
   مطابق لـDart، والخادم يرسل العمود دائماً.
2. **`quantity`/`balance_after` عند غيابهما**: Dart يستعمل `?? 0`
   (`inventory_adapter.dart:232-236`). عندنا `balance_after` له افتراض Kotlin
   `0.0` في الكيان ⇒ نفس النتيجة، و`quantity` **بلا افتراض** ⇒ يُعزل الصف
   بحمولته. فرق مقصود موثَّق: لا نُلفّق كمية صفرية؛ والعزل آمن لأن المؤشر
   يتقدّم، ويُعاد الحل من الحمولة. (نفس سياسة `applyWireDefaults` المعلنة: لا
   صفر مكان قيمة رقمية قياسية.)
3. **طبقتا الحجر**: نقلهما للفرع = عمل إضافي بلا تغيير في تقارب البيانات؛ مُوثَّق
   كفرق مقصود.
4. **النشر**: يجب التأكد من أن نشر الـWorker الذي سيتصل به التطبيق هو النشر
   المتوافق مع `commitStamped`/`sync_write_times` (فرع الجلسة).
5. **لا يعوّض هذا التقرير** عن: تشغيل Flutter نفسه، أو جهاز حقيقي، أو مقارنة
   screenshots.

## 6) المراجع

- الفرع: `origin/feat/cloudflare-sync-execution@ac283c6c` (PR #613).
- مرفقات لم تصل بيئة الجلسة (أُبلغ عنها في المحادثة): «ملحق دعم التطبيقين Flutter
  وAndroid_Kotlin.md» و«cloudflare-pull-delta-sync-root-cause-report.md» — عند
  وصولهما تُقارَن نتائجهما ببند-ببند مع هذا التقرير.
- عندنا: `docs/android-pull-parity-flutter.md`،
  `docs/cloudflare-migrations-parity.md`، `docs/android-pull-quarantine.md`.
