# خطة الانتقال الشاملة إلى Cloudflare Worker للمزامنة
# Marina Hotel — Cloudflare Worker Sync Migration Plan (v2)

> **الحالة الفعلية:** الفرع `origin/api-cloudflare` يحتوي على تنفيذ شبه مكتمل للـ Worker.
> هذا المستند هو خطة دقيقة مبنية على الكود الفعلي في الفرع، مع تحديد ما تم وما تبقى.
>
> **الهدف النهائي:** استبدال طبقة المزامنة في `mobile/lib/services/appwrite_sync_manager.dart`
> (6445 سطراً) بـ Worker على Cloudflare يعمل كـ backend للمزامنة، مع الاستمرار في
> المنطق المحلي (Drift + outbox) على الجهاز.

---

## 1. ملخص تنفيذي / Executive Summary

### 1.1 ما تم تنفيذه فعلاً (origin/api-cloudflare)
| المكوّن | الحالة | الملف |
|---|---|---|
| D1 Database (SQLite) | ✅ مكتمل | `worker/schema.sql` (33 KB — 28 جدول، 106 فهرس) |
| Durable Object (SyncLockDO) | ✅ مكتمل | `worker/src/sync-lock.ts` |
| KV (Rate Limiting) | ✅ مكتمل | `worker/wrangler.toml` (RATE_LIMIT) |
| JWT Auth (PBKDF2 + HS256) | ✅ مكتمل | `worker/src/auth.ts` |
| Pull (delta-by-cursor) | ✅ مكتمل | `worker/src/sync.ts` (`handlePull`) |
| Push (batch) | ✅ مكتمل | `worker/src/sync.ts` (`handlePush`) |
| Conflict Resolution (LWW + vector clock) | ✅ مكتمل | `worker/src/sync.ts` |
| Idempotency (idempotency_log) | ✅ مكتمل | `worker/src/sync.ts` |
| Global sync clock (monotonic ts) | ✅ مكتمل | `worker/schema.sql` (`sync_clock`) |
| Rate Limiting (D1-based) | ✅ مكتمل | `worker/src/index.ts` (`checkRateLimit`) |
| CORS + Global error handling | ✅ مكتمل | `worker/src/index.ts` |
| SQLi protection (whitelist + prepared) | ✅ مكتمل | `worker/src/sync.ts` (P0-A..J) |
| R2 file storage | ❌ غير مذكور في الفرع | — |
| Realtime (WebSocket via DO) | ❌ غير مذكور | — |
| Mobile migration service | ✅ مكتمل | `mobile/lib/services/cloudflare_migration_service.dart` |
| Cloudflare config (Dart) | ✅ مكتمل | `mobile/lib/services/cloudflare_config.dart` |
| Cloudflare sync manager (Dart) | ✅ مكتمل | `mobile/lib/services/cloudflare_sync_manager.dart` |
| Mobile fixes (strict ts, FK, idempotent) | ✅ مكتمل | آخر commit `ab0df7a2` |

### 1.2 ما تبقى (Gaps)
1. **R2 file storage** — الفرع يذكره في README لكن لا يوجد binding في `wrangler.toml` ولا `storage.ts`.
2. **Realtime / WebSocket** — لا يوجد endpoint للـ realtime داخل الـ DO.
3. **Durable Object as WebSocket server** — `SyncLockDO` يدير أقفال فقط، لا يدير WebSockets.
4. **Metadata-first pull** — الـ Pull الحالي يستخدم cursor-based (single integer). الفرع `perf/appwrite-sync-pull-reduction` يطبق metadata-first (Phase 1: $id+$updatedAt، Phase 3: ids). يجب نقل هذا التحسين.
5. **booking_nights cap (1000)** — لا يوجد enforcement للـ initial pull limit.
6. **Tests** — الـ README يذكر 30 اختبار runtime، لكنها غير موجودة في الفرع.
7. **CI/CD** — لا يوجد `.github/workflows/worker-deploy.yml`.
8. **Secrets management** — `account_id` مكشوف في `wrangler.toml` (يجب إزالته).
9. **Per-entity watermarks** — الـ Pull يستخدم cursor واحد (`sync_clock`)، وليس per-entity watermark.
10. **Audit logs exclusion** — لا يوجد منطق لاستبعاد `audit_logs` من المزامنة.

