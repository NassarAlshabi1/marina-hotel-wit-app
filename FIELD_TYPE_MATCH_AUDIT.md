# تدقيق مطابقة أنواع الحقول — Drift (mobile) ↔ Cloudflare D1 (worker)

> **الحالة:** مسودة — نتائج تدقيق (2026-09-05)
> **الفرع:** `agent/lunar-sharp-n1st` — HEAD `75162383`
> **النطاق:** كيانات المزامنة الـ 23 في `mobile/lib/services/cloudflare_config.dart` (`migrationOrder`)
> **المصادر:**
> - Drift: `mobile/lib/services/local_db.dart` (`SyncFields` mixin سطر 19، الجداول)
> - D1: `worker/schema.sql` + `worker/migrations/0002_inventory_blacklist.sql` + `worker/migrations/0003_app_users.sql`
> - ترشيح الأعمدة عند الـ push: `worker/src/database.ts:346`

---

## 🔴 تحديث (تدقيق عميق) — المشكلة الأخطر: عدم تطابق **حالة أحرف المفاتيح** (casing)، وليس الأنواع

التتبع الكامل لمسار الدفع (outbox → `cloudflare_sync_manager._pushBatch` → worker) كشف أن
مشكلة **أنواع** الحقول ثانوية. المشكلة الجوهرية: **معظم الكيانات تُرسل حمولة بمفاتيح
camelCase** (صيغة Appwrite القديمة) إلى worker لا يقبل إلا **snake_case** ويقرأ
`data.local_uuid`. النتيجة: فقدان بيانات صامت وكسر الهوية عند الدفع لهذه الكيانات.

### سلسلة الأدلة (كود مُتحقَّق منه)
1. **worker يتوقع snake_case فقط**: `createRecord` يقرأ `data.local_uuid` وإلا يولّد
   UUID عشوائياً (`database.ts:301`)، ويُرشّح المفاتيح مقابل أعمدة D1 الفعلية
   (snake) عبر `getTableColumns` (PRAGMA table_info) — **لا يوجد أي تحويل
   camelCase→snake** في الـ worker (`database.ts:342-349`). و`updateRecord` يستدعي
   `requireEntityId(data)` = `data.local_uuid ?? data.id ?? data.server_id`
   (`sync.ts:60-63`).
2. **الدفع يُرسل الحمولة حرفياً**: `_pushBatch` يُرسل `data = jsonDecode(item.payload)`
   دون أي تطبيع/تحويل (`cloudflare_sync_manager.dart:511-521`).
3. **العقد الصحيح** (مسار `app_users` في الـ HEAD): `appUsersSyncPayload` يبني
   snake_case + `local_uuid` + `vector_clock` + حقول المزامنة + bool→int
   (`auth_local_store.dart`). هذا هو النموذج الصحيح. ✅
4. **الكيانات المكسورة** تُبنى بـ camelCase عبر `adapter.toJson(row, src: Source.appwrite)`
   (يُثبت الاختبار `adapters_round_trip_test.dart:104-110` أن ناتج `Source.appwrite`
   هو `localUuid`/`roomNumber`/`guestName` = camelCase) أو عبر خرائط camelCase يدوية
   في الخدمات/المستودعات.
5. **لا اختبار يحرس هذا العقد**: `cloudflare_sync_manager_test.dart` يختبر الحالة/التهيئة
   فقط، واختبارات الـ worker (87 ناجحة) تستخدم عيّنات snake_case مكتوبة يدوياً — فلا
   تلتقط حمولة العميل الحقيقية.

### مصفوفة حالة الأحرف لكل كيان (حمولة outbox الفعلية)

| الحالة | الكيانات | المصدر |
|---|---|---|
| ✅ **snake_case (صحيح)** | `rooms`, `debts`, `cash_transactions`, `booking_notes`, `shift_notes`, `app_users` | `_payloadFrom` في الـ DAO / `appUsersSyncPayload` |
| ❌ **camelCase (مكسور)** | `bookings`, `payments`, `expenses`, `employees` | DAO → `toJsonForSource(row, Source.appwrite)` |
| ❌ **camelCase (مكسور)** | `guest_infos`, `inventory_items`, `inventory_transactions`, `salary_withdrawals`, `booking_price_adjustments`, `payment_voids`, `price_adjustments`, `blacklist` | خرائط camelCase يدوية في المستودعات/الخدمات |
| ⚠️ **مسار الإدراج غير مؤكد** | `booking_nights`, `salary_cycles`, `salary_payments`, `salary_carry_over_logs`, `audit_logs` | ظهرت فقط في `delta_sync_service` (محرك Drive منفصل) — لم أؤكد كيف/هل تُدرَج في outbox الخاص بـ Cloudflare |

### الأثر على الكيانات المكسورة
- **create**: `data.local_uuid` غير موجود (المفتاح `localUuid`) → الـ worker يولّد UUID
  عشوائياً، وكل أعمدة العمل camelCase تُسقَط بالمُرشِّح → صف بقيم افتراضية وهوية خاطئة.
