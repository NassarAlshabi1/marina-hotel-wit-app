# مواصفة المزامنة الكاملة — مسودة مرجعية لتطبيق Flutter/Dart

> **حالة الملف:** مسودة مرجعية (draft) للاستعمال في تطبيق Flutter/Dart. محتواها مستخرج **آلياً من المصدر** (`worker/src/database.ts`, `worker/schema.sql`, كيانات Room، `SyncWireFields.kt`, `SyncEpochs.kt`, `fk_rules.dart` في الفرع المرجعي) مع شروح منقولة من تعليقات الشيفرة نفسها — لا اجتهاد ولا أرقام محفوظة.

| البند | القيمة |
| --- | --- |
| تاريخ التوليد | 2026-10-08 |
| فرع الجلسة | `arena/be8302d7-marina-hotel-wit-app` |
| آخر التزام موثّق | `341f92fd` (سلسلة الإصلاح `c3bc16b5`…`d364b90b`) |
| الفرع المرجعي الدارتي | `feat/cloudflare-sync-execution` |
| قاعدة الدمج | `agent/android-cloudflare` (`d95974fc`) |
| كيانات السلك (المتزامنة) | 24 |
| جداول D1 (كلها) | 34 |
| كيانات Room (كلها) | 39 |

**إعادة التوليد:** `python3 docs/tools/generate_sync_spec.py` (يقرأ المخطط والكيانات وخرائط السلك من المصدر — لا قيم محفوظة).

**كيف تُقرأ:** الأقسام ١–٢ و٤–١٣ هي العقد (يجب أن تُطابقه أي جهة عميل)، والقسم ٣ فهارس حقول كاملة مولّدة لكل جدول. كل رقم في هذا الملف قابل للتحقق من الشيفرة المذكورة بجانبه؛ وما لم يُتحقق منه مُعلَم صراحةً.

## ١) المعمارية

### ١.١ الطبقات (وما يقابلها في Dart)

| الطبقة | عندنا (Kotlin) | المقابل الدارتي (الفرع المرجعي) | الدور |
| --- | --- | --- | --- |
| التخزين المحلي | Room (`AppDatabase`، schema 77) | Drift (`local_db.dart`) | 24 جدولاً متزامناً + جداول محلية |
| الوصول | `data/local/dao/*.dao.kt` | `services/daos/*.dart` | استعلامات + كتابات جزئية |
| المستودعات | `data/repository/*RepositoryImpl.kt` | `services/repositories/*.dart` | ختم الطوابع + `version+1` + outbox |
| صندوق الصادر | `OutboxRepository` + `outbox` | `OutboxDao` | طابور رفع + idempotencyKey |
| محرك المزامنة | `SyncManager` + `CloudflareSyncService` | `cloudflare_sync_manager.dart` | سحب/دفع/مؤشرات/مسح |
| استيعاب السحب | `SyncIngestorRegistry` | منطق `_applyRemoteRecord` في مدير المزامنة | ترجمة FK + LWW + عزل |
| الحقول المشتقة | `BookingDerivedRefreshService` | `booking_derived_fields_service.dart` | إعادة حساب الإجماليات المخزَّنة |
| الحيّ (Realtime) | `data/remote/realtime/*` | `cloudflare_realtime_sync.dart` | إشارات + debounce/cooldown |
| FCM | `MarinaMessagingService` | إشعار بيانات من الـWorker | إشارة «هناك تغيير» فقط |
| الـWorker | `worker/src/*.ts` (D1) | نفسه (خادم مشترك) | مصدر الحقيقة + مؤشر الدلتا |

**القاعدة الذهبية:** العميل لا يحسب الحقيقة النهائية للتزامن — الـWorker هو من يرتب الدلتا ويملك المؤشر و`version`، والعميل يُطبّق ويختم محلياً بعقد موحّد.

### ١.٢ دورة السحب (Pull) — خطوة بخطوة

```text
① إشارة (يدوي / Realtime / FCM / دوري كل ساعة) ⇒ بوابة AutomaticDeltaGate
② GET /api/sync/pull?cursor=<محفوظ>&limit≤500&entity?&exclude_device?&tombstones_only?&include_remaining?
③ لكل صفحة: SyncIngestorRegistry.ingestPage(records) داخل معاملة واحدة
     • توجيه الكيان (_entity أو بصمة الأعمدة)
     • ترجمة مراجع FK (fk_rules) — غير المحلول: تأجيل/عزل
     • تطبيع: الأسماء السلكية (aliases) → الافتراضيات → وحدة الطوابع (ثوانٍ)
     • قرار LWW: الوارد أحدث ⇒ استبدال؛ متعادل ⇒ الوارد؛ المحلي أحدث ⇒ تخطٍّ
       (إلا إن كان version الوارد أعلى ⇒ حارس انزياح الساعة M3)
     • tombstone ⇒ يُطبَّق دائماً (قرار نهائي) بحقول المزامنة فقط
④ حفظ المؤشر من قيمة cursor التي أعادها الخادم (لا من آخر صف طُبِّق)
⑤ بعد الدورة: مسح الحذفيات (tombstones_only=1) حتى 20 صفحة/دورة + إعادة بناء المشتقات
⑥ الحجر: صفوف غير قابلة للتطبيق تُعزل بحمولتها (attempts + firstSeen) ويستمر المؤشر
```

### ١.٣ دورة الدفع (Push)

```text
① كل كتابة محلية تُدرج صف outbox: entity + op(insert/update/delete) + local_uuid + payload(JSON) + idempotencyKey
② OutboxRepository.processPending(): دفعات ≤ PUSH_BATCH_SIZE ⇒ POST /api/sync/push {operations[]}
③ PushWireContract: camelCase→snake_case، bool→int، insert→create، blacklist_entries→blacklist،
   expenses بلا employee_uuid صريحة ⇒ حذف المفتاح + clear_employee_link=1، وتطبيع أعمدة الطوابع للثواني
④ استجابة الخادم: results[] لكل عملية (success/skipped/status) + summary —
   validation_error/conflict = رفض دائم ⇒ dead-letter (لا إعادة)، خطأ شبكة ⇒ requeue
⑤ بعد ≥5 محاولات (فيما عدا salary_withdrawals) ⇒ dead-letter بتشخيص
```

### ١.٤ التدفقات الحيّة والحراس

| المكوّن | العقد المختصر |
| --- | --- |
| Realtime (`/api/realtime`) | إشارة تغيير ⇒ debounce 500ms ⇒ دلتا واحدة بحد أدنى تبريد 15s؛ إعادة اتصال backoff 1s→60s (6 محاولات) ثم إعادة تسليح كل 120s؛ نبض 30s |
| FCM | رسالة بيانات فقط (لا تُحدِّث شيئاً بنفسها) ⇒ تُحوَّل إلى إشارة سحب بالمصدر `fcm` |
| Sweep | مسح تقارب للتمسّح الصامت: حتى 20 صفحة/دورة بمؤشر محفوظ لا يُضبط قبل الاكتمال |
| بوابة الدلتا | سقف دوري 60 دقيقة لا يُتجاوَز بالضغطة اليدوية المتكررة |
| مراقب المعلّقات | كل 5 دقائق: إن بقي معلّق ⇒ جدولة دفع |
| حراس المؤشر | رفض مؤشر مستقبلي (>2e9) أو متقدم على الخادم > 366 يوماً ⇒ لا تقدّم أعمى |

### ١.٥ خريطة الملفات

| الموضع عندنا | الملف |
| --- | --- |
| `data/sync/SyncEpochs.kt` | `mobile/android/app/src/main/kotlin/com/marina/marina/data/sync/SyncEpochs.kt` |
| `data/sync/SyncWireFields.kt` | `mobile/android/app/src/main/kotlin/com/marina/marina/data/sync/SyncWireFields.kt` |
| `data/sync/SyncEntityGson.kt` | `mobile/android/app/src/main/kotlin/com/marina/marina/data/sync/SyncEntityGson.kt` |
| `data/sync/PullSanityPolicy.kt` | `mobile/android/app/src/main/kotlin/com/marina/marina/data/sync/PullSanityPolicy.kt` |
| `data/sync/RemoteSignalPolicy.kt` | `mobile/android/app/src/main/kotlin/com/marina/marina/data/sync/RemoteSignalPolicy.kt` |
| `data/sync/AutomaticDeltaGate.kt` | `mobile/android/app/src/main/kotlin/com/marina/marina/data/sync/AutomaticDeltaGate.kt` |
| `data/repository/SyncManager.kt` | `mobile/android/app/src/main/kotlin/com/marina/marina/data/repository/SyncManager.kt` |
| `data/repository/SyncIngestorRegistry.kt` | `mobile/android/app/src/main/kotlin/com/marina/marina/data/repository/SyncIngestorRegistry.kt` |
| `data/repository/OutboxRepository.kt` | `mobile/android/app/src/main/kotlin/com/marina/marina/data/repository/OutboxRepository.kt` |
| `data/repository/BookingDerivedRefreshService.kt` | `mobile/android/app/src/main/kotlin/com/marina/marina/data/repository/BookingDerivedRefreshService.kt` |
| `data/remote/PushWireContract.kt` | `mobile/android/app/src/main/kotlin/com/marina/marina/data/remote/PushWireContract.kt` |
| `data/remote/realtime/RealtimePolicy.kt` | `mobile/android/app/src/main/kotlin/com/marina/marina/data/remote/realtime/RealtimePolicy.kt` |
| `data/local/AppDatabase.kt` | `mobile/android/app/src/main/kotlin/com/marina/marina/data/local/AppDatabase.kt` |
| `domain/util/StatusUtils.kt` | `mobile/android/app/src/main/kotlin/com/marina/marina/domain/util/StatusUtils.kt` |

| المرجع الدارتي | الملف |
| --- | --- |
| `mobile/lib/services/cloudflare_sync_manager.dart` | محرك السحب/الدفع الكامل + LWW + العزل |
| `mobile/lib/services/sync/fk_rules.dart` | قواعد ترجمة العلاقات (FK) |
| `mobile/lib/services/sync/pull_quarantine.dart` | سياسة الحجر (عتبة 3 + شفاء) |
| `mobile/lib/services/sync/pull_apply_rules.dart` | قواعد الدمج بالمفتاح الطبيعي |
| `mobile/lib/services/repositories/rooms_repository.dart` | refreshAllRoomOccupancy |
| `mobile/lib/utils/status_utils.dart` | مجموعات الحالات |
| `mobile/lib/services/booking_derived_fields_service.dart` | الحقول المشتقة |
| `mobile/lib/services/payment_void_service.dart` | إلغاء الدفعة (عقد كامل) |

### ١.٦ سجل التغييرات (ما تغيّر فعلاً — لا ادّعاء)

**جولة إغلاق §5 (2026-10-07/08) — سلسلة `c3bc16b5` … `341f92fd`:**

| الالتزام | التغيير | الأثر | الدليل |
| --- | --- | --- | --- |
| `c3bc16b5` | توحيد الزمن: كل مواضع الميلي في 13 مستودعاً ⇒ `SyncEpochs.nowSeconds()` + فصل صريح للحقول الزمنية-العملية | لا صف محلي بطابع ميلي يرفض تحديثات الخادم | CI `37698116017` + `RepositoryEpochParityTest` (10) |
| `c3bc16b5` | نقل `refreshAllRoomOccupancy` حرفياً + الاستدعاءان (حفظ الحجز/إتمام المغادرة) + حذف التقريب الموضعي | إشغال كل الغرف يُعاد ضبطه من الحجوزات النشطة كالمرجع | `RoomOccupancySweepParityTest` (6) |
| `c3bc16b5` | عطل `last_modified = 0`: 8 نداءات DAO جزئية + terminate/reactivate/updateSettlement/voidPayment/markRead/softDeleteItem | تعديلنا المحلي لم يعد يُطمس بأي صف خادمي ولو أقدم | `RepositoryEpochParityTest` |
| `c3bc16b5` | `updateComputedFields` لا يلمس `last_modified/version` (نصّ تعليق Dart) | فتح شاشة الدفع لم يعد يُفقد الصف أفضليته في LWW | `RepositoryEpochParityTest` |
| `c3bc16b5` | رصيد المخزون بعد الحركة: ختم ثوانٍ + `version+1` + رفع `inventory_items:update` | تغيير الرصيد صار يصل السحابة (كان محلياً فقط) | `RepositoryEpochParityTest` |
| `c3bc16b5` | `payment_voids` و`booking_price_adjustments` يُختمان بالثواني (كانت أصفاراً) | صفوف جديدة سليمة الطابع | `RepositoryEpochParityTest` |
| `c3bc16b5` | حارس انزياح الساعة M3 في LWW: `remote.version > local.version` ⇒ المضيّ بالوارد | لا فقد دائم لجهاز ساعته متقدمة | 3 اختبارات في `SyncIngestorRegistryTest` |
| `c3bc16b5` | `inventory_transactions.transaction_time` ×1000 من `created_at` | حركات المخزون الواردة صارت داخل نطاق تقارير الميلي | `SyncWireFieldParityTest` (قفل محدَّث بإفصاح) |
| `b3768022` | إصلاحا تصريف: ختم `BookingPriceAdjustment` على الصف؛ `secondsToMillis` يعيد `Any` | بناء أخضر | CI `37696113594` ⇒ `37696941360` |
| `14d768a8` | إغلاق تعليق Kotlin متداخل في KDoc | تصريف الاختبارات | CI |
| `4619441f` | تمرير `lastModified` في اختبار قديم بعد تغيّر توقيع DAO | تصريف الاختبارات | CI |
| `2b7af35d` | `SyncEntityGson`: تسلسل واعٍ بظلّ حقول `BaseSyncEntity` — **عطل حقيقي كشفه الاختبار**: حركات المخزون كانت لا تُرفع إطلاقاً | كل رفع كيان أصبح ممكناً + اختبار انحدار | CI `37696941360` ⇒ `37697574905` |
| `d364b90b` | تصحيح توقعات كمية في اختبارات جديدة (رصيد يبدأ من صفر) | اختبارات صحيحة | CI `37698116017` أخضر |
| `341f92fd` | توثيق §5 في `android-epoch-unit-parity.md` بأدلة التشغيل | إفصاح كامل | هذا الملف |

**جولات أسبق في الفرع نفسه** (للحدود الزمنية: `3e71420f` إصلاح جذر الوحدة، `f23eb8db` هجرة Room 76→77، `0f4d2d20` قفل `finance_snapshots`، `8cef717a` إغلاق F-1..F-4) — تفاصيلها في `docs/android-epoch-unit-parity.md` و`docs/merge-4df4118-review.md`.

---

## ٢) عقد السلك (D1 / Worker)

### ٢.١ جدول الكيانات ↔ الجداول

