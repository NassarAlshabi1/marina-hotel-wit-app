/**
 * D1 helpers — thin wrapper around `DB` with prepared statements.
 * Mirrors `mobile/lib/services/local_db.dart` + `remote_meta` / `entity_watermark` tables.
 */

import type { Env } from './types';

export const DB_SCHEMA = {
  remoteMeta: 'remote_meta',
  entityWatermark: 'entity_watermark',
  outbox: 'outbox',
  syncLog: 'sync_log',
} as const;

/** Upsert a `$updatedAt` for a doc id in `remote_meta` (used by metadata-first pull). */
export async function upsertRemoteMeta(
  db: D1Database,
  entity: string,
  docId: string,
  updatedAt: number,
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO remote_meta (entity, doc_id, updated_at)
       VALUES (?, ?, ?)
       ON CONFLICT(entity, doc_id) DO UPDATE SET excluded.updated_at`,
    )
    .bind(entity, docId, updatedAt)
    .run();
}

/** Bulk upsert metadata rows. */
export async function upsertRemoteMetaBulk(
  db: D1Database,
  entity: string,
  rows: Array<{ id: string; ts: number }>,
): Promise<void> {
  if (rows.length === 0) return;
  const stmts = rows.map((r) =>
    db
      .prepare(
        `INSERT INTO remote_meta (entity, doc_id, updated_at)
         VALUES (?, ?, ?)
         ON CONFLICT(entity, doc_id) DO UPDATE SET excluded.updated_at`,
      )
      .bind(entity, r.id, r.ts),
  );
  await db.batch(stmts);
}

/** Get the local `$updatedAt` cache for an entity (metadata-first diff). */
export async function getRemoteMetaMap(
  db: D1Database,
  entity: string,
): Promise<Map<string, number>> {
  const { results } = await db
    .prepare(`SELECT doc_id, updated_at FROM remote_meta WHERE entity = ?`)
    .bind(entity)
    .all<{ doc_id: string; updated_at: number }>();
  const map = new Map<string, number>();
  for (const r of results ?? []) map.set(r.doc_id, r.updated_at);
  return map;
}

/** Read the per-entity pull watermark (last pull ts). */
export async function getWatermark(
  db: D1Database,
  entity: string,
): Promise<number> {
  const { results } = await db
    .prepare(`SELECT last_pull_ts FROM entity_watermark WHERE entity = ?`)
    .bind(entity)
    .all<{ last_pull_ts: number }>();
  return results?.[0]?.last_pull_ts ?? 0;
}

/** Read the per-entity server-authoritative max (closes the delta window). */
export async function getWatermarkServerMax(
  db: D1Database,
  entity: string,
): Promise<number> {
  const { results } = await db
    .prepare(`SELECT last_server_max FROM entity_watermark WHERE entity = ?`)
    .bind(entity)
    .all<{ last_server_max: number }>();
  return results?.[0]?.last_server_max ?? 0;
}

/** Advance the watermark to the server max (server-authoritative). */
export async function setWatermark(
  db: D1Database,
  entity: string,
  lastPullTs: number,
  lastServerMax: number,
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO entity_watermark (entity, last_pull_ts, last_server_max)
       VALUES (?, ?, ?)
       ON CONFLICT(entity) DO UPDATE SET
         excluded.last_pull_ts,
         excluded.last_server_max`,
    )
    .bind(entity, lastPullTs, lastServerMax)
    .run();
}

/** Insert an outbox entry (returns the new row id). */
export async function insertOutbox(
  db: D1Database,
  entry: {
    entity: string;
    op: string;
    localUuid: string;
    serverId: number | null;
    payload: string;
    clientTs: number;
    idempotencyKey: string | null;
    deviceId: string;
  },
): Promise<number | null> {
  const { success, meta } = await db
    .prepare(
      `INSERT INTO outbox
         (entity, op, local_uuid, server_id, payload, client_ts,
          idempotency_key, device_id, processing_status)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending')`,
    )
    .bind(
      entry.entity,
      entry.op,
      entry.localUuid,
      entry.serverId,
      entry.payload,
      entry.clientTs,
      entry.idempotencyKey,
      entry.deviceId,
    )
    .run();
  return success ? (meta?.last_row_id ?? null) : null;
}

/** Claim pending outbox rows for processing (atomic). */
export async function claimOutbox(
  db: D1Database,
  limit: number,
): Promise<
  Array<{
    id: number;
    entity: string;
    op: string;
    localUuid: string;
    serverId: number | null;
    payload: string;
    clientTs: number;
    idempotencyKey: string | null;
    deviceId: string;
    attempts: number;
  }>
> {
  const { results } = await db
    .prepare(
      `SELECT id, entity, op, local_uuid, server_id, payload, client_ts,
              idempotency_key, device_id, attempts
       FROM outbox
       WHERE processing_status = 'pending'
       ORDER BY client_ts ASC
       LIMIT ?`,
    )
    .bind(limit)
    .all();
  return (results ?? []) as never;
}

/** Mark an outbox row as completed / failed. */
export async function markOutboxDone(
  db: D1Database,
  id: number,
  status: 'completed' | 'failed',
  error?: string,
): Promise<void> {
  await db
    .prepare(
      `UPDATE outbox
       SET processing_status = ?, processing_started_at = ?,
           last_error = ?, attempts = attempts + 1
       WHERE id = ?`,
    )
    .bind(status, Math.floor(Date.now() / 1000), error ?? null, id)
    .run();
}

/** Write a sync log row. */
export async function writeSyncLog(
  db: D1Database,
  entry: {
    deviceId: string;
    entity: string;
    phase: string;
    status: string;
    records: number;
    durationMs: number;
    message?: string;
  },
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO sync_log (device_id, entity, phase, status, records, duration_ms, message, ts)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      entry.deviceId,
      entry.entity,
      entry.phase,
      entry.status,
      entry.records,
      entry.durationMs,
      entry.message ?? null,
      Math.floor(Date.now() / 1000),
    )
    .run();
}