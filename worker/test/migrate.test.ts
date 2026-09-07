// ═══════════════════════════════════════════════════════════════
//  migrate.test.ts — plan task 1.6 + 2.6
//  Per-statement whitelist (SQLi vectors), zip-bomb cap, atomic
//  chunked batches, sync_clock advancement.
// ═══════════════════════════════════════════════════════════════

import { env, SELF } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import { resetDb, adminAuthHeader, uniqueUuid } from './helpers';

beforeEach(async () => {
  await resetDb();
});


async function postMigrate(
  auth: string,
  sql: string,
  headers: Record<string, string> = { 'Content-Type': 'application/sql' }
): Promise<Response> {
  return SELF.fetch('https://example.com/api/sync/migrate', {
    method: 'POST',
    headers: { Authorization: auth, ...headers },
    body: sql,
  });
}

describe('migrate: whitelist + SQLi defense', () => {
  it('accepts plain INSERT OR IGNORE/REPLACE into entity tables', async () => {
    const auth = await adminAuthHeader();
    const u1 = uniqueUuid('m1');
    const u2 = uniqueUuid('m2');
    const sql =
      `INSERT OR IGNORE INTO rooms (local_uuid, room_number, type, price, status, created_at, updated_at, last_modified) VALUES ('${u1}', 'M-101', 'suite', 99.5, 'available', 1700000000, 1700000000, 1700000000);\n` +
      `INSERT OR REPLACE INTO rooms (local_uuid, room_number, type, price, status, created_at, updated_at, last_modified) VALUES ('${u2}', 'M-102', 'double', 80, 'available', 1700000000, 1700000000, 1700000000);`;
    const res = await postMigrate(auth, sql);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { success: boolean; rowsInserted: number; abortedEarly: boolean };
    expect(body.success).toBe(true);
    expect(body.rowsInserted).toBe(2);
    expect(body.abortedEarly).toBe(false);
  });

  it.each([
    ['INSERT INTO users (id, username, password_hash, role, created_at, updated_at) VALUES ("x","y","z","admin",1,2)', 'infra table'],
    ['INSERT OR IGNORE INTO rooms (local_uuid) SELECT local_uuid FROM bookings', 'INSERT...SELECT exfiltration'],
    ['INSERT OR IGNORE INTO rooms (local_uuid) VALUES ((SELECT password_hash FROM users))', 'subquery exfiltration'],
    ["INSERT OR IGNORE INTO rooms (local_uuid, room_number) VALUES ('a', 'x');/**/DELETE FROM users", 'semicolon + comment attack'],
    ['INSERT OR IGNORE INTO rooms WITH d AS (DELETE FROM users) SELECT 1', 'WITH-clause data modification'],
    ['INSERT OR IGNORE INTO rooms (local_uuid) VALUES ("a") ON CONFLICT DO UPDATE SET room_number = "hacked"', 'ON CONFLICT DO UPDATE'],
    ['DROP TABLE users', 'not an insert'],
    ['INSERT OR IGNORE INTO sqlite_master VALUES (1)', 'internal table'],
    ['INSERT OR IGNORE INTO rooms (local_uuid) VALUES ("a"); PRAGMA table_info(rooms)', 'trailing pragma'],
  ])('rejects: %s (%s)', async (sql) => {
    const auth = await adminAuthHeader();
    const res = await postMigrate(auth, sql);
    expect(res.status).toBe(400);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain('Only INSERT');
  });

  it('smuggled DELETE via quote tricks is rejected fail-closed (400) and users stay intact', async () => {
    const auth = await adminAuthHeader();
    // The quote-aware splitter resolves this payload into multiple
    // statements — one of which is a bare `DELETE FROM users` that the
    // whitelist rejects. Ambiguous payloads fail CLOSED (400): nothing
    // in the batch executes.
    const evil = `INSERT OR IGNORE INTO rooms (local_uuid, room_number, type) VALUES ('${uniqueUuid('evil')}','a'''); DELETE FROM users; --', 'x', 'y')`;
    const res = await postMigrate(auth, evil);
    expect(res.status).toBe(400);
    const usersCount = await env.DB.prepare('SELECT COUNT(*) AS c FROM users').first<{ c: number }>();
    expect(usersCount?.c).toBeGreaterThanOrEqual(1); // users table intact
    const evilRows = await env.DB.prepare('SELECT COUNT(*) AS c FROM rooms').first<{ c: number }>();
    expect(evilRows?.c).toBe(0); // nothing from the rejected batch executed
  });

  it('quote-aware splitting keeps semicolons/keywords inside string literals as inert data', async () => {
    const auth = await adminAuthHeader();
    // Benign case: a room_number that CONTAINS a semicolon + keyword text
    // stays a single statement and is stored as data, never executed.
    const tricky = `some; DELETE FROM fake; text`;
    const uuid = uniqueUuid('semi');
    const sql = `INSERT OR IGNORE INTO rooms (local_uuid, room_number, type, price, status, created_at, updated_at, last_modified) VALUES ('${uuid}', '${tricky}', 'double', 5, 'available', 1, 1, 1);`;
    const res = await postMigrate(auth, sql);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { success: boolean; rowsInserted: number };
    expect(body.success).toBe(true);
    expect(body.rowsInserted).toBe(1);
    const row = await env.DB.prepare('SELECT room_number FROM rooms WHERE local_uuid = ?')
      .bind(uuid)
      .first<{ room_number: string }>();
    expect(row?.room_number).toBe(tricky);
  });
});

