// ═══════════════════════════════════════════════════════════════
//  sync.ts — Sync Pull/Push Handlers
//  Delta sync + idempotent push + conflict resolution (LWW + VC)
// ═══════════════════════════════════════════════════════════════

import type { Database, PushOperation, SyncRecord } from './database';
import { isValidEntity, SYNC_ENTITY_TABLES } from './database';
import type { AuthContext } from './auth';

// ─── Validation ───────────────────────────────────────────────

const MAX_BATCH_SIZE = 100;
const MAX_PAYLOAD_SIZE = 5 * 1024 * 1024; // 5MB

/**
 * Device attribution for pushed rows (fix discovered by test): the op
 * carries the device that produced it (cloudflare_sync_manager sends
 * `deviceId` per operation), while the JWT device_id is whatever was
 * present at LOGIN time — often empty for bootstrap-registered users.
 * The op value wins; the JWT value is the fallback.
 */
function opDeviceId(op: PushOperation, ctx: AuthContext): string {
  if (typeof op.deviceId === 'string' && op.deviceId.length > 0) return op.deviceId;
  return ctx.deviceId;
}

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


function requireEntityId(data: Record<string, unknown>): string {
  const value = data.local_uuid ?? data.id ?? data.server_id;
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error('Record is missing local_uuid, id, or server_id');
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
    // True [1, 200] clamp: 0 and negatives → 1, NaN → 200, anything
    // larger → 200. (The old `parseInt(...) || 200` let limit=0 slip to
    // the 200 default and return a full page for a nonsense request.)
    const parsedLimit = parseInt(limitStr, 10);
    const limit = Math.min(Math.max(Number.isFinite(parsedLimit) ? parsedLimit : 200, 1), MAX_BATCH_SIZE);
    // Echo filter (plan 2.5): skip rows this device already has locally.
    const excludeDevice = url.searchParams.get('exclude_device') || undefined;

    const result = await db.pullChanges(entity, cursor, limit, excludeDevice);

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
        let entityId: string;

        switch (op.operation) {
          case 'create': {
            const record = await db.createRecord(op.entity, op.data, opDeviceId(op, ctx), op.vectorClock);
            entityId = record.local_uuid;
            break;
          }
          case 'update': {
            const recordId = requireEntityId(op.data);
            const record = await db.updateRecord(
              op.entity,
              recordId,
              op.data,
              op.vectorClock,
              opDeviceId(op, ctx),
              op.updatedAt
            );
            entityId = record.local_uuid;
            break;
          }
          case 'delete': {
            entityId = requireEntityId(op.data);
            await db.deleteRecord(op.entity, entityId, opDeviceId(op, ctx));
            break;
          }
          default:
            throw new Error(`Unknown operation: ${op.operation}`);
        }

        // ─── Save idempotency ──────────────────────────────────
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

    // ✅ Cap the DECOMPRESSED size too — Content-Length only reflects the
    // gzipped bytes; a small zip bomb otherwise expands without bound.
    if (sqlText.length > 10 * 1024 * 1024) {
      return jsonResponse({ error: 'Payload too large (max 10MB decompressed)' }, 413);
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

    for (let i = 0; i < statements.length; i++) {
      if (!isAllowedMigrateStatement(statements[i] ?? '', validTargets)) {
        return jsonResponse(
          {
            error:
              'Only INSERT [OR REPLACE / IGNORE] INTO <entity> (cols) VALUES (literals) statements are allowed',
            statement_index: i + 1,
          },
          400
        );
      }
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
      `${sqlText.length} bytes (${contentLength} compressed)`);

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

    return jsonResponse({
      success: errors.length === 0,
      rowsInserted,
      statementsExecuted,
      statementsTotal: statements.length,
      abortedEarly: statementsExecuted < statements.length,
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
