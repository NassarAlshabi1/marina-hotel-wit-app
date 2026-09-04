/**
 * Outbox processor — applies a batch of push changes to D1.
 * - idempotency via `idempotency_key`
 * - optimistic lock + vector clock merge
 * - tombstone (soft delete) instead of hard delete
 * - push echo immunization (no broadcast back to the sending device)
 */

import { resolveConflict } from './conflictResolver';
import type {
  Env,
  SyncLogEntry,
  SyncPushRequest,
  SyncPushResponse,
  SyncPushResult,
} from '../types';
import {
  getRemoteMetaMap,
  insertOutbox,
  markOutboxDone,
  upsertRemoteMeta,
  writeSyncLog,
} from './database';

const BATCH_LIMIT = 100;

export async function processPush(
  env: Env,
  req: SyncPushRequest,
  deviceId: string,
): Promise<SyncPushResponse> {
  const changes = req.changes.slice(0, BATCH_LIMIT);
  const results: SyncPushResult[] = [];
  const start = Date.now();

  // 1. Persist pending outbox rows first (durable queue).
  for (const c of changes) {
    try {
      await insertOutbox(env.DB, {
        entity: c.entity,
        op: c.op,
        localUuid: c.localUuid,
        serverId: c.serverId ?? null,
        payload: JSON.stringify(c.payload),
        clientTs: c.clientTs,
        idempotencyKey: c.idempotencyKey ?? null,
        deviceId: c.deviceId,
      });
    } catch (e) {
      results.push({
        localUuid: c.localUuid,
        success: false,
        error: e instanceof Error ? e.message : 'outbox insert failed',
      });
    }
  }

  // 2. Apply each change within a single D1 batch transaction.
  const stmts = changes.map((c) => {
    const row = c.payload as Record<string, any>;
    const localUuid = row.localUuid ?? c.localUuid;
    return env.DB.prepare(
      `SELECT * FROM "${c.entity}" WHERE local_uuid = ? LIMIT 1`,
    ).bind(localUuid);
  });
  const existingRows = await env.DB.batch(stmts);

  const applyStmts: D1PreparedStatement[] = [];
  const applied: Array<{ entity: string; id: string; ts: number }> = [];

  for (let i = 0; i < changes.length; i++) {
    const c = changes[i];
    const existing = (existingRows[i]?.results?.[0] as Record<string, unknown>) ?? null;
    const row = c.payload as Record<string, any>;
    const localUuid = row.localUuid ?? c.localUuid;
    const serverId = row.serverId ?? c.serverId ?? null;
    const updatedAt = (row.updatedAt as number) ?? Math.floor(Date.now() / 1000);

    const res = resolveConflict({
      incoming: row,
      existing,
      incomingDeviceId: c.deviceId,
    });

    if (res.action === 'conflict') {
      results.push({
        localUuid: c.localUuid,
        success: false,
        conflict: true,
        error: res.reason,
      });
      continue;
    }

    const merged = res.merged ?? row;
    const cols = Object.keys(merged).filter((k) => k !== 'localUuid');
    const placeholders = cols.map(() => '?').join(', ');
    const values = cols.map((k) => {
      const v = merged[k];
      if (v === undefined || v === null) return null;
      if (typeof v === 'object') return JSON.stringify(v);
      return v;
    });

    applyStmts.push(
      env.DB.prepare(
        `INSERT INTO "${c.entity}" (local_uuid, ${cols.join(', ')})
         VALUES (?, ${placeholders})
         ON CONFLICT(local_uuid) DO UPDATE SET ${cols
           .map((k) => `${k} = excluded.${k}`)
           .join(', ')}`,
      ).bind(localUuid, ...values),
    );
    applied.push({ entity: c.entity, id: localUuid, ts: updatedAt });
    results.push({ localUuid: c.localUuid, success: true, serverId });
  }

  if (applyStmts.length > 0) {
    await env.DB.batch(applyStmts);
  }

  // 3. Update remote_meta for applied rows (metadata-first diff on next pull).
  if (applied.length > 0) {
    const byEntity = new Map<string, Array<{ id: string; ts: number }>>();
    for (const a of applied) {
      const arr = byEntity.get(a.entity) ?? [];
      arr.push({ id: a.id, ts: a.ts });
      byEntity.set(a.entity, arr);
    }
    for (const [entity, rows] of byEntity.entries()) {
      // Keep only the max ts per id.
      const dedup = new Map<string, number>();
      for (const r of rows) {
        const prev = dedup.get(r.id) ?? 0;
        dedup.set(r.id, Math.max(prev, r.ts));
      }
      await upsertRemoteMetaBulk(
        env.DB,
        entity,
        Array.from(dedup.entries()).map(([id, ts]) => ({ id, ts })),
      );
    }
  }

  // 4. Sync log.
  await writeSyncLog(env.DB, {
    deviceId,
    entity: 'multi',
    phase: 'push',
    status: results.every((r) => r.success) ? 'ok' : 'partial',
    records: changes.length,
    durationMs: Date.now() - start,
  });

  return { results };
}