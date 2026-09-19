// ═══════════════════════════════════════════════════════════════
//  schema.parity.test.ts — D1 mirrors the mobile Drift sync contract
//
//  Audit (2026-09-05): every Drift table (mobile local_db.dart) was
//  diffed against schema.sql. 26 contract columns were missing across
//  8 tables and price_adjustments declared INTEGER where the Drift /
//  cloud contract is REAL (Wave 6b). Fixed in schema.sql + 0005.
//
//  These tests lock the parity in:
//   1. Fresh installs (schema.sql) carry every contract column with
//      the declared type.
//   2. Migration 0005 upgrades a LEGACY deployment: rows preserved,
//      price_adjustments rebuilt as REAL, new columns present.
// ═══════════════════════════════════════════════════════════════

import { beforeAll, describe, expect, it } from 'vitest';
import { env } from 'cloudflare:test';
import migrationSql0005 from '../migrations/0005_schema_parity.sql?raw';
import { resetDb, schemaStatements } from './helpers';

interface ColumnInfo {
  name: string;
  type: string;
  notnull: number;
  dflt_value: string | null;
}

async function columnsOf(table: string): Promise<Map<string, ColumnInfo>> {
  const res = await env.DB.prepare(
    `PRAGMA table_info(${table})`,
  ).all<ColumnInfo>();
  return new Map(res.results.map((c) => [c.name, c]));
}

/** Contract columns (column -> declared D1 type) per the audit. */
const EXPECTED: Record<string, Record<string, string>> = {
  // ✅ (2026-09-19) عقد employee_uuid — المفتاح المستقر عبر الأجهزة
  // لموظف في كل جداول الرواتب (توجيه المستخدم؛ migration 0007).
  expenses: { employee_uuid: 'TEXT' },
  salary_withdrawals: { employee_uuid: 'TEXT' },
  salary_cycles: { employee_uuid: 'TEXT' },
  salary_payments: { employee_uuid: 'TEXT' },
  bookings: { financial_frozen_at: 'INTEGER', financial_hash: 'TEXT' },
  guest_infos: { guest_phone: 'TEXT' },
  booking_nights: {
    booking_uuid_cache: 'TEXT',
    server_booking_id: 'INTEGER',
  },
  booking_price_adjustments: { booking_uuid: 'TEXT', applied_at: 'INTEGER' },
  payments: {
    void_reason: 'TEXT',
    is_immutable: 'INTEGER',
    received_by_user_id: 'INTEGER',
    received_by_name: 'TEXT',
    received_session_uuid: 'TEXT',
    received_by_cloud_id: 'TEXT',
  },
  debts: {
    guest_phone: 'TEXT',
    description: 'TEXT',
    status: 'TEXT',
    due_date: 'TEXT',
    booking_uuid_cache: 'TEXT',
    debtor_name: 'TEXT',
    amount: 'REAL',
    date: 'TEXT',
  },
  salary_carry_over_logs: {
    from_cycle_id: 'TEXT',
    to_cycle_id: 'TEXT',
    carry_date: 'TEXT',
    performed_by: 'TEXT',
    hotel_day_key: 'TEXT',
  },
};

describe('schema parity: fresh install (schema.sql)', () => {
  beforeAll(async () => {
    await resetDb();
  });

  for (const [table, cols] of Object.entries(EXPECTED)) {
    it(`${table} carries all contract columns with declared types`, async () => {
      const actual = await columnsOf(table);
      for (const [col, type] of Object.entries(cols)) {
        const info = actual.get(col);
        expect(info, `${table}.${col} missing`).toBeDefined();
        expect(info!.type, `${table}.${col} type`).toBe(type);
      }
    });
  }

  it('price_adjustments.previous_value/new_value are REAL (Wave 6b)', async () => {
    const actual = await columnsOf('price_adjustments');
    expect(actual.get('previous_value')!.type).toBe('REAL');
    expect(actual.get('new_value')!.type).toBe('REAL');
    expect(actual.get('adjustment_mode')!.type).toBe('TEXT');
    expect(actual.get('booking_uuid')!.type).toBe('TEXT');
    expect(actual.get('applied_at')!.type).toBe('INTEGER');
  });
});

