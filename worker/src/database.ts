// ═══════════════════════════════════════════════════════════════
//  database.ts — D1 Database Layer
//  Handles all SQL queries with parameterized statements (SQL injection safe)
// ═══════════════════════════════════════════════════════════════

import type { D1Database } from '@cloudflare/workers-types';

// ─── Types ────────────────────────────────────────────────────

export interface SyncRecord {
  id?: string;
  local_uuid: string;
  server_id?: string | null;
  created_at: number;
  updated_at: number;
  deleted_at?: number | null;
  version: number;
  device_id?: string;
  vector_clock?: string;
  origin?: string;
  idempotency_key?: string | null;
  [key: string]: unknown;
}

export interface PullResult {
  changes: SyncRecord[];
  cursor: number;
  has_more: boolean;
}

export interface PushOperation {
  idempotencyKey: string;
  entity: string;
  operation: 'create' | 'update' | 'delete';
  data: Record<string, unknown>;
  vectorClock: string;
  updatedAt: number;
  deviceId?: string;
}

// ─── Entity table mapping ─────────────────────────────────────
// 1:1 mapping — entity name = D1 table name (matches Drift SQLite schema)
// 23 synced entities (plan D7/D8 + user directive 2026-09-05):
//   * inventory_items / inventory_transactions / blacklist added — the
//     Appwrite contract (27 collections) includes them and omitting them
//     meant inventory & blacklist writes were silently lost.
//   * app_users added (user directive 2026-09-05: default sync scope
//     includes user_app with pull/push + outbox delta sync) — the entity
//     was synced via Appwrite Cloud (appwrite_config.dart:116,
//     outbox_dao.dart _entityTableMap, auth_local_store outbox ops) but
//     the Cloudflare layer dropped it entirely; local Drift table
//     AppUsers added (schemaVersion 66) as the pull landing zone.
//   * hotel_day_ledger REMOVED (plan D8): it is local-only by design
//     (Appwrite sync manager never synced it either) — keeping it in the
//     mapping invited stuck pushes for a table clients never upload.

const ENTITY_TABLES: Record<string, string> = {
  // Core hotel entities
  rooms: 'rooms',
  bookings: 'bookings',
  payments: 'payments',
  expenses: 'expenses',
  employees: 'employees',
  debts: 'debts',

  // Booking-related
  booking_notes: 'booking_notes',
  booking_nights: 'booking_nights',
  booking_price_adjustments: 'booking_price_adjustments',
  guest_infos: 'guest_infos',

  // Shift & cash
  shift_notes: 'shift_notes',
  cash_transactions: 'cash_transactions',

  // Salary
  salary_cycles: 'salary_cycles',
  salary_payments: 'salary_payments',
  salary_withdrawals: 'salary_withdrawals',
  salary_carry_over_logs: 'salary_carry_over_logs',

  // Adjustments & audit
  price_adjustments: 'price_adjustments',
  audit_logs: 'audit_logs',
  payment_voids: 'payment_voids',

  // Inventory (gap closure — was silently missing)
  inventory_items: 'inventory_items',
  inventory_transactions: 'inventory_transactions',

  // App users (auth accounts — user directive 2026-09-05; local Drift
  // table AppUsers is the pull landing zone / push source)
  app_users: 'app_users',

  // Blacklist (cloud-only entity, no Drift table client-side)
  blacklist: 'blacklist',
};

const VALID_ENTITIES = new Set(Object.keys(ENTITY_TABLES));

export function isValidEntity(entity: string): boolean {
  return VALID_ENTITIES.has(entity);
}

export function getTableName(entity: string): string {
  const table = ENTITY_TABLES[entity];
  if (!table) {
    throw new Error(`Unknown entity: ${entity}`);
  }
  return table;
}

/** Every physical table the API touches (entities + infrastructure). */
export const ALL_TABLE_NAMES: string[] = [
  ...Object.keys(ENTITY_TABLES),
  'users',
  'devices',
  'rate_limits',
];

/** Physical table names that bulk migration may write to (entities only). */
export const SYNC_ENTITY_TABLES: readonly string[] = Object.values(ENTITY_TABLES);