- **update**: `requireEntityId` يرجع إلى `data.id` (المعرّف المحلي الرقمي) →
  `WHERE local_uuid = '<رقم>'` → لا تطابق → التحديث لا يُصيب أي صف.
- **النتيجة**: مزامنة Cloudflare غير وظيفية عملياً لهذه الكيانات (فقدان بيانات صامت).

### مستوى الثقة
- **عالٍ على مستوى الكود** — الأدلة متسقة ومتقاطعة (كود worker + كود adapter +
  اختبار round-trip يؤكد camelCase + غياب أي تطبيع + غياب اختبار حارس).
- **لم يُتحقق وقت التشغيل**: Flutter غير مثبت في الـ sandbox، فلم أُنفّذ دفعاً حياً ضد
  worker حقيقي. يُوصى بتشغيل دفعة `bookings` واحدة ومراقبة صف D1 لتأكيد نهائي.

### الإصلاح المقترح (جذري)
توحيد كل مسارات الدفع إلى Cloudflare على **snake_case + local_uuid + vector_clock**:
إمّا تمرير `Source.drive` (الذي يُنتج snake_case) في مسار outbox الخاص بـ Cloudflare،
أو إضافة `Source.cloudflare` مخصص، أو تطبيق `_toSnakeCase`/`PayloadMapper` داخل
`_pushBatch` قبل الإرسال — مع إضافة اختبار end-to-end يحرس العقد لكل الكيانات الـ 23.

---

## الخلاصة التنفيذية (مطابقة الأنواع)

مطابقة الأنواع **ليست 100%** (لكنها ثانوية مقارنةً بمشكلة الـ casing أعلاه).

- ✅ `app_users` (كيان الـ HEAD الجديد): مطابقة كاملة عموداً بعمود.
- ⚠️ تعارض نوع مؤكد واحد: `price_adjustments.previous_value` / `new_value` (Drift **REAL** مقابل D1 **INTEGER**).
- ⚠️ عدة جداول D1 متأخرة عن Drift بأعمدة ناقصة (تُسقَط بصمت لو أُرسلت في حمولة الـ push).

---

## قواعد الربط المعتمدة

| Drift | D1 (SQLite) |
|---|---|
| `IntColumn` | `INTEGER` |
| `TextColumn` | `TEXT` |
| `RealColumn` | `REAL` |
| `BoolColumn` | `INTEGER` (0/1) — **متوقع، ليس اختلافاً** |
| `.nullable()` | `NULL` مسموح؛ غيرها `NOT NULL` |
| camelCase | snake_case |

**الجسر الآمن:** الـ worker يُرشّح الأعمدة المجهولة عند الـ push
(`if (value !== undefined && validColumns.has(key))` — `database.ts:346`)، فأي عمود
غير موجود في جدول D1 الهدف **يُسقَط بصمت دون خطأ** — لكنه أيضاً **لا يُحفَظ**.
لذلك `sync_timestamp` (موجود في Drift `SyncFields` ومستبعَد عمداً من كل جداول D1) سليم.

---

## ✅ ما هو صحيح تماماً

- **`app_users`** — طوبِقَ كل عمود بين `class AppUsers` (Drift) و`0003_app_users.sql`:
  المعرّفات، `active` (bool→INTEGER)، `credentials_version`، `last_login`، وكل حقول
  `SyncFields` وnullability — **مطابقة 100%**.
- حقول المبالغ/الأسعار في بقية الكيانات (`rooms.price`، `employees.basic_salary`،
  `cash_transactions.amount`، `payments.amount`، `expenses.amount`، إجماليات `debts`،
  أسعار `booking_nights`، `salary_withdrawals.amount`، `booking_price_adjustments.amount`،
  `payment_voids.original_amount`) كلها **REAL↔REAL** متطابقة.
- أعمدة الرواتب الصحيحة (`expected_amount`، `actual_paid`، `remaining_amount`،
  `salary_payments.amount`، `payment_voids.voided_amount`) **INTEGER↔INTEGER** متطابقة.
- كيانات مطابقة تماماً (لا تعارض نوع ولا أعمدة ناقصة): `rooms`, `employees`, `expenses`,
  `booking_notes`, `shift_notes`, `cash_transactions`, `salary_cycles`, `salary_payments`,
  `salary_withdrawals`, `audit_logs`, `payment_voids`, `inventory_items`,
  `inventory_transactions`, `app_users`.

---

## ⚠️ (أ) تعارض نوع مؤكد — `price_adjustments`

| العمود | Drift (`local_db.dart`) | D1 (`schema.sql:724-725`) |
|---|---|---|
| `previous_value` | `RealColumn` → **REAL** (سطر ~490) | `INTEGER NOT NULL` |
| `new_value` | `RealColumn` → **REAL** (سطر ~491) | `INTEGER NOT NULL` |

