# تقليل السحب (Pull) على مستوى السجل — Appwrite Delta Sync

> **مسودة للمراجعة** — تحليل مرتكز على الكود الفعلي (لا تخمين).
> النطاق: مجلد `mobile/`، مسار السحب في مزامنة Appwrite Delta Sync (push/pull).
> التاريخ: 2026-08-30.
> ملاحظة: هذه وثيقة تُكمّل `PULL_OPTIMIZATION_ANALYSIS.md` وتصحّح عمومياته،
> بالتركيز على **مستوى السجل**: عدد السجلات وبايتات كل سجل المنقولة فعلياً.

---

## 0. الخلاصة التنفيذية

نظام المزامنة سليم من ناحية الصحّة (cursor pagination، bootstrap guard، vector clocks،
حل تعارض متقدّم)، لكنه **يهدر على مستوى السجل** في أربعة مواضع قابلة للقياس:

1. يُنقل **كل حقول كل سجل** في كل سحب (لا Field Projection).
2. **watermark عالمي واحد** يربط مصير الكيانات الـ22 ببعضها؛ فشل كيان يُعيد سحب الكل.
3. **نافذة أمان 15ث** تُعيد سحب سجلات مطبّقة مسبقاً في كل دورة.
4. **tombstones** تُعاد في delta لأنها غير مُستبعدة (بخلاف full).

أعلى رافعتين مردوداً وأقلّهما خطراً: **(1) Field Projection** و**(5) استبعاد tombstones**.

---

## 1. بنية مسار السحب (كما هي في الكود)

```
AppwriteSyncManager.sync()                       // appwrite_sync_manager.dart:794
  └─ فحص سياسة الـ Outbox (canPull)              // :811-834  + outbox_pull_policy.dart
  └─ حلقة لكل كيان بترتيب FK آمن                  // :1044-1633  (22 كيان)
       └─ SyncPullService.buildDeltaQueries()    // sync_pull_service.dart:434-463
       └─ AppwriteService.list*()  (ترقيم مؤشّري) // appwrite_service.dart:150-214
       └─ _isRemoteDataNewer / checkAndResolveConflict → upsertFromJson
  └─ حسم الـ watermark عند نجاح الدورة            // :1668-1700
```

**استعلام الـ delta الفعلي** (`sync_pull_service.dart:434-463`):

```dart
static const int _safetyWindowSeconds = 15;                 // :421
...
final cutoffSeconds = lastPullTs - _safetyWindowSeconds;    // :457
final cutoffIso = DateTime.fromMillisecondsSinceEpoch(
  cutoffSeconds * 1000, isUtc: true).toIso8601String();
return [Query.greaterThan(r'$updatedAt', cutoffIso)];       // :462
```

**الترقيم** (`appwrite_service.dart:150-214`): مؤشّري صحيح على `$id`، حجم الصفحة
`AppwriteConfig.maxPageSize = 100`. هذا الجزء سليم ولا يحتاج تغييراً.

**الكيانات المسحوبة (22):** rooms, employees, inventory_items, inventory_transactions,
bookings, cash_transactions, expenses, booking_nights (مؤشّر مستقل), booking_notes,
payments, debts, salary_cycles, salary_payments, salary_withdrawals, guest_infos,
booking_price_adjustments, shift_notes, blacklist, price_adjustments, audit_logs,
payment_voids, salary_carry_over_logs.
(`hotel_day_ledger` محلي فقط، و`app_settings` معطّل عبر `appSettingsSyncEnabled=false`.)

---

## 2. التشخيص: مصادر الهدر على مستوى السجل

### 2.1 حمولة كاملة لكل سجل — لا Field Projection ⭐ الأكبر

كل استدعاء `listDocuments` يُعيد **كل حقول المستند** + حقول Appwrite النظامية
(`$id`, `$createdAt`, `$updatedAt`, `$permissions`, `$databaseId`, `$collectionId`).
لا يوجد `Query.select()` في مسار السحب. النتيجة: بايتات/سجل أكبر بكثير مما يحتاجه
الـ upsert المحلي، ويتضخّم الأثر مع كل صفحة (100 سجل) وكل كيان وكل دورة.

- **متحقَّق:** `Query.select` مدعوم في الإصدار المستخدم (`appwrite: ^21.0.0`) ومستخدم
  فعلاً في `advanced_query_builder.dart:180` — لكنه **غير مستخدم في مسار السحب**.

### 2.2 Watermark عالمي واحد يربط الكيانات ببعضها

المؤشّر مخزّن في صف واحد `SyncState(id=1).lastPullTs` (`local_db.dart:903-935`)،
ويُقرأ/يُكتب عبر `SyncPullService` (`sync_pull_service.dart:509-544`). لا يتقدّم إلا
عند نجاح **الدورة كاملة**:

