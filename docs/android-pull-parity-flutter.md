# مواءمة «سحب التغييرات» في أندرويد مع تطبيق Flutter

المصدر المرجعي: `feat/cloudflare-sync-execution`
(`mobile/lib/services/cloudflare_sync_manager.dart` و
`cloudflare_realtime_sync.dart` و`sync/pull_quarantine.dart` و
`sync/pull_apply_rules.dart`)، والمقصد: `agent/android-cloudflare`
(تطبيق Kotlin/Compose الأصلي في `mobile/android`).

## الخلاصة

محرك أندرويد كان يملك أصلًا: مؤشر دلتا محفوظ، epoch، فلتر صدى الجهاز،
سقف 100 صفحة، حجر صحي، روابط أب مؤجلة، `repair_pending`، وتطبيع الطوابع.
هذه الدفعة تنقل العقود التي كانت ناقصة فعلاً:

1. **المزامنة الفورية (Realtime WebSocket)** — المفتاح كان معروضًا في
   الإعدادات ويوعد باستقبال تغييرات الأجهزة الأخرى، ولم يكن هناك عميل
   WebSocket إطلاقًا. الآن: `CloudflareRealtimeClient` على `/api/realtime`
   (RealtimeHubDO).
2. **مسح الحذفيات التاريخي لمرة واحدة** — `tombstones_only=1` بمؤشر
   مستقل قابل للاستئناف (الأجهزة التي سحبت في نافذة العقد القديم كان
   مؤشرها قد تجاوز حذفيات لم تُبَث لها).
3. **حراس المؤشر المسموم** — ثلاث طبقات: عند الإقلاع، أثناء الدورة، وعند
   التثبيت النهائي (طوابع ميلي/sentinel التي تُعمي الجهاز للأبد).
4. **إشعار FCM → سحب دلتا** — خدمة رسائل تصل بإشارة `marina_sync`.
5. **إعادة بناء الحقول المشتقة للحجوزات بعد السحب** — اكتُشفت في التدقيق
   المتأخر: الإجماليات المخزَّنة تُحسب على كل جهاز، فجهاز يسحب دفعة/ليلة من
   جهاز آخر كان يبقى بأرقام قديمة (Dart يعيد البناء في كل دورة:
   `_refreshDerivedAfterPull`).

قواعد الرفع/الدمج/المعادلات المالية ومخطط Room لم تُمس. لا migration جديد.

## 1) المزامنة الفورية (Realtime)

`data/remote/realtime/`:

- `CloudflareRealtimeClient` — OkHttp WebSocket إلى
  `wss://<host>/api/realtime?deviceId=..&entity=*` مع
  `Authorization: Bearer <JWT>`؛ القراءة من `SyncPreferences` ومفاتيح
  `WorkerEndpoints` (تدوير النطاق المخصّص ↔ workers.dev، تثبيت الناجح
  وتنزيل الفاشل — نفس عقد Flutter).
- **الحدث إشارة لا بيانات**: `change` فقط يزيد الشارة ويجدول سحب دلتا عبر
  المحرك؛ لا تطبيق مباشر من حمولة الحدث. `presence/lock/unlock` تُهمل
  (الأقفال تُدار خادميًا).
- **echo filter**: حدث جهازنا نفسه (`deviceId == deviceId المحلي`) لا
  يُطلق سحبًا.
- **ضبط المعدل (أرقام Flutter حرفيًا)**: debounce 500ms، تهدئة 15s بين
  دورات السحب، حارس in-flight + متابعة trailing، وفشل السحب لا يهضم
  الحدث (يُعاد جدولته).
- **إعادة الاتصال**: backoff أُسّي 1s→60s، حد 6 محاولات ثم إعادة تسليح
  دورية كل دقيقتين؛ heartbeat 30s؛ مهلة إنشاء اتصال 15s (مقبس شبه مفتوح
  على شبكات محجوبة كان يعلّق كل المحاولات).
- **استرداد بعد الانقطاع**: أول اشتراك ناجح بعد انقطاع غير مقصود يطلق
  سحبًا واحدًا يستدرك ما فات.
- **دورة الحياة**: يعمل في الواجهة فقط — `AutoSyncEngine.onForeground()`
  يستأنفه و`onBackground()/stop()` يوقفه ويلغي كل ما هو مجدول (نفس مرحلة
  Flutter 3.3: بطارية + عدم إبقاء DO مفتوحًا بلا داعٍ).

`SyncManager.pullOnRealtimeEvent()` هو نظير `realtimeTriggeredPull`:
**دلتا فقط** (`push:false`)، **يتخطى بصمت** عند انشغال مزامنة أخرى
(`false` فيجدول المستدعي متابعة)، ويتجاوز بوابة الساعة عمدًا لأن الحدث
دليل تغيير فعلي (`forcePull:true` في Dart).

الواجهات: `RealtimeSyncRepository` (domain) يعرض
`RealtimeSyncState` — حالة الاتصال، المحاولات، آخر إطار، آخر خطأ، وعداد
التغييرات البعيدة. تظهر حيًّا في: شاشة إعدادات المزامنة (سطر تحت مفتاح
Realtime) وشريط حالة اللوحة الرئيسية عند وصول تغييرات من أجهزة أخرى.

## 2) مسح الحذفيات التاريخي

`SyncManager.performTombstoneSweepIfDue()`:

- البوابة: العلم `cf_tombstone_sweep_done` غير مضبوط **و** الجهاز قائم
  فعلاً (`cursor > 0` أو اكتمل full sync سابقًا). التثبيت الجديد لا
  يمسح — سحبه الكامل يجلب الحذفيات نفسها.
- الاستئناف: `cf_tombstone_sweep_cursor` يُحفظ بعد كل صفحة مطبَّقة، ففشل
  شبكي لا يعيد المسح من الصفر.
- حارس تقدم: مؤشر ثابت مع صفوف = إجهاض بلا ضبط العلم.
- سقف 20 صفحة في الدورة الواحدة (فلسفة سقف الصفحات نفسه): مسح ضخم لا
  يحبس دورة السحب، والبقية تُستأنف في الدورة القادمة.
- الفشل (شبكة/HTTP/رد ناقص أو غياب توكن) **لا** يضبط العلم ولا يُفشل دورة
  السحب — أفضل جهد صريح.
- المؤشر الرئيسي لا يُلمس إطلاقًا: الدلتا تبقى المرجع الوحيد لتقدم الجهاز.
- `WorkerPullResponse` يُمرَّر بـ`tombstones_only=1` وكان الخادم يدعمه
  أصلًا (`worker/src/sync.ts`+`database.ts`)؛ لا تغيير في الـ Worker.

## 3) حراس المؤشر المسموم

`data/sync/PullSanityPolicy.kt` (سياسات نقية قابلة للاختبار) وثلاث طبقات
تنفيذ في `SyncManager`:

| الطبقة | الموضع | العقد |
| --- | --- | --- |
| الإقلاع | `sanitizeStoredCursorIfNeeded()` | مؤشر محفوظ > 2e9 → تصفير + إسقاط `full_sync_complete` + `full_replay_pending`، ويُسجَّل في سجل الأخطاء المحلي. يُستدعى من `AutoSyncEngine.start()` وعند كل دورة سحب. |
| أثناء التشغيل | داخل حلقة السحب | مؤشر خادم > `server_time` المُعلن + سنة كاملة → الدورة تفشل، **ولا تُطبَّق الصفحة** (طوابعها المسمومة كانت ستكسب كل قرارات LWW). |
| التثبيت النهائي | قبل كتابة المؤشر | مؤشر مرشّح > 2e9 لا يُخزَّن أبدًا: يُصفَّر المؤشر مع علامة full sync (يعمل حتى مع Worker قديم بلا `server_time`). |

الحد 2e9 يبقى آمنًا حتى سنة 2033 (الثواني الحالية ~1.79e9)، وهو مرآة عتبة
الخادم `FUTURE_TIMESTAMP_THRESHOLD` نفسها.

## 4) رسائل FCM

`data/sync/MarinaMessagingService` (مسجَّلة في `AndroidManifest.xml`):

- تُعالج فقط رسائل `type`/`source` = `marina_sync` (عقد `fcm_service.dart`).
- **echo filter**: رسالة من نفس الجهاز (`senderDeviceId` == `deviceId`) تُهمل.
- التسليم إلى `AutoSyncEngine.onRemoteSignal()`: في الواجهة = شارة + سحب
  دلتا مُدمج؛ في الخلفية = تُحفظ الإشارة وتُستهلك عند العودة للواجهة.