---

## 2. التحليل العميق للوضع الحالي / Deep Current-State Analysis

### 2.1 العمارة القائمة في الفرع `api-cloudflare`
```
المخطط المعماري:
┌──────────────────────┐         ┌─────────────────────────────────────┐
│   Mobile App (Dart)  │  HTTPS  │   Cloudflare Worker (TypeScript)    │
│                      │ ──────▶ │                                     │
│  cloudflare_config   │         │   ┌─────────────────────────────┐   │
│  cloudflare_sync_    │         │   │  index.ts (Router + CORS)   │   │
│   manager            │         │   └──────────────┬──────────────┘   │
│  cloudflare_         │         │                  │                  │
│   migration_service  │         │   ┌──────────────▼──────────────┐   │
│                      │         │   │  auth.ts (JWT + PBKDF2)     │   │
│  Drift (local DB)    │         │   └──────────────┬──────────────┘   │
│   + outbox           │         │                  │                  │
│                      │         │   ┌──────────────▼──────────────┐   │
│                      │         │   │  sync.ts (Pull/Push)        │   │
└──────────────────────┘         │   └──────────────┬──────────────┘   │
                                │                  │                  │
                                │   ┌──────────────▼──────────────┐   │
                                │   │  database.ts (D1 helpers)   │   │
                                │   └──────────────┬──────────────┘   │
                                │                  │                  │
                                │   ┌──────────────▼──────────────┐   │
                                │   │  sync-lock.ts (SyncLockDO)   │   │
                                │   └──────────────┬──────────────┘   │
                                │                  │                  │
                                │   ┌──────────────▼──────────────┐   │
                                │   │  schema.sql (D1: 28 tables) │   │
                                │   └─────────────────────────────┘   │
                                │                                     │
                                │   KV (RATE_LIMIT) — مذكور لكن غير   │
                                │   مستخدم فعلياً (Rate Limiting      │
                                │   مبني على D1)                      │
                                │                                     │
                                │   Durable Objects (SYNC_LOCK)        │
                                │   — أقفال فقط، لا WebSockets       │
                                └─────────────────────────────────────┘
```

### 2.2 الكيانات المتزامنة (28 جدول في schema.sql)
مستخرجة من `worker/schema.sql`:
- **Auth (3):** `users`, `devices`, `sync_clock`
- **Sync infra (4):** `rate_limits`, `sync_log`, `sync_conflicts`, `idempotency_log`
- **Business entities (21):** `rooms`, `bookings`, `booking_nights`, `booking_notes`,
  `payments`, `debts`, `expenses`, `employees`, `shift_notes`, `cash_transactions`,
  `salary_cycles`, `salary_payments`, `salary_withdrawals`, `salary_carry_over_logs`,
  `blacklist`, `price_adjustments`, `booking_price_adjustments`, `payment_voids`,
  `guest_infos`, `app_settings`, `audit_logs`

### 2.3 نموذج المزامنة — SyncFields (موحّد بين الجهاز والخادم)
كل جدول أعمال يحمل الأعمدة الـ 16 من `SyncFields`:
| العمود | النوع | المصدر | الاستخدام |
|---|---|---|---|
| `local_uuid` | TEXT NOT NULL UNIQUE | SyncFields | المعرّف الموحد عبر الأجهزة |
| `server_id` | INTEGER NULL | SyncFields | المعرّف من الخادم |
| `created_at`/`updated_at` | INTEGER NOT NULL | SyncFields | إيقات زمني (ثواني) |
| `deleted_at` | INTEGER NULL | SyncFields | tombstone |
| `last_modified` | INTEGER NOT NULL | SyncFields | آخر تعديل |
| `*_iso` | TEXT NULL | SyncFields | نسخة ISO |
| `*_epoch` | INTEGER DEFAULT 0 | SyncFields | إيقات بالمللي |
| `version` | INTEGER DEFAULT 1 | SyncFields | Optimistic lock |
| `origin` | TEXT DEFAULT 'local' | SyncFields | مصدر السجل |
| `vector_clock` | TEXT DEFAULT '{}' | SyncFields | كشف التعارضات |
| `device_id` | TEXT DEFAULT '' | SyncFields | آخر جهاز عدّل |
| `idempotency_key` | TEXT NULL | SyncFields | منع التكرار |