describe('migrate: payload limits', () => {
  it('rejects an empty body (400)', async () => {
    const auth = await adminAuthHeader();
    const res = await postMigrate(auth, '   ');
    expect(res.status).toBe(400);
    const body = (await res.json()) as { error: string };
    expect(body.error).toBe('Empty SQL body');
  });

  it('rejects >200 statements (400)', async () => {
    const auth = await adminAuthHeader();
    const stmts = Array.from({ length: 201 }, (_, i) =>
      `INSERT OR IGNORE INTO rooms (local_uuid, room_number, type, price, status, created_at, updated_at, last_modified) VALUES ('${uniqueUuid(`bulk${i}`)}', 'B${i}', 'x', 1, 'available', 1, 1, 1);`
    );
    const res = await postMigrate(auth, stmts.join('\n'));
    expect(res.status).toBe(400);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain('Too many statements');
  });

  it('rejects decompressed bodies >10MB (zip-bomb defense, 413)', async () => {
    const auth = await adminAuthHeader();
    // One syntactically-valid INSERT padded with a huge comment-free
    // string literal — decompressed size exceeds the cap while the
    // compressed size stays small. (Content-Length reflects gzip bytes.)
    const bigPadding = 'x'.repeat(11 * 1024 * 1024);
    const sql = `INSERT OR IGNORE INTO rooms (local_uuid, room_number, type) VALUES ('${uniqueUuid('pad')}', '${bigPadding}', 'x')`;
    const gzipped = await new Response(
      new Blob([sql]).stream().pipeThrough(new CompressionStream('gzip'))
    ).arrayBuffer();
    const res = await SELF.fetch('https://example.com/api/sync/migrate', {
      method: 'POST',
      headers: {
        Authorization: auth,
        'Content-Type': 'application/sql',
        'Content-Encoding': 'gzip',
        'Content-Length': String(gzipped.byteLength),
      },
      body: new Uint8Array(gzipped),
    });
    expect(res.status).toBe(413);
  });
});

