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
    database.ts            ← 22 كياناً + sync_clock أحادي + LWW/VC + PRAGMA whitelist
    sync-lock.ts           ← SyncLockDO: أقفال 30s + WebSocket hub + cursors
  schema.sql               ← مخطط D1 الكامل (30 جدولاً: 22 كياناً + 8 بنية تحتية)
  migrations/
    0002_inventory_blacklist.sql ← ترقيع الفجوة: inventory×2 + blacklist
  test/                    ← vitest + @cloudflare/vitest-pool-workers (82 اختباراً)
  wrangler.toml            ← إعدادات النشر (D1 + DO، بلا KV)
  vitest.config.ts
  tsconfig.json / tsconfig.test.json
```

> ملاحظة: **لا يوجد R2 ولا storage.ts ولا مجلد flutter/ داخل هذا المستودع** —
> عميل المزامنة هو `mobile/lib/services/cloudflare_*` في نفس المستودع.

## الإعداد

### 1. قاعدة بيانات D1

```bash
# إنشاء قاعدة جديدة (مرة واحدة)
wrangler d1 create marina-hotel-db
# ← ضع database_id الناتج في wrangler.toml

# قاعدة جديدة: طبّق المخطط الكامل ثم الترقيع
npm run db:init
npm run db:migrate

# قاعدة قائمة أُنشئت قبل ترقيع inventory/blacklist: الترقيع فقط
npm run db:migrate
```

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
npm test          # 82 اختباراً عبر vitest-pool-workers + miniflare D1/DO محلي
npm run typecheck # tsc للـ src وللـ tests
```

## نقاط النهاية

| Method | Path | Auth | الوصف |
|--------|------|------|-------|
| GET | `/health`, `/` | — | فحص حيوية |
| GET | `/api/ping` | — | قياس سرعة الشبكة (~1KB) |
| POST | `/api/auth/register` | — (أول مستخدم فقط) ثم admin | bootstrap + إنشاء مستخدمين |
| POST | `/api/auth/login` | — | دخول → JWT (24h) |
| GET | `/api/sync/pull?cursor=0&limit=200&exclude_device=X` | ✅ | سحب دلتا + مرشح echo |
| POST | `/api/sync/push` (gzip اختياري) | ✅ | دفع outbox ≤100 عملية |
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
  (غير قابل للتكرار عالمياً) — مؤشر الخادم هو المرجع دائماً.
- **`exclude_device`:** يستبعد سجلات الجهاز نفسه من السحب (echo filter) —
  أعمدة الخادم (`device_id=''`) لا تُستبعد أبداً.
- **الحد الزمني للسحب:** `limit` يُقص فعلياً إلى [1, 200].

## حل التعارض

- **التصنيف:** مقارنة ساعات المتجهات — equal / local_newer / remote_newer /
  concurrent.
- **LWW:** الطابع الزمني للعملية (`updatedAt` من الـ outbox = clientTs) هو
  مرجع القرار؛ عند **تساوي** الزمن يفصل العداد `version` الأعلى — جهاز
  بساعة متأخرة يفوز برباط الزمن فقط إذا كان تعديله أحدث فعلاً.
- **التعارض المتزامن:** يُحفظ في `sync_conflicts` (الحل `last_write_wins`)
  مع كامل الحمولتين، وتُدمج ساعات المتجهات.
- **الحذف:** tombstone ناعم (`deleted_at`) بطابع `updated_at` فريد — يصل
  لكل الأجهزة مرة واحدة بالضبط عبر مؤشر الدلتا.

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
