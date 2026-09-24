// ═══════════════════════════════════════════════════════════════
//  sync.ts — Sync Pull/Push Handlers
//  Delta sync + idempotent push + conflict resolution (LWW + VC)
// ═══════════════════════════════════════════════════════════════

import type { Database, PushOperation, SyncRecord } from './database';
import { isValidEntity, SYNC_ENTITY_TABLES } from './database';
import type { AuthContext } from './auth';
import type { RealtimeMessage } from './sync-lock';

/**
 * Best-effort realtime change notifier (plan phase 3): after a successful
 * push the worker notifies the SyncLockDO WebSocket hub so OTHER devices
 * trigger an immediate delta pull instead of waiting for auto-sync.
 * Implementation lives in index.ts (it owns the DO namespace binding);
 * sync.ts stays decoupled from bindings.
 */
export type RealtimeBroadcast = (msg: RealtimeMessage) => Promise<void>;

// ─── Validation ───────────────────────────────────────────────

const MAX_BATCH_SIZE = 100;
const MAX_PAYLOAD_SIZE = 5 * 1024 * 1024; // 5MB

// ✅ (2026-09-09) سقف صفحة السحب مستقل عن الرفع — طلب المستخدم
// «تسريع السحب الكامل عند أول تثبيت»: 7,300 صف ≈ 15 طلباً بدل 73
// (العميل يطلب 400/صفحة للسحب الكامل و100 للدلتا). الرفع يبقى 100
// عملية/دفعة لأن كل عملية تتكلف كتابات D1 متعددة.
const MAX_PULL_BATCH_SIZE = 500;

/**
 * Device attribution for pushed rows (fix discovered by test): the op
 * carries the device that produced it (cloudflare_sync_manager sends
 * `deviceId` per operation), while the JWT device_id is whatever was
 * present at LOGIN time — often empty for bootstrap-registered users.
 * The op value wins; the JWT value is the fallback.
 *
 * ✅ مراجعة 2026-09-09 #18: كلا المصدرين قد يكونان فارغين (توكن بلا
 * device_id claim وop بلا deviceId) — عندها كان الصف يُختم '' والبث
 * الواقعي يُرسل deviceId:'' فلا يستطيع أي عميل تمييز الصدى الذاتي
 * (فلتر msg.deviceId == _currentDeviceId) ويعيد السحب هدراً. نضمن
 * الآن أصلاً غير فارغ دائماً — الصفوف ذات الأصل المجهول تُختم
 * 'unknown-origin' ولا تُبث أصلاً بهوية فارغة.
 */
function opDeviceId(op: PushOperation, ctx: AuthContext): string {
  if (typeof op.deviceId === 'string' && op.deviceId.length > 0) return op.deviceId;
  if (typeof ctx.deviceId === 'string' && ctx.deviceId.length > 0) return ctx.deviceId;
  return 'unknown-origin';
}

// ✅ P1 (2026-09-24) حدود الحقول القادمة من العميل — تمنع الحقول
// الشاذة/الضخمة من الوصول إلى D1 (حماية كلفة + سلامة). الحدود أعلى
// بكثير من أي قيمة شرعية يرسلها العميل الحالي (outbox يرسل UUID ≤36
// وvector clocks صغيرة) فلا ترفض بيانات مشروعة.
export const PUSH_FIELD_LIMITS = {
  idempotencyKey: 128,
  deviceId: 128,
  entity: 64,
  entityId: 256,
  vectorClock: 4096,
} as const;

function validatePushOperation(op: PushOperation): string | null {
  if (!op.idempotencyKey || typeof op.idempotencyKey !== 'string') {
    return 'idempotencyKey is required';
  }
  if (op.idempotencyKey.length > PUSH_FIELD_LIMITS.idempotencyKey) {
    return `idempotencyKey too long (max ${PUSH_FIELD_LIMITS.idempotencyKey})`;
  }
  if (!op.entity || typeof op.entity !== 'string') {
    return 'entity is required';
  }
  if (op.entity.length > PUSH_FIELD_LIMITS.entity) {
    return `entity too long (max ${PUSH_FIELD_LIMITS.entity})`;
  }
  if (!['create', 'update', 'delete'].includes(op.operation)) {
    return `Invalid operation: ${op.operation}`;
  }
  if (!op.data || typeof op.data !== 'object') {
    return 'data must be an object';
  }
  if (!op.vectorClock || typeof op.vectorClock !== 'string') {
    return 'vectorClock is required';
  }
  if (op.vectorClock.length > PUSH_FIELD_LIMITS.vectorClock) {
    return `vectorClock too long (max ${PUSH_FIELD_LIMITS.vectorClock})`;
  }
  if (typeof op.updatedAt !== 'number' || op.updatedAt <= 0) {
    // ✅ P1 (2026-09-24): سلوك ورسالة موحّدان — الشرط القديم (‎< 0)
    // كان يسمح بـ updatedAt=0 بينما الرسالة تقول positive. مسار الرفع
    // لا يستلم 0 من العميل الحالي (outbox يختم clientTs بالثواني)،
    // ومسار migration الخام لا يمر من هنا إطلاقاً فلا يتأثر.
    return 'updatedAt must be a positive number';
  }
  if (op.deviceId !== undefined && (typeof op.deviceId !== 'string' || op.deviceId.length > PUSH_FIELD_LIMITS.deviceId)) {
    return `deviceId must be a string of at most ${PUSH_FIELD_LIMITS.deviceId} chars`;
  }
  return null;
}

