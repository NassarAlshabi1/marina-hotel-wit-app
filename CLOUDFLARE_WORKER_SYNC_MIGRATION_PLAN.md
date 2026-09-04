# خطة نقل المزامنة إلى Cloudflare Worker
# Cloudflare Worker Sync Migration Plan
## (worker/ · TypeScript · D1 + KV Rate + Durable Objects)

> **الهدف:** استبدال طبقة Appwrite Sync بعامل Cloudflare Worker مكتوب بلغة **TypeScript**،
> يعتمد على **D1 Database** (كقاعدة بيانات SQLite الموحدة للخادم)، و**KV** للـ **rate-limiting**، و**Durable Objects**
> لإدارة اتصالات الوقت الحقيقية (WebSocket) والقفل المركزي لكل جهاز/جلسة مزامنة.
>
> **الملف الرئيسي:** `mobile/lib/services/appwrite_sync_manager.dart` (6445 سطر — أكبر ملف في المشروع) يُعيد تنفيذ
> منطق المزامنة الآن عبر Worker جديد.

---

## 1. ملخص تنفيذي / Executive Summary

- **الواجهة الحالية (Appwrite):** 21 مجموعة بيانات (collections) + جدول `outbox` + جدول `sync_remote_meta` + `sync_log`.
  المزامنة تعتمد على Delta/metadata-first pull، و push عبر الـ outbox، وـ Realtime عبر WebSocket.
- **الهدف الجديد (Cloudflare Worker):** نقل كل ذلك إلى `worker/` بـ TypeScript، حيث:
  - **D1** = مصدر الصحة للبيانات (SQLite على الطرفية) — بدلاً من Appwrite Collections.
  - **KV** = نظام تحميل الطلبات (rate limiting) + تخزين جلسات جهاز مؤقتة.
  - **Durable Objects** = إدارة WebSocket الدائمة للـ Realtime + قفل مزامنة مركزي لكل جهاز.
- **نفس بروتوكول المزامنة:** نفس مفهوم `SyncFields` (vectorClock, idempotencyKey, serverId, deletedAt...),
  نفس metadata-first delta pull، نفس "push echo immunization" — لكن المنطق يُنقل من Dart → TypeScript.

---

## 2. العمارة الحالية / Current Architecture (Appwrite)

### 2.1 الكيانات (21 مجموعة) — Entity Map
مصدر: `mobile/lib/services/appwrite_config.dart` (`_entityToCollection`).

| # | الكيان (Entity) | جدول SQLite المحلي | ملاحظات |
|---|---|---|---|
| 1 | `rooms` | rooms | الغرف |
| 2 | `bookings` | bookings | الحجوزات |
| 3 | `payments` | payments | المدفوعات |
| 4 | `expenses` | expenses | المصاريف |
| 5 | `employees` | employees | الموظفين |
| 6 | `debts` | debts | الديون |
| 7 | `booking_notes` | booking_notes | ملاحظات الحجز |
| 8 | `shift_notes` | shift_notes | ملاحظات الوردية |
| 9 | `cash_transactions` | cash_transactions | المعاملات النقدية |
| 10 | `booking_nights` | booking_nights | ليالي الحجز (**تهدف للحد الأقصى 1000 أولي**) |
| 11 | `salary_cycles` | salary_cycles | دورات الرواتب |
| 12 | `salary_payments` | salary_payments | دفعات الرواتب |
| 13 | `salary_withdrawals` | salary_withdrawals | سحب الرواتب |
| 14 | `salary_carry_over_logs` | salary_carry_over_logs | ترحيل الرواتب |
| 15 | `blacklist` | blacklist | القوائم الحظر |
| 16 | `price_adjustments` | price_adjustments | تعديلات الأسعار |
| 17 | `booking_price_adjustments` | booking_price_adjustments | تعديلات أسعار الحجز |
| 18 | `audit_logs` | audit_logs | سجلات التدقيق (**مستبعدة من Appwrite sync — `e1975be2`**) |
| 19 | `payment_voids` | payment_voids | إلغاءات الدفع |
| 20 | `guest_infos` | guest_infos | بيانات النزلاء |
| 21 | `app_settings` | app_settings | إعدادات التطبيق |

