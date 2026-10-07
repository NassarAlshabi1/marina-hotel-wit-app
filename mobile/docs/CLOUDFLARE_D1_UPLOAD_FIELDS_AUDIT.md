# تدقيق: الجداول والحقول المرفوعة إلى Cloudflare D1

**التاريخ:** 2026-09-28
**الفرع:** `refactor/performance-fixes-v2`
**نوع الفحص:** فحص مصدري مباشر (لا تخمين) — مطابق للسياسة `docs/PERFORMANCE.md` §3 "قياس لا تخمين".

## السؤال

هل يتم إرسال جميع حقول جداول المزامنة، بما فيها حقل `vector_clock`، ضمن ميزة
"النسخ الاحتياطي" إلى Cloudflare في شاشة الإعدادات؟

## الجواب: نعم

آلية الرفع لا تبني JSON يدويًا حقلاً حقلاً (وهو المكان الشائع لنسيان حقل)، بل
تستخدم `SELECT *` حرفيًا من قاعدة البيانات المحلية، ثم تشتق أسماء الأعمدة
المرفوعة من مفاتيح الصفوف المقروءة فعليًا — بلا أي قائمة بيضاء أو تصفية.

## مسارات الملفات ذات الصلة

| الغرض | المسار |
|---|---|
| شاشة الإعدادات (نقطة الدخول) | `mobile/lib/screens/settings/settings_screen.dart` |
| شاشة النسخ الاحتياطي الشاملة (تبويبات) | `mobile/lib/screens/settings/backup/comprehensive_backup_screen_v2.dart` |
| تبويب Cloudflare D1 (بناء البيانات المُرسلة + قائمة الجداول الافتراضية) | `mobile/lib/screens/settings/backup/tabs/cloudflare_d1_tab.dart` |
| خدمة الرفع الفعلي (HTTP إلى Cloudflare) | `mobile/lib/services/cloudflare_d1_service.dart` |
| تعريف الجداول وحقل `vector_clock` (mixin `SyncFields`) | `mobile/lib/services/local_db.dart` |
| الأعمدة الفعلية المولّدة في SQLite (تأكيد اسم العمود) | `mobile/lib/services/local_db.g.dart` |
| اختبار انحدار قائم مسبقًا يثبّت هذا السلوك | `mobile/test/unit/cloudflare_d1_upload_fields_test.dart` |

## آلية الرفع

في `cloudflare_d1_tab.dart` (حول السطر 323-334)، دالة `readChunk` المستخدمة لكل جدول:

```dart
readChunk: (limit, offset) async {
  final rows = await db
      .customSelect(
        'SELECT * FROM "${table.name.replaceAll('"', '""')}" LIMIT ? OFFSET ?',
        variables: [Variable.withInt(limit), Variable.withInt(offset)],
      )
      .get();
  return rows.map((r) => r.data).toList();
},
```

وفي `cloudflare_d1_service.dart` (`uploadData`)، أسماء الأعمدة المرفوعة تُشتق
مباشرة من مفاتيح أول صف مقروء — بلا أي `whitelist`/`blacklist`:

```dart
if (columns.isEmpty) {
  columns = firstChunk.first.keys.toList();
  await _reconcileSchema(t, columns, warnings);
}
...
final values = columns.map((c) => _sqlLiteral(row[c])).join(',');
statements.add(
  'INSERT OR REPLACE INTO "${_quoteIdent(t.name)}" '
  '(${columns.map(_quoteIdent).join(',')}) VALUES ($values)',
);
```

## حقل `vector_clock`

معرّف مرة واحدة في mixin `SyncFields` (`local_db.dart` السطر 33)، والمطبّق على
كل جداول المزامنة:

```dart
TextColumn get vectorClock => text().withDefault(const Constant('{}'))();
```

تم التأكد من الملف المولّد `local_db.g.dart` أن اسم العمود الفعلي في SQLite هو
**`vector_clock`** (الأسطر 162، 461، 634، 780). بما أن الرفع يعتمد على
`SELECT *` بلا تصفية، فإن `vector_clock` يُرفع تلقائيًا مع كل الحقول الأخرى.

