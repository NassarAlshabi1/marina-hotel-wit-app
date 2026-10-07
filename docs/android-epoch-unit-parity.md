# وحدة الطوابع الزمنية في المزامنة (ثوانٍ لا ميلي ثانية) — عطل «سحب دلتا الغرف»

**التاريخ:** 2026-10-06 · **آخر تحديث:** 2026-10-07 (إغلاق المتبقّي §5) · **الفرع:** `arena/be8302d7-marina-hotel-wit-app`
(= قاعدة `agent/android-cloudflare`).
**السياق:** شكوى «سحب البيانات delta — الغرف: الشاغرة/المحجوزة/المكتمل». بعد
تدقيق سطر-بسطر (لا تخمين) ظهر أن **البيانات ليست غائبة عن السلك**، بل كانت
تُرفض أو تُبطَل وحدتها داخل الجهاز نفسه.

## 0) الخلاصة التنفيذية

- حالة الغرفة (`شاغرة`/`محجوزة`) وحالة الحجز (`مكتمل`) تسافران **كصفوف**
  (`rooms.status` و`bookings.status`) عبر الدلتا كأي حقل آخر، والـ Worker يرسل
  الصف كاملاً. لا فلتر خادمي يُسقط الغرف ولا الحجوزات المكتملة.
- العطل الحقيقي: **وحدة الطوابع الزمنية**. المرجع (Flutter + الـ Worker)
  يستعمل **الثواني**، وطبقة البيانات عندنا كانت تكتب `last_modified` و`updated_at`
  بـ**ميلي ثانية** في مواضع عدة. وبما أن قرار الدمج عندنا هو «الأحدث بـ
  `last_modified` يفوز»، فالقيمتان كانتا تُقارنان بوحدتين مختلفتين ⇒ نتائج
  معكوسة في الاتجاهين (تفصيل البند 2).
- الإصلاح: وحدة موحّدة (`SyncEpochs`) على **الحدود** (سحب/رفع) + تصحيح كتابة
  الغرف والحجوزات (شاملة رفع الحذف الناعم ورفع النسخة) على عقد Dart الحرفي.
- الاختبارات: `SyncEpochParityTest` (5 حالات) — تفشل قبل الإصلاح وتنجح بعده.

## 1) العقد المقيس (مصادر الحقيقة)

| الطرف | الوحدة | الدليل |
| --- | --- | --- |
| Flutter (المرجع) | ثوانٍ | `mobile/lib/utils/time.dart:8` — `nowEpoch() => millisecondsSinceEpoch ~/ 1000`؛ ويُستعمل في `rooms_dao.dart:74/106/144/181` (`createdAt/updatedAt/lastModified`) و`bookings_dao.dart:104-106/148/210-212` |
| الـ Worker (D1) | ثوانٍ | `Math.floor(Date.now()/1000)` في `allocateUpdatedAt`/`reStampPoisoned`؛ وعتبتاه: `MS_TIMESTAMP_THRESHOLD = 1e11` و`FUTURE_TIMESTAMP_THRESHOLD = 2e9` (`worker/src/database.ts:603/614`) |
| الـ Worker عند الرفع | ينسخ ما يرسله العميل | `createRecord`: `if (!record.last_modified) record.last_modified = now` — أي **لا يُصلح** طابعاً ميلياً وارداً، ولا يكتشفه `reStampPoisoned` لأنه يشترط `updated_at > 2e9` والمظروف يبقى بالثواني |
| أندرويد قبل الإصلاح | **ميلي ثانية** في `last_modified`/`updated_at` | `RoomsRepositoryImpl.updateStatus/softDelete`، `BookingsRepositoryImpl.update/insert`، و`~61` موضعاً آخر (قائمة البند 5) |

## 2) الأعطال المقيسة (كلها في مسار «الغرف» المطلوب)

### العطل A — الصف الملموس محلياً **لا يستقبل تحديثات الخادم بعدها**

`RoomsRepositoryImpl.updateStatus` (نقرة «تعيين كمحجوزة/شاغرة») كانت تكتب
`last_modified = System.currentTimeMillis()` ≈ `1.77e12`، وصف الخادم يحمل
`last_modified` بالثواني ≈ `1.76e9`. وقرار الاستيعاب:

```kotlin
remoteLastModified >= existing.lastModified   // 1.76e9 >= 1.77e12 == false ⇒ تخطٍّ صامت
```

⇒ **كل جهاز لمس غرفة محلياً يصبح أعمى عن تلك الغرفة للأبد** (ولا يُشفى لأنه
لا يسحب صفاً لنفسه بسبب `exclude_device`). هذا بالحرف «سحب دلتا الغرف لا يعمل».

### العطل B — العكس: تعديلنا المحلي يُطمس