### 2.4 الـ Pull — كيف يعمل حالياً
من `worker/src/sync.ts` (`handlePull`):
1. **العميل:** `GET /api/sync/pull?cursor=0&limit=200`
2. **الخادم:** يقرأ من `sync_clock` (الـ cursor العالمي) ثم يجلب السجلات التي `updated_at > cursor`، مرتبة تصاعدياً بـ `updated_at`، بحد أقصى `limit`.
3. **الاستجابة:** `{ cursor: <newCursor>, changes: [{entity, data, version, vector_clock, deleted_at}] }`
4. **العميل:** يحدّث cursor محلياً ويطبّق التغييرات على Drift.

**المشكلة:** هذا cursor-based بسيط، لكن لا يميز بين الكيانات، ولا يدعم metadata-first
(الفرع `perf/appwrite-sync-pull-reduction` يثبت أن metadata-first يقلل التنزيل بنسبة كبيرة).

### 2.5 الـ Push — كيف يعمل حالياً
من `worker/src/sync.ts` (`handlePush`):
1. **العميل:** `POST /api/sync/push` مع `[{entity, operation, localUuid, data, vectorClock, version, idempotencyKey}]`
2. **الخادم:** لكل عملية:
   - يتحقق من `idempotencyKey` (إذا وُجد، يُرجع النتيجة المخزنة).
   - يقارن `vectorClock` و`version` (LWW).
   - يحل التعارض ويُسجله في `sync_conflicts`.
   - يستخدم `sync_clock` لتوليد `updated_at` صارم التصاعد (RETURNING).
3. **الاستجابة:** `{ results: [{localUuid, success, serverVersion, conflict?}] }`

### 2.6 الـ SyncLockDO — كيف يعمل
من `worker/src/sync-lock.ts`:
- **النمط:** Durable Object واحد لكل `entity:entityId` (مثل `bookings:uuid-123`).
- **القفل:** TTL افتراضي 30 ثانية، يمنع الكتابة المتزامنة على نفس السجل.
- **API:** `acquire(deviceId, ttlMs?)` → `release(deviceId)` → `forceRelease()`.
- **التحقق:** يرفض القفل إذا كان محجوزاً لجهاز آخر.

**الفجوة:** الـ DO لا يدعم WebSocket للـ realtime. يجب إضافة `SyncRealtimeDO` منفصل.

### 2.7 Rate Limiting — كيف يعمل
من `worker/src/index.ts` (`checkRateLimit`):
- **التخزين:** D1 (`rate_limits` table) — **ليس** KV (رغم وجود binding).
- **النافذة:** 60 ثانية افتراضياً (قابل للتهيئة).
- **الحد:** 1000 طلب/نافذة/IP.
- **التنظيف:** احتمالية 1% لكل طلب تحذف النوافذ القديمة.

**ملاحظة:** الفرع يستخدم D1 بدلاً من KV لـ Rate Limiting لتجنب حد الكتابة اليومي على KV.