## الجداول الافتراضية المرفوعة (21 جدولاً — `kAppwriteSyncedTables`)

هذه هي الجداول المحددة افتراضيًا عند تفعيل مفتاح "جداول مزامنة Appwrite Cloud
فقط" في تبويب Cloudflare D1. كل جدول منها يحمل mixin **`SyncFields`** الذي
يضيف 17 حقل مزامنة مشترك.

### الحقول المشتركة (SyncFields) — موجودة في كل جدول أدناه

```
local_uuid, server_id, created_at, updated_at, deleted_at, last_modified,
created_at_iso, updated_at_iso, deleted_at_iso, created_at_epoch,
last_modified_epoch, version, origin, vector_clock, device_id,
sync_timestamp, idempotency_key
```

### الحقول الخاصة بكل جدول (بالإضافة إلى الحقول المشتركة أعلاه)

| # | الجدول | الحقول الخاصة |
|---|---|---|
| 1 | `rooms` | id, room_number, type, price, status, image_url, cleaning_status, last_cleaned_hotel_day, last_occupied_hotel_day, requires_maintenance |
| 2 | `bookings` | id, server_booking_id, room_number, guest_name, guest_phone, guest_id_type, guest_id_number, guest_id_issue_date, guest_id_issue_place, guest_nationality, guest_email, guest_address, checkin_date, checkout_date, actual_checkout, status, notes, discount, discount_type, discount_start_date, expected_nights, calculated_nights, total_nights_cached, stay_duration_iso, last_night_epoch, is_overdue, needs_checkout_review, total_due_cached, total_paid_cached, remaining_balance_cached, is_fully_paid, hotel_day_checkin, hotel_day_checkout, financial_frozen_at, financial_hash |
| 3 | `booking_nights` | id, booking_local_id, hotel_day_key, night_start, night_end, nightly_rate, sequence, is_processed_by_auto_fix, base_rate, adjustment, final_rate, applied_adjustment_uuid, applied_adjustments_json, booking_uuid_cache, server_booking_id |
| 4 | `booking_notes` | id, booking_id, note_text, alert_type, alert_until, is_active |
| 5 | `booking_price_adjustments` | id, booking_local_uuid, booking_local_id, room_number, amount, effective_hotel_day, end_hotel_day, is_active, reason, applied_by, cancelled_at, cancelled_by, booking_uuid, adjustment_type, adjustment_mode, applied_at |
| 6 | `payments` | id, server_payment_id, booking_local_id, server_booking_id, room_number, amount, payment_date, notes, payment_method, revenue_type, cash_transaction_local_id, cash_transaction_server_id, reference_number, hotel_day_key, is_pending_balance, linked_debt_uuid, booking_uuid_cache, discount_amount, discount_start_date, is_voided, voided_at, voided_by, void_reason, is_immutable, received_by_user_id, received_by_name, received_session_uuid, received_by_cloud_id |
| 7 | `payment_voids` | id, original_payment_uuid, original_payment_id, booking_uuid, voided_amount, void_reason, voided_by, voided_at, voided_at_iso, hotel_day_key, reversal_payment_uuid, approved_by, note, original_amount, payment_uuid |
| 8 | `price_adjustments` | id, target_type, target_uuid, adjustment_type, previous_value, new_value, reason, effective_date, applied_by, hotel_day_key, adjustment_mode, booking_uuid, applied_at, is_reversed, reversed_at, reversed_by |
| 9 | `expenses` | id, expense_type, related_id, description, amount, date, cash_transaction_id, hotel_day_key, category_uuid, cash_flow_uuid, is_auto_generated, employee_uuid, withdrawal_uuid, expense_kind, employee_link_cleared |
| 10 | `debts` | id, booking_local_id, guest_name, checkin_date, checkout_date, date_recorded, debt_reason, total_amount, paid_amount, remaining_amount, payment_date, is_settled, pledge, pledge_type, note, debt_uuid, hotel_day_opened, hotel_day_closed, is_from_auto_fix, settlement_confirmed, guest_phone, description, status, due_date, booking_uuid_cache, debtor_name, amount, date |
| 11 | `employees` | id, name, basic_salary, position, phone, hire_date, status, termination_date, termination_reason, employee_i_d (من `employeeID` — تأكيد من `local_db.g.dart`) |
| 12 | `guest_infos` | id, room_number, guest_name, nationality, id_number, id_type, issue_date, issue_place, governorate, notes, guest_phone |
| 13 | `cash_transactions` | id, register_id, transaction_type, amount, reference_type, reference_id, description, transaction_time, created_by |
| 14 | `shift_notes` | id, title, content, priority, shift_type, is_read, expires_at, created_by |
| 15 | `salary_cycles` | id, employee_id, employee_uuid, cycle_key, hotel_day_start, hotel_day_end, expected_amount, actual_paid, remaining_amount, status |
| 16 | `salary_payments` | id, cycle_id, employee_uuid, cycle_uuid, amount, hotel_day_key, payment_date_iso, method, is_auto_generated |
| 17 | `salary_withdrawals` | id, employee_id, employee_uuid, amount, withdraw_date, reason, hotel_day_key, withdrawal_type, description, expense_id, expense_uuid, recorder_name |
| 18 | `salary_carry_over_logs` | id, employee_id, employee_uuid, amount, previous_cycle_start, previous_cycle_end, new_cycle_start, new_cycle_end, reason, carried_at, from_cycle_id, to_cycle_id, carry_date, performed_by, hotel_day_key |
| 19 | `audit_logs` | id, operation_type, entity_type, entity_uuid, entity_id, previous_state, new_state, changed_fields, performed_by, ip_address, hotel_day_key, timestamp, timestamp_iso, is_financial, amount_impact |
| 20 | `inventory_items` | id, name, unit, category, quantity, minimum_quantity, is_active |
| 21 | `inventory_transactions` | id, item_local_uuid, item_id, movement_type, quantity, balance_after, note, user_id, user_name |