| الكيان (على السلك) | جدول D1 | جدول Room | صنف Kotlin | عدد أعمدة Room | عدد أعمدة D1 |
| --- | --- | --- | --- | --- | --- |
| `rooms` | `rooms` | `rooms` | `RoomEntity` | 27 | 26 |
| `bookings` | `bookings` | `bookings` | `BookingEntity` | 52 | 51 |
| `payments` | `payments` | `payments` | `PaymentEntity` | 45 | 44 |
| `expenses` | `expenses` | `expenses` | `ExpenseEntity` | 31 | 30 |
| `employees` | `employees` | `employees` | `EmployeeEntity` | 27 | 26 |
| `debts` | `debts` | `debts` | `DebtEntity` | 45 | 44 |
| `booking_notes` | `booking_notes` | `booking_notes` | `BookingNoteEntity` | 23 | 22 |
| `booking_nights` | `booking_nights` | `booking_nights` | `BookingNightEntity` | 32 | 31 |
| `booking_price_adjustments` | `booking_price_adjustments` | `booking_price_adjustments` | `BookingPriceAdjustmentEntity` | 33 | 32 |
| `guest_infos` | `guest_infos` | `guest_infos` | `GuestInfoEntity` | 28 | 27 |
| `shift_notes` | `shift_notes` | `shift_notes` | `ShiftNoteEntity` | 25 | 24 |
| `cash_transactions` | `cash_transactions` | `cash_transactions` | `CashTransactionEntity` | 26 | 25 |
| `salary_cycles` | `salary_cycles` | `salary_cycles` | `SalaryCycleEntity` | 27 | 26 |
| `salary_payments` | `salary_payments` | `salary_payments` | `SalaryPaymentEntity` | 26 | 25 |
| `salary_withdrawals` | `salary_withdrawals` | `salary_withdrawals` | `SalaryWithdrawalEntity` | 29 | 27 |
| `salary_carry_over_logs` | `salary_carry_over_logs` | `salary_carry_over_logs` | `SalaryCarryOverLogEntity` | 32 | 31 |
| `price_adjustments` | `price_adjustments` | `price_adjustments` | `PriceAdjustmentEntity` | 33 | 32 |
| `audit_logs` | `audit_logs` | `audit_logs` | `AuditLogEntity` | 32 | 31 |
| `payment_voids` | `payment_voids` | `payment_voids` | `PaymentVoidEntity` | 32 | 31 |
| `inventory_items` | `inventory_items` | `inventory_items` | `InventoryItemEntity` | 24 | 23 |
| `inventory_transactions` | `inventory_transactions` | `inventory_transactions` | `InventoryTransactionEntity` | 27 | 25 |
| `app_users` | `app_users` | `app_users` | `AppUserEntity` | 27 | 26 |
| `devices` | `devices` | `devices` | `DeviceInfoEntity` | 29 | 28 |
| `blacklist` | `blacklist` | `blacklist_entries` | `BlacklistEntryEntity` | 28 | 31 |

ملاحظة: كيان السلك `blacklist` يقابل محلياً جدول `blacklist_entries` مع إعادة تسمية حقول (انظر §٣.١).

### ٢.٢ حقول المزامنة الإجبارية (BaseSyncEntity — 17 حقلاً)

| الحقل | الدور |
| --- | --- |
| `local_uuid` | المعرّف العالمي للصف (مفتاح المزامنة الحقيقي) |
| `server_id` | ظلّ id الخادمي (يُتعلَّم من السحب) |
| `created_at` | ختم الإنشاء (ثوانٍ) |
| `updated_at` | ختم آخر تحديث (ثوانٍ) |
| `deleted_at` | ختم الحذف الناعم (ثوانٍ) |
| `last_modified` | طابع LWW (ثوانٍ) |
| `created_at_iso` | صيغة ISO للإنشاء |
| `updated_at_iso` | صيغة ISO للتحديث |
| `deleted_at_iso` | صيغة ISO للحذف |
| `created_at_epoch` | ختم الإنشاء (ثوانٍ، مساعد) |
| `last_modified_epoch` | طابع LWW مساعد (ثوانٍ) |
| `version` | عدّاد النسخة (يتصاعد، كاسر التعادل) |
| `origin` | أصل الصف (local/server) |
| `vector_clock` | ساعة متجهة JSON |
| `device_id` | هوية الجهاز الكاتب |
| `sync_timestamp` | ختم المزامنة |
| `idempotency_key` | مفتاح منع التكرار |

**قاعدة النقل:** كل جدول متزامن يحمل هذه الأعمدة. `local_uuid` هو مفتاح الهوية الحقيقي بين الأجهزة؛ `id` محلي و`server_id` ظلّ لا يُكتب إلا من السحب.

### ٢.٣ وحدة الزمن — ثوانٍ لا ميلي ثانية (عقد حاكم)

| البند | القيمة | المصدر |
| --- | --- | --- |
| وحدة أعمدة المزامنة | **ثوانٍ** (`created_at`, `updated_at`, `deleted_at`, `last_modified`, `*_epoch`) | `SyncEpochs.nowSeconds()` / `Time.nowEpoch()` |
| الحد الفاصل للتعرّف على الميلي | `> 100_000_000_000` (1e11) | `SyncEpochs.MILLIS_THRESHOLD` = `Database.MS_TIMESTAMP_THRESHOLD` |
| سقف «المستقبلي» | `2_000_000_000` (2e9) | `SyncEpochs.FUTURE_THRESHOLD` |
| التسامح مع انزياح ساعة الكتابة | 90 ثانية | `Database.CLOCK_SKEW_ALLOWANCE_S` |
| التطبيع الوارد | يُقسَم الميلي على 1000 قبل قرار LWW وقبل الخزن | `SyncEpochs.normalizeWireEpochFields` |
| التطبيع الصادر | نفسه على حمولة الرفع | `SyncEpochs.normalizeOutgoingEpochFields` (داخل `PushWireContract`) |
| حقول تبقى بالميلي **بعمد** | `expenses.date` (نص ISO من `Date(ms)`), `payments.payment_date` (ISO), `payment_voids.voided_at_iso`, `salary_withdrawals.withdraw_date` (ميلي), `inventory_transactions.transaction_time` (ميلي محلي بحت) | تعليقات المستودعات + `SyncWireFields.millisTargets` |
| أزمنة ليست أعمدة مزامنة | `OutboxRepository.clientTs` (ميلي)، `SyncManager` (ميلي)، `BookingDerivedRefreshService.moment` (ميلي) | تعليقات صريحة |

**الأثر إن أُهمل هذا العقد** (مقيس): صف ملموس محلياً بطابع ميلي يفوز دائماً على تحديثات الخادم بالثواني ⇒ لا يستقبل تحديثاً أبداً؛ والعكس: طابع صفري/أقدم يجعل أي صف خادمي يطمس التعديل المحلي.

### ٢.٤ نقاط النهاية (Worker)

| المسار | الطريقة | الدور |
| --- | --- | --- |
| `/api/sync/pull` | `GET` | الدلتا: `cursor`,`limit≤500`,`entity?`,`exclude_device?`,`tombstones_only?`,`include_remaining?`,`normalize_timestamps?` |
| `/api/sync/push` | `POST` | دفعة عمليات (≤ حجم الدفعة) → results[] + summary |
| `/api/sync/migrate` | `POST` | مخطط/هجرات (تشغيلي) |
| `/api/sync/log` | `GET` | سجل المزامنة |
| `/api/sync/conflicts` | `GET` | التعارضات |
| `/api/sync/lock · /api/sync/unlock · /api/sync/locks` | `POST/GET` | قفل المزامنة بين العمليات |
| `/api/realtime · /api/realtime/status` | `GET` | قناة التغييرات الحيّة |
| `/api/devices/register · /api/devices/tokens` | `POST/GET` | تسجيل الجهاز ورموز FCM |
| `/api/auth/login · /api/auth/register` | `POST` | المصادقة |
| `/api/health/d1 · /health · /api/ping` | `GET` | صحة |
| `/api/admin/sync/rotate-epoch` | `POST` | تدوير حقبة المزامنة (تشغيلي) |
| `/api/stats · /api/ai/query` | `GET/POST` | إحصاءات/استعلام |

استجابة `/api/sync/pull`:

```json
{ "changes": [ { "_entity": "...", "id": 1, "local_uuid": "...", "...": "أعمدة السطر كما في D1" } ],
  "cursor": "12345", "epoch": 1, "has_more": true, "repair_pending": false,
  "remaining": 0, "errors": [], "normalization": null, "server_time": 1760000000 }
```

استجابة `/api/sync/push`:

```json
{ "results": [ { "success": true, "skipped": false, "status": null|"validation_error"|"conflict"|"internal_error"|"deleted" } ],
  "summary": { "total": 3, "success": 3, "failed": 0, "skipped": 0 }, "server_time": 1760000000 }
```

### ٢.٥ الهجرات (worker/migrations) — 15 ملفاً

| الملف | الغرض |
| --- | --- |
| `0002_inventory_blacklist.sql` | جداول المخزون والقائمة السوداء |
| `0003_app_users.sql` | مستخدمو التطبيق (حسابات) |
| `0004_devices_sync.sql` | سجل الأجهزة + أهداف FCM |
| `0005_schema_parity.sql` | مواءمة المخطط (أعمدة ناقصة) |
| `0006_salary_withdrawals_employee_uuid.sql` | ربط سحوبات الرواتب بالموظف بـuuid |
| `0007_salary_tables_employee_uuid.sql` | uuid للأب في جداول الرواتب |
| `0008_idempotency_log_cleanup.sql` | تنظيف سجل منع التكرار |
| `0009_finance_snapshots.sql` | جدول لقطات المالية (خادمي) |
| `0010_sync_meta.sql` | ميتا المزامنة (منها حقبة المزامنة) |
| `0011_salary_parent_uuids.sql` | uuid الأب لجداول الرواتب |
| `0012_expense_employee_link_clear_flag.sql` | علم فصل ربط الموظف عن المصروف |
| `0013_salary_withdrawal_expense_uuid.sql` | uuid المصروف على السحب |
| `0014_sync_write_times.sql` | أعمدة أوقات الكتابة |
| `0015_expense_kind.sql` | تصنيف المصروف |

---

## ٣) الحقول والربط — الفهارس الكاملة (مولّدة من المصدر)

### ٣.١ أسماء السلك المختلفة (aliases عند الاستيعاب)

| الكيان | حقل السلك | الحقل المحلي |
| --- | --- | --- |
| `inventory_items` | `quantity` | `current_quantity` |
| `inventory_transactions` | `movement_type` | `transaction_type` |
| `inventory_transactions` | `created_at` | `transaction_time` |
| `blacklist` | `guest_name` | `name` |
| `blacklist` | `guest_id_number` | `national_id` |
| `blacklist` | `guest_phone` | `phone` |
| `blacklist` | `is_active` | `active` |

### ٣.٢ الافتراضيات عند غياب الحقل (entityDefaults — نظير `?? fallback` في محوّلات Dart)

| الكيان | الحقل | القيمة الافتراضية |
| --- | --- | --- |
| `inventory_items` | `unit` | `قطعة` |
| `inventory_items` | `is_active` | `true` |
| `employees` | `position` | `موظف` |
| `employees` | `phone` | (فراغ) |
| `employees` | `hire_date` | (فراغ) |
| `employees` | `status` | (فراغ) |
| `rooms` | `cleaning_status` | `clean` |
| `rooms` | `status` | (فراغ) |
| `bookings` | `guest_id_type` | `بطاقة شخصية` |
| `bookings` | `discount_type` | `per_night` |
| `bookings` | `status` | (فراغ) |
| `bookings` | `expected_nights` | `1` |
| `bookings` | `calculated_nights` | `1` |
| `guest_infos` | `id_type` | `بطاقة شخصية` |
| `salary_cycles` | `status` | `draft` |
| `salary_withdrawals` | `withdrawal_type` | `سحب راتب` |
| `salary_withdrawals` | `employee_name` | (فراغ) |
| `booking_notes` | `is_active` | `1` |
| `booking_price_adjustments` | `is_active` | `true` |
| `price_adjustments` | `adjustment_mode` | `per_night` |
| `inventory_transactions` | `movement_type` | `adjustment` |
| `inventory_transactions` | `transaction_type` | `adjustment` |
| `shift_notes` | `priority` | `medium` |
| `shift_notes` | `shift_type` | `all` |
| `shift_notes` | `created_by` | `user` |
| `shift_notes` | `is_read` | `0` |
| `blacklist` | `reported_by` | `police` |
| `blacklist` | `active` | `true` |
| `devices` | `status` | `active` |
| `devices` | `is_active` | `true` |
| `app_users` | `active` | `true` |

### ٣.٣ مرايا الرفع (wireMirrors — تُضاف بجانب المحلي قبل الإرسال)

| الكيان | الحقل المحلي | اسم السلك |
| --- | --- | --- |
| `inventory_items` | `current_quantity` | `quantity` |
| `inventory_transactions` | `transaction_type` | `movement_type` |
| `blacklist` | `active` | `is_active` |

### ٣.٤ أعمدة محلية بميلي تُغذّى بالثواني (تُضاعف ×1000 عند الاستيعاب)

- `inventory_transactions.transaction_time`

### ٣.٥ جداول الحقول — كل كيان

> `—` في عمود الغلاف يعني «لا مقابل على السلك» (عمود محلي بحت). الحقول المعلَّمة «مزامنة» هي حقول `BaseSyncEntity`.

#### `rooms` → D1 `rooms` · Room `rooms` · RoomEntity (27 حقلاً)

| العمود المحلي | اسم السلك | خاصية Kotlin | نوع D1 | ملاحظة |
| --- | --- | --- | --- | --- |
| `id` | `id` | `id` | INTEGER |  |
| `room_number` | `room_number` | `roomNumber` | TEXT • NOT NULL |  |
| `type` | `type` | `type` | TEXT • NOT NULL |  |
| `price` | `price` | `price` | REAL • NOT NULL |  |
| `status` | `status` | `status` | TEXT • NOT NULL | افتراضي عند الغياب: `""` |
| `image_url` | `image_url` | `imageUrl` | TEXT |  |
| `cleaning_status` | `cleaning_status` | `cleaningStatus` | TEXT • NOT NULL • DEFAULT 'clean' | افتراضي عند الغياب: `clean` |
| `last_cleaned_hotel_day` | `last_cleaned_hotel_day` | `lastCleanedHotelDay` | TEXT |  |
| `last_occupied_hotel_day` | `last_occupied_hotel_day` | `lastOccupiedHotelDay` | TEXT |  |
| `requires_maintenance` | `requires_maintenance` | `requiresMaintenance` | INTEGER • NOT NULL • DEFAULT 0 |  |
| `local_uuid` | `local_uuid` | `localUuid` | TEXT • NOT NULL | مزامنة |
| `server_id` | `server_id` | `serverId` | INTEGER | مزامنة |
| `created_at` | `created_at` | `createdAt` | INTEGER • NOT NULL | مزامنة |
| `updated_at` | `updated_at` | `updatedAt` | INTEGER • NOT NULL | مزامنة |
| `deleted_at` | `deleted_at` | `deletedAt` | INTEGER | مزامنة |
| `last_modified` | `last_modified` | `lastModified` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `created_at_iso` | `created_at_iso` | `createdAtIso` | TEXT | مزامنة |
| `updated_at_iso` | `updated_at_iso` | `updatedAtIso` | TEXT | مزامنة |
| `deleted_at_iso` | `deleted_at_iso` | `deletedAtIso` | TEXT | مزامنة |
| `created_at_epoch` | `created_at_epoch` | `createdAtEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `last_modified_epoch` | `last_modified_epoch` | `lastModifiedEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `version` | `version` | `version` | INTEGER • NOT NULL • DEFAULT 1 | مزامنة |
| `origin` | `origin` | `origin` | TEXT • NOT NULL • DEFAULT 'local' | مزامنة |
| `vector_clock` | `vector_clock` | `vectorClock` | TEXT • NOT NULL • DEFAULT '{}' | مزامنة |
| `device_id` | `device_id` | `deviceId` | TEXT • NOT NULL • DEFAULT '' | مزامنة |
| `sync_timestamp` | `sync_timestamp` | `syncTimestamp` | — | مزامنة |
| `idempotency_key` | `idempotency_key` | `idempotencyKey` | TEXT | مزامنة |

#### `bookings` → D1 `bookings` · Room `bookings` · BookingEntity (52 حقلاً)