/**
 * ✅ P0 review (2026-09-24): local_uuid هو الهوية الأساسية للمزامنة،
 * ثم server_id، ثم legacy id (لمخططات قديمة فقط). لا يوجد بديل صامت
 * لـ data.id — الحالات الغامضة تُرفض برسالة واضحة، والمنفّذ الذري في
 * database.ts يحدد هوية الصف الفعلية من الصف نفسه (ولا يعيد تغيير
 * local_uuid أبداً).
 */
export function resolvePushEntityId(data: Record<string, unknown>): string {
  const value = data.local_uuid ?? data.id ?? data.server_id;
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error('Record is missing local_uuid, id, or server_id');
  }
  if (value.length > PUSH_FIELD_LIMITS.entityId) {
    throw new Error(`entityId too long (max ${PUSH_FIELD_LIMITS.entityId})`);
  }
  return value;
}

// ─── SQL splitting (quote-aware) ─────────────────────────────────

/**
 * Split raw SQL text into individual statements while respecting
 * single-quoted string literals (including '' escapes).
 * A naive split(';') breaks any statement whose VALUES contain a
 * semicolon inside a string (e.g. notes fields) and corrupts migrations.
 */
export function splitSqlStatements(sqlText: string): string[] {
  const statements: string[] = [];
  let current = '';
  let inString = false;
  for (let i = 0; i < sqlText.length; i++) {
    const ch = sqlText[i];
    if (inString) {
      current += ch;
      if (ch === "'") {
        if (sqlText[i + 1] === "'") {
          current += "'"; // escaped quote — consume both
          i++;
        } else {
          inString = false;
        }
      }
      continue;
    }
    if (ch === "'") {
      inString = true;
      current += ch;
      continue;
    }
    if (ch === ';') {
      const trimmed = current.trim();
      if (trimmed.length > 0) statements.push(trimmed);
      current = '';
      continue;
    }
    current += ch;
  }
  const trailing = current.trim();
  if (trailing.length > 0) statements.push(trailing);
  return statements;
}

/** Only single-statement INSERTs into whitelisted entity tables pass. */
const MIGRATE_INSERT_RE =
  /^INSERT\s+(?:OR\s+(?:REPLACE|IGNORE)\s+)?INTO\s+([A-Za-z_][A-Za-z0-9_]*)/i;
const MAX_MIGRATE_STATEMENTS = 200;

/**
 * Remove single-quoted string literals (quote-aware) so keyword scanning
 * only sees the structural SQL skeleton.
 */
function stripSqlStrings(stmt: string): string {
  let out = '';
  let inString = false;
  for (let i = 0; i < stmt.length; i++) {
    const ch = stmt[i];
    if (inString) {
      if (ch === "'") {
        if (stmt[i + 1] === "'") {
          i++; // escaped quote — stays inside the string
        } else {
          inString = false;
        }
      }
      continue; // drop literal content
    }
    if (ch === "'") {
      inString = true;
      out += ' ';
      continue;
    }
    out += ch;
  }
  return out;
}

/**
 * Forbidden keywords ANYWHERE after the target table name. This blocks
 * semicolon-free attack vectors that still start with a valid
 * `INSERT INTO <entity>`: WITH-clause data modification
 * (`INSERT INTO rooms WITH d AS (DELETE FROM users) SELECT …`),
 * subquery exfiltration (`VALUES ((SELECT password_hash FROM users))`),
 * ON CONFLICT DO UPDATE, etc. The migration client only ever sends
 * `INSERT [OR REPLACE] INTO t (cols) VALUES (literals…)` — literals only.
 * Word-boundary matching keeps identifiers like `updated_at`/`deleted_at`
 * safe (underscore is a word character, so no boundary after UPDATE/DELETE).
 */