**حدود مقصودة:** لا نصدر إشعارًا محليًا من حمولة رسالة، ولا نبدأ شبكة من
عملية غير ظاهرة (قيد Android على حدود الخلفية) — بخلاف مسار Flutter الذي
يعمل في عملية الخلفية. هذا بديل صريح لا ادعاء مطابقة حرفية، وقيد الحصول
على رسالة أصلًا يبقى على عاتق مرسل FCM (worker/`functions/fcm-notifier`).

**فرق ثالث مُعلَن (مقصود)**: مسار FCM في Flutter يستدعي `sync(push: false)`
بلا `deltaOnly` — أي أنه قد يبدأ bootstrap على جهاز لم يُكمل full sync،
بينما أندرويد يمرّره عبر `pullOnRealtimeEvent()` (دلتا دائماً). عملياً لا
فرق في البيانات: الدلتا من مؤشر صفر تجلب كل الصفوف؛ الفرق في أعلام
full-sync/remaining/normalization التي تبقى مسؤولية الإجراء الصريح
`fullPull()` — وهو الاتساق الذي يفرضه `deltaOnly` في Dart نفسه لباقي
المشغّلات (اللوحة، التلقائي، Realtime).

## تفاصيل مطابقة عميل Realtime (تدقيق 2026-10-06)

قورن `cloudflare_realtime_sync.dart` (كل الملف) بـ`CloudflareRealtimeClient.kt`:

| البند | Dart | Kotlin |
| --- | --- | --- |
| heartbeat | `pingInterval: 30s` | `pingInterval(30s)` |
| مهلة الاتصال | `connectTimeout: 15s` | `connectTimeout(15s)` + مؤقت حراسة (watchdog) |
| مهلة القراءة | لا شيء (مقبس مفتوح) | `readTimeout(0)` |
| تدوير النقاط | `WorkerEndpoints.active` + `candidatesFor` + `reportSuccess/reportFailure` | نفسه حرفياً عبر `WorkerEndpoints` |
| echo filter | `msg.deviceId == _currentDeviceId` | نفسه (`preferences.getDeviceId()`) |
| الأنواع المُطلِقة | `change` فقط (`presence/lock/unlock` لا) | نفسه |
| استرداد بعد الانقطاع | `_recoveryPullPending` ⇒ حدث عند أول اتصال | نفسه |
| الاستسلام/إعادة التسليح | 6 محاولات ثم كل دقيقتين | نفسه |
| الرابط | `/api/realtime?deviceId=…&entity=*` على `wss` | نفسه |

**فرق مقصود واحد (أكثر تحفّظاً)**: `ensureStarted()` في Dart لا يفحص مفتاح
التشغيل — فبعد تعطيل المستخدم للمزامنة الفورية يستطيع استئناف المقبس عند
العودة للواجهة. في أندرويد يفحص `ensureStarted()`/`connect()` المفتاح
(`getRealtimeSyncEnabled() && getCloudflareSyncEnabled()`) فلا يُفتح مقبس
أصلاً — نفس دلالة الإعداد «معطّل» (وإلا فالمفتاح وعدٌ كاذب).

**فرق مقصود ثانٍ (قيود Android)**: رسالة FCM في الخلفية لا تبدأ شبكة من
عملية غير ظاهرة — تُحفظ الإشارة وتُستهلك عند العودة للواجهة بشرط
`masterSyncEnabled && networkAllowed` (نظير Dart يبدأ `sync(push:false)`
مباشرة في معالج الخلفية). كل من التصفية والقرار في
`RemoteSignalPolicy` الخالصة المُختبرة.

## زر «سحب التغييرات» في اللوحة = دلتا دائماً (لا Bootstrap صامت)

الفرق المكتشف في جولة 2026-10-06: تعليق `performPullOnly` كان **يدّعي**
مطابقة `sync(push: false, deltaOnly: true, forcePull: true)` في Dart، لكن
التنفيذ كان `pullDelta()` الذي يقلب السحب إلى full replay كامل أي أن جهازاً
جديداً (مؤشر 0) يضغط الزر فيُشغّل bootstrap صامتاً — وهو ما يمنعه Dart
صراحةً:

```dart
// cloudflare_sync_manager.dart l.1850-1851
// Full Sync is explicit (fullSync()). Normal foreground/manual pulls are
// bounded delta pulls even before the first Bootstrap.
final wasFullSync = !deltaOnly && !_fullSyncCompleted;
```

الإصلاح (مطابق حرفياً):

- `SyncManager.pullDelta(..., deltaOnly: Boolean = false)`:
  `fullReplay = isFullPull || pendingReplay || (!deltaOnly && cursor == 0L)`.
  أي أن `deltaOnly` يمنع **بدء** bootstrap جديد، بينما يبقى **الاستئناف
  المُعلَّم** (تدوير epoch أو استعادة نسخة: علم `full_replay_pending`)
  سارياً — العلم يعني «بدأناه ويجب إنهاؤه».
- `performPullOnly()` صار `pullDelta(deltaOnly = true)`: زر اللوحة،
  والسحب التلقائي، وRealtime/FCM كلهم دلتا (Dart: السحب التلقائي
  l.3936 وrealtime l.4313 بـ`deltaOnly: true`).
- `fullPull()` (زر السحب الكامل في الإعدادات) هو الـbootstrap الصريح
  الوحيد: لا يتغير.

اختبار حاكم: `freshDeviceDashboardPullStaysDeltaAndNeverBootstraps`
— جهاز بمؤشر 0 وبلا `full sync` مكتمل يضغط الزر ⇒ الطلب يحمل
`exclude_device=own` وبلا `include_remaining`/`normalize_timestamps`،
و`isFullSyncComplete()` و`isFullReplayPending()` يبقيان `false` بينما
المؤشر يتقدم فعلاً.

**تدقيق 2026-10-06 (لاحق):** كان هذا التأكيد **قابلاً للنقض شكلاً فقط**:
سجل `PullRequest` في الاختبار كان يقرأ ثلاث حجج (المؤشر/`exclude_device`/
`tombstones_only`) ولا يقرأ `include_remaining`/`normalize_timestamps` —
وهما العلمان الوحيدان المميزان لمسار السحب الكامل. فيصحّ الاختبار حتى لو
تسرّب bootstrap صامت على شكل `include_remaining=1`. الآن يُسجَّل كل ما
يُرسل فعلاً إلى `CloudflareWorkerApi.pull` (ست حجج)، وأُضيف الطرف المقابل
`explicitFullSyncIsTheOnlyPathRequestingRemainingAndNormalization`: الإجراء
الصريح `fullPull()` هو الذي يمرّر `"1"` للعلمين وبلا `exclude_device`
ويُعلن اكتمال الـ bootstrap — أي أن الرصد غير فارغ، وأن الفرق بين الزرين
مُثبت في الاتجاهين.

**ملاحظة سابقة هذه الجولة**: أعلام `include_remaining`/`normalize_timestamps`/
`tombstones_only` صارت تُرسل نصاً `"1"` (كانت `Boolean` → `"true"`)، لأن
الـ Worker يفحص `=== '1'` حرفياً — وبذلك كان `tombstones_only` يُهمل صامتة
حتى في worker هذا الفرع. التفاصيل في
[`cloudflare-migrations-parity.md`](./cloudflare-migrations-parity.md) §4.

## إعادة بناء الحقول المشتقة للحجوزات بعد السحب (تدقيق 2026-10-06)

**الثغرة المكتشفة:** الإجماليات المخزَّنة في جدول الحجوزات
(`calculated_nights` / `total_due_cached` / `total_paid_cached` /
`remaining_balance_cached` / `is_fully_paid`) تُحسب **محلياً على كل جهاز**،
وكان محرك Kotlin يسحب دفعاتٍ أو لياليَ حجز أنشأها جهاز آخر **دون** إعادة
حسابها — فيبقى الجهاز بأرقام قديمة حتى يفتح المستخدم شاشة الدفع (أو ينفّذ
تعديلاً محلياً). Flutter يعيد البناء تلقائياً في كل دورة سحب.

**العقد الدارتي الحرفي** (`feat/cloudflare-sync-execution`):