| العمود المحلي | اسم السلك | خاصية Kotlin | نوع D1 | ملاحظة |
| --- | --- | --- | --- | --- |
| `id` | `id` | `id` | INTEGER |  |
| `server_booking_id` | `server_booking_id` | `serverBookingId` | INTEGER |  |
| `room_number` | `room_number` | `roomNumber` | TEXT • NOT NULL |  |
| `guest_name` | `guest_name` | `guestName` | TEXT • NOT NULL |  |
| `guest_phone` | `guest_phone` | `guestPhone` | TEXT • NOT NULL |  |
| `guest_id_type` | `guest_id_type` | `guestIdType` | TEXT • NOT NULL • DEFAULT 'بطاقة | افتراضي عند الغياب: `بطاقة شخصية` |
| `guest_id_number` | `guest_id_number` | `guestIdNumber` | TEXT • NOT NULL • DEFAULT '' |  |
| `guest_id_issue_date` | `guest_id_issue_date` | `guestIdIssueDate` | TEXT |  |
| `guest_id_issue_place` | `guest_id_issue_place` | `guestIdIssuePlace` | TEXT |  |
| `guest_nationality` | `guest_nationality` | `guestNationality` | TEXT • NOT NULL |  |
| `guest_email` | `guest_email` | `guestEmail` | TEXT |  |
| `guest_address` | `guest_address` | `guestAddress` | TEXT |  |
| `checkin_date` | `checkin_date` | `checkinDate` | TEXT • NOT NULL |  |
| `checkout_date` | `checkout_date` | `checkoutDate` | TEXT |  |
| `actual_checkout` | `actual_checkout` | `actualCheckout` | TEXT |  |
| `status` | `status` | `status` | TEXT • NOT NULL | افتراضي عند الغياب: `""` |
| `notes` | `notes` | `notes` | TEXT |  |
| `discount` | `discount` | `discount` | REAL • NOT NULL • DEFAULT 0 |  |
| `discount_type` | `discount_type` | `discountType` | TEXT • NOT NULL • DEFAULT 'per_night' | افتراضي عند الغياب: `per_night` |
| `discount_start_date` | `discount_start_date` | `discountStartDate` | TEXT |  |
| `expected_nights` | `expected_nights` | `expectedNights` | INTEGER • NOT NULL • DEFAULT 1 | افتراضي عند الغياب: `1` |
| `calculated_nights` | `calculated_nights` | `calculatedNights` | INTEGER • NOT NULL • DEFAULT 1 | افتراضي عند الغياب: `1` |
| `total_nights_cached` | `total_nights_cached` | `totalNightsCached` | INTEGER • NOT NULL • DEFAULT 0 |  |
| `stay_duration_iso` | `stay_duration_iso` | `stayDurationIso` | TEXT |  |
| `last_night_epoch` | `last_night_epoch` | `lastNightEpoch` | INTEGER |  |
| `is_overdue` | `is_overdue` | `isOverdue` | INTEGER • NOT NULL • DEFAULT 0 |  |
| `needs_checkout_review` | `needs_checkout_review` | `needsCheckoutReview` | INTEGER • NOT NULL • DEFAULT 0 |  |
| `total_due_cached` | `total_due_cached` | `totalDueCached` | REAL • NOT NULL • DEFAULT 0 |  |
| `total_paid_cached` | `total_paid_cached` | `totalPaidCached` | REAL • NOT NULL • DEFAULT 0 |  |
| `remaining_balance_cached` | `remaining_balance_cached` | `remainingBalanceCached` | REAL • NOT NULL • DEFAULT 0 |  |
| `is_fully_paid` | `is_fully_paid` | `isFullyPaid` | INTEGER • NOT NULL • DEFAULT 0 |  |
| `hotel_day_checkin` | `hotel_day_checkin` | `hotelDayCheckin` | TEXT |  |
| `hotel_day_checkout` | `hotel_day_checkout` | `hotelDayCheckout` | TEXT |  |
| `financial_frozen_at` | `financial_frozen_at` | `financialFrozenAt` | INTEGER |  |
| `financial_hash` | `financial_hash` | `financialHash` | TEXT |  |
| `local_uuid` | `local_uuid` | `localUuid` | TEXT • NOT NULL | مزامنة |
| `server_id` | `server_id` | `serverId` | INTEGER | مزامنة |
| `created_at` | `created_at` | `createdAt` | INTEGER • NOT NULL | مزامنة |
| `updated_at` | `updated_at` | `updatedAt` | INTEGER • NOT NULL | مزامنة |
| `deleted_at` | `deleted_at` | `deletedAt` | INTEGER | مزامنة |
| `last_modified` | `last_modified` | `lastModified` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `created_at_iso` | `created_at_iso` | `createdAtIso` | TEXT | مزامنة |
| `updated_at_iso` | `updated_at_iso` | `updatedAtIso` | TEXT | مزامنة |
| `deleted_at_iso` | `deleted_at_iso` | `deletedAtIso` | TEXT | مزامنة |
| `created_at_epoch` | `created_at_epoch` | `createdAtEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `last_modified_epoch` | `last_modified_epoch` | `lastModifiedEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `version` | `version` | `version` | INTEGER • NOT NULL • DEFAULT 1 | مزامنة |
| `origin` | `origin` | `origin` | TEXT • NOT NULL • DEFAULT 'local' | مزامنة |
| `vector_clock` | `vector_clock` | `vectorClock` | TEXT • NOT NULL • DEFAULT '{}' | مزامنة |
| `device_id` | `device_id` | `deviceId` | TEXT • NOT NULL • DEFAULT '' | مزامنة |
| `sync_timestamp` | `sync_timestamp` | `syncTimestamp` | — | مزامنة |
| `idempotency_key` | `idempotency_key` | `idempotencyKey` | TEXT | مزامنة |

#### `payments` → D1 `payments` · Room `payments` · PaymentEntity (45 حقلاً)

| العمود المحلي | اسم السلك | خاصية Kotlin | نوع D1 | ملاحظة |
| --- | --- | --- | --- | --- |
| `id` | `id` | `id` | INTEGER |  |
| `server_payment_id` | `server_payment_id` | `serverPaymentId` | INTEGER |  |
| `booking_local_id` | `booking_local_id` | `bookingLocalId` | INTEGER |  |
| `server_booking_id` | `server_booking_id` | `serverBookingId` | INTEGER |  |
| `room_number` | `room_number` | `roomNumber` | TEXT |  |
| `amount` | `amount` | `amount` | REAL • NOT NULL |  |
| `payment_date` | `payment_date` | `paymentDate` | TEXT • NOT NULL |  |
| `notes` | `notes` | `notes` | TEXT |  |
| `payment_method` | `payment_method` | `paymentMethod` | TEXT • NOT NULL |  |
| `revenue_type` | `revenue_type` | `revenueType` | TEXT • NOT NULL |  |
| `cash_transaction_local_id` | `cash_transaction_local_id` | `cashTransactionLocalId` | INTEGER |  |
| `cash_transaction_server_id` | `cash_transaction_server_id` | `cashTransactionServerId` | INTEGER |  |
| `reference_number` | `reference_number` | `referenceNumber` | TEXT |  |
| `hotel_day_key` | `hotel_day_key` | `hotelDayKey` | TEXT |  |
| `is_pending_balance` | `is_pending_balance` | `isPendingBalance` | INTEGER • NOT NULL • DEFAULT 0 |  |
| `linked_debt_uuid` | `linked_debt_uuid` | `linkedDebtUuid` | TEXT |  |
| `booking_uuid_cache` | `booking_uuid_cache` | `bookingUuidCache` | TEXT |  |
| `discount_amount` | `discount_amount` | `discountAmount` | REAL |  |
| `discount_start_date` | `discount_start_date` | `discountStartDate` | TEXT |  |
| `is_voided` | `is_voided` | `isVoided` | INTEGER • NOT NULL • DEFAULT 0 |  |
| `voided_at` | `voided_at` | `voidedAt` | INTEGER |  |
| `voided_by` | `voided_by` | `voidedBy` | TEXT |  |
| `void_reason` | `void_reason` | `voidReason` | TEXT |  |
| `is_immutable` | `is_immutable` | `isImmutable` | INTEGER • NOT NULL • DEFAULT 0 |  |
| `received_by_user_id` | `received_by_user_id` | `receivedByUserId` | INTEGER |  |
| `received_by_name` | `received_by_name` | `receivedByName` | TEXT |  |
| `received_session_uuid` | `received_session_uuid` | `receivedSessionUuid` | TEXT |  |
| `received_by_cloud_id` | `received_by_cloud_id` | `receivedByCloudId` | TEXT |  |
| `local_uuid` | `local_uuid` | `localUuid` | TEXT • NOT NULL | مزامنة |
| `server_id` | `server_id` | `serverId` | INTEGER | مزامنة |
| `created_at` | `created_at` | `createdAt` | INTEGER • NOT NULL | مزامنة |
| `updated_at` | `updated_at` | `updatedAt` | INTEGER • NOT NULL | مزامنة |
| `deleted_at` | `deleted_at` | `deletedAt` | INTEGER | مزامنة |
| `last_modified` | `last_modified` | `lastModified` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `created_at_iso` | `created_at_iso` | `createdAtIso` | TEXT | مزامنة |
| `updated_at_iso` | `updated_at_iso` | `updatedAtIso` | TEXT | مزامنة |
| `deleted_at_iso` | `deleted_at_iso` | `deletedAtIso` | TEXT | مزامنة |
| `created_at_epoch` | `created_at_epoch` | `createdAtEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `last_modified_epoch` | `last_modified_epoch` | `lastModifiedEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `version` | `version` | `version` | INTEGER • NOT NULL • DEFAULT 1 | مزامنة |
| `origin` | `origin` | `origin` | TEXT • NOT NULL • DEFAULT 'local' | مزامنة |
| `vector_clock` | `vector_clock` | `vectorClock` | TEXT • NOT NULL • DEFAULT '{}' | مزامنة |
| `device_id` | `device_id` | `deviceId` | TEXT • NOT NULL • DEFAULT '' | مزامنة |
| `sync_timestamp` | `sync_timestamp` | `syncTimestamp` | — | مزامنة |
| `idempotency_key` | `idempotency_key` | `idempotencyKey` | TEXT | مزامنة |

#### `expenses` → D1 `expenses` · Room `expenses` · ExpenseEntity (31 حقلاً)

| العمود المحلي | اسم السلك | خاصية Kotlin | نوع D1 | ملاحظة |
| --- | --- | --- | --- | --- |
| `id` | `id` | `id` | INTEGER |  |
| `expense_type` | `expense_type` | `expenseType` | TEXT • NOT NULL |  |
| `expense_kind` | `expense_kind` | `expenseKind` | TEXT |  |
| `related_id` | `related_id` | `relatedId` | INTEGER |  |
| `description` | `description` | `description` | TEXT • NOT NULL |  |
| `amount` | `amount` | `amount` | REAL • NOT NULL |  |
| `date` | `date` | `date` | TEXT • NOT NULL |  |
| `cash_transaction_id` | `cash_transaction_id` | `cashTransactionId` | INTEGER |  |
| `hotel_day_key` | `hotel_day_key` | `hotelDayKey` | TEXT |  |
| `category_uuid` | `category_uuid` | `categoryUuid` | TEXT |  |
| `cash_flow_uuid` | `cash_flow_uuid` | `cashFlowUuid` | TEXT |  |
| `is_auto_generated` | `is_auto_generated` | `isAutoGenerated` | INTEGER • NOT NULL • DEFAULT 0 |  |
| `employee_uuid` | `employee_uuid` | `employeeUuid` | TEXT |  |
| `employee_link_cleared` | `employee_link_cleared` | `employeeLinkCleared` | INTEGER • NOT NULL • DEFAULT 0 |  |
| `local_uuid` | `local_uuid` | `localUuid` | TEXT • NOT NULL | مزامنة |
| `server_id` | `server_id` | `serverId` | INTEGER | مزامنة |
| `created_at` | `created_at` | `createdAt` | INTEGER • NOT NULL | مزامنة |
| `updated_at` | `updated_at` | `updatedAt` | INTEGER • NOT NULL | مزامنة |
| `deleted_at` | `deleted_at` | `deletedAt` | INTEGER | مزامنة |
| `last_modified` | `last_modified` | `lastModified` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `created_at_iso` | `created_at_iso` | `createdAtIso` | TEXT | مزامنة |
| `updated_at_iso` | `updated_at_iso` | `updatedAtIso` | TEXT | مزامنة |
| `deleted_at_iso` | `deleted_at_iso` | `deletedAtIso` | TEXT | مزامنة |
| `created_at_epoch` | `created_at_epoch` | `createdAtEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `last_modified_epoch` | `last_modified_epoch` | `lastModifiedEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `version` | `version` | `version` | INTEGER • NOT NULL • DEFAULT 1 | مزامنة |
| `origin` | `origin` | `origin` | TEXT • NOT NULL • DEFAULT 'local' | مزامنة |
| `vector_clock` | `vector_clock` | `vectorClock` | TEXT • NOT NULL • DEFAULT '{}' | مزامنة |
| `device_id` | `device_id` | `deviceId` | TEXT • NOT NULL • DEFAULT '' | مزامنة |
| `sync_timestamp` | `sync_timestamp` | `syncTimestamp` | — | مزامنة |
| `idempotency_key` | `idempotency_key` | `idempotencyKey` | TEXT | مزامنة |

#### `employees` → D1 `employees` · Room `employees` · EmployeeEntity (27 حقلاً)

| العمود المحلي | اسم السلك | خاصية Kotlin | نوع D1 | ملاحظة |
| --- | --- | --- | --- | --- |
| `id` | `id` | `id` | INTEGER |  |
| `name` | `name` | `name` | TEXT • NOT NULL |  |
| `basic_salary` | `basic_salary` | `basicSalary` | REAL • NOT NULL |  |
| `position` | `position` | `position` | TEXT • NOT NULL • DEFAULT 'موظف' | افتراضي عند الغياب: `موظف` |
| `phone` | `phone` | `phone` | TEXT • NOT NULL • DEFAULT '' | افتراضي عند الغياب: `""` |
| `hire_date` | `hire_date` | `hireDate` | TEXT • NOT NULL • DEFAULT '' | افتراضي عند الغياب: `""` |
| `status` | `status` | `status` | TEXT • NOT NULL | افتراضي عند الغياب: `""` |
| `termination_date` | `termination_date` | `terminationDate` | TEXT |  |
| `termination_reason` | `termination_reason` | `terminationReason` | TEXT |  |
| `employee_id` | `employee_id` | `employeeID` | TEXT |  |
| `local_uuid` | `local_uuid` | `localUuid` | TEXT • NOT NULL | مزامنة |
| `server_id` | `server_id` | `serverId` | INTEGER | مزامنة |
| `created_at` | `created_at` | `createdAt` | INTEGER • NOT NULL | مزامنة |
| `updated_at` | `updated_at` | `updatedAt` | INTEGER • NOT NULL | مزامنة |
| `deleted_at` | `deleted_at` | `deletedAt` | INTEGER | مزامنة |
| `last_modified` | `last_modified` | `lastModified` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `created_at_iso` | `created_at_iso` | `createdAtIso` | TEXT | مزامنة |
| `updated_at_iso` | `updated_at_iso` | `updatedAtIso` | TEXT | مزامنة |
| `deleted_at_iso` | `deleted_at_iso` | `deletedAtIso` | TEXT | مزامنة |
| `created_at_epoch` | `created_at_epoch` | `createdAtEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `last_modified_epoch` | `last_modified_epoch` | `lastModifiedEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `version` | `version` | `version` | INTEGER • NOT NULL • DEFAULT 1 | مزامنة |
| `origin` | `origin` | `origin` | TEXT • NOT NULL • DEFAULT 'local' | مزامنة |
| `vector_clock` | `vector_clock` | `vectorClock` | TEXT • NOT NULL • DEFAULT '{}' | مزامنة |
| `device_id` | `device_id` | `deviceId` | TEXT • NOT NULL • DEFAULT '' | مزامنة |
| `sync_timestamp` | `sync_timestamp` | `syncTimestamp` | — | مزامنة |
| `idempotency_key` | `idempotency_key` | `idempotencyKey` | TEXT | مزامنة |

#### `debts` → D1 `debts` · Room `debts` · DebtEntity (45 حقلاً)