const FORBIDDEN_TAIL_RE =
  /\b(SELECT|DELETE|UPDATE|DROP|ALTER|CREATE|ATTACH|DETACH|PRAGMA|WITH|VACUUM|REINDEX|UNION|JOIN|TRIGGER|VIEW|INDEX|INSERT)\b/i;

export function isAllowedMigrateStatement(stmt: string, validTargets: Set<string>): boolean {
  const match = MIGRATE_INSERT_RE.exec(stmt);
  const target = match?.[1];
  if (!match || !target || !validTargets.has(target)) return false;
  const skeleton = stripSqlStrings(stmt);
  const tail = skeleton.slice(match[0].length);
  return !FORBIDDEN_TAIL_RE.test(tail);
}

// ─── Capped request-body reader (P1 2026-09-24) ───────────────

/**
 * يقرأ جسم الطلب مع سقف مزدوج: الحجم المضغوط (بايتات الشبكة الفعلية،
 * حتى بغياب Content-Length) والحجم المفكوك بعد DecompressionStream.
 * يوقف القرار فور تجاوز أي سقف — gzip bomb صغير مضغوط بشكل عنيف لا
 * يستطيع تضخيم الذاكرة بلا حد. يُرجع نص الجسم أو يرمي PayloadTooLarge.
 */
export class PayloadTooLargeError extends Error {}

async function readBodyTextWithLimit(
  request: Request,
  maxCompressedBytes: number,
  maxDecompressedBytes: number
): Promise<string> {
  // الحد المضغوط: Content-Length إن وُجد — فحص مبكر بلا لمس الجسم.
  const contentLength = parseInt(request.headers.get('Content-Length') || '0', 10);
  if (contentLength > maxCompressedBytes) {
    throw new PayloadTooLargeError('compressed');
  }

  const isGzip = (request.headers.get('Content-Encoding') || '') === 'gzip';
  const rawBody = request.body;
  if (!rawBody) {
    return '';
  }

  // عدّاد بايتات الشبكة أثناء القراءة (يحمي حتى بلا Content-Length) —
  // مجموع جارٍ لا فحص لكل قطعة على حدة.
  let rawTotal = 0;
  const limitedRaw = new TransformStream<Uint8Array, Uint8Array>({
    transform(chunk, controller) {
      rawTotal += chunk.byteLength;
      if (rawTotal > maxCompressedBytes) {
        controller.error(new PayloadTooLargeError('compressed'));
        return;
      }
      controller.enqueue(chunk);
    },
  });

  const source = rawBody.pipeThrough(limitedRaw);
  if (!isGzip) {
    const buf = await new Response(source).arrayBuffer();
    if (buf.byteLength > maxDecompressedBytes) {
      throw new PayloadTooLargeError('decompressed');
    }
    return new TextDecoder().decode(buf);
  }

  // gzip: فك متدفق مع سقف على الحجم المفكوك — لا تحميل كامل قبل الفحص.
  const ds = new DecompressionStream('gzip');
  const decompressed = source.pipeThrough(ds);
  const reader = decompressed.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  const decoder = new TextDecoder();
  let text = '';
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxDecompressedBytes) {
      try {
        await reader.cancel();
      } catch {
        // stream already errored/closed — nothing to do
      }
      throw new PayloadTooLargeError('decompressed');
    }
    chunks.push(value);
  }
  // دمج نهائي واحد بعد اجتياز السقف.
  const merged = new Uint8Array(total);
  let offset = 0;
  for (const c of chunks) {
    merged.set(c, offset);
    offset += c.byteLength;
  }
  text = decoder.decode(merged);
  return text;
}

// ─── Pull Handler (Delta Sync) ────────────────────────────────

