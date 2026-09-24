// ═══════════════════════════════════════════════════════════════
//  migrate.security.test.ts — P1 migration whitelist exhaustive (2026-09-24)
//
//  يحدّث عقد الحماية في handleMigrate:
//    رفض: DELETE / UPDATE / DROP / SELECT / WITH / ATTACH / PRAGMA /
//         comments قبل INSERT / multiple-statements injection
//    قبول: INSERT / INSERT OR IGNORE / INSERT OR REPLACE على جداول
//         الكيانات فقط
// ═══════════════════════════════════════════════════════════════

import { SELF } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import { resetDb, adminAuthHeader } from './helpers';

beforeEach(async () => {
  await resetDb();
});

async function migrate(auth: string, sql: string): Promise<Response> {
  return SELF.fetch('https://example.com/api/sync/migrate', {
    method: 'POST',
    headers: { Authorization: auth, 'Content-Type': 'application/sql' },
    body: sql,
  });
}

const VALID_ROOM_COLS =
  '(local_uuid, room_number, type, price, status, created_at, updated_at, last_modified, version)';

describe('migrate: whitelist accepts the three documented INSERT forms', () => {
  it.each([
    ['plain INSERT', `INSERT INTO rooms ${VALID_ROOM_COLS} VALUES ('m-room-1', 'M1', 'double', 100, 'available', 1700000000, 1700000000, 1700000000, 1);`],
    ['INSERT OR IGNORE', `INSERT OR IGNORE INTO rooms ${VALID_ROOM_COLS} VALUES ('m-room-2', 'M2', 'double', 100, 'available', 1700000000, 1700000000, 1700000000, 1);`],
    ['INSERT OR REPLACE', `INSERT OR REPLACE INTO rooms ${VALID_ROOM_COLS} VALUES ('m-room-3', 'M3', 'double', 100, 'available', 1700000000, 1700000000, 1700000000, 1);`],
  ])('%s into a valid entity table is accepted', async (_name, sql) => {
    const auth = await adminAuthHeader();
    const res = await migrate(auth, sql);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { success: boolean; rowsInserted: number };
    expect(body.success).toBe(true);
    expect(body.rowsInserted).toBe(1);
  });
});

describe('migrate: whitelist rejects destructive/injection statements', () => {
  const authedRejects: Array<[string, string]> = [
    ['DELETE', `DELETE FROM users;`],
    ['UPDATE', `UPDATE users SET password_hash = 'x';`],
    ['DROP', `DROP TABLE rooms;`],
    ['SELECT exfiltration', `SELECT password_hash FROM users;`],
    ['WITH data-modifying CTE', `WITH d AS (DELETE FROM users RETURNING *) INSERT INTO rooms ${VALID_ROOM_COLS} VALUES ('m-x1', 'X1', 't', 1, 's', 1, 1, 1, 1);`],
    ['ATTACH', `ATTACH DATABASE '/tmp/evil.db' AS evil;`],
    ['PRAGMA', `PRAGMA journal_mode = WAL;`],
    ['ALTER', `ALTER TABLE rooms ADD COLUMN evil TEXT;`],
    ['CREATE', `CREATE TABLE evil (x TEXT);`],
    ['INSERT into a NON-entity table (users)', `INSERT INTO users (id, username, password_hash, role) VALUES ('u1', 'evil', 'x', 'admin');`],
    ['comment before a non-INSERT (smuggling)', `/**/DELETE FROM users;`],
    ['semicolon multiple-statement injection', `INSERT OR IGNORE INTO rooms ${VALID_ROOM_COLS} VALUES ('m-ok', 'OK1', 't', 1, 's', 1, 1, 1, 1); DELETE FROM users;`],
    ['subquery exfiltration inside VALUES', `INSERT OR IGNORE INTO rooms ${VALID_ROOM_COLS} VALUES ((SELECT password_hash FROM users), 'S1', 't', 1, 's', 1, 1, 1, 1);`],
    ['keywords hiding inside identifiers tail', `INSERT OR IGNORE INTO rooms ${VALID_ROOM_COLS} VALUES ('m-v', 'V1', 't', 1, 's', 1, 1, 1, 1) /* injected */; DELETE FROM users;`],
  ];

  it.each(authedRejects)('rejects %s (400, nothing executes)', async (_name, sql) => {
    const auth = await adminAuthHeader();
    const res = await migrate(auth, sql);
    expect(res.status).toBe(400);
    const body = (await res.json()) as { error?: string; statement_index?: number };
    expect(body.error).toBeDefined();
  });

  it('injected batch leaves users table intact (fail-closed)', async () => {
    const auth = await adminAuthHeader();
    await migrate(
      auth,
      `INSERT OR IGNORE INTO rooms ${VALID_ROOM_COLS} VALUES ('m-ok2', 'OK2', 't', 1, 's', 1, 1, 1, 1); DELETE FROM users;`
    );
    const count = await SELF.fetch('https://example.com/api/stats', {
      headers: { Authorization: auth },
    });
    expect(count.status).toBe(200);
    const stats = (await count.json()) as { tables: Record<string, number> };
    // المستخدم الإداري (bootstrap) ما زال موجوداً — لم يُحذف
    expect(stats.tables['users']).toBeGreaterThanOrEqual(1);
  });
});

describe('migrate: partial failure response contract (P1)', () => {
  it('chunk failure reports success:false + abortedEarly + executed/total counts', async () => {
    const auth = await adminAuthHeader();
    // Chunk 1 = 50 عبارة سليمة، Chunk 2 = عبارة تكرر room_number فريداً
    // بلا OR IGNORE → chunk2 يفشل ذرياً بعد نجاح chunk1 → partial failure.
    const stmts: string[] = [];
    for (let i = 0; i < 50; i++) {
      stmts.push(
        `INSERT OR IGNORE INTO rooms ${VALID_ROOM_COLS} VALUES ('m-p-${i}', 'PUNIQUE-${i}', 't', 1, 's', 1, 1, 1, 1);`
      );
    }
    stmts.push(
      `INSERT INTO rooms ${VALID_ROOM_COLS} VALUES ('m-p-dup', 'PUNIQUE-0', 't', 1, 's', 1, 1, 1, 1);`
    );
    const res = await migrate(auth, stmts.join('\n'));
    expect(res.status).toBe(200); // الاستجابة وصلت (وليست 500)
    const body = (await res.json()) as {
      success: boolean;
      abortedEarly: boolean;
      statementsExecuted: number;
      statementsTotal: number;
      errors: string[];
    };
    expect(body.success).toBe(false);
    expect(body.abortedEarly).toBe(true);
    expect(body.statementsExecuted).toBe(50);
    expect(body.statementsTotal).toBe(51);
    expect(body.errors.length).toBeGreaterThan(0);
  }, 30_000);

  it('retry after failure is safe (idempotent INSERT OR IGNORE re-runs cleanly)', async () => {
    const auth = await adminAuthHeader();
    const sql = `INSERT OR IGNORE INTO rooms ${VALID_ROOM_COLS} VALUES ('m-r1', 'R1', 't', 1, 's', 1, 1, 1, 1);`;
    await migrate(auth, sql);
    const second = await migrate(auth, sql);
    const body = (await second.json()) as { success: boolean; rowsInserted: number };
    expect(body.success).toBe(true);
    expect(body.rowsInserted).toBe(0); // OR IGNORE — لا صفوف جديدة ولا أخطاء
  });
});