| العمود المحلي | اسم السلك | خاصية Kotlin | نوع D1 | ملاحظة |
| --- | --- | --- | --- | --- |
| `id` | `id` | `id` | INTEGER |  |
| `booking_local_id` | `booking_local_id` | `bookingLocalId` | INTEGER |  |
| `guest_name` | `guest_name` | `guestName` | TEXT • NOT NULL |  |
| `checkin_date` | `checkin_date` | `checkinDate` | TEXT • NOT NULL |  |
| `checkout_date` | `checkout_date` | `checkoutDate` | TEXT • NOT NULL |  |
| `date_recorded` | `date_recorded` | `dateRecorded` | TEXT • NOT NULL • DEFAULT '' |  |
| `debt_reason` | `debt_reason` | `debtReason` | TEXT • NOT NULL • DEFAULT '' |  |
| `total_amount` | `total_amount` | `totalAmount` | REAL • NOT NULL |  |
| `paid_amount` | `paid_amount` | `paidAmount` | REAL • NOT NULL |  |
| `remaining_amount` | `remaining_amount` | `remainingAmount` | REAL • NOT NULL |  |
| `payment_date` | `payment_date` | `paymentDate` | TEXT • NOT NULL |  |
| `is_settled` | `is_settled` | `isSettled` | INTEGER • NOT NULL • DEFAULT 0 |  |
| `pledge` | `pledge` | `pledge` | TEXT |  |
| `pledge_type` | `pledge_type` | `pledgeType` | TEXT |  |
| `note` | `note` | `note` | TEXT |  |
| `debt_uuid` | `debt_uuid` | `debtUuid` | TEXT |  |
| `hotel_day_opened` | `hotel_day_opened` | `hotelDayOpened` | TEXT |  |
| `hotel_day_closed` | `hotel_day_closed` | `hotelDayClosed` | TEXT |  |
| `is_from_auto_fix` | `is_from_auto_fix` | `isFromAutoFix` | INTEGER • NOT NULL • DEFAULT 0 |  |
| `settlement_confirmed` | `settlement_confirmed` | `settlementConfirmed` | INTEGER • NOT NULL • DEFAULT 0 |  |
| `guest_phone` | `guest_phone` | `guestPhone` | TEXT |  |
| `description` | `description` | `description` | TEXT |  |
| `status` | `status` | `status` | TEXT |  |
| `due_date` | `due_date` | `dueDate` | TEXT |  |
| `booking_uuid_cache` | `booking_uuid_cache` | `bookingUuidCache` | TEXT |  |
| `debtor_name` | `debtor_name` | `debtorName` | TEXT |  |
| `amount` | `amount` | `amount` | REAL |  |
| `date` | `date` | `date` | TEXT |  |
| `local_uuid` | `local_uuid` | `localUuid` | TEXT • NOT NULL | مزامنة |
| `server_id` | `server_id` | `serverId` | INTEGER | مزامنة |
| `created_at` | `created_at` | `createdAt` | INTEGER • NOT NULL | مزامنة |
| `updated_at` | `updated_at` | `updatedAt` | INTEGER • NOT NULL | مزامنة |
| `deleted_at` | `deleted_at` | `deletedAt` | INTEGER | مزامنة |
| `last_modified` | `last_modified` | `lastModified` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `created_at_iso` | `created_at_iso` | `createdAtIso` | TEXT | مزامنة |
| `updated_at_iso` | `updated_at_iso` | `updatedAtIso` | TEXT | مزامنة |
| `deleted_at_iso` | `deleted_at_iso` | `deletedAtIso` | TEXT | مزامنة |
| `created_at_epoch` | `created_at_epoch` | `createdAtEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `last_modified_epoch` | `last_modified_epoch` | `lastModifiedEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `version` | `version` | `version` | INTEGER • NOT NULL • DEFAULT 1 | مزامنة |
| `origin` | `origin` | `origin` | TEXT • NOT NULL • DEFAULT 'local' | مزامنة |
| `vector_clock` | `vector_clock` | `vectorClock` | TEXT • NOT NULL • DEFAULT '{}' | مزامنة |
| `device_id` | `device_id` | `deviceId` | TEXT • NOT NULL • DEFAULT '' | مزامنة |
| `sync_timestamp` | `sync_timestamp` | `syncTimestamp` | — | مزامنة |
| `idempotency_key` | `idempotency_key` | `idempotencyKey` | TEXT | مزامنة |

#### `booking_notes` → D1 `booking_notes` · Room `booking_notes` · BookingNoteEntity (23 حقلاً)

| العمود المحلي | اسم السلك | خاصية Kotlin | نوع D1 | ملاحظة |
| --- | --- | --- | --- | --- |
| `id` | `id` | `id` | INTEGER |  |
| `booking_id` | `booking_id` | `bookingId` | INTEGER • NOT NULL |  |
| `note_text` | `note_text` | `noteText` | TEXT • NOT NULL |  |
| `alert_type` | `alert_type` | `alertType` | TEXT • NOT NULL |  |
| `alert_until` | `alert_until` | `alertUntil` | TEXT |  |
| `is_active` | `is_active` | `isActive` | INTEGER • NOT NULL • DEFAULT 1 | افتراضي عند الغياب: `1` |
| `local_uuid` | `local_uuid` | `localUuid` | TEXT • NOT NULL | مزامنة |
| `server_id` | `server_id` | `serverId` | INTEGER | مزامنة |
| `created_at` | `created_at` | `createdAt` | INTEGER • NOT NULL | مزامنة |
| `updated_at` | `updated_at` | `updatedAt` | INTEGER • NOT NULL | مزامنة |
| `deleted_at` | `deleted_at` | `deletedAt` | INTEGER | مزامنة |
| `last_modified` | `last_modified` | `lastModified` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `created_at_iso` | `created_at_iso` | `createdAtIso` | TEXT | مزامنة |
| `updated_at_iso` | `updated_at_iso` | `updatedAtIso` | TEXT | مزامنة |
| `deleted_at_iso` | `deleted_at_iso` | `deletedAtIso` | TEXT | مزامنة |
| `created_at_epoch` | `created_at_epoch` | `createdAtEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `last_modified_epoch` | `last_modified_epoch` | `lastModifiedEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `version` | `version` | `version` | INTEGER • NOT NULL • DEFAULT 1 | مزامنة |
| `origin` | `origin` | `origin` | TEXT • NOT NULL • DEFAULT 'local' | مزامنة |
| `vector_clock` | `vector_clock` | `vectorClock` | TEXT • NOT NULL • DEFAULT '{}' | مزامنة |
| `device_id` | `device_id` | `deviceId` | TEXT • NOT NULL • DEFAULT '' | مزامنة |
| `sync_timestamp` | `sync_timestamp` | `syncTimestamp` | — | مزامنة |
| `idempotency_key` | `idempotency_key` | `idempotencyKey` | TEXT | مزامنة |

#### `booking_nights` → D1 `booking_nights` · Room `booking_nights` · BookingNightEntity (32 حقلاً)

| العمود المحلي | اسم السلك | خاصية Kotlin | نوع D1 | ملاحظة |
| --- | --- | --- | --- | --- |
| `id` | `id` | `id` | INTEGER |  |
| `booking_local_id` | `booking_local_id` | `bookingLocalId` | INTEGER • NOT NULL |  |
| `hotel_day_key` | `hotel_day_key` | `hotelDayKey` | TEXT • NOT NULL |  |
| `night_start` | `night_start` | `nightStart` | TEXT • NOT NULL |  |
| `night_end` | `night_end` | `nightEnd` | TEXT • NOT NULL |  |
| `nightly_rate` | `nightly_rate` | `nightlyRate` | REAL • NOT NULL • DEFAULT 0 |  |
| `sequence` | `sequence` | `sequence` | INTEGER • NOT NULL • DEFAULT 0 |  |
| `is_processed_by_auto_fix` | `is_processed_by_auto_fix` | `isProcessedByAutoFix` | INTEGER • NOT NULL • DEFAULT 0 |  |
| `base_rate` | `base_rate` | `baseRate` | REAL • NOT NULL • DEFAULT 0 |  |
| `adjustment` | `adjustment` | `adjustment` | REAL • NOT NULL • DEFAULT 0 |  |
| `final_rate` | `final_rate` | `finalRate` | REAL • NOT NULL • DEFAULT 0 |  |
| `applied_adjustment_uuid` | `applied_adjustment_uuid` | `appliedAdjustmentUuid` | TEXT |  |
| `applied_adjustments_json` | `applied_adjustments_json` | `appliedAdjustmentsJson` | TEXT |  |
| `booking_uuid_cache` | `booking_uuid_cache` | `bookingUuidCache` | TEXT |  |
| `server_booking_id` | `server_booking_id` | `serverBookingId` | INTEGER |  |
| `local_uuid` | `local_uuid` | `localUuid` | TEXT • NOT NULL | مزامنة |
| `server_id` | `server_id` | `serverId` | INTEGER | مزامنة |
| `created_at` | `created_at` | `createdAt` | INTEGER • NOT NULL | مزامنة |
| `updated_at` | `updated_at` | `updatedAt` | INTEGER • NOT NULL | مزامنة |
| `deleted_at` | `deleted_at` | `deletedAt` | INTEGER | مزامنة |
| `last_modified` | `last_modified` | `lastModified` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `created_at_iso` | `created_at_iso` | `createdAtIso` | TEXT | مزامنة |
| `updated_at_iso` | `updated_at_iso` | `updatedAtIso` | TEXT | مزامنة |
| `deleted_at_iso` | `deleted_at_iso` | `deletedAtIso` | TEXT | مزامنة |
| `created_at_epoch` | `created_at_epoch` | `createdAtEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `last_modified_epoch` | `last_modified_epoch` | `lastModifiedEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `version` | `version` | `version` | INTEGER • NOT NULL • DEFAULT 1 | مزامنة |
| `origin` | `origin` | `origin` | TEXT • NOT NULL • DEFAULT 'local' | مزامنة |
| `vector_clock` | `vector_clock` | `vectorClock` | TEXT • NOT NULL • DEFAULT '{}' | مزامنة |
| `device_id` | `device_id` | `deviceId` | TEXT • NOT NULL • DEFAULT '' | مزامنة |
| `sync_timestamp` | `sync_timestamp` | `syncTimestamp` | — | مزامنة |
| `idempotency_key` | `idempotency_key` | `idempotencyKey` | TEXT | مزامنة |

#### `booking_price_adjustments` → D1 `booking_price_adjustments` · Room `booking_price_adjustments` · BookingPriceAdjustmentEntity (33 حقلاً)

| العمود المحلي | اسم السلك | خاصية Kotlin | نوع D1 | ملاحظة |
| --- | --- | --- | --- | --- |
| `id` | `id` | `id` | INTEGER |  |
| `booking_local_uuid` | `booking_local_uuid` | `bookingLocalUuid` | TEXT • NOT NULL |  |
| `booking_local_id` | `booking_local_id` | `bookingLocalId` | INTEGER |  |
| `room_number` | `room_number` | `roomNumber` | TEXT |  |
| `amount` | `amount` | `amount` | REAL • NOT NULL • DEFAULT 0 |  |
| `effective_hotel_day` | `effective_hotel_day` | `effectiveHotelDay` | TEXT • NOT NULL |  |
| `end_hotel_day` | `end_hotel_day` | `endHotelDay` | TEXT |  |
| `is_active` | `is_active` | `isActive` | INTEGER • NOT NULL • DEFAULT 1 | افتراضي عند الغياب: `true` |
| `reason` | `reason` | `reason` | TEXT |  |
| `applied_by` | `applied_by` | `appliedBy` | TEXT |  |
| `cancelled_at` | `cancelled_at` | `cancelledAt` | TEXT |  |
| `cancelled_by` | `cancelled_by` | `cancelledBy` | TEXT |  |
| `booking_uuid` | `booking_uuid` | `bookingUuid` | TEXT |  |
| `adjustment_type` | `adjustment_type` | `adjustmentType` | INTEGER • NOT NULL • DEFAULT 0 |  |
| `adjustment_mode` | `adjustment_mode` | `adjustmentMode` | TEXT • NOT NULL • DEFAULT 'per_night' |  |
| `applied_at` | `applied_at` | `appliedAt` | INTEGER |  |
| `local_uuid` | `local_uuid` | `localUuid` | TEXT • NOT NULL | مزامنة |
| `server_id` | `server_id` | `serverId` | INTEGER | مزامنة |
| `created_at` | `created_at` | `createdAt` | INTEGER • NOT NULL | مزامنة |
| `updated_at` | `updated_at` | `updatedAt` | INTEGER • NOT NULL | مزامنة |
| `deleted_at` | `deleted_at` | `deletedAt` | INTEGER | مزامنة |
| `last_modified` | `last_modified` | `lastModified` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `created_at_iso` | `created_at_iso` | `createdAtIso` | TEXT | مزامنة |
| `updated_at_iso` | `updated_at_iso` | `updatedAtIso` | TEXT | مزامنة |
| `deleted_at_iso` | `deleted_at_iso` | `deletedAtIso` | TEXT | مزامنة |
| `created_at_epoch` | `created_at_epoch` | `createdAtEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `last_modified_epoch` | `last_modified_epoch` | `lastModifiedEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `version` | `version` | `version` | INTEGER • NOT NULL • DEFAULT 1 | مزامنة |
| `origin` | `origin` | `origin` | TEXT • NOT NULL • DEFAULT 'local' | مزامنة |
| `vector_clock` | `vector_clock` | `vectorClock` | TEXT • NOT NULL • DEFAULT '{}' | مزامنة |
| `device_id` | `device_id` | `deviceId` | TEXT • NOT NULL • DEFAULT '' | مزامنة |
| `sync_timestamp` | `sync_timestamp` | `syncTimestamp` | — | مزامنة |
| `idempotency_key` | `idempotency_key` | `idempotencyKey` | TEXT | مزامنة |

#### `guest_infos` → D1 `guest_infos` · Room `guest_infos` · GuestInfoEntity (28 حقلاً)

| العمود المحلي | اسم السلك | خاصية Kotlin | نوع D1 | ملاحظة |
| --- | --- | --- | --- | --- |
| `id` | `id` | `id` | INTEGER |  |
| `room_number` | `room_number` | `roomNumber` | TEXT • NOT NULL |  |
| `guest_name` | `guest_name` | `guestName` | TEXT • NOT NULL |  |
| `nationality` | `nationality` | `nationality` | TEXT • NOT NULL |  |
| `id_number` | `id_number` | `idNumber` | TEXT • NOT NULL |  |
| `id_type` | `id_type` | `idType` | TEXT • NOT NULL • DEFAULT 'بطاقة | افتراضي عند الغياب: `بطاقة شخصية` |
| `issue_date` | `issue_date` | `issueDate` | TEXT |  |
| `issue_place` | `issue_place` | `issuePlace` | TEXT |  |
| `governorate` | `governorate` | `governorate` | TEXT |  |
| `notes` | `notes` | `notes` | TEXT |  |
| `guest_phone` | `guest_phone` | `guestPhone` | TEXT |  |
| `local_uuid` | `local_uuid` | `localUuid` | TEXT • NOT NULL | مزامنة |
| `server_id` | `server_id` | `serverId` | INTEGER | مزامنة |
| `created_at` | `created_at` | `createdAt` | INTEGER • NOT NULL | مزامنة |
| `updated_at` | `updated_at` | `updatedAt` | INTEGER • NOT NULL | مزامنة |
| `deleted_at` | `deleted_at` | `deletedAt` | INTEGER | مزامنة |
| `last_modified` | `last_modified` | `lastModified` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `created_at_iso` | `created_at_iso` | `createdAtIso` | TEXT | مزامنة |
| `updated_at_iso` | `updated_at_iso` | `updatedAtIso` | TEXT | مزامنة |
| `deleted_at_iso` | `deleted_at_iso` | `deletedAtIso` | TEXT | مزامنة |
| `created_at_epoch` | `created_at_epoch` | `createdAtEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `last_modified_epoch` | `last_modified_epoch` | `lastModifiedEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `version` | `version` | `version` | INTEGER • NOT NULL • DEFAULT 1 | مزامنة |
| `origin` | `origin` | `origin` | TEXT • NOT NULL • DEFAULT 'local' | مزامنة |
| `vector_clock` | `vector_clock` | `vectorClock` | TEXT • NOT NULL • DEFAULT '{}' | مزامنة |
| `device_id` | `device_id` | `deviceId` | TEXT • NOT NULL • DEFAULT '' | مزامنة |
| `sync_timestamp` | `sync_timestamp` | `syncTimestamp` | — | مزامنة |
| `idempotency_key` | `idempotency_key` | `idempotencyKey` | TEXT | مزامنة |

#### `shift_notes` → D1 `shift_notes` · Room `shift_notes` · ShiftNoteEntity (25 حقلاً)

