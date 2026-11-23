# تقرير تشخيصي وهندسي شامل — تضخّم ليالي الحجز، مسارات مزامنة المدفوعات، ومخاطر اختلاف المعرّفات

**التطبيق:** Marina Hotel — `mobile/`
**المرجع المُدقَّق:** `feat/cloudflare-sync-execution` @ `6a1da1a5f8e79fa073efa492c1be2b0a05a3bd88` (آخر التزام على الفرع: `fix(test): complete guest-credit port — unclamped balance + first-checkout rebuild` — 2026-11-21)
**فرع الجلسة:** `arena/6540cfd7-marina-hotel-wit-app` (مبني على نفس الالتزام أعلاه)
**التحقق من المطابقة:** `git fetch origin feat/cloudflare-sync-execution` ثم `git diff --stat HEAD FETCH_HEAD` ⇒ **فارق صفر** على الشجرة كاملة وعلى `mobile/` تحديداً. أي أن كل مرجع `ملف:سطر` في هذا التقرير يقع حرفياً على الفرع المطلوب (انظر الملحق هـ).
**تاريخ التقرير:** 2026-11-23
**نطاق التقرير:** طبقة البيانات المحلية (Drift/SQLite) + طبقة المزامنة (Cloudflare Worker + D1) + المسارات المالية (الحجوزات، الليالي، المدفوعات، الإلغاءات، التعديلات السعرية، الاستعادة)
**حالة التنفيذ (تحديث 2026-11-23):** الإصلاحات الجذرية الخاصة بـ**«لا ليالٍ مكررة»** نُفِّذت فعلياً على فرع الجلسة: هوية عالمية لكل ليلة على D1 (`uuid الحجز + اليوم`)، إلغاء القيد المحلي الذي كان يُتلف الليالي بين الأجهزة، حمولات لقطة صف كاملة بدل `{localUuid}`، إعلان موت صريح قبل أي حذف، بوابة سلامة على الإقلاع، وترحيل `0018` لطيّ المكرر القائم. التفصيل والأدلة والتحقق في **[§9](#9-الإصلاحات-المنفَّذة-فعلياً-دليل-لا-ليالٍ-مكررة)**. أرقام الأسطر في §2 و§5 تصف شيفرة **قبل** الإصلاح (الالتزام `6a1da1a5`)، وبعد الإصلاح تغيّرت مواضعها — الجدول المرجعي المحدَّث في §9.1.

**مرجع البيانات الرقمية:** لقطة الفحص الخارجية التي قدّمها المستخدم (3,495 ليلة مقابل 356 حجزاً). هذه اللقطة **ليست داخل المستودع**؛ كل الاستنتاجات البنيوية أدناه مأخوذة من الكود، والأرقام تُعامَل كمدخلات تحتاج إعادة إنتاج على D1 (الاستعلامات في الملحق ب).

---

## المحتويات

0. [تصحيح أساس التقرير: D1 وليس Appwrite](#0-تصحيح-أساس-التقرير-d1-وليس-appwrite)
1. [ملخص تنفيذي ودرجات الخطورة](#1-ملخص-تنفيذي-ودرجات-الخطورة)
2. [الأخطاء المكتشفة في حساب الليالي](#2-الأخطاء-المكتشفة-في-حساب-الليالي)
3. [تحليل مسارات مزامنة المدفوعات](#3-تحليل-مسارات-مزامنة-المدفوعات)
4. [مخاطر اختلاف معرّفات الحجز والدفعات](#4-مخاطر-اختلاف-معرّفات-الحجز-والدفعات)
5. [خطة إصلاح جذري مرتبة حسب الأولوية](#5-خطة-إصلاح-جذري-مرتبة-حسب-الأولوية)
6. [اختبارات إلزامية قبل اعتماد الإصلاح](#6-اختبارات-إلزامية-قبل-اعتماد-الإصلاح)
7. [مصالحة بيانات النزيل دون إفساد سجله المالي](#7-مصالحة-بيانات-النزيل-دون-إفساد-سجله-المالي)
8. [الملاحق](#8-الملاحق)
9. [الإصلاحات المنفَّذة فعلياً: دليل «لا ليالٍ مكررة»](#9-الإصلاحات-المنفَّذة-فعلياً-دليل-لا-ليالٍ-مكررة)

---

## 0. تصحيح أساس التقرير: D1 وليس Appwrite

المسودة المرجعية التي طُلب تحديثها بُنيت على افتراض أن `mobile/` يزامن **Appwrite Cloud**. هذا غير صحيح على هذا الفرع، وأي خطة إصلاح مبنية على هذا الافتراض ستضرب ملفات ودوال غير موجودة أصلاً — وقد تحذف/تعدّل مسارات لا علاقة لها بالمزامنة الحالية.

**الأدلة القاطعة داخل الكود:**

| الدليل | الموقع |
|---|---|
| `AppwriteSyncManager` لم يعد صنفاً — مجرد **typedef** لـ `CloudflareSyncManager` | `mobile/lib/services/cloudflare_sync_manager.dart:4485` |
| `appwrite_sync_manager.dart` أصبح ملفاً من 4 أسطر يعيد تصدير مدير Cloudflare فقط | `mobile/lib/services/appwrite_sync_manager.dart:1-4` |
| `AppwriteRealtimeSync` = typedef لـ `CloudflareRealtimeSync` | `mobile/lib/services/cloudflare_sync_manager.dart:4486` |
| التطبيق يهيّئ `CloudflareConfig` و`CloudflareSyncManager` ومهام WorkManager لمزامنة Cloudflare | `mobile/lib/main.dart:50-52, 341-360, 440-473` |
| تعليقات صريحة: `SecondaryAppwriteConfig removed (Cloudflare migration)` | `mobile/lib/main.dart:168, 322` |
| نقاط النهاية الفعلية: `${CloudflareConfig.workerUrl}/api/sync/push` وسحب مؤشر-based | `mobile/lib/services/cloudflare_sync_manager.dart:1512` |
| Worker يخدم D1 عبر `wrangler.toml` (قاعدة `marina-hotel-db`) | `worker/wrangler.toml:8-11` |

**النتيجة العملية:** أسماء `Appwrite*` في الكود والوثائق (مثل `APPWRITE_*.md` داخل `mobile/`) هي **بقايا توافق تسمية** فقط. مصدر الحقيقة للمزامنة هو:

- عميل: `mobile/lib/services/cloudflare_sync_manager.dart` (رفع outbox + سحب دلتا بمؤشر + ترجمة مفاتيح أجنبية + حجر صحي للمؤشرات غير القابلة للحل).
- خادم: `worker/src/sync.ts` + `worker/src/database.ts` + مخطط `worker/schema.sql`.

### 0.1 ما ورد في المسودة مقابل الواقع على الفرع

| ما ورد في المسودة | الواقع على الفرع | التصحيح المطلوب |
|---|---|---|
| تضخّم في `Appwrite Cloud` | التضخّم (إن وُجد) اليوم في **D1** `booking_nights`، ويمكن أن يكون محلياً أيضاً | كل التحقيقات تُوجَّه إلى D1 + SQLite المحلي |
| `nights_snapshot_2026-11-23.json` | غير موجود في المستودع | الأرقام تُعامَل كبلاغ ميداني، مع استعلامات إعادة إنتاج (ملحق ب) |
| `financial_link_relink_service.dart` | **غير موجود** في `lib/services/sync_core/` | يجب كتابته (بند P1-2) |
| «درع الفقدان الصامت» `failedDocIds` + `throw StateError` في `_syncInventoryItems`/`_syncCashTransactions`/`_syncPriceAdjustments`/`_syncPaymentVoids` | **هذه الدوال غير موجودة**. المزامنة الحالية عامة على الكيانات (`_pushOutbox` / `_pullChanges` / `_applyChange`) وحمايتها الفعلية: `hadError` + عدم تقديم المؤشر + سلّم حجر | تُبنى الحماية على العقود الفعلية، لا على أسماء دوال وهمية |
| `_syncBookingNights`, `_syncPayments`, `_syncPaymentVoids`, `_relinkOrphanedBookingNights` | **غير موجودة** | نفس الملاحظة |
| «`PaymentsDao` يدعم البحث عبر `bookingUuidCache` في `list` و`watchList`» | **غير صحيح**: `list`/`watchList` تربط بـ `bookingLocalId` فقط (`payments_dao.dart:28-69, 108-131`)؛ المطابقة بـ UUID موجودة في `PaymentsRepository` فقط وبشكل جزئي | توحيد مسار الاستعلام (بند P1-1) |
| «حفظ أعلام الإلغاء والمناعة في `importFromJson`» | **غير صحيح**: `PaymentsDao.importFromJson` لا ينسخ `isVoided`/`voidedAt`/`voidedBy`/`voidReason`/`isImmutable`/`isPendingBalance`/`discountAmount`/`discountStartDate` (`payments_dao.dart:485-528`) | إصلاح فوري (بند P0-6) |
| «`RestoreFixService` يحافظ على `localUuid` لليالي الموجودة» | **غير صحيح**: الدالة تحذف **كل** ليالي النظام (`restore_fix_service.dart:716, 737`) ثم تعيد البناء بمفاتيح حتمية جديدة | إعادة تصميم النطاق (بند P0-4) |
| «`remainingBalance` محفوظ سالباً (رصيد دائن)» | صحيح في `calculateForBooking` (`enhanced_booking_calculation_service.dart:271-276`)، لكنه **مقصوص عند الصفر** في `_refreshCompletedStay` (`booking_derived_fields_service.dart:253`) وفي الاستعادة (`restore_fix_service.dart:897-900`) | توحيد عقد الرصيد (بند P0-5) |
| اختبارات `silent_loss_remaining_entities_regression_test.dart` وغيرها | **غير موجودة** | مصفوفة الاختبارات في القسم 6 |

> **قاعدة عمل:** أي بند في هذا التقرير لا يشير إلى `file:line` فعلي داخل الفرع يُعتبر غير موثّق ولا يُنفَّذ.

---

## 1. ملخص تنفيذي ودرجات الخطورة

### 1.1 الخلاصة في ثلاث نقاط

1. **الليالي (`booking_nights`) ليست كياناً محلياً مشتقاً "بريئاً" كما يفترض التعليق في `cloudflare_sync_manager.dart:2628-2637`**: هي تُدفع إلى D1 (برسائل رفع جزئية) وتُسحب منها وتُنافس على نفس الصف. لا يوجد في D1 أي قيد فريد على `(booking_uuid_cache, hotel_day_key)` ولا على `(booking_local_id, hotel_day_key)` — أي أن D1 **قادر بنيوياً** على تخزين عدد غير محدود من الليالي لنفس الحجز ونفس اليوم، بينما SQLite المحلي يسمح بواحد فقط لكل زوج **محلي**.
2. **ثلاث آليات مستقلة تُنتج التضخّم**: (أ) حذف صلب وإعادة إدراج بمفاتيح جديدة (`_replaceBookingNights`, الاستعادة)، (ب) رفع "update" بحمولة رقيقة `{localUuid}` يُترجم على الخادم إلى **create بقيم افتراضية** إذا لم يجد الصف → ليالٍ يتيمة `booking_local_id = 0` / `hotel_day_key = ''`، (ج) مفتاح فريد محلي جهازي (`booking_local_id`) لا معنى عالمي له، فينقسم نفس الحجز إلى عدة مجموعات.
3. **الخطر المالي الأكبر ليس في عدد الليالي بل في المجاميع**: مسار الإصلاح التلقائي بعد الاستعادة (`RestoreFixService`) يحتسب المدفوع **بما فيها الملغاة** (`restore_fix_service.dart:427-446`) ويقصّ الرصيد الدائن، و`importFromJson` يُسقط أعلام الإلغاء عند الاستعادة، و`watchTotalPaidForBooking` يحتسب الدفعات **المعلّقة** بينما محرك الحساب يستبعدها. أي أن نفس النزيل يظهر له رصيدان مختلفان حسب الشاشة.

### 1.2 جدول الخطورة

| # | المشكلة | الخطورة | نوع الأثر |
|---|---|---|---|
| P0-1 | حمولات ليالٍ رقيقة + تحويل update→create على الخادم | **حرج** | فقدان/توليد بيانات مالية |
| P0-2 | غياب قيد فريد على D1 لليالي | **حرج** | تضخّم لا نهائي + تقارير خاطئة |
| P0-3 | حذف صلب لليالي بلا tombstone في outbox | **حرج** | عودة الأيتام بالسحب + انحراف الأجهزة |
| P0-4 | `runAutoFixAfterRestore` يحذف كل الليالي ويعيد بناء التاريخ بسعر الغرفة الحالي | **حرج** | تدمير أسعار تاريخية + تضخّم |
| P0-5 | تعارض تعريف "المدفوع" بين 5 مسارات | **حرج** | أرصدة متضاربة مع النزيل |
| P0-6 | `PaymentsDao.importFromJson` يُسقط أعلام الإلغاء/المناعة | **حرج** | دفعات ملغاة تعود حيّة |
| P0-7 | سند الإلغاء (`payment_voids`) لا يُطبَّق على الدفعة عند السحب | **حرج** | إلغاء لا يصل للجهاز الآخر |
| P0-8 | `isVoided` يُحلّ بـ newerWins (غير رتيب) | عالٍ | إحياء دفعة ملغاة نتيجة تعارض |
| P1-1 | مطابقة المعرّف المحلي فقط في عدة مسارات قراءة | عالٍ | دفعات/ليالٍ تختفي من الواجهات |
| P1-2 | لا يوجد إصلاح روابط مالية (relink) لـ `booking_local_id` الفاسد | عالٍ | دين/دفعة على الحجز الخطأ |
| P1-3 | `booking_local_uuid` مقارنة حرفية بلا تطبيع في التعديلات السعرية | عالٍ | خصم لا يُطبَّق = مبالغة في المطالبة |
| P1-4 | `_fetchActiveAdjustments` يُسقط تعديلات بلا `roomNumber` أو بعد تغيير الغرفة | عالٍ | خصم مفقود |
| P1-5 | فحص السلامة لا يشمل تكرار الليالي ولا يناقض المجاميع المعلّقة | متوسط | لا كشف مبكر |
| P1-6 | `_dedupNaturalKeyOnInsert` يتجاهل الصفوف المحذوفة ناعماً ولا يحفظ ظل الخادم | متوسط | ليلة محذوفة لا تعود/يتيم دائم |
| P2-1 | ترحيل D1 يرسل `booking_local_id` خاماً بلا إزالة تكرار | متوسط | بذور تكرار عند الترحيل |
| P2-2 | القيود الفريدة المحلية لكيانات أخرى (مثل `payment_voids.original_payment_uuid`) بلا مفتاح طبيعي في السحب | متوسط | حجر صحي دائم للسند |
| P2-3 | غياب عدادات/تشخيصات للتكرار والانحراف قبل وبعد المزامنة | متوسط | زمن اكتشاف طويل |

---

## 2. الأخطاء المكتشفة في حساب الليالي

### 2.1 نموذج الهوية الحالي (وهو جذر المشكلة)

| الطبقة | المفتاح | المدى |
|---|---|---|
| SQLite المحلي (`booking_nights`) | `UNIQUE(booking_local_id, hotel_day_key)` — `mobile/lib/services/local_db.dart:518-520` | **جهاز واحد فقط** |
| SQLite المحلي | `local_uuid` فريد ضمنياً (Drift/SyncFields) | عالمي |
| D1 (`booking_nights`) | `local_uuid UNIQUE` فقط — `worker/schema.sql:400-436` | عالمي |
| D1 | **لا يوجد** أي فهرس فريد على `(booking_local_id, hotel_day_key)` أو `(booking_uuid_cache, hotel_day_key)` | — |

`booking_local_id` هو `AUTOINCREMENT` محلي (`local_db.dart:499`)، ويُرسَل إلى D1 كما هو في الترحيل (`cloudflare_migration_service.dart:184-193`). أي أن الرقم `5` على الجهاز A قد يكون الحجز "101" على الجهاز B. لهذا:

- المفتاح المحلي الوحيد لليلة **لا يعبّر عن هوية عالمية**.
- الليلة نفسها يمكن أن تُخزَّن مرتين على D1 إذا وصلت بمفتاحين محليين مختلفين (جهازان، أو استعادة أعادت ترقيم الحجوزات).
- السحب يستطيع حل المشكلة جزئياً عبر ترجمة `booking_uuid_cache → bookings.local_uuid` (`cloudflare_sync_manager.dart:2932-3040`)، لكن ذلك **لا يُصلح** الصفوف التي لا تحمل `booking_uuid_cache`، وهي جوهر المجموعة الثانية في البلاغ.

### 2.2 الآليات المولِّدة للتضخّم (مرتّبة بالأثر)

#### D-N1 — حمولة رفع رقيقة لليالي، وتحويل `update` الغائب إلى `create` بقيم افتراضية (الأخطر)

- المنتج الأول: `enhanced_booking_calculation_service.dart:465-475`
  ```dart
  'payload': <String, dynamic>{'localUuid': night.localUuid},
  ```
- المنتج الثاني: `booking_child_uuid_backfill_service.dart:132-142`
- منتج ثالث (شبه سليم لكن ناقص): `enhanced_booking_calculation_service.dart:352-365` يرسل فقط `deletedAt` و`lastModified` بلا بقية الصف.
- عقد الـ outbox **ينص صراحة** على أن «الصانع الجزئي يجب أن يرسل لقطة صف كاملة» (`outbox_dao.dart:283-286`).
- الخادم: إذا لم يجد صفاً بـ `local_uuid` لعملية `update` فإنه **يعيد تنفيذها كـ create** (`worker/src/database.ts:1446-1453`)، و`prepareInsertRow` يملأ أعمدة NOT NULL غير المزوّدة بقيم افتراضية `0` أو `''` (`worker/src/database.ts:1282-1302`).

**النتيجة:** صف في D1 بالشكل `booking_local_id = 0`, `hotel_day_key = ''`, `night_start = ''`, `final_rate = 0` — وهو **بالضبط** وصف المجموعة الثالثة (200 ليلة "يتيمة") في البلاغ. ولأنه لا يوجد قيد فريد، يُمكن أن يتكرر هذا لكل جهاز ولكل دورة.

#### D-N2 — حذف صلب وإعادة إدراج بمفاتيح جديدة (`_replaceBookingNights`)

`enhanced_booking_calculation_service.dart:659-800`:

1. يقارن كل ليلة محلية بـ `IdGen.bookingNightUuid(bookingUuid, day)`؛ أي اختلاف في `localUuid` (وهو حال كل الصفوف القديمة بعد إدخال المفتاح الحتمي) يُفعّل `shouldRebuild = true`.
2. `db.delete(db.bookingNights)` يحذف الصفوف فعلياً (`:726-733`) — **بلا** إدخال `op: 'delete'` في outbox.
3. يُدرج صفوفاً جديدة بالمفاتيح الحتمية (`:714-780`).
4. لا يُدرج في outbox إلا تحديث صف **الحجز** (`mergeBookingOutbox`, `:782-800`).

**الأثر المزدوج:**
- الليالي القديمة على D1 تبقى حيّة بمفاتيحها القديمة، ثم تعود بالسحب وتُدمج/تُضاف → مجموعات متعددة لنفس اليوم.
- تحويل كل الصفوف إلى المفاتيح الحتمية عند أول تشغيل بعد التحديث يُنتج **موجة إعادة ترقيم** واحدة ضخمة (تفسير معقول لمجموعة "rebuild" ذات الطابع الزمني الموحّد).
- الأيام التي اختفت من الإقامة (تقصير/مغادرة مبكرة) لا يُرسل لها tombstone من هذا المسار؛ الإخفاء الناعم موجود فقط في `refreshCompletedStay` (`enhanced_booking_calculation_service.dart:317-370`).

#### D-N3 — إعادة البناء الشاملة في الاستعادة

`runAutoFixAfterRestore` → `_rebuildBookingStructures` → `_rebuildBookingNights`:

- `await db.delete(db.bookingNights).go();` يحذف ليالي **كل** الحجوزات، بما فيها الحجوزات المغلقة تاريخياً (`restore_fix_service.dart:737`)، وكذلك `_handleEmptyBookings` (`:716`).
- يعيد البناء لجميع الحجوزات بسعر الغرفة الحالي (`calculateForBooking`) لا بالسعر المخزّن، خلافاً لعقد «الإقامة المنتهية لا تُعاد تسعيرتها» (`booking_derived_fields_service.dart:165-181`).
- يكتب `lastModified` للحقول المشتقة (`restore_fix_service.dart:938-941`) فيبدو الاشتقاق "تعديل مستخدم" ويفوز في LWW ويُدفع.
- لا تُدرج **أي عملية لليالي** في outbox (الحجز نفسه يُسجّل تحديثه عبر `bookingsDao.updateById`)، فيبقى D1 على حالة الليالي القديمة → أول سحب يعيد إليك ما حذفته، وقد يكتب فوق الاشتقاق الجديد.

#### D-N4 — ترجمة المفاتيح الأجنبية لا تُنقذ الليالي بلا `booking_uuid_cache`

`_resolveForeignKeysForRecord` يجرّب بالترتيب: `booking_uuid_cache` → ظلّ `server_id` → `server_booking_id` القديم → الاحتفاظ بالقيمة المحلية → تأجيل (`cloudflare_sync_manager.dart:2932-3040`). الليالي التي لا تحمل UUID (المجموعة الثانية في البلاغ: 1,975 ليلة) تعتمد على أرقام قد تتقاطع بين فضاء Appwrite القديم وفضاء D1، أو تُؤجَّل ثم تُحجَر. الحجر يحفظ الحمولة لكنه **لا يمنع** التكرار لاحقاً إذا وصل الأب بصفحة أخرى وطُبِّق الصف بمفتاح محلي مختلف.

#### D-N5 — المفتاح الطبيعي الوحيد في السحب لا يغطي الحالات الحقيقية

`naturalUniqueKeys` يعرّف مفتاحاً واحداً فقط (`mobile/lib/services/sync/pull_apply_rules.dart:36-38`):

```dart
'booking_nights': ['booking_local_id', 'hotel_day_key'],
```

- لا يغطي `(booking_uuid_cache, hotel_day_key)` — وهو المفتاح العالمي الحقيقي.
- `_dedupNaturalKeyOnInsert` يبحث بلا `deleted_at IS NULL` (`cloudflare_sync_manager.dart:3392-3412`)، فصف محلي محذوف ناعماً يحجب إدراج نسخة سحابية حيّة، أو يُدمج عليه فيعيد `deleted_at = null` إذا كان الوارد أحدث.
- عند الدمج، لا يُحفظ "ظلّ" `server_id` للصف السحابي المكرر، فتفقد الأبناء (دفعات/ملاحظات) مرجعها الرقمي.
- لا تُسجَّل النسخة المكررة في سجل تدقيق، فيظل التكرار **صامتاً** على الخادم بلا عدّاد.

#### D-N6 — الليالي تُقرأ في الواجهات بالمفتاح المحلي فقط

- `bookingNightsProvider`: `where(n.bookingLocalId.equals(bookingId))` فقط (`mobile/lib/providers/repository_providers.dart:587-597`).
- شاشة الدفع: تجمع `finalRate` على الصفوف وتستخدم `nights.length` كمقام لمتوسط السعر (`booking_payment_screen.dart:2575-2596`).
- مسار الامتداد: يجمع الليالي بـ `bookingLocalId` فقط (`booking_payment_screen.dart:1920-1945`).
- يوجد حارس جيد `BookingNightCoverage.completeForStay` (`mobile/lib/utils/booking_night_coverage.dart:9-46`) لكنه مستخدم في مسار واحد فقط (يسقط إلى حساب بديل عند أي نقص/تكرار).

**الأثر:** أي ليلة مربوطة بـ UUID لحجز لكن `booking_local_id` مختلف (نتيجة إصلاح ربط أو دمج) **تختفي** من واجهة النزيل؛ وأي تكرار يظهر في المجاميع ويحرّف المتوسط المستخدم في "تعديل السعر المتفق عليه". هذا يفسّر شكوى «الحساب لا يطابق الليالي».

#### D-N7 — مسار الترحيل يبذر التكرار

`CloudflareMigrationService.migrate` يقرأ **كل** صف محلي كما هو ويرسله SQL مباشر إلى D1، بما فيه `booking_local_id` و`local_uuid`، بلا إزالة تكرار ولا توحيد مفاتيح. أي تكرار محلي سابق (ناتج استعادة) يُصبح تكراراً سحابياً دائماً (`cloudflare_migration_service.dart:152-194`).

#### D-N8 — لا شيء يمنع ليلة بعد المغادرة من البقاء على D1

`refreshCompletedStay` يُخفي الليالي بعد المغادرة محلياً ويرسل تحديث `deletedAt` (`:317-370`)، لكن:
- `_replaceBookingNights` لا يفعل ذلك (D-N2).
- الاستعادة تحذف كل شيء وتعيد البناء بلا tombstone (D-N3).
- الخادم لا يُطبّق أي قاعدة عمل على الليالي (لا تحقق من `hotel_day_key` داخل نطاق الإقامة).

### 2.3 خريطة المجموعات الثلاث في البلاغ إلى الكود

| المجموعة (من البلاغ) | التوقيع | التفسير البرمجي المرجّح |
|---|---|---|
| 1,320 ليلة `rebuild_2026_10` — `bookingUuidCache != null` و`bookingLocalId == null`، `adjustment = 0` | مفاتيح مربوطة بحجز، بلا رابط محلي، بلا تعديلات | (أ) صفوف أُنشئت في **فضاء Appwrite** حيث `bookingLocalId` اختياري؛ (ب) بعد الترحيل إلى D1 لا يمكن تخزين `null` في `booking_local_id` (NOT NULL)، فالتوقيع على D1 يظهر كـ `0` أو رقم جهاز آخر. غياب `adjustment` يشير إلى إعادة بناء من مسار لا يجمع التعديلات (D-N2/D-N3). |
| 1,975 ليلة `server`/`secondary_backup` — `bookingUuidCache == null` و`bookingLocalId != null`، 115 رقماً متصادماً | روابط محلية بلا هوية عالمية | ترحيل خام (P2-1) + ليالٍ قديمة قبل `bookingUuidCache` + استعادة أعادت ترقيم الحجوزات. الأرقام المتصادمة هي `AUTOINCREMENT` بين أجهزة (D-N1, D-N4). |
| 200 ليلة `derived`/`server` — يتيمة تماماً | لا uuid ولا local id | **بصمة `prepareInsertRow`**: create من حمولة رقيقة → `booking_local_id = 0`، `hotel_day_key = ''`. هذا هو الدليل الأقوى على D-N1. |

> **ملاحظة دقة:** الأرقام الثلاثة مأخوذة من لقطة Appwrite-era؛ على D1 يجب إعادة إنتاجها بالاستعلامات في الملحق ب. التوقيعات أعلاه تشرح **كيف** سينتقل النمط نفسه إلى D1، لا أنها أرقام D1 الحالية.

---

## 3. تحليل مسارات مزامنة المدفوعات

### 3.1 المسارات الفعلية (كما هي في الكود)

| # | المسار | نقطة الدخول | الحمولة إلى outbox | ملاحظات |
|---|---|---|---|---|
| P-A | إنشاء دفعة | `PaymentsDao.insertOne` (`payments_dao.dart:315-376`) | **لقطة صف كاملة** عبر `adapters.payments.toJsonForSource` (`:446-476`) | سليم |
| P-B | تعديل دفعة | `PaymentsDao.updateById` (`:393-431`) | لقطة كاملة | سليم |
| P-C | حذف ناعم | `PaymentsDao.softDelete` (`:433-458`) | لقطة كاملة بـ `deletedAt` | سليم |
| P-D | إلغاء دفعة | `PaymentVoidService.voidPayment` (`payment_void_service.dart:65-230`) | (1) `payment_voids:create` بحقول السند، (2) `payments:update` **بلقطة كاملة** بعد تحديث الأعلام | أُصلح في 2026-09-14 داخل الخدمة نفسها (`:195-223`) |
| P-E | سحب دفعات | `_pullChanges → _applyChange` (`cloudflare_sync_manager.dart:3072-3380`) | — | LWW بـ `updated_at` + `version`، مع `_resolveForeignKeysForRecord` لربط الحجز |
| P-F | سحب إلغاءات | نفس المسار، كيان `payment_voids` | — | **لا يوجد أي أثر على صف الدفعة** |
| P-G | إعادة حساب الحقول المشتقة بعد السحب | `_refreshDerivedAfterPull` (`:3942-3958`) لكل حجوزات نشطة | `enqueueOutbox:false` | سليم مبدئياً، لكنه يعتمد على دوال الحساب المعطوبة في P0-5 |

### 3.2 نقاط الضعف في المسار (بالترتيب)

#### P-1 — سند الإلغاء لا يُطبَّق عند السحب (فجوة حرجة)

`_applyChange` عام تماماً، ولا يوجد أي معالج خاص بـ `payment_voids` يُحدّث `payments.isVoided`. التحقق: البحث عن `originalPaymentUuid` في كامل `lib/` لا يُظهر أي مستهلك خارج المحوّلات/التصدير (`payment_voids_adapter.dart`, `appwrite_sync_utils.dart`). أي أن:

- إذا وصل سند الإلغاء بدون وصول صف الدفعة المحدّث (فقد LWW، أو دفعة لم تُرفع بعد بسبب dead-letter، أو سند وصل لجهاز كان الدفعة عنده "أحدث") → **الدفعة تبقى حيّة في التقارير على ذلك الجهاز**.
- هذا يناقض العقد المكتوب في الخدمة نفسها: «يُرفع ذلك مع سجل payment_voids ليبقى السلوك متطابقاً على كل جهاز» (`payment_void_service.dart:167-170`).

#### P-2 — `isVoided` يُحلّ كحقل عادي (غير رتيب)

في `smart_conflict_resolver.dart:115-123` سياسة `payments` تجعل `isVoided` بـ `newerWins`. الإلغاء قرار **أحادي الاتجاه** (latch) لا يجوز أن يخسر أمام تعديل أحدث على نفس الصف. عملياً: أي تعديل لاحق على دفعة ملغاة (ملاحظة، مطابقة حجز) قد يعيد `isVoided = false` إذا كان الطابع/الإصدار أحدث.

#### P-3 — تعريف "المدفوع" غير موحّد (5 تعريفات مختلفة)

| الموضع | الاستبعادات | ملاحظة |
|---|---|---|
| `enhanced_booking_calculation_service._getTotalPayments` (`:581-606`) | deleted, voided, pending + `revenueType='room'` | التعريف المرجعي الأقرب للصحة |
| `restore_fix_service._recalculateBookingFinancials` (`:857-890`) | deleted فقط | **يشمل الملغاة والمعلّقة** → تضخيم |
| `payments_repository.watchTotalPaidForBooking` (`:324-347`) | deleted, voided | **يشمل المعلّقة** |
| `sync_integrity_checker._checkBookingAmounts` (`:250-305`) | deleted, voided, pending, room | يطابق المرجعي |
| `booking_payment_screen` (جمع مباشر) (`:2596+`) | يعتمد على `paymentsByBooking` (UUID + مستبعد المحذوف فقط) | يشمل الملغاة والمعلّقة |

**الأثر:** نفس النزيل يظهر "مسدد" في شاشة، و"عليه مبلغ" في شاشة أخرى، و"مدفوع بالكامل" بعد تشغيل الإصلاح التلقائي. هذا هو أهم سبب لشكاوى الرصيد، وهو مستقل عن مشكلة الليالي.

#### P-4 — لا مفتاح طبيعي للمدفوعات في السحب

`naturalUniqueKeys` لا يعرّف مدفوعات. القيود المحلية الفريدة على المدفوعات غير موجودة أصلاً (لا `uniqueKeys` في جدول `Payments`, `local_db.dart:286-360`). النتيجة:

- استعادة نسخة احتياطية أنشأت `local_uuid` جديداً لنفس الإيصال → إيصالان في D1، كلاهما "حي".
- لا مجال لكشف ذلك إلا بمقارنة (حجز، مبلغ، تاريخ، طريقة، رقم مرجعي) — وهي مقارنة **بشريّة** لا آلية.

#### P-5 — إسقاط الأعلام عند الاستعادة

`PaymentsDao.importFromJson` (`:485-528`) لا ينسخ: `isVoided`, `voidedAt`, `voidedBy`, `voidReason`, `isImmutable`, `isPendingBalance`, `discountAmount`, `discountStartDate`, `idempotencyKey`, `vectorClock`, `deviceId`. يُستخدم في مسار التراجع عن الإصلاح التلقائي (`restore_fix_service.dart:1258-1262`) وفي أي استدعاء آخر للمستودع.

**النتيجة المباشرة:** دفعة ملغاة تعود إلى الحياة كدفعة محصّلة بعد أي تراجع/استعادة تمر بهذا المسار، والمجاميع تزيد.

#### P-6 — الدفعات المعلّقة (`isPendingBalance`) و"الديون المرتبطة"

`linkedDebtUuid` يُرحَّل ويُحفظ، لكن لا يوجد أي منطق سحب يربط سداد الدين بتحديث الدين (`debts.paidAmount/remainingAmount/isSettled`) عند وصول دفعة تحمل `linkedDebtUuid`. النتيجة احتمال ازدواج: الدين يبقى "غير مسدد" والسداد محسوب في المدفوعات، أو العكس حسب الجهاز الذي أنشأ السداد.

#### P-7 — لا كشف انحراف آلي بعد السحب

`_refreshDerivedAfterPull` يعيد الحساب لكنه لا يقارن بالنتيجة السابقة ولا يسجّل فرقاً، لذلك أي قفزة في `totalPaidCached` أو `remainingBalanceCached` تمر بصمت. لا يوجد "بصمة مالية" يمكن مقارنتها بين الأجهزة.

---

## 4. مخاطر اختلاف معرّفات الحجز والدفعات

### 4.1 نموذج المعرّفات

| المعرّف | المكان | عالمي؟ | يُستخدم خطأً في |
|---|---|---|---|
| `bookings.id` | SQLite محلي | ❌ | `payments_dao.list(bookingLocalId:)`, `bookingNightsProvider`, `_recalculateBookingFinancials`, `_fetchActiveAdjustments` (أحد الطرفين), ترحيل D1 |
| `bookings.server_id` | D1 id ظلّ | ✅ ظرفياً (فقط بعد أن يتعلمه الجهاز) | ترجمة FK (الخيار 2) |
| `bookings.local_uuid` | UUID | ✅ | المرجع الصحيح |
| `payments.booking_local_id` | عمود FK رقمي | ❌ | كل استعلامات DAO |
| `payments.booking_uuid_cache` | نص | ✅ | بعض الاستعلامات فقط |
| `payments.server_payment_id` | D1 id | ظرفي | `serverId` في outbox |

### 4.2 سيناريوهات الفساد المالي (كل منها قابل للحدوث بالكود الحالي)

1. **دفعة على الحجز الخطأ:** دفعة تحمل `booking_local_id = 7` (حجز "غرفة 101" على جهازها الأصلي) و`booking_uuid_cache` فارغ. بعد الترحيل والسحب على جهاز آخر، تُترجم بالخيار 4 («احتفظ بالقيمة المحلية») أو تُؤجَّل ثم تُحجَر. إن قُبلت كـ 7 على الجهاز الثاني (حجز مختلف تماماً) → **مبلغ يُنسب لنزيل آخر**.
2. **اختفاء دفعة من كشف النزيل:** دفعة صحيحة تحمل UUID صحيحاً لكن `booking_local_id` مختلف. `payments_dao.list(bookingLocalId:)` لا يراها → النزيل يظهر مديناً بمبلغ مدفوع. (`PaymentsRepository.paymentsByBooking` يراها، وهذا يجعل الشاشتين تختلفان.)
3. **ازدواج المدفوع عند الدمج:** إذا كانت للدفعة نسختان بـ `local_uuid` مختلفين (استعادة)، لا شيء يمنع احتسابهما معاً. يظهر النزيل "دافعاً أكثر" ثم يُقصّ ذلك عند الصفر (P0-5) فيختفي الفائض.
4. **إلغاء لا يُطبَّق:** انظر P-1. الأثر: تقارير اليوم تحتسب دفعة ملغاة.
5. **خصم لا يُطبَّق:** `bookingLocalUuid.equals(booking.localUuid)` مقارنة حرفية بين صيغتين (بشرطات/بدونها أو اختلاف حالة أحرف) في `booking_price_adjustment_service.dart:278-310` و`:803-830`، وفي `_fetchActiveAdjustments` (`enhanced_booking_calculation_service.dart:608-618`). لا تستخدم `BookingPaymentMatcher.uuidCandidates` المتاح. الأثر: **مطالبة النزيل بمبلغ أعلى من المتفق عليه** — وهو أخطر أثر على الثقة.
6. **تعديل على غرفة سابقة:** `_fetchActiveAdjustments` يرفض أي تعديل `roomNumber` فارغ أو مختلف عن غرفة الحجز الحالية (`:620-640`). بعد "نقل الغرفة" تبقى التعديلات على الغرفة القديمة → تُسقط. توجد دالة `transferAdjustmentsToRoom` لكنها لا تُستدعى تلقائياً من كل مسارات النقل.
7. **ليلة تُدمج في حجز آخر:** إن أخطأت ترجمة FK (رقم قديم صادف حجزاً آخر)، فإن `_dedupNaturalKeyOnInsert` سيدمج بيانات الليلة السحابية **فوق** حجز محلي مختلف (LWW)، فيتغيّر سعر ليلة في حجز لا علاقة له. لا شيء يسجّل ذلك كتعارض مالي.
8. **إعادة ترقيم الحجوزات بالاستعادة:** استعادة النسخة تحذف الحجوزات والمدفوعات وتعيد إدراجها بـ `id` المحفوظ (`bookings_dao.importFromJson` يحفظ `id`) لكن قد يتغيّر ترتيب/إسناد الليالي والأبناء بعد إعادة البناء.

### 4.3 كشف المخاطر آلياً

- `SyncIntegrityChecker` يمتلك فحصين قريبين: تطابق `total_paid_cached` مع المجموع الفعلي (`:250-305`)، وتعارض `payments.booking_local_id` مع مالك UUID (`:308-340`). لكنه:
  - لا يفحص الليالي إطلاقاً.
  - لا يُشغَّل تلقائياً قبل/بعد المزامنة.
  - لا يفحص الدفعات المعلّقة أو سندات الإلغاء اليتيمة.
- يوصى بتحويله إلى **بوابة** قبل أي مزامنة وبعدها (بند P1-5).

---

## 5. خطة إصلاح جذري مرتبة حسب الأولوية

> ترتيب التنفيذ إجباري: P0 يوقف النزيف، P1 يصلح الروابط، P2 يمنع الانحدار. لا يُنفَّذ أي بند من P1 قبل اكتمال P0-1..P0-4 لأن أي مصالحة على منطق معطوب ستُنتج فساداً جديداً.

### المرحلة P0 — إيقاف النزيف (أسبوع 1)

#### P0-1 — منع الحمولات الرقيقة وتوليد الأيتام على الخادم

**التغييرات:**

1. `mobile/lib/services/enhanced_booking_calculation_service.dart`: إنشاء دالة واحدة `_nightPayload(BookingNight)` تُرجع **لقطة صف كاملة** (بنفس مفاتيح `toJsonForSource`/`PayloadMapper`)، واستبدال الحمولات الرقيقة في `:465-475` و`:352-365`. أفضل: إضافة `toJsonForSource` لمحوّل `booking_nights` القائم واستخدامه كما يفعل `PaymentsDao._payloadForLocalUuid` (`payments_dao.dart:443-476`).
2. `mobile/lib/services/booking_child_uuid_backfill_service.dart:132-142`: نفس المعالجة.
3. `worker/src/database.ts:1446-1453`: **لا** تحويل `update` غائب إلى `create` لكيانات «عالية الخطورة» (`booking_nights`, `payments`, `debts`, `booking_price_adjustments`) إلا إذا كانت الحمولة تحمل الحد الأدنى من الحقول الدلالية:
   - `booking_nights`: `booking_uuid_cache` (أو `booking_local_id` مع `hotel_day_key` و`night_start` و`final_rate`).
   - `payments`: `amount` و`payment_date` و`payment_method` و`revenue_type`.
   وإلا → `validation_error` (يفشل العميل بـ dead-letter واضح بدل صف يتيم).
4. `worker/src/database.ts:1282-1302`: منع ملء `booking_local_id` بـ `0` لكيان الليالي؛ اعتبار غيابه خطأ تحقق لا قيمة افتراضية.

**معيار القبول:** لا يمكن أن يوجد في D1 صف `booking_nights` بـ `booking_local_id = 0` أو `hotel_day_key = ''` أو `night_start = ''` بعد النشر (اختبار + استعلام مراقبة يومي).

#### P0-2 — فرض الهوية العالمية لليلة على D1

**التغييرات:**

1. هجرة جديدة `worker/migrations/0019_booking_nights_identity.sql`:
   - توحيد `booking_uuid_cache` للحالات القابلة للحل من `booking_local_id` عبر JOIN محلي على الخادم غير ممكن (D1 لا يعرف ids الأجهزة)، لذلك الهجرة تُنشئ الفهرس فقط:
     ```sql
     CREATE UNIQUE INDEX IF NOT EXISTS idx_booking_nights_uuid_day
       ON booking_nights(booking_uuid_cache, hotel_day_key)
       WHERE deleted_at IS NULL AND booking_uuid_cache IS NOT NULL;
     ```
   - **قبل** إنشاء الفهرس: تشغيل سكربت إصلاح (القسم 7) يحوّل التكرار إلى tombstone للأقدم، وإلا فشلت الهجرة.
2. `worker/src/database.ts`: عند `create` لليلة، تحقق من وجود صف حي بنفس `(booking_uuid_cache, hotel_day_key)`؛ إن وُجد → طبّق LWW و **لا تُنشئ** صفاً ثانياً (نفس فلسفة `_dedupNaturalKeyOnInsert` المحلية).
3. `mobile/lib/services/sync/pull_apply_rules.dart:36-38`: إضافة المفتاح العالمي إلى جانب المفتاح المحلي:
   ```dart
   'booking_nights': ['booking_uuid_cache', 'hotel_day_key'],
   ```
   مع الاحتفاظ بالمفتاح المحلي كخطة ثانية في المنطق (وليس كمفتاح أول).
4. `cloudflare_sync_manager.dart:_dedupNaturalKeyOnInsert` (`:3386-3467`):
   - إضافة `AND deleted_at IS NULL` لمسبار الصف المحلي.
   - عند الدمج، تسجيل `sync_conflicts`/`audit_logs` بسجل «نسخة مكررة دُمجت» مع `local_uuid` الوارد و`server_id` (ظل) — بدل الطباعة الصامتة.

**معيار القبول:** استعلام الملحق ب-1 يُرجع صفر صفوف بعد الإصلاح، ويبقى صفراً بعد 3 دورات مزامنة كاملة من جهازين.

#### P0-3 — لا حذف صلب للّيالي؛ كل اختفاء tombstone

**التغييرات:**

1. `_replaceBookingNights` (`enhanced_booking_calculation_service.dart:659-800`):
   - بناء خريطة الليالي الحالية بمفتاح `hotelDayKey`.
   - بدل `delete` شامل: لكل مفتاح زال من التقسيم الجديد → تحديث `deletedAt` + `lastModified`، وإدراج `booking_nights:update` في outbox بحمولة **كاملة** (كما في `:352-365`).
   - لكل مفتاح موجود: `update` لقطة كاملة عند تغيّر أي رقم.
   - لكل مفتاح جديد: `create` لقطة كاملة بـ `localUuid = IdGen.bookingNightUuid(...)`.
2. إضافة "توقيع" لمنع إعادة الترقيم الجماعي: عند ربط ليلة قديمة بمفتاح غير حتمي، **حافظ على `localUuid` القديم** وحدّث `bookingUuidCache` فقط (كما يفعل `booking_child_uuid_backfill_service`)، بدلاً من حذفها وإعادة إنشائها بمفتاح جديد. المفتاح الحتمي يُستخدم فقط للصفوف **الجديدة**.

**معيار القبول:** إعادة حساب أي حجز 5 مرات متتالية لا تغيّر `local_uuid` لأي ليلة، ولا تُنتج أي عملية `delete` فورية، ولا يزيد عدد صفوف `booking_nights` المحلي أو على D1.

#### P0-4 — حصر إعادة البناء في الاستعادة وإيقاف تدمير التاريخ

**التغييرات:**

1. `restore_fix_service.dart:737`: إلغاء `delete(db.bookingNights).go()` الشامل. إعادة البناء فقط للحجوزات التي «تحتاج إصلاحاً» (`_getBookingsNeedingFix`) وللحجوزات النشطة، وباستخدام `refreshCompletedStay` للحجوزات المغلقة (أسعار مخزّنة).
2. الحفاظ على `localUuid` القائم لكل ليلة عند إعادة البناء (قراءة المفاتيح قبل الحذف، واستخدامها للصفوف المطابقة بالـ `hotel_day_key`).
3. عدم كتابة `lastModified` للحقول المشتقة (`:938-941`) — تُكتب `updatedAt` فقط، كما في `booking_derived_fields_service.dart:143-150`.
4. `_restoreFromSnapshot` (`:1225-1275`): إما أن تُستعاد الجداول الستة كاملة (بما فيها `booking_nights` و`booking_price_adjustments` و`payment_voids`) من لقطة **كاملة**، أو لا تُستعاد إطلاقاً. الوضع الحالي (حذف الليالي بلا استعادتها) غير مقبول.
5. لقطة الأمان `createLocalSnapshot` (`:126-160`) يجب أن تُضمّن `booking_nights` و`booking_price_adjustments` و`payment_voids`، وإلا فليست لقطة.

**معيار القبول:** اختبار على قاعدة إنتاج منسوخة: تشغيل `runAutoFixAfterRestore` ثم مقارنة `SUM(final_rate)` لكل حجز — الفرق يجب أن يكون صفراً للحجوزات المغلقة.

#### P0-5 — تعريف مالي واحد مرجعي

**التغييرات:**

1. إنشاء `mobile/lib/services/finance/canonical_balance.dart` بدالة واحدة:
   ```dart
   // المدفوع الفعلي لحجز: deleted IS NULL, isVoided=0, isPendingBalance=0,
   // revenueType ∈ ('room','',NULL), والربط UUID أولاً ثم local id.
   Stream<double> watchPaidForBooking(...);
   double paidForBookingSync(...);
   ```
2. إحلالها في: `_getTotalPayments`, `watchTotalPaidForBooking`, `_recalculateBookingFinancials`, `sync_integrity_checker._checkBookingAmounts`, وشاشة الدفع.
3. توحيد عقد الرصيد: `remaining = totalDue - totalPaid` **بلا قص** في كل المسارات (`booking_derived_fields_service.dart:253`, `restore_fix_service.dart:897-900`)، مع علم `hasCredit` وعرضه، وعدم تحويله تلقائياً إلى دين.
4. تثبيت قاعدة: `isPendingBalance` ليس محصّلاً ولا ديناً — يُعرض منفصلاً.

**معيار القبول:** لكل حجز في قاعدة اختبار (20 حالة معروفة): `totalPaidCached` == المبلغ المرجعي، و`remainingBalanceCached` == `totalDue - paid` (قد يكون سالباً)، في كل الشاشات الخمس.

#### P0-6 — إصلاح استيراد المدفوعات

**التغيير:** `payments_dao.dart:485-528` — إضافة كل الأعلام والحقول المالية المفقودة، مع اختبار يقارن `exportToJson → importFromJson` دورة كاملة (round-trip) لكل عمود.

**معيار القبول:** دورة تصدير/استيراد تحفظ `isVoided`, `voidedAt`, `voidedBy`, `voidReason`, `isImmutable`, `isPendingBalance`, `linkedDebtUuid`, `discountAmount`, `discountStartDate`, `bookingUuidCache`, `hotelDayKey` (اختبار يسرد الأعمدة آلياً ضد `Payments().columns`).

#### P0-7 — تطبيق سند الإلغاء عند السحب

**التغييرات:**

1. `cloudflare_sync_manager.dart:_applyChange` — بعد تطبيق ناجح لكيان `payment_voids`، تنفيذ:
   ```sql
   UPDATE payments
      SET is_voided = 1, voided_at = ?, voided_by = ?, void_reason = ?,
          is_immutable = 1, last_modified = MAX(last_modified, ?), version = version + 1
    WHERE local_uuid = ?
      AND (is_voided = 0 OR is_voided IS NULL);
   ```
   بلا لمس `amount`/`payment_date`/`booking_local_id`. وإن لم توجد الدفعة → حفظ "سند معلّق" (سجل انتظار) وإعادة المحاولة بعد وصولها.
2. إضافة `payment_voids` إلى `_derivedRefreshEntities` (موجود) + إعادة حساب الحجز المتأثر فوراً عبر `refreshForBookingId` بالـ `booking_uuid` من السند.
3. تسجيل `audit_logs` لكل تطبيق سند (من، متى، أي دفعة).

**معيار القبول:** سيناريو جهازين: إلغاء على A، سحب على B → `payments.isVoided = 1` و`totalPaidCached` ينقص بالمبلغ على B خلال دورة واحدة.

#### P0-8 — `isVoided` قرار رتيب

**التغييرات:**

1. `smart_conflict_resolver.dart:120`: بدل `newerWins` → قاعدة `latchTrue` (جديدة) أو `localWins` مع تحقق: `isVoided = local || remote`. نفس المعالجة في `worker/src/database.ts` عند الدمج (يجب أن يكون القرار على الخادم أيضاً، لا في العميل فقط).
2. `payments.isImmutable = true` يعني رفض أي تعديل على المبلغ/التاريخ من أي جهاز (تحقق خادمي، لا واجهة فقط).

**معيار القبول:** اختبار تعارض: دفعة ملغاة على A + تعديل ملاحظة على B بطابع أحدث → النتيجة `isVoided = true` على الجهازين وعلى D1.

### المرحلة P1 — إصلاح الروابط والقراءات (أسبوع 2)

#### P1-1 — مطابقة موحّدة (UUID أولاً)

- `PaymentsDao.list`/`watchList`/`listFilteredByHotelDay`/`listForReport`: إضافة معامل `bookingUuid` واستخدام `uuidCandidates` مع شرط «UUID أولاً، وإلا local id فقط إذا كان UUID فارغاً» (نفس منطق `BookingPaymentMatcher.matches`).
- `bookingNightsProvider`: استخدام نفس المنطق (UUID أو local id) وفرز `hotel_day_key`.
- كل موضع يستخدم `bookingLocalUuid.equals(...)` → `isIn(uuidCandidates(...))`: `booking_price_adjustment_service.dart:278-310, 803-830`، `enhanced_booking_calculation_service.dart:608-618`.
- كل استعلام يربط دفعات بحجز بـ `bookingLocalId` وحده: `restore_fix_service.dart:427-446`.
- استبدال `nights.length` بمصدر موثوق (`calculatedNights` أو `BookingNightCoverage`) في حساب المتوسط (`booking_payment_screen.dart:2596`).

#### P1-2 — خدمة إصلاح الروابط المالية (المفقودة)

إنشاء `mobile/lib/services/sync_core/financial_link_relink_service.dart`:

- للجداول `payments`, `debts`, `booking_nights`, `booking_price_adjustments`.
- لكل صف يحمل `*_uuid_cache` صالحاً: إن كان `booking_local_id` فارغاً أو يشير إلى حجز مختلف → صحّحه إلى `bookings.id` المطابق للـ UUID.
- إن كان `booking_uuid_cache` فارغاً و`booking_local_id` يشير إلى حجز موجود → املأ `booking_uuid_cache` من الحجز.
- إن تناقض الاثنان → **UUID يفوز** (هو المفتاح العالمي)، ويُسجّل تعارض.
- تنفيذ التحديث محلياً فقط، بلا outbox (مصالحة محلية)، مع `audit_logs` وعدّاد.
- تشغيلها: عند الإقلاع بعد الاستعادة، وبعد كل سحب يحتوي تغييرات في الكيانات الأربعة، ومن شاشة الصيانة يدوياً.

#### P1-3 — حماية «لا ليالٍ مجانية» وحدود التعديل

- `StayBalanceCalculator` يقصّ التعديل عند `baseRate * 3` (`stay_balance_calculator.dart:272-273, 307-308`) — يجب توحيد السقف مع محرك الحساب (`enhanced_booking_calculation_service.dart:203-206` يقصّ عند `baseRate * 100`). اختلاف السقفين يعني سعرين مختلفين لنفس الليلة.
- منع `finalRate <= 0` لليلة إلا بسبب خصم موثّق (`appliedAdjustmentUuid` غير فارغ و`reason` غير فارغ).

#### P1-4 — التعديلات السعرية بعد تغيير الغرفة

- استدعاء `transferAdjustmentsToRoom` تلقائياً داخل مسار نقل الغرفة (حيث يُحدَّث `bookings.room_number`).
- أو إزالة شرط تطابق `roomNumber` من `_fetchActiveAdjustments` والاعتماد على `booking_local_uuid` فقط.
- اختبار: نقل غرفة ثم تعديل سعر ثم كشف حساب — لا فقدان خصم ولا تطبيق مزدوج.

#### P1-5 — بوابة سلامة قبل/بعد المزامنة

توسيع `SyncIntegrityChecker`:

- إضافة `booking_nights` إلى فحص تكرار `local_uuid` (`:174-186`).
- فحوص جديدة: (أ) تكرار `(booking_uuid_cache, hotel_day_key)`، (ب) ليالٍ يتيمة، (ج) ليالٍ خارج نطاق الإقامة، (د) `COUNT(nights)` مقابل `calculated_nights`، (هـ) سندات إلغاء بلا دفعة ملغاة، (و) دفعات معلّقة محسوبة في `totalPaidCached`.
- تشغيل تلقائي: قبل الرفع (سريع) وبعد السحب (كامل)، مع تسجيل النتائج في `audit_logs` وعدّاد يظهر في شاشة الصحة.
- **قاعدة النشر:** لا يُسمح بمزامنة إذا كانت الفحوص الحرجة (أ، ب، هـ) > 0 بعد الإصلاح؛ قبل الإصلاح تُسجّل فقط.

### المرحلة P2 — الوقاية والمراقبة (أسبوع 3)

- **P2-1:** ترحيل D1 (`cloudflare_migration_service.dart:152-194`) يجب أن يمر عبر `naturalUniqueKeys`/إزالة تكرار قبل الإرسال، وألا يرسل `booking_local_id` بلا `booking_uuid_cache`.
- **P2-2:** تعميم المفاتيح الطبيعية في السحب على الكيانات ذات القيود المحلية الفريدة: `payment_voids(original_payment_uuid)`, `salary_cycles(employee_id, cycle_key)`, `hotel_day_ledger(hotel_day_key)` — وإلا فالسند الصحيح قد يُحجَر للأبد.
- **P2-3:** لوحة "سلامة البيانات" في التطبيق: عدد المجموعات المكررة، اليتامى، انحراف المجاميع، عمر الحجر الصحي، آخر مصالحة — مع زر "تشخيص" (dry-run) وزر "إصلاح" (بتأكيد ونسخة احتياطية).
- **P2-4:** بصمة مالية لكل حجز (hash لـ `totalDue`, `totalPaid`, `remaining`, `COUNT(nights)`) تُقارن بين الأجهزة عند السحب؛ أي اختلاف يُسجَّل ويُعاد الحساب بدل المرور الصامت.

---

## 6. اختبارات إلزامية قبل اعتماد الإصلاح

> **حالة التنفيذ في هذه الجلسة:** بيئة العمل لا تحتوي Flutter/Dart (`which flutter dart` لا يُرجع شيئاً)، لذلك **لم يُشغَّل أي اختبار**. ما يلي هو بوابة القبول الإلزامية قبل الدمج.

### 6.1 اختبارات الوحدة (Drift على `NativeDatabase.memory()`)

| # | الملف المقترح | السيناريو | التأكيد |
|---|---|---|---|
| T-01 | `mobile/test/unit/booking_nights_identity_test.dart` | إعادة حساب نفس الحجز 5 مرات مع تغيير سعر الغرفة بينها | `local_uuid` ثابت لكل يوم، لا `delete` فوري، العدد ثابت |
| T-02 | نفس الملف | تقصير الإقامة (مغادرة مبكرة) | الليالي الزائدة `deleted_at != null` + سجل outbox بحمولة كاملة، ولا حذف صلب |
| T-03 | `mobile/test/unit/booking_nights_outbox_payload_test.dart` | كل منتج لحمولة `booking_nights` | الحمولة تحتوي `hotel_day_key`, `booking_uuid_cache`, `night_start`, `base_rate`, `final_rate`, `adjustment` (ليس `{localUuid}` فقط) |
| T-04 | `mobile/test/unit/booking_nights_pull_dedupe_test.dart` | صفّان سحابيان لنفس `(uuid, day)` بمفاتيح مختلفة وأزمنة مختلفة | صف محلي واحد، الأحدث بيانات، سجل تدقيق للدمج، لا استثناء UNIQUE |
| T-05 | نفس الملف | صف محلي محذوف ناعماً + صف سحابي حيّ بنفس اليوم | السلوك المعرّف صراحةً (إحياء أو تجاهل) — لا ازدواج ولا اختفاء صامت |
| T-06 | `mobile/test/unit/payments_import_flags_test.dart` | `exportToJson → importFromJson` | كل أعمدة `Payments` متساوية بما فيها أعلام الإلغاء/المناعة/المعلّق |
| T-07 | `mobile/test/unit/payment_void_pull_apply_test.dart` | سحب `payment_voids` لدفعة موجودة | `isVoided=1`, `isImmutable=1`, `totalPaidCached` ينقص، `audit_logs` سجل |
| T-08 | نفس الملف | سحب سند لدفعة غير موجودة | يُحفظ في سجل انتظار، ويُطبَّق بعد وصول الدفعة |
| T-09 | `mobile/test/unit/payment_void_monotonic_test.dart` | تعارض: إلغاء + تعديل أحدث | `isVoided` يبقى `true` محلياً وبعد الدمج |
| T-10 | `mobile/test/unit/canonical_balance_test.dart` | 6 تركيبات (ملغاة، معلّقة، محذوفة، non-room، UUID only، local only) | كل المسارات ترجع نفس الرقم |
| T-11 | `mobile/test/unit/credit_balance_test.dart` | دفع زائد ثم مغادرة مبكرة | `remainingBalanceCached < 0` في `calculateForBooking` و`refreshCompletedStay` و`runAutoFixAfterRestore` |
| T-12 | `mobile/test/unit/restore_autofix_scope_test.dart` | حجز مغلق تاريخي + حجز نشط + استعادة | ليالي الحجز المغلق وأسعاره لم تتغير؛ النشط أُعيد حسابه فقط |
| T-13 | `mobile/test/unit/financial_relink_test.dart` | دفعة/دين/تعديل/ليلة مع `booking_local_id` خاطئ و`uuid` صحيح | يُصحَّح الربط للـ UUID، والمبالغ لا تتغير، ولا كتابة outbox |
| T-14 | `mobile/test/unit/price_adjustment_uuid_normalization_test.dart` | صيغ UUID (بشرطات/بدون/أحرف كبيرة) | الخصم يُطبَّق دائماً مرة واحدة فقط |
| T-15 | `mobile/test/unit/nights_coverage_ui_test.dart` | تكرار/نقص ليالٍ ثم شاشة الدفع | لا تُستخدم `nights.length` كمقام؛ القيمة من `calculatedNights`/`BookingNightCoverage` |
| T-16 | `mobile/test/unit/sync_integrity_gate_test.dart` | قاعدة بها تكرار ليالٍ + سند معلّق | البوابة تُرجع حالات حرجة وتوقف المزامنة (قبل الإصلاح: تسجيل فقط) |

### 6.2 اختبارات الخادم (`worker/test/*` — Vitest + D1 محلي)

| # | الملف | السيناريو | التأكيد |
|---|---|---|---|
| W-01 | `sync.nights.identity.test.ts` | `push` عملية `update` لليلة غير موجودة بحمولة رقيقة | `validation_error` (لا create بقيم افتراضية) |
| W-02 | نفس الملف | `create` لليلة موجودة بنفس `(uuid_cache, day)` | لا صف ثانٍ، LWW يُطبَّق، الاستجابة تُبلّغ `merged` |
| W-03 | `sync.payments.void.test.ts` | `create` سند إلغاء + `update` دفعة أقدم | الدفعة تبقى `is_voided=1` على D1 |
| W-04 | `schema.parity.test.ts` | فهرس الليالي الفريد موجود | `PRAGMA index_list('booking_nights')` يحتوي الفهرس الجزئي |
| W-05 | `sync.push.financial-atomicity.test.ts` (توسيع) | فشل إحدى عمليات الدفعة | لا تُطبَّق جزئياً؛ العميل لا يحذف من outbox |
| W-06 | `sync.pull.regression.test.ts` (توسيع) | سحب بعد إصلاح التكرار | لا صفوف مكررة، والمؤشر يتقدم |

### 6.3 اختبارات التكامل (جهازان + Worker وهمي)

| # | الملف | السيناريو |
|---|---|---|
| I-01 | `mobile/test/integration/two_device_nights_roundtrip_test.dart` | جهاز A يعدّل حجزاً → رفع → جهاز B يسحب → ليالٍ متطابقة (عدداً وأسعاراً و`local_uuid` لكل يوم)، ثم B يعدّل → A يسحب → نفس النتيجة |
| I-02 | `.../two_device_void_test.dart` | إلغاء على A، سحب على B، ثم تعديل على B، ثم سحب على A — لا إحياء للدفعة |
| I-03 | `.../restore_then_sync_test.dart` | استعادة على A ثم مزامنة كاملة → لا تكرار على D1، ولا عودة ليالٍ محذوفة |
| I-04 | `.../duplicate_backup_restore_test.dart` | استعادة نسخة تحتوي صفوفاً مكررة → المصالحة تُنتج صفاً واحداً لكل (حجز، يوم) مع tombstone للباقي |

### 6.4 اختبار البيانات الحقيقية (Golden copy)

- نسخة من D1 الحقيقية (مُصدَّرة) أو `JSON` من الجهاز.
- تشغيل استعلامات الملحق ب قبل/بعد.
- **شروط القبول الرقمية:**
  - `night_groups_duplicated = 0`
  - `night_orphans = 0`
  - `voids_without_voided_payment = 0`
  - `cached_paid_mismatch = 0`
  - `nights_outside_stay = 0`
  - مجموع `final_rate` لكل حجز مغلق **لم يتغير** بالمقارنة مع لقطة ما قبل الإصلاح (فرق 0 لكل حجز).

### 6.5 أوامر التشغيل

```bash
# العميل
cd mobile
flutter pub get
flutter analyze lib/services lib/providers
flutter test test/unit/booking_nights_identity_test.dart \
             test/unit/booking_nights_outbox_payload_test.dart \
             test/unit/booking_nights_pull_dedupe_test.dart \
             test/unit/payments_import_flags_test.dart \
             test/unit/payment_void_pull_apply_test.dart \
             test/unit/payment_void_monotonic_test.dart \
             test/unit/canonical_balance_test.dart \
             test/unit/credit_balance_test.dart \
             test/unit/restore_autofix_scope_test.dart \
             test/unit/financial_relink_test.dart
flutter test test/integration/two_device_nights_roundtrip_test.dart
flutter test   # الحزمة كاملة — يجب ألا يكسر أي اختبار قائم

# الخادم
cd ../worker
npm ci
npx tsc --noEmit
npm test
```

**بوابة الدمج:** لا يُدمج أي بند P0 قبل نجاح T-01..T-12 + W-01..W-04 + I-01/I-02 و«شروط القبول الرقمية» على نسخة بيانات حقيقية.

---

## 7. مصالحة بيانات النزيل دون إفساد سجله المالي

### 7.1 المبادئ غير القابلة للتفاوض

1. **المدفوعات سجل غير قابل للحذف (append-only).** لا حذف صف دفعة، ولا تغيير مبلغ أو تاريخ دفعة قائمة. أي تصحيح مالي = سند إلغاء (`payment_voids`) + دفعة بديلة عند اللزوم. المحذوف ناعماً يبقى محذوفاً ناعماً.
2. **الرصيد مشتق لا مخزَّن.** القيمة المخزّنة (`totalPaidCached`, `remainingBalanceCached`) هي **كاش**، ومصدر الحقيقة هو الصفوف. أي مصالحة تُعيد الحساب من الصفوف ولا تُعدّل الكاش يدوياً.
3. **UUID هوية، والمعرّف الرقمي عنوان جهاز.** لا يُستخدم `booking_local_id` كمفتاح عالمي، ولا يُعاد استخدامه أبداً.
4. **لا مصالحة بلا نسخة.** ملف SQLite + JSON كامل (بما فيه الليالي والتعديلات والإلغاءات) قبل أي كتابة، مع `run_id` في كل سجل تدقيق.
5. **Dry-run أولاً.** كل سكربت إصلاح يطبع «ما سيفعل» ويُخزّنه، ولا يكتب إلا بموافقة صريحة.
6. **قابلية الرجوع.** كل تغيير يُسجَّل (قبل/بعد) في `audit_logs` مع `run_id`، بحيث يمكن التراجع بالمقلوب.
7. **ثم أعِد التوزيع.** بعد إصلاح جهاز واحد، يجب أن يمر الإصلاح على D1 ثم يُسحب لكل الأجهزة. لا تعتمد على إصلاح محلي واحد.

### 7.2 الإجراء (Runbook) — بالترتيب

#### المرحلة 0: التجميد والنسخ

1. إيقاف المزامنة عن بُعد (kill switch: `CloudflareDualRunService`) — يمنع دورة مزامنة أثناء الإصلاح أن تعيد البيانات القديمة.
2. إيقاف `sync_enabled` محلياً على كل جهاز.
3. نسخ احتياطي:
   - ملف SQLite (`sqlite_backup_restore.dart`).
   - JSON كامل لكل الجداول (بما فيه `booking_nights`, `booking_price_adjustments`, `payment_voids`, `audit_logs`).
   - تصدير D1:
     ```bash
     cd worker
     npx wrangler d1 export marina-hotel-db --remote --output=backup_$(date +%F).sql
     npx wrangler d1 execute marina-hotel-db --remote --command "SELECT COUNT(*) FROM booking_nights"
     ```
4. توثيق «خط الأساس»: عدد الحجوزات، عدد الليالي، مجموع `final_rate` الكلي، مجموع المدفوعات الحية.

#### المرحلة 1: تشخيص بلا كتابة

- تشغيل استعلامات الملحق ب على D1 وعلى كل جهاز.
- إنتاج **ورقة عمل لكل نزيل** بالشكل:

| الحقل | القيمة |
|---|---|
| `booking.local_uuid` | … |
| `booking_local_id` (لكل جهاز) | … |
| `checkin` / `actualCheckout` | … |
| الليالي المتوقعة (`calculatedNights`) | … |
| الليالي الفعلية (حيّة) | … (مع قائمة `hotel_day_key`) |
| الليالي المكررة | … |
| المدفوع المرجعي | … |
| `totalPaidCached` الحالي | … |
| `totalDue` | … |
| الرصيد المرجعي | … (سالب = رصيد للنزيل) |
| الإلغاءات ذات الصلة | … |
| التعديلات النشطة | … |
| القرار | (أحد قرارات الجدول 7.4) |

#### المرحلة 2: خريطة الهوية (Canonical Map)

- لكل `booking_uuid`: اختر `id` محلياً لكل جهاز (لا يُغيَّر)، وحدّد `server_id` (D1 id) الظلّي.
- رتّب الليالي المرشّحة لكل (حجز، يوم) بمعيار الحسم التالي:
  1. الليلة التي `nightly_rate`/`final_rate` تطابق السعر التاريخي المتوقع (سعر الغرفة وقت الإقامة أو الليلة المخزّنة السابقة) — تُفضَّل.
  2. عند التعادل: الأقدم `created_at` (النسخة الأصلية) تُعتمد للهوية، والأحدث `updated_at` تُعتمد للبيانات.
  3. عند تناقض جوهري (سعر مختلف بلا سند تعديل): **لا تحسم آلياً** — تُدرج في قائمة مراجعة بشرية.
- الباقي = مرشّحون للأرشفة (tombstone).

#### المرحلة 3: إصلاح الليالي (المفتاح)

1. على D1: لكل مجموعة مكررة، أبقِ صفاً واحداً (`deleted_at IS NULL`) وحوّل الباقي إلى `deleted_at = الآن` + `updated_at` جديد (tombstone) — **لا DELETE**.
2. صحّح `booking_uuid_cache` للصفوف التي يمكن حلها (ليست يتيمة).
3. الصفوف اليتيمة (بلا uuid قابل للحل): انقلها إلى «أرشيف» بحالة `deleted_at` + سجل تدقيق يذكر الحمولة الأصلية، **بعد** موافقة بشرية.
4. الليالي الناقصة داخل نطاق الإقامة: أعِد توليدها من `booking` + سعر الغرفة المخزّن + التعديلات النشطة، بمفتاح `IdGen.bookingNightUuid`، وبـ `create` **لقطة كاملة**.
5. الليالي بعد `actualCheckout`: `deleted_at` + تحديث الحجز.
6. أنشئ الفهرس الفريد الجزئي (P0-2) بعد أن تصبح النتيجة صفر تكرار.

#### المرحلة 4: إصلاح الروابط المالية (بلا مساس بالمبالغ)

- `payments`, `debts`, `booking_price_adjustments`: UUID يفوز؛ يُعدَّل **عمود الربط فقط**.
- `payments.isVoided`: إن وُجد سند إلغاء حيّ → `true` + الأعلام المشتقة منه (بلا تغيير المبلغ).
- الدفعات المعلّقة: تبقى `isPendingBalance = 1` وتُستثنى من المجاميع، ولا تُحوّل إلى دين تلقائياً.
- الدفعات المكررة (نسختان لسند واحد): **لا تُحذف**؛ تُعالَج بـ:
  - إن كانت إحداهما نسخة استعادة (نفس المرجع/التاريخ/المبلغ ونفس الحجز): تُلغى الثانية بسند `voidReason = 'duplicate_restore_<run_id>'` (فتُستثنى من المجاميع ويبقى الأثر).
  - إن كانتا دفعتين حقيقيتين (نفس المبلغ في نفس اليوم) → تبقى الاثنتان، وتُدرج في قائمة «تحقق بشري» لأن الحذف هنا كارثة.

#### المرحلة 5: إعادة الحساب والتحقق

1. تشغيل `BookingDerivedFieldsService.refreshAllActiveBookings(enqueueOutbox: false)` بعد الإصلاح (وعلى كل جهاز بعد السحب).
2. إعادة الأرصدة المرجعية ومقارنة الكاش:
   - `|totalPaidCached - paidRef| < 0.01` لكل حجز.
   - `remaining = totalDue - paidRef` (بلا قص).
3. تشغيل بوابة السلامة (P1-5) — يجب أن تكون كل الحالات الحرجة = 0.

#### المرحلة 6: النشر والمراقبة

1. رفع الإصلاح من الجهاز المرجعي (outbox لقطات كاملة فقط، أو تطبيق مباشر على D1 ضمن سكربت مراجَع).
2. إعادة تفعيل kill switch تدريجياً: جهاز واحد → دورة سحب كاملة → تحقق → بقية الأجهزة.
3. خلال 72 ساعة: راقب يومياً: عدد المجموعات المكررة، عدد اليتامى، انحراف المجاميع، حجم الحجر الصحي، أي `validation_error` جديد.

#### المرحلة 7: الإقفال

- أرشف لقطة «بعد» + تقرير الفروق.
- سجّل في `audit_logs` سجل إقفال يحمل `run_id` والعدد النهائي.
- أضف «بصمة مالية» يومية (P2-4) لاكتشاف أي انحراف مستقبلي مبكراً.

### 7.3 مثال عملي: نزيل دفع زيادة ثم غادر مبكراً

**الواقع:** حجز 3 ليالٍ × 10,000 = 30,000. دفع 35,000. غادر بعد ليلتين.

**الخطر في الكود الحالي:**
- `refreshCompletedStay` يحذف الليلة الثالثة (سليم)، لكنه يقصّ `remaining = 30,000 - 35,000 = -5,000` إلى **0** (`booking_derived_fields_service.dart:253`) → يختفي رصيد النزيل الدائن.
- الإصلاح التلقائي قد يحتسب المدفوع مختلفاً (بلا استبعاد الإلغاءات) فيعطي رقماً ثالثاً.

**المعالجة الصحيحة:**
1. الليالي: ليلتان فقط حيّتان (الثالثة `deleted_at` مع tombstone — لا حذف صلب).
2. `totalDue = 20,000`، `paidRef = 35,000`، `remaining = -15,000` = **رصيد دائن 15,000** يُعرض صراحةً.
3. لا يُنشأ دين ولا يُقصّ الرصيد.
4. إن أراد المدير ردّ الفائض: يُنشأ **سند استرداد** (دفعة سالبة/نوع `refund`) أو `payment_void` لدفعة خاطئة — لا تعديل يدوي على `remainingBalanceCached`.
5. يُسجَّل كل ذلك في `audit_logs` مع `run_id`.

### 7.4 قرارات المصالحة حسب الحالة

| الحالة | القرار | ممنوع |
|---|---|---|
| ليالٍ مكررة لنفس (حجز، يوم) | صف واحد حيّ + tombstone للباقي | حذف صلب |
| ليلة يتيمة بلا حجز | محاولة ربط بـ UUID؛ فشل → أرشيف بـ tombstone + تدقيق | إسناد تخميني بحسب المبلغ/التاريخ |
| ليلة بعد المغادرة | إخفاء ناعم + إعادة حساب | حذف صلب أو تجاهل |
| ليلة ناقصة داخل الإقامة | إعادة توليد بمفتاح حتمي ولقطة كاملة | ترك النقص («يكفي المجموع») |
| دفعة على حجز خاطئ | تصحيح عمود الربط فقط بـ UUID | تعديل المبلغ أو الحجز للطرف الآخر |
| دفعة ملغاة بلا علم | إعادة تطبيق السند | حذف الدفعة |
| دفعتان متطابقتان | تحقق بشري؛ نسخة استعادة → إلغاء الثانية بسند | حذف إحداهما |
| رصيد دائن | إظهاره سالباً ومسار استرداد | قصّه إلى صفر أو تحويله لدين |
| دفعة معلّقة | تستثنى من المحصّل وتُعرض منفصلة | احتسابها مدفوعة |
| انحراف كاش الحجز | إعادة حساب من الصفوف | تعديل الكاش يدوياً |

### 7.5 معايير الإقفال (Sign-off)

- [ ] صفر مجموعات ليالٍ مكررة على D1 وكل جهاز.
- [ ] صفر ليالٍ يتيمة / خارج الإقامة.
- [ ] صفر سندات إلغاء بلا دفعة ملغاة.
- [ ] `totalPaidCached` == المرجعي لكل الحجوزات (فرق < 0.01).
- [ ] الرصيد الدائن يظهر سالباً في كل الشاشات للحالات المعروفة.
- [ ] مجموع `final_rate` للحجوزات المغلقة لم يتغير قبل/بعد.
- [ ] الحجر الصحي لا يحتوي `booking_nights` (أو مبرَّر بسجل).
- [ ] لا `validation_error` متكرر بعد النشر بـ 72 ساعة.

---

## 8. الملاحق

### الملحق أ — خريطة الأدلة (ملف:سطر)

| الموضوع | الدليل |
|---|---|
| typedef المزامنة | `cloudflare_sync_manager.dart:4485-4486` |
| بناء عملية الرفع من حمولة outbox | `sync/payload_normalizer.dart:125-185` |
| عقد «لقطة صف كاملة» | `daos/outbox_dao.dart:283-286` |
| حذف/إدراج الليالي بلا outbox | `enhanced_booking_calculation_service.dart:720-800` |
| حمولات رقيقة | `enhanced_booking_calculation_service.dart:354-365, 465-475`; `booking_child_uuid_backfill_service.dart:132-142` |
| المفتاح الحتمي | `utils/id.dart:10-21`; `enhanced_booking_calculation_service.dart:669-672`; `restore_fix_service.dart:820-826` |
| المفتاح الفريد المحلي | `local_db.dart:498-520` |
| غياب الفهرس الفريد على D1 | `worker/schema.sql:400-436` |
| update→create على الخادم | `worker/src/database.ts:1446-1453` |
| ملء NOT NULL الافتراضي | `worker/src/database.ts:1282-1302` |
| إزالة تكرار المفتاح الطبيعي | `cloudflare_sync_manager.dart:3386-3467`; `sync/pull_apply_rules.dart:36-38` |
| ترجمة FK | `cloudflare_sync_manager.dart:2932-3040`; `sync/fk_rules.dart:80-120` |
| حجر/مؤشر السحب | `cloudflare_sync_manager.dart:2280-2430, 2600-2645` |
| تطبيق الإلغاء (محلي فقط) | `payment_void_service.dart:65-230` |
| سياسة `isVoided` | `sync_core/smart_conflict_resolver.dart:115-123` |
| استيراد المدفوعات الناقص | `daos/payments_dao.dart:483-527` |
| استعلامات DAO بالمفتاح المحلي | `daos/payments_dao.dart:45-71, 114-146` |
| مطابقة UUID في المستودع | `repositories/payments_repository.dart:169-200, 324-347` |
| قصّ الرصيد الدائن | `booking_derived_fields_service.dart:253`; `restore_fix_service.dart:897-900` |
| الرصيد بلا قص (المرجعي) | `enhanced_booking_calculation_service.dart:271-286` |
| الحذف الشامل في الاستعادة | `restore_fix_service.dart:716, 737` |
| كتابة lastModified للاشتقاق | `restore_fix_service.dart:938-941` |
| احتساب الملغاة في الإصلاح | `restore_fix_service.dart:427-446` |
| لقطة أمان ناقصة | `restore_fix_service.dart:126-160` |
| المدفوعات المعلّقة في مجموع الشاشة | `repositories/payments_repository.dart:336-346` |
| سقوف التعديل المختلفة | `stay_balance_calculator.dart:272-273`; `enhanced_booking_calculation_service.dart:203-206` |
| حارس تغطية الليالي | `utils/booking_night_coverage.dart:9-46` |
| فحص السلامة الحالي | `services/sync_integrity_checker.dart:174-186, 250-340` |
| ترحيل D1 الخام | `cloudflare_migration_service.dart:152-194` |

### الملحق ب — استعلامات التشخيص (read-only)

> على D1: `cd worker && npx wrangler d1 execute marina-hotel-db --remote --command "<SQL>"`
> محلياً: نفس SQL في `sqlite3` على نسخة من ملف قاعدة الجهاز.

**ب-1) مجموعات الليالي المكررة بالهوية العالمية**

```sql
SELECT COALESCE(booking_uuid_cache, '<null>') AS booking_uuid,
       hotel_day_key,
       COUNT(*) AS rows,
       COUNT(DISTINCT local_uuid) AS uuids,
       MIN(created_at) AS first_created,
       MAX(updated_at) AS last_updated
FROM booking_nights
WHERE deleted_at IS NULL
GROUP BY booking_uuid_cache, hotel_day_key
HAVING COUNT(*) > 1
ORDER BY rows DESC;
```

**ب-2) تكرار بالمفتاح المحلي**

```sql
SELECT booking_local_id, hotel_day_key, COUNT(*) c
FROM booking_nights
WHERE deleted_at IS NULL
GROUP BY booking_local_id, hotel_day_key
HAVING c > 1;
```

**ب-3) الليالي اليتيمة**

```sql
SELECT n.local_uuid, n.booking_local_id, n.booking_uuid_cache,
       n.hotel_day_key, n.night_start, n.final_rate
FROM booking_nights n
LEFT JOIN bookings b
  ON b.local_uuid = n.booking_uuid_cache
 AND b.deleted_at IS NULL
WHERE n.deleted_at IS NULL
  AND (n.booking_uuid_cache IS NULL OR b.local_uuid IS NULL)
ORDER BY n.booking_local_id, n.hotel_day_key;
```

**ب-4) عدد الليالي مقابل المحسوب**

```sql
SELECT b.local_uuid,
       b.calculated_nights,
       b.total_nights_cached,
       COUNT(n.id) AS live_nights
FROM bookings b
LEFT JOIN booking_nights n
  ON n.booking_uuid_cache = b.local_uuid
 AND n.deleted_at IS NULL
WHERE b.deleted_at IS NULL
GROUP BY b.id
HAVING COUNT(n.id) <> COALESCE(b.calculated_nights, COUNT(n.id))
ORDER BY ABS(COUNT(n.id) - COALESCE(b.calculated_nights, 0)) DESC;
```

**ب-5) ليالٍ بعد المغادرة الفعلية**

```sql
SELECT n.local_uuid, n.hotel_day_key, b.local_uuid AS booking_uuid,
       b.actual_checkout
FROM booking_nights n
JOIN bookings b ON b.local_uuid = n.booking_uuid_cache
WHERE n.deleted_at IS NULL
  AND b.actual_checkout IS NOT NULL AND TRIM(b.actual_checkout) <> ''
  AND date(n.hotel_day_key) >= date(b.actual_checkout)
ORDER BY b.actual_checkout DESC;
```

**ب-6) دفعات على حجز يخالف UUID**

```sql
SELECT p.local_uuid AS payment_uuid,
       p.booking_local_id,
       b_uuid.id AS owner_of_uuid,
       p.amount, p.payment_date, p.is_voided
FROM payments p
JOIN bookings b_uuid
  ON b_uuid.deleted_at IS NULL
 AND TRIM(COALESCE(p.booking_uuid_cache,'')) <> ''
 AND lower(replace(trim(p.booking_uuid_cache),'-','')) =
     lower(replace(trim(b_uuid.local_uuid),'-',''))
WHERE p.deleted_at IS NULL
  AND (p.booking_local_id IS NULL OR p.booking_local_id <> b_uuid.id);
```

**ب-7) سندات إلغاء بلا دفعة ملغاة (انحراف P-1)**

```sql
SELECT v.local_uuid AS void_uuid,
       v.original_payment_uuid,
       p.local_uuid AS payment_exists,
       p.is_voided
FROM payment_voids v
LEFT JOIN payments p ON p.local_uuid = v.original_payment_uuid
WHERE v.deleted_at IS NULL
  AND (p.local_uuid IS NULL OR p.is_voided = 0);
```

**ب-8) مجموع كاش الحجز مقابل المرجعي**

```sql
SELECT b.local_uuid,
       b.total_paid_cached,
       (SELECT COALESCE(SUM(p.amount), 0) FROM payments p
         WHERE p.deleted_at IS NULL AND p.is_voided = 0
           AND p.is_pending_balance = 0
           AND (p.revenue_type = 'room' OR p.revenue_type = '' OR p.revenue_type IS NULL)
           AND (lower(replace(trim(p.booking_uuid_cache),'-','')) =
                lower(replace(trim(b.local_uuid),'-',''))
             OR ((p.booking_uuid_cache IS NULL OR TRIM(p.booking_uuid_cache) = '')
                 AND p.booking_local_id = b.id))
       ) AS paid_ref
FROM bookings b
WHERE b.deleted_at IS NULL
  AND ABS(b.total_paid_cached - (
        SELECT COALESCE(SUM(p.amount), 0) FROM payments p
         WHERE p.deleted_at IS NULL AND p.is_voided = 0
           AND p.is_pending_balance = 0
           AND (p.revenue_type = 'room' OR p.revenue_type = '' OR p.revenue_type IS NULL)
           AND (lower(replace(trim(p.booking_uuid_cache),'-','')) =
                lower(replace(trim(b.local_uuid),'-',''))
             OR ((p.booking_uuid_cache IS NULL OR TRIM(p.booking_uuid_cache) = '')
                 AND p.booking_local_id = b.id))
      )) > 0.01;
```

**ب-9) الدفعات المرشحة للتكرار (تحقق بشري — ليست حكماً آلياً)**

```sql
SELECT COALESCE(booking_uuid_cache,'<null>') AS booking_uuid,
       amount, payment_date, payment_method,
       COALESCE(reference_number,'-') AS ref,
       COUNT(*) AS copies,
       GROUP_CONCAT(local_uuid) AS uuids
FROM payments
WHERE deleted_at IS NULL AND is_voided = 0
GROUP BY booking_uuid_cache, amount, payment_date, payment_method, reference_number
HAVING COUNT(*) > 1
ORDER BY copies DESC, amount DESC;
```

**ب-10) مؤشرات صحية للوحة المراقبة**

```sql
SELECT
 (SELECT COUNT(*) FROM (
    SELECT 1 FROM booking_nights WHERE deleted_at IS NULL
    GROUP BY booking_uuid_cache, hotel_day_key HAVING COUNT(*) > 1)) AS dup_groups,
 (SELECT COUNT(*) FROM booking_nights n
    LEFT JOIN bookings b ON b.local_uuid = n.booking_uuid_cache
    WHERE n.deleted_at IS NULL AND b.local_uuid IS NULL) AS orphans,
 (SELECT COUNT(*) FROM booking_nights
    WHERE deleted_at IS NULL AND (hotel_day_key = '' OR night_start = '')) AS malformed,
 (SELECT COUNT(*) FROM payment_voids v
    LEFT JOIN payments p ON p.local_uuid = v.original_payment_uuid
    WHERE v.deleted_at IS NULL AND (p.local_uuid IS NULL OR p.is_voided = 0)) AS void_drift;
```

### الملحق ج — قواعد تصميم تُثبَّت في الكود (لمنع التكرار مستقبلاً)

1. **المشتق لا يُدفع إلا حين يكون تاريخاً غير قابل لإعادة الاشتقاق.** الليالي للحجوزات المغلقة تاريخ يجب حفظه؛ لغيرها يمكن إعادة اشتقاقه. عند الدفع، لقطة كاملة دائماً.
2. **لا `delete` على جداول متزامنة.** `deleted_at` + `op='update'` (أو `op='delete'` إذا كان الكيان يدعم tombstone) وبحمولة كاملة.
3. **كل جدول متزامن له مفتاح طبيعي عالمي معرّف في مكان واحد** (`sync/pull_apply_rules.dart`) ومطبَّق على الخادم أيضاً، لا على العميل فقط.
4. **`update` لا يُنشئ.** إن كان الصف غائباً فعلى الخادم أن يرفض أو يطلب `create` بحمولة كاملة.
5. **القرارات الأحادية (إلغاء، قفل، حذف) رتيبة** — لا تُحلّ بـ LWW.
6. **الرصيد الدائن قيمة قانونية** لا حالة خطأ. لا `clamp(0, …)` في أي مسار مالي.
7. **الاستعادة لا تعيد بناء ما لا تملك نسخته.** لقطة الأمان يجب أن تحتوي كل ما ستلمسه.
8. **كل إصلاح يُسجَّل بـ `run_id`** ويقبل dry-run، ويُقاس بمؤشرات قبل/بعد.

### الملحق د — حدود التحقق في هذا التقرير

- لم يُشغَّل أي اختبار ولا بناء (`flutter`/`dart` غير مثبّتين في بيئة العمل). تم التحقق فقط من تطابق الفرع (الملحق هـ) ومن صحة استشهادات `ملف:سطر` آلياً.
- لا وصول إلى D1 الإنتاجي ولا إلى لقطة `nights_snapshot_*.json`؛ الأرقام المذكورة (3,495 / 356 / 1,320 / 1,975 / 200 / 115) هي من بلاغ المستخدم، وتُعاد إنتاجها بالملحق ب.
- «لم أجد معالجاً لـ `payment_voids` عند السحب» مبني على فحص كامل لـ `lib/` عن `originalPaymentUuid` و`isVoided` في مسار السحب؛ إن أُضيف المعالج في فرع آخر، يجب تحديث P0-7.
- بند P0-2 يفترض إمكانية إنشاء فهرس فريد جزئي على D1 (مدعوم في SQLite/D1). إن رفض D1 الفهرس بسبب بيانات قائمة، فالإصلاح المسبق شرط لا خيار.
- ترتيب P0 إجباري: P0-1 وP0-2 معاً يوقفان التوليد، لكن P0-3/P0-4 يجب أن يسبقا أي مصالحة نهائية، وإلا عادت البيانات القديمة من D1 بعد الإصلاح.

---



### الملحق هـ — تثبيت المرجع على الفرع وتدقيق الاستشهادات (2026-11-23)

**1) التحقق من الفرع المطلوب**