export async function handlePull(
  request: Request,
  db: Database,
  ctx: AuthContext
): Promise<Response> {
  try {
    const url = new URL(request.url);
    const cursorStr = url.searchParams.get('cursor') || '0';
    const cursor = Math.max(0, parseInt(cursorStr, 10) || 0);
    const entity = url.searchParams.get('entity');
    // ✅ Validate the entity BEFORE touching SQL — an unknown entity used to
    // reach the database and surface as an opaque 500 with SQL details.
    if (entity !== null && !isValidEntity(entity)) {
      return jsonResponse({ error: `Unknown entity: ${entity}` }, 400);
    }
    const limitStr = url.searchParams.get('limit') || '200';
    // True [1, MAX_PULL_BATCH_SIZE] clamp: 0 and negatives → 1, NaN →
    // 200, anything larger → 500. (The old `parseInt(...) || 200` let
    // limit=0 slip to the 200 default and return a full page for a
    // nonsense request.)
    const parsedLimit = parseInt(limitStr, 10);
    const limit = Math.min(
      Math.max(Number.isFinite(parsedLimit) ? parsedLimit : 200, 1),
      MAX_PULL_BATCH_SIZE,
    );
    // Echo filter (plan 2.5): skip rows this device already has locally.
    const excludeDevice = url.searchParams.get('exclude_device') || undefined;
    // ✅ مراجعة #1: مسح تقارب الحذفيات — tombstones_only=1 يجلب الصفوف
    //    المحذوفة فقط (نافذة واحدة رخيصة) ليطبّقها العميل كحذف محلي
    //    ما فاته أثناء نافذة العقد القديم الذي كان يفلترها.
    const tombstonesOnly =
      url.searchParams.get('tombstones_only') === '1';
    // ✅ (2026-09-10) مؤشر تقدم السحب الكامل — العميل الكامل فقط يطلب
    //    remaining (COUNT فهرسي batch واحد)؛ الدلتا بلا كلفة إضافية.
    const includeRemaining =
      url.searchParams.get('include_remaining') === '1';

    // ✅ Self-healing data repair is an explicit, one-time maintenance pass.
    // Ordinary delta pulls must not scan every entity table just to discover
    // that no legacy millisecond timestamps remain.
    //
    // ✅ P1 (2026-09-24) فصل الكتابة عن GET: الصيانة انتقلت إلى
    // POST /api/admin/sync/normalize-timestamps (admin فقط). معامل الـ GET
    // يبقى للتوافق مع إصدارات العميل الحالية التي تمرّره في السحب الكامل،
    // لكنه يُنفَّذ الآن لـ admin/manager فقط؛ بقية الأدوار تحصل على pull
    // طبيعي مع normalization:null (الشكل نفسه الذي يعود عند فشل الصيانة —
    // العميل يتحمّله أصلاً). الإصلاح الذاتي داخل pullChanges (إعادة ختم
    // الصفوف التي تلمسها الصفحة فعلاً) يعمل للجميع بلا استثناء.
    const normalizeTimestamps =
      url.searchParams.get('normalize_timestamps') === '1';
    const roleAllowsMaintenance = ctx.role === 'admin' || ctx.role === 'manager';
    let normalization: Awaited<ReturnType<Database['normalizeTimestamps']>> | null = null;
    if (normalizeTimestamps && roleAllowsMaintenance) {
      try {
        normalization = await db.normalizeTimestamps(500);
      } catch (err) {
        console.error('[SYNC/PULL] normalization failed (pull continues):', err);
      }
    }

    const result = await db.pullChanges(
      entity,
      cursor,
      limit,
      excludeDevice,
      tombstonesOnly,
      includeRemaining
    );

    return jsonResponse({
      changes: result.changes,
      cursor: result.cursor.toString(),
      has_more: result.has_more,
      remaining: result.remaining,
      errors: result.errors,
      normalization,
      server_time: Math.floor(Date.now() / 1000),
    });
  } catch (err) {
    console.error('[SYNC/PULL] Error:', err);
    return jsonResponse({ error: 'Pull failed', detail: String(err) }, 500);
  }
}

// ─── Push Handler (Outbox processing) ─────────────────────────