### 2.8 الأمان — ما تم تطبيقه
من `origin/api-cloudflare` (commit `ab0df7a2`):
- **P0-A..P0-J:** إصلاحات أمان صارمة في `sync.ts`, `database.ts`, `index.ts`, `auth.ts`, `sync-lock.ts`.
- **SQLi:** statement splitter يقبل فقط INSERTs مفردة في جداول الكيانات.
- **HMAC constant-time:** مقارنة آمنة في `auth.ts`.
- **PBKDF2 versioning:** `pbkdf2$25000$salt$hash` مع دعم legacy 10k.
- **Login brute-force:** bucket منفصل 20 طلب/دقيقة.
- **Migrate endpoint:** محدود بـ 200 عبارة/10MB مع whitelist صارم.

### 2.9 ما تم نقله من الفرع `perf/appwrite-sync-pull-reduction`
- **النقل:** الفرع `api-cloudflare` لم يأخذ تحسينات `perf/appwrite-sync-pull-reduction` بعد.
- **التحسينات المطلوبة:** metadata-first pull، booking_nights cap، audit_logs exclusion،
  2-minute throttle، pull staleness guard.

---

## 3. الخطة التفصيلية للتنفيذ / Detailed Implementation Plan

### 3.1 المرحلة 0 — الاستعداد (يوم 1-2)
**الهدف:** تجهيز بيئة التطوير والـ CI.

**المهام:**
1. **نقل الكود من الفرع إلى main:**
   ```bash
   git checkout main
   git merge origin/api-cloudflare --no-ff -m "Merge api-cloudflare worker"
   ```
2. **حذف `account_id` من `wrangler.toml`:**
   ```diff
   - account_id = "81a73bba9acc1de5693ff929d0a372ce"
   ```
3. **تجهيز Secrets:**
   ```bash
   wrangler secret put JWT_SECRET
   wrangler secret put CORS_ORIGIN
   ```
4. **إعداد بيئة staging:**
   - D1 منفصل: `marina-hotel-db-staging`
   - KV منفصل: staging rate limit
   - DO: staging namespace
5. **CI workflow** (`.github/workflows/worker-deploy.yml`):
   - عند push لـ `api-cloudflare` → deploy staging
   - عند tag `v*` → deploy production

### 3.2 المرحلة 1 — تشغيل Staging (يوم 3-5)
**الهدف:** تشغيل الـ Worker على بيئة staging مع بيانات الاختبار.

**المهام:**
1. **نشر staging:**
   ```bash
   wrangler deploy --env staging
   ```
2. **إنشاء مستخدم admin أول:**
   ```bash
   curl -X POST https://marina-hotel-api-staging.workers.dev/api/auth/register \
     -H "Content-Type: application/json" \
     -d '{"username":"admin","password":"strong-pass","role":"admin"}'
   ```
3. **تشغيل migration من جهاز الاختبار:**
   ```dart
   await CloudflareMigrationService(apiClient).migrate();
   ```
4. **اختبار دورة مزامنة كاملة:**
   - Push من الجهاز → تحقق في D1.
   - Pull من جهاز ثانٍ → تحقق من تطبيق البيانات.
   - تعارض متعمد → تحقق من تسجيله في `sync_conflicts`.

**معيار النجاح:** دورة push/pull تعمل على 21 كيان بدون فقدان بيانات.

### 3.3 المرحلة 2 — إضافة التحسينات من perf/appwrite-sync-pull-reduction (يوم 6-10)
**الهدف:** نقل تحسينات الأداء من الفرع `perf`.

**المهام:**
1. **Metadata-first pull** في `worker/src/sync.ts`:
   ```typescript
   // Phase 1: return $id + $updatedAt only
   // GET /api/sync/pull-metadata?entity=bookings&since=<ts>
   // → { docs: [{localUuid, updatedAt, deleted}] }
   ```
2. **Per-entity watermark** (بدلاً من cursor عالمي):
   ```sql
   CREATE TABLE entity_watermark (
     entity TEXT PRIMARY KEY,
     last_pull_ts INTEGER NOT NULL,
     last_server_max INTEGER NOT NULL
   );
   ```
3. **booking_nights cap (1000):**
   ```typescript
   const INITIAL_PULL_LIMITS = { booking_nights: 1000 };
   ```
