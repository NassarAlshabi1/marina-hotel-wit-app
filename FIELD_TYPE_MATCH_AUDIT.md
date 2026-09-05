# تدقيق مطابقة أنواع الحقول — Drift (mobile) ↔ Cloudflare D1 (worker)

> **الحالة:** مسودة — نتائج تدقيق (2026-09-05)
> **الفرع:** `agent/lunar-sharp-n1st` — HEAD `75162383`
> **النطاق:** كيانات المزامنة الـ 23 في `mobile/lib/services/cloudflare_config.dart` (`migrationOrder`)
> **المصادر:**
> - Drift: `mobile/lib/services/local_db.dart` (`SyncFields` mixin سطر 19، الجداول)
> - D1: `worker/schema.sql` + `worker/migrations/0002_inventory_blacklist.sql` + `worker/migrations/0003_app_users.sql`
> - ترشيح الأعمدة عند الـ push: `worker/src/database.ts:346`

---

## الخلاصة التنفيذية

مطابقة الأنواع **ليست 100%**.

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
