# مطابقة ترحيلات Cloudflare D1 مع فرع `feat/cloudflare-sync-execution`

**تاريخ التدقيق:** 2026-10-06
**المقارنة:** `arena/be8302d7-marina-hotel-wit-app` (HEAD التنفيذي) ↔
`origin/feat/cloudflare-sync-execution` (`ac283c6c`).

الغرض: التحقق أن ما يحتاجه **سحب التغييرات** (مؤشر الدلتا، epoch، مسح
الحذفيات، تطبيع الطوابع) متطابق بين الفرعين، وأن أي فرق في الترحيلات
مقصود ومُعلَن لا مفقود.

---

## 1) الخلاصة

- **لا ترحيل جديد مطلوباً لمسار السحب.** كل ما يقرأه/يكتبه محرك السحب
  موجود في الفرعين: `sync_meta` (epoch)، `tombstones_only` (فلترة صفوف
  الحذف)، `include_remaining`، `normalize_timestamps`، `server_time`.
- **الترحيلات المشتركة بالأسماء (0002–0007 و0010) متطابقة فعلياً**:
  لا فرق SQL واحد — الفروق كلها تعليقات (`Apply with:`) وصياغة/تنسيق في
  0010. تحقّق ذلك مجدداً **بيان-ببيان** (§5): 78 عبارة SQL في سبعة ملفات،
  بلا عبارة واحدة مختلفة.
- **ما بعد ذلك متباعد القصد**: كل فرع أضاف ترحيلات ميزاته. لا يجوز دمج
  الرقم `0011` بينهما لأنه يعني شيئين مختلفين.

## 2) جدول الترحيلات

| الرقم | هذا الفرع | فرع Flutter | الفرق الفعلي |
| --- | --- | --- | --- |
| 0002 | `0002_inventory_blacklist.sql` | نفسه | **بايت-ببايت متطابق** (نفس sha1) |
| 0003 | `0003_app_users.sql` | نفسه | تعليق `Apply with` فقط |
| 0004 | `0004_devices_sync.sql` | نفسه | تعليق `Apply with` فقط |
| 0005 | `0005_schema_parity.sql` | نفسه | تعليق `Apply with` فقط |
| 0006 | `0006_salary_withdrawals_employee_uuid.sql` | نفسه | تعليق `Apply once with` فقط |
| 0007 | `0007_salary_tables_employee_uuid.sql` | نفسه | تعليق `Apply once with` فقط |
| 0008 | — | `0008_idempotency_log_cleanup.sql` | فهرس TTL لسجل idempotency (خاص بفرع Flutter) |
| 0009 | — | `0009_finance_snapshots.sql` | جداول المالية الأسبوعية (خاص بفرع Flutter) |
| 0010 | `0010_sync_meta.sql` | نفسه | **نفس SQL**: `CREATE TABLE sync_meta` + زرع `epoch`؛ الفرق تعليقات/تنسيق `INSERT` فقط |
| 0011 | `0011_salary_parent_uuids.sql` | `0011_portable_financial_relationships.sql` | **تعارض رقمي مقصود** — محتويان مختلفان |
| 0012 | `0012_expense_employee_link_clear_flag.sql` | — | خاص بهذا الفرع |
| 0013 | `0013_salary_withdrawal_expense_uuid.sql` | — | خاص بهذا الفرع |
| 0014 | `0014_sync_write_times.sql` | — | خاص بهذا الفرع |
| 0015 | `0015_expense_kind.sql` | — | خاص بهذا الفرع |

**عقد السحب المشترك (تحقُّق مباشر من `worker/src/sync.ts` في الفرعين):**

| العنصر | هذا الفرع | فرع Flutter | الحكم |
| --- | --- | --- | --- |
| `exclude_device` | l.216 | l.331 | متطابق |
| `tombstones_only` | l.220-221 (`=== '1'`) | l.335-336 (`=== '1'`) | متطابق |
| `include_remaining` | l.225 (`['1','true']`) | l.340 (`=== '1'`) | ⚠️ هذا الفرع أكثر تسامحاً |
| `normalize_timestamps` | l.231 (`['1','true']`) | l.354 (`=== '1'`) | ⚠️ هذا الفرع أكثر تسامحاً |
| `epoch` | l.251 | l.375 | متطابق |
| `has_more` / `remaining` / `server_time` | l.257-262 | l.381-385 | متطابق |
| `sync_meta` قراءة/زرع كسول | `database.ts` l.625-653 | `database.ts` l.608-633 | متطابق سلوكياً |

النتيجة العملية: **العميل يجب أن يرسل `1` نصاً** ليُفهم في الفرعين —
وهذا ما فُرض في `CloudflareWorkerApi` (انظر §4).

## 3) فرق `schema.sql` (مرجعي)

`schema.sql` في كل فرع = مجموع ترحيلاته، لذا يختلف بطبيعة الحال:

- هذا الفرع: يضم كتلة `sync_meta` (سطور 39-48) وعمودي `expense_kind`
  و`employee_link_cleared` و`salary_withdrawals.expense_uuid` و`sync_write_times`
  المطابقة لترحيلاته 0012-0015.
- فرع Flutter: يضم `idx_idempotency_processed_at` (0008)، جداول
  `finance_*` (0009)، و`withdrawal_uuid` + فهارسه (0011).
- `worker/postgres/schema.sql` يختلف بنفس المنطق (18 سطراً: أعمدة/فهارس
  المالية في فرع Flutter)، وهو غير مستخدم في مسار D1.

**لا `ALTER` متعارض على أي جدول مشترك** بين الفرعين: الاختلافات إضافية
بحتة (أعمدة/فهارس/جداول جديدة).

## 4) ما تغيّر في هذه الجولة

1. **`worker/package.json`**: كان ترحيل `0015_expense_kind.sql` **بلا
   سكربت تشغيل** — تشغيل قائمة `db:migrate:*` على قاعدة قائمة كان يُبقي
   D1 بلا عمود `expense_kind`، فيرفض الـ Worker أي دفع يحمل هذا الحقل
   (`expense-kind.ts` + `CHECK` في المخطط). أُضيف:
   `npm run db:migrate:expense-kind`.
2. **أعلام الاستعلام نصية `"1"`**: `CloudflareWorkerApi.pull` كان يعرّف
   `include_remaining`/`normalize_timestamps`/`tombstones_only` كـ
   `Boolean`، وRetrofit يُنتج `"true"` — وهو ما يفهمه هذا الفرع في
   الأولين فقط، **ولا يفهمه في `tombstones_only` إطلاقاً** (لأنه `=== '1'`
   حرفياً في الفرعين)، أي أن مسح الحذفيات لم يكن يُفعَّل. صارت
   `String?` تُرسل `"1"` كما تفعل Dart بالضبط
   (`cloudflare_sync_manager.dart` l.2633/2634/3679).

## 5) إعادة تحقق آلي (2026-10-06) — بيان-ببيان لا بايت-ببايت

بعد أن سجّل التدقيق الأول «متطابقة فعلياً» بلغة وصفية، أُعيد التحقق بطريقة
قابلة لإعادة الإنتاج: تُجرَّد التعليقات (`--`) وتُطوى المسافات وتُقسَّم
النصوص إلى عبارات SQL (على `;`) ثم تُقارَن قوائم العبارات حرفياً:

```python
def norm(text):
    text = re.sub(r"--[^\n]*", "", text)
    text = re.sub(r"\s+", " ", text)
    return [s.strip() for s in text.split(";") if s.strip()]
```

النتيجة (HEAD التنفيذي ↔ `origin/feat/cloudflare-sync-execution` = `ac283c6c`):

| الملف | عبارات SQL | الحكم |
| --- | --- | --- |
| `0002_inventory_blacklist.sql` | 14 | متطابقة (والملف نفسه **بايت-ببايت**: `sha256 272503c6e39f…`) |
| `0003_app_users.sql` | 4 | متطابقة |
| `0004_devices_sync.sql` | 7 | متطابقة |
| `0005_schema_parity.sql` | 33 | متطابقة |
| `0006_salary_withdrawals_employee_uuid.sql` | 3 | متطابقة |
| `0007_salary_tables_employee_uuid.sql` | 15 | متطابقة |
| `0010_sync_meta.sql` | 2 | متطابقة (`CREATE TABLE sync_meta` كما هو حرفياً + زرع `epoch`) |

الفرق في الملفات الستة غير 0002 محصور في التعليقات (تعليق `Apply with`
الإنجليزي عندنا مقابل شرح عربي عندهم) وتقسيم سطر `INSERT` في 0010 — **لا
عبارة SQL واحدة مختلفة**. ويبقى التباعد الحقيقي كما هو مُوثَّق: ترحيلات
ميزات خاصة بكل فرع (لنا 0011–0015، ولهم `0008_idempotency_log_cleanup` و
`0009_finance_snapshots` و`0011_portable_financial_relationships`)، مع
تعارض رقمي مقصود على `0011`.

## 6) حدود هذا التدقيق

- لا تنفيذ لـ `wrangler d1` هنا (لا شبكة ولا حساب Cloudflare في بيئة
  التنفيذ): كل ما سبق مقارنة نصية/بنيوية على المستودع.
- لا يُدّعى أن قواعد D1 الحيّة عند المستخدم بحالة معيّنة؛ للتحقق منها:
  `npx wrangler d1 execute marina-hotel-db --remote --command "SELECT name FROM sqlite_master WHERE type='table'"`.
- قرار «فرع واحد للترحيلات» قرار نشر (Ops) وليس قرار كود: دمج الفرعين
  يتطلب توحيد ترقيم `0011` قبل أي `db:migrate` مشترك.