| العمود المحلي | اسم السلك | خاصية Kotlin | نوع D1 | ملاحظة |
| --- | --- | --- | --- | --- |
| `id` | `id` | `id` | INTEGER |  |
| `title` | `title` | `title` | TEXT • NOT NULL |  |
| `content` | `content` | `content` | TEXT • NOT NULL |  |
| `priority` | `priority` | `priority` | TEXT • NOT NULL • DEFAULT 'medium' | افتراضي عند الغياب: `medium` |
| `shift_type` | `shift_type` | `shiftType` | TEXT • NOT NULL • DEFAULT 'all' | افتراضي عند الغياب: `all` |
| `is_read` | `is_read` | `isRead` | INTEGER • NOT NULL • DEFAULT 0 | افتراضي عند الغياب: `0` |
| `expires_at` | `expires_at` | `expiresAt` | TEXT |  |
| `created_by` | `created_by` | `createdBy` | TEXT • NOT NULL • DEFAULT 'user' | افتراضي عند الغياب: `user` |
| `local_uuid` | `local_uuid` | `localUuid` | TEXT • NOT NULL | مزامنة |
| `server_id` | `server_id` | `serverId` | INTEGER | مزامنة |
| `created_at` | `created_at` | `createdAt` | INTEGER • NOT NULL | مزامنة |
| `updated_at` | `updated_at` | `updatedAt` | INTEGER • NOT NULL | مزامنة |
| `deleted_at` | `deleted_at` | `deletedAt` | INTEGER | مزامنة |
| `last_modified` | `last_modified` | `lastModified` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `created_at_iso` | `created_at_iso` | `createdAtIso` | TEXT | مزامنة |
| `updated_at_iso` | `updated_at_iso` | `updatedAtIso` | TEXT | مزامنة |
| `deleted_at_iso` | `deleted_at_iso` | `deletedAtIso` | TEXT | مزامنة |
| `created_at_epoch` | `created_at_epoch` | `createdAtEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `last_modified_epoch` | `last_modified_epoch` | `lastModifiedEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `version` | `version` | `version` | INTEGER • NOT NULL • DEFAULT 1 | مزامنة |
| `origin` | `origin` | `origin` | TEXT • NOT NULL • DEFAULT 'local' | مزامنة |
| `vector_clock` | `vector_clock` | `vectorClock` | TEXT • NOT NULL • DEFAULT '{}' | مزامنة |
| `device_id` | `device_id` | `deviceId` | TEXT • NOT NULL • DEFAULT '' | مزامنة |
| `sync_timestamp` | `sync_timestamp` | `syncTimestamp` | — | مزامنة |
| `idempotency_key` | `idempotency_key` | `idempotencyKey` | TEXT | مزامنة |

#### `cash_transactions` → D1 `cash_transactions` · Room `cash_transactions` · CashTransactionEntity (26 حقلاً)

| العمود المحلي | اسم السلك | خاصية Kotlin | نوع D1 | ملاحظة |
| --- | --- | --- | --- | --- |
| `id` | `id` | `id` | INTEGER |  |
| `register_id` | `register_id` | `registerId` | INTEGER |  |
| `transaction_type` | `transaction_type` | `transactionType` | TEXT • NOT NULL |  |
| `amount` | `amount` | `amount` | REAL • NOT NULL |  |
| `reference_type` | `reference_type` | `referenceType` | TEXT |  |
| `reference_id` | `reference_id` | `referenceId` | INTEGER |  |
| `description` | `description` | `description` | TEXT |  |
| `transaction_time` | `transaction_time` | `transactionTime` | TEXT • NOT NULL |  |
| `created_by` | `created_by` | `createdBy` | INTEGER |  |
| `local_uuid` | `local_uuid` | `localUuid` | TEXT • NOT NULL | مزامنة |
| `server_id` | `server_id` | `serverId` | INTEGER | مزامنة |
| `created_at` | `created_at` | `createdAt` | INTEGER • NOT NULL | مزامنة |
| `updated_at` | `updated_at` | `updatedAt` | INTEGER • NOT NULL | مزامنة |
| `deleted_at` | `deleted_at` | `deletedAt` | INTEGER | مزامنة |
| `last_modified` | `last_modified` | `lastModified` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `created_at_iso` | `created_at_iso` | `createdAtIso` | TEXT | مزامنة |
| `updated_at_iso` | `updated_at_iso` | `updatedAtIso` | TEXT | مزامنة |
| `deleted_at_iso` | `deleted_at_iso` | `deletedAtIso` | TEXT | مزامنة |
| `created_at_epoch` | `created_at_epoch` | `createdAtEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `last_modified_epoch` | `last_modified_epoch` | `lastModifiedEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `version` | `version` | `version` | INTEGER • NOT NULL • DEFAULT 1 | مزامنة |
| `origin` | `origin` | `origin` | TEXT • NOT NULL • DEFAULT 'local' | مزامنة |
| `vector_clock` | `vector_clock` | `vectorClock` | TEXT • NOT NULL • DEFAULT '{}' | مزامنة |
| `device_id` | `device_id` | `deviceId` | TEXT • NOT NULL • DEFAULT '' | مزامنة |
| `sync_timestamp` | `sync_timestamp` | `syncTimestamp` | — | مزامنة |
| `idempotency_key` | `idempotency_key` | `idempotencyKey` | TEXT | مزامنة |

#### `salary_cycles` → D1 `salary_cycles` · Room `salary_cycles` · SalaryCycleEntity (27 حقلاً)

| العمود المحلي | اسم السلك | خاصية Kotlin | نوع D1 | ملاحظة |
| --- | --- | --- | --- | --- |
| `id` | `id` | `id` | INTEGER |  |
| `employee_id` | `employee_id` | `employeeId` | INTEGER • NOT NULL |  |
| `employee_uuid` | `employee_uuid` | `employeeUuid` | TEXT |  |
| `cycle_key` | `cycle_key` | `cycleKey` | TEXT • NOT NULL |  |
| `hotel_day_start` | `hotel_day_start` | `hotelDayStart` | TEXT |  |
| `hotel_day_end` | `hotel_day_end` | `hotelDayEnd` | TEXT |  |
| `expected_amount` | `expected_amount` | `expectedAmount` | INTEGER • NOT NULL • DEFAULT 0 |  |
| `actual_paid` | `actual_paid` | `actualPaid` | INTEGER • NOT NULL • DEFAULT 0 |  |
| `remaining_amount` | `remaining_amount` | `remainingAmount` | INTEGER • NOT NULL • DEFAULT 0 |  |
| `status` | `status` | `status` | TEXT • NOT NULL • DEFAULT 'draft' | افتراضي عند الغياب: `draft` |
| `local_uuid` | `local_uuid` | `localUuid` | TEXT • NOT NULL | مزامنة |
| `server_id` | `server_id` | `serverId` | INTEGER | مزامنة |
| `created_at` | `created_at` | `createdAt` | INTEGER • NOT NULL | مزامنة |
| `updated_at` | `updated_at` | `updatedAt` | INTEGER • NOT NULL | مزامنة |
| `deleted_at` | `deleted_at` | `deletedAt` | INTEGER | مزامنة |
| `last_modified` | `last_modified` | `lastModified` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `created_at_iso` | `created_at_iso` | `createdAtIso` | TEXT | مزامنة |
| `updated_at_iso` | `updated_at_iso` | `updatedAtIso` | TEXT | مزامنة |
| `deleted_at_iso` | `deleted_at_iso` | `deletedAtIso` | TEXT | مزامنة |
| `created_at_epoch` | `created_at_epoch` | `createdAtEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `last_modified_epoch` | `last_modified_epoch` | `lastModifiedEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `version` | `version` | `version` | INTEGER • NOT NULL • DEFAULT 1 | مزامنة |
| `origin` | `origin` | `origin` | TEXT • NOT NULL • DEFAULT 'local' | مزامنة |
| `vector_clock` | `vector_clock` | `vectorClock` | TEXT • NOT NULL • DEFAULT '{}' | مزامنة |
| `device_id` | `device_id` | `deviceId` | TEXT • NOT NULL • DEFAULT '' | مزامنة |
| `sync_timestamp` | `sync_timestamp` | `syncTimestamp` | — | مزامنة |
| `idempotency_key` | `idempotency_key` | `idempotencyKey` | TEXT | مزامنة |

#### `salary_payments` → D1 `salary_payments` · Room `salary_payments` · SalaryPaymentEntity (26 حقلاً)

| العمود المحلي | اسم السلك | خاصية Kotlin | نوع D1 | ملاحظة |
| --- | --- | --- | --- | --- |
| `id` | `id` | `id` | INTEGER |  |
| `cycle_id` | `cycle_id` | `cycleId` | INTEGER • NOT NULL |  |
| `cycle_uuid` | `cycle_uuid` | `cycleUuid` | TEXT |  |
| `employee_uuid` | `employee_uuid` | `employeeUuid` | TEXT |  |
| `amount` | `amount` | `amount` | INTEGER • NOT NULL • DEFAULT 0 |  |
| `hotel_day_key` | `hotel_day_key` | `hotelDayKey` | TEXT |  |
| `payment_date_iso` | `payment_date_iso` | `paymentDateIso` | TEXT • NOT NULL |  |
| `method` | `method` | `method` | TEXT |  |
| `is_auto_generated` | `is_auto_generated` | `isAutoGenerated` | INTEGER • NOT NULL • DEFAULT 0 |  |
| `local_uuid` | `local_uuid` | `localUuid` | TEXT • NOT NULL | مزامنة |
| `server_id` | `server_id` | `serverId` | INTEGER | مزامنة |
| `created_at` | `created_at` | `createdAt` | INTEGER • NOT NULL | مزامنة |
| `updated_at` | `updated_at` | `updatedAt` | INTEGER • NOT NULL | مزامنة |
| `deleted_at` | `deleted_at` | `deletedAt` | INTEGER | مزامنة |
| `last_modified` | `last_modified` | `lastModified` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `created_at_iso` | `created_at_iso` | `createdAtIso` | TEXT | مزامنة |
| `updated_at_iso` | `updated_at_iso` | `updatedAtIso` | TEXT | مزامنة |
| `deleted_at_iso` | `deleted_at_iso` | `deletedAtIso` | TEXT | مزامنة |
| `created_at_epoch` | `created_at_epoch` | `createdAtEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `last_modified_epoch` | `last_modified_epoch` | `lastModifiedEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `version` | `version` | `version` | INTEGER • NOT NULL • DEFAULT 1 | مزامنة |
| `origin` | `origin` | `origin` | TEXT • NOT NULL • DEFAULT 'local' | مزامنة |
| `vector_clock` | `vector_clock` | `vectorClock` | TEXT • NOT NULL • DEFAULT '{}' | مزامنة |
| `device_id` | `device_id` | `deviceId` | TEXT • NOT NULL • DEFAULT '' | مزامنة |
| `sync_timestamp` | `sync_timestamp` | `syncTimestamp` | — | مزامنة |
| `idempotency_key` | `idempotency_key` | `idempotencyKey` | TEXT | مزامنة |

#### `salary_withdrawals` → D1 `salary_withdrawals` · Room `salary_withdrawals` · SalaryWithdrawalEntity (29 حقلاً)

| العمود المحلي | اسم السلك | خاصية Kotlin | نوع D1 | ملاحظة |
| --- | --- | --- | --- | --- |
| `id` | `id` | `id` | INTEGER |  |
| `employee_id` | `employee_id` | `employeeId` | INTEGER • NOT NULL |  |
| `employee_uuid` | `employee_uuid` | `employeeUuid` | TEXT |  |
| `expense_uuid` | `expense_uuid` | `expenseUuid` | TEXT |  |
| `expense_id` | `expense_id` | `expenseId` | INTEGER |  |
| `employee_name` | `employee_name` | `employeeName` | — | افتراضي عند الغياب: `""` |
| `amount` | `amount` | `amount` | REAL • NOT NULL |  |
| `withdraw_date` | `withdraw_date` | `withdrawDate` | TEXT • NOT NULL |  |
| `hotel_day_key` | `hotel_day_key` | `hotelDayKey` | TEXT |  |
| `withdrawal_type` | `withdrawal_type` | `withdrawalType` | TEXT | افتراضي عند الغياب: `سحب راتب` |
| `reason` | `reason` | `reason` | TEXT |  |
| `description` | `description` | `description` | TEXT |  |
| `local_uuid` | `local_uuid` | `localUuid` | TEXT • NOT NULL | مزامنة |
| `server_id` | `server_id` | `serverId` | INTEGER | مزامنة |
| `created_at` | `created_at` | `createdAt` | INTEGER • NOT NULL | مزامنة |
| `updated_at` | `updated_at` | `updatedAt` | INTEGER • NOT NULL | مزامنة |
| `deleted_at` | `deleted_at` | `deletedAt` | INTEGER | مزامنة |
| `last_modified` | `last_modified` | `lastModified` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `created_at_iso` | `created_at_iso` | `createdAtIso` | TEXT | مزامنة |
| `updated_at_iso` | `updated_at_iso` | `updatedAtIso` | TEXT | مزامنة |
| `deleted_at_iso` | `deleted_at_iso` | `deletedAtIso` | TEXT | مزامنة |
| `created_at_epoch` | `created_at_epoch` | `createdAtEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `last_modified_epoch` | `last_modified_epoch` | `lastModifiedEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `version` | `version` | `version` | INTEGER • NOT NULL • DEFAULT 1 | مزامنة |
| `origin` | `origin` | `origin` | TEXT • NOT NULL • DEFAULT 'local' | مزامنة |
| `vector_clock` | `vector_clock` | `vectorClock` | TEXT • NOT NULL • DEFAULT '{}' | مزامنة |
| `device_id` | `device_id` | `deviceId` | TEXT • NOT NULL • DEFAULT '' | مزامنة |
| `sync_timestamp` | `sync_timestamp` | `syncTimestamp` | — | مزامنة |
| `idempotency_key` | `idempotency_key` | `idempotencyKey` | TEXT | مزامنة |

#### `salary_carry_over_logs` → D1 `salary_carry_over_logs` · Room `salary_carry_over_logs` · SalaryCarryOverLogEntity (32 حقلاً)

| العمود المحلي | اسم السلك | خاصية Kotlin | نوع D1 | ملاحظة |
| --- | --- | --- | --- | --- |
| `id` | `id` | `id` | INTEGER |  |
| `employee_id` | `employee_id` | `employeeId` | INTEGER • NOT NULL |  |
| `employee_uuid` | `employee_uuid` | `employeeUuid` | TEXT |  |
| `amount` | `amount` | `amount` | REAL • NOT NULL |  |
| `previous_cycle_start` | `previous_cycle_start` | `previousCycleStart` | TEXT • NOT NULL |  |
| `previous_cycle_end` | `previous_cycle_end` | `previousCycleEnd` | TEXT • NOT NULL |  |
| `new_cycle_start` | `new_cycle_start` | `newCycleStart` | TEXT • NOT NULL |  |
| `new_cycle_end` | `new_cycle_end` | `newCycleEnd` | TEXT • NOT NULL |  |
| `reason` | `reason` | `reason` | TEXT • NOT NULL |  |
| `carried_at` | `carried_at` | `carriedAt` | INTEGER • NOT NULL |  |
| `from_cycle_id` | `from_cycle_id` | `fromCycleId` | TEXT |  |
| `to_cycle_id` | `to_cycle_id` | `toCycleId` | TEXT |  |
| `carry_date` | `carry_date` | `carryDate` | TEXT |  |
| `performed_by` | `performed_by` | `performedBy` | TEXT |  |
| `hotel_day_key` | `hotel_day_key` | `hotelDayKey` | TEXT |  |
| `local_uuid` | `local_uuid` | `localUuid` | TEXT • NOT NULL | مزامنة |
| `server_id` | `server_id` | `serverId` | INTEGER | مزامنة |
| `created_at` | `created_at` | `createdAt` | INTEGER • NOT NULL | مزامنة |
| `updated_at` | `updated_at` | `updatedAt` | INTEGER • NOT NULL | مزامنة |
| `deleted_at` | `deleted_at` | `deletedAt` | INTEGER | مزامنة |
| `last_modified` | `last_modified` | `lastModified` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `created_at_iso` | `created_at_iso` | `createdAtIso` | TEXT | مزامنة |
| `updated_at_iso` | `updated_at_iso` | `updatedAtIso` | TEXT | مزامنة |
| `deleted_at_iso` | `deleted_at_iso` | `deletedAtIso` | TEXT | مزامنة |
| `created_at_epoch` | `created_at_epoch` | `createdAtEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `last_modified_epoch` | `last_modified_epoch` | `lastModifiedEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `version` | `version` | `version` | INTEGER • NOT NULL • DEFAULT 1 | مزامنة |
| `origin` | `origin` | `origin` | TEXT • NOT NULL • DEFAULT 'local' | مزامنة |
| `vector_clock` | `vector_clock` | `vectorClock` | TEXT • NOT NULL • DEFAULT '{}' | مزامنة |
| `device_id` | `device_id` | `deviceId` | TEXT • NOT NULL • DEFAULT '' | مزامنة |
| `sync_timestamp` | `sync_timestamp` | `syncTimestamp` | — | مزامنة |
| `idempotency_key` | `idempotency_key` | `idempotencyKey` | TEXT | مزامنة |