export async function handlePush(
  request: Request,
  db: Database,
  ctx: AuthContext,
  broadcast?: RealtimeBroadcast
): Promise<Response> {
  try {
    // ─── P1 (2026-09-24) سقف مزدوج: مضغوط + مفكوك ───────────
    // كان الاعتماد على Content-Length فقط — يفشل عندما يحذف العميل
    // الترويسة أو مع gzip مضغوط بشدة (gzip bomb). القارئ المحدود يعدّ
    // بايتات الشبكة الفعلية ويوقف الفك فور تجاوز الحجم المفكوك 5MB.
    let bodyText: string;
    try {
      bodyText = await readBodyTextWithLimit(request, MAX_PAYLOAD_SIZE, MAX_PAYLOAD_SIZE);
    } catch (err) {
      if (err instanceof PayloadTooLargeError) {
        return jsonResponse({ error: 'Payload too large', scope: err.message }, 413);
      }
      throw err;
    }

    const body = JSON.parse(bodyText) as { operations: PushOperation[] };

    if (!body.operations || !Array.isArray(body.operations)) {
      return jsonResponse({ error: 'operations array required' }, 400);
    }

    if (body.operations.length > MAX_BATCH_SIZE) {
      return jsonResponse({ error: `Max ${MAX_BATCH_SIZE} operations per batch` }, 400);
    }

    const results: Array<{
      idempotencyKey: string;
      success: boolean;
      entity?: string;
      entityId?: string;
      error?: string;
      skipped?: boolean;
      /** ✅ (fix M4) تصنيف الرفض — يتيح للعميل فصل الأخطاء الدائمة عن المؤقتة
       * ✅ (F1 2026-09-22) 'deleted': التعديل خسر عمداً لصالح tombstone
       * (عقد delete-vs-update) — نجاح شكلي بلا تطبيق محتوى */
      status?: 'validation_error' | 'conflict' | 'internal_error' | 'deleted';
    }> = [];

    // Distinct entities touched by SUCCESSFUL, non-skipped ops — one change
    // event per entity (entity-level signal; clients answer with a delta
    // pull, so per-row granularity is unnecessary). Skipped ops are exact
    // replays already broadcast with their original batch.
    const touched = new Map<
      string,
      { entityId: string; deviceId: string; operation: string }
    >();

    for (const op of body.operations) {
      try {
        // ─── Validate ──────────────────────────────────────────
        const validationError = validatePushOperation(op);
        if (validationError) {
          results.push({
            idempotencyKey: op.idempotencyKey || 'unknown',
            success: false,
            // ✅ (fix M4) العميل كان يقرأ status ولا يجده → الرفض الدائم يُعاد
            // حتى عتبة dead-letter بلا فائدة. الآن يُعلَم صراحةً.
            status: 'validation_error',
            error: validationError,
          });
          continue;
        }

        // ─── حارس يتيم الموظفين (قراءة فقط — قبل الخطة الذرية) ──
        // ✅ (2026-09-21) «لفصل موظف استخدم «إنهاء الخدمة» من التطبيق».
        // رفض دائم (validation_error): العميل يضعه في dead-letter فوراً
        // بدل إعادة دفعه للأبد (عقد fix M4). حذف موظف بلا أي تاريخ
        // مالي يبقى ممكناً (تنظيف إدخال خاطئ حديث).
        if (op.operation === 'delete' && op.entity === 'employees') {
          const candidateId = (op.data.local_uuid ?? op.data.id ?? op.data.server_id) as string | number | undefined;
          if (candidateId !== undefined && candidateId !== null && String(candidateId).length > 0) {
            const history = await db.employeeFinancialHistoryCount(String(candidateId));
            const historyTotal = history
              ? Object.values(history).reduce((a, b) => a + b, 0)
              : 0;
            if (historyTotal > 0) {
              results.push({
                idempotencyKey: op.idempotencyKey || 'unknown',
                success: false,
                status: 'validation_error',
                error:
                  `حذف الموظف مرفوض: يشير إليه تاريخ مالي ` +
                  `(${historyTotal} سجل — ${JSON.stringify(history)}) — ` +
                  `استخدم «إنهاء الخدمة» من التطبيق (تغيير الحالة ` +
                  `فقط)؛ الحذف يتيّم تاريخه المالي على بقية الأجهزة`,
              });
              continue;
            }
          }
        }

        // ─── P0 (2026-09-24): تنفيذ ذري — claim + mutation + response ──
        // في D1 batch واحدة (transaction). كان التدفق القديم
        // checkIdempotency → mutation → saveIdempotency ثلاث رحلات
        // مستقلة: جهازان بنفس المفتاح كانا يجتازان الفحص معاً وينفّذان
        // الـ mutation مرتين. الآن:
        //   - مفتاح مكرر → UNIQUE في أول عبارة → تراجع كامل للدفعة →
        //     إعادة النتيجة السابقة (skipped:true) — exactly-once.
        //   - فشل الـ mutation → تراجع الـ claim معه (لا سجل يتيم).
        //   - فشل الحفظ ⇒ لا mutation أصلاً (نفس الوحدة الذرية).
        const atomic = await db.executeOperationAtomically(op, opDeviceId(op, ctx));

        if (atomic.kind === 'failed') {
          results.push({
            idempotencyKey: op.idempotencyKey,
            success: false,
            error: atomic.error,
          });
          continue;
        }

        if (atomic.kind === 'replayed') {
          // إعادة إرسال بنفس المفتاح بعد timeout/انقطاع أو سباق مكرر:
          // نفس النتيجة السابقة بلا تنفيذ ثانٍ (ولا بث — الكيان بُثّ
          // مع دفعته الأصلية).
          const saved = (atomic.response ?? {}) as { entityId?: string; status?: string };
          results.push({
            idempotencyKey: op.idempotencyKey,
            success: true,
            skipped: true,
            entity: op.entity,
            entityId: saved.entityId,
            // ✅ عقد F1: replay حالة 'deleted' يعود للعميل كي يوقف
            // إعادة المحاولة ويلتزم بالحذف.
            ...(saved.status === 'deleted' ? { status: 'deleted' as const } : {}),
          });
          continue;
        }

        if (atomic.kind === 'noop') {
          // خسارة سباق optimistic guard / صف مفقود — يُعاد الصف الحالي
          // كنجاح بلا تغيير (نفس شكل رفض LWW القديم)، والتعارض مُسجَّل.
          results.push({
            idempotencyKey: op.idempotencyKey,
            success: true,
            entity: op.entity,
            entityId: atomic.entityId,
          });
          continue;
        }

        // kind === 'applied'
        const appliedStatus = (atomic.response as { status?: string } | null)?.status;
        results.push({
          idempotencyKey: op.idempotencyKey,
          success: true,
          // ✅ (F1 2026-09-22) التعديل خسر عمداً لصالح tombstone —
          // status:'deleted' يوقف إعادة محاولة العميل بوعي.
          ...(appliedStatus === 'deleted' ? { status: 'deleted' as const } : {}),
          entity: op.entity,
          entityId: atomic.entityId,
        });
        if (appliedStatus !== 'deleted' && !touched.has(op.entity)) {
          touched.set(op.entity, {
            entityId: atomic.entityId,
            deviceId: opDeviceId(op, ctx),
            operation: op.operation,
          });
        }
      } catch (err) {
        console.error(`[SYNC/PUSH] Operation failed: ${op.idempotencyKey}`, err);
        results.push({
          idempotencyKey: op.idempotencyKey,
          success: false,
          error: String(err),
        });
      }
    }

    // ─── Realtime broadcast (plan phase 3) ────────────────────
    // Best-effort and AFTER the push is durably recorded: a broadcast
    // failure must never fail the push (realtime is an optimization —
    // devices still converge via auto-sync/delta cursor).
    if (broadcast && touched.size > 0) {
      try {
        await Promise.all(
          [...touched.entries()].map(([entity, info]) =>
            broadcast({
              type: 'change',
              entity,
              entityId: info.entityId,
              operation: info.operation,
              deviceId: info.deviceId,
              timestamp: Date.now(),
            })
          )
        );
      } catch (err) {
        console.error('[SYNC/PUSH] Realtime broadcast failed (push unaffected):', err);
      }
    }

    const successCount = results.filter((r) => r.success).length;
    const failureCount = results.length - successCount;

    return jsonResponse({
      results,
      summary: {
        total: results.length,
        success: successCount,
        failed: failureCount,
        skipped: results.filter((r) => r.skipped).length,
      },
      server_time: Math.floor(Date.now() / 1000),
    });
  } catch (err) {
    console.error('[SYNC/PUSH] Error:', err);
    return jsonResponse({ error: 'Push failed', detail: String(err) }, 500);
  }
}