```dart
// appwrite_sync_manager.dart:1668-1700
if (failedCollections.isEmpty) {
  final newPullTs = _maxUpdatedAtInPull ?? Time.nowEpoch();
  await _updateLastPullTs(newPullTs);
  await _pullService?.markFullSyncComplete();
}
// وإلا: لا يتقدّم lastPullTs ولا fullSyncComplete
```

**الأثر على مستوى السجل:** فشل كيان واحد (مثلاً timeout على `audit_logs`) يمنع تقدّم
المؤشّر، فتُعيد الدورة التالية سحب نافذة الـ15ث **لكل الكيانات الـ22** — لا الكيان
الفاشل فقط. وقبل اكتمال أول full sync، أي فشل يُبقي الجهاز في وضع full fetch كامل.

- **سابقة داعمة للحل:** `booking_nights` يملك مؤشّراً مستقلاً في SharedPreferences
  (`getBookingNightsPullTs`/`updateBookingNightsPullTs`, `sync_pull_service.dart:490-503`) —
  إثبات أن المؤشّر لكل كيان قابل للتطبيق ومطبَّق جزئياً.

### 2.3 نافذة الأمان 15ث تُعيد سحب سجلات مطبّقة

النافذة (`_safetyWindowSeconds = 15`) تُطرح من المؤشّر قبل بناء الفلتر، فيُعاد في كل
دورة سحب **كل سجل تغيّر في آخر 15ث** لكل كيان. هذه السجلات تُطرح محلياً عبر فحص
المحتوى/التعارض:

```dart
// sync_pull_service.dart:315-351  (_contentEquals يتجاهل حقول الميتاداتا)
// appwrite_sync_manager.dart:2691-2701  (continue إذا !shouldApplyRemote)
```

أي أن التكلفة **بايتات شبكة مهدورة**، لا كتابات DB. الغرض من النافذة تفادي انحراف
الساعات بين الأجهزة — هدف صحيح لكنه مدفوع الثمن في كل دورة ولكل كيان.

### 2.4 Delta لا يستبعد tombstones

فلتر استبعاد المحذوف موجود فقط في السحب الكامل:

```dart
// sync_pull_service.dart:430-432
static List<String> buildFullSyncQueries() => [
  Query.or([Query.isNull('deletedAt'), Query.equal('deletedAt', 0)]),
];
```

بينما `buildDeltaQueries` **بلا فلتر deletedAt**. النتيجة: السجل المحذوف ناعماً يبقى
له `$updatedAt` حديث، فيُعاد سحبه في كل دورة داخل النافذة رغم أنه طُبّق محلياً.

### 2.5 حدّ أدنى 22 طلب/دورة حتى بلا تغييرات

الحلقة تصدر استعلام list لكل كيان دائماً، سواء تغيّر أم لا. بنية Realtime موجودة
لكنها **معطّلة افتراضياً** (`appwrite_realtime_sync.dart`، pref
`appwrite_realtime_ws_enabled = false`)، فلا توجد إشارة تُخبر أي الكيانات تغيّر.