#### `price_adjustments` → D1 `price_adjustments` · Room `price_adjustments` · PriceAdjustmentEntity (33 حقلاً)

| العمود المحلي | اسم السلك | خاصية Kotlin | نوع D1 | ملاحظة |
| --- | --- | --- | --- | --- |
| `id` | `id` | `id` | INTEGER |  |
| `target_type` | `target_type` | `targetType` | TEXT • NOT NULL |  |
| `target_uuid` | `target_uuid` | `targetUuid` | TEXT • NOT NULL |  |
| `adjustment_type` | `adjustment_type` | `adjustmentType` | TEXT • NOT NULL |  |
| `previous_value` | `previous_value` | `previousValue` | REAL • NOT NULL |  |
| `new_value` | `new_value` | `newValue` | REAL • NOT NULL |  |
| `reason` | `reason` | `reason` | TEXT |  |
| `effective_date` | `effective_date` | `effectiveDate` | TEXT • NOT NULL |  |
| `applied_by` | `applied_by` | `appliedBy` | TEXT • NOT NULL |  |
| `hotel_day_key` | `hotel_day_key` | `hotelDayKey` | TEXT • NOT NULL |  |
| `adjustment_mode` | `adjustment_mode` | `adjustmentMode` | TEXT • NOT NULL • DEFAULT 'per_night' | افتراضي عند الغياب: `per_night` |
| `booking_uuid` | `booking_uuid` | `bookingUuid` | TEXT |  |
| `applied_at` | `applied_at` | `appliedAt` | INTEGER |  |
| `is_reversed` | `is_reversed` | `isReversed` | INTEGER • NOT NULL • DEFAULT 0 |  |
| `reversed_at` | `reversed_at` | `reversedAt` | TEXT |  |
| `reversed_by` | `reversed_by` | `reversedBy` | TEXT |  |
| `local_uuid` | `local_uuid` | `localUuid` | TEXT • NOT NULL | مزامنة |
| `server_id` | `server_id` | `serverId` | INTEGER | مزامنة |
| `created_at` | `created_at` | `createdAt` | INTEGER • NOT NULL | مزامنة |
| `updated_at` | `updated_at` | `updatedAt` | INTEGER • NOT NULL | مزامنة |
| `deleted_at` | `deleted_at` | `deletedAt` | INTEGER | مزامنة |
| `last_modified` | `last_modified` | `lastModified` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `created_at_iso` | `created_at_iso` | `createdAtIso` | TEXT | مزامنة |
| `updated_at_iso` | `updated_at_iso` | `updatedAtIso` | TEXT | مزامنة |
| `deleted_at_iso` | `deleted_at_iso` | `deletedAtIso` | TEXT | مزامنة |
| `created_at_epoch` | `created_at_epoch` | `createdAtEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `last_modified_epoch` | `last_modified_epoch` | `lastModifiedEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `version` | `version` | `version` | INTEGER • NOT NULL • DEFAULT 1 | مزامنة |
| `origin` | `origin` | `origin` | TEXT • NOT NULL • DEFAULT 'local' | مزامنة |
| `vector_clock` | `vector_clock` | `vectorClock` | TEXT • NOT NULL • DEFAULT '{}' | مزامنة |
| `device_id` | `device_id` | `deviceId` | TEXT • NOT NULL • DEFAULT '' | مزامنة |
| `sync_timestamp` | `sync_timestamp` | `syncTimestamp` | — | مزامنة |
| `idempotency_key` | `idempotency_key` | `idempotencyKey` | TEXT | مزامنة |

#### `audit_logs` → D1 `audit_logs` · Room `audit_logs` · AuditLogEntity (32 حقلاً)

| العمود المحلي | اسم السلك | خاصية Kotlin | نوع D1 | ملاحظة |
| --- | --- | --- | --- | --- |
| `id` | `id` | `id` | INTEGER |  |
| `operation_type` | `operation_type` | `operationType` | TEXT • NOT NULL |  |
| `entity_type` | `entity_type` | `entityType` | TEXT • NOT NULL |  |
| `entity_uuid` | `entity_uuid` | `entityUuid` | TEXT • NOT NULL |  |
| `entity_id` | `entity_id` | `entityId` | INTEGER |  |
| `previous_state` | `previous_state` | `previousState` | TEXT |  |
| `new_state` | `new_state` | `newState` | TEXT |  |
| `changed_fields` | `changed_fields` | `changedFields` | TEXT |  |
| `performed_by` | `performed_by` | `performedBy` | TEXT • NOT NULL |  |
| `ip_address` | `ip_address` | `ipAddress` | TEXT |  |
| `hotel_day_key` | `hotel_day_key` | `hotelDayKey` | TEXT • NOT NULL |  |
| `timestamp` | `timestamp` | `timestamp` | INTEGER • NOT NULL |  |
| `timestamp_iso` | `timestamp_iso` | `timestampIso` | TEXT • NOT NULL |  |
| `is_financial` | `is_financial` | `isFinancial` | INTEGER • NOT NULL • DEFAULT 0 |  |
| `amount_impact` | `amount_impact` | `amountImpact` | INTEGER |  |
| `local_uuid` | `local_uuid` | `localUuid` | TEXT • NOT NULL | مزامنة |
| `server_id` | `server_id` | `serverId` | INTEGER | مزامنة |
| `created_at` | `created_at` | `createdAt` | INTEGER • NOT NULL | مزامنة |
| `updated_at` | `updated_at` | `updatedAt` | INTEGER • NOT NULL | مزامنة |
| `deleted_at` | `deleted_at` | `deletedAt` | INTEGER | مزامنة |
| `last_modified` | `last_modified` | `lastModified` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `created_at_iso` | `created_at_iso` | `createdAtIso` | TEXT | مزامنة |
| `updated_at_iso` | `updated_at_iso` | `updatedAtIso` | TEXT | مزامنة |
| `deleted_at_iso` | `deleted_at_iso` | `deletedAtIso` | TEXT | مزامنة |
| `created_at_epoch` | `created_at_epoch` | `createdAtEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `last_modified_epoch` | `last_modified_epoch` | `lastModifiedEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `version` | `version` | `version` | INTEGER • NOT NULL • DEFAULT 1 | مزامنة |
| `origin` | `origin` | `origin` | TEXT • NOT NULL • DEFAULT 'local' | مزامنة |
| `vector_clock` | `vector_clock` | `vectorClock` | TEXT • NOT NULL • DEFAULT '{}' | مزامنة |
| `device_id` | `device_id` | `deviceId` | TEXT • NOT NULL • DEFAULT '' | مزامنة |
| `sync_timestamp` | `sync_timestamp` | `syncTimestamp` | — | مزامنة |
| `idempotency_key` | `idempotency_key` | `idempotencyKey` | TEXT | مزامنة |

#### `payment_voids` → D1 `payment_voids` · Room `payment_voids` · PaymentVoidEntity (32 حقلاً)

| العمود المحلي | اسم السلك | خاصية Kotlin | نوع D1 | ملاحظة |
| --- | --- | --- | --- | --- |
| `id` | `id` | `id` | INTEGER |  |
| `original_payment_uuid` | `original_payment_uuid` | `originalPaymentUuid` | TEXT • NOT NULL |  |
| `original_payment_id` | `original_payment_id` | `originalPaymentId` | INTEGER • NOT NULL |  |
| `booking_uuid` | `booking_uuid` | `bookingUuid` | TEXT • NOT NULL |  |
| `voided_amount` | `voided_amount` | `voidedAmount` | INTEGER • NOT NULL |  |
| `void_reason` | `void_reason` | `voidReason` | TEXT • NOT NULL |  |
| `voided_by` | `voided_by` | `voidedBy` | TEXT • NOT NULL |  |
| `voided_at` | `voided_at` | `voidedAt` | INTEGER • NOT NULL |  |
| `voided_at_iso` | `voided_at_iso` | `voidedAtIso` | TEXT • NOT NULL |  |
| `hotel_day_key` | `hotel_day_key` | `hotelDayKey` | TEXT • NOT NULL |  |
| `reversal_payment_uuid` | `reversal_payment_uuid` | `reversalPaymentUuid` | TEXT |  |
| `approved_by` | `approved_by` | `approvedBy` | TEXT |  |
| `note` | `note` | `note` | TEXT |  |
| `original_amount` | `original_amount` | `originalAmount` | REAL |  |
| `payment_uuid` | `payment_uuid` | `paymentUuid` | TEXT |  |
| `local_uuid` | `local_uuid` | `localUuid` | TEXT • NOT NULL | مزامنة |
| `server_id` | `server_id` | `serverId` | INTEGER | مزامنة |
| `created_at` | `created_at` | `createdAt` | INTEGER • NOT NULL | مزامنة |
| `updated_at` | `updated_at` | `updatedAt` | INTEGER • NOT NULL | مزامنة |
| `deleted_at` | `deleted_at` | `deletedAt` | INTEGER | مزامنة |
| `last_modified` | `last_modified` | `lastModified` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `created_at_iso` | `created_at_iso` | `createdAtIso` | TEXT | مزامنة |
| `updated_at_iso` | `updated_at_iso` | `updatedAtIso` | TEXT | مزامنة |
| `deleted_at_iso` | `deleted_at_iso` | `deletedAtIso` | TEXT | مزامنة |
| `created_at_epoch` | `created_at_epoch` | `createdAtEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `last_modified_epoch` | `last_modified_epoch` | `lastModifiedEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `version` | `version` | `version` | INTEGER • NOT NULL • DEFAULT 1 | مزامنة |
| `origin` | `origin` | `origin` | TEXT • NOT NULL • DEFAULT 'local' | مزامنة |
| `vector_clock` | `vector_clock` | `vectorClock` | TEXT • NOT NULL • DEFAULT '{}' | مزامنة |
| `device_id` | `device_id` | `deviceId` | TEXT • NOT NULL • DEFAULT '' | مزامنة |
| `sync_timestamp` | `sync_timestamp` | `syncTimestamp` | — | مزامنة |
| `idempotency_key` | `idempotency_key` | `idempotencyKey` | TEXT | مزامنة |

#### `inventory_items` → D1 `inventory_items` · Room `inventory_items` · InventoryItemEntity (24 حقلاً)

| العمود المحلي | اسم السلك | خاصية Kotlin | نوع D1 | ملاحظة |
| --- | --- | --- | --- | --- |
| `id` | `id` | `id` | INTEGER |  |
| `name` | `name` | `name` | TEXT • NOT NULL |  |
| `unit` | `unit` | `unit` | TEXT • NOT NULL • DEFAULT 'قطعة' | افتراضي عند الغياب: `قطعة` |
| `category` | `category` | `category` | TEXT |  |
| `current_quantity` | `current_quantity` | `currentQuantity` | — | يُغذّى من `quantity` على السلك • يُرسَل أيضاً كـ`quantity` |
| `minimum_quantity` | `minimum_quantity` | `minimumQuantity` | INTEGER • NOT NULL • DEFAULT 0 |  |
| `is_active` | `is_active` | `isActive` | INTEGER • NOT NULL • DEFAULT 1 | افتراضي عند الغياب: `true` |
| `local_uuid` | `local_uuid` | `localUuid` | TEXT • NOT NULL | مزامنة |
| `server_id` | `server_id` | `serverId` | INTEGER | مزامنة |
| `created_at` | `created_at` | `createdAt` | INTEGER • NOT NULL | مزامنة |
| `updated_at` | `updated_at` | `updatedAt` | INTEGER • NOT NULL | مزامنة |
| `deleted_at` | `deleted_at` | `deletedAt` | INTEGER | مزامنة |
| `last_modified` | `last_modified` | `lastModified` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `created_at_iso` | `created_at_iso` | `createdAtIso` | TEXT | مزامنة |
| `updated_at_iso` | `updated_at_iso` | `updatedAtIso` | TEXT | مزامنة |
| `deleted_at_iso` | `deleted_at_iso` | `deletedAtIso` | TEXT | مزامنة |
| `created_at_epoch` | `created_at_epoch` | `createdAtEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `last_modified_epoch` | `last_modified_epoch` | `lastModifiedEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `version` | `version` | `version` | INTEGER • NOT NULL • DEFAULT 1 | مزامنة |
| `origin` | `origin` | `origin` | TEXT • NOT NULL • DEFAULT 'local' | مزامنة |
| `vector_clock` | `vector_clock` | `vectorClock` | TEXT • NOT NULL • DEFAULT '{}' | مزامنة |
| `device_id` | `device_id` | `deviceId` | TEXT • NOT NULL • DEFAULT '' | مزامنة |
| `sync_timestamp` | `sync_timestamp` | `syncTimestamp` | — | مزامنة |
| `idempotency_key` | `idempotency_key` | `idempotencyKey` | TEXT | مزامنة |

#### `inventory_transactions` → D1 `inventory_transactions` · Room `inventory_transactions` · InventoryTransactionEntity (27 حقلاً)

| العمود المحلي | اسم السلك | خاصية Kotlin | نوع D1 | ملاحظة |
| --- | --- | --- | --- | --- |
| `id` | `id` | `id` | INTEGER |  |
| `item_id` | `item_id` | `itemId` | INTEGER • NOT NULL |  |
| `transaction_type` | `transaction_type` | `transactionType` | — | يُغذّى من `movement_type` على السلك • افتراضي عند الغياب: `adjustment` • يُرسَل أيضاً كـ`movement_type` |
| `quantity` | `quantity` | `quantity` | INTEGER • NOT NULL |  |
| `balance_after` | `balance_after` | `balanceAfter` | INTEGER • NOT NULL |  |
| `note` | `note` | `note` | TEXT |  |
| `item_local_uuid` | `item_local_uuid` | `itemLocalUuid` | TEXT |  |
| `user_id` | `user_id` | `userId` | INTEGER |  |
| `user_name` | `user_name` | `userName` | TEXT |  |
| `transaction_time` | `transaction_time` | `transactionTime` | — | يُغذّى من `created_at` على السلك • ميلي محلي (×1000 من السلك) |
| `local_uuid` | `local_uuid` | `localUuid` | TEXT • NOT NULL | مزامنة |
| `server_id` | `server_id` | `serverId` | INTEGER | مزامنة |
| `created_at` | `created_at` | `createdAt` | INTEGER • NOT NULL | مزامنة |
| `updated_at` | `updated_at` | `updatedAt` | INTEGER • NOT NULL | مزامنة |
| `deleted_at` | `deleted_at` | `deletedAt` | INTEGER | مزامنة |
| `last_modified` | `last_modified` | `lastModified` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `created_at_iso` | `created_at_iso` | `createdAtIso` | TEXT | مزامنة |
| `updated_at_iso` | `updated_at_iso` | `updatedAtIso` | TEXT | مزامنة |
| `deleted_at_iso` | `deleted_at_iso` | `deletedAtIso` | TEXT | مزامنة |
| `created_at_epoch` | `created_at_epoch` | `createdAtEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `last_modified_epoch` | `last_modified_epoch` | `lastModifiedEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `version` | `version` | `version` | INTEGER • NOT NULL • DEFAULT 1 | مزامنة |
| `origin` | `origin` | `origin` | TEXT • NOT NULL • DEFAULT 'local' | مزامنة |
| `vector_clock` | `vector_clock` | `vectorClock` | TEXT • NOT NULL • DEFAULT '{}' | مزامنة |
| `device_id` | `device_id` | `deviceId` | TEXT • NOT NULL • DEFAULT '' | مزامنة |
| `sync_timestamp` | `sync_timestamp` | `syncTimestamp` | — | مزامنة |
| `idempotency_key` | `idempotency_key` | `idempotencyKey` | TEXT | مزامنة |

