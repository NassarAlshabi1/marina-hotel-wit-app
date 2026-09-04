/**
 * Hono routes for the sync API.
 */

import { Hono } from 'hono';
import type { Env } from '../types';
import { processPush } from '../services/outboxProcessor';
import { pullMetadata, pullFull, pullDelta, checkpointEntity } from '../services/pullService';
import { rateLimit } from '../rateLimit';
import { RATE_LIMIT } from '../config';

const app = new Hono<{ Env: Env }>();

// ── Health ────────────────────────────────────────────────────────────────
app.get('/health', async (c) => {
  let dbOk = false;
  let kvOk = false;
  try {
    await c.env.DB.prepare('SELECT 1').run();
    dbOk = true;
  } catch { /* ignore */ }
  try {
    await c.env.RATE_KV.get('__health__');
    kvOk = true;
  } catch { /* ignore */ }
  return c.json({
    status: dbOk && kvOk ? 'ok' : 'degraded',
    db: dbOk ? 'ok' : 'fail',
    kv: kvOk ? 'ok' : 'fail',
    ts: Date.now(),
  });
});

// ── Push outbox ───────────────────────────────────────────────────────────
app.post('/sync/push', async (c) => {
  const ctx = c.get('device') as { deviceId: string } | undefined;
  if (!ctx) return c.json({ error: 'unauthorized' }, { status: 401 });

  const rl = await rateLimit(c.env, ctx.deviceId, RATE_LIMIT.DEFAULT);
  if (!rl.allowed) {
    return c.json(
      { error: 'rate limit exceeded', retryInMs: rl.resetMs },
      { status: 429 },
    );
  }

  const body = (await c.req.json()) as { changes: any[] };
  const result = await processPush(c.env, body, ctx.deviceId);
  return c.json(result);
});

// ── Pull metadata-first (Phase 1) ─────────────────────────────────────────
app.get('/sync/pull-metadata', async (c) => {
  const ctx = c.get('device') as { deviceId: string } | undefined;
  if (!ctx) return c.json({ error: 'unauthorized' }, { status: 401 });

  const rl = await rateLimit(c.env, ctx.deviceId, RATE_LIMIT.PULL_METADATA);
  if (!rl.allowed) {
    return c.json({ error: 'rate limit exceeded', retryInMs: rl.resetMs }, { status: 429 });
  }

  const entities = (c.req.query('entities') ?? '').split(',').filter(Boolean);
  const since = Number(c.req.query('since') ?? '0');
  const tombstones = c.req.query('tombstones') !== 'false';
  const docs = await pullMetadata(c.env, entities, since, tombstones);
  return c.json(docs);
});

// ── Pull full documents (Phase 3) ─────────────────────────────────────────
app.get('/sync/pull', async (c) => {
  const ctx = c.get('device') as { deviceId: string } | undefined;
  if (!ctx) return c.json({ error: 'unauthorized' }, { status: 401 });

  const entity = c.req.query('entity');
  const ids = (c.req.query('ids') ?? '').split(',').filter(Boolean);
  if (!entity) return c.json({ error: 'entity required' }, { status: 400 });
  const docs = await pullFull(c.env, entity, ids);
  return c.json({ [entity]: docs });
});

// ── Pull delta (fallback) ─────────────────────────────────────────────────
app.get('/sync/pull-delta', async (c) => {
  const ctx = c.get('device') as { deviceId: string } | undefined;
  if (!ctx) return c.json({ error: 'unauthorized' }, { status: 401 });

  const entity = c.req.query('entity');
  const since = Number(c.req.query('since') ?? '0');
  if (!entity) return c.json({ error: 'entity required' }, { status: 400 });
  const docs = await pullDelta(c.env, entity, since);
  return c.json({ entity, documents: docs });
});

// ── Checkpoint (server-authoritative watermark) ───────────────────────────
app.post('/sync/checkpoint', async (c) => {
  const ctx = c.get('device') as { deviceId: string } | undefined;
  if (!ctx) return c.json({ error: 'unauthorized' }, { status: 401 });
  const body = (await c.req.json()) as { entity: string; serverMaxTs: number };
  await checkpointEntity(c.env, body.entity, body.serverMaxTs);
  return c.json({ ok: true });
});

// ── Entity CRUD (admin/dashboard reads) ───────────────────────────────────
app.get('/entities/:entity', async (c) => {
  const ctx = c.get('device') as { deviceId: string } | undefined;
  if (!ctx) return c.json({ error: 'unauthorized' }, { status: 401 });
  const entity = c.req.param('entity');
  const filters = c.req.queries.get('filters');
  let sql = `SELECT * FROM "${entity}"`;
  const binds: unknown[] = [];
  if (filters) {
    sql += ` WHERE ${filters}`;
  }
  sql += ' ORDER BY updated_at DESC LIMIT 100';
  const { results } = await c.env.DB.prepare(sql).bind(...binds).all();
  return c.json({ [entity]: results ?? [] });
});

// ── Admin: one-time migration (guarded) ───────────────────────────────────
app.post('/admin/migrate', async (c) => {
  const key = c.req.header('X-Admin-Key');
  if (!c.env.ADMIN_API_KEY || key !== c.env.ADMIN_API_KEY) {
    return c.json({ error: 'forbidden' }, { status: 403 });
  }
  return c.json({ ok: false, error: 'migration endpoint disabled in production' }, { status: 503 });
});

export default app;