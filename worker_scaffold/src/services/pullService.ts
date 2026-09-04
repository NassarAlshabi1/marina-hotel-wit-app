/**
 * Pull service — metadata-first delta + tombstone-aware.
 * Mirrors the `perf/appwrite-sync-pull-reduction` metadata-first pull:
 *   Phase 1: return only $id + $updatedAt for the time window.
 *   Phase 3: caller fetches full documents for the changed subset.
 */

import type { Env, PullMetadataResponse } from '../types';
import { DEFAULT_INITIAL_PULL_LIMIT, INITIAL_PULL_LIMITS } from '../config';
import {
  getRemoteMetaMap,
  getWatermark,
  setWatermark,
} from './database';

export async function pullMetadata(
  env: Env,
  entities: string[],
  since: number,
  tombstones: boolean,
): Promise<PullMetadataResponse> {
  const response: PullMetadataResponse = {};
  const metaMap = new Map<string, Map<string, number>>();

  for (const entity of entities) {
    const watermark = since > 0 ? since : await getWatermark(env.DB, entity);
    const limit = INITIAL_PULL_LIMITS[entity] ?? DEFAULT_INITIAL_PULL_LIMIT;

    const { results } = await env.DB.prepare(
      `SELECT local_uuid AS $id, updated_at AS $updatedAt,
              COALESCE(deleted_at, 0) AS deleted
       FROM "${entity}"
       WHERE updated_at > ?
       ORDER BY updated_at ASC
       LIMIT ?`,
    )
      .bind(watermark, limit)
      .all<{ $id: string; $updatedAt: number; deleted: number }>();

    const docs = (results ?? []).map((r) => ({
      $id: r.$id,
      $updatedAt: r.$updatedAt,
      deleted: tombstones ? r.deleted > 0 : r.deleted > 0 ? undefined : undefined,
    }));
    response[entity] = docs;
    metaMap.set(entity, new Map(docs.map((d) => [d.$id, d.$updatedAt])));
  }

  return response;
}

/**
 * Pull full documents for the changed subset (metadata-first Phase 3).
 * `ids` are local_uuids that the client determined as changed.
 */
export async function pullFull(
  env: Env,
  entity: string,
  ids: string[],
): Promise<Record<string, unknown>[]> {
  if (ids.length === 0) return [];
  const placeholders = ids.map(() => '?').join(', ');
  const { results } = await env.DB.prepare(
    `SELECT * FROM "${entity}" WHERE local_uuid IN (${placeholders})`,
  )
    .bind(...ids)
    .all<Record<string, unknown>>();
  return results ?? [];
}

/**
 * Pull delta (fallback for clients that don't support metadata-first).
 * Returns all documents in the time window.
 */
export async function pullDelta(
  env: Env,
  entity: string,
  since: number,
): Promise<Record<string, unknown>[]> {
  const watermark = since > 0 ? since : await getWatermark(env.DB, entity);
  const limit = INITIAL_PULL_LIMITS[entity] ?? DEFAULT_INITIAL_PULL_LIMIT;
  const { results } = await env.DB.prepare(
    `SELECT * FROM "${entity}"
     WHERE updated_at > ?
     ORDER BY updated_at ASC
     LIMIT ?`,
  )
    .bind(watermark, limit)
    .all<Record<string, unknown>>();
  return results ?? [];
}

/**
 * Advance the per-entity watermark to the server-authoritative max.
 * Closes the delta window so the next cycle doesn't re-pull the same rows.
 */
export async function checkpointEntity(
  env: Env,
  entity: string,
  serverMaxTs: number,
): Promise<void> {
  const currentPull = await getWatermark(env.DB, entity);
  const nextPull = Math.max(currentPull, serverMaxTs);
  await setWatermark(env.DB, entity, nextPull, serverMaxTs);
}