`RoomsRepositoryImpl.insert/update` و`BookingsRepositoryImpl.insert/update`
كانت لا تكتب `last_modified` إطلاقاً (نموذج المجال `Room`/`Booking` لا يحمل
الحقل)، فيبقى الصف على القيمة الافتراضية `0` ⇒ `1.76e9 >= 0` ⇒ صف الخادم
الأقدم يفوز ويُعيد حالة الغرفة/الحجز إلى الوراء حتى بعد تعديل المستخدم.

### العطل C — حذف الغرفة **لا يُرفع إطلاقاً**

`RoomsRepositoryImpl.softDelete` كانت تكتب القبورة محلياً **بلا إدراج عملية
outbox**، بينما Dart (`rooms_dao.dart:176-215`) يدرج `op='update'` بحمولة
تحمل `deleted_at/updated_at/last_modified`. الأثر: الغرفة المحذوفة تبقى حيّة في
D1 وعلى بقية الأجهزة.

### العطل D — تلويث D1 لبقية الأجهزة

حمولة الرفع كانت تُرسل `last_modified` بالميلي، والـ Worker يخزّنه حرفياً ⇒
تطبيق Flutter على جهاز آخر يقارن طابعه (ثوانٍ) بطابعنا (ميلي) فيفوز طابعنا
دائماً بلا أي سبب زمني حقيقي (ويقفل الصف هناك أيضاً).

## 3) الإصلاح

1. **`data/sync/SyncEpochs.kt`** (جديد) — مصدر واحد للعقد:
   - `nowSeconds()` = `System.currentTimeMillis() / 1000` (نظير `Time.nowEpoch`).
   - `MILLIS_THRESHOLD = 1e11` و`FUTURE_THRESHOLD = 2e9` (نفس قيم الـ Worker).
   - `WIRE_EPOCH_FIELDS` = `created_at/updated_at/deleted_at/last_modified/created_at_epoch/last_modified_epoch` — **أعمدة المزامنة فقط**؛ حقول الأعمال
     (`checkin_date`, `hotel_day_key`, `transaction_time`, …) لا تُلمس.
   - `normalizeWireEpochFields` (سحب) و`normalizeOutgoingEpochFields` (رفع)
     و`toSeconds` (للمقارنة).
2. **الاستيعاب** (`SyncIngestorRegistry.applyRecord`): تطبيع الطوابع الواردة
   قبل قرار الدمج وقبل الخزن ⇒ صفوف D1 المسمومة (التي أنتجناها سابقاً) تُشفى
   عند أول سحب، ولا تعود تقفل نفسها.
3. **قرار الدمج**: المقارنة تجري **بعد توحيد الوحدة على الطرفين**:
   `toSeconds(remote) >= toSeconds(existing)` — فالصف المحلي القديم الطابع لا
   يحجب تحديثاً خادمياً أحدث.
4. **الرفع** (`PushWireContract.normalizeForWire`): تطبيع أعمدة الطوابع قبل
   الإرسال ⇒ لا تلويث لـ D1 من هذا التطبيق.
5. **الغرف** (`RoomsRepositoryImpl` + `RoomsDao.updateStatus`): ثوانٍ في
   `insert/update/updateStatus/softDelete`، و`last_modified` يُكتب فعلاً،
   و`version = existing.version + 1` (نظير Dart — و`version` كاسر التعادل
   الوحيد في الـ Worker)، و`softDelete` يُدرج عملية outbox بحمولة القبورة.
6. **الحجوزات** (`BookingsRepositoryImpl.insert/update`): نفس العقد (ثوانٍ +
   `last_modified` + رفع النسخة) — وهذا هو مسار «إنهاء الحجز (مكتمل)» في
   التطبيق (`BookingCheckoutViewModel` يستدعي `update`).

## 4) الاختبارات (`SyncEpochParityTest`، Robolectric sdk 34)

| الحالة | ما تُثبته |
| --- | --- |
| `roomLocalWritesStampSecondsNotMillis` | `insert/updateStatus/update/softDelete` تكتب ثوانٍ، وترفع `version`، و`softDelete` يدرج عملية بحمولة `deleted_at` |
| `millisStampedLocalRoomStillAcceptsNewerServerRow` | صف محلي بطابع ميلي (`1.76e12`) يستقبل صف الخادم الأحدث (`1.7600006e9`) ويطبّقه — **كان يُتخطّى قبل الإصلاح** |
| `poisonedServerRoomRowIsNormalizedToSecondsOnIngest` | صف D1 مسموم بالميلي يُخزَّن بالثواني ويبقى قابلاً للتحديث لاحقاً |
| `bookingCompletionStampsSecondsAndBumpsVersion` | «مكتمل» يُختم بالثواني ويرفع النسخة، والصف يقبل تحديثاً خادمياً أحدث |
| `pushPayloadNormalizesEpochColumnsAndKeepsBusinessTimestamps` + `secondsAreNeverDividedTwice` | حمولة الرفع: أعمدة الطوابع تُقسَم، وحقول الأعمال لا تُلمس، ولا قسمة مزدوجة لقيمة ثوانٍ |