// ─── Sync Log Handler ─────────────────────────────────────────

export async function handleSyncLog(
  request: Request,
  db: Database,
  ctx: AuthContext
): Promise<Response> {
  try {
    const url = new URL(request.url);
    // ✅ (fix W-min2) منع القيم السالبة: LIMIT سالب في SQLite = بلا حدّ
    const limit = Math.max(1, Math.min(parseInt(url.searchParams.get('limit') || '50', 10) || 50, 200));
    const offset = parseInt(url.searchParams.get('offset') || '0', 10);

    // Note: sync log reads go through the typed Database layer
    const logs = await db.getSyncLog(limit, offset);

    return jsonResponse({
      logs,
      limit,
      offset,
    });
  } catch (err) {
    console.error('[SYNC/LOG] Error:', err);
    return jsonResponse({ error: 'Failed to fetch sync log', detail: String(err) }, 500);
  }
}

// ─── Migration Handler (raw SQL batch insert) ─────────────────
// Accepts raw SQL INSERT statements (gzipped) and executes them
// directly via D1 batch API. This bypasses the per-operation validation
// loop and uses D1's native batch insert for ~10x speed improvement.
//
// ✅ P1 (2026-09-24) توثيق عزل المسار: هذا المسار migration لمرة واحدة
// وليس sync push عادياً. `INSERT OR REPLACE` مقصود هنا (يستعيض عن الصف
// كاملاً بقيم الترحيل) ويُعتمد عليه لإعادة المحاولة الآمنة، ولا يمس
// مسار /sync/push الذي يفرض version/sync-fields الخادمية عبر
// createRecord/updateRecord. version الملوثة من الترحيل تُطبَّع بعد كل
// دفعة عبر sanitizeMigrateVersions (نفس عتبة MAX_SANE_VERSION).
//
// Expected request:
//   POST /api/sync/migrate
//   Headers: Content-Encoding: gzip, Content-Type: application/sql
//   Body: gzipped SQL string like:
//     INSERT OR IGNORE INTO rooms (local_uuid, room_number, ...) VALUES
//       ('uuid1', '101', ...),
//       ('uuid2', '102', ...),
//       ...;
//     INSERT OR IGNORE INTO bookings (...) VALUES (...);
//
// Response: { success: true, rowsInserted: N, errors: [...] }

