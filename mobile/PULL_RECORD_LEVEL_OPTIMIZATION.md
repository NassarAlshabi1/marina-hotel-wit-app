# تقليل السحب (Pull) عبر Realtime على مستوى الكيان/السجل — Appwrite Delta Sync

> **مسودة للمراجعة** — تحليل مرتكز على الكود الفعلي (لا تخمين).
> النطاق: مجلد `mobile/`، مسار السحب في مزامنة Appwrite (push/pull) مع **جعل
> Appwrite Realtime على الكيانات هو محور تقليل السحب**.
> التاريخ: 2026-08-30.
> تُكمّل هذه الوثيقة `PULL_OPTIMIZATION_ANALYSIS.md` و`PULL_RECORD_LEVEL_OPTIMIZATION`
> السابقة، لكنها تعيد ترتيب الأولويات حول التنفيذ عبر Realtime.

---

## 0. الخلاصة التنفيذية

الفكرة الجوهرية: **بدل سحب كل الكيانات دورياً بحثاً عن تغييرات، ندع الخادم يُخبرنا
بالتغيير لحظةَ حدوثه عبر Realtime، ونطبّقه على مستوى السجل مباشرةً.** هذا يحوّل النظام
من *poll-based* (سحب أعمى دوري) إلى *push-based* (تطبيق موجّه بالحدث).

الوضع الحالي: `AppwriteRealtimeSync` موجود لكنه:
1. **معطّل افتراضياً** (`appwrite_realtime_ws_enabled = false`، `appwrite_realtime_sync.dart:78-79`).
2. **لا يطبّق السجل المتغيّر** — يرفع علامة UI فقط (`hasRemoteChanges = true`) ويزيد
   عدّاداً، ثم يترك السحب الفعلي لـ auto-sync الذي يسحب **الـ22 كياناً كاملةً**
   (`appwrite_realtime_sync.dart:205-221`).
3. **رسالة Realtime تحمل السجل كاملاً** (`message.payload`) وتحدّد الكيان والعملية
   (`message.events`) — لكن هذه البيانات تُهمَل حالياً وتُختزل إلى مجرّد «علامة تغيير».

النتيجة: أثمن ما في Realtime (السجل + هويّة الكيان) يُهدَر، ويظلّ السحب الأعمى قائماً.

**التوصية:** استغلال حمولة Realtime على مرحلتين:
- **المرحلة A — سحب موجّه:** الحدث يُعلّم الكيان المتأثّر «متّسخاً» فقط، فيسحب النظام
  الكيانات المتّسخة فقط بدل الـ22 (طلبات 22 → المتغيّر فقط).
- **المرحلة B — تطبيق موجّه بالحدث:** تطبيق السجل مباشرةً من `message.payload` عبر
  نفس خط الأنابيب (conflict → upsert)، فيُلغى طلب السحب لذلك السجل نهائياً (يصل السجل
  مرة واحدة بحجمه فقط، بلا نافذة إعادة سحب ولا مسح حقول كامل).

مع إبقاء **سحب دوري احتياطي (backstop)** للمصالحة عند انقطاع الاتصال أو فقد الأحداث.

---

## 1. الوضع الحالي لـ Realtime (مؤكَّد من الكود)

الملف: `lib/services/appwrite_realtime_sync.dart` (singleton).

### 1.1 الاشتراك
- يشترك في قنوات مستندات **18 مجموعة** (`_collections`, `:37-57`):
  rooms, bookings, booking_notes, booking_nights, payments, expenses,
  cash_transactions, debts, employees, salary_cycles, salary_payments,
  salary_withdrawals, shift_notes, guest_infos, price_adjustments,
  booking_price_adjustments, audit_logs, payment_voids.
- صيغة القناة: `databases.{db}.collections.{collectionId}.documents` (`:89-94`).

### 1.2 معالجة الحدث `_onEvent` (`:163-222`)
```dart
final payload = message.payload;                       // ← السجل الكامل (يُهمَل!)
final sourceDevice = payload['device_id'] ?? payload['lastModifiedBy'];
if (sourceDevice == _currentDeviceId) return;          // ✅ كبح الصدى الذاتي
final isDataChange = eventTypes.any((e) =>
  e.endsWith('.create') || e.endsWith('.update') || e.endsWith('.delete'));
...
_debounceTimer = Timer(500ms, () {
  hasRemoteChanges.value = true;                        // ← فقط علامة UI
  pendingRemoteChangesCount.value++;                    // ← فقط عدّاد
});
```
**الخلاصة:** الحدث يُختزل إلى علامة + عدّاد. لا `upsert`، لا استخدام للـ payload، لا
تحديد للكيان المتأثّر. السحب الفعلي يبقى أعمى وكاملاً عبر auto-sync.