### 2.2 نموذج المزامنة — SyncFields Mixin
مصدر: `mobile/lib/services/local_db.dart` (mixin `SyncFields` على جميع الجداول).

كل جدول يحمل الحقول التالية (مع `version`, `origin`, `vectorClock`, `deviceId`, `idempotencyKey`):

| الحقل | النوع | الاستخدام |
|---|---|---|
| `localUuid` | TEXT (PK/فريد) | المفتاح الأساسي الموحد عبر الأجهزة |
| `serverId` | INTEGER nullable | المعرف من الخادم |
| `createdAt`/`updatedAt` | INTEGER | إيقات زمني بالثواني |
| `deletedAt` | INTEGER nullable | إلهاء منطقي (tombstone) |
| `version` | INTEGER (default 1) | للـ Optimistic Lock |
| `origin` | TEXT (default 'local') | مصدر السجل |
| `vectorClock` | TEXT (default '{}') | للـ conflict detection |
| `deviceId` | TEXT | آخر جهاز عدّل |
| `idempotencyKey` | TEXT nullable | لمنع التكرار |
| `syncTimestamp` | INTEGER (default 0) | مؤشر المزامنة |

### 2.3 نماذج العمليات — Outbox (push)
مصدر: `mobile/lib/data/sync_models.dart` (`SyncQueueEntry`) + جدول `Outbox` في `local_db.dart`.

```jsonc
// عنصر outbox — يُرسل إلى Worker عبر POST /sync/push
{
  "entity": "bookings",            // اسم الكيان
  "op": "insert",                  // insert | update | delete
  "localUuid": "uuid-...",
  "serverId": 123,                 // nullable
  "payload": { ... } ,             // جسم السجل (camelCase كما يرسله الهاتف)
  "clientTs": 1700000000,          // إيقات الجهاز
  "idempotencyKey": "uuid-...",
  "processingStatus": "pending",   // pending | processing | completed | failed
  "deliveredToPrimary": false,
  "deliveredToSecondary": true,
  "source": "local"                // | "restore"
}
```

**مؤشرات Outbox** (للـ Worker): `idx_outbox_status`, `idx_outbox_entity_status`, `idx_outbox_uuid_pending`,
`idx_outbox_processing_started`.

### 2.4 نموذج السحب — Pull (metadata-first + delta)
مصدر المشروع `perf/appwrite-sync-pull-reduction` (commit `a7dfd80c`، `94fa3ef2`، `30ebe23b`).

1. **Phase 1 — metadata:** `GET /sync/pull-metadata?entities=bookings,booking_nights&since=<lastPullTs>`
   → يُرجع `$id + $updatedAt` فقط (Query.select) للـ window الزمني.
2. **Phase 2 — diff المحلي:** المقارنة مع `sync_remote_meta` (كاش $updatedAt لكل مستند/كيان).
   → القائمة `unknownTsIds` و `changed` IDs فقط.
3. **Phase 3 — تحميل كامل للفرق:** `GET /sync/pull?ids=<changed>` → تحميل الوثائق الكاملة فقط.
   → الصفوف المطابقة محلياً = صفر تحميل.
4. **Phase 4 — checkpoint:** تقدم المؤشر إلى `max($updatedAt)` من **الخادم** (ليس وقت الجهاز)
   عبر `_pendingMetaServerMaxTs` — يغلق النافذة ويمنع إعادة السحب.

**قواعد أساسية (من الفرع perf):**
- `booking_nights`: full/initial pull محدود بـ `SyncConstants.initialBookingNightsPullLimit` (1000) + استبعاد tombstones.
- `audit_logs`: مستبعد من Appwrite sync تماماً.
- سحب مركزي 2-minute throttle + `SYNC_DIAGNOSTIC` للتهديدات المتكررة.
- دوري delta-only تلقائي بعد 1h عدم نشاط (`pull staleness guard`).

### 2.5 Realtime + حل النزاعات
- **Realtime الحالي:** Appwrite WebSocket يرسل بروتوكولات Remote→Local.
- **الصراعات:** `vectorClock` + Optimistic Lock (`version`).
- **push echo immunization:** لا تُعاد معالجة التغييرات التي أرسلها الجهاز نفسه (من الـ outbox المحلي).