### تحديث (2026-10-07) — أعمدة عقد العلاقات المحمولة m68/m69

أُضيفت وتحقّقت أسماؤها الفعلية من `local_db.g.dart` (الأسطر 8731/8742/8752 وما حولها):

| العمود المحلي (snake_case — هو نفسه على D1) | الجدول | ملاحظة |
|---|---|---|
| `withdrawal_uuid` | `expenses` | m68 — رابط المرآة الدائم سحبة↔مصروف |
| `expense_kind` | `expenses` | m69 — تصنيف محمول (قيم مسموحة: normal, salary_advance, salary_installment, salary_withdrawal, salary_deduction, unclassified) |
| `employee_link_cleared` | `expenses` | m69 — INTEGER NOT NULL DEFAULT 0 على D1 (يُرفع 0/1) |
| `cycle_uuid` | `salary_payments` | m69 — كان عموداً خاماً من G-1 وصار معلناً رسمياً |
| `expense_uuid` | `salary_withdrawals` | m68 — يقابل `expense_id` الرقمي غير المحمول |

هذه الأعمدة تصل إلى D1 تلقائياً (SELECT * بلا whitelist)، ومُثبَّتة باختبارات قفل:
`test/unit/cloudflare_d1_upload_fields_test.dart` — مجموعة «حقول عقد m69 في رفع Cloudflare D1»
(3 اختبارات: وجود الأعمدة محلياً، وصولها بقيمها في `INSERT OR REPLACE` الفعلي، وسبق
`ALTER TABLE ADD COLUMN` لأول `INSERT` على قاعدة D1 قديمة).



- **لا توجد حقول مفقودة** في مسار Cloudflare D1: بما أن آلية القراءة
  `SELECT *` بلا أي `whitelist`، فكل عمود موجود فعليًا في الجدول المحلي
  (المشترك عبر `SyncFields` أو الخاص بالجدول) يُقرأ ويُرفع تلقائيًا — لا
  يوجد كود يعدّد أسماء الأعمدة يدويًا هنا فيُحتمل نسيان حقل.