// ─── Database wrapper ─────────────────────────────────────────

export class Database {
  constructor(private readonly db: D1Database) {}

  /** Raw D1 access for narrowly scoped infrastructure queries. */
  get raw(): D1Database {
    return this.db;
  }

  // ─── Sync Clock (monotonic unique updated_at allocator) ───────

  /**
   * Allocate a globally-unique, strictly-monotonic `updated_at` (seconds).
   * Single atomic statement against the sync_clock singleton; two concurrent
   * writes can therefore never share the same updated_at, which is what
   * makes the integer pull cursor lossless.
   */
  async allocateUpdatedAt(): Promise<number> {
    const now = Math.floor(Date.now() / 1000);
    const result = await this.db
      .prepare(
        'UPDATE sync_clock SET last_ts = MAX(last_ts + 1, ?) WHERE id = 1 RETURNING last_ts'
      )
      .bind(now)
      .first<{ last_ts: number }>();

    if (result && typeof result.last_ts === 'number') {
      return result.last_ts;
    }

    // Singleton row missing (DB created before seeding) — seed and retry once.
    await this.db
      .prepare('INSERT OR IGNORE INTO sync_clock (id, last_ts) VALUES (1, ?)')
      .bind(now)
      .run();
    const retry = await this.db
      .prepare(
        'UPDATE sync_clock SET last_ts = MAX(last_ts + 1, ?) WHERE id = 1 RETURNING last_ts'
      )
      .bind(now)
      .first<{ last_ts: number }>();
    if (retry && typeof retry.last_ts === 'number') {
      return retry.last_ts;
    }
    throw new Error('sync_clock allocation failed');
  }

  /** Advance the sync clock past a foreign timestamp (e.g. after bulk migration). */
  async advanceSyncClock(minTs: number): Promise<void> {
    if (!Number.isFinite(minTs) || minTs <= 0) return;
    await this.db
      .prepare('UPDATE sync_clock SET last_ts = MAX(last_ts, ?) WHERE id = 1')
      .bind(Math.floor(minTs))
      .run();
  }

  /** MAX(updated_at) across every synced entity table. */
  async maxUpdatedAtAcrossEntities(): Promise<number> {
    // One MAX query per table — a single `SELECT MAX(m) FROM (…22 UNION ALL…)`
    // trips D1's compound-SELECT term limit ("too many terms in compound
    // SELECT"), which silently broke sync_clock advancement after every
    // migration. Per-table queries + a JS max are immune.
    let max = 0;
    for (const table of Object.values(ENTITY_TABLES)) {
      const row = await this.db
        .prepare(`SELECT MAX(updated_at) AS m FROM ${table}`)
        .first<{ m: number | string | null }>();
      const v = Number(row?.m ?? 0);
      if (Number.isFinite(v) && v > max) max = v;
    }
    return max;
  }

  // ─── Delta Pull ────────────────────────────────────────────