## 5) إغلاق المتبقّي (نُفِّذ — إفصاح وتحفّظات)

الثلاثة المعلنة في النسخة السابقة نُقلت فعلاً (الالتزامات
`c3bc16b5` … `d364b90b` على فرع الجلسة)، وهذا ما تحقّق بالتشغيل لا بالادّعاء:

### 5.1 وحدة الزمن في المستودعات الثلاثة عشر

- كل مواضع الميلي في `data/repository/*RepositoryImpl.kt` صارت
  `SyncEpochs.nowSeconds()` (جرد آلي: **58** استعمالاً للثواني مقابل **صفر**
  كتابة مباشرة بالميلي على أعمدة المزامنة؛ المتبقّي بالميلي **بعمد**:
  `OutboxRepository.clientTs`, `SyncManager` (11 موضعاً — زمن جدار لا عمود
  مزامنة), `BookingDerivedRefreshService.moment`, `SyncIngestorRegistry`).
- حقول الأعمال بقيت بالميلي حيث يعتمد عليها العرض/الاستعلام: `expenses.date`
  و`payments.payment_date` (نصوص ISO مبنية على `Date(millis)`)،
  `salary_withdrawals.withdraw_date`، و`inventory_transactions.transaction_time`
  (عمود محلي بحت — لا مقابل له في `worker/schema.sql` ولا Drift).

### 5.2 فجوة الإشغال — النقل الحرفي بدل التقريب

- نُقلت `refreshAllRoomOccupancy` من `rooms_repository.dart:221-258` بلا
  «تحسين»: مشغولة = حجوزات non-deleted بحالة ضمن التسعة،
  `shouldBeOccupied && !isRoomOccupied` ⇒ «محجوزة»،
  `!shouldBeOccupied && !isRoomAvailable` ⇒ «شاغرة»، وإلا لا كتابة.
- **المقايضة المعلنة (قرار صريح)**: غرفة «صيانة» بلا حجز نشط تُعاد إلى
  «شاغرة» — هذا سلوك Dart نفسه (ليست مشغولة ولا متاحة)، ونُقل كما هو
  التزاماً بالمطابقة السلوكية، وليس سهواً.
- الاستدعاءان: `BookingEditViewModel` (نظير `booking_edit.dart` l.1131) و
  `BookingCheckoutViewModel` (نظير `booking_checkout_screen.dart` l.702-711).
  **لم يُمَس** `BookingPaymentViewModel` عن قصد: المرجع يحدّث غرفة واحدة هناك
  (`enqueueOutbox:false` في `booking_payment_screen.dart`).
- دقّة إضافية: فرع `originIsServer` في كتابة الإشغال يختم `last_modified=now`
  أيضاً — لأن `refreshAllRoomOccupancy` في Dart **لا يمرّر** طابعاً وارداً.

### 5.3 عطل `last_modified = 0` (صنف B) — الجذر الذي كان يطمس تعديلنا

- السبب: نموذج المجال لا يحمل حقول المزامنة، و`dao.insert/update(x.toEntity())`
  بلا ختم ⇒ يُكتب **صفر**؛ وقرار «آخر كتابة تفوز» يقارن
  `remote >= existing.lastModified` فيفوز أي صف خادمي ولو أقدم.
- الإصلاح: نداءات DAO الجزئية الثمانية (softDelete للجداول، `terminate`,
  `reactivate`, `markRead`, `voidPayment`, `updateSettlement`, `softDeleteItem`)
  صارت تختم `last_modified/updated_at` بالثواني وتُرفع نسخة حيث يرفعها Dart
  (`version = version + 1`)؛ والمستودعات تختم على `.toEntity()`/صف `getById`
  فقط مع حفظ `localUuid/createdAt`.
- ثلاثة مواضع إضافية اكتُشفت بالتدقيق وأُصلحت بنظيرها الدارتي:
  - `BookingsRepository.updateComputedFields` كان يكتب الصف كاملاً و`last_modified=0`؛
    الآن لا يُلمس إلا الحقول المشتقة + `updated_at` (بنصّ تعليق
    `booking_derived_fields_service.dart` l.132-149: «لا نحدّث lastModified للحقول المشتقة»).
  - `InventoryDao.insertTransactionAndUpdateBalance` كان يكتب رصيد الصنف بـ
    `updated_at` بالميلي بلا `last_modified` ولا `version+1` ولا رفع — صار نظير
    `inventory_repository.dart` l.133-157، ويُرفع `inventory_items:update` مع الحركة.
  - `payment_voids` و`booking_price_adjustments`: الصف الجديد يُختم بالثواني
    (كانت أصفاراً) نظير `payment_void_service.dart` l.132-152 و
    `booking_price_adjustment_service.dart` l.258-280.