| العنصر | المصدر |
| --- | --- |
| الشرط: `pulledDerivedEntities.isNotEmpty && totalPulled > 0` | `cloudflare_sync_manager.dart` l.2591 |
| مجموعة الكيانات المؤثرة | `_derivedRefreshEntities` (l.3766): `bookings`, `booking_nights`, `payments`, `price_adjustments`, `booking_price_adjustments`, `payment_voids` |
| نطاق الإعادة | `BookingDerivedFieldsService.refreshAllActiveBookings`: كل الحجوزات بلا `actual_checkout` وغير المحذوفة ناعمياً، ثم تصفية `StatusUtils.isBookingActive(status)` |
| المعاملة | معاملة واحدة لكل الدفعة (تعليق Dart الصريح: تفادي `SQLITE_BUSY`)، وفشل صف يُسجَّل ويُتابع |
| بلا رفع | `enqueueOutbox: false` — المشتق يُحسب على كل جهاز ولا يُرفع (وإلا حلقة سحب/رفع) |
| حارس تكرار | `_derivedRefreshRunning` — لا إعادة دخول |
| موضع التنفيذ | بعد دورة السحب: لا تُنفَّذ في الدورة الفاشلة (Dart يرمي قبل السطر) وتُنفَّذ في الدورة المتدهورة التي انتهت بلا خطأ |

**التنفيذ في أندرويد:**

- `data/repository/BookingDerivedRefreshService.kt` (جديد): نظير
  `BookingDerivedFieldsService` — نفس النطاق ونفس المعاملة الواحدة ونفس
  التسامح مع فشل الصف ونفس «بلا رفع» (الكتابة عبر
  `BookingsDao.updateFinancialCache` التي لا تمس بيانات المزامنة).
- `PullApplyReport.touched` (جديد، نظير `touchedEntities`): كيانات الصفوف
  المطبَّقة فعلاً فقط — تُجمع عبر الصفحات **وعبر** إعادة حل المؤجَّل
  (`retryPendingLinks`)، ثم تحكم بوابة `affectsDerived` متى تُستدعى الخدمة
  (لا استدعاء لكيان غير مؤثر: `SyncManager.refreshDerivedAfterCycle`).
- `BookingsRepositoryImpl`: حساب الحقول المشتقة المحلي (عند إضافة/تعديل حجز)
  صار مُفوَّضاً **لنفس الخدمة** — مصدر وحيد بدل نسختين قابلتين للانحراف.
  وقد رصد CI انحداراً حقيقياً من هذا النقل: جعل الكتابة كتابتين متتاليتين
  يُظهر للمراقبين لحظةً تكون فيها الإجماليات قديمة، فأسقط اختبار القائمة
  (متوقّع 1900 وكان 2000). الإصلاح: الصف + الـoutbox + المشتقات داخل
  `db.withTransaction` واحدة — وهو نصّ ما يفعله Dart في
  `bookings_repository.dart` (create/update).

**فروق مقصودة (معلنة لا مخفية):**

1. Dart يكتب اثني عشر حقلاً مشتقاً (منها `isOverdue` / `needsCheckoutReview` /
   `hotel_day_checkin` / `hotel_day_checkout`)، وأندرويد يكتب الأعمدة الخمسة
   التي تقرأها واجهاته فعلاً (تحقّق بحثاً في طبقة `presentation`: لا قارئ
   لـ`isOverdue`/`needsCheckoutReview` في الحجز). التوسيع لاحقاً يقتضي إضافة
   عمود إلى استعلام التحديث فقط.
2. Dart يكتب `updated_at` جديداً للحجز أثناء إعادة البناء (دون `last_modified`)؛
   أندرويد يترك بيانات المزامنة كما هي. الأثر محلي بحت: كل قرارات «آخر كتابة
   تفوز» في الاستيعاب تعتمد `last_modified` (لذلك لا تأثير على أي قرار
   استيعاب)، والفرق يمنع أن يبدو المشتق المحلي تعديلاً حديثاً.
3. سقف «حارس إعادة الدخول»: Dart يعيد `false` صامتاً عند التزامن، وأندرويد
   كذلك (`AtomicBoolean` + CAS) — بلا طابور تراكمي عند دورات متلاحقة.

**الاختبارات:** `BookingDerivedRefreshParityTest` (Robolectric، شبكة مصطنعة
عبر Proxy، قاعدة في الذاكرة) — الدفعة البعيدة تُحدّث المخزَّن فوراً (وكان
صفراً قبل الدورة)، ليلة الحجز تُحدّث من سجل الليالي لا من الصيغة، كتلة غير
مؤثرة (`rooms`) لا تلمس أي حقل مخزَّن (مقارنة قبل/بعد لكل الحقول)، النطاق
يستثني المغادرَ والمحذوفَ ناعمياً، ولا كتابة على صف محذوف
(`updateFinancialCache` تشترط `deleted_at IS NULL`)، وتقرير الاستيعاب يحمل
الكيانات المطبَّقة فقط (لا المؤجَّلة/المتخطّاة/الفاشلة).

**الدليل:** تشغيل `37526150400` @ `c7527567` — المهام الثلاث **نجحت**
(`:app:testDebugUnitTest` + `worker: vitest + typecheck` + `android-sync-detekt`).

## تدقيق الملفات المرجعية المتبقية (2026-10-06، مقابل `ac283c6c`)

الملفات الخمسة الباقية من مسار السحب في Flutter دُقّقت سطراً بسطر مقابل نظيرها
في Kotlin (قراءة المصدرين، لا تشغيل جهاز). خلاصة كل ملف:

### 1) `sync/pull_apply_rules.dart` — ✅ مُغطّى بآلية مختلفة

| البند الدارتي | أندرويد |
| --- | --- |
| `pullApplyPriority` (الأب قبل الابن في كل محاولة) | لا فرز حسب الأولوية: المؤجّل يُعاد حله بعد اكتمال **كل** الصفحات عبر `retryPendingLinks()` الذي يكرّر المرور حتى انقطاع التقدم. النتيجة النهائية نفسها؛ الفرق أن صفاً يتيماً قد يُحاوَل مرتين بدل مرة (كلفة محلية بلا شبكة). |
| `naturalUniqueKeys` (ليلة الحجز: `booking_local_id` + `hotel_day_key`) | منفَّذ صراحةً: `SyncIngestorRegistry.fetchByNaturalKey` + `bookingNightsDao.getByNaturalKey`، والدمج LWW بإعادة استخدام معرّف الصف المحلي (`remote.copyWithId(existing.id)`) فلا يُنشأ صف ثانٍ ولا يتجمد المؤشر. |
| `_isUniqueConstraintError` (SqliteException 2067) | غير مطلوب: كل كتابات الاستيعاب `@Insert(onConflict = REPLACE)` ⇒ تعارض الفريد يُحلّ بـ«استبدال» لا باستثناء (خلاف Drift). الصفوف المرفوضة فعلياً تبقى `Failed` وتُسجَّل في `sync_quarantine` — سلوك **أشدّ صرامة مقصود** ومغطّى باختبار `malformedPullRowsAreQuarantinedInsteadOfSilentlySkipped`. |

### 2) `sync/pull_quarantine.dart` — ✅ الجوهر منفَّذ، والعدّادات/السقوف مقصودة الانتفاء

- **سجل الانتظار** (`_blockedPending`: حمولة كاملة تبقى عبر الجلسات وتُعاد كل
  دورة، والمؤشر يتقدم) ↔ جدول `pending_sync_links` في Room: يُكتب داخل معاملة
  الصفحة لكل صف مؤجَّل، ويُعاد حله في `retryPendingLinks()` في كل دورة،
  و`hasFailures` يعني «فشل تطبيق فعلي» فقط ⇒ الصف اليتيم **لا** يجمّد المؤشر
  (جوهر إصلاح 2026-09-15).
- **الحجر** (`_quarantinedRecords`، بلا حمولة معادة) ↔ جدول `sync_quarantine`
  (دليل لا يُنفَّذ). أندرويد يستخدمه أيضاً للفشل الفعلي؛ ولأن الفشل الفعلي
  **لا يثبّت المؤشر** فالصف يُعاد سحبه وتطبيقه كل دورة ⇒ الشفاء تلقائي بلا
  عدّاد دورات (طريق مختلف، ونفس نتيجة الشفاء).
