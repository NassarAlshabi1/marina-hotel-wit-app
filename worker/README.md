# Marina Hotel — Cloudflare Worker API + D1 Sync

**التقنيات:** Cloudflare Worker (TypeScript) + D1 Database + Durable Objects.
**عقد البيانات:** snake_case مرآة 1:1 لجداول Drift المحلية (خطة D4).

## البنية الفعلية

```
worker/
  src/
    index.ts               ← Router + CORS + rate limit (D1) + Auth middleware
    auth.ts                ← JWT HMAC-SHA256 + PBKDF2 (25k، versioned) + أدوار
    sync.ts                ← pull / push / migrate / log / conflicts + SQL whitelist
    database.ts            ← كيانات المزامنة + sync_clock/epoch + LWW/VC + PRAGMA whitelist
    sync-lock.ts           ← SyncLockDO: أقفال 30s + WebSocket hub + cursors
  schema.sql               ← مخطط D1 الكامل (يتضمن sync_meta لجيل المزامنة)
  migrations/
    0002_inventory_blacklist.sql ← ترقيع الفجوة: inventory×2 + blacklist
    0010_sync_meta.sql       ← جيل البيانات لإبطال مؤشرات السحب بعد الاستعادة
    0011_salary_parent_uuids.sql ← مفاتيح UUID لآباء مدفوعات الرواتب والترحيل
    0012_expense_employee_link_clear_flag.sql ← تثبيت فك ربط الموظف الصريح للمزامنة
  test/                    ← vitest + @cloudflare/vitest-pool-workers (اختبارات Worker/D1)
  wrangler.toml            ← إعدادات النشر (D1 + DO، بلا KV)
  vitest.config.ts
  tsconfig.json / tsconfig.test.json
```

> ملاحظة: **لا يوجد R2 ولا storage.ts ولا مجلد flutter/ داخل هذا المستودع** —
> عميل المزامنة هو تطبيق Android/Kotlin داخل `mobile/android/` في نفس المستودع.

## الإعداد

### 1. قاعدة بيانات D1

```bash
# إنشاء قاعدة جديدة (مرة واحدة)
wrangler d1 create marina-hotel-db
# ← ضع database_id الناتج في wrangler.toml

# قاعدة جديدة: schema.sql يتضمن الحالة الحالية كاملة (بما فيها 0014)
npm run db:init

# قاعدة قائمة معروفة الحالة: حدّد الترحيل الناقص من سجل موثوق أولاً.
# لا تشغّل سلسلة عامة ولا تعِد تشغيل ملف سبق تطبيقه.
# إذا كانت القاعدة مطبّقاً عليها 0010 و0011 غير مطبّق:
npm run db:migrate:salary-parent-uuids    # 0011 salary parent UUID links
# بعد التحقق من 0011، أضف علامة فك الربط:
npm run db:migrate:expense-link-clear-flag # 0012 explicit expense-link unlink marker
```

قاعدة جديدة: `schema.sql` يتضمن الأعمدة والفهارس الحالية كاملة، لذلك استخدم
`db:init` وحده ولا تشغّل 0011/0012 بعدها. قاعدة قائمة معروفة ومطبّق عليها 0011
تحتاج 0012 فقط. إذا كان سجل الترحيلات أو شكل المخطط غير مؤكد، فتوقّف وافحصه
يدوياً قبل التنفيذ؛ لا تستخدم أوامر جماعية لتخمين الحالة. لا تشغّل 0006/0007 أو
أي backfill تاريخي ضمن النشر المعتاد: يتطلب ذلك مصدر حقيقة موثوقاً ومراجعة
وموافقة منفصلة، ووجود ملف SQL لا يثبت صحة بياناته الحية. احتفظ بنسخة احتياطية
وتحقق من الاستعادة قبل أي ترحيل معتمد. تدوير epoch إجراء صيانة بعد استعادة/إعادة
استيراد خادمية، وليس في كل نشر؛ endpoint محمي بدور admin (راجع جدول نقاط النهاية أدناه).

### 2. سر JWT

```bash
wrangler secret put JWT_SECRET
# أدخل سلسلة عشوائية قوية — لا يُخزن في wrangler.toml أبداً
```

### 3. النشر والتحقق

```bash
npm install
npx wrangler deploy --dry-run --outdir dist   # تحقق محلي
npm run deploy                                 # نشر فعلي
curl https://<worker>.workers.dev/health       # → {"status":"ok"}
```

### 4. أول مستخدم (bootstrap)

```bash
curl -X POST https://<worker>.workers.dev/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"...","role":"admin"}'
```
بعد وجود مستخدم نشط واحد، التسجيل المفتوح يُقفل تماماً؛ إنشاء مستخدمين
جدد يتطلب توكن admin صالح.

## الاختبارات

```bash
npm install
npm test          # اختبارات العقود والتكامل عبر vitest-pool-workers وD1/DO محلياً
npm run typecheck # tsc للـ src وللـ tests
```

## نقاط النهاية

