# وحدة الطوابع الزمنية في المزامنة (ثوانٍ لا ميلي ثانية) — عطل «سحب دلتا الغرف»

**التاريخ:** 2026-10-06 · **الفرع:** `arena/be8302d7-marina-hotel-wit-app`
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

## 5) المتبقّي (معلن، لا مخفي)

- **61 موضعاً** في 13 مستودعاً آخر ما تزال تكتب `updated_at`/`deleted_at`/`last_modified`
  بالميلي (`Blacklist/Cash/Debts/Employees/Expenses/GuestInfos/Inventory/Payments/Salary/SalaryWithdrawals/ShiftNotes/BookingNights/Bookings.checkout|softDelete`).
  **أثرها المتبقّي بعد هذا الإصلاح**: لا يمسّ قرارات المزامنة (التطبيع على
  الحدود يحيّدها)، وإنما يترك الوحدة المخزَّنة محلياً غير متسقة في تلك الأعمدة.
  تُنقل تدريجياً إلى `SyncEpochs.nowSeconds()` بنفس النمط.
- **مزامنة إشغال الغرف الشامل**: Dart ينفّذ `refreshAllRoomOccupancy`
  (`repositories/rooms_repository.dart:221-258`) بعد أي تعديل حجز — يُعيد ضبط
  **كل** الغرف من الحجوزات النشطة. عندنا تقريب موضعي للغرفتين المعنيتين
  (`BookingEditViewModel.refreshRoomOccupancy`). الفرق موثّق ولم يُنقل بعد؛
  والمقايضة: النقل الحرفي يقلّد أيضاً سلوك Dart في عدم استثناء غرف الصيانة
  (يُعيدها إلى `شاغرة`)، لذا يحتاج قراراً صريحاً قبل التنفيذ.
- `BookingsRepositoryImpl.checkout/softDelete` و`updateComputedFields`: بلا
  إدراج outbox وبوحدة قديمة — `checkout` غير مستدعى في التطبيق حالياً
  (المسار الفعلي `update`)، و`softDelete` يحتاج مراجعة سلوك مقابل Dart.
- `app/schemas/*.json` ليست مصدر القياس (كما هو مثبت سابقاً) — كل الأرقام أعلاه
  من الشيفرة نفسها.

## 6) المراجع

- [`android-pull-parity-flutter.md`](./android-pull-parity-flutter.md) — مواءمة
  محرك السحب كاملاً (نُقل فيها ما نُقل، ووُثّق ما لم يُنقل).
- [`flutter-branch-review-cloudflare-sync-execution.md`](./flutter-branch-review-cloudflare-sync-execution.md)
  — مراجعة الفرع المرجعي (F1–F8).
- [`android-pull-quarantine.md`](./android-pull-quarantine.md) — سياسة العزل
  والشفاء (لماذا لا يتجمّد المؤشر).