4. **audit_logs exclusion:**
   ```typescript
   const SYNC_EXCLUDED = ['audit_logs'];
   ```
5. **2-minute pull throttle:**
   ```typescript
   const PULL_THROTTLE_MS = 120_000;
   ```
6. **Pull staleness guard (1h idle → delta-only):**
   ```typescript
   const PULL_STALENESS_MS = 60 * 60 * 1000;
   ```
7. **تحديث `sync_clock` ليكون per-entity** (أو إضافة `entity_watermark` كطبقة ثانية).

**معيار النجاح:** Pull metadata ≤ 50ms لـ window 1000 سجل.

### 3.4 المرحلة 3 — Realtime عبر Durable Objects (يوم 11-15)
**الهدف:** إضافة WebSocket للـ realtime notifications.

**المهام:**
1. **إنشاء `SyncRealtimeDO`** (Durable Object جديد):
   ```typescript
   // worker/src/realtime.ts
   export class SyncRealtimeDO implements DurableObject {
     private clients = new Set<WebSocket>();
     
     async fetch(request: Request): Promise<Response> {
       if (request.headers.get('Upgrade') === 'websocket') {
         const pair = new WebSocketPair();
         // ... accept, store, broadcast
       }
     }
     
     async broadcast(deviceId: string, entity: string, op: string, id: string) {
       // Push echo immunization: skip sender
     }
   }
   ```
2. **تحديث `wrangler.toml`:**
   ```toml
   [[durable_objects.bindings]]
   name = "SYNC_REALTIME"
   class_name = "SyncRealtimeDO"
   
   [[migrations]]
   tag = "v2"
   new_sqlite_classes = ["SyncRealtimeDO"]
   ```
3. **Webhook في `handlePush`:** بعد نجاح كل عملية، بثّ حدث realtime:
   ```typescript
   await env.SYNC_REALTIME.get(id).fetch('https://do/broadcast', { method: 'POST', body });
   ```
4. **WebSocket endpoint:** `GET /api/sync/realtime` (auth required).
5. **Mobile client:** اشتراك WebSocket + تطبيق `remote-change` على Drift.

**معيار النجاح:** تغيير على جهاز A → جهاز B يستقبل الحدث في < 500ms.

### 3.5 المرحلة 4 — R2 File Storage (يوم 16-17)
**الهدف:** تخزين الملفات (صور النزلاء، الإيصالات) في R2.

**المهام:**
1. **إنشاء R2 bucket:**
   ```bash
   wrangler r2 bucket create marina-hotel-files
   ```
2. **تحديث `wrangler.toml`:**
   ```toml
   [[r2_buckets]]
   binding = "FILES"
   bucket_name = "marina-hotel-files"
   ```
3. **إنشاء `worker/src/storage.ts`:**
   - `POST /api/files/upload` — multipart upload إلى R2.
   - `GET /api/files/:id` — download.
   - `DELETE /api/files/:id` — delete.
4. **MIME whitelist:** images/jpeg, images/png, application/pdf.
5. **حجم أقصى:** 50MB.
6. **Mobile client:** تحديث `cloudflare_sync_manager.dart` لرفع الصور.

**معيار النجاح:** رفع صورة نزيل → استرجاعها من جهاز آخر.

### 3.6 المرحلة 5 — التبديل التدريجي (يوم 18-25)
**الهدف:** استبدال Appwrite تدريجياً بدون downtime.

**الاستراتيجية:** Feature flag في `cloudflare_config.dart`:
```dart
class CloudflareConfig {
  static const bool useCloudflareSync = bool.fromEnvironment(
    'USE_CLOUDFLARE_SYNC',
    defaultValue: false,
  );
}
```

**التبديل لكل كيان:**
| اليوم | الكيانات | الميزة |
|---|---|---|
| 18 | `rooms`, `employees` | أقل تعقيداً |
| 20 | `expenses`, `debts` | متوسطة |
| 22 | `bookings`, `booking_nights`, `booking_notes` | حرجة — اختبار مكثف |
| 24 | `payments`, `cash_transactions`, `payment_voids` | مالية — اختبار حذر |
| 25 | الباقي | التحول الكامل |