> ملاحظة توضيحية: هذا مصدر هدر على مستوى **الطلبات** أكثر منه على مستوى السجل،
> لكنه مذكور لاكتمال الصورة ولأن الحل (#3) يخدم الهدفين.

### 2.6 ما هو سليم بالفعل (لا يُلمس)

- الترقيم المؤشّري على `$id` (`appwrite_service.dart:159-213`) — إصلاح P1-4.
- Full Sync Bootstrap Guard (`sync_pull_service.dart:448-452`).
- اشتقاق المؤشّر من `max($updatedAt)` لا من ساعة الجهاز (`appwrite_sync_manager.dart:1669`).
- حل التعارض (vector clock → LWW → 3-way merge) و`_contentEquals`.

---

## 3. روافع التقليل (مرتّبة بالأولوية)

### رافعة 1 — Field Projection عبر `Query.select()` ⭐ (كلفة منخفضة / أثر أكبر)

اجلب فقط الأعمدة التي يحتاجها الـ upsert المحلي لكل كيان، بدل المستند الكامل.

```dart
// المقترح داخل buildDeltaQueries / buildFullSyncQueries (لكل كيان)
return [
  Query.greaterThan(r'$updatedAt', cutoffIso),
  Query.select([...roomsSyncFields, r'$id', r'$updatedAt']),
];
```

- **الأثر:** خفض بايتات/سجل بنسبة كبيرة (يتناسب مع نسبة الأعمدة غير الضرورية).
- **التنفيذ:** تعريف قائمة حقول لكل كيان (يمكن اشتقاقها من الـ adapters في
  `lib/services/adapters/`). يجب دائماً تضمين `$id` و`$updatedAt` (يعتمد عليهما المؤشّر
  والـ dedup عبر `_extractUpdatedAtSec`).
- **الخطر/التحقق:** التأكد أن كل حقل يقرأه `upsertFromJson` وحلّ التعارض
  (`lastModified`, `deletedAt`, `vectorClock`, `deviceId`, `version`) ضمن القائمة، وإلا
  ضاعت بيانات. اختبار مطابقة قبل/بعد على عيّنة سجلات.

### رافعة 2 — Watermark مستقل لكل كيان (كلفة متوسطة)

استبدل الصف العالمي بمؤشّر لكل كيان (توسعة `SyncState` بعمود/JSON، أو جدول
`sync_cursors(entity, last_pull_ts)`)، على غرار ما هو مطبّق لـ `booking_nights`.

- **الأثر:** كل كيان يتقدّم مستقلاً؛ فشل كيان لا يُعيد سحب الباقي. يلغي «تضخيم إعادة
  السحب عبر الكيانات» الموصوف في 2.2.
- **التنفيذ:** تعميم نمط `getBookingNightsPullTs`/`updateBookingNightsPullTs` على كل
  الكيانات، وتحديث حسم المؤشّر في `appwrite_sync_manager.dart:1668-1700` ليكتب مؤشّر
  كل كيان عند نجاحه هو (لا انتظار نجاح الدورة كاملة).
- **الخطر/التحقق:** الحفاظ على Bootstrap Guard لكل كيان؛ اختبار سيناريو فشل كيان
  واحد والتأكد أن البقية تتقدّم وأن الفاشل يُعاد وحده.

### رافعة 3 — تخطّي الكيانات غير المتغيّرة (كلفة متوسطة)

فعّل إشارة تغيير خفيفة بدل استعلام الكيانات الـ22 عمياء:
- إمّا تفعيل `AppwriteRealtimeSync` الموجود (رفع `appwrite_realtime_ws_enabled`) لتحديد
  الكيانات المتّسخة بين الدورات.
- أو مستند «heartbeat» واحد يحمل آخر `$updatedAt` لكل كيان، يُقرأ بطلب واحد في بداية
  الدورة، فتُستعلَم الكيانات التي تجاوز طابعها المؤشّر المحلي فقط.

- **الأثر:** طلبات 22 → «المتّسخة فقط» لكل دورة (ويقلّل السجلات المفحوصة تبعاً).
- **الخطر/التحقق:** ضمان عدم تفويت تغيير عند انقطاع الـ socket (fallback دوري موجود
  أصلاً: `_startPollingFallback`).

### رافعة 4 — مؤشّر مركّب `($updatedAt, $id)` لإلغاء تكرار النافذة (كلفة متوسطة)

خزّن مع المؤشّر آخر `$id` عند حدّ `max($updatedAt)`، واطرح السجلات المطبّقة عند نفس
الطابع. هذا يسمح بتصغير النافذة إلى ثوانٍ قليلة (أو إزالتها) دون فقد سجل حدّي، أو
اجعلها تكيّفية: WiFi ≈ 5ث، خلوي ≈ 15ث.

- **الأثر:** خفض بايتات إعادة السحب في 2.3 دون المساس بالأمان ضد انحراف الساعة.
- **الخطر/التحقق:** اختبار سجلين بنفس `$updatedAt` بالضبط عبر جهازين؛ التأكد أن أحدهما
  لا يُفقَد عند تقليص النافذة.

### رافعة 5 — استبعاد tombstones من Delta ⭐ (كلفة منخفضة)

أضف فلتر `deletedAt` إلى `buildDeltaQueries` (كما في full) بعد ضمان تطبيق الحذف محلياً،
أو اسحب المحذوف ضمن نافذة صغيرة مرة واحدة فقط.

- **الأثر:** يمنع إعادة سحب السجلات المحذوفة ناعماً كل دورة.
- **الخطر/التحقق:** الانتباه لمنطق «durable remote tombstone» (`sync_pull_service.dart:99-117`)
  الذي يمنع بعث السجل المحذوف — يجب ألّا يُفقَد إشعار الحذف للأجهزة التي لم تستقبله بعد.
  الحل الأسلم: استبعاد المحذوف **القديم فقط** (خارج نافذة نشر الحذف).

### رافعة 6 — إنهاء مبكر عند 0 مستند (كلفة منخفضة)

إن أعادت أول صفحة delta لكيانٍ 0 مستند، تخطَّ بقية معالجته فوراً. يتكامل مع #3
ويقلّل الحلقات الفارغة.

---

## 4. جدول الأثر (تقديري ومتحفّظ)

| الرافعة | مستوى التقليل | الأثر النسبي | الكلفة | الخطر |
|---------|----------------|--------------|--------|-------|
| 1 — Field Projection | بايتات/سجل | مرتفع | منخفضة | منخفض (باختبار الحقول) |
| 2 — Watermark لكل كيان | سجلات مُعادة عبر الكيانات | مرتفع عند الفشل | متوسطة | متوسط |
| 3 — تخطّي غير المتغيّر | طلبات + سجلات ممسوحة | مرتفع | متوسطة | متوسط |
| 4 — مؤشّر مركّب | بايتات النافذة المكرّرة | متوسط | متوسطة | متوسط |
| 5 — استبعاد tombstones | سجلات محذوفة مُعادة | متوسط | منخفضة | منخفض |
| 6 — إنهاء مبكر | حلقات/طلبات فارغة | منخفض | منخفضة | منخفض |

> تُقاس القيم الفعلية بعد التطبيق عبر عدّادات موجودة أصلاً في مسار المزامنة
> (`_maxUpdatedAtInPull`، عدّاد المستندات المطبّقة/المتخطّاة) قبل/بعد. تجنّبنا عمداً
> نِسَباً مطلقة مبالغة (كالمذكورة في الوثيقة السابقة) لعدم توفّر قياس ميداني بعد.

---

## 5. خطة التنفيذ المرحلية

**المرحلة 1 — مكاسب سريعة (خطر منخفض):**
- رافعة 1 (Field Projection) — تبدأ بكيان واحد عالي التردّد (bookings/payments) للتحقق.
- رافعة 5 (استبعاد tombstones القديمة من delta).

**المرحلة 2 — متوسطة:**
- رافعة 2 (watermark لكل كيان) — تعميم نمط booking_nights.
- رافعة 4 (مؤشّر مركّب / نافذة تكيّفية).
- رافعة 6 (إنهاء مبكر).

**المرحلة 3 — استراتيجية:**
- رافعة 3 (تفعيل Realtime / heartbeat لتخطّي غير المتغيّر).

---

## 6. المخاطر والتحقق

القيد الأول في الكود الحالي هو **عدم فقدان أي سجل** (توثّقه تعليقات
`sync_pull_service.dart:398-420` و Bootstrap Guard). كل رافعة يجب أن تُختبر ضد هذا القيد:

- **اختبار عدم الفقد:** جهازان يكتبان بالتزامن؛ التأكد أن كل سجل يصل للطرفين بعد
  تطبيق كل رافعة (خاصة 1 و4 و5).
- **اختبار الفشل الجزئي:** حقن فشل كيان واحد؛ التأكد (بعد رافعة 2) أن البقية تتقدّم.
- **قياس قبل/بعد:** تسجيل عدد الطلبات، السجلات المسحوبة، السجلات المتخطّاة، والبايتات
  التقديرية (`estimatedBytesPerDeltaChange` في `sync_constants.dart:106`).
- **علم ميزة (Feature Flag):** إخفاء كل رافعة خلف مفتاح للتراجع السريع، على غرار
  مفاتيح prefs الحالية (`appwrite_realtime_ws_enabled` …).

---

## 7. المراجع (ملفات وأسطر)

- `lib/services/sync_core/sync_pull_service.dart` — delta queries (:434-463)، نافذة الأمان
  (:421)، full queries (:430-432)، المؤشّرات (:490-544)، حل التعارض (:78-351).
- `lib/services/appwrite_sync_manager.dart` — حلقة السحب (:1044-1633)، حسم المؤشّر (:1668-1700)،
  upsert/dedup (:2659-2720).
- `lib/services/appwrite_service.dart` — الترقيم المؤشّري وحجم الصفحة (:150-214).
- `lib/services/appwrite_config.dart` — `maxPageSize` (:142)، معرّفات الكيانات.
- `lib/services/sync/outbox_pull_policy.dart` — حجب السحب أثناء outbox معلّق.
- `lib/services/appwrite_realtime_sync.dart` — بنية Realtime (معطّلة) لرافعة #3.
- `lib/services/advanced_query_builder.dart:180` — استخدام قائم لـ `Query.select` (دليل جدوى #1).
- `lib/services/sync_constants.dart` — الفواصل (:66)، ترتيب الجداول (:18-52)، بايتات تقديرية (:106).
- `lib/services/local_db.dart` — مخطّط `SyncState` (:903-935) و`Outbox` (:783).

---

*مسودة للمراجعة — جاهزة للنقاش قبل تحويلها إلى مهام تنفيذ.*