| الخطوة | الأمر | الناتج |
|---|---|---|
| جلب الفرع | `git fetch origin feat/cloudflare-sync-execution` | `branch 'feat/cloudflare-sync-execution' -> FETCH_HEAD` |
| طرف الفرع | `git log -1 --format='%H %ad %s' FETCH_HEAD` | `6a1da1a5f8e79fa073efa492c1be2b0a05a3bd88` — 2026-11-21 — `fix(test): complete guest-credit port — unclamped balance + first-checkout rebuild` |
| مطابقة الشجرة | `git diff --stat HEAD FETCH_HEAD` | **فارغ** (صفر ملفات متغيرة) |
| مطابقة `mobile/` | `git diff --stat HEAD FETCH_HEAD -- mobile` | **فارغ** |
| عدد ملفات `mobile/lib/services` على الفرع | `git ls-tree -r --name-only FETCH_HEAD mobile/lib/services \| wc -l` | **231** |

**الاستنتاج:** فرع الجلسة مبني على **نفس** التزام طرف `feat/cloudflare-sync-execution`، وشجرة `mobile/` متطابقة بايتاً ببايت. لذلك كل ما في هذا التقرير مُقاس على الفرع المطلوب لا على نسخة أخرى. (لا يمكن لجلسة العمل الانتقال إلى فرع آخر أو الدفع إليه؛ الفرع مثبّت، لكن التطابق يغني عن الانتقال.)