describe('migrate: atomic chunk execution (plan 2.6)', () => {
  it('a failing statement aborts the rest of its chunk and reports abortEarly', async () => {
    const auth = await adminAuthHeader();
    const u1 = uniqueUuid('ok');
    // Second statement is a COMPILE error (no such column) — INSERT OR IGNORE
    // swallows constraint violations (NOT NULL/UNIQUE), so only a statement
    // that fails to compile/reach execution aborts the atomic chunk.
    const sql = [
      `INSERT OR IGNORE INTO rooms (local_uuid, room_number, type, price, status, created_at, updated_at, last_modified) VALUES ('${u1}', 'A-1', 'double', 5, 'available', 1, 1, 1);`,
      `INSERT OR IGNORE INTO rooms (local_uuid, nonexistent_column) VALUES ('${uniqueUuid('bad')}', 1);`,
      `INSERT OR IGNORE INTO rooms (local_uuid, room_number, type, price, status, created_at, updated_at, last_modified) VALUES ('${uniqueUuid('after')}', 'A-3', 'double', 5, 'available', 1, 1, 1);`,
    ].join('\n');
    const res = await postMigrate(auth, sql);
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      success: boolean;
      rowsInserted: number;
      statementsExecuted: number;
      statementsTotal: number;
      abortedEarly: boolean;
      totalErrors: number;
    };
    expect(body.success).toBe(false);
    expect(body.totalErrors).toBeGreaterThan(0);
    expect(body.abortedEarly).toBe(true);
    expect(body.statementsExecuted).toBeLessThan(body.statementsTotal);
    // Atomicity: the first statement of the failed chunk rolled back too
    const count = await env.DB.prepare('SELECT COUNT(*) AS c FROM rooms').first<{ c: number }>();
    expect(count?.c).toBe(0);
  });

  it('retry after failure is idempotent (INSERT OR IGNORE re-runs cleanly)', async () => {
    const auth = await adminAuthHeader();
    let seq = 0;
    const good = () =>
      `INSERT OR IGNORE INTO rooms (local_uuid, room_number, type, price, status, created_at, updated_at, last_modified) VALUES ('${uniqueUuid('r1')}', 'R-${++seq}-${Date.now()}', 'double', 5, 'available', 1, 1, 1);`;
    // First run: a compile error breaks the chunk (constraint skips would be
    // silently swallowed by OR IGNORE — compile errors are not)
    const badSql = [
      good(),
      `INSERT OR IGNORE INTO rooms (local_uuid, nonexistent_column) VALUES ('${uniqueUuid('bad')}', 1);`,
    ].join('\n');
    await postMigrate(auth, badSql);

    // Retry with only good statements — previously-committed rows are IGNOREd
    const retry = await postMigrate(auth, [good(), good()].join('\n'));
    const body = (await retry.json()) as { success: boolean; rowsInserted: number };
    expect(body.success).toBe(true);
    expect(body.rowsInserted).toBe(2); // only the new ones
  });
});

describe('migrate: sync_clock advancement', () => {
  it('advances sync_clock past migrated updated_at values', async () => {
    const auth = await adminAuthHeader();
    const before = await env.DB.prepare('SELECT last_ts FROM sync_clock WHERE id = 1').first<{ last_ts: number }>();

    const bigTs = 4_000_000_000; // far in the future
    const sql = `INSERT OR REPLACE INTO rooms (local_uuid, room_number, type, price, status, created_at, updated_at, last_modified) VALUES ('${uniqueUuid('clock')}', 'C-1', 'double', 5, 'available', 1, ${bigTs}, 1);`;
    await postMigrate(auth, sql);

    const after = await env.DB.prepare('SELECT last_ts FROM sync_clock WHERE id = 1').first<{ last_ts: number }>();
    expect(after!.last_ts).toBeGreaterThanOrEqual(bigTs);
    expect(after!.last_ts).toBeGreaterThan(before?.last_ts ?? 0);

    // A subsequent push allocates strictly-greater updated_at
    const createRes = await SELF.fetch('https://example.com/api/sync/push', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: auth },
      body: JSON.stringify({
        operations: [
          {
            idempotencyKey: uniqueUuid('post-clock'),
            entity: 'rooms',
            operation: 'create',
            data: {
              local_uuid: uniqueUuid('post-clock'),
              room_number: 'C-2',
              type: 'double',
              price: 5,
              status: 'available',
              created_at: 1,
              updated_at: 1,
              device_id: 'device-A',
            },
            vectorClock: '{}',
            updatedAt: 1,
          },
        ],
      }),
    });
    expect(createRes.status).toBe(200);
    const pushed = await env.DB.prepare(
      "SELECT MAX(updated_at) AS m FROM rooms WHERE room_number = 'C-2'"
    ).first<{ m: number }>();
    expect(pushed!.m).toBeGreaterThan(bigTs);
  });
});