- **السبب:** في *Wave 6b (2026-08-12)* غُيِّرا في Drift من `IntColumn` → `RealColumn`
  (عقد السحابة `double`) لمنع اقتطاع قيم مثل `1500.75` → `1500`، لكن **لم يُحدَّث
  `worker/schema.sql`** فبقيا `INTEGER`. لا توجد migration لاحقة تصحّحهما
  (`grep previous_value` → schema.sql فقط).
- **الأثر الفعلي:** محدود — بمرونة أنواع SQLite، قيمة REAL في عمود بـ INTEGER affinity
  تُخزَّن كـ REAL (لا تُقتطع). لكنه تعارض تصريحي حقيقي يخالف Drift وعقد السحابة،
  ويجب توحيده إلى `REAL`.
- **ملاحظة إضافية (nullability):** `hotel_day_key` في D1 `NOT NULL` بينما في Drift
  `nullable()` — عدم تطابق ثانوي (الـ worker يملأ `''` عند الغياب).

---

## ⚠️ (ب) أعمدة موجودة في Drift ومفقودة من جدول D1

> **تصحيح بعد التتبع العميق:** بُنّاة الحمولة تستخدم **قوائم بيضاء منتقاة** (مثل
> `_payloadFrom` في `debts_dao` الذي يُرسل 14 عموداً فقط، جميعها موجودة في D1). لذا
> معظم الأعمدة أدناه (مثل `debts.guest_phone/description/status/due_date/amount/date`)
> **لا تُرسَل أصلاً** — فهي حقول Appwrite خاملة، وليست فقدان بيانات فعلياً عبر Cloudflare.
> يبقى المهم منها ما يُرسَل فعلاً (انظر قسم الـ casing؛ وأي عمود ضمن حمولة snake_case
> لكنه غير موجود في D1 سيُسقَط). القائمة أدناه للأرشفة/المطابقة الكاملة فقط.

هذه لا تُسبّب خطأً (يُرشّحها الـ worker)، لكن **أي قيمة فيها تُرسَل لن تُحفَظ في D1**
فتُفقَد عند السحب لجهاز آخر — بقدر وجودها ضمن حمولة الـ push الفعلية لمسار Cloudflare.

| الجدول | الأعمدة الناقصة في D1 |
|---|---|
| `price_adjustments` | `adjustment_mode`, `booking_uuid`, `applied_at` |
| `debts` | `guest_phone`, `description`, `status`, `due_date`, `booking_uuid_cache`, `debtor_name`, `amount`, `date` |
| `bookings` | `financial_frozen_at`, `financial_hash` |
| `payments` | `void_reason`, `is_immutable`, `received_by_user_id`, `received_by_name`, `received_session_uuid`, `received_by_cloud_id` |
| `booking_nights` | `booking_uuid_cache`, `server_booking_id` |
| `salary_carry_over_logs` | `from_cycle_id`, `to_cycle_id`, `carry_date`, `performed_by`, `hotel_day_key` |
| `guest_infos` | `guest_phone` |

> أعمدة `debts` الإضافية أُضيفت لِـ whitelist في `appwrite_sync_utils.dart` (Wave 6)
> — يجب التحقق أيّها ضمن حمولة push مسار Cloudflare فعلاً.

---

## (ج) حالة `blacklist`

- **cloud-only** — لا يوجد `class Blacklist` في Drift. الجدول موجود فقط في D1
  (`schema.sql` + `0002_inventory_blacklist.sql`). لا مقارنة أنواع ممكنة/مطلوبة.
  **ليس اختلافاً.**

---

## الخطوات المقترحة

1. **تحديد النطاق الحقيقي:** فحص أيّ من أعمدة القسم (ب) موجودة فعلاً في حمولة push
   مسار Cloudflare (outbox payload) لتمييز فقدان البيانات الحقيقي عن الأعمدة الخاملة.
2. **migration واحدة `0004`** تُصلح الكل:
   - تحويل `price_adjustments.previous_value` / `new_value` إلى `REAL`.
   - إضافة الأعمدة الناقصة المؤكَّد أنها تُزامَن لِـ D1 لمطابقة Drift.
3. تحديث `worker/schema.sql` ليعكس الحالة النهائية، وإضافة اختبار worker يتحقق من
   تكافؤ مجموعة الأعمدة بين Drift وD1 لكل كيان لمنع الانحراف مستقبلاً.

---

## سجل التحقق

- `worker` — الأعمدة تُرشَّح عند الـ push: `database.ts:340-349` ✔
- لا migration تُصحّح `previous_value`/`new_value`: `grep` → `schema.sql:724-725` فقط ✔
- `app_users` مطابق: `0003_app_users.sql` ↔ `class AppUsers` ✔
- الفرع نظيف عند التدقيق: HEAD `75162383`