// ─── Legacy-shape price_adjustments (pre-0005, from git HEAD) ──
const LEGACY_PRICE_ADJUSTMENTS = `
CREATE TABLE price_adjustments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  target_type TEXT NOT NULL,
  target_uuid TEXT NOT NULL,
  adjustment_type TEXT NOT NULL,
  previous_value INTEGER NOT NULL,
  new_value INTEGER NOT NULL,
  reason TEXT,
  effective_date TEXT NOT NULL,
  applied_by TEXT NOT NULL,
  hotel_day_key TEXT NOT NULL,
  is_reversed INTEGER NOT NULL DEFAULT 0,
  reversed_at TEXT,
  reversed_by TEXT,
  local_uuid TEXT NOT NULL UNIQUE,
  server_id INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  last_modified INTEGER NOT NULL DEFAULT 0,
  created_at_iso TEXT,
  updated_at_iso TEXT,
  deleted_at_iso TEXT,
  created_at_epoch INTEGER NOT NULL DEFAULT 0,
  last_modified_epoch INTEGER NOT NULL DEFAULT 0,
  version INTEGER NOT NULL DEFAULT 1,
  origin TEXT NOT NULL DEFAULT 'local',
  vector_clock TEXT NOT NULL DEFAULT '{}',
  device_id TEXT NOT NULL DEFAULT '',
  idempotency_key TEXT
);
INSERT INTO price_adjustments (
  target_type, target_uuid, adjustment_type, previous_value, new_value,
  reason, effective_date, applied_by, hotel_day_key, local_uuid,
  created_at, updated_at
) VALUES ('room', 'rm-1', 'manual', 1500.75, 2000.25, 'test',
  '2026-09-05', 'tester', '2026-09-05', 'pa-uuid-1', 1, 1);
`;

describe('migration 0005: legacy deployment upgrade', () => {
  it('rebuilds price_adjustments as REAL preserving rows and adds columns', async () => {
    await resetDb();

    // Re-create a LEGACY (pre-0005) shape: drop the 8 affected tables
    // from the fresh schema and rebuild the price_adjustments one with
    // its old INTEGER declaration + a seeded fractional row.
    for (const t of [
      'bookings',
      'guest_infos',
      'booking_nights',
      'booking_price_adjustments',
      'payments',
      'debts',
      'salary_carry_over_logs',
      'price_adjustments',
    ]) {
      await env.DB.prepare(`DROP TABLE IF EXISTS ${t}`).run();
      // Minimal stubs so ALTER TABLE has a target (only
      // price_adjustments is restored in full legacy shape).
      if (t !== 'price_adjustments') {
        await env.DB.prepare(
          `CREATE TABLE ${t} (id INTEGER PRIMARY KEY, local_uuid TEXT)`,
        ).run();
      }
    }
    for (const stmt of schemaStatements(LEGACY_PRICE_ADJUSTMENTS)) {
      await env.DB.prepare(stmt).run();
    }

    // Apply the migration.
    for (const stmt of schemaStatements(migrationSql0005)) {
      await env.DB.prepare(stmt).run();
    }

    // price_adjustments: REAL declared, fractional value preserved.
    const cols = await columnsOf('price_adjustments');
    expect(cols.get('previous_value')!.type).toBe('REAL');
    expect(cols.get('new_value')!.type).toBe('REAL');
    expect(cols.get('adjustment_mode')!.dflt_value).toContain('per_night');
    const row = await env.DB.prepare(
      'SELECT previous_value, new_value, adjustment_mode, target_uuid FROM price_adjustments WHERE local_uuid = ?',
    )
      .bind('pa-uuid-1')
      .first<{ previous_value: number; new_value: number; adjustment_mode: string }>();
    expect(row!.previous_value).toBe(1500.75);
    expect(row!.new_value).toBe(2000.25);
    expect(row!.adjustment_mode).toBe('per_night');

    // Legacy stubs gained the contract columns.
    for (const [table, colsMap] of Object.entries(EXPECTED)) {
      const actual = await columnsOf(table);
      for (const col of Object.keys(colsMap)) {
        expect(actual.get(col), `${table}.${col} after 0005`).toBeDefined();
      }
    }
  });
});