**لكل كيان:**
1. تشغيل الـ feature flag لذلك الكيان.
2. مراقبة logs في D1 + mobile لمدة 24 ساعة.
3. مقارنة عدد السجلات (D1 vs Appwrite).
4. إذا مطابق → تأكيد. إذا لا → rollback.

### 3.7 المرحلة 6 — إيقاف Appwrite (يوم 26-28)
**الهدف:** إزالة Appwrite نهائياً.

**المهام:**
1. **تأكيد اكتمال التحويل:** كل الكيانات على Worker.
2. **نسخ احتياطي أخير:** تصدير Appwrite DB إلى JSON.
3. **تعطيل Appwrite API key** في `appwrite_config.dart`.
4. **حذف `appwrite_sync_manager.dart`** (6445 سطر).
5. **تحديث `pubspec.yaml`:** إزالة `appwrite` dependency.
6. **تحديث docs:** `mobile/CLAUDE.md` لإزالة قسم Appwrite.

---

## 4. الجدول الزمني / Timeline

| المرحلة | المدة | المسؤول | المخرجات |
|---|---|---|---|
| 0 — الاستعداد | يوم 1-2 | DevOps | CI workflow, secrets, staging env |
| 1 — تشغيل Staging | يوم 3-5 | Backend | Worker deployed, admin user, first sync |
| 2 — تحسينات perf | يوم 6-10 | Backend | metadata-first, watermarks, caps |
| 3 — Realtime | يوم 11-15 | Backend | WebSocket DO, push notifications |
| 4 — R2 Storage | يوم 16-17 | Backend | File upload/download |
| 5 — التبديل التدريجي | يوم 18-25 | Full team | 21 كيان على Worker |
| 6 — إيقاف Appwrite | يوم 26-28 | DevOps | Appwrite removed, cleanup |

**المجموع:** 4 أسابيع (28 يوم عمل).

---

## 5. المخاطر والحدود / Risks & Constraints

### 5.1 مخاطر حرجة
| المخاطرة | الاحتمال | الأثر | التخفيف |
|---|---|---|---|
| فقدان بيانات أثناء التحويل | متوسط | كارثي | نسخ احتياطي قبل كل مرحلة + Dry-run mode |
| تعارض schema بين D1 و Drift | منخفض | عالي | schema.sql مبني مباشرة من Drift |
| KV Rate limit cap (100k writes/day) | عالي | متوسط | تم حله باستخدام D1 بدلاً من KV |
| DO cold start | منخفض | منخفض | TTL طويل + keep-alive |
| D1 read latency (>50ms) | متوسط | متوسط | Indexes على `updated_at` (موجودة) |
| WebSocket connection drops | عالي | متوسط | Auto-reconnect + exponential backoff |

### 5.2 حدود Cloudflare
- **D1:** ≤ 10 GB storage، ≤ 5M reads/day (free) أو unlimited (paid).
- **KV:** ≤ 100k writes/day (free) — تم تجنبه.
- **DO:** ≤ 10k objects، ≤ 30s CPU per session.
- **Worker CPU time:** 10ms (free) / 50ms (paid) per request.

### 5.3 مخاطر الأمان
- `account_id` مكشوف في `wrangler.toml` — **يجب إزالته**.
- `CORS_ORIGIN = "*"` في staging — **يجب تقييده** في production.
- JWT expiry 24 ساعة — **يجب تقليله** إلى 12 ساعة.
- لا يوجد refresh token — **يجب إضافته** لاحقاً.

---

## 6. معايير النجاح / Success Criteria