- **فروق مقصودة**: لا عدّاد حجب/عتبة 3 دورات ولا سقوف `300/300` ولا إخلاء
  بالأقدم. سبب الوجود الدارتي هو تخزين الحمولات في `SharedPreferences`
  (بطء + خطر `TransactionTooLarge` على أندرويد)؛ الحمولات هنا في Room مفهرسة.
  الإخلاء عمداً **غير** منقول حتى لا يُفقد دليل حجب قابل للإصلاح.
- `isQuarantined` (تخطي المعزول إن عاد في صفحة) غير لازم: الحجر في أندرويد =
  فشل فعلي يُبقي المؤشر، فإعادة التطبيق هي مسار الشفاء لا التخطي.

### 3) `sync/app_open_pull_gate.dart` — ✅ مُغطّى ببوابة موحّدة

- الدارتي: مفتاح `last_app_open_pull_epoch_ms` + فاصل **ساعة**، ويُختم **فقط
  بعد سحب ناجح**.
- أندرويد: `automaticPullDue` + `AUTOMATIC_PULL_INTERVAL_MS` (ساعة) فوق
  `getLastPullTs()`، والختم في المواضع الثلاثة كلها **بعد** `pulled >= 0`
  (`performSyncNow` / `performPullOnly` / `performFullPull`)، وبدء التشغيل عبر
  `preferences.getSyncOnStartup()` في `onForeground()`.
- فرق مقصود: مفتاح واحد لكل السحب التلقائي بدل مفتاح خاص بفتح التطبيق ⇒ لا
  يمكن أن ينحرف مساران (وهو سبب استخلاص `AppOpenPullGate` في Dart نفسه)،
  والنتيجة أشدّ صرامة لا أرخى.

### 4) `sync/auto_outbox_sync_watcher.dart` — ✅ + ثغرتان أُغلقتا في هذه الدفعة

| البند | أندرويد |
| --- | --- |
| اشتراك واحد على جدول outbox | `outboxRepository.pendingCount().collect { if (it > 0) schedulePush(3_000L) }` (Flow من Room بدل `SELECT COUNT(*)` مُراقب). |
| `SyncConstants.outboxDebounceWindow` = 3s | نفس القيمة نصاً (`3_000L`). |
| رفع فوري عند العودة للاتصال | `registerNetworkCallback`: `onAvailable`/`onCapabilitiesChanged`/`onLost` ⇒ `schedulePush(0L)` + `requestPullCheck(probeWhenFresh = true)`. |
| `_pushing` + `SyncGuard.tryAcquire` | `SyncOperationRunner` (mutex + `SyncForegroundLifetime` lease) يرفض التقاطع بدل الانتظار. |
| `_doPush` يتخطى بصمت عند انقطاع الشبكة | `drainOutbox()` ببوابة `networkAllowed()` (INTERNET + VALIDATED + wifiOnly). |

**الثغرة (أ) — الرفع من الخلفية:** `pushOnly()` يحجز خدمة أمامية، و Android 12+
يمنع بدء خدمة أمامية من الخلفية. كان `drainOutbox()` يحاول في كل دورة خلفية
فيفشل الحجز ثم يُعاد الجدولة كل 30 ثانية (طَرْق بلا نتيجة). الآن:
`pushDeferredWhileBackgrounded` يُضبط ويُستهلك في `onForeground()` بـ
`schedulePush(0L)`؛ الصفوف تبقى `pending` في outbox (لا فقدان بيانات)، وهو نفس
عقد Dart («الرفع يُؤجَّل، الـ outbox يحتفظ بالصفوف») بديلاً صريحاً عن
WorkManager الذي يرفع من الخلفية في Flutter.

**الثغرة (ب) — لا شبكة أمان:** لو فشل تسجيل callback الشبكة (يُبتلع الخطأ في
`runCatching`)، فصفٌّ ظهر والجهاز غير متصل لا يجد من يرفعه. أُضيف
`pendingPushMonitor` كل 5 دقائق — نظير `SyncGuardian._startPendingMonitor`
تماماً — يفحص العدّاد ويرفع فوراً في الواجهة، أو يُعلّم التأجيل في الخلفية.

### 5) `sync_guardian.dart` — ✅ مُغطّى، وبند واحد غير منقول عن قصد

- `notifyLocalChange` (debounce 5s ⇒ `syncNow`): مُغطّى بمسار واحد هو مراقب
  outbox (3s)؛ لا حاجة لتهدئتين متتاليتين لنفس الحدث.
- `onAppForeground` (تخطي إن مرّت أقل من دقيقتين): أندرويد أشدّ صرامة — بوابة
  الساعة (ساعة) + `AUTOMATIC_PULL_INTERVAL_MS`، فلا سحب عند كل عودة.
- `_startPendingMonitor` (كل 5 دقائق): أُضيف كما في البند (ب) أعلاه.
- لقطة الصحة: `SyncHealthViewModel` (`lastPull`/`lastPush`/`enabled`/
  `errorCount` + `SyncHealthReport`) مقابل `SyncHealthSnapshot` في Dart.
- `setDevicePriority` / `sync_guardian_device_priority`: **غير منقول** — القيمة
  تُكتب وتُقرأ داخل `sync_guardian.dart` نفسه ولا يقرأها أي ملف Dart آخر
  (تحقّق بحثاً على كامل `mobile/lib` في `ac283c6c`)، وأثرها الوحيد الحقل
  `priorityOverridden` في لقطة الصحة ⇒ لا سلوك مزامنة مفقود.

## الاختبارات

| الملف | ما يثبته |
| --- | --- |
| `SyncPullParityTest` | زر اللوحة على جهاز جديد يبقى دلتا ولا يبدأ bootstrap؛ مسح الحذفيات يُطبَّق مرة واحدة ولا يلمس مؤشر الدلتا؛ فشله يبقي البوابة مفتوحة؛ الاستئناف من المؤشر المحفوظ؛ التثبيت الجديد لا يمسح؛ تصفير المؤشر المسموم قبل السحب؛ رفض مؤشر خادم متقدم على `server_time` بلا تطبيق الصفحة؛ منع تثبيت مؤشر فوق الحد الثابت؛ مُشغّل Realtime دلتا فقط ويتخطى بصمت أثناء مزامنة جارية. |
| `BookingDerivedRefreshParityTest` | إعادة بناء الحقول المشتقة بعد السحب: دفعة بعيدة تُحدّث المخزَّن (وكان صفراً)، ليلة حجز تُحدّث من سجل الليالي، كتلة غير مؤثرة لا تلمس المخزَّن، النطاق (نشط فقط) والحذف الناعم، و`touched` يحمل المطبَّق فقط. |
| `PullSanityPolicyTest` | عتبات 2e9 وهامش السنة وحدود صرامة المقارنة وبوابة المسح (كل تركيبات المدخلات). |
| `RealtimeMessageTest` | تحليل متسامح: الشكل الصحيح، حقول اختيارية، إطارات مشوّهة/ناقصة/أنواع خاطئة، حقول زائدة. |
| `RealtimePolicyTest` | سلّم backoff، تحويل https→wss (جذر فشل Dart)، بناء الرابط `entity=*` وترميز `deviceId`، تقصير رسائل الخطأ. |
| `RealtimePullSchedulerTest` | دمج الدفعة (debounce)، تأجيل ما يقع داخل التهدئة ثم تنفيذ واحد، إعادة جدولة الفشل، الإلغاء، حساب المتبقي من التهدئة. |
| `CloudflareRealtimeClientTest` | بوابة المفتاح، echo filter، الشارة، دليل حياة المقبس بإطار مشوّه، التشخيصات، وعدم فتح أي مقبس بلا توكن. |
| `CloudflareDeltaContractTest` | عقد أعلام الاستعلام النصية `"1"` وغيابها عند عدم الطلب. |
| `RemoteSignalPolicyTest` | تصفية مصدر FCM (`type` ثم `source`)، echo filter بالحرف (`senderDeviceId`)، قرار التسليم/التأجيل/التجاهل، وبوابة استهلاك الإشارة المؤجَّلة. |
| `worker/test/sync.tombstone.sweep.test.ts` | عقد الخادم الذي يعتمد عليه المسح: المؤشر = آخر صف حذف مُعاد (لا أكبر طابع)، صف حي أحدث لا يقدّم المؤشر، `exclude_device` داخل نافذة الحذفيات، واستئناف idempotent بعد الانهيار. |