---

## 3. العمارة المستهدفة — Cloudflare Worker (TypeScript)

### 3.1 المكدّس التكنولوجي
| المكوّن | التكنولوجيا | الدور |
|---|---|---|
| Worker الرئيسي | TypeScript + Hono (`hono`) | RESTful API + WebSocket doorman |
| قاعدة البيانات | **D1 Database** (SQLite) | 21 جدول + outbox + remote_meta + sync_log |
| التخزين الخافت | **KV** | rate-limiting token bucket + session cache مؤقت |
| الاتصال المستمر | **Durable Objects** | إدارة WebSocket الدائمة + قفل مزامنة لكل جهاز |
| المشغل | `wrangler` + `@cloudflare/next-on-pages` | بناء/نشر |
| Auth | JWT (HS256) موقعة بمفتاح سري Worker | توثيق الجهاز/المستخدم |
| المراقبة | `@cloudflare/workers-analytics-provider` | سجلات sync + metrics |

### 3.2 بنية المشروع المقترحة `worker/`
```
worker/
├── src/
│   ├── index.ts                 // نقطة الدخول — Hono app + WebSocket upgrade
│   ├── config.ts                // متغيّرات البيئة (D1، KV، DO، JWT secret)
│   ├── auth.ts                  // middleware JWT
│   ├── rateLimit.ts             // rate-limiter مبني على KV
│   ├── routes/
│   │   ├── sync.ts              // POST /sync/push ، GET /sync/pull*
│   │   ├── pull.ts              // pull full documents by ids
│   │   ├── pullMetadata.ts      // pull $id+$updatedAt only (metadata-first)
│   │   ├── entities.ts          // CRUD للكيانات (rooms, bookings, …)
│   │   └── health.ts            // مراقبة الصحة
│   ├── services/
│   │   ├── database.ts          // D1 helpers (prepared statements)
│   │   ├── conflictResolver.ts  // vectorClock + version + tombstones
│   │   ├── outboxProcessor.ts   // معالجة دفعات الـ outbox
│   │   ├── checkpoint.ts        // تقدم مؤشرات per-entity
│   │   └── logger.ts            // سجلات sync
│   └── durableObjects/
│       ├── SessionObject.ts     // WebSocket + device sync lock
│       └── types.ts
├── migrations/                  // ملفات SQL للـ D1 (schema + indexes)
│   └── 001_initial_schema.sql
├── test/                        // اختبارات Vitest
├── package.json
├── tsconfig.json
└── wrangler.toml
```

### 3.3 مثال `wrangler.toml`
```toml
name = "marina-sync-worker"
main = "src/index.ts"
compatibility_date = "2026-09-04"

[[d1_databases]]
binding = "DB"
database_name = "marina_hotel"
database_id = "<DB_ID>"

[[kv_namespaces]]
binding = "RATE_KV"
id = "<KV_ID>"

[[durable_objects]]
name = "SyncSession"
class_name = "SyncSession"

[env.production]
# ...
```

---

## 4. تعريف شيماء D1 — D1 Schema Migration

### 4.1 استراتيجية الترحيل (One-time)
1. إخراج نسخة `.db` من Appwrite/MariaDB الحالي (dump أو من `scripts/appwrite/...`).
2. تشغيل `migrations/001_initial_schema.sql` على D1.
3. استيراد البيانات عبر `wrangler d1 execute marina_hotel --local --file=seed.sql`
   (أو Worker migrate endpoint مؤقت `POST /admin/migrate`).

### 4.2 الجداول الأساسية (مُقابلة SQLite المحلي)
(نفس تعريف `local_db.dart` — نسخة مباشرة إلى D1):

