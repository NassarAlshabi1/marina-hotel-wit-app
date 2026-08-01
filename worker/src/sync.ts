// ═══════════════════════════════════════════════════════════════
//  sync.ts — Sync Pull/Push Handlers
//  Delta sync + idempotent push + conflict resolution (LWW + VC)
// ═══════════════════════════════════════════════════════════════

import type { D1Database } from '@cloudflare/workers-types';
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
    // ─── Size limit check (use compressed size if gzip) ─────
    const contentLength = parseInt(request.headers.get('Content-Length') || '0', 10);
    if (contentLength > MAX_PAYLOAD_SIZE) {
      return jsonResponse({ error: 'Payload too large' }, 413);
    }

    // ─── Decompress gzip if Content-Encoding: gzip ──────────
    // Cloudflare Workers automatically decompresses gzip responses, but
    // for REQUESTS we need to handle it manually using DecompressionStream.
    let bodyText: string;
    const contentEncoding = request.headers.get('Content-Encoding') || '';

    if (contentEncoding === 'gzip') {
      // Use the native DecompressionStream API (supported in Workers runtime)
      const ds = new DecompressionStream('gzip');
      const decompressedStream = request.body!.pipeThrough(ds);
      const decompressedBuffer = await new Response(decompressedStream).arrayBuffer();
      bodyText = new TextDecoder().decode(decompressedBuffer);
    } else {
      bodyText = await request.text();
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

// ─── Migration Handler (raw SQL batch insert) ─────────────────
// Accepts raw SQL INSERT statements (gzipped) and executes them
// directly via D1 batch API. This bypasses the per-operation validation
// loop and uses D1's native batch insert for ~10x speed improvement.
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
    const contentLength = parseInt(
      request.headers.get('Content-Length') || '0',
      10
    );
    if (contentLength > 10 * 1024 * 1024) {
      return jsonResponse({ error: 'Payload too large (max 10MB)' }, 413);
    }

    // ─── Decompress gzip if present ───────────────────────────
    let sqlText: string;
    const contentEncoding = request.headers.get('Content-Encoding') || '';

    if (contentEncoding === 'gzip') {
      const ds = new DecompressionStream('gzip');
      const decompressedStream = request.body!.pipeThrough(ds);
      const decompressedBuffer = await new Response(decompressedStream).arrayBuffer();
      sqlText = new TextDecoder().decode(decompressedBuffer);
    } else {
      sqlText = await request.text();
    }

    if (!sqlText || sqlText.trim().length === 0) {
      return jsonResponse({ error: 'Empty SQL body' }, 400);
    }

    // ─── Security: only allow INSERT statements ───────────────
    const sqlUpper = sqlText.trim().toUpperCase();
    if (!sqlUpper.startsWith('INSERT')) {
      return jsonResponse(
        { error: 'Only INSERT statements are allowed for migration' },
        400
      );
    }

    // Block dangerous keywords (defense in depth)
    const dangerous = ['DROP', 'DELETE', 'UPDATE', 'ALTER', 'CREATE', 'ATTACH', 'DETACH'];
    for (const kw of dangerous) {
      // Allow these words only inside VALUES (as string literals), but
      // block them as statement starts. Simple check: if the statement
      // starts with INSERT and contains these as separate statements
      // (after ;), reject.
      const re = new RegExp(`;\\s*${kw}`, 'i');
      if (re.test(sqlText)) {
        return jsonResponse(
          { error: `Blocked keyword after semicolon: ${kw}` },
          400
        );
      }
    }

    // ─── Execute SQL via D1 prepare().run() (per-statement) ───
    // Simpler than batch() — avoids PRAGMA issues and gives accurate
    // per-statement error reporting. Each INSERT OR REPLACE statement
    // is executed independently.
    const d1Db = (db as unknown as { db: D1Database }).db;
    let rowsInserted = 0;
    const errors: string[] = [];

    // Split by semicolons to handle multiple INSERT statements
    const statements = sqlText
      .split(';')
      .map(s => s.trim())
      .filter(s => s.length > 0);

    console.log(`[MIGRATE] Received ${statements.length} SQL statements, ` +
      `${sqlText.length} bytes (${contentLength} compressed)`);

    // Execute each statement independently
    for (let i = 0; i < statements.length; i++) {
      const stmt = statements[i];
      try {
        const prepared = d1Db.prepare(stmt + ';');
        const result = await prepared.run();
        // D1 run() returns { success, meta: { changes, ... }, results }
        const meta = (result as { meta?: { changes?: number; last_row_id?: number } }).meta;
        if (meta && typeof meta.changes === 'number') {
          rowsInserted += meta.changes;
        }
      } catch (err) {
        const errMsg = String(err).slice(0, 300);
        errors.push(`Statement ${i + 1}: ${errMsg}`);
        console.error(`[MIGRATE] Statement ${i + 1} failed:`, errMsg);
        // Continue with next statement — don't abort the whole batch
      }
    }

    console.log(`[MIGRATE] Done: ${rowsInserted} rows inserted, ` +
      `${errors.length} errors`);

    return jsonResponse({
      success: errors.length === 0,
      rowsInserted,
      statementsExecuted: statements.length,
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