### 5.4 حارس انزياح الساعة في LWW (نظير Dart M3)

- `SyncIngestorRegistry`: كان يُسقط أي وارد طابعه أقدم من المحلي — وجهاز
  ساعته متقدمة **يُسقط كل وارد إلى الأبد** بينما مؤشر السحب يتقدم فوقه ⇒ فقد
  دائم. الآن: `remote.version > existing.version` ⇒ المضيّ بالوارد (الخادم
  يختم `version` بنفسه: `database.ts` l.1285-1293)، وإلا تخطٍّ — مطابق
  `cloudflare_sync_manager.dart` l.3013-3037.

### 5.5 عطل تسلسل كشفه CI: حركات المخزون كانت **لا تُرفع**

- `OutboxRepository.enqueueObject` كان يستعمل `Gson()` بسيطاً، وكل كيان يرث
  `BaseSyncEntity` يعيد تعريف حقوله ⇒ `declares multiple JSON fields named 'id'`
  ⇒ استثناء يُلتقط كـ`Result.failure`. الموضع الوحيد الذي يمرّر كياناً خاماً هو
  `inventory_transactions`، فالحركات بقيت محلية بلا رفع وبلا أثر ظاهر.
- الحل: `data/sync/SyncEntityGson.kt` (استراتيجية استبعاد الظل في نقطة واحدة،
  يستعملها مسار الرفع و`SyncIngestorRegistry.gsonFor` معاً) + اختبار انحدار.

### 5.6 الدليل التشغيلي (CI، فرع الجلسة)

| التشغيل | الالتزام | النتيجة |
| --- | --- | --- |
| Sync Unit Tests `37698116017` | `d364b90b` | **success** — `:app:testDebugUnitTest`: 409 حالة • 0 فشل • 0 أخطاء • 0 متخطّاة؛ worker vitest+typecheck: success؛ detekt: success |
| Android APK Build `37698116051` | `d364b90b` | **success** — release موقّع 5,960,887 بايت (`9771b444…`)، debug 25,366,772 بايت؛ apksigner v1/v2/v3 = true |

سلسلة التشخيص التي سبقت الأخضر (كلها بإصلاح فعلي لا تخفيف فحص): `37695795804`
خطأ تصريف (`BookingPriceAdjustment` بلا `createdAt/updatedAt`) ← `37696113594`
تعليق Kotlin غير مغلق ← `37696545953` وسيط `lastModified` ناقص في اختبار قديم ←
`37696941360` عطل Gson الحقيقي أعلاه ← `37697574905` توقعات كمية خاطئة في
اختبارات جديدة ← **`37698116017` أخضر**.

### 5.7 ما يبقى معلناً (لا مخفي)

- `BookingsRepositoryImpl.checkout`: لا إدراج outbox — مقصود ومطابق للمرجع
  (`checkout` تعتمد مسار `update` في التطبيق، وDart يحدّث الحجز عبر `updateById`).
- `hotel_day_ledger` محلي بحت (غير موجود في `ENTITY_TABLES` عند الـWorker) — لا يُزامَن.
- `app/schemas/*.json` ليست مصدر القياس — كل الأرقام أعلاه من الشيفرة وتشغيل CI.
- التشغيل الأحمر الوحيد المتبقّي على الفرع هو **«Code scanning AI findings on
  PR #617»** (`GitHub Advanced Security`، `event: dynamic`) — وكيل Copilot
  Autofix الخارجي: يفشل في الخطوة `Processing Request (Linux)` بعد نجاح كل
  خطوات الإعداد، ويفشل بالطريقة نفسها على فروع أخرى غير هذا العمل ⇒ ليس من
  شيفرة المستودع ولا يُصلَح منه.

## 6) المراجع

- [`android-pull-parity-flutter.md`](./android-pull-parity-flutter.md) — مواءمة
  محرك السحب كاملاً (نُقل فيها ما نُقل، ووُثّق ما لم يُنقل).
- [`flutter-branch-review-cloudflare-sync-execution.md`](./flutter-branch-review-cloudflare-sync-execution.md)
  — مراجعة الفرع المرجعي (F1–F8).
- [`android-pull-quarantine.md`](./android-pull-quarantine.md) — سياسة العزل
  والشفاء (لماذا لا يتجمّد المؤشر).