```sql
-- مثال: bookings (باقي الكيانات بنفس النمط + SyncFields)
CREATE TABLE IF NOT EXISTS bookings (
  local_uuid   TEXT PRIMARY KEY,
  server_id    INTEGER,
  room_number  TEXT,
  guest_name   TEXT,
  guest_phone  TEXT,
  checkin_date TEXT,
  checkout_date TEXT,
  status       TEXT,
  -- ... باقي الحقول
  created_at   INTEGER NOT NULL,
  updated_at   INTEGER NOT NULL,
  deleted_at   INTEGER,
  version      INTEGER NOT NULL DEFAULT 1,
  `origin`     TEXT NOT NULL DEFAULT 'local',
  vector_clock TEXT NOT NULL DEFAULT '{}',
  device_id    TEXT NOT NULL DEFAULT '',
  idempotency_key TEXT,
  sync_timestamp INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_bookings_updated_at ON bookings(updated_at);
CREATE INDEX IF NOT EXISTS idx_bookings_room       ON bookings(room_number);
CREATE INDEX IF NOT EXISTS idx_bookings_status      ON bookings(status);
```

### 4.3 جداول المزامنة الخاصة بالـ Worker
```sql
-- كاش $updatedAt الخاص بكل مستند/كيان (يحل محل Appwrite sync_remote_meta)
CREATE TABLE IF NOT EXISTS remote_meta (
  entity       TEXT NOT NULL,
  doc_id       TEXT NOT NULL,
  updated_at   INTEGER NOT NULL,
  PRIMARY KEY (entity, doc_id)
);
CREATE INDEX IF NOT EXISTS idx_remote_meta_entity ON remote_meta(entity);

-- آخر checkpoint pull لكل كيان (per-entity watermark)
CREATE TABLE IF NOT EXISTS entity_watermark (
  entity       TEXT PRIMARY KEY,
  last_pull_ts INTEGER NOT NULL DEFAULT 0,
  last_server_max INTEGER NOT NULL DEFAULT 0
);

-- صف الـ outbox المركزي (مُطابق لـ mobile Outbox)
CREATE TABLE IF NOT EXISTS outbox (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  entity              TEXT NOT NULL,
  op                  TEXT NOT NULL,          -- insert|update|delete
  local_uuid          TEXT NOT NULL,
  server_id           INTEGER,
  payload             TEXT NOT NULL,          -- JSON
  client_ts           INTEGER NOT NULL,
  attempts            INTEGER NOT NULL DEFAULT 0,
  last_error          TEXT,
  idempotency_key     TEXT,
  processing_status   TEXT NOT NULL DEFAULT 'pending',
  processing_started_at INTEGER,
  device_id           TEXT NOT NULL,
  processed_at        INTEGER
);
CREATE INDEX IF NOT EXISTS idx_outbox_status ON outbox(processing_status);
CREATE INDEX IF NOT EXISTS idx_outbox_entity_status ON outbox(entity, op, processing_status);
CREATE INDEX IF NOT EXISTS idx_outbox_uuid_pending ON outbox(entity, local_uuid, processing_status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_outbox_idempotency ON outbox(idempotency_key) WHERE processing_status='completed';

-- سجلات التدول/المزامنة
CREATE TABLE IF NOT EXISTS sync_log (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  device_id     TEXT NOT NULL,
  entity        TEXT NOT NULL,
  phase         TEXT NOT NULL,          -- push|pull_metadata|pull_delta|apply
  status        TEXT NOT NULL,          -- ok|partial|failed
  records       INTEGER,
  duration_ms   INTEGER,
  message       TEXT,
  ts            INTEGER NOT NULL
);
```

### 4.4 فهارس الأداء (port من `setup_appwrite_schema.js` — 23× `idx_updated_at`)
- `idx_<entity>_updated_at` لكل كيان (21 فهرساً).
- فهرس مركب على `outbox(entity, local_uuid, processing_status)`.
- فهرس زمني على `sync_log(device_id, ts)`.

---

## 5. API الـ Worker — نقطة النهاية والبروتوكول

### 5.1 المصادقة
- كل طلب يحمل `Authorization: Bearer <JWT>` (HS256، يحمل `deviceId` + `hotelId`).
- JWT يُصدّره Worker عبر endpoint تسجيل دخول (استبدال Appwrite account/session أو API key).
- `auth.ts` = middleware يتحقّق ويضيف `env.userId` / `env.deviceId` للـ context.