**2) تدقيق آلي للاستشهادات**

تم فحص **37** استشهاداً `ملف:سطر` — كل استشهاد يقارن نص السطر الفعلي على `FETCH_HEAD` بما ادّعاه التقرير:

| النتيجة | العدد |
|---|---|
| مطابق تماماً | 32 |
| يحتاج تصحيح سطر (صُحِّح وأُعيد الفحص) | 5 |
| **الإجمالي بعد التصحيح** | **37 / 37 مطابق** |

الاستشهادات الخمسة التي صُحِّحت:

| الموضع | كان | صار | الدليل |
|---|---|---|---|
| حذف الليالي في `_replaceBookingNights` | `:706-714` | `:726-733` | مطلع `doWrite` في السطر 722 |
| نطاق نفس الدالة | `:700-800` | `:720-800` | نهاية إدراج الحجوزات في outbox ~800 |
| `PaymentsDao.list` و`watchList` | `:45-71, 114-146` | `:28-69, 108-131` | بداية الدالتين 28 و108 |
| `PaymentsDao.importFromJson` | `:483-527` | `:485-528` | بداية الدالة 485، نهايتها 528 |
| `_derivedRefreshEntities` | `:3926-3934` | `:3928-3936` | تعريف المجموعة في 3928 |

**3) إعادة التحقق عند أي تحديث للفرع**