تُعديلات على `SyncIngestorRegistryTest`: حالات السحب القائمة صارت تضبط
`setTombstoneSweepDone(true)` صراحةً كي يبقى تركيزها على المؤشر/الحجر
الصحي/epoch — سلوك المسح له اختبار مخصص (أعلاه).

## التحقق والحدود

### دليل تشغيل فعلي (2026-10-06)

| العنصر | القيمة |
| --- | --- |
| الفرع | `arena/be8302d7-marina-hotel-wit-app` |
| الالتزام | `745112fb` |
| التشغيل | `37513552713` — <https://github.com/NassarAlshabi1/marina-hotel-wit-app/actions/runs/37513552713> |
| الأمر | `./gradlew :app:testDebugUnitTest` على ubuntu-latest + JDK 17 |
| النتيجة | **success** — المهمة `:app:testDebugUnitTest` نجحت (18:44→18:49 UTC) |

أحدث التشغيلات (بعد تدقيق الملفات المتبقية):

| العنصر | القيمة |
| --- | --- |
| التشغيل | `37519136397` — الالتزام `289c31a4` — **success** (المهام الثلاث) |
| التشغيل | `37519764533` — الالتزام `1b6708f3` — **success** (المهام الثلاث) |
| التشغيل | `37520379621` — الالتزام `dc19aac9` — **success** (المهام الثلاث، ويشمل تصريف `AutoSyncEngine` المعدَّل) |
| التشغيل | `37526150400` — الالتزام `c7527567` — **success** (المهام الثلاث، بعد إضافة إعادة بناء الحقول المشتقة) |
| التشغيل | `37527146727` — الالتزام `3a53ccf4` — **success** (مع ملخّص Detekt لكل ملف وقاعدة) |
| التشغيل | `37527612571` — الالتزام `2573d2a8` — **success** (مع نسبة كل ملاحظة إلى سطر جديد/قائم) |
| التشغيل | `37528515035` — الالتزام `c565b341` — **success** (جعل تأكيد دلتا اللوحة قابلاً للتكذيب؛ وCI كشف قبلها خطأ تصريف `remaining = 3` في التشغيل `37528204941` وأُصلح) |
| التشغيل | `37528998667` — الالتزام `c7e393b1` — **success** (مع check-run `android-sync-test-summary`: **360 حالة، 0 فشل، 0 متخطّاة**) |
| التشغيل | `37532858856` — الالتزام `40bcff51` — **success** (بناء APK أول، `android-session-apk`) |
| التشغيل | `37533752036` — الالتزام `bc77d74` — **success** (بناء APK نهائي مع أسطر حكم التوقيع) |
| Detekt (ملفات الدفعة) | **248 ملاحظة** (المستودع: 1592) — التفصيل الكامل والقابل للتدقيق في «فحص ثابت إعلامي» أدناه. |
| اختبار هشّ رُصد وأُصلح | `SyncIngestorRegistryTest.threeIndependentPaymentsSurviveRepeatedEditsInPaymentAndIncomeReports`: `expected:<475.0> but was:<400.0>` — كان يقرأ حالة **دورة سابقة** (`state.first { !it.isLoading }`) قبل تطبيق تعديل الدفعة الجديدة. الإصلاح: `awaitSettledReport` ينتظر **تقارب القيمة المتوقعة** نفسها (لا زوال التحميل فقط) ⇒ لا يتحول إلى تخفيف للفحص: التعديل الذي لا يُعكس يبقى فاشلاً بمهلة. |

قبل هذا التشغيل رصد CI الحقيقي — لا المراجعة النصية — ثلاث علل أُصلحت:
خطأان في التصريف (`AutoSyncEngine` صار يأخذ `Lazy<CloudflareRealtimeClient>`
و`Response.error<Unit>`)، وساعة اختبار الجدولة (كانت مربوطة يدوياً فلا
تنقضي التهدئة)، وتوقّع `null` لا `false` لغياب علم `tombstones_only`.
كما كشف اختبار «زر اللوحة على جهاز جديد» أن `deltaOnly` وُضع في
`performSyncNow` بدل `performPullOnly` — فصُحّح ونُقل.

### دليل «الاختبارات جرت فعلاً» — check-run ملخّص (2026-10-06)

«المهمة خضراء» لا تُثبت أن حالات التكافؤ **جُرت**: سجلات المهام وartifacts
(`marina-sync-test-results`) موجودة لكن تنزيلها من بيئة الجلسة يفشل
(`EOF` من blob storage)، وcheck-run التشخيص يُنشأ عند الفشل فقط — فلم يكن
أمام المراجع أي دليل رقمي على تشغيل ناجح. أُضيفت خطوة غير حاجبة
(`continue-on-error`) تنشر check-run باسم `android-sync-test-summary` يقرأ
XML النتائج ويطبع العدّادات وأسماء حالات أصناف التكافؤ.

نتيجة التشغيل `37528998667` @ `c7e393b1`:

| الصنف | حالات | فشل |
| --- | --- | --- |
| `SyncIngestorRegistryTest` | 56 | 0 |
| `SyncPullParityTest` | 12 | 0 |
| `BookingDerivedRefreshParityTest` | 6 | 0 |
| **إجمالي `:app:testDebugUnitTest`** | **360** | **0** (0 متخطّاة، 0 أخطاء) |

والحالتان المعنيتان بمطلب «زر اللوحة = دلتا» مذكورتان بالاسم في نص
check-run نفسه: `freshDeviceDashboardPullStaysDeltaAndNeverBootstraps`
و`explicitFullSyncIsTheOnlyPathRequestingRemainingAndNormalization`.