### 5.2 rate-limiting عبر KV
- **الخوارزمية:** Token Bucket (سعة افتراضية 60 طلب/دقيقة/جهاز) مخزن في KV بـ TTL.
- `rateLimit.ts`: يقرأ `RATE_KV` بمفتاح `rl:<deviceId>:<minute>`، ينقص، يرفض بـ 429 عند النفاذ.
- حالات استثناء: pull_metadata (سعة أعلى)، admin migrate (مفتوح).

### 5.3 النقاط النهائية — Endpoints

#### `POST /sync/push`
- **الجسم:** `{ changes: SyncQueueEntry[] }` (نفس شكل الـ outbox).
- **المنطق (`outboxProcessor.ts`):**
  1. تخزين كل `change` في جدول `outbox` بـ `processing_status='pending'`.
  2. معالجة دفعة واحدة (batch) داخل معاملة D1:
     - إهمام `idempotency_key` → تخطي إذا `processing_status='completed'`.
     - `insert`: UPSERT في الجدول الهدف بحسب `local_uuid`، تعيين `server_id` إن لم يكن.
     - `update`: تحقّق `version` (Optimistic Lock)؛ إذا انحرف → **conflict** → دمج `vector_clock`.
     - `delete`: تعيين `deleted_at` (tombstone) — لا حذف فعلي.
  3. تحديث `remote_meta` بـ `$updatedAt`/id لكل سطر معالج.
  4. إرجاع `{ results: [{localUuid, success, serverId, conflict?}] }`.
  5. **push echo immunization:** إذا كان `deviceId` == جهاز المعالجة، لا تُعيد إرساله للـ Realtime.

#### `GET /sync/pull-metadata` (metadata-first — Phase 1)
- **البارامترات:** `?entities=bookings,booking_nights&since=<lastPullTs>&tombstones=true`
- **الاستجابة:**
  ```jsonc
  {
    "bookings":         [{ "$id": "uuid-x", "$updatedAt": 1700000000, "deleted": false }],
    "booking_nights":   [{ "$id": "...", "$updatedAt": ... }]
  }
  ```
- فقط `$id + $updatedAt` (اختيارياً `deleted` flag) — بدون باقي الحقول.

#### `GET /sync/pull` (Phase 3 — تحميل الفرق فقط)
- **البارامترات:** `?entities=bookings&ids=id1,id2,…`
- **الاستجابة:** `{ bookings: [ { full documents } ] }` — فقط الـ IDs التي طلبها العميل.

#### `GET /sync/pull-delta` (طريقة مدمجة — خيار fallback)
- `?entity=<e>&since=<ts>` → يُرجع كل الوثائق المتغررة في الـ window (للأجهزة التي لا تدعم metadata-first).

#### `GET /entities/<entity>` (CRUD للواجهات الإدارية / Dashboard)
- `GET /entities/:entity?filters=…` → قراءة محدثة (للواجهات الإدارية / Dashboard).

#### `GET /health`
- فحص صحة D1 + KV + DO.

#### `POST /admin/migrate`
- endpoint محمي لمرة واحدة لترحيل البيانات (مفعّل ثم معطّل).

### 5.4 Realtime — Durable Object `SyncSession`
- الـ Worker يرفع اتصال WebSocket إلى `SyncSession` (DO مفتوح على `/realtime` أو عبر `upgradeWebSocket`).
- `SyncSession Object`:
  - يسجّل الاتصالات لكل `deviceId` + `hotelId`.
  - عند **push ناجح** → يبثلّث `Remote→Local` change جديد للأجهزة الأخرى (Broadcast).
  - **قفل المزامنة:** قبل بدء دورة sync كاملة، يطلب الـ DO lock لمدة TTL قصيرة (mutex مركزي).
  - يُحدّث الـ KV بجلسات نشطة (للـ health monitor).

---

## 6. استراتيجية حل النزاعات — Conflict Resolution

منطق موحد في `conflictResolver.ts` (ينسخ من `mobile/lib/services/sync_core/smart_conflict_resolver.dart`):

