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