// ═══════════════════════════════════════════════════════════════
//  Migration 0007 — employee_uuid closure + guarded historical
//  backfill. The legacy shape: salary_cycles / salary_payments lack
//  the column entirely; salary_withdrawals rows and legacy expenses
//  carry only device-local numeric links (employee_id / related_id).
// ═══════════════════════════════════════════════════════════════
import migrationSql0007 from '../migrations/0007_salary_tables_employee_uuid.sql?raw';

// Legacy shapes (pre-0007): the two tables WITHOUT employee_uuid.
const LEGACY_SALARY_CYCLES = `
CREATE TABLE salary_cycles (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  employee_id INTEGER NOT NULL,
  cycle_key TEXT NOT NULL,
  hotel_day_start TEXT,
  hotel_day_end TEXT,
  expected_amount INTEGER NOT NULL DEFAULT 0,
  actual_paid INTEGER NOT NULL DEFAULT 0,
  remaining_amount INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'draft',
  local_uuid TEXT NOT NULL UNIQUE,
  server_id INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  last_modified INTEGER NOT NULL DEFAULT 0,
  version INTEGER NOT NULL DEFAULT 1,
  origin TEXT NOT NULL DEFAULT 'local',
  vector_clock TEXT NOT NULL DEFAULT '{}',
  device_id TEXT NOT NULL DEFAULT '',
  UNIQUE (employee_id, cycle_key)
);
`;

const LEGACY_SALARY_PAYMENTS = `
CREATE TABLE salary_payments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  cycle_id INTEGER NOT NULL,
  amount INTEGER NOT NULL DEFAULT 0,
  hotel_day_key TEXT,
  payment_date_iso TEXT NOT NULL,
  method TEXT,
  is_auto_generated INTEGER NOT NULL DEFAULT 0,
  local_uuid TEXT NOT NULL UNIQUE,
  server_id INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  last_modified INTEGER NOT NULL DEFAULT 0,
  version INTEGER NOT NULL DEFAULT 1,
  origin TEXT NOT NULL DEFAULT 'local',
  vector_clock TEXT NOT NULL DEFAULT '{}',
  device_id TEXT NOT NULL DEFAULT '',
  idempotency_key TEXT
);
`;