1. **Optimistic Lock:** عند `update`، الـ Worker يتحقّق من `version`؛ إذا لم يطابق → رفع `conflict` flag.
2. **vectorClock merger:** دمج العقود (`mergeVectorClocks`) — الجهاز الأحدث يربح لكن لا يضيع التغييرات الأخرى.
3. **Tombstone precedence:** `deleted_at` يأخذ الأولوية — لا إحياء تلقائي لسجلات محذوفة.
4. **server-authoritative timestamps:** تقدم `entity_watermark.last_server_max` (ليس وقت الجهاز).

---

## 7. بروتوكول المزامنة الكامل — Sync Protocol (mobile ↔ Worker)

جدول مرحّل يعاد توحيده في `SyncSession`/`AppwriteSyncManager`:

```
دورة (push → pull → apply) — كل 2-15 دقيقة أو عند فتح الشاشة أو CRUD:

1. PUSH OUTBOX
   mobile: POST /sync/push  { changes: pendingOutbox }
   worker: يعالج الدفعة، يُرجع results؛ يحدّث outbox في D1.

2. REALTIME NOTIFY  (اختياري)
   worker: يُرسل WebSocket broadcast للأجهزة الأخرى ← push echo immunization يمنع التكرار للـ device المرسِل.

3. PULL METADATA-FIRST
   mobile: GET /sync/pull-metadata?entities=…&since=<watermark>
   worker: يُرجع $id+$updatedAt فقط.
   mobile: يقارن مع remote_meta المحلي.

4. PULL DELTA DOCS
   mobile: GET /sync/pull?entities=…&ids=<changed>
   worker: يُرجع الوثائق الكاملة للفرق فقط.

5. APPLY + CHECKPOINT
   mobile: يطبق على Drift، يكتب sync_remote_meta.
   worker: يرفع entity_watermark إلى server max($updatedAt) — يغلق النافذة.

6. SYNC LOG
   كل المرحلات تُسجل إلى D1 sync_log للمراقبة.
```

**مطلوبات مطابقة الفرع `perf/appwrite-sync-pull-reduction`:**
- `booking_nights` — full pull محدود 1000 + tombstone exclusion.
- `audit_logs` — مستبعد من pull/push.
- 2-minute pull throttle + staleness guard (delta-only بعد 1h idle).

---

## 8. تخطيط الترحيل المرحلي — Phased Rollout

| المرحلة | ما يتم تنفيذه | المخاطر | بديل/للتراجع |
|---|---|---|---|
| **0 — الاستعداد** | إنشاء `worker/`، `wrangler.toml`، migrations، schema. تشغيل D1 علىي بيئة staging. | - | الاحتفاظ بـ Appwrite كخلفية. |
| **1 — Push via Worker** | توجيه `POST /sync/push` إلى الـ Worker (بدل Appwrite). Pull لا يزال على Appwrite. | فقدان push إذا فشل D1. | feature flag يرجع الـ push لـ Appwrite. |
| **2 — Pull metadata-first** | توجيه `pull-metadata`/`pull` إلى الـ Worker. | drift بين Appwrite و D1 خلال الترحيل. | إعادة كتابة `entity_watermark` من Appwrite. |
| **3 — Realtime via DO** | تشغيل `SyncSession` DO؛ إيقاف Appwrite WebSocket. | فقدان اتصال WebSocket، latency. | fallback إلى polling كل 30s. |
| **4 — Admin endpoints** | توجيه CRUD `entities/*` إلى Worker. | كسر واجهة Dashboard. | نفس feature flag. |
| **5 — إيقاف Appwrite** | إيقاف `appwrite_sync_manager.dart` بالكامل؛ حذف Collections. | انقطاع تام إذا فشل D1. | rollback إلى 2 دقائق max — D1 replicate سريع. |

**آلية التبديل:** `AppwriteConfig.useWorkerSync` flag في `.env` → يحوّل الـ mobile بين Appwrite و Worker.
الترحيل لكل `entity` بشكل منفصل (entity-level feature flag) لضمان zero-downtime.

---

## 9. النقل من `appwrite_sync_manager.dart` — Mapping the Move