```bash
cd /path/to/repo
git fetch origin feat/cloudflare-sync-execution
git diff --stat HEAD FETCH_HEAD          # يجب أن يبقى فارغاً قبل الاعتماد على هذا التقرير
git diff --stat HEAD FETCH_HEAD -- mobile worker   # نطاق التقرير تحديداً
```

إن ظهر أي فرق على `mobile/lib/services/` أو `worker/src/` أو `worker/schema.sql`، تُعاد مراجعة البنود P0-1..P0-8 قبل التنفيذ، لأن أي تعديل على `payload_normalizer.dart` أو `database.ts` قد يغيّر جذور المشكلة.

---

**الخلاصة النهائية:** المشكلة ليست «مزامنة Appwrite» ولا «دالة مفقودة واحدة». هي **ثلاث طبقات متراكبة**: (1) هوية محلية تُستخدم كأنها عالمية، (2) عقد رفع جزئي يسمح للخادم بتوليد صفوف يتيمة، (3) تعريفات مالية متعددة للمدفوع. الإصلاح الجذري = هوية UUID عالمية + منع الحمولات الجزئية + لقطة كاملة + tombstone بدل الحذف + تعريف مالي واحد + بوابة سلامة تمنع المزامنة عند وجود انحراف. المصالحة تُنفَّذ بعد ذلك فقط، وبـ dry-run ونسخة احتياطية وسجل تدقيق، وبقاعدة واحدة: **لا تُحذف دفعة، ولا يُقصّ رصيد دائن، ولا يُعاد ترقيم هوية.**

