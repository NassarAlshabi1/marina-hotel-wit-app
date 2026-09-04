/**
 * Marina Hotel Sync Worker — Cloudflare Worker entry point.
 * Hono + D1 + KV + Durable Objects.
 */

import { Hono } from 'hono';
import { verifyToken } from './auth';
import syncApp from './routes/sync';
import { SyncSession } from './durableObjects/SessionObject';
import type { Env } from './types';

const app = new Hono<{ Env: Env }>();

// ── Auth middleware ────────────────────────────────────────────────────────
app.use('*', async (c, next) => {
  const path = c.req.path;
  // Public endpoints (health + websocket handshake).
  if (path === '/health' || path.startsWith('/ws')) return next();

  const auth = c.req.header('Authorization');
  if (!auth?.startsWith('Bearer ')) {
    return c.json({ error: 'missing token' }, { status: 401 });
  }
  const token = auth.slice(7);
  const ctx = await verifyToken(c.env, token);
  if (!ctx) {
    return c.json({ error: 'invalid token' }, { status: 401 });
  }
  c.set('device', ctx);
  return next();
});

// ── Realtime WebSocket (Durable Object) ────────────────────────────────────
app.get('/ws', (c) => {
  const id = c.env.SyncSession.idFromName(c.req.header('X-Hotel-Id') ?? 'default');
  const url = new URL(c.req.url);
  const doUrl = new URL(`https://fake.example/`);
  doUrl.pathname = '/ws';
  doUrl.searchParams.set('upgrade', '1');
  const doReq = new Request(doUrl, {
    headers: { Upgrade: 'websocket' },
  });
  // Forward to the Durable Object via the stub.
  const stub = c.env.SyncSession.get(id);
  return stub.fetch(doReq);
});

// ── Sync API ───────────────────────────────────────────────────────────────
app.route('/sync', syncApp);

// ── Admin broadcast (push → realtime) ──────────────────────────────────────
app.post('/realtime/broadcast', async (c) => {
  const ctx = c.get('device') as { deviceId: string } | undefined;
  if (!ctx) return c.json({ error: 'unauthorized' }, { status: 401 });
  const body = await c.req.json();
  const id = c.env.SyncSession.idFromName(c.env.HOTEL_ID);
  const stub = c.env.SyncSession.get(id);
  const res = await stub.fetch(
    new Request('https://fake.example/broadcast', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    }),
  );
  return new Response(res.body, { status: res.status });
});

export default {
  fetch: app.fetch,
  SyncSession,
};