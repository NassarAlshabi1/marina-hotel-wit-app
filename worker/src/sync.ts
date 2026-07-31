// ═══════════════════════════════════════════════════════════════
//  sync.ts — Sync Pull/Push Handlers
//  Delta sync + idempotent push + conflict resolution (LWW + VC)
// ═══════════════════════════════════════════════════════════════

import type { Database, PushOperation, SyncRecord } from './database';
import type { AuthContext } from './auth';

// ─── Validation ───────────────────────────────────────────────

const MAX_BATCH_SIZE = 100;
const MAX_PAYLOAD_SIZE = 5 * 1024 * 1024; // 5MB

function validatePushOperation(op: PushOperation): string | null {
  if (!op.idempotencyKey || typeof op.idempotencyKey !== 'string') {
    return 'idempotencyKey is required';
  }
  if (!op.entity || typeof op.entity !== 'string') {
    return 'entity is required';
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
  if (typeof op.updatedAt !== 'number' || op.updatedAt < 0) {
    return 'updatedAt must be a positive number';
  }
  return null;
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
    const cursor = parseInt(cursorStr, 10) || 0;
    const entity = url.searchParams.get('entity');
    const limitStr = url.searchParams.get('limit') || '200';
    const limit = Math.min(Math.max(parseInt(limitStr, 10) || 200, 1), MAX_BATCH_SIZE);

    const result = await db.pullChanges(entity, cursor, limit);

    return jsonResponse({
      changes: result.changes,
      cursor: result.cursor.toString(),
      has_more: result.has_more,
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
  ctx: AuthContext
): Promise<Response> {
  try {
    // ─── Size limit check ────────────────────────────────────
    const contentLength = parseInt(request.headers.get('Content-Length') || '0', 10);
    if (contentLength > MAX_PAYLOAD_SIZE) {
      return jsonResponse({ error: 'Payload too large' }, 413);
    }

    const body = await request.json() as { operations: PushOperation[] };

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
    }> = [];

    for (const op of body.operations) {
      try {
        // ─── Validate ──────────────────────────────────────────
        const validationError = validatePushOperation(op);
        if (validationError) {
          results.push({
            idempotencyKey: op.idempotencyKey || 'unknown',
            success: false,
            error: validationError,
          });
          continue;
        }

        // ─── Idempotency check ─────────────────────────────────
        const idempResult = await db.checkIdempotency(op.idempotencyKey);
        if (idempResult.exists) {
          results.push({
            idempotencyKey: op.idempotencyKey,
            success: true,
            skipped: true,
            entity: op.entity,
            entityId: (idempResult.response as { entityId?: string })?.entityId,
          });
          continue;
        }

        // ─── Execute operation ─────────────────────────────────
        let record: SyncRecord | { deleted: boolean };

        switch (op.operation) {
          case 'create':
            record = await db.createRecord(op.entity, op.data, ctx.deviceId);
            break;
          case 'update':
            record = await db.updateRecord(
              op.entity,
              (op.data.local_uuid as string) || (op.data.id as string),
              op.data,
              op.vectorClock,
              ctx.deviceId
            );
            break;
          case 'delete':
            record = await db.deleteRecord(
              op.entity,
              (op.data.local_uuid as string) || (op.data.id as string),
              ctx.deviceId
            );
            break;
          default:
            throw new Error(`Unknown operation: ${op.operation}`);
        }

        // ─── Save idempotency ──────────────────────────────────
        const entityId = (record as SyncRecord).local_uuid || (op.data.local_uuid as string) || (op.data.id as string) || 'unknown';
        const responsePayload = { entity: op.entity, entityId, operation: op.operation };
        await db.saveIdempotency(op.idempotencyKey, op.entity, op.operation, entityId, responsePayload);

        results.push({
          idempotencyKey: op.idempotencyKey,
          success: true,
          entity: op.entity,
          entityId,
        });
      } catch (err) {
        console.error(`[SYNC/PUSH] Operation failed: ${op.idempotencyKey}`, err);
        results.push({
          idempotencyKey: op.idempotencyKey,
          success: false,
          error: String(err),
        });
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
    const limit = Math.min(parseInt(url.searchParams.get('limit') || '50', 10), 200);
    const offset = parseInt(url.searchParams.get('offset') || '0', 10);

    // Note: sync_log queries use the D1 prepare/bind pattern (SQL injection safe)
    const stmt = (db as unknown as { db: { prepare: (sql: string) => { bind: (...args: unknown[]) => { all: () => Promise<{ results: unknown[] }> } } } }).db
      .prepare('SELECT * FROM sync_log ORDER BY timestamp DESC LIMIT ? OFFSET ?')
      .bind(limit, offset);
    const result = await stmt.all();

    return jsonResponse({
      logs: result.results,
      limit,
      offset,
    });
  } catch (err) {
    console.error('[SYNC/LOG] Error:', err);
    return jsonResponse({ error: 'Failed to fetch sync log', detail: String(err) }, 500);
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
    const limit = Math.min(parseInt(url.searchParams.get('limit') || '50', 10), 200);

    const stmt = (db as unknown as { db: { prepare: (sql: string) => { bind: (...args: unknown[]) => { all: () => Promise<{ results: unknown[] }> } } } }).db
      .prepare('SELECT * FROM sync_conflicts ORDER BY created_at DESC LIMIT ?')
      .bind(limit);
    const result = await stmt.all();

    return jsonResponse({
      conflicts: result.results,
      limit,
    });
  } catch (err) {
    console.error('[SYNC/CONFLICTS] Error:', err);
    return jsonResponse({ error: 'Failed to fetch conflicts', detail: String(err) }, 500);
  }
}

// ─── Helper ───────────────────────────────────────────────────

function jsonResponse(data: unknown, status: number = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    },
  });
}