---

## 9. الإصلاحات المنفَّذة فعلياً: دليل «لا ليالٍ مكررة»

هذا القسم **سجل تنفيذ** لا خطة: كل بند أدناه موجود في الشجرة على فرع الجلسة، ومصحوب بموضعه الدقيق ودليل تحقق قابل لإعادة التشغيل. الشرط الحاكم الذي وضعه المستخدم — **«تأكد لا ليالي مكررة»** — يُعامَل هنا كاختبار قبول، لا كنية.

### 9.1 خريطة التغييرات (مواضع ما بعد الإصلاح)

| الطبقة | الملف | الموضع | ما تغيّر | الجذر الذي يغلقه |
|---|---|---|---|---|
| عميل | `mobile/lib/services/sync/booking_night_payload.dart` | `:23` (`BookingNightPayloadBuilder`)، `:43` (`enqueue`) | مصدر واحد لحمولة الليلة: **لقطة صف كاملة** من `NightsAdapter.toJson` بلا `id`، مع خيار `tombstonedAt` يُضيف حقول الموت ويرفع `version/lastModified` | الحمولات الرقيقة `{'localUuid': …}` |
| عميل | `mobile/lib/services/enhanced_booking_calculation_service.dart` | `:747` (`doWrite`)، `:789` (إعلان الموت)، `:944` (رفع الليالي) | إعادة كتابة `_replaceBookingNights`: لا حذف صامت، لا تغيير لهوية صف قائم، رفع كل ليلة بعد الكتابة | «حذف صفوف بلا إعلان» + «لا enqueue في مسار إعادة البناء» |
| عميل | نفس الملف | `:717-724` (فحص إعادة البناء) | أُسقط شرط «`localUuid == المفتاح الحتمي`» | حلقة إعادة بناء لا نهائية كانت تُبدّل الهويات كل دورة |
| عميل | `mobile/lib/services/adapters/nights_adapter.dart` | `:252-253` | `toJson` صار يُرسل `booking_uuid_cache` و`server_booking_id` (كانا يُسقطان) | استحالة حلّ الحجز على الخادم/الجهاز الآخر |
| عميل | `mobile/lib/services/booking_nights_integrity_service.dart` | `:118` (`audit`)، `:187` (`ensureNoDuplicates`)، `:294` (طيّ المجموعات)، `:498` (`_retireNight`) | بوابة سلامة: فحص + طيّ التكرار بمفتاح `(uuid الحجز، اليوم)` + إعادة ربط الصفوف المعلّقة + إعلان موت الزائد ثم إزالته محلياً | التكرار المحلي و«الليالي المعلّقة» على هوية حجز خطأ |
| عميل | `mobile/lib/main.dart` | `:457` | تشغيل البوابة عند كل إقلاع **قبل** أي مزامنة أو حساب مالي | بقاء التكرار يعيش بين الجلسات ويُحتسب مرتين |
| خادم | `worker/src/database.ts` | `:1637` (`normalizeBookingNightIdentity`)، `:1422` | ترجمة `booking_uuid_cache → bookings.id` قبل أي كتابة؛ رفض ما لا يُحلّ؛ اشتقاق الهوية من الصف القائم للحمولات القديمة | اعتبار المعرّف الرقمي المحلي هوية عالمية (115 معرّفاً متصادماً) |
| خادم | `worker/src/database.ts` | `:1720` (`bookingNightSlotGuard`)، `:1463` | إخفاء أي صف حيّ آخر لنفس (الحجز، اليوم) **داخل نفس الدفعة الذرّية** قبل الإدراج | صفّان حيّان لنفس الليلة على D1 |
| خادم | `worker/src/sync.ts` | `:125-143` | رفض `create` لليلة بلا `hotel_day_key` أو بلا هوية حجز (مع قبول العميل الأقدم عند وجود رابط رقمي) | توليد صفوف يتيمة بقيم `0`/`''` |
| خادم | `worker/schema.sql` | `:433` (حُذف القيد)، `:446` (الفهرس الجزئي) | إزالة `UNIQUE (booking_local_id, hotel_day_key)` وإضافة `UNIQUE (booking_uuid_cache, hotel_day_key) WHERE deleted_at IS NULL` | القيد الذي كان يرفض/يُتلف الليالي عبر الأجهزة |
| ترحيل | `worker/migrations/0018_booking_nights_identity_dedupe.sql` | كامل الملف | إعادة بناء الجدول بلا القيد المحلي → طيّ المكرر الحيّ → إخفاء اليتامى → إعادة ربط الأرقام بمعرّف الحجز الخادمي → فرض الفهرس الفريد | بيانات D1 القائمة اليوم (3,495 صفاً) |
| اختبار | `worker/test/sync.push.booking_nights.test.ts` | `:104` فما بعد (6 اختبارات) | تثبيت العقد: ترجمة الهوية، طيّ التكرار، رفض اليتامى، توافق الحمولة الرقيقة | منع الانحدار |

