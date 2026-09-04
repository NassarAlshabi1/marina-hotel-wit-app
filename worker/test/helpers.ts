// ═══════════════════════════════════════════════════════════════
//  helpers.ts — shared test utilities
//
//  Every test resets D1 to a clean schema via resetDb() so tests are
//  order-independent regardless of pool-level storage semantics.
// ═══════════════════════════════════════════════════════════════

import { env, SELF } from 'cloudflare:test';
import { expect } from 'vitest';
import schemaSql from '../schema.sql?raw';
import migrationSql from '../migrations/0002_inventory_blacklist.sql?raw';

export const JWT_SECRET = 'test-only-secret-0123456789abcdef';

/** JWT for an authenticated admin (obtained through the real /register flow). */
let cachedAdminToken: string | null = null;

export function schemaStatements(sqlText: string): string[] {
  // schema.sql / migrations contain no quoted semicolons in our DDL —
  // a plain split on ';' with comment stripping is sufficient here and
  // keeps the helper independent of the production SQL splitter.
  const noComments = sqlText
    .split('\n')
    .filter((line) => !line.trimStart().startsWith('--'))
    .join('\n');
  return noComments
    .split(';')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

/** Rebuild the full schema from scratch. */
export async function resetDb(): Promise<void> {
  const tablesResult = await env.DB.prepare(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%'"
  ).all<{ name: string }>();
  for (const row of tablesResult.results) {
    await env.DB.prepare(`DROP TABLE IF EXISTS ${row.name}`).run();
  }
  for (const stmt of schemaStatements(schemaSql)) {
    await env.DB.prepare(stmt).run();
  }
  for (const stmt of schemaStatements(migrationSql)) {
    await env.DB.prepare(stmt).run();
  }
  cachedAdminToken = null;
}

/** JWT secret visible to the worker under test. */
export function testJwtSecret(): string {
  return JWT_SECRET;
}

/**
 * Create the bootstrap admin through the public API and return a
 * Bearer-ready Authorization header. Cached per test (resetDb clears it).
 */
export async function adminAuthHeader(): Promise<string> {
  if (cachedAdminToken) return `Bearer ${cachedAdminToken}`;
  const res = await SELF.fetch('https://example.com/api/auth/register', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: 'admin', password: 'secret-pw-123', role: 'admin' }),
  });
  if (res.status === 201) {
    const body = (await res.json()) as { token: string };
    cachedAdminToken = body.token;
  } else if (res.status === 409) {
    // Admin already exists (only possible if a test skipped resetDb) —
    // fall through to login.
    const login = await SELF.fetch('https://example.com/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: 'admin', password: 'secret-pw-123' }),
    });
    const body = (await login.json()) as { token: string };
    cachedAdminToken = body.token;
  } else {
    throw new Error(`admin bootstrap failed: HTTP ${res.status}`);
  }
  return `Bearer ${cachedAdminToken}`;
}

// NOTE: with singleWorker the module registry is SHARED across test files,
// so hooks registered here would fire only for the first-importing file.
// Every test file must therefore register `beforeEach(resetDb)` itself —
// see the header of any test file.

// ─── Payload builders ────────────────────────────────────────

let uuidCounter = 0;
export function uniqueUuid(prefix = 'uuid'): string {
  uuidCounter += 1;
  return `${prefix}-00000000-0000-0000-0000-${String(uuidCounter).padStart(12, '0')}`;
}

/** Minimal valid rooms create payload (whole Drift row, snake_case). */
export function roomPayload(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    local_uuid: uniqueUuid('room'),
    room_number: `R${Math.floor(Math.random() * 100000)}`,
    type: 'double',
    price: 100.5,
    status: 'available',
    cleaning_status: 'clean',
    requires_maintenance: 0,
    created_at: 1700000000,
    updated_at: 1700000000,
    last_modified: 1700000000,
    created_at_epoch: 0,
    last_modified_epoch: 0,
    version: 1,
    origin: 'local',
    vector_clock: '{}',
    device_id: 'device-A',
    ...overrides,
  };
}

export function pushOp(
  entity: string,
  operation: 'create' | 'update' | 'delete',
  data: Record<string, unknown>,
  overrides: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    idempotencyKey: uniqueUuid('idem'),
    entity,
    operation,
    data,
    vectorClock: (data.vector_clock as string) ?? '{}',
    updatedAt: 1700000000,
    deviceId: (data.device_id as string) ?? 'device-A',
    ...overrides,
  };
}

export async function pushOperations(
  authHeader: string,
  operations: unknown[],
  extraHeaders: Record<string, string> = {}
): Promise<Response> {
  return SELF.fetch('https://example.com/api/sync/push', {
    method: 'POST',
    headers: {
      Authorization: authHeader,
      'Content-Type': 'application/json',
      ...extraHeaders,
    },
    body: JSON.stringify({ operations }),
  });
}

export interface PushResultItem {
  idempotencyKey: string;
  success: boolean;
  entity?: string;
  entityId?: string;
  error?: string;
  skipped?: boolean;
}

export interface PushResponseBody {
  results: PushResultItem[];
  summary: { total: number; success: number; failed: number; skipped: number };
  server_time: number;
}

export async function pull(
  authHeader: string,
  params: Record<string, string> = {}
): Promise<{ changes: Array<Record<string, unknown>>; cursor: string; has_more: boolean; server_time: number }> {
  const qs = new URLSearchParams(params).toString();
  const res = await SELF.fetch(`https://example.com/api/sync/pull${qs ? `?${qs}` : ''}`, {
    headers: { Authorization: authHeader },
  });
  expect(res.status).toBe(200);
  return (await res.json()) as {
    changes: Array<Record<string, unknown>>;
    cursor: string;
    has_more: boolean;
    server_time: number;
  };
}