| Method | Path | Auth | الوصف |
|--------|------|------|-------|
| GET | `/health`, `/` | — | فحص حيوية |
| GET | `/api/ping` | — | قياس سرعة الشبكة (~1KB) |
| POST | `/api/auth/register` | — (أول مستخدم فقط) ثم admin | bootstrap + إنشاء مستخدمين |
| POST | `/api/auth/login` | — | دخول → JWT (24h) |
| GET | `/api/sync/pull?cursor=0&limit=200&exclude_device=X` | ✅ | سحب دلتا + epoch + مرشح echo |
| POST | `/api/sync/push` (gzip اختياري) | ✅ | دفع outbox ≤100 عملية |
| POST | `/api/admin/sync/rotate-epoch` | ✅ admin | إبطال مؤشرات كل الأجهزة بعد استعادة/إعادة استيراد |
| POST | `/api/sync/migrate` (gzip) | ✅ | ترحيل SQL دفعي — INSERT whitelist ذرّية |
| GET | `/api/sync/log?limit=&offset=` | ✅ | سجل تدقيق المزامنة |
| GET | `/api/sync/conflicts?limit=` | ✅ | سجل التعارضات |
| POST | `/api/sync/lock` / `unlock`, GET `/api/sync/locks` | ✅ | أقفال كيانات عبر SyncLockDO |
| GET | `/api/realtime` (Upgrade: websocket) | ✅ | WebSocket realtime hub |
| POST | `/api/devices/register`, GET `/api/devices/tokens` | ✅ | أجهزة FCM |
| GET | `/api/stats` | ✅ | عدّادات كل الجداول |

## عقد المزامنة

- **الهوية:** `local_uuid` هو مفتاح العميل (UNIQUE)؛ `id` AUTOINCREMENT
  داخلي يُولده الخادم ولا يُشير إليه العملاء.
- **الحقول:** snake_case مطابق لأعمدة Drift؛ الحقول غير المعروفة تُرشّح
  عبر `PRAGMA table_info` قبل الكتابة (حماية SQLi على مستوى المعرّفات).
- **الدفع:** كل عملية تحمل `idempotencyKey` — التكرار يُعاد كـ `skipped`
  بنفس الاستجابة المخزنة في `idempotency_log`.
- **السحب:** مؤشر صحيح `updated_at` مُخصص من `sync_clock` أحادي
  (غير قابل للتكرار عالمياً) — مؤشر الخادم هو المرجع دائماً؛ الصفحة لا
  تُقطع داخل مجموعة طوابع متساوية.
- **الجيل (`epoch`):** كل رد pull يحمل جيل D1. عند استعادة/استيراد يعيد
  المسؤول تدويره، فتصفّر التطبيقات مؤشرها وتسحب من البداية. التوافق مع
  Worker أقدم محفوظ: غياب epoch لا يوقف المزامنة.
- **`exclude_device`:** يستبعد سجلات الجهاز نفسه من الدلتا — السحب الكامل
  لا يمرره كي يتعلم الجهاز ظلال `server_id` لصفوفه؛ أعمدة الخادم لا تُستبعد.
- **الحد الزمني للسحب:** `limit` يُقص فعلياً إلى [1, 500]؛ سقف الدفع 100.

## حل التعارض

- **التصنيف:** مقارنة ساعات المتجهات — equal / local_newer / remote_newer /
  concurrent.
- **LWW:** مرجع القرار `updatedAt` للعملية؛ يُقصّ المستقبل إلى سماحية 90
  ثانية، وداخل نافذة انحراف الساعة يفصل `version` الأعلى. تعديل أقدم من
  النافذة يخسر حتى لو ادّعى العميل نسخة أعلى.
- **التعارض المتزامن:** يُحفظ في `sync_conflicts` مع كامل الحمولتين، وتُدمج
  ساعات المتجهات.
- **الحذف:** tombstone ناعم (`deleted_at`) ينتشر عبر مؤشر الدلتا، والحذف
  يفوز دائماً على تعديل يصل لاحقاً؛ الرفض يعود `success: true, status: deleted`
  ويُحفظ idempotently كي لا يعيد العميل دفع التعديل الخاسر.

## الأمان

- JWT HMAC-SHA256 ذاتي التوقيع + مقارنة زمن ثابت للتواقيع وكلمات المرور.
- PBKDF2-SHA256 إصداري (25k للمفاتيح الجديدة، دعم legacy 10k للقراءة).
- Rate limiting على **D1** (نافذة ثابتة، UPSERT ذرّي + `RETURNING`) —
  لا KV (سقف الكتابة اليومي المجاني 1000/يوم وانفجار الاتساق النهائي)؛
  دلو login منفصل أصمد (20/نافذة) + `Retry-After` على 429؛ fail-open
  عند فشل الد1 للحفاظ على التوفر.
- `/api/sync/migrate`: كل عبارة تُفحص قبل التنفيذ — INSERT فقط إلى جداول
  كيانات مسماة، لا SELECT/DELETE/WITH/PRAGMA بعد strip النصوص؛ التنفيذ
  بدفعات `db.batch()` ذرّية (50 عبارة/دفعة) مع fail-fast وإعادة محاولة
  آمنة (كل العبارات INSERT OR IGNORE/REPLACE).
- سقف مزدوج للحجم: مضغوط 10MB + مفكوك 10MB (دفاع zip-bomb).

## إصلاح سلامة البيانات: 0013 و0014 / Room 72

راجع [خطة النشر والاختبارات](../docs/financial-integrity-fixes.md) قبل النشر.
قاعدة قائمة على 0012 تحتاج 0013 (رابط UUID المصروف) ثم 0014 (زمن حسم التعارض
المستقل عن المؤشر)، بعد النسخ الاحتياطي واختبار staging والموافقة. يجب تطبيق
0014 قبل نشر Worker الجديد. قاعدة جديدة تستخدم `schema.sql` فقط.

لم تعد مطابقة المرآة في Android تعتمد `exp_N` أو تشابه المبلغ واليوم؛ السجلات
القديمة غير المؤكدة تبقى للمراجعة ولا تُصلح تلقائياً.

## Append-only expense corrections (0015)

See [financial reversals](../docs/financial-reversals.md) for the `reverse` sync command, admin period-closure API, required maintenance rollout and scope limitations. Existing expenses and salary withdrawals cannot be edited/deleted after this migration. General SQL import no longer accepts those two tables. No production migration is automatic.