### 1.3 المتانة الموجودة (نُعيد استخدامها كما هي)
- **إعادة اتصال بـ backoff أسّي** (5s→60s، حدّ 6 محاولات، `:247-299`).
- **fallback إلى polling** كل 30ث عند تعطّل WebSocket (`:131-156`) — يرفع علامة فقط.
- **كبح الصدى الذاتي** عبر `device_id`/`lastModifiedBy` (`:172-174`).
- **تتبّع آخر `$updatedAt` من الخادم** (`_lastServerUpdate`, `:191-233`) — مفيد جداً
  كمؤشّر مصالحة (انظر 3.4).
- تصفية الأحداث غير البياناتية (permissions…) (`:176-189`).

### 1.4 فجوات التغطية (مهمّة للتصميم)
- **4 كيانات مسحوبة غير مشمولة بـ Realtime:** `inventory_items`,
  `inventory_transactions`, `blacklist`, `salary_carry_over_logs`
  (موجودة في حلقة السحب الـ22 لكنها غائبة عن `_collections` الـ18).
  → تبقى بحاجة لسحب دوري، أو تُضاف لقائمة Realtime.
- **معطّل افتراضياً** — يتطلب رفع `appwrite_realtime_ws_enabled`.
- **الاعتماد على `device_id` في الحمولة** — يجب ضمان أن كل مستند يُكتب في Appwrite
  يحمل `device_id`/`lastModifiedBy` وإلا فشل كبح الصدى (تحقّق مطلوب).

---

## 2. لماذا يبقى السحب الحالي مهدراً (تشخيص مستوى السجل)

هذه المصادر قائمة **حتى مع تفعيل Realtime الحالي**، لأن Realtime لا يطبّق شيئاً:

1. **22 طلب/دورة** حتى بلا تغييرات — حلقة السحب تستعلم كل كيان دائماً
   (`appwrite_sync_manager.dart:1044-1633`).
2. **حمولة كاملة لكل سجل** — لا `Query.select()` في مسار السحب رغم دعمه (appwrite ^21،
   مستخدم في `advanced_query_builder.dart:180`).
3. **نافذة أمان 15ث** (`sync_pull_service.dart:421,457`) تُعيد سحب سجلات مطبّقة كل دورة.
4. **watermark عالمي واحد** (`SyncState.lastPullTs`) لا يتقدّم إلا بنجاح الدورة كاملة
   (`appwrite_sync_manager.dart:1668-1700`) → فشل كيان يُعيد سحب الجميع.
5. **delta لا يستبعد tombstones** (بخلاف full، `sync_pull_service.dart:430-432`).

Realtime المطبَّق على مستوى الكيان/السجل يعالج (1) جذرياً، ويقلّل أثر (2)–(5) لأنه
يستبدل معظم دورات السحب بتطبيق موجّه بالحدث.

---

## 3. التصميم المقترح: Realtime على الكيانات كمحور لتقليل السحب

### 3.1 المرحلة A — سحب موجّه بالكيان المتّسخ (Targeted Pull) ⭐ أول خطوة

بدل رفع علامة عامة، يستخرج `_onEvent` **معرّف الكيان** من سلسلة الحدث ويعلّمه «متّسخاً».

صيغة الحدث في Appwrite:
`databases.{db}.collections.{collectionId}.documents.{docId}.{create|update|delete}`
→ يمكن استخراج `collectionId` (ومنه اسم الكيان عبر عكس `AppwriteConfig.collectionIds`).

```dart
// تعديل مقترح داخل _onEvent
final dirtyCollectionId = _extractCollectionId(message.events); // parse من events
if (dirtyCollectionId != null) {
  _dirtyEntities.add(_entityNameFor(dirtyCollectionId));
}
// ثم: sync يسحب _dirtyEntities فقط بدل الـ22
```

- **الأثر:** طلبات 22 → عدد الكيانات المتّسخة فقط (غالباً 1–3/دورة).
- **يتكامل مع:** watermark لكل كيان (المرحلة C) لسحب دلتا الكيان المتّسخ فقط.
- **الخطر/التحقق:** عند فقد أحداث (انقطاع)، لا نعرف ما اتّسخ → يعالجها backstop (3.4).

### 3.2 المرحلة B — تطبيق موجّه بالحدث (Event-Driven Apply) ⭐⭐ الأعمق

طبّق السجل مباشرةً من `message.payload` عبر **نفس** خط أنابيب السحب، فيُلغى طلب الشبكة
لذلك السجل تماماً:

```dart
// بدل رفع علامة فقط:
final entity = _entityNameFor(collectionId);
final applied = await _pullService.checkAndResolveConflict(
  entity: entity, remoteData: payload, /* local lookup by localUuid */
);
if (applied.shouldApplyRemote) {
  await _adapterRegistry.forEntity(entity)
      .upsertFromJson(payload, src: Source.appwrite);   // نفس مسار السحب
  await _pullService.updateEntityPullTs(entity, _extractUpdatedAtSec(payload));
}
```

- **الأثر (مستوى السجل):** السجل المتغيّر يصل **مرة واحدة بحجمه فقط**، فوراً، بلا:
  - طلب `listDocuments` (0 طلب سحب لهذا التغيير)،
  - نافذة إعادة سحب 15ث،
  - مسح حقول كامل (رغم أن الحمولة كاملة، فهي سجل واحد لا صفحة 100).
- **إعادة الاستخدام:** يمرّ عبر `checkAndResolveConflict` (`sync_pull_service.dart:78-290`)
  و`upsertFromJson` و`RemoteChangeNotificationService` — أي بلا منطق تعارض جديد.
- **المخاطر الجوهرية والتحقق:**
  - **ترتيب FK:** الأحداث تصل بترتيب عشوائي (قد يصل payment قبل booking). الحل:
    عند فشل FK، أدرِج السجل في «طابور مؤجّل» وأعد المحاولة، أو اسقط لـ **سحب موجّه**
    (المرحلة A) لذلك الكيان بترتيب `SyncConstants.tableOrder`.
  - **فقد الأحداث/الانقطاع:** لا ضمان تسليم في Realtime → **إلزامي** وجود backstop (3.4).
  - **كبح الصدى:** يعتمد على `device_id` في الحمولة (قائم `:172-174`) — تحقّق من وجوده
    في كل كتابة.
  - **الحذف:** حدث `.delete` قد لا يحمل الحقول كاملة → عالِج كـ tombstone عبر
    `localUuid`/`$id` فقط (احترام «durable remote tombstone»، `sync_pull_service.dart:99-117`).

### 3.3 المرحلة C — دعائم مستوى السجل المكمّلة

تبقى نافعة لدورات السحب الاحتياطية (backstop) وللكيانات غير المشمولة بـ Realtime:
- **watermark مستقل لكل كيان** (تعميم نمط `booking_nights`, `sync_pull_service.dart:490-503`)
  — ضروري ليعمل السحب الموجّه (A) دون إعادة سحب البقية.
- **Field Projection عبر `Query.select()`** — يقلّل بايتات backstop pull.
- **استبعاد tombstones القديمة من delta**.
- **إنهاء مبكر عند 0 مستند**.

### 3.4 السحب الاحتياطي للمصالحة (Reconciliation Backstop) — إلزامي

Realtime «أفضل جهد» (best-effort): تُفقَد أحداث أثناء الانقطاع/الخلفية. لذا:
- عند **إعادة الاتصال** أو **العودة للمقدّمة**: نفّذ **سحباً دلتا موجّهاً منذ
  `_lastServerUpdate`** (متتبَّع أصلاً `:191-233`) أو منذ آخر watermark، لسدّ الفجوة.
- **سحب دوري نادر** (مثلاً كل 30–60 دقيقة بدل الحالي) كحزام أمان نهائي.
- الكيانات الأربعة غير المشمولة بـ Realtime تُسحب دلتا دورياً حتى تُضاف لقائمة القنوات.

هذا يحفظ **القيد الأول: عدم فقدان أي سجل** مع خفض تردّد السحب الكامل جذرياً.

---

## 4. جدول الأثر (تقديري ومتحفّظ)

| المرحلة | الآلية | مستوى التقليل | الأثر | الكلفة | الخطر |
|---------|--------|----------------|-------|--------|-------|
| A — سحب موجّه | تعليم الكيان المتّسخ من الحدث | طلبات/دورة | مرتفع (22→المتغيّر) | متوسطة | متوسط |
| B — تطبيق موجّه | upsert من payload مباشرةً | طلبات + بايتات/سجل | الأعلى (يُلغي السحب لكل حدث) | متوسطة–عالية | متوسط–عالٍ (FK/فقد أحداث) |
| C — watermark/كيان | مؤشّر مستقل | إعادة السحب عبر الكيانات | مرتفع عند الفشل | متوسطة | متوسط |
| C — Field Projection | Query.select | بايتات/سجل (backstop) | مرتفع | منخفضة | منخفض |
| C — tombstones/early-exit | فلترة/قطع | سجلات مُعادة | متوسط | منخفضة | منخفض |
| 3.4 — Backstop | سحب مصالحة | (يمنع فقد السجلات) | أمان | منخفضة | منخفض |