/** Rebuild the pre-0007 legacy shape of the four salary tables. */
async function buildLegacySalaryShape(): Promise<void> {
  await resetDb();
  // employees survive from the fresh schema — seed the exact ambiguity
  // topology observed in production D1.
  await env.DB.prepare(
    `INSERT INTO employees (name, basic_salary, status, hire_date, local_uuid, server_id, created_at, updated_at, last_modified)
     VALUES ('موظف أ', 100, 'active', '2026-01-01', 'uuid-a', 5, 1, 1, 0),
            ('موظف ب', 100, 'active', '2026-01-01', 'uuid-b', 7, 1, 1, 0),
            ('موظف قديم محذوف', 100, 'terminated', '2026-01-01', 'uuid-c', 1, 1, 1, 0),
            ('موظف د', 100, 'active', '2026-01-01', 'uuid-d', 1, 1, 1, 0)`
  ).run();
  // uuid-e: server_id NULL — only resolvable via the guarded e.id
  // fallback (its D1 autoincrement id).
  await env.DB.prepare(
    `INSERT INTO employees (name, basic_salary, status, hire_date, local_uuid, server_id, created_at, updated_at, last_modified)
     VALUES ('موظف هـ', 100, 'active', '2026-01-01', 'uuid-e', NULL, 1, 1, 0)`
  ).run();
  await env.DB.prepare(
    "UPDATE employees SET deleted_at = 1 WHERE local_uuid = 'uuid-c'"
  ).run();

  await env.DB.prepare('DROP TABLE salary_cycles').run();
  await env.DB.prepare('DROP TABLE salary_payments').run();
  for (const stmt of schemaStatements(LEGACY_SALARY_CYCLES)) {
    await env.DB.prepare(stmt).run();
  }
  for (const stmt of schemaStatements(LEGACY_SALARY_PAYMENTS)) {
    await env.DB.prepare(stmt).run();
  }

  // salary_withdrawals keeps its 0006 column but every row is NULL
  // (the exact production state: 620/620 unlinked).
  await env.DB.prepare(
    `INSERT INTO salary_withdrawals (employee_id, amount, withdraw_date, local_uuid, created_at, updated_at, last_modified)
     VALUES (5, 100, '2026-09-01', 'wd-1', 1, 1, 0),
            (7, 200, '2026-09-02', 'wd-2', 1, 1, 0),
            (1, 300, '2026-09-03', 'wd-3', 1, 1, 0),
            (3, 400, '2026-09-04', 'wd-4', 1, 1, 0),
            (99, 500, '2026-09-05', 'wd-5', 1, 1, 0)`
  ).run();

  // Legacy expenses linked only via related_id (device-local ids).
  await env.DB.prepare(
    `INSERT INTO expenses (expense_type, description, amount, date, related_id, local_uuid, created_at, updated_at, last_modified)
     VALUES ('سحب راتب', 'بند', 50, '2026-09-01', 5, 'ex-1', 1, 1, 0),
            ('سحب راتب', 'بند', 60, '2026-09-02', 1, 'ex-2', 1, 1, 0),
            ('سلفة', 'بند', 70, '2026-09-03', 4, 'ex-3', 1, 1, 0),
            ('سحب راتب', 'بند', 80, '2026-09-04', 99, 'ex-4', 1, 1, 0)`
  ).run();

  // Legacy cycles (employee_id only) + payments (cycle_id only).
  await env.DB.prepare(
    `INSERT INTO salary_cycles (employee_id, cycle_key, status, local_uuid, created_at, updated_at, last_modified)
     VALUES (5, 'cy-1', 'draft', 'cy-uuid-1', 1, 1, 0),
            (99, 'cy-2', 'draft', 'cy-uuid-2', 1, 1, 0)`
  ).run();
  const cycleId = (await env.DB.prepare(
    "SELECT id FROM salary_cycles WHERE local_uuid = 'cy-uuid-1'"
  ).first<{ id: number }>())!.id;
  await env.DB.prepare(
    `INSERT INTO salary_payments (cycle_id, amount, payment_date_iso, local_uuid, created_at, updated_at, last_modified)
     VALUES (${cycleId}, 900, '2026-09-10', 'sp-1', 1, 1, 0)`
  ).run();
}