### 9.2 لماذا تمنع هذه التغييرات التكرار فعلياً (سلسلة السبب)

1. **هوية واحدة للليلة على الخادم.** `booking_local_id` رقم `AUTOINCREMENT` محلي للجهاز؛ لم يعد هوية. الخادم يستخرج `bookings.id` من `booking_uuid_cache` في كل `create/update`، فيصبح مفتاح الليلة `(uuid الحجز، اليوم)` — وهو ما لا يتغيّر بين الأجهزة.
2. **القيد القديم أُزيل لأنه كان جزءاً من العطل.** `UNIQUE (booking_local_id, hotel_day_key)` كان (أ) يرفض ليلة مشروعة عند تصادم الأرقام، (ب) يمنع «الإحلال» (إخفاء نسخة + إدراج بديل) لأن القيد غير مشروط بـ `deleted_at`. استُبدل بفهرس فريد **جزئي** على الهوية العالمية للصفوف الحيّة فقط.
3. **كل حذف صار مُعلَناً بلقطة كاملة.** لم يبقَ في العميل مسار يحذف ليلة محلياً ثم يترك نسختها على D1 («شبح» يعود بالسحب التالي). `_retireNight` و`doWrite` يُرسلان لقطة الصف كاملة + `deletedAt/version` قبل الحذف، فلا يتولّد على الخادم صف جديد بقيم `0`/`''`.
4. **إعادة البناء لم تعد تُبدّل الهويات.** الصفوف القائمة لليوم نفسه تُحدَّث في مكانها (نفس `local_uuid`)، فإعادة الحساب لا تُنشئ سلسلة هويات متعاقبة لنفس الليلة.
5. **قاعدة حلّ الأب على الجهاز الآخر صارت تعمل.** `mobile/lib/services/sync/fk_rules.dart:88` يحلّ `booking_local_id` أولاً عبر `booking_uuid_cache` (ثم ظلّ `server_id`). لكن `NightsAdapter.toJson` **لم يكن يُرسل** `booking_uuid_cache` ولا `server_booking_id` إطلاقاً (`nights_adapter.dart:252-253` بعد الإصلاح)، فكل ليلة تُرفع كانت تصل بلا مفتاح عالمي — وهذا بالضبط ما يفسّر كتلة الـ**1,975 صفاً** التي يُحلّ فيها الرقم المحلي على جهاز آخر إلى حجز مختلف. بعد الإصلاح: الرفع يحمل الهوية، والسحب يحلّها، فتنتهي «الليالي المعلّقة».
6. **بوابة على الإقلاع + درع على الخادم.** حتى لو وصل مكرر من جهاز لم يُحدَّث بعد، فإن `BookingNightsIntegrityService` يطويه محلياً ويُعلن موته، و`bookingNightSlotGuard` يطويه على D1 في نفس دفعة الكتابة. النتيجة: التكرار يُشفى ولا يُخزَّن.

