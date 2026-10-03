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

# قاعدة جديدة: schema.sql يتضمن الحالة الحالية كاملة (بما فيها 0010)
npm run db:init

# قاعدة قائمة: نفّذ فقط الترحيلات غير المطبّقة، بالترتيب الرقمي، ومرة واحدة:
npm run db:migrate                       # 0002 inventory/blacklist
npm run db:migrate:app-users             # 0003 app_users
npm run db:migrate:devices               # 0004 devices
npm run db:migrate:parity                # 0005 parity
npm run db:migrate:salary-withdrawals    # 0006 employee_uuid withdrawals
npm run db:migrate:salary-employee-uuid  # 0007 employee_uuid salary tables
npm run db:migrate:sync-meta             # 0010 epoch
```

لا تُعِد تشغيل ترحيل سبق تطبيقه؛ خصوصاً 0005–0007 التي تحتوي ALTER TABLE.
قاعدة حالية مطبّق عليها 0002–0007 تحتاج 0010 فقط. تدوير epoch إجراء صيانة
بعد استعادة/إعادة استيراد خادمية، وليس في كل نشر؛ endpoint محمي بدور admin
(راجع جدول نقاط النهاية أدناه).

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