export async function handleMigrate(
  request: Request,
  db: Database,
  ctx: AuthContext
): Promise<Response> {
  try {
    // ─── Size limit: allow up to 10MB for migration batches ───
    // ✅ P1 (2026-09-24) سقف مزدوج موحّد عبر القارئ المحدود: مضغوط
    // (ببايتات الشبكة الفعلية حتى بغياب Content-Length) + مفكوك —
    // نفس حماية gzip bomb في /sync/push.
    let sqlText: string;
    try {
      sqlText = await readBodyTextWithLimit(
        request,
        10 * 1024 * 1024,
        10 * 1024 * 1024
      );
    } catch (err) {
      if (err instanceof PayloadTooLargeError) {
        return jsonResponse(
          { error: `Payload too large (max 10MB ${err.message})` },
          413
        );
      }
      throw err;
    }

    if (!sqlText || sqlText.trim().length === 0) {
      return jsonResponse({ error: 'Empty SQL body' }, 400);
    }

    // ─── Security: per-statement INSERT whitelist ─────────────
    // The old check (first statement starts with INSERT + `;\s*KEYWORD`
    // regex) was bypassable with SQL comments: `;/**/DELETE FROM users`
    // slipped past the regex and was then executed. Every statement is now
    // individually validated to be a plain INSERT into a whitelisted entity
    // table — any comment or other prefix fails the regex and the whole
    // batch is rejected BEFORE anything executes.
    const validTargets = new Set<string>(SYNC_ENTITY_TABLES);
    const statements = splitSqlStatements(sqlText);

    if (statements.length === 0) {
      return jsonResponse({ error: 'Empty SQL body' }, 400);
    }
    if (statements.length > MAX_MIGRATE_STATEMENTS) {
      return jsonResponse(
        { error: `Too many statements (max ${MAX_MIGRATE_STATEMENTS} per batch)` },
        400
      );
    }

    // ✅ (ملحق المراجعة 2026-09-17): جمع الجداول الملموسة أثناء التحقق —
    // تُستخدم لاحقاً لتمريرة تطهير version بعد التنفيذ (انظر أسفل).
    const touchedTables = new Set<string>();
    for (let i = 0; i < statements.length; i++) {
      const stmt = statements[i] ?? '';
      if (!isAllowedMigrateStatement(stmt, validTargets)) {
        return jsonResponse(
          {
            error:
              'Only INSERT [OR REPLACE / IGNORE] INTO <entity> (cols) VALUES (literals) statements are allowed',
            statement_index: i + 1,
          },
          400
        );
      }
      const target = MIGRATE_INSERT_RE.exec(stmt)?.[1];
      if (target) touchedTables.add(target);
    }

    // ─── Execute via D1 batch API in atomic chunks (plan 2.6) ─
    // Each chunk of ≤50 statements runs through db.batch() which is
    // ATOMIC in D1: either the whole chunk commits or none of it does.
    // Per-statement run() previously allowed partial imports (half a
    // multi-row INSERT committed) with no way for the client to know
    // which rows landed. On chunk failure we stop immediately — every
    // statement is INSERT [OR IGNORE/REPLACE] (idempotent), so the
    // client can safely retry the whole batch.
    const MIGRATE_CHUNK_SIZE = 50;
    const d1Db = db.raw;
    let rowsInserted = 0;
    let statementsExecuted = 0;
    const errors: string[] = [];

    console.log(`[MIGRATE] Received ${statements.length} SQL statements, ` +
      `${sqlText.length} bytes decompressed`);

    for (let start = 0; start < statements.length; start += MIGRATE_CHUNK_SIZE) {
      const chunk = statements.slice(start, start + MIGRATE_CHUNK_SIZE);
      try {
        const results = await d1Db.batch(
          chunk.map((stmt) => d1Db.prepare(stmt + ';'))
        );
        for (const result of results) {
          // batch() returns one result per statement with meta.changes
          const meta = (result as { meta?: { changes?: number } }).meta;
          if (meta && typeof meta.changes === 'number') {
            rowsInserted += meta.changes;
          }
        }
        statementsExecuted += chunk.length;
      } catch (err) {
        const errMsg = String(err).slice(0, 300);
        const chunkNo = Math.floor(start / MIGRATE_CHUNK_SIZE) + 1;
        errors.push(
          `Chunk ${chunkNo} (statements ${start + 1}-${start + chunk.length}) aborted atomically: ${errMsg}`
        );
        console.error(`[MIGRATE] Chunk ${chunkNo} failed:`, errMsg);
        break; // fail-fast — retry is safe (idempotent INSERTs)
      }
    }

    console.log(`[MIGRATE] Done: ${rowsInserted} rows inserted, ` +
      `${statementsExecuted}/${statements.length} statements executed, ` +
      `${errors.length} errors`);

    // ✅ Advance the sync clock past migrated timestamps so subsequent
    // server-side allocations remain strictly greater than migrated rows
    // (keeps the integer pull cursor lossless after bulk import).
    try {
      await db.advanceSyncClock(await db.maxUpdatedAtAcrossEntities());
    } catch (clockErr) {
      console.warn('[MIGRATE] sync_clock advance failed:', clockErr);
    }

    // ✅ (ملحق المراجعة 2026-09-17): تمريرة تطهير بعد الترحيل —
    // INSERT OR REPLACE يحمل version العميل حرفياً (دليل حي: rooms
    // 1e12+n، وإعادة حقن 9999 في payments بتاريخ 2026-09-17 01:27 UTC
    // بلا أثر في sync_log). القيم فوق MAX_SANE_VERSION تُعاد إلى 1
    // بعد كل دفعة كي لا يُعاد تلويث الصفوف المصحَّحة يدوياً. الفشل هنا
    // غير فادح (الحارس في updateRecord يلتقطها لاحقاً عند أول تعديل).
    let versionsSanitized = 0;
    if (touchedTables.size > 0) {
      try {
        versionsSanitized = await db.sanitizeMigrateVersions([
          ...touchedTables,
        ]);
        if (versionsSanitized > 0) {
          console.warn(
            `[MIGRATE] sanitized ${versionsSanitized} row(s) with polluted version (>1e6) across ${touchedTables.size} table(s)`
          );
        }
      } catch (sanErr) {
        console.warn('[MIGRATE] version sanitize pass failed:', sanErr);
      }
    }

    return jsonResponse({
      success: errors.length === 0,
      rowsInserted,
      statementsExecuted,
      statementsTotal: statements.length,
      abortedEarly: statementsExecuted < statements.length,
      versionsSanitized,
      errors: errors.slice(0, 20), // Limit errors to first 20 to avoid huge response
      totalErrors: errors.length,
      server_time: Math.floor(Date.now() / 1000),
    });
  } catch (err) {
    console.error('[MIGRATE] Error:', err);
    return jsonResponse(
      { error: 'Migration failed', detail: String(err) },
      500
    );
  }
}