| المنطق الأصلي (Dart) | المكان الجديد (TypeScript Worker) |
|---|---|
| `_pullDocsDeltaMetadataFirst(entity, queries)` | `GET /sync/pull-metadata` + `GET /sync/pull` |
| `appwriteService.listBookingNights(...)` | `GET /sync/pull?entity=booking_nights&ids=…` (capped 1000) |
| `database.upsertRemoteMeta(...)` | `remote_meta` في D1 |
| `_pendingMetaServerMaxTs` + `entity_watermark` | `entity_watermark.last_server_max` |
| `failedCollections` | إرجاع `partial` + تسجيل `sync_log` |
| `SyncMutex` / `SyncGate` | `SyncSession` DO lock |
| Appwrite Realtime WebSocket | `SyncSession` DO `Broadcast` |
| CircuitBreaker/AdaptiveFallback | KV-backed retry counters + 503 circuit |
| SmartSync/SmartConflictResolver | `conflictResolver.ts` |

---

## 10. الاختبار — Testing Strategy

- **Vitest** على `worker/test/` يغطي:
  - `outboxProcessor` (idempotency، optimistic lock، tombstone، push echo).
  - `conflictResolver` (vector clock merge، version drift).
  - `pullMetadata` (only $id+$updatedAt، tombstone exclusion).
  - `rateLimit` (429 عند التجاوز).
- **اتصال حقيقي:** `wrangler dev` + mobile عنه تشغيل التكاملي.
- **معايير أداء الـ Worker:**
  - Pull metadata ≤ 50ms للـ window (≤ 1000 doc).
  - Push batch ≤ 100 صف/ثانية.
  - Rate limit تُمنع bursts > 60 req/min/device.

---

## 11. المخاطر والحدود — Risks & Constraints

1. **D1 limits:** ≤ 10 GB storage / ≤ 100k reads/sec (kf perf branch) — كافي لفندق واحد لكن راجع SLA.
2. **KV consistency:** eventual — لا تستخدم KV للكيانات المهمة، فقط rate-limit + cache مؤقت.
3. **DO limits:** ≤ 10k objects، ≤ 30s CPU جلسة — يكفي لغرض الـ WebSocket locking.
4. **الترميز camelCase ↔ snake_case:** يبقى في `payload_mapper.ts` (ينسخ من `mobile/lib/services/sync/payload_mapper.dart`).
5. **الصيانة:** schema migrations يُدار عبر `migrations/*.sql` + wrangler d1 migrations.
6. **الأمان:** لا تُكتب API keys في `.env` (CLAUDE.md يُنبّه: `AGENT_ROUTER_API_KEY` مكشوف)؛ تستخدم Worker secrets (`wrangler secret put`).

---

## 12. قائمة المهام — TODO

- [ ] إنشاء `worker/` scaffolding (`package.json`, `tsconfig.json`, `wrangler.toml`).
- [ ] كتابة `migrations/001_initial_schema.sql` + `002_indexes.sql`.
- [ ] تنفيذ `src/routes/sync.ts` (push/pull-metadata/pull).
- [ ] تنفيذ `src/services/conflictResolver.ts` + `outboxProcessor.ts`.
- [ ] تنفيذ `src/services/rateLimit.ts` (KV token bucket).
- [ ] تنفيذ `SyncSession` Durable Object (`src/durableObjects/SessionObject.ts`).
- [ ] كتابة اختبارات Vitest.
- [ ] إضافة feature flag `useWorkerSync` إلى `mobile/.env` + AppwriteConfig.
- [ ] تشغيل D1 staging + wrangler dev؛ تشغيل دورة مزامنة تكاملية.

---

> **الملخّص:** هذه الخطة تنقل طبقة المزامنة (التي تقع حالياً في `appwrite_sync_manager.dart` + Appwrite Collections) إلى Worker Cloudflare موحد بـ TypeScript/D1/KV/د. الأمان والـ realtime يُداران عبر Durable Objects، والـ rate-limiting عبر KV، مع الحفاظ على بروتوكول المزامنة الموحد (metadata-first delta + vector clock + idempotency) كما هو معرّف في فرع
> `perf/appwrite-sync-pull-reduction`. الترحيل على ثلاث مراحل: push → pull → realtime، مع إمكانية التراجع الكامل إلى Appwrite.