- **مفتاح "إظهار كل الجداول المحلية":** الشاشة تحتوي مفتاحًا إضافيًا (خارج
  الافتراضي) لإظهار كل الجداول المحلية بدل الـ21 المذكورة أعلاه فقط، وتشمل
  جداولاً بلا `SyncFields` (بلا `vector_clock`) مثل `outbox`, `sync_state`,
  `sync_queue`, `sync_log`, `sync_conflicts`, `ancestor_cache`,
  `sync_remote_meta`, `auto_fix_runs`, `integrity_violations`,
  `app_sessions`، بالإضافة إلى `hotel_day_ledger` الذي *يملك* `SyncFields`
  لكنه ليس ضمن قائمة Appwrite الافتراضية. هذه الجداول ليست "جداول مزامنة"
  بالمعنى المطلوب في السؤال الأصلي ولا تُختار افتراضيًا.
- **تمييز مهم عن مسار Appwrite:** تبويب "Appwrite" في نفس الشاشة (خدمة
  `comprehensive_appwrite_backup_service.dart`) يبني البيانات يدويًا حقلاً
  حقلاً عبر دوال `*_ToMap`، وهناك تم توثيق حقول مفقودة تاريخيًا (انظر
  `docs/UPLOAD_FULL_BACKUP_DEEP_AUDIT_REPORT.md`). هذا **لا ينطبق** على مسار
  Cloudflare D1 موضوع هذا التقرير؛ فهو سليم بنيويًا لاعتماده على `SELECT *`
  المباشر.

## دليل تجريبي (اختبار انحدار قائم مسبقًا)

يثبت `mobile/test/unit/cloudflare_d1_upload_fields_test.dart` هذا السلوك
تجريبيًا: يُدرج صفًا بقيمة `vectorClock: '{"dev-b":9}'`، يُشغّل `uploadData`
الفعلي مع `MockClient` يلتقط جسم الطلب، ثم يتحقق أن عبارة `INSERT OR REPLACE`
المُرسلة فعليًا تحتوي `vector_clock` ضمن قائمة الأعمدة والقيمة الحرفية.

**إضافة (2026-10-07):** نفس الملف يحمل مجموعة «حقول عقد m69 في رفع Cloudflare D1»
(3 اختبارات) تثبّت أعمدة m68/m69 أعلاه من طرف الرفع الفعلي، ومجموع الملف 38 اختباراً
نجحت في التشغيل 37668104390 (`rc=0`).

## تحصين مسار D1 (2026-10-04) — فجوات تدقيق المسار الأربع

**الفرع:** `fix/phase0-salary-link-hardening`
**نوع الفحص:** تشخيص مصدري مباشر ثم إصلاح — بلا تخمين.

### F1 — صفوف blacklist داخل رفع shift_notes إلى D1 (مؤكدة — أُصلحت)

الخلل المثبت: مزامنة Appwrite تستبعد `createdBy='blacklist'` من رفع
`shift_notes` وترسلها إلى مجموعة `blacklist` المستقلة (فلتر 2026-08-06 في
`_getShiftNoteByLocalUuid`)، بينما كان مسار D1 يرفع كل صفوف `shift_notes`
حرفيًا بـ `SELECT *` — وD1 بلا جدول `blacklist`. النتيجة: صفوف القائمة
السوداء (ضيوف مرفوضون) تظهر في مرآة D1 داخل `shift_notes` — تفرّع مسار
وتسريب بيانات.

**وأُثبت أثناء التدقيق خلل جانبي أخطر:** `_processBlacklistEntry` كان يعيد
استخدام نفس المُلقٍ المُفلتر بـ `'user'`، فيعيد NULL **دائمًا** لمدخلات
blacklist في الـ outbox، فيدفع `_handleDeleteOp` tombstone يحذف مستند
blacklist من السحابة عند كل رفع.

الإصلاح:
1. فصل المُلقيات: `_getBlacklistEntryByLocalUuid` بفلتر `'blacklist'` لمسار
   الرفع السحابي (يعيد تدفق blacklist إلى عمله الصحيح)، و`'user'` يبقى لمسار
   shift_notes.
