// ═══════════════════════════════════════════════════════════════
//  sync-lock.ts — Durable Object for Distributed Sync Locks
//
//  ✅ P1 (2026-09-24) Coordination-only contract:
//    SyncLockDO   = acquire / release / status  (lock tokens)
//    RealtimeHubDO = WebSocket + presence + change notifications
//
//  Lock tokens: every granted lock carries an unguessable
//  crypto.randomUUID() lockId stored with the lock record. Release
//  requires deviceId + lockId — knowing the deviceId alone (or
//  guessing the old `${lockKey}:${deviceId}:${now}` pattern) can no
//  longer release someone else's lock.
//
//  ✅ (2026-09-17→24) Realtime notifications moved OUT of this class
//  into the dedicated RealtimeHubDO (src/realtime-hub.ts) on the
//  WebSocket Hibernation API. The legacy in-memory WebSocket/session/
//  broadcast/cursor code was removed after a full reference audit:
//  production routes (/api/realtime, push broadcasts) target
//  RealtimeHubDO; the only references to the legacy paths were inside
//  this file's own tests (updated accordingly).
//
//  ⚠️ Correctness note: this DO is COORDINATION ONLY. D1 transactions
//  + idempotency claims + optimistic concurrency (database.ts) are the
//  actual correctness guarantees; lock loss never corrupts data.
// ═══════════════════════════════════════════════════════════════

export interface SyncLockRequest {
  deviceId: string;
  entity: string;
  entityId: string;
  operation: 'create' | 'update' | 'delete';
}

export interface SyncLockResponse {
  granted: boolean;
  lockId?: string;
  heldBy?: string;
  expiresAt?: number;
}

/**
 * رسالة البث اللحظي — العقد المشترك بين Worker→RealtimeHubDO والعملاء.
 * ⚠️ البيانات الكاملة للصف لا تُرسل عبر WebSocket أبداً: الرسالة
 * إشعار إبطال (invalidation) فقط — العملاء يجيبون بـ /api/sync/pull
 * ويحصلون على الدلتا الموثوقة من D1 (مصدر الحقيقة الوحيد).
 */
export interface RealtimeMessage {
  type: 'change' | 'lock' | 'unlock' | 'presence';
  entity: string;
  entityId: string;
  operation?: string;
  deviceId?: string;
  timestamp: number;
  data?: unknown;
}

/** مدة القفل الافتراضية (TTL) — إعادة التقييم: coordination فقط،
 *  لا تصحّح بيانات، فانتهاء القفل ليس خطر سلامة. */
const LOCK_TTL_MS = 30_000;

interface StoredLock {
  deviceId: string;
  lockId: string;
  expiresAt: number;
}

// ═══════════════════════════════════════════════════════════════
//  Durable Object: SyncLockDO
// ═══════════════════════════════════════════════════════════════

export class SyncLockDO {
  state: DurableObjectState;

  constructor(state: DurableObjectState) {
    this.state = state;
  }

  // ─── HTTP Handler (lock acquire/release/status) ────────────

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    // ─── Lock acquire ───────────────────────────────────────
    if (path === '/lock' && request.method === 'POST') {
      return this.handleLockAcquire(request);
    }

    // ─── Lock release ───────────────────────────────────────
    if (path === '/unlock' && request.method === 'POST') {
      return this.handleLockRelease(request);
    }

    // ─── Lock status ────────────────────────────────────────
    if (path === '/status' && request.method === 'GET') {
      return this.handleLockStatus();
    }

