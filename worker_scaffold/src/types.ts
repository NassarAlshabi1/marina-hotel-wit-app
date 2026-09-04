/**
 * Shared types for the Marina Hotel sync worker.
 * Mirrors the mobile `SyncFields` model + `SyncQueueEntry` outbox shape.
 */
export type SyncOp = 'insert' | 'update' | 'delete';

export interface SyncQueueEntry {
  entity: string;
  op: SyncOp;
  localUuid: string;
  serverId?: number | null;
  payload: Record<string, unknown>;
  clientTs: number;
  idempotencyKey?: string | null;
  deviceId: string;
  source?: 'local' | 'restore';
}

export interface SyncPushRequest {
  changes: SyncQueueEntry[];
}

export interface SyncPushResult {
  localUuid: string;
  success: boolean;
  serverId?: number | null;
  conflict?: boolean;
  error?: string;
}

export interface SyncPushResponse {
  results: SyncPushResult[];
}

export interface PullMetadataDoc {
  $id: string;
  $updatedAt: number;
  deleted?: boolean;
}

export interface PullMetadataResponse {
  [entity: string]: PullMetadataDoc[];
}

export interface PullRequest {
  entities: string[];
  ids: string[];
}

export interface PullResponse {
  [entity: string]: Record<string, unknown>[];
}

export interface PullDeltaRequest {
  entity: string;
  since: number;
}

export interface PullDeltaResponse {
  entity: string;
  documents: Record<string, unknown>[];
}

export interface HealthResponse {
  status: 'ok' | 'degraded';
  db: 'ok' | 'fail';
  kv: 'ok' | 'fail';
  ts: number;
}

export interface SyncLogEntry {
  deviceId: string;
  entity: string;
  phase: 'push' | 'pull_metadata' | 'pull_delta' | 'apply';
  status: 'ok' | 'partial' | 'failed';
  records: number;
  durationMs: number;
  message?: string;
}

export interface DeviceContext {
  deviceId: string;
  hotelId: string;
  userId?: string;
}

export interface Env {
  DB: D1Database;
  RATE_KV: KVNamespace;
  SyncSession: DurableObjectNamespace;
  JWT_SECRET: string;
  HOTEL_ID: string;
  ADMIN_API_KEY?: string;
}