> تُقاس القيم فعلياً عبر عدّادات المسار القائمة (`pendingRemoteChangesCount`,
> `_maxUpdatedAtInPull`, عدّاد المطبّق/المتخطّى) قبل/بعد. نتجنّب نِسَباً مطلقة مبالغة.

---

## 5. خطة التنفيذ المرحلية

**المرحلة 1 — تفعيل وتغطية Realtime (خطر منخفض):**
1. رفع `appwrite_realtime_ws_enabled` خلف Feature Flag تدريجي.
2. إضافة الكيانات الأربعة الناقصة لقائمة `_collections` (أو إبقاؤها على السحب الدوري صراحةً).
3. التحقق من وجود `device_id`/`lastModifiedBy` في كل كتابة (كبح الصدى).

**المرحلة 2 — سحب موجّه (المرحلة A) + watermark لكل كيان (C):**
4. استخراج الكيان المتّسخ من `message.events` وتعليمه.
5. تعميم watermark المستقل، وجعل السحب يقتصر على `_dirtyEntities`.
6. Backstop المصالحة عند إعادة الاتصال/المقدّمة (3.4).

**المرحلة 3 — تطبيق موجّه بالحدث (المرحلة B):**
7. تمرير `payload` عبر `checkAndResolveConflict` + `upsertFromJson`.
8. طابور FK المؤجّل + سقوط آمن للسحب الموجّه عند فشل FK.
9. معالجة `.delete` كـ tombstone.

**المرحلة 4 — دعائم backstop (C):**
10. Field Projection عبر `Query.select()` للسحب الاحتياطي.
11. استبعاد tombstones القديمة + إنهاء مبكر.

---

## 6. المخاطر والتحقق

القيد الأول في الكود: **عدم فقدان أي سجل** (`sync_pull_service.dart:398-420` + Bootstrap
Guard). كل مرحلة تُختبر ضدّه:

- **فقد الأحداث:** محاكاة انقطاع طويل ثم تغييرات على الخادم؛ التأكد أن Backstop (3.4)
  يستردّ كل ما فات بعد إعادة الاتصال.
- **ترتيب FK:** إرسال حدث سجل تابع قبل أصله (payment قبل booking)؛ التأكد من التأجيل/
  السقوط الآمن دون فقد.
- **الصدى الذاتي:** كتابة محلية → التأكد أن الحدث المرتدّ يُتجاهَل (`device_id`).
- **التعارض:** كتابتان متزامنتان عبر جهازين على نفس السجل؛ التأكد أن نتيجة المسار
  الموجّه = نتيجة السحب العادي (نفس `checkAndResolveConflict`).
- **القياس قبل/بعد:** عدد الطلبات/دورة، السجلات المسحوبة، البايتات التقديرية
  (`estimatedBytesPerDeltaChange`, `sync_constants.dart:106`).
- **Feature Flags:** كل مرحلة خلف مفتاح للتراجع الفوري (على غرار
  `appwrite_realtime_ws_enabled`).

---

## 7. المراجع (ملفات وأسطر)

- `lib/services/appwrite_realtime_sync.dart` — الاشتراك (:37-57,89-94)، `_onEvent` (:163-222)،
  polling fallback (:131-156)، إعادة الاتصال (:247-299)، تتبّع `_lastServerUpdate` (:191-233).
- `lib/services/sync_core/sync_pull_service.dart` — `checkAndResolveConflict` (:78-290)،
  delta/full queries (:430-463)، watermark/booking_nights (:490-544)، نافذة الأمان (:421).
- `lib/services/appwrite_sync_manager.dart` — حلقة السحب (:1044-1633)، حسم watermark (:1668-1700)،
  upsert/dedup (:2659-2720)، `_extractUpdatedAtSec` (:2226-2241).
- `lib/services/appwrite_service.dart:150-214` — الترقيم المؤشّري وحجم الصفحة (100).
- `lib/services/appwrite_config.dart` — `collectionIds` (:95-119)، `databaseId`، `maxPageSize` (:142).
- `lib/services/advanced_query_builder.dart:180` — استخدام قائم لـ `Query.select` (جدوى Field Projection).
- `lib/services/sync_constants.dart` — `tableOrder` (:18-52)، الفواصل (:66)، بايتات تقديرية (:106).
- `lib/services/local_db.dart` — مخطّط `SyncState` (:903-935) و`Outbox` (:783).

---

*مسودة للمراجعة — جاهزة للنقاش قبل تحويلها إلى مهام تنفيذ.*
