# مواءمة «سحب التغييرات» في أندرويد مع تطبيق Flutter

المصدر المرجعي: `feat/cloudflare-sync-execution`
(`mobile/lib/services/cloudflare_sync_manager.dart` و
`cloudflare_realtime_sync.dart` و`sync/pull_quarantine.dart` و
`sync/pull_apply_rules.dart`)، والمقصد: `agent/android-cloudflare`
(تطبيق Kotlin/Compose الأصلي في `mobile/android`).

## الخلاصة

محرك أندرويد كان يملك أصلًا: مؤشر دلتا محفوظ، epoch، فلتر صدى الجهاز،
سقف 100 صفحة، حجر صحي، روابط أب مؤجلة، `repair_pending`، وتطبيع الطوابع.
هذه الدفعة تنقل العقود الأربعة التي كانت ناقصة فعلاً:

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

اختبار حاكم جديد: `freshDeviceDashboardPullStaysDeltaAndNeverBootstraps`
— جهاز بمؤشر 0 وبلا `full sync` مكتمل يضغط الزر ⇒ الطلب يحمل
`exclude_device=own` وبلا `include_remaining`/`normalize_timestamps`،
و`isFullSyncComplete()` و`isFullReplayPending()` يبقيان `false` بينما
المؤشر يتقدم فعلاً.

**ملاحظة سابقة هذه الجولة**: أعلام `include_remaining`/`normalize_timestamps`/
`tombstones_only` صارت تُرسل نصاً `"1"` (كانت `Boolean` → `"true"`)، لأن
الـ Worker يفحص `=== '1'` حرفياً — وبذلك كان `tombstones_only` يُهمل صامتة
حتى في worker هذا الفرع. التفاصيل في
[`cloudflare-migrations-parity.md`](./cloudflare-migrations-parity.md) §4.

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

أحدث تشغيلين (بعد تدقيق الملفات المتبقية):

| العنصر | القيمة |
| --- | --- |
| التشغيل | `37519136397` — الالتزام `289c31a4` — **success** (المهام الثلاث) |
| التشغيل | `37519764533` — الالتزام `1b6708f3` — **success** (المهام الثلاث) |
| Detekt (ملفات الدفعة) | **178 ملاحظة** (المستودع: 1589) — انظر «فحص ثابت إعلامي» أدناه |
| اختبار هشّ رُصد وأُصلح | `SyncIngestorRegistryTest.threeIndependentPaymentsSurviveRepeatedEditsInPaymentAndIncomeReports`: `expected:<475.0> but was:<400.0>` — كان يقرأ حالة **دورة سابقة** (`state.first { !it.isLoading }`) قبل تطبيق تعديل الدفعة الجديدة. الإصلاح: `awaitSettledReport` ينتظر **تقارب القيمة المتوقعة** نفسها (لا زوال التحميل فقط) ⇒ لا يتحول إلى تخفيف للفحص: التعديل الذي لا يُعكس يبقى فاشلاً بمهلة. |

قبل هذا التشغيل رصد CI الحقيقي — لا المراجعة النصية — ثلاث علل أُصلحت:
خطأان في التصريف (`AutoSyncEngine` صار يأخذ `Lazy<CloudflareRealtimeClient>`
و`Response.error<Unit>`)، وساعة اختبار الجدولة (كانت مربوطة يدوياً فلا
تنقضي التهدئة)، وتوقّع `null` لا `false` لغياب علم `tombstones_only`.
كما كشف اختبار «زر اللوحة على جهاز جديد» أن `deltaOnly` وُضع في
`performSyncNow` بدل `performPullOnly` — فصُحّح ونُقل.

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

### فحص ثابت إعلامي

أُضيفت خطوة Detekt إلى الـworkflow أعلاه **غير حاجبة** (`continue-on-error`)
تُظهر ملاحظات Detekt على ملفات هذه الدفعة فقط عبر check run مستقل
(`android-sync-detekt`)، لأن بوابة الجودة الكاملة في هذا المستودع كانت
حمراء قبل الدفعة — لا ندّعي جعلها خضراء ولا نُخفي نتائجها.

نطاق القياس نفسه صُحّح مرتين، لأنه هو ما جعل الأرقام السابقة مضللة:
1. كانت الخطوة تستنسخ `fetch-depth: 1` وتقرأ `git diff` ضد `event.before`
   غير الموجود ⇒ ملفات «الدفعة» كانت ناقصة (صفر ملاحظة).
2. ثم صارت تقرأ `<file name>` الصحيح من XML (لا `error@source` = اسم القاعدة)
   وتستنسخ بتاريخ كامل — فظهرت الملاحظات الحقيقية.
3. الآن نطاق «الدفعة» = فرق الفرع عن `agent/android-cloudflare` صراحةً (مع
   جلب الـref وطباعة `batch base:` في السجل)، لا ما تغيّر في آخر push فقط.

هذه 178 ملاحظة **دين قائم في ملفات عدّلتها/لمستها الدفعة** أكثرها في واجهات
قديمة (`DashboardScreen.kt` وغيرها)، وليست مقدمة من هذه الدفعة؛ لكن الرقم
يُعرض كما هو ولا يُطمث.

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