### 9.3 التحقق المنفَّذ (قابل لإعادة التشغيل)

| # | الأمر | النتيجة |
|---|---|---|
| 1 | `cd worker && npx tsc --noEmit -p tsconfig.json` | نجح بلا أخطاء |
| 2 | `cd worker && npx vitest run` | **27 ملف / 328 اختباراً — كلها ناجحة** (منها 6 جديدة في `test/sync.push.booking_nights.test.ts`) |
| 3 | اختبارات الليالي الجديدة | `translates booking_local_id from the booking uuid…`، `collapses a second live night for the same (booking, day)…`، `rejects a night without hotel_day_key…`، `rejects a night whose booking uuid cannot be resolved…`، `lets a thin update payload inherit identity…`، `never creates a row from an update of an unknown thin payload` — كلها ✓ |
| 4 | تشغيل `0018` على قاعدة SQLite 3.40.1 فيها بيانات ملوّثة (6 صفوف: تكراران، يتيم، صف بلا cache) | بعد الترحيل: `duplicate_groups = 0`، `orphans = 0`، الصف المرتبط هو الفائز، والفهارس أُنشئت؛ وإعادة تشغيل الملف لا تُغيّر شيئاً (idempotent) |

**قبل الاعتماد على أرقام D1:** §5 يبقى صحيحاً — نفّذ استعلامات الملحق (ب) على نسخة الإنتاج قبل وبعد الترحيل، وسجّل الفرق، لأن التقرير لا يملك لقطة حيّة من D1.