// ─── Conflicts Handler ────────────────────────────────────────

export async function handleConflicts(
  request: Request,
  db: Database,
  ctx: AuthContext
): Promise<Response> {
  try {
    const url = new URL(request.url);
    // ✅ (fix W-min2) منع القيم السالبة: LIMIT سالب في SQLite = بلا حدّ
    const limit = Math.max(1, Math.min(parseInt(url.searchParams.get('limit') || '50', 10) || 50, 200));

    // Note: conflicts reads go through the typed Database layer
    const conflicts = await db.getConflicts(limit);

    return jsonResponse({
      conflicts,
      limit,
    });
  } catch (err) {
    console.error('[SYNC/CONFLICTS] Error:', err);
    return jsonResponse({ error: 'Failed to fetch conflicts', detail: String(err) }, 500);
  }
}

// ─── Helper ───────────────────────────────────────────────────

// ✅ P2 (2026-09-24) توحيد CORS: كان هذا الملف يرسل '*' دائماً بينما
// index.ts يستخدم env.CORS_ORIGIN. المصدر الآن واحد — index.ts يضبطه
// مرة لكل نشر (قيمة ثابتة لكل deployment) فتتطابق رؤوس كل الاستجابات.
// القيمة الافتراضية '*' تحافظ على سلوك الاستدعاءات المباشرة في الاختبارات
// (CORS لا يؤثر على عملاء Dart/Android أصلاً).
let syncCorsOrigin = '*';

export function setSyncCorsOrigin(origin: string | undefined): void {
  if (typeof origin === 'string' && origin.length > 0) {
    syncCorsOrigin = origin;
  }
}

function jsonResponse(data: unknown, status: number = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': syncCorsOrigin,
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    },
  });
}