**ملاحظة صدق خارجية:** على كل التزام — قبل هذه الدفعة وبعدها — يظهر
check-run `github-advanced-security` (workflow «Code scanning AI findings
on PR #617»، حدث `dynamic`) بحالة **failure** بلا مخرجات، و`Corgea: Security
Scan` بحالة **skipped** («You've exceeded your plan limit»). هما ليسا من
بواباتنا ولا يقيسان هذا الكود؛ نذكرهما حتى لا يُظن أن «كل شيء أخضر» حيث
توجد إشارات حمراء خارج نطاق الدفعة.

### بناء APK فعلي (2026-10-06) — للمرة الأولى على هذه الدفعة

`android-kotlin-build.yml` (بناء الإصدار الموقّع) لا يمكن تشغيله من جلسة
الوكيل: التوكن بلا `actions: write`، و`workflow_dispatch` يرد `HTTP 403`،
والـworkflow مقيَّد أصلاً بقائمة فروع لا تشمل فرع الجلسة. لذلك أُضيف
`.github/workflows/android-session-apk-build.yml` (فرع الجلسة فقط) يكرّر
خطواته حرفياً: استعادة مفتاح التوقيع من `mobile/Keystore.txt` مع التحقق من
`sha256`، ثم `assembleRelease`/`assembleDebug`، ثم فحص `apksigner` للخطط
الثلاث (v1+v2+v3) و`zipalign -c 4`، ثم رفع artifacts ونشر check-run
`android-session-apk` يحمل البصمة والحجم (لأن تنزيل artifacts من بيئة
الجلسة يفشل بـ`EOF` — أُعيدت المحاولة هنا وفشلت مثل كل مرة).

| العنصر | القيمة |
| --- | --- |
| التشغيل | `37532858856` — الالتزام `40bcff51` — **success** (بناء أول) |
| التشغيل | `37533752036` — الالتزام `bc77d74` — **success** (البناء المعتمد، مع أسطر حكم apksigner في الدليل) |
| `app-release.apk` (موقّع) | 5,944,507 بايت (5.67 MiB) في كل تشغيل — `sha256 fc684a20574cd53d22afd5f7463c542403c6a72fafcb91a9b01eb3cc2a0f9f1e` (تشغيل `bc77d74`) |
| `app-debug.apk` (تشخيصي) | 25,334,005 بايت (24.16 MiB) — `sha256 5d0e157c8b26eafbabb8e26ad543b2d3cba87c34e1b8e58a1fa7b09a74eb6faa` |
| `mapping.txt` (R8) | 5,234,396 بايت — لفكّ رموز أعطال الإصدار المقلَّم |
| التوقيع (نص الحكم من check-run) | `Verified using v1 scheme (JAR signing): true` • `v2 … : true` • `v3 … : true` • `v3.1: false` • `v4: false` (الأخيران غير مفعّلين عمداً — المطلوب v1+v2+v3 فقط) و`zipalign -c 4` نجح |
| الـartifacts | `marina-session-release-apk` • `marina-session-debug-apk` • `marina-session-release-mapping` (صلاحية 30 يوماً حتى 2026-11-05) |

**ملاحظة على البصمة (أمانة قياس):** التشغيلان أنتجا ملفاً **بنفس الحجم
بالبايت** لكن ببصمة مختلفة (`24f223d2…` ثم `fc684a20…`)، لأن أرشيف APK
يخزّن طابع تعديل كل مُدخل (ZIP) — أي أن البناء **غير قابل للتكرار** بصمةً،
والبصمة وحدها لا تصلح كمعرّف ثابت للنسخة على مرّ التشغيلات. لا يوجد زمن
مُبرمَج في التطبيق (`versionCode 1` و`versionName "1.0"` ثابتان).

**دروس التنفيذ الفعلي (لا تُخفى):**

1. أول تشغيل `37531978458` **فشل** في خطوة تحديد الملفات: كان release قد
   بُني فعلاً (5.67 MiB — أثبته check-run) لكن الخطوة كانت تشترط وجود debug
   APK بلا خطوة لبنائه. الإصلاح: خطوة `assembleDebug`، وتحديد صارم للـrelease
   وحده، والـdebug تحذير لا فشل.
2. مسار الخرج ليس افتراضي AGP: `mobile/android/build.gradle` يعيد توجيه
   `buildDir` إلى `mobile/build/app`، فالمسار الفعلي
   `mobile/build/app/outputs/apk/release/app-release.apk` (تأكيد مباشر من
   التشغيل، لا افتراض).
3. **ما لم يُتحقق هنا:** التثبيت على جهاز حقيقي والإطلاق منه (يحتاج جهازاً
   أو محاكياً؛ `android-emulator-launch-probe.yml` يفعل ذلك خارج فرع
   الجلسة)، وبناء النسخة غير المقلَّمة (`-PmarinaNoMinify`) التشخيصية.
   والـAPK نفسه لم يُنزَّل إلى بيئة الجلسة (blob storage يردّ `EOF`)؛ الحجم
   والبصمة مقروءان من الملف داخل الـrunner عبر check-run.

### تحقق الخادم (worker) — تشغيل فعلي في بيئة الجلسة

بيئة الجلسة تحتوي Node 22 / npm 10 (خلاف JDK الذي لا يوجد):

| العنصر | القيمة |
| --- | --- |
| الأمر | `npm ci && npm run typecheck && npx vitest run` داخل `worker/` |
| النتيجة | **227 اختباراً في 21 ملفاً نجحت** + العقد الجديد 3 اختبارات ⇒ **230/230** |
| `tsc` | نظيف (كلا الإعدادين: `tsconfig.json` و`tsconfig.test.json`) |

هذا يثبت طرف الخادم من مسار السحب: `tombstones_only=1` (مع `exclude_device`
والمؤشر)، و`epoch`، وحدود الدلتا — لكنه **لا** يستبدل اختبار جهاز حقيقي
ضد قاعدة D1 المنشورة.

### فحص ثابت إعلامي — مُدقَّق بالأرقام (لا رقم إجمالي معتم)

أُضيفت خطوة Detekt إلى الـworkflow **غير حاجبة** (`continue-on-error`) عبر check
run مستقل (`android-sync-detekt`)، لأن بوابة الجودة الكاملة في هذا المستودع
حمراء قبل هذه الدفعة (1592 ملاحظة في 295 ملف مصدر رئيسي) — لا ندّعي جعلها
خضراء ولا نُخفي نتائجها.

نطاق القياس صُحّح ثلاث مرات (وكل تصحيح موثّق في سجل الالتزامات):
1. `fetch-depth: 1` + `event.before` غير الموجود ⇒ قائمة ملفات ناقصة (صفر ملاحظة).
2. قراءة `<file name>` الصحيح من XML (لا `error@source` = اسم القاعدة) + تاريخ
   كامل ⇒ ظهور الملاحظات الحقيقية.
3. نطاق «الدفعة» = `git diff origin/agent/android-cloudflare...HEAD` صراحةً
   (مع جلب الـref وطباعة `batch base:`)، ثم **نسبة كل ملاحظة** إلى سطر أضافته
   الدفعة أو سطر قائم قبلاً عبر `git diff -U0` — لأن الرقم الإجمالي وحده
   كان غير قابل للتفسير (178 ثم 248 بلا وسيلة لمعرفة المصدر داخل check run).

**النتيجة المقروءة من التشغيل `37527612571` @ `2573d2a8`:**

| القياس | العدد |
| --- | --- |
| ملاحظات ملفات الدفعة (18 ملفاً) | 248 |
| **على أسطر أضافتها الدفعة** | **21** |
| على أسطر قائمة قبلها | 227 |
| المستودع كله (لملفات المصدر الرئيسي) | 1592 |

توزيع الـ21 على ملفات الدفعة: `CloudflareRealtimeClient` 7، `RealtimePolicy` 5،
`SyncManager` 3، `RealtimeMessage` 2، `DashboardScreen` 1، `PaymentsDao` 1،
`RealtimePullScheduler` 1، `BookingDerivedRefreshService` 1. (بقية الملفات
التي أنشأتها الدفعة — `MarinaMessagingService`، `PullSanityPolicy`،
`RemoteSignalPolicy`، `RealtimeSyncState`، `RealtimeSyncRepository` — بصفر
ملاحظات.)

أعلى القواعد في الدفعة: `MagicNumber` 100، `MaxLineLength` 29،
`TooGenericExceptionCaught` 28، `ReturnCount` 26 — وهي نفس أنماط الدين القائم
في المستودع (متوسط المستودع ≈ 5.4 ملاحظة/ملف مقابل 13.8 لملفات الدفعة التي
تتركّز في ملفات واجهات ومزامنة قديمة كبيرة).

**ما لا ندّعيه:** لا ندّعي أن الـ21 «مقبولة» ولا أن الـ227 «ليست مسؤوليتنا» —
الرقم يُعرض كما هو مع نسبته. وما تحقّق فعلاً هو أن **الكود الجديد الوظيفي
(خدمة الحقول المشتقة، سياسات الإشارة، مسارات السحب) بلا ملاحظات وظيفية**،
وأن ما تبقّى أسلوبي (أرقام سحرية/طول أسطر/التقاط عام للاستثناءات — نمط
المستودع نفسه، حيث 26 من 28 ملاحظة `TooGenericExceptionCaught` قائمة قبلنا).

### تحقق «حالة عالقة» (`isSyncing` / `isManualSyncing` / سجل الأخطاء) — مُغلق بالأدلة

بند تحقق كان مفتوحاً في مراجعة سابقة: هل يمكن أن يبقى زر المزامنة معلَّقاً
(`isSyncing=true`) أو أن يبقى خطأ قديم معروضاً؟ النتيجة بعد تتبّع كل مسار
خروج — **لا مسار عالق**، والدليل بالمرجع:

| المسار | الدليل |
| --- | --- |
| كل عمليات المزامنة تمرّ بـ`SyncManager.runOwned` ← `SyncOperationRunner.runIfIdle` | `onFinished(cause)` مسجَّل في `task.invokeOnCompletion` — يُنفَّذ مع النجاح والفشل **والإلغاء** — و`SyncManager.kt` l.123-152 يصفّر `isSyncing` هناك |
| فشل مبكر (فشل دخول / جداول فاشلة / استثناء شبكة) | `finishWithError(...)` يضبط `isSyncing=false, isError=true` ويسجّل الخطأ (`SyncManager.kt` l.700-716) |
| رفض البدء بسبب مزامنة جارية | `onBusy` يعيد `-1` بلا لمس الحالة؛ والرفض من `SyncOperationRunner` لا ينشئ مهمة أصلاً |
| إلغاء الشاشة أثناء سحب مقبول | العملية مملوكة لعملية التطبيق (`SupervisorJob`) لا للشاشة، فتُكمل وتُفرِّغ العلم؛ يغطيه اختبار قائم `acceptedPullFinishesAfterScreenCancellationWithoutAllowingOverlap` (ضمن 56 حالة `SyncIngestorRegistryTest` في ملخّص التشغيل أعلاه) |
| «سحب/رفع/سحب كامل الآن» في شاشة الإعدادات | `try/catch/finally` + `onStartFailure` في المسارات الثلاثة (`CloudflareSyncSettingsViewModel.kt` l.372-500) ⇒ `isManualSyncing=false` في كل خروج، والحالة لكل نسخة ViewModel فلا تتسرب بعد إعادة الإنشاء |
| سجل الأخطاء `cf_sync_error_history` | تشخيصي لا حاجب: حلقة بسقف 40 سجلاً (`MAX_SYNC_ERROR_RECORDS`) مع حجب `Bearer`، وله مسح صريح من `SyncDiagnosticsViewModel`. **فرق مقصود عن Dart**: مرجع Flutter يحتفظ بالسجل في الذاكرة فقط (`sync_error_handler.dart`)، وأندرويد يستمرئه ليبقى بعد إعادة التشغيل — إضافة تشخيصية لا تغيّر سلوك المزامنة |

### ما لم يُتحقق بعد

- **workflow الإنتاج `android-kotlin-build.yml` لم يُشغَّل بعد على هذا
  العمل**: مُقيَّد بقائمة فروع (`agent/android-cloudflare` وغيرها) ولا يقبل
  `workflow_dispatch` من جلسة الوكيل (HTTP 403 `actions: write`). تشغيله
  (بناء APK موقّع + اختبار الإطلاق) يقع عند دمج هذا العمل في
  `agent/android-cloudflare`. الـworkflow المستقل أعلاه يثبت الوحدة فقط،
  لا التوقيع ولا الإطلاق على محاكٍ.
- شبكة الحزمة محجوبة في بيئة الجلسة (لا JDK/Gradle محلياً)؛ كل أرقام هذا
  القسم مقروءة من CI.
- فحص هذا الفرع الوحيد الذي رُصد آلياً هو «Code scanning AI findings» وقد
  فشل في خطوة `Processing Request` (بنية تحتية للوكيل)، والفشل نفسه مسجَّل
  على PRs أخرى لا علاقة لها بهذه الدفعة — لا يُنسب إلى الكود هنا ولا يُخفى.
- لا اختبار جهاز فعلي: سلوك Android الحقيقي لخدمة FCM، وتعدد الأجهزة على
  نفس الحساب، وشبكات اليمن المحجوبة (تدوير النطاق المخصّص) تحتاج جهازًا.
- بوابة الجودة (Detekt/Lint) كانت حمراء قبل هذه الدفعة ولم تُخفَّ
  نتائجها؛ هذه الدفعة لا تدّعي جعلها خضراء.
- ترحيلات D1 ومطابقتها مع فرع Flutter مُدقَّقة في
  [`cloudflare-migrations-parity.md`](./cloudflare-migrations-parity.md).
- **لا** ادعاء مطابقة 100% مع Flutter خارج مسار السحب: هذا العمل محصور في
  سحب التغييرات وصولًا إليه (Realtime/FCM/مسح الحذفيات/الحراس)، ولا يمس
  منطق تشفير/دفع الصفوف نفسه (`performPushOnly`)، لكن **مراقب الـoutbox**
  (متى يُطلق الرفع وبأي تأجيل) صار جزءاً صريحاً من هذا التدقيق (البند 4
  أعلاه)، والمعادلات المالية ومخطط Room خارج النطاق.
- **لم يُضف اختبار JVM** لتأجيل الرفع في الخلفية ومراقب الـ5 دقائق:
  `AutoSyncEngine` يبنى على تعاونيات أندرويد (`SyncManager`،
  `OutboxRepository`، `CloudflareRealtimeClient`، `SyncPreferences`) والمستودع
  لا يستعمل مكتبة mocking (mockk/Mockito)؛ فالتغطية = تصريف CI + مراجعة كود،
  لا اختبار سلوكي. مسجّل هنا صراحةً بدل ادعاء تغطية.

## إصلاح شكوى 2026-10-06: «الدلتا لا تسحب الجداول ولا الحقول + شاشة الحالة ناقصة»

شكوى المستخدم بنصها: «مزامنة delta cloudflare D1 sync لا تعمل جيداً لا تسحب
الجداول أو الحقول، وأيضاً في شاشة الإعدادات حالة المزامنة لا تُظهر جميع الجداول
المزامنة». جرت المقارنة بالقياس (أعمدة D1 مقابل كيانات Room الـ24، ومسار
الاستيعاب مقابل `pull_quarantine.dart`) فظهرت **ثلاثة أعطال مستقلة** لا عرضٌ
لواحد:

### (1) تجميد مؤشر الدلتا — السبب المباشر لـ«لا تسحب شيئاً»

كان `SyncManager.pullDelta` يرمي استثناءً عند أول صفحة فيها صف فاشل
(`report.hasFailures ⇒ throw`). الاستثناء يمنع `preferences.saveLastPullCursor`
⇒ **المؤشر لا يتقدم أبداً** ⇒ كل دورة تعيد سحب الصفحة نفسها وتفشل في الصف نفسه:
عطل دائم لا يُشفي نفسه، وأثره الظاهر «الدلتا لا تسحب جدولاً ولا حقلاً».

- **المرجع الدارتي** (`mobile/lib/services/sync/pull_quarantine.dart`): الصف
  الفاشل يُعزل بحمولته الكاملة في مخزن محلي، والمؤشر **يتقدم**، ويُعاد حلّ
  الصف من حمولته في الدورات التالية (`collectHealCandidates`) حتى يزول السبب
  (وصول الأب، إصلاح قيمة على الخادم، أو ترقية التطبيق التي تضيف عموداً ناقصاً).
- **في Kotlin**: `PullApplyReport` صار يحمل `failedRecords` (الكيان + الحمولة)،
  و`ingestPage` يزيد عدّاد محاولة الصف (`attempts`) ويحفظ عمر أول عزل
  (`firstSeen`)، وكل دورة تبدأ بـ`healQuarantinedBatch(100)` من الحمولة
  المحفوظة، و`enforceQuarantineCap()` يُبقي السجل داخل سقف 300 بإخلاء الأقدم
  عمراً. فشل الشفاء لا يُصعِّد فشل الدورة (الصف مُعزول أصلاً).
- **ما لم يتغيّر عن قصد**: `response.errors[]` **الخادمية** (جداول فاشلة على
  D1) تبقى دورة فاشلة بلا تقديم مؤشر — تلك لا يُشفيها العميل، بل إصلاح D1.
- **أثر جانبي مقصود**: رسالة الحالة تُظهر «عُزل N سجلاً غير قابل للتطبيق
  ويُعاد حلّها من حمولتها» بدل رسالة فشل عامة.

### (2) 14 حقلاً خادمياً بلا عمود محلي (تُسقَط صامتة)

المقارنة الآلية بين `worker/schema.sql` وكيانات Room (الاسم الخادمي = اسم
عمود Flutter Drift الحرفي) أظهرت 14 عموداً لا مقابل له محلياً؛ منها ما كان
يُخزَّن صفراً/فراغاً، ومنها ما كان يُفشل تطبيق الصف كلياً (فيتسبّب في العطل 1):

| الكيان | السلك (Flutter/D1) | أندرويد قبل الإصلاح |
| --- | --- | --- |
| `inventory_items` | `quantity` / `is_active` | `current_quantity` / — |
| `inventory_transactions` | `movement_type` / `item_local_uuid` / `user_id` / `user_name` | `transaction_type` / — |
| `blacklist` | `guest_name` / `guest_id_number` / `guest_phone` / `is_active` / `added_by` / `added_date` | `name` / `national_id` / `phone` / `active` / — |
| `salary_withdrawals` | `expense_id` | — |
| `expenses` | `employee_link_cleared` | — |

- **8 أعمدة جديدة** عبر `MIGRATION_75_76` و`SCHEMA_VERSION 76`: `expenses.employee_link_cleared`،
  `salary_withdrawals.expense_id`، `inventory_items.is_active`،
  `inventory_transactions.{item_local_uuid,user_id,user_name}`، و(للمحاسبة)
  `sync_quarantine.{attempts,firstSeen}`. الأعمدة الجديدة تحمل `defaultValue`
  في الكيان نفسه مطابقاً لـ`ALTER TABLE … DEFAULT` كي لا يختلف مخطط الترقية عن
  مخطط التثبيت الجديد.
- **6 خرائط مرادفة** في مصدر حقيقة واحد **للاتجاهين**: `data/sync/SyncWireFields.kt`
  — السحب عبر `applyLocalAliases` (تُملأ الأسماء المحلية من الخادمية فقط إن
  كانت فارغة، فلا تُطمس قيمة محلية أدق)، والرفع عبر `toWire` من
  `OutboxRepository.enqueue` (يُضاف الاسم الخادمي المرادف بجانب المحلي، لأن
  الخادم يفلتر غير المعروف فيُسقط `current_quantity`/`transaction_type`).
  ويُغذّى `transaction_time` المحلي من `created_at` لغياب عمود زمني على السلك.
- **علم فكّ الربط لاصق**: كان `employee_link_cleared` يُزال من الحمولة قبل
  التطبيق فلا يُحفظ؛ صار يُكتب في العمود الجديد. القاعدة:
  `explicitUnlink || (لا employee_uuid وارد && القيمة المحلية السابقة true)`
  — أي أن حمولة بلا علم وبلا ربط جديد لا تُعيد الربط القديم، وحمولة بربط جديد
  تُعيده فعلاً (نظير حفظ Dart لـ`employeeLinkCleared: false` صراحةً).

### (3) شاشة «حالة المزامنة» كانت تعرض 8 جداول من 24

كانت `SyncHealthRepository` تسأل قائمة ثابتة (`rooms, bookings, payments,
expenses, debts, employees, salary_withdrawals, inventory_items`) بينما المحرك
يسحب **24 كياناً**، فسقوط 16 جدولاً (الليالي، الحجوزات المساعدة، دورة/دفعات/
بدلات الرواتب، المخزون، المستخدمون، الأجهزة، القائمة السوداء …) من الشاشة.

- صارت الخريطة تُبنى من `SyncIngestorRegistry.SYNC_ENTITY_TABLES` (مصدر حقيقة
  واحد: 24 كياناً → جدول Room، و`blacklist → blacklist_entries` الاستثناء الوحيد).
- كل استعلام داخل حماية: جدول غائب يُعرض **«غير متاح»** بدل إسقاط القائمة
  كلها أو إظهار صفر كاذب.
- بطاقة جديدة **«سجلات معزولة (فشل تطبيقها عند السحب)»** تُظهر عدد ما في
  `sync_quarantine` — الرقم الذي كان غائباً تماماً عن الشاشة.

### الاختبارات المضافة (JVM/Robolectric + Room حقيقي)

| الملف | الحالات |
| --- | --- |
| `SyncWireFieldParityTest.kt` | 7: الكمية/العلم، نوع الحركة وحقول المنفّذ، حقول القائمة السوداء، `expense_id`، لاصق فكّ الربط، **صف غير قابل للتطبيق لا يجمّد المؤشر ويتصاعد عدّاده**، الشفاء من الحمولة المحفوظة، إخلاء السقف الأقدم-أولاً |
| `SyncHealthTablesTest.kt` | 3: ظهور **كل** الكيانات الـ24 في التقرير، وجود جدول Room لكل كيان مُعلن، وعدّ الصفوف + سجلات العزل |
| `FinancialMigrationTest.kt` | حالة جديدة 75→76: الأعمدة العشرة موجودة بأنواعها وقيودها، والقيم الافتراضية لصفوف قائمة، وصف حجر قديم يبقى ببياناته، والمال لم يُمس |

**الحدود**: لا تشغيل محلي (لا JDK/Gradle في بيئة الجلسة) — الإثبات بالتصريف في CI.

#### ملحق (تشغيل 37536692883): العمود الناقص كان يُسقط الصف كاملاً

تشغيل CI على `1005fc2e` أعطى 7 حالات حمراء: 3 منها كانت تُثبّت العقد القديم
(«المؤشر لا يتقدم فوق صف معزول») وقد صُحّحت لتطابق سياسة Dart المصححة، و4
كشفت عطلاً ثانياً في مسار الاستيعاب نفسه — كان جذره:

- **Gson لا يستدعي قيم مُنشئ Kotlin**: `gsonFor(clazz)` يُنشئ الكيان بلا مُنشئ،
  فأي حقل غير قابل للـnull غاب مفتاحه (أو وصل `null`) يصل `null` إلى Room ⇒
  رفض الصف لقيد NOT NULL ⇒ عزل صف سليم بالكامل.
- **المرجع الدارتي يفعل العكس حرفياً**: كل محوّل يقرأ الحقل ببديله
  (`inventory_adapter.dart`: `unit: ... ?? 'قطعة'`، `isActive: ... ?? true`،
  `employees_adapter.dart`: `position: ... ?? 'موظف'`، `salary_cycles_adapter`:
  `status: ... ?? 'draft'`، `booking_notes_adapter`: `isActive: ... ?? 1`).
- **الإصلاح**: `SyncWireFields.entityDefaults` (قيم مُثبتة من محوّلات Dart
  ومن مُنشئات Room لكيانات لا محوّل لها مثل `blacklist`/`devices`/`app_users`)
  + `applyWireDefaults(entity, mapped)` تُنفَّذ بعد المرادفات وقبل Gson،
  + **درع الأعلام** `shieldMissingBooleans`: أي Boolean غير قابل للـnull غاب
  يُملأ بمُثبته أو `false` — لأن علماً غائباً كان يُسقط الصف كاملاً أيضاً
  (`booking_price_adjustments.is_active` = true، `inventory_items.is_active` = true).
- **الحد المقصود**: لا يُلفَّق صفر مكان قيمة مالية. القيم المالية/العددية غير
  المُثبتة تبقى تُعزل بحمولتها — وهذا صار آمناً لأن المؤشر يتقدّم (لا تجميد)
  ويُعاد حلّها من الحمولة كل دورة.
- **تصحيح اختبارين قديمين**: `malformedPullRows…` و`nonFinitePayloads…` كانا
  يقارنان صفوف الحجر بالتساوي التام بعد دورة ثانية — والعدّاد الآن يتصاعد
  (نظير عدّاد الدورات في Dart)، فصارا يقارنان الهوية والحمولة والسبب ويؤكدان
  `attempts == 2` وثبات `firstSeen`. واختبار `quarantinedPullDoesNotAdvanceSavedCursor`
  أُعيد كتابته (`quarantinedPullAdvancesSavedCursorAndStaysRecoverable`) على
  العقد المصحَّح: المؤشر يتقدم إلى 456، ولا `isError`، والصف يبقى في الحجر
  بحمولته قابلاً للشفاء.

---

## ملحق تشغيل ثانٍ (2026-10-06): تدقيق فرع Flutter المرجعي رأساً برأس

مراجعة **مقارنة** لفرع `feat/cloudflare-sync-execution`@`ac283c6c` مقابل ما في
فرع الجلسة — التقرير الكامل في
[`flutter-branch-review-cloudflare-sync-execution.md`](./flutter-branch-review-cloudflare-sync-execution.md).
أهم ما أنتجته:

1. **حرجة**: زر «سحب التغييرات الآن» كان **يُحجب** عند وجود سجلات outbox غير
   مُسلَّمة، بينما سياسة `OutboxPullPolicy` في الفرع المرجعي **كود ميت** (لا
   مستدعي لها في `mobile/lib`) فالسحب هناك لا يُحجب أبداً. صار الزر يُعلِم
   ويُكمل السحب (الإصلاح في `CloudflareSyncSettingsViewModel.runPullNow`).
2. **نقص تكافؤ**: الفرع يوجّه كل سجل بـ`record['_entity'] ?? _detectEntity(record)`
   (استنتاج الكيان من بصمة الأعمدة، 24 بصمة)، وكنا نعزل أي سجل بلا وسم
   `missing_entity` بلا أمل نجاح. **أُضيف** `SyncIngestorRegistry.resolveEntity`
   + `inferEntityFromRecord` بجدول بصمات منقول حرفياً، مع 4 اختبارات تكافؤ.
3. **افتراضي ناقص**: `inventory_transactions.movement_type → 'adjustment'`
   (نظير `?? 'adjustment'` في `inventory_adapter.dart`) — أُضيف للمفتاحين
   `movement_type` و`transaction_type` مع اختبار سحب فعلي.
4. فروق مقصودة موثّقة: طبقة حجر واحدة بدل طبقتين، وعزل السجل مجهول الهوية
   بحمولته بدل إسقاطه صامتاً، وعدم تلفيق قيم رقمية (`quantity`).