describe('migration 0007: employee_uuid closure + guarded backfill', () => {
  it('adds the column, heals every resolvable link, keeps orphans intact', async () => {
    await buildLegacySalaryShape();
    const withdrawalsBefore = await env.DB.prepare(
      'SELECT COUNT(*) AS n FROM salary_withdrawals'
    ).first<{ n: number }>();
    const expensesBefore = await env.DB.prepare(
      'SELECT COUNT(*) AS n FROM expenses'
    ).first<{ n: number }>();

    for (const stmt of schemaStatements(migrationSql0007)) {
      await env.DB.prepare(stmt).run();
    }

    // ─── Columns + types ───
    for (const table of ['salary_cycles', 'salary_payments']) {
      const cols = await columnsOf(table);
      const info = cols.get('employee_uuid');
      expect(info, `${table}.employee_uuid missing`).toBeDefined();
      expect(info!.type).toBe('TEXT');
      expect(info!.notnull).toBe(0);
    }

    // ─── salary_withdrawals healing ───
    // Seeded employees autoincrement ids: uuid-a=1, uuid-b=2,
    // uuid-c=3 (deleted), uuid-d=4, uuid-e=5.
    // wd-1: employee_id=5 → server_id=5 unique (uuid-a) wins over the
    //       e.id=5 employee (uuid-e) — server_id precedence proven.
    // wd-2: employee_id=7 → server_id=7 unique → uuid-b
    // wd-3: employee_id=1 → server_id=1 ambiguous (deleted + live) →
    //       live-preference → uuid-d
    // wd-4: employee_id=3 → no server_id=3 → e.id fallback → uuid-c
    //       (deleted — historical rows may reference historical employees)
    // wd-5: employee_id=99 → orphan → stays NULL (preserved).
    const wd = await env.DB.prepare(
      `SELECT local_uuid, employee_uuid FROM salary_withdrawals ORDER BY local_uuid`
    ).all<{ local_uuid: string; employee_uuid: string | null }>();
    const wdMap = new Map(wd.results.map((r) => [r.local_uuid, r.employee_uuid]));
    expect(wdMap.get('wd-1')).toBe('uuid-a');
    expect(wdMap.get('wd-2')).toBe('uuid-b');
    expect(wdMap.get('wd-3')).toBe('uuid-d');
    expect(wdMap.get('wd-4')).toBe('uuid-c'); // e.id=3 → uuid-c (deleted)
    expect(wdMap.get('wd-5')).toBeNull(); // orphan — never dropped, never guessed

    // ─── expenses healing (related_id semantics) ───
    const ex = await env.DB.prepare(
      `SELECT local_uuid, employee_uuid FROM expenses ORDER BY local_uuid`
    ).all<{ local_uuid: string; employee_uuid: string | null }>();
    const exMap = new Map(ex.results.map((r) => [r.local_uuid, r.employee_uuid]));
    expect(exMap.get('ex-1')).toBe('uuid-a'); // related_id=5 → server_id=5
    expect(exMap.get('ex-2')).toBe('uuid-d'); // related_id=1 → ambiguous → live
    expect(exMap.get('ex-3')).toBe('uuid-d'); // related_id=4 → no server_id=4 → e.id=4
    expect(exMap.get('ex-4')).toBeNull(); // orphan

    // ─── salary_cycles healing ───
    const cy = await env.DB.prepare(
      `SELECT local_uuid, employee_uuid FROM salary_cycles ORDER BY local_uuid`
    ).all<{ local_uuid: string; employee_uuid: string | null }>();
    const cyMap = new Map(cy.results.map((r) => [r.local_uuid, r.employee_uuid]));
    expect(cyMap.get('cy-uuid-1')).toBe('uuid-a'); // employee_id=5
    expect(cyMap.get('cy-uuid-2')).toBeNull(); // orphan

    // ─── salary_payments healing (via its cycle) ───
    const sp = await env.DB.prepare(
      `SELECT local_uuid, employee_uuid FROM salary_payments ORDER BY local_uuid`
    ).all<{ local_uuid: string; employee_uuid: string | null }>();
    expect(sp.results[0]!.employee_uuid).toBe('uuid-a'); // cycle cy-uuid-1

    // ─── Zero data loss ───
    const withdrawalsAfter = await env.DB.prepare(
      'SELECT COUNT(*) AS n FROM salary_withdrawals'
    ).first<{ n: number }>();
    const expensesAfter = await env.DB.prepare(
      'SELECT COUNT(*) AS n FROM expenses'
    ).first<{ n: number }>();
    expect(withdrawalsAfter!.n).toBe(withdrawalsBefore!.n);
    expect(expensesAfter!.n).toBe(expensesBefore!.n);
    // Amounts untouched.
    const amounts = await env.DB.prepare(
      `SELECT local_uuid, amount FROM salary_withdrawals WHERE local_uuid = 'wd-5'`
    ).first<{ amount: number }>();
    expect(amounts!.amount).toBe(500);
  });
});