| المعيار | الهدف | القياس |
|---|---|---|
| Push throughput | ≥ 100 سجل/ثانية | bench script |
| Pull metadata latency | ≤ 50ms لـ 1000 سجل | benchmark |
| Realtime latency | ≤ 500ms من Push إلى WebSocket | timing logs |
| Zero data loss | 0 سجل مفقود | reconciliation script |
| Conflict rate | < 0.1% من العمليات | sync_conflicts count |
| Uptime | ≥ 99.9% | Cloudflare analytics |
| Sync log size | < 10MB/day | D1 query |

---

## 7. بنية الكود النهائية / Final Code Structure

```
worker/
├── src/
│   ├── index.ts              # Router + CORS + Rate Limit + Global error
│   ├── auth.ts               # JWT + PBKDF2 + middleware
│   ├── sync.ts               # Pull/Push/Conflicts
│   ├── database.ts           # D1 helpers + sync_clock
│   ├── sync-lock.ts          # SyncLockDO (per-record lock)
│   ├── realtime.ts           # SyncRealtimeDO (WebSocket) [جديد]
│   ├── storage.ts            # R2 file upload/download [جديد]
│   ├── pull-metadata.ts      # metadata-first pull [جديد]
│   └── types.ts              # TypeScript types
├── migrations/
│   ├── 001_initial_schema.sql
│   └── 002_metadata_first.sql  # entity_watermark [جديد]
├── test/
│   ├── pull.test.ts
│   ├── push.test.ts
│   ├── conflict.test.ts
│   └── security.test.ts      # SQLi vectors
├── wrangler.toml
├── package.json
└── tsconfig.json
```

---

## 8. قائمة المهام التفصيلية / Detailed TODO

### 8.1 ضروري قبل الإنتاج
- [ ] حذف `account_id` من `wrangler.toml`
- [ ] تقييد `CORS_ORIGIN` في production
- [ ] تقليل JWT expiry إلى 12 ساعة
- [ ] إضافة `entity_watermark` table
- [ ] تنفيذ metadata-first pull
- [ ] تنفيذ `booking_nights` cap (1000)
- [ ] استبعاد `audit_logs` من المزامنة
- [ ] إضافة CI workflow للـ deploy
- [ ] كتابة اختبارات Vitest

### 8.2 تحسينات مستقبلية
- [ ] Refresh token mechanism
- [ ] WebSocket عبر `SyncRealtimeDO`
- [ ] R2 file storage
- [ ] Per-device rate limiting
- [ ] Real-time conflict resolution UI
- [ ] Webhook notifications (FCM)
- [ ] Backup/restore endpoint

### 8.3 تنظيف
- [ ] حذف `appwrite_sync_manager.dart` (6445 سطر)
- [ ] إزالة `appwrite` من `pubspec.yaml`
- [ ] تحديث docs (CLAUDE.md, README)
- [ ] حذف `scripts/appwrite/` scripts

---

## 9. ملخص الفروقات عن الخطة الأصلية / Deviations from Original Plan

| الخطة الأصلية (v1) | التنفيذ الفعلي في الفرع | السبب |
|---|---|---|
| Hono framework | لا framework — vanilla fetch | بساطة، تحكم كامل |
| KV للـ Rate Limiting | D1 للـ Rate Limiting | KV له حد كتابة يومي |
| D1 للـ remote_meta | لا يوجد — sync_clock عالمي | تبسيط، لكن أقل مرونة |
| metadata-first pull | cursor-based pull | لم يُنقل من perf branch |
| R2 storage | غير مذكور | مؤجل |
| Realtime WebSocket | غير مذكور | مؤجل |
| Per-entity watermark | cursor عالمي | تبسيط |

---

## 10. المراجع / References

- **الفرع العامل:** `origin/api-cloudflare` (آخر commit `ab0df7a2`)
- **الفرع المرجعي للأداء:** `origin/perf/appwrite-sync-pull-reduction`
- **الـ schema:** `worker/schema.sql` (33 KB, 28 tables, 106 indexes)
- **التوثيق الداخلي:** `worker/README.md`
- **آخر إصلاحات أمان:** commit `ab0df7a2` (P0-A..P0-J)