#### `app_users` → D1 `app_users` · Room `app_users` · AppUserEntity (27 حقلاً)

| العمود المحلي | اسم السلك | خاصية Kotlin | نوع D1 | ملاحظة |
| --- | --- | --- | --- | --- |
| `id` | `id` | `id` | INTEGER |  |
| `username` | `username` | `username` | TEXT • NOT NULL |  |
| `password` | `password` | `password` | TEXT |  |
| `full_name` | `full_name` | `fullName` | TEXT • NOT NULL • DEFAULT '' |  |
| `user_type` | `user_type` | `userType` | TEXT • NOT NULL • DEFAULT '' |  |
| `permissions` | `permissions` | `permissions` | TEXT |  |
| `active` | `active` | `active` | INTEGER • NOT NULL • DEFAULT 1 | افتراضي عند الغياب: `true` |
| `last_login` | `last_login` | `lastLogin` | INTEGER |  |
| `credentials_version` | `credentials_version` | `credentialsVersion` | INTEGER • NOT NULL • DEFAULT 0 |  |
| `role` | `role` | `role` | TEXT |  |
| `local_uuid` | `local_uuid` | `localUuid` | TEXT • NOT NULL | مزامنة |
| `server_id` | `server_id` | `serverId` | INTEGER | مزامنة |
| `created_at` | `created_at` | `createdAt` | INTEGER • NOT NULL | مزامنة |
| `updated_at` | `updated_at` | `updatedAt` | INTEGER • NOT NULL | مزامنة |
| `deleted_at` | `deleted_at` | `deletedAt` | INTEGER | مزامنة |
| `last_modified` | `last_modified` | `lastModified` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `created_at_iso` | `created_at_iso` | `createdAtIso` | TEXT | مزامنة |
| `updated_at_iso` | `updated_at_iso` | `updatedAtIso` | TEXT | مزامنة |
| `deleted_at_iso` | `deleted_at_iso` | `deletedAtIso` | TEXT | مزامنة |
| `created_at_epoch` | `created_at_epoch` | `createdAtEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `last_modified_epoch` | `last_modified_epoch` | `lastModifiedEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `version` | `version` | `version` | INTEGER • NOT NULL • DEFAULT 1 | مزامنة |
| `origin` | `origin` | `origin` | TEXT • NOT NULL • DEFAULT 'local' | مزامنة |
| `vector_clock` | `vector_clock` | `vectorClock` | TEXT • NOT NULL • DEFAULT '{}' | مزامنة |
| `device_id` | `device_id` | `deviceId` | TEXT • NOT NULL • DEFAULT '' | مزامنة |
| `sync_timestamp` | `sync_timestamp` | `syncTimestamp` | — | مزامنة |
| `idempotency_key` | `idempotency_key` | `idempotencyKey` | TEXT | مزامنة |

#### `devices` → D1 `devices` · Room `devices` · DeviceInfoEntity (29 حقلاً)

| العمود المحلي | اسم السلك | خاصية Kotlin | نوع D1 | ملاحظة |
| --- | --- | --- | --- | --- |
| `id` | `id` | `id` | INTEGER |  |
| `device_name` | `device_name` | `deviceName` | TEXT • NOT NULL • DEFAULT '' |  |
| `device_model` | `device_model` | `deviceModel` | TEXT |  |
| `device_type` | `device_type` | `deviceType` | TEXT |  |
| `os_version` | `os_version` | `osVersion` | TEXT |  |
| `platform` | `platform` | `platform` | TEXT |  |
| `app_version` | `app_version` | `appVersion` | TEXT |  |
| `fcm_token` | `fcm_token` | `fcmToken` | TEXT |  |
| `status` | `status` | `status` | TEXT • NOT NULL • DEFAULT 'active' | افتراضي عند الغياب: `active` |
| `is_active` | `is_active` | `isActive` | INTEGER • NOT NULL • DEFAULT 1 | افتراضي عند الغياب: `true` |
| `last_seen` | `last_seen` | `lastSeen` | TEXT |  |
| `last_active` | `last_active` | `lastActive` | INTEGER |  |
| `local_uuid` | `local_uuid` | `localUuid` | TEXT • NOT NULL | مزامنة |
| `server_id` | `server_id` | `serverId` | INTEGER | مزامنة |
| `created_at` | `created_at` | `createdAt` | INTEGER • NOT NULL | مزامنة |
| `updated_at` | `updated_at` | `updatedAt` | INTEGER • NOT NULL | مزامنة |
| `deleted_at` | `deleted_at` | `deletedAt` | INTEGER | مزامنة |
| `last_modified` | `last_modified` | `lastModified` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `created_at_iso` | `created_at_iso` | `createdAtIso` | TEXT | مزامنة |
| `updated_at_iso` | `updated_at_iso` | `updatedAtIso` | TEXT | مزامنة |
| `deleted_at_iso` | `deleted_at_iso` | `deletedAtIso` | TEXT | مزامنة |
| `created_at_epoch` | `created_at_epoch` | `createdAtEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `last_modified_epoch` | `last_modified_epoch` | `lastModifiedEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `version` | `version` | `version` | INTEGER • NOT NULL • DEFAULT 1 | مزامنة |
| `origin` | `origin` | `origin` | TEXT • NOT NULL • DEFAULT 'local' | مزامنة |
| `vector_clock` | `vector_clock` | `vectorClock` | TEXT • NOT NULL • DEFAULT '{}' | مزامنة |
| `device_id` | `device_id` | `deviceId` | TEXT • NOT NULL | مزامنة |
| `sync_timestamp` | `sync_timestamp` | `syncTimestamp` | — | مزامنة |
| `idempotency_key` | `idempotency_key` | `idempotencyKey` | TEXT | مزامنة |

#### `blacklist` → D1 `blacklist` · Room `blacklist_entries` · BlacklistEntryEntity (28 حقلاً)

| العمود المحلي | اسم السلك | خاصية Kotlin | نوع D1 | ملاحظة |
| --- | --- | --- | --- | --- |
| `id` | `id` | `id` | INTEGER |  |
| `name` | `name` | `name` | TEXT • NOT NULL | يُغذّى من `guest_name` على السلك |
| `nationality` | `nationality` | `nationality` | TEXT • NOT NULL • DEFAULT '' |  |
| `national_id` | `national_id` | `nationalId` | TEXT | يُغذّى من `guest_id_number` على السلك |
| `phone` | `phone` | `phone` | TEXT | يُغذّى من `guest_phone` على السلك |
| `reason` | `reason` | `reason` | TEXT |  |
| `notes` | `notes` | `notes` | TEXT |  |
| `reported_by` | `reported_by` | `reportedBy` | TEXT | افتراضي عند الغياب: `police` |
| `active` | `active` | `active` | INTEGER • NOT NULL • DEFAULT 1 | يُغذّى من `is_active` على السلك • افتراضي عند الغياب: `true` • يُرسَل أيضاً كـ`is_active` |
| `added_by` | `added_by` | `addedBy` | TEXT |  |
| `added_date` | `added_date` | `addedDate` | TEXT |  |
| `local_uuid` | `local_uuid` | `localUuid` | TEXT • NOT NULL | مزامنة |
| `server_id` | `server_id` | `serverId` | INTEGER | مزامنة |
| `created_at` | `created_at` | `createdAt` | INTEGER • NOT NULL | مزامنة |
| `updated_at` | `updated_at` | `updatedAt` | INTEGER • NOT NULL | مزامنة |
| `deleted_at` | `deleted_at` | `deletedAt` | INTEGER | مزامنة |
| `last_modified` | `last_modified` | `lastModified` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `created_at_iso` | `created_at_iso` | `createdAtIso` | TEXT | مزامنة |
| `updated_at_iso` | `updated_at_iso` | `updatedAtIso` | TEXT | مزامنة |
| `deleted_at_iso` | `deleted_at_iso` | `deletedAtIso` | TEXT | مزامنة |
| `created_at_epoch` | `created_at_epoch` | `createdAtEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `last_modified_epoch` | `last_modified_epoch` | `lastModifiedEpoch` | INTEGER • NOT NULL • DEFAULT 0 | مزامنة |
| `version` | `version` | `version` | INTEGER • NOT NULL • DEFAULT 1 | مزامنة |
| `origin` | `origin` | `origin` | TEXT • NOT NULL • DEFAULT 'local' | مزامنة |
| `vector_clock` | `vector_clock` | `vectorClock` | TEXT • NOT NULL • DEFAULT '{}' | مزامنة |
| `device_id` | `device_id` | `deviceId` | TEXT • NOT NULL • DEFAULT '' | مزامنة |
| `sync_timestamp` | `sync_timestamp` | `syncTimestamp` | — | مزامنة |
| `idempotency_key` | `idempotency_key` | `idempotencyKey` | TEXT | مزامنة |

## ٤) قواعد العلاقات (FK) — ترجمة هوية الخادم إلى الهوية المحلية

المصدر الحاكم: `mobile/lib/services/sync/fk_rules.dart` في الفرع المرجعي (مستخرج آلياً من `local_db.dart` و`schema.sql`)، ومطابقة تنفيذه عندنا في `SyncIngestorRegistry`. **نوعان فقط:**

- `numericPointer`: العمود الرقمي يحمل `id` الأب في فضاء الخادم ⇒ يُترجَم إلى `id` الصف المحلي.
- `naturalKey`: العمود نصّي عالمي (`room_number` أو `local_uuid`) ⇒ يمر كما هو، ويُشترط وجود الأب فقط.

| الكيان | العمود | النوع | الأب | مفتاح الأب | nullable | عمود uuid-cache | يُجرَّب server_booking_id القديم | NULL عند تعذّر الحل |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `bookings` | `room_number` | `naturalKey` | `rooms` | `room_number` | لا | — | — | — |
| `booking_nights` | `booking_local_id` | `numericPointer` | `bookings` | `id` | لا | `booking_uuid_cache` | نعم | — |
| `booking_notes` | `booking_id` | `numericPointer` | `bookings` | `id` | لا | — | نعم | — |
| `payments` | `booking_local_id` | `numericPointer` | `bookings` | `id` | نعم | `booking_uuid_cache` | نعم | — |
| `payments` | `cash_transaction_local_id` | `numericPointer` | `cash_transactions` | `id` | نعم | — | — | نعم |
| `booking_price_adjustments` | `booking_local_id` | `numericPointer` | `bookings` | `id` | نعم | `booking_uuid` | نعم | — |
| `booking_price_adjustments` | `booking_local_uuid` | `naturalKey` | `bookings` | `local_uuid` | لا | — | — | — |
| `salary_cycles` | `employee_id` | `numericPointer` | `employees` | `id` | لا | `employee_uuid` | — | — |
| `salary_payments` | `cycle_id` | `numericPointer` | `salary_cycles` | `id` | لا | — | — | — |
| `salary_withdrawals` | `employee_id` | `numericPointer` | `employees` | `id` | لا | `employee_uuid` | — | — |
| `salary_carry_over_logs` | `employee_id` | `numericPointer` | `employees` | `id` | لا | — | — | — |
| `inventory_transactions` | `item_id` | `numericPointer` | `inventory_items` | `id` | لا | `item_local_uuid` | — | — |

### ٤.١ خوارزمية الحل (بالترتيب)

```text
① الهوية العالمية أولاً: uuid-cache على الابن → local_uuid الأب (الأوثق بين الأجهزة)
② ظلّ الخادم: bookings.server_id / *_id المحلي ← تُعلَّم من السحب (server_id := id الخادمي)
③ الفضاء القديم: server_booking_id على الابن ← server_booking_id على الأب (صفوف Appwrite المهاجرة)
④ فشل الكل: العمود nullable ⇒ يُترك NULL (أو يُحذف من الحمولة)؛ غير nullable ⇒
   الصف يُؤجَّل (deferred) ويُعاد بعد اكتمال الصفحات، وإن تكرّر ⇒ حجر بحمولته