2. استبعاد الصفوف من رفع D1: الثابت `kShiftNotesD1ExclusionWhere`
   (`created_by IS NULL OR created_by <> 'blacklist'`) يُطبق على العدّ
   (COUNT) وعلى القراءة (readChunk) في وضعَي الرفع معًا — الجدول فيزيائيًا
   واحد. الاستبعاد عرضي فقط: البيانات تبقى محلية، وAppwrite يبقى ناقلها
   الرسمي إلى مجموعة `blacklist`.

### F2 — app_users متزامنة بلا جدول محلي (مؤكدة — أُغلقت)

`app_users` مجموعة متزامنة (رفع عبر `_processAppUserEntry`، سحب عبر
`loadCloudAccounts`) لكن الحسابات تُخزن في SharedPreferences
(`custom_accounts` + `user_permissions`) لا في Drift — لذلك لم يصلها مسار
D1 أبدًا وفقُدت مرآة D1 دليل المستخدمين كاملًا.

الإصلاح: جدول `app_users` **تركيبي** في مسار D1
(`cloudflare_d1_app_users_source.dart`):
- المصدر: الحسابات الثابتة (كودية) + الحسابات المحلية + الحسابات السحابية
  best-effort بمهلة 10 ثوانٍ (عند انقطاع الشبكة تُرفع المحلية فقط بصمت).
- الشكل: شكل مستند Appwrite (doc_id/username/full_name/user_type/role/
  permissions/active/credentials_version/...).
- الأمان: `password_hash` يحمل تجزئة PBKDF2 فقط (نفس مستوى السرية عند
  Appwrite)؛ الحسابات الكودية (admin) تُصدَّر بلا تجزئة لأن اعتمادها
  يُستعاد من الكود. لا نص صريح لكلمة مرور في أي مسار.
- يظهر افتراضيًا ضمن "جداول مزامنة Appwrite" عبر `kD1SyntheticTables`.

### F3 — حقول Phase 0 تصل D1 بلا إثبات (جزئية — أُثبتت)

بنية المسار (`SELECT *` بلا قائمة بيضاء) تضمن وصول الأعمدة تلقائيًا، لكن
لم يكن هناك اختبار يثبّت `employee_uuid` بالاسم عبر `uploadData` الحقيقي.
أُضيف اختبار يدرج دورة/مسحوبة/مصروف رواتب بقيم مميزة ويثبت وصول
`employee_uuid` وقيمته الحرفية، وأن `related_id` يصل `NULL` صراحةً (P0.4)
بمطابقة العبارة كاملة حرفيًا.

### F4 — «employeeUuid مفقود من salary_cycles على السحابة» (مرفوضة بتحفظ)

الفحص المباشر أثبت أن `_filterPayload('salary_cycles')` يحتفظ بـ
`employeeUuid` و`employeeLocalUuid`، و`collectionSchema` و
`unified_appwrite_setup.js` يعرّفانهما (2026-09-19) — أي أن رفع Phase 0
سليم. **الخلل الحقيقي:** مواصفات `appwrite_schema_verifier.dart` (زر
"التحقق من Schema" + مولّد سكربتات إنشاء المجموعات الناقصة) كانت ناقصة
`employeeUuid/employeeLocalUuid` في `salary_cycles` و`salary_carry_over_logs`،
و`cycleLocalUuid/employeeUuid/employeeLocalUuid` في `salary_payments` —
أي أن التحقق لا يكشف غيابها عن السحابة، وسكربت إنشاء جهاز جديد يُنشئ
المجموعة بدونها فيُرفض رفع Phase 0 بـ 400. أُحاذيت المواصفات مع
`collectionSchema` دون مساس بأنواع المبالغ التاريخية.

### الاختبارات

`test/unit/cloudflare_d1_upload_fields_test.dart`: 10/10 (5 قديمة + 5 جديدة
تغطي F1/F2/F3 أعلاه). النتائج الكاملة وقت الإصلاح: analyze نظيف، ومجموعات
services/unit/integration/auth/utils/screens/widget/performance خضراء
بالكامل. ملاحظة: `test/delete_404_handling_test.dart` (جذر test/) فاشل
مسبقًا على الفرع قبل هذه التغييرات — خارج نطاق هذا الإصلاح ويُتبع منفصلًا.