  async pullChanges(
    entity: string | null,
    cursor: number,
    limit: number = 200,
    excludeDeviceId?: string
  ): Promise<PullResult> {
    const entities = entity ? [entity] : Object.keys(ENTITY_TABLES);
    const fetchLimit = Math.max(1, limit) + 1; // +1 → detect overflow cheaply
    const allChanges: SyncRecord[] = [];

    // Echo filter (plan 2.5): a device that already applied its own push
    // must not receive its own rows back — skipping them removes the
    // guaranteed-empty delta cycle after every local change. Server-written
    // rows (device_id '') are never excluded.
    const excludeDevice =
      excludeDeviceId && excludeDeviceId.length > 0 ? excludeDeviceId : null;

    for (const ent of entities) {
      const table = ENTITY_TABLES[ent];
      const rows = excludeDevice
        ? await this.db
            .prepare(
              `SELECT * FROM ${table} WHERE updated_at > ? AND (device_id IS NULL OR device_id != ?) ORDER BY updated_at ASC, local_uuid ASC LIMIT ?`
            )
            .bind(cursor, excludeDevice, fetchLimit)
            .all()
        : await this.db
            .prepare(
              `SELECT * FROM ${table} WHERE updated_at > ? ORDER BY updated_at ASC, local_uuid ASC LIMIT ?`
            )
            .bind(cursor, fetchLimit)
            .all();
      for (const row of rows.results) {
        const record = row as unknown as SyncRecord;
        // ✅ أضف _entity لكل سجل ليتمكن Flutter من معرفة الجدول
        // بدون الحاجة لتخمين نوعه من الحقول
        (record as Record<string, unknown>)._entity = ent;
        allChanges.push(record);
      }
    }

    // Global deterministic order across tables.
    // updated_at is unique for server-written rows (sync_clock allocator);
    // local_uuid is the tie-breaker for any legacy rows.
    allChanges.sort((a, b) => {
      if (a.updated_at !== b.updated_at) return a.updated_at - b.updated_at;
      return String(a.local_uuid).localeCompare(String(b.local_uuid));
    });

    // Paginate
    const page = allChanges.slice(0, limit);
    const hasMore = allChanges.length > limit;

    // ✅ CRITICAL FIX: cursor must be the updated_at of the LAST record
    // actually returned in this page — never the max across all fetched
    // rows (the old code returned the global max, permanently skipping
    // every record between the page boundary and that max).
    const nextCursor = page.length > 0 ? page[page.length - 1].updated_at : cursor;

    return {
      changes: page,
      cursor: nextCursor,
      has_more: hasMore,
    };
  }

  // ─── Push: Create ──────────────────────────────────────────

  // Cache: table name → Set of valid column names (avoids repeated PRAGMA queries)
  private _tableColumnsCache: Map<string, Set<string>> = new Map();

  /**
   * Get the set of valid column names for a table.
   * Cached to avoid repeated PRAGMA queries.
   */
  async getTableColumns(table: string): Promise<Set<string>> {
    const cached = this._tableColumnsCache.get(table);
    if (cached) return cached;

    const result = await this.db
      .prepare(`PRAGMA table_info(${table})`)
      .all<{ name: string; notnull: number; dflt_value: string | null; type: string }>();

    const cols = new Set<string>();
    for (const row of result.results) {
      cols.add(row.name);
    }
    this._tableColumnsCache.set(table, cols);
    return cols;
  }

  async createRecord(
    entity: string,
    data: Record<string, unknown>,
    deviceId: string,
    clientVectorClock?: string
  ): Promise<SyncRecord> {
    const table = getTableName(entity);
    const now = Math.floor(Date.now() / 1000);

    // Use local_uuid as the primary identifier — D1 tables use INTEGER autoIncrement for id
    const localUuid = (data.local_uuid as string) || crypto.randomUUID();

    // ✅ Globally-unique updated_at (keeps the pull cursor lossless)
    const serverUpdatedAt = await this.allocateUpdatedAt();

    // ✅ Respect the client's vector clock when it is a valid object;
    // otherwise seed a fresh clock for this device.
    const clientVc = this.parseVectorClock(clientVectorClock || '{}');
    const vectorClockJson =
      Object.keys(clientVc).length > 0
        ? JSON.stringify(clientVc)
        : JSON.stringify({ [deviceId]: 1 });

    const createdAtNum = Number(data.created_at);

    const record: SyncRecord = {
      ...data,
      local_uuid: localUuid,
      server_id: null,
      created_at:
        Number.isFinite(createdAtNum) && createdAtNum > 0
          ? Math.floor(createdAtNum)
          : now,
      updated_at: serverUpdatedAt,
      deleted_at: null,
      version: 1,
      device_id: deviceId,
      vector_clock: vectorClockJson,
      origin: 'cloud',
    };

    // Remove 'id' — D1 INTEGER autoIncrement will generate it
    delete (record as Record<string, unknown>).id;

    // Fill NOT NULL fields with defaults if not provided
    if (!record.last_modified) (record as Record<string, unknown>).last_modified = now;
    if (!record.created_at_epoch) (record as Record<string, unknown>).created_at_epoch = 0;
    if (!record.last_modified_epoch) (record as Record<string, unknown>).last_modified_epoch = 0;

    // ─── Filter to only columns that exist in the target table ───
    // This prevents "no such column" errors when data contains fields
    // from a different entity (e.g. guest_phone in debts data).
    const validColumns = await this.getTableColumns(table);
    const cleanRecord: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(record)) {
      if (value !== undefined && validColumns.has(key)) {
        cleanRecord[key] = value;
      }
    }

    // ─── Fill NOT NULL columns (without defaults) with empty values ───
    // Get the column metadata to identify NOT NULL columns without defaults
    const colMeta = await this.db
      .prepare(`PRAGMA table_info(${table})`)
      .all<{ name: string; notnull: number; dflt_value: string | null; type: string }>();

    for (const col of colMeta.results) {
      // Skip if column has a default, is nullable, is PK/id, or is already in cleanRecord
      if (col.dflt_value !== null) continue;
      if (col.notnull === 0) continue;
      if (col.name === 'id' || col.name === 'local_uuid') continue;
      if (col.name in cleanRecord) continue;

      // Fill with appropriate empty value based on type
      const typeLower = col.type.toLowerCase();
      if (typeLower === 'integer' || typeLower === 'real' || typeLower === 'numeric') {
        cleanRecord[col.name] = 0;
      } else {
        cleanRecord[col.name] = '';
      }
    }

    const columns = Object.keys(cleanRecord);
    const placeholders = columns.map(() => '?').join(', ');
    const values = columns.map((col) => cleanRecord[col]);

    // Use INSERT OR IGNORE for idempotency (duplicate local_uuid = skip)
    // but check the actual row count to detect silent failures
    const insertResult = await this.db
      .prepare(`INSERT OR IGNORE INTO ${table} (${columns.join(', ')}) VALUES (${placeholders})`)
      .bind(...values)
      .run();

    // If no rows were written, check if the record already exists
    // (idempotent skip) or if there was a silent constraint violation
    if (insertResult.meta.changes === 0) {
      const existing = await this.db
        .prepare(`SELECT local_uuid FROM ${table} WHERE local_uuid = ?`)
        .bind(localUuid)
        .first<{ local_uuid: string }>();

      if (!existing) {
        // Not a duplicate — a constraint was silently violated.
        // Retry with a plain INSERT to surface the actual error.
        console.error(`[CREATE] Silent insert failure for ${entity}/${localUuid}. Retrying with plain INSERT to surface error.`);
        await this.db
          .prepare(`INSERT INTO ${table} (${columns.join(', ')}) VALUES (${placeholders})`)
          .bind(...values)
          .run();
      }
    }

    // Log to sync_log — use local_uuid as entity_id
    await this.logSync(entity, localUuid, 'create', 1, deviceId, record);

    return record;
  }

  // ─── Push: Update ──────────────────────────────────────────

  async updateRecord(
    entity: string,
    recordId: string,
    data: Record<string, unknown>,
    vectorClock: string,
    deviceId: string,
    fallbackUpdatedAt?: number
  ): Promise<SyncRecord> {
    const table = getTableName(entity);

    // Fetch existing record by local_uuid (not id — id is autoIncrement)
    const existing = await this.db
      .prepare(`SELECT * FROM ${table} WHERE local_uuid = ?`)
      .bind(recordId)
      .first<SyncRecord>();

    if (!existing) {
      // Record doesn't exist — create it instead
      return this.createRecord(entity, { ...data, local_uuid: recordId }, deviceId, vectorClock);
    }

    // ─── Conflict Detection: Vector Clock ───────────────────
    const conflict = this.detectConflict(existing.vector_clock || '{}', vectorClock);
    // LWW input precedence (fix proven by test + client code): the op-level
    // `updatedAt` (outbox clientTs, cloudflare_sync_manager.dart:857) is the
    // authoritative edit timestamp of the operation; `data.updated_at` is a
    // row snapshot that can be stale relative to the edit. The protocol
    // field wins; the row field is the legacy fallback.
    const incomingTimestamp =
      fallbackUpdatedAt !== undefined && Number.isFinite(fallbackUpdatedAt)
        ? Math.floor(fallbackUpdatedAt)
        : Number(data.updated_at) || Math.floor(Date.now() / 1000);

    // LWW resolution (plan 2.4): wall-clock timestamps are not monotonic
    // across devices (a slow clock must not win) — timestamps decide only
    // when they DIFFER; on a tie the monotonic `version` counter decides.
    // The client increments SyncFields.version on every local edit, so a
    // genuinely newer edit from a slow-clock device still carries a higher
    // version and wins the tie instead of being silently dropped.
    const timestampLoss =
      incomingTimestamp < existing.updated_at ||
      (incomingTimestamp === existing.updated_at &&
        !this.incomingVersionWins(existing.version, data.version));

    if (conflict === 'concurrent') {
      // Save conflict for audit
      await this.saveConflict(entity, recordId, existing, data, existing.vector_clock ?? '{}', vectorClock);

      if (timestampLoss) {
        // Server copy is newer — reject incoming
        return existing;
      }
    } else if (conflict === 'local_newer') {
      // ✅ FIX: server state strictly dominates the client clock — the edit
      // was made against stale data. The old code fell through and APPLIED
      // it, regressing fields the server had already superseded. Apply only
      // if the client demonstrably edited later (later timestamp, or an
      // equal timestamp with a strictly higher version); otherwise reject.
      if (timestampLoss) {
        return existing;
      }
    }
    // 'equal' | 'remote_newer' → apply

    // ─── Apply update ────────────────────────────────────────
    const now = await this.allocateUpdatedAt();
    const newVersion = existing.version + 1;

    // Merge vector clocks
    const mergedVc = this.mergeVectorClocks(existing.vector_clock || '{}', vectorClock);

    // Build UPDATE SET clause
    const updateFields = { ...data };
    updateFields.updated_at = now;
    updateFields.version = newVersion;
    updateFields.vector_clock = mergedVc;
    updateFields.device_id = deviceId;

    // Remove fields that shouldn't be updated
    delete updateFields.id;
    delete updateFields.local_uuid;
    delete updateFields.created_at;
    delete updateFields.server_id;

    // ✅ SECURITY FIX: whitelist column names against the real table schema.
    // `data` keys were previously interpolated raw into the SET clause — a
    // malicious client could craft keys containing SQL (balancing '?'
    // placeholders and commenting out the trailing WHERE) to run arbitrary
    // UPDATE logic. Values stay bound; identifiers must come from
    // PRAGMA table_info only.
    const validColumns = await this.getTableColumns(table);
    const cleanUpdate: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(updateFields)) {
      if (value !== undefined && validColumns.has(key)) {
        cleanUpdate[key] = value;
      }
    }

    const setClauses = Object.keys(cleanUpdate)
      .map((col) => `${col} = ?`)
      .join(', ');
    const values = Object.keys(cleanUpdate).map((col) => cleanUpdate[col]);

    await this.db
      .prepare(`UPDATE ${table} SET ${setClauses} WHERE local_uuid = ?`)
      .bind(...values, recordId)
      .run();

    // Log to sync_log
    await this.logSync(entity, recordId, 'update', newVersion, deviceId, cleanUpdate);

    // Return updated record
    return { ...existing, ...cleanUpdate } as SyncRecord;
  }

  // ─── Push: Delete (soft delete) ────────────────────────────

  async deleteRecord(
    entity: string,
    recordId: string,
    deviceId: string
  ): Promise<{ deleted: boolean }> {
    const table = getTableName(entity);
    // ✅ Tombstones must be pullable too — allocate a unique updated_at so
    // the deletion surfaces exactly once in every client's delta stream.
    const now = await this.allocateUpdatedAt();

    const existing = await this.db
      .prepare(`SELECT version FROM ${table} WHERE local_uuid = ?`)
      .bind(recordId)
      .first<{ version: number }>();

    if (!existing) {
      return { deleted: false };
    }

    const newVersion = existing.version + 1;

    await this.db
      .prepare(
        `UPDATE ${table} SET deleted_at = ?, updated_at = ?, version = ? WHERE local_uuid = ?`
      )
      .bind(now, now, newVersion, recordId)
      .run();

    await this.logSync(entity, recordId, 'delete', newVersion, deviceId, null);

    return { deleted: true };
  }

  // ─── Idempotency Check ─────────────────────────────────────

  async checkIdempotency(key: string): Promise<{ exists: boolean; response?: unknown }> {
    const result = await this.db
      .prepare('SELECT response FROM idempotency_log WHERE key = ?')
      .bind(key)
      .first<{ response: string }>();

    if (result) {
      return { exists: true, response: JSON.parse(result.response) };
    }
    return { exists: false };
  }

  async saveIdempotency(key: string, entity: string, operation: string, entityId: string, response: unknown): Promise<void> {
    const now = Math.floor(Date.now() / 1000);
    await this.db
      .prepare(
        'INSERT OR IGNORE INTO idempotency_log (key, entity, operation, entity_id, processed_at, response) VALUES (?, ?, ?, ?, ?, ?)'
      )
      .bind(key, entity, operation, entityId, now, JSON.stringify(response))
      .run();
  }

  // ─── Sync Log ──────────────────────────────────────────────

  async logSync(
    entity: string,
    entityId: string,
    operation: string,
    version: number,
    deviceId: string,
    payload: unknown
  ): Promise<void> {
    const now = Math.floor(Date.now() / 1000);
    await this.db
      .prepare(
        'INSERT INTO sync_log (entity, entity_id, operation, version, device_id, timestamp, payload) VALUES (?, ?, ?, ?, ?, ?, ?)'
      )
      .bind(entity, entityId, operation, version, deviceId, now, payload ? JSON.stringify(payload) : null)
      .run();
  }

  // ─── Sync Log / Conflicts queries (typed, no private-field hacks) ─

  async getSyncLog(limit: number, offset: number): Promise<unknown[]> {
    const result = await this.db
      .prepare('SELECT * FROM sync_log ORDER BY timestamp DESC, id DESC LIMIT ? OFFSET ?')
      .bind(limit, offset)
      .all();
    return result.results;
  }

  async getConflicts(limit: number): Promise<unknown[]> {
    const result = await this.db
      .prepare('SELECT * FROM sync_conflicts ORDER BY created_at DESC, id DESC LIMIT ?')
      .bind(limit)
      .all();
    return result.results;
  }

  // ─── Conflict Handling ─────────────────────────────────────

  private detectConflict(localVc: string, remoteVc: string): 'equal' | 'local_newer' | 'remote_newer' | 'concurrent' {
    const local = this.parseVectorClock(localVc);
    const remote = this.parseVectorClock(remoteVc);

    let localNewer = false;
    let remoteNewer = false;

    const allKeys = new Set([...Object.keys(local), ...Object.keys(remote)]);
    for (const key of allKeys) {
      const l = local[key] || 0;
      const r = remote[key] || 0;
      if (l > r) localNewer = true;
      if (r > l) remoteNewer = true;
    }

    if (localNewer && remoteNewer) return 'concurrent';
    if (localNewer) return 'local_newer';
    if (remoteNewer) return 'remote_newer';
    return 'equal';
  }

  private async saveConflict(
    entity: string,
    entityId: string,
    localRecord: unknown,
    remoteData: unknown,
    localVc: string,
    remoteVc: string
  ): Promise<void> {
    const now = Math.floor(Date.now() / 1000);
    await this.db
      .prepare(
        `INSERT INTO sync_conflicts (entity, entity_id, local_payload, remote_payload, local_vector_clock, remote_vector_clock, resolution, resolved_at, created_at, device_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
      )
      .bind(
        entity,
        entityId,
        JSON.stringify(localRecord),
        JSON.stringify(remoteData),
        localVc,
        remoteVc,
        'last_write_wins',
        now,
        now,
        ''
      )
      .run();
  }

  /**
   * Tie-breaker for equal `updated_at` (plan 2.4): the incoming edit wins
   * only with a strictly higher version. Absent/invalid version loses —
   * old clients without version semantics keep the previous behaviour
   * (server copy wins ties).
   */
  private incomingVersionWins(
    existingVersion: number,
    incomingVersion: unknown
  ): boolean {
    const v = Number(incomingVersion);
    return Number.isFinite(v) && v > existingVersion;
  }

  private parseVectorClock(vc: string): Record<string, number> {
    try {
      const parsed: unknown = JSON.parse(vc);
      if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
        return {};
      }
      const out: Record<string, number> = {};
      for (const [key, value] of Object.entries(parsed as Record<string, unknown>)) {
        const num = Number(value);
        if (key.length > 0 && Number.isFinite(num)) {
          out[key] = num;
        }
      }
      return out;
    } catch {
      return {};
    }
  }

  private mergeVectorClocks(local: string, remote: string): string {
    const l = this.parseVectorClock(local);
    const r = this.parseVectorClock(remote);
    const merged: Record<string, number> = { ...l };
    for (const [key, val] of Object.entries(r)) {
      merged[key] = Math.max(merged[key] || 0, val);
    }
    return JSON.stringify(merged);
  }

  // ─── User Auth ─────────────────────────────────────────────

  async getUser(username: string): Promise<{ id: string; password_hash: string; role: string } | null> {
    return this.db
      .prepare('SELECT id, password_hash, role FROM users WHERE username = ? AND deleted_at IS NULL')
      .bind(username)
      .first<{ id: string; password_hash: string; role: string }>();
  }

  async countActiveUsers(): Promise<number> {
    const row = await this.db
      .prepare('SELECT COUNT(*) AS count FROM users WHERE deleted_at IS NULL')
      .first<{ count: number | string }>();
    return Number(row?.count ?? 0);
  }

  async createUser(username: string, passwordHash: string, role: string): Promise<string> {
    const id = crypto.randomUUID();
    const now = Math.floor(Date.now() / 1000);
    await this.db
      .prepare('INSERT INTO users (id, username, password_hash, role, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)')
      .bind(id, username, passwordHash, role, now, now)
      .run();
    return id;
  }

  // ─── Device Management (for FCM) ────────────────────────────

  async registerDevice(
    deviceId: string,
    fcmToken: string | null,
    deviceName?: string,
    platform?: string
  ): Promise<void> {
    const now = Math.floor(Date.now() / 1000);
    // Ensure devices table exists
    await this.db.prepare(
      `CREATE TABLE IF NOT EXISTS devices (
        id TEXT PRIMARY KEY,
        device_id TEXT NOT NULL UNIQUE,
        fcm_token TEXT,
        status TEXT DEFAULT 'active',
        device_name TEXT,
        platform TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )`
    ).run();

    // Upsert device
    await this.db.prepare(
      `INSERT INTO devices (id, device_id, fcm_token, status, device_name, platform, created_at, updated_at)
       VALUES (?, ?, ?, 'active', ?, ?, ?, ?)
       ON CONFLICT(device_id) DO UPDATE SET
         fcm_token = excluded.fcm_token,
         status = 'active',
         device_name = excluded.device_name,
         platform = excluded.platform,
         updated_at = excluded.updated_at`
    ).bind(
      crypto.randomUUID(),
      deviceId,
      fcmToken,
      deviceName || null,
      platform || null,
      now,
      now
    ).run();
  }

  async getDeviceTokens(excludeDeviceId?: string): Promise<string[]> {
    const stmt = excludeDeviceId
      ? this.db.prepare('SELECT fcm_token FROM devices WHERE status = ? AND fcm_token IS NOT NULL AND fcm_token != ? AND device_id != ?')
      : this.db.prepare('SELECT fcm_token FROM devices WHERE status = ? AND fcm_token IS NOT NULL');

    const result = excludeDeviceId
      ? await stmt.bind('active', '', excludeDeviceId).all()
      : await stmt.bind('active').all();

    return result.results
      .map((r) => (r as { fcm_token?: string }).fcm_token)
      .filter((t): t is string => !!t && t.length > 0);
  }

  async setDeviceFcmToken(deviceId: string, fcmToken: string): Promise<void> {
    const now = Math.floor(Date.now() / 1000);
    await this.db.prepare(
      `UPDATE devices SET fcm_token = ?, updated_at = ? WHERE device_id = ?`
    ).bind(fcmToken, now, deviceId).run();
  }
}