```

**نقاط دقيقة مثبتة:**

- `booking_nights`: المفتاح الطبيعي `(booking_local_id, hotel_day_key)` — صف بـ`local_uuid` جديد لنفس الليلة **يُدمج LWW** بدل إدراج صف ثانٍ.
- `payments.cash_transaction_local_id`: مؤشر ثانوي — تعذّر الحل ⇒ NULL (لا يُعطّل الدورة).
- `payment_voids` و`price_adjustments`: كل أعمدتها uuid عالمية بلا قيود FK محلية ⇒ تمر بلا ترجمة.
- حارس الكتابة المحلية: أي كتابة تُثبّت `localUuid` من الصف القائم (لا تولّد جديداً عند التحديث).

---

## ٥) عقد الكتابة المحلية (ما يجب أن يفعله كل مسار كتابة)

| # | القاعدة | التفصيل |
| --- | --- | --- |
| 1 | ختم الزمن بالثواني | `createdAt/updatedAt/lastModified/deletedAt/lastModifiedEpoch = SyncEpochs.nowSeconds()` |
| 2 | `last_modified` يُكتب دائماً | لا يُترك صفراً: نموذج المجال لا يحمله ⇒ يُختم على `.toEntity()` أو على صف `getById` |
| 3 | `version+1` في التحديث | نظير `existing.version + 1` (كاسر تعادل الـWorker عند تساوي `updated_at`) |
| 4 | الكتابات الجزئية (UPDATE) | كل `@Query` تحديث يمرّر `lastModified` ويُرفع `version` حيث يرفعه Dart |
| 5 | outbox مع الكتابة | `enqueueObject(entity, op, localUuid, payload)` — و`insert` تُترجَم إلى `create` |
| 6 | الحذف ناعم + مزامن | `deleted_at` + `updated_at` + `last_modified` + صف outbox `delete` |
| 7 | حقول الهوية تُحفظ | عند التحديث: `localUuid/createdAt/serverId` من الصف القائم لا من النموذج |
| 8 | استثناء معلن | `checkout` (مسار الحجز): لا يدرج outbox — صراحةً مطابق للمرجع |
| 9 | الحقول المشتقة | تُحسب محلياً وتُكتب **بلا** لمس `last_modified/version` (وإلا منعت السحب من تحديثها) |

### ٥.١ جدول الكتابات الجزئية المصلَحة (عطل `last_modified=0`)

| DAO | الدالة | ما تكتبه الآن |
| --- | --- | --- |
| `BlacklistEntriesDao/CashTransactionsDao/DebtsDao/EmployeesDao/ExpensesDao/GuestInfosDao/InventoryDao/PaymentsDao/SalaryWithdrawalsDao/ShiftNotesDao/BookingsDao/RoomsDao` | `softDelete` | `deleted_at`,`updated_at`,`last_modified` = now(ثوانٍ) |
| `DebtsDao` | `updateSettlement` | + `version = version + 1` (نظير Dart) |
| `EmployeesDao` | `terminate / reactivate` | + `version = version + 1` |
| `PaymentsDao` | `voidPayment` | + `version = version + 1` + `is_immutable = 1` |
| `ShiftNotesDao` | `markRead` | + `version = version + 1` |
| `InventoryDao` | `softDeleteItem` | `deleted_at`,`updated_at`,`last_modified` |
| `InventoryDao` | `updateQuantity (بعد حركة)` | + `last_modified`,`last_modified_epoch`، `version+1` |

### ٥.٢ كتابات كاملة (insert/update) — العقد لكل مستودع

| المستودع | insert | update | ملاحظة |
| --- | --- | --- | --- |
| `BlacklistRepositoryImpl` | ثوانٍ + lastModified/epoch على الصف | ثوانٍ + version+1 (fallback: existing?.version ?: 1) | localUuid/createdAt من القائم |
| `CashRepositoryImpl` | ثوانٍ + lastModified/epoch | — | لا تحديث |
| `DebtsRepositoryImpl` | ثوانٍ + lastModified/epoch | ثوانٍ + version+1 | markSettled عبر DAO جزئي |
| `EmployeesRepositoryImpl` | ثوانٍ + lastModified/epoch | ثوانٍ + version+1 | terminate/reactivate جزئيان |
| `ExpensesRepositoryImpl` | ثوانٍ؛ `date` = ISO بالميلي | ثوانٍ + version+1 (coerce 0..999999) | مرآة السحب/الراتب داخل معاملة |
| `GuestInfosRepositoryImpl` | ثوانٍ + lastModified/epoch | ثوانٍ + version+1 (fallback ?: 1) |  |
| `InventoryRepositoryImpl` | ثوانٍ + lastModified/epoch | ثوانٍ + version+1 (fallback ?: prepared.version) | recordMovement: ختم الصنف + رفع الصف + الحركة |
| `PaymentsRepositoryImpl` | ثوانٍ؛ `payment_date` ISO بالميلي | ثوانٍ + version+1 | void: سجل payment_voids مختم + رفع الدفعة |
| `BookingsRepositoryImpl` | ثوانٍ + lastModified/epoch + إعادة بناء المشتقات | ثوانٍ + version+1 + إعادة البناء | updateComputedFields: بلا لمس lastModified/version |
| `BookingNightsRepositoryImpl` | replaceNights/upsertAdjustment: ثوانٍ | deactivateAdjustment: version+1 | منطق المفتاح الطبيعي |
| `SalaryRepositoryImpl` | insertCycle/insertPayment/carryOver: ثوانٍ + lastModified | updateCycle: ثوانٍ + version+1 | employee_uuid إلزامي |
| `SalaryWithdrawalsRepositoryImpl` | ثوانٍ؛ `withdraw_date` ميلي | ثوانٍ + حفظ localUuid/createdAt | مرآة المصروف |
| `ShiftNotesRepositoryImpl` | ثوانٍ + lastModified/epoch | ثوانٍ + version+1 | markRead جزئي + version |
| `RoomsRepositoryImpl` | ثوانٍ + lastModified/epoch | ثوانٍ + version+1 | updateStatus + مسح الإشغال |

---

## ٦) عقد السحب التفصيلي

### ٦.١ LWW + حارس انزياح الساعة (M3)

```text
normalizedRemote = toSeconds(record.last_modified)
if (local == null)                      ⇒ تخزين (صف جديد)
else if (remote.deleted_at != null)      ⇒ tombstone: تُحدَّث حقول المزامنة فقط (قرار نهائي)
else if (normalizedRemote >= toSeconds(local.last_modified)) ⇒ استبدال الصف المحلي (بنفس id)
else if (remote.version > local.version) ⇒ استبدال أيضاً  ← حارس M3 (ساعة الجهاز متقدمة)
else                                    ⇒ تخطٍّ (المحلي أحدث ولم يُرفع بعد)
```

**لماذا M3:** بلا الحارس، جهاز ساعته متقدمة يُسقط كل وارد إلى الأبد بينما مؤشر السحب يتقدم فوقه ⇒ فقد دائم غير مرئي. الدليل: الخادم يختم `version` بنفسه (`existing.version + 1` في `database.ts`) فلا يقبل نسخة العميل.

**تطابق التعادل:** عند تساوي الطابع يفوز الوارد (نظير `local > remote` كشرط تخطٍّ في Dart).

### ٦.٢ مسح الحذفيات (Tombstone sweep)

- الـWorker يدعم `tombstones_only=1` (الصفوف المحذوفة فقط) — نافذة رخيصة لالتقاط ما فاته عميل بنى على نافذة العقد القديم.
- العميل يمسح حتى **20 صفحة/دورة** بمؤشر محفوظ، والعلم لا يُضبط قبل الاكتمال.
- ترتيب البث: التمثال يُبَث في الترتيب الزمني نفسه بجوار الصفوف الحية (لا يُسطَّح مرة واحدة).

### ٦.٣ الحجر والشفاء (Quarantine)

| البند | القيمة |
| --- | --- |
| سعة الحجر | 300 صف (الأقدم يُطرد) |
| العتبة | 3 محاولات قبل اعتباره محجوراً دائماً (يُتخطى في صفحات السحب) |
| الشفاء | دفعة شفاء حتى 100/دورة (`healQuarantinedBatch`) |
| مبدأ حاكم | **المؤشر يتقدم دائماً** — لا تجميد؛ الصف المحجور يبقى قابل الاسترجاع بحمولته |
| أثر الصف السيئ | يُعزل ولا يُسقط الصفحة (فلسفة Dart: «الصف يُطبَّق» والبقية تمضي) |

### ٦.٤ إعادة بناء الحقول المشتقة

- الكيانات المُحفِّزة: `bookings`, `booking_nights`, `payments`, `price_adjustments`, `booking_price_adjustments`, `payment_voids`.
- تُنفَّذ بعد دورة السحب إن لمس أي منها، وفي معاملة واحدة لكل الدفعة، وحجز فاشل لا يُسقط البقية.
- الكاتب المحلي: أي كتابة حجز/دفعة تُعيد البناء في المعاملة نفسها.

### ٦.٥ حراس سلامة المؤشر

| الحارس | القيمة |
| --- | --- |
| سقف صفحات الدورة | 100 |
| نافذة الدلتا القصوى (مجموعة `updated_at` واحدة) | 20,000 صف |
| مؤشر مستقبلي مرفوض | > 2e9 |
| تقدم على الخادم مرفوض | > 366 يوماً |
| معاينة `remaining` | كل 5 صفحات (تخفيف حمل) |

---

## ٧) الإشغال والحالات (نظير `status_utils.dart`)

### ٧.١ `refreshAllRoomOccupancy` (النقل الحرفي)

```text
occupied = { room_number | bookings.deleted_at IS NULL AND status IN (التسعة) }
لكل غرفة غير محذوفة:
  shouldBeOccupied = occupied.contains(room.roomNumber)
  if ( shouldBeOccupied && !isRoomOccupied(room.status))   ⇒ status = 'محجوزة'
  else if (!shouldBeOccupied && !isRoomAvailable(room.status)) ⇒ status = 'شاغرة'
  else ⇒ لا كتابة (بلا رفع نسخة وبلا outbox)
```

الاستدعاءان الوحيدان: حفظ الحجز (`booking_edit.dart` l.1131) وإتمام المغادرة (`booking_checkout_screen.dart` l.702-711). **المقايضة المعلنة:** غرفة «صيانة» بلا حجز نشط ⇒ «شاغرة» (سلوك Dart الحرفي — ليست مشغولة ولا متاحة).

### ٧.٢ مجموعات الحالات

| المجموعة | القيم (كما في Dart) |
| --- | --- |
| غرف متاحة | `شاغرة`, `شاغره`, `متاحة`, `متاح`, `available`, `vacant`, `empty` |
| غرف مشغولة | `محجوزة`, `محجوز`, `مشغولة`, `occupied`, `محجوز temporarily`, `نشط`, `active`, `مؤقت`, `provisional` |
| غرف مكتملة (مستبعدة صراحةً من الإشغال) | `مكتمل`, `مكتملة`, `completed`, `checked_out`, `checked out` |
| صيانة | `صيانة`, `maintenance`, `under_maintenance`, `under maintenance` |
| حجوزات نشطة (SQL) | `محجوزة`, `محجوز`, `نشط`, `active`, `confirmed`, `قيد الحجز`, `in_progress`, `مؤقت`, `provisional` |

التطبيع قبل المقارنة: `trim + lowercase`. ومنطق الحجز الفعّال: `isRoomOccupied` يستبعد المكتملة **صراحةً** ثم يفحص مجموعة المشغولة؛ و`isRoomAvailable` تتقاطع مع المشغولة.

## ٨) الثوابت والحراس — جدول موحّد

| الثابت | القيمة | الجهة |
| --- | --- | --- |
| `MS_TIMESTAMP_THRESHOLD` / `MILLIS_EPOCH_THRESHOLD` / `MILLIS_THRESHOLD` | 1e11 | Worker + Android (ثلاثة أسماء لعقد واحد) |
| `FUTURE_TIMESTAMP_THRESHOLD` / `FUTURE_THRESHOLD` | 2e9 | Worker + Android |
| `CLOCK_SKEW_ALLOWANCE_S` | 90 ثانية | Worker |
| `MAX_SANE_VERSION` | 1,000,000 | Worker (نسخة أعلى ⇒ 1) |
| `PUSH_BATCH_SIZE` | وفق `CloudflareConfig` | Android |
| `MAX_ATTEMPTS_BEFORE_BACKOFF` | 5 (بلا `salary_withdrawals`) | Android (dead-letter) |
| `MAX_PULL_PAGES_PER_CYCLE` | 100 | Android |
| `MAX_TOMBSTONE_SWEEP_PAGES_PER_CYCLE` | 20 | Android |
| `MAX_PULL_WINDOW` | 20,000 | Worker |
| `MAX_SANE_PULL_CURSOR_FUTURE` | 2e9 | Android |
| `MAX_PULL_CURSOR_AHEAD_OF_SERVER_SEC` | 366 يوماً | Android |
| `PULL_QUARANTINE_CAP` / عتبة العزل / `HEAL_LIMIT` | 300 / 3 / 100 | Android |
| `AUTOMATIC_PULL_INTERVAL_MS` | 60 دقيقة | Android (بوابة الدلتا) |
| `PENDING_PUSH_MONITOR_MS` | 5 دقائق | Android |
| `REALTIME_DEBOUNCE_MS` / `REALTIME_PULL_COOLDOWN_MS` | 500ms / 15s | Android |
| `REALTIME_BASE_BACKOFF_MS` / `MAX_BACKOFF_MS` / `MAX_RECONNECT_ATTEMPTS` | 1s / 60s / 6 | Android |
| `REALTIME_REARM_INTERVAL_MS` / `REALTIME_HEARTBEAT_MS` | 120s / 30s | Android |
| `sync/auto_outbox_sync_watcher` (Dart) | نظير مراقب المعلّقات | Dart |

---

## ٩) عقود الاختبار (ما يقفله كل ملف)

| الملف | الحالات | ما يقفله |
| --- | --- | --- |
| `RepositoryEpochParityTest.kt` | 11 | طوابع ثوانٍ + version+1 لكل مستودع + حقول الأعمال بالميلي + تسلسل الكيان (ظلّ Gson) |
| `RoomOccupancySweepParityTest.kt` | 6 | حالات المسح الأربع + عدم الكتابة بلا داعٍ + فرع originIsServer |
| `StatusUtilsParityTest.kt` | 5 | مطابقة مجموعات الحالات مع `status_utils.dart` |
| `SyncIngestorRegistryTest.kt` | 63 | FK/تأجيل/عزل/LWW/حارس الانزياح/الحذفيات |
| `SyncPullParityTest.kt` | 12 | عقد السحب (مؤشر/صفحات/استئناف) |
| `BookingDerivedRefreshParityTest.kt` | 6 | إعادة بناء المشتقة + الحذف |
| `SyncEpochParityTest.kt` | — | وحدة الطوابع (ثوانٍ) على مسار الغرف |
| `SyncWireFieldParityTest.kt` | — | أسماء السلك + الافتراضيات + وحدة `transaction_time` |
| `worker/test/*.ts` | — | عقد الـWorker (sweep/تكافؤ لقطات المالية/idempotency) |

## ١٠) أدلة التشغيل (آخر دورة)

| التشغيل | الالتزام | النتيجة |
| --- | --- | --- |
| Sync Unit Tests `37698116017` | `d364b90b` | success — `:app:testDebugUnitTest` ‏409 حالة • 0 فشل • 0 خطأ • 0 متخطّاة؛ worker vitest+typecheck success؛ detekt success |
| Android APK Build `37698116051` | `d364b90b` | success — release موقّع 5,960,887 بايت (`9771b444…`)، debug 25,366,772 بايت؛ apksigner v1/v2/v3 = true |

التشغيل الأحمر الوحيد على الفرع: «Code scanning AI findings on PR #617» (`github-advanced-security`، وكيل Copilot Autofix) — يفشل في خطوة «Processing Request» بعد نجاح كل خطوات الإعداد، وعلى فروع أخرى كذلك ⇒ خارجي.

---

## ١١) فجوات وتحفّظات معلنة (لا مخفية)

- `hotel_day_ledger`: جدول **محلي بحت** — غير موجود في `ENTITY_TABLES`؛ لا يُزامَن (خطة D8).
- `finance_snapshots`: مرآة مخطط موثّقة؛ المسارات في الفرع المرجعي فقط ولا مستدعٍ عندنا.
- `blacklist` كيان سلكي بلا جدول Drift في Flutter الأصلي (عندنا `blacklist_entries`).
- `BookingsRepositoryImpl.checkout`: بلا إدراج outbox (مقصود؛ المسار الفعلي `update`).
- `inventory_transactions.transaction_time`: عمود محلي بحت (لا مقابل على السلك) — يُغذّى من `created_at` ×1000.
- `D1` يجلب بترتيب `DESC` مقابل `ASC` في Room لبعض الفهارس — افتراق موثّق بلا أثر وظيفي.

## ١٢) قائمة تحقق — تطبيق Flutter/Dart

> الترتيب مقصود: كل بند قابل للفحص الآلي (مقارنة شيفرة أو اختبار).

| # | البند | معيار القبول |
| --- | --- | --- |
| 1 | وحدة الزمن | كل كتابة محلية على أعمدة المزامنة = `Time.nowEpoch()` (ثوانٍ)؛ والحقول الزمنية-العملية تبقى بوحدتها (§٢.٣) |
| 2 | ختم `last_modified` | لا يوجد مسار يكتب `last_modified = 0` — كل insert/update/softDelete يختمه |
| 3 | `version+1` | كل تحديث يرفع النسخة من الصف القائم (`existing.version + 1`) |
| 4 | الكتابات الجزئية | كل `update` جزئي يمرّر `lastModified` — لا استثناء |
| 5 | الحذف الناعم | `deleted_at + updated_at + last_modified` + صف outbox بمرآة الحذف |
| 6 | صندوق الصادر | idempotencyKey = `entity_op_localUuid_uuid`؛ insert⇒create؛ blacklist_entries⇒blacklist؛ bool⇒int؛ camelCase⇒snake_case |
| 7 | استيعاب السحب | ترتيب: كيان → FK (fk_rules) → aliases → defaults → وحدة الطوابع → LWW |
| 8 | LWW | `remote >= local` ⇒ استبدال؛ ومع `remote.version > local.version` ⇒ استبدال حتى لو الطابع أقدم |
| 9 | tombstone | يُطبَّق دائماً بحقول المزامنة فقط، ولا يعطّل الدورة |
| 10 | المفتاح الطبيعي | `booking_nights` بـ`(booking_local_id, hotel_day_key)` يُدمج LWW لا يُدرج ثانياً |
| 11 | الحجر | سعة 300، عتبة 3، شفاء 100/دورة، والمؤشر يتقدم دائماً |
| 12 | مسح الحذفيات | `tombstones_only=1` حتى 20 صفحة/دورة بمؤشر لا يُضبط قبل الاكتمال |
| 13 | الحقول المشتقة | تُبنى بعد السحب عند لمس الكيانات الستة، وبلا لمس `last_modified/version` |
| 14 | الإشغال | `refreshAllRoomOccupancy` حرفياً بموضعَي الاستدعاء، بما فيه سلوك الصيانة |
| 15 | الحالات | المجموعات الخمس حرفية بتطبيع `trim+lowercase` |
| 16 | الحقن/الحماية | `clear_employee_link=1` عند الفصل الصريح فقط؛ ولا يُرسَل `employee_uuid` فارغاً عمداً |
| 17 | الاختبارات | عقد آلي يقفل: الوحدة، version، المسح، المجموعات، FK، LWW، الحجر |
| 18 | الأدلة | تشغيل CI أخضر + إفصاح عن أي فشل خارجي (لا ادّعاء نجاح بلا تشغيل) |

---

**نهاية المسودة.** أي بند بلا دليل تشغيل في هذا الملف مُعلَم؛ وما لم يُذكر هنا فمرجعه الفرع `arena/be8302d7-marina-hotel-wit-app` نفسه (المصدر الأصدق).