    return new Response('Not found', { status: 404 });
  }

  // ─── Lock Acquire ──────────────────────────────────────────

  async handleLockAcquire(request: Request): Promise<Response> {
    const body = (await request.json()) as SyncLockRequest;
    // ✅ Validate input — a missing field used to silently create a lock on
    // the key "undefined:undefined", blocking the real entity for 30s.
    if (!body || typeof body.deviceId !== 'string' || body.deviceId.length === 0 ||
        typeof body.entity !== 'string' || body.entity.length === 0 ||
        typeof body.entityId !== 'string' || body.entityId.length === 0) {
      return Response.json(
        { granted: false, error: 'deviceId, entity, and entityId are required' },
        { status: 400 }
      );
    }
    const lockKey = `${body.entity}:${body.entityId}`;
    const now = Date.now();

    const existingLock = (await this.state.storage.get<StoredLock>(
      `lock:${lockKey}`
    )) as StoredLock | undefined;

    const grant = async (): Promise<Response> => {
      // ✅ P1: token حقيقي غير قابل للتخمين — crypto.randomUUID() بدل
      // `${lockKey}:${deviceId}:${now}` الذي كان قابلاً للاستنتاج.
      const lockId = crypto.randomUUID();
      const expiresAt = now + LOCK_TTL_MS;
      await this.state.storage.put(`lock:${lockKey}`, {
        deviceId: body.deviceId,
        lockId,
        expiresAt,
      } satisfies StoredLock);
      return Response.json({
        granted: true,
        lockId,
        expiresAt,
      } as SyncLockResponse);
    };

    if (existingLock) {
      // Lock expired? Take it over
      if (existingLock.expiresAt < now) {
        return grant();
      }

      // Same device? Extend the lock (new token — the old one expires
      // with it; coordination-only so no correctness impact).
      if (existingLock.deviceId === body.deviceId) {
        return grant();
      }

      // Lock held by another device
      return Response.json({
        granted: false,
        heldBy: existingLock.deviceId,
        expiresAt: existingLock.expiresAt,
      } as SyncLockResponse);
    }

    // No existing lock — acquire it
    return grant();
  }

  // ─── Lock Release ──────────────────────────────────────────

  async handleLockRelease(request: Request): Promise<Response> {
    const body = (await request.json()) as (SyncLockRequest & { lockId?: string });
    if (!body || typeof body.deviceId !== 'string' || body.deviceId.length === 0 ||
        typeof body.entity !== 'string' || body.entity.length === 0 ||
        typeof body.entityId !== 'string' || body.entityId.length === 0) {
      return Response.json(
        { released: false, error: 'deviceId, entity, and entityId are required' },
        { status: 400 }
      );
    }
    // ✅ P1: release يتطلب deviceId + lockId معاً — معرفة deviceId فقط
    // (أو تخمين التوكن القديم) لا تكفي لفك قفل جهاز آخر.
    if (typeof body.lockId !== 'string' || body.lockId.length === 0) {
      return Response.json(
        { released: false, reason: 'lockId is required' },
        { status: 400 }
      );
    }
    const lockKey = `${body.entity}:${body.entityId}`;

    const existingLock = (await this.state.storage.get<StoredLock>(
      `lock:${lockKey}`
    )) as StoredLock | undefined;

    if (
      existingLock &&
      existingLock.deviceId === body.deviceId &&
      existingLock.lockId === body.lockId
    ) {
      await this.state.storage.delete(`lock:${lockKey}`);
      return Response.json({ released: true });
    }

    return Response.json({ released: false, reason: 'Not lock owner' }, { status: 409 });
  }

  // ─── Lock Status ───────────────────────────────────────────

  async handleLockStatus(): Promise<Response> {
    // List all active locks — keys are returned WITHOUT the internal
    // `lock:` storage prefix so clients see the natural
    // `<entity>:<entityId>` identity. lockId is intentionally NOT echoed
    // here (status is an ops view, not a release credential).
    const locks: Array<{ key: string; deviceId: string; expiresAt: number }> = [];
    const entries = await this.state.storage.list<StoredLock>({
      prefix: 'lock:',
    });

    for (const [key, value] of entries) {
      if (value.expiresAt > Date.now()) {
        locks.push({
          key: key.slice('lock:'.length),
          deviceId: value.deviceId,
          expiresAt: value.expiresAt,
        });
      } else {
        // Clean up expired locks
        await this.state.storage.delete(key);
      }
    }

    return Response.json({ locks, count: locks.length });
  }
}
