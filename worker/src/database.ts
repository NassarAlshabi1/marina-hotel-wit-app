// ═══════════════════════════════════════════════════════════════
//  database.ts — D1 Database Layer
//  Handles all SQL queries with parameterized statements (SQL injection safe)
// ═══════════════════════════════════════════════════════════════

import type { D1Database } from '@cloudflare/workers-types';

// ─── Types ────────────────────────────────────────────────────

export interface SyncRecord {
  id: string;
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

const ENTITY_TABLES: Record<string, string> = {
  rooms: 'rooms',
  bookings: 'bookings',
  payments: 'payments',
  expenses: 'expenses',
  employees: 'employees',
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

// ─── Database wrapper ─────────────────────────────────────────

export class Database {
  constructor(private db: D1Database) {}

  // ─── Delta Pull ────────────────────────────────────────────

  async pullChanges(
    entity: string | null,
    cursor: number,
    limit: number = 200
  ): Promise<PullResult> {
    const entities = entity ? [entity] : Object.keys(ENTITY_TABLES);
    const allChanges: SyncRecord[] = [];
    let maxTimestamp = cursor;

    for (const ent of entities) {
      const table = ENTITY_TABLES[ent];
      const stmt = this.db.prepare(
        `SELECT * FROM ${table} WHERE updated_at > ? ORDER BY updated_at ASC LIMIT ?`
      );
      const rows = await stmt.bind(cursor, limit).all();
      for (const row of rows.results) {
        const record = row as unknown as SyncRecord;
        allChanges.push(record);
        if (record.updated_at > maxTimestamp) {
          maxTimestamp = record.updated_at;
        }
      }
    }

    // Sort all changes by updated_at
    allChanges.sort((a, b) => a.updated_at - b.updated_at);

    // Paginate
    const page = allChanges.slice(0, limit);
    const hasMore = allChanges.length > limit;

    return {
      changes: page,
      cursor: maxTimestamp,
      has_more: hasMore,
    };
  }

  // ─── Push: Create ──────────────────────────────────────────

  async createRecord(
    entity: string,
    data: Record<string, unknown>,
    deviceId: string
  ): Promise<SyncRecord> {
    const table = getTableName(entity);
    const now = Math.floor(Date.now() / 1000);

    // Use local_uuid as the primary identifier — D1 tables use INTEGER autoIncrement for id
    const localUuid = (data.local_uuid as string) || crypto.randomUUID();

    const record: SyncRecord = {
      ...data,
      local_uuid: localUuid,
      server_id: null,
      created_at: (data.created_at as number) || now,
      updated_at: now,
      deleted_at: null,
      version: 1,
      device_id: deviceId,
      vector_clock: JSON.stringify({ [deviceId]: 1 }),
      origin: 'cloud',
    };

    // Remove 'id' — D1 INTEGER autoIncrement will generate it
    delete (record as Record<string, unknown>).id;

    // Fill NOT NULL fields with defaults if not provided
    if (!record.last_modified) (record as Record<string, unknown>).last_modified = now;
    if (!record.created_at_epoch) (record as Record<string, unknown>).created_at_epoch = 0;
    if (!record.last_modified_epoch) (record as Record<string, unknown>).last_modified_epoch = 0;

    // Filter out undefined values (D1 doesn't accept them)
    const cleanRecord: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(record)) {
      if (value !== undefined) {
        cleanRecord[key] = value;
      }
    }

    const columns = Object.keys(cleanRecord);
    const placeholders = columns.map(() => '?').join(', ');
    const values = columns.map((col) => cleanRecord[col]);

    await this.db
      .prepare(`INSERT OR IGNORE INTO ${table} (${columns.join(', ')}) VALUES (${placeholders})`)
      .bind(...values)
      .run();

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
    deviceId: string
  ): Promise<SyncRecord> {
    const table = getTableName(entity);

    // Fetch existing record by local_uuid (not id — id is autoIncrement)
    const existing = await this.db
      .prepare(`SELECT * FROM ${table} WHERE local_uuid = ?`)
      .bind(recordId)
      .first<SyncRecord>();

    if (!existing) {
      // Record doesn't exist — create it instead
      return this.createRecord(entity, { ...data, local_uuid: recordId }, deviceId);
    }

    // ─── Conflict Detection: Vector Clock ───────────────────
    const conflict = this.detectConflict(existing.vector_clock || '{}', vectorClock);
    if (conflict === 'concurrent') {
      // Save conflict
      await this.saveConflict(entity, recordId, existing, data, existing.vector_clock, vectorClock);

      // LWW resolution: compare timestamps
      const incomingTimestamp = (data.updated_at as number) || Math.floor(Date.now() / 1000);
      if (incomingTimestamp <= existing.updated_at) {
        // Local is newer — reject incoming
        return existing;
      }
    }

    // ─── Apply update ────────────────────────────────────────
    const now = Math.floor(Date.now() / 1000);
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

    // Filter out undefined values
    const cleanUpdate: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(updateFields)) {
      if (value !== undefined) {
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
    await this.logSync(entity, recordId, 'update', newVersion, deviceId, updateFields);

    // Return updated record
    return { ...existing, ...updateFields } as SyncRecord;
  }

  // ─── Push: Delete (soft delete) ────────────────────────────

  async deleteRecord(
    entity: string,
    recordId: string,
    deviceId: string
  ): Promise<{ deleted: boolean }> {
    const table = getTableName(entity);
    const now = Math.floor(Date.now() / 1000);

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

  private parseVectorClock(vc: string): Record<string, number> {
    try {
      return JSON.parse(vc) || {};
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