### 9.4 ما لم يُتحقَّق منه في هذه البيئة (بصراحة)

- **لا توجد سلسلة أدوات Dart/Flutter في بيئة العمل** (`flutter`/`dart` غير مثبّتين)، فلم يُشغَّل `flutter analyze` ولا `flutter test` على تعديلات `mobile/`. المراجعة كانت ثابتة (قراءة أنواع ومسارات)، والملفات المعدّلة أربعة فقط.
- لذلك **يجب** قبل الدمج تشغيل:
  ```bash
  cd mobile
  flutter analyze lib/services/enhanced_booking_calculation_service.dart \
                  lib/services/booking_nights_integrity_service.dart \
                  lib/services/sync/booking_night_payload.dart \
                  lib/services/adapters/nights_adapter.dart lib/main.dart
  flutter test test/services/   # + اختبارات الليالي الموصوفة في §6
  ```
- الثقة الكاملة في منع التكرار على مستوى البيانات تأتي من ثلاثة مستويات: اختبارات الخادم (نُفِّذت)، ترحيل SQL (نُفِّذ)، واختبارات العميل (لم تُنفَّذ بعد). المستوى الثالث هو المتبقي قبل إعلان الإغلاق.

### 9.5 ترتيب النشر والتراجع

1. **نسخة احتياطية إلزامية:** `cd worker && npx wrangler d1 export marina-hotel-db --remote --output backup-before-0018.sql`.
2. **الترحيل أولاً:** `npm run db:migrate:booking-nights-identity:remote` — لأن شيفرة الخادم الجديدة تعتمد على غياب القيد المحلي (إخفاء + إدراج بنفس اليوم). تنفيذ الشيفرة قبل الترحيل يُفشل إدراج الليالي المتصادمة فقط (لا تلف بيانات)، لكن الترتيب الآمن هو الترحيل أولاً.
3. **ثم نشر العامل:** `npm run deploy`.
4. **ثم إصدار العميل** (يستفيد تلقائياً من `enqueue` الكامل + البوابة عند الإقلاع).
5. **التراجع:** للشيفرة `git revert`؛ للبيانات أعد تحميل `backup-before-0018.sql`. لا يوجد حذف صلب في أي خطوة (كل الطيّ عبر `deleted_at`)، فالتراجع لا يفقد صفاً.

### 9.6 المتبقي من الخطة (لم يُنفَّذ في هذه الجولة)

- **P0-5..P0-8 مالية:** توحيد تعريف «مسدَّد»، تطبيق `payment_voids` عند السحب، جعل `isVoided` أحادي الاتجاه، وإصلاح `importFromJson` الذي يُسقط أعلام الإلغاء. هذه مستقلة عن الليالي لكنها نفس العائلة (سجل مالي واحد لا خمسة).
- **المصالحة مع النزيل (§7):** تبقى كما هي: dry-run + نسخة احتياطية + سجل تدقيق، وبقاعدة «لا تُحذف دفعة، ولا يُقصّ رصيد دائن، ولا يُعاد ترقيم هوية».
- **تشغيل اختبارات العميل** أعلاه قبل الدمج.
