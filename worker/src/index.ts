// ═══════════════════════════════════════════════════════════════
//  index.ts — Cloudflare Worker Main Entry
//  Router + Rate Limiting + CORS + Auth Middleware
// ═══════════════════════════════════════════════════════════════

import { Database, isValidEntity } from './database';
import { authMiddleware, handleLogin, hashPassword, signToken } from './auth';
import { handlePull, handlePush, handleSyncLog, handleConflicts } from './sync';
import { SyncLockDO } from './sync-lock';

// ─── Environment bindings ─────────────────────────────────────

export { SyncLockDO };

export interface Env {
  DB: D1Database;
  SYNC_LOCK: DurableObjectNamespace;
  RATE_LIMIT: KVNamespace;
  JWT_SECRET: string;
  JWT_EXPIRY_HOURS: string;
  RATE_LIMIT_WINDOW: string;
  RATE_LIMIT_MAX: string;
  CORS_ORIGIN: string;
}

// ─── Rate Limiting ────────────────────────────────────────────

async function checkRateLimit(
  kv: KVNamespace,
  clientId: string,
  window: number,
  maxRequests: number
): Promise<{ allowed: boolean; remaining: number; resetAt: number }> {
  const now = Date.now();
  const windowStart = Math.floor(now / (window * 1000)) * (window * 1000);
  const key = `rl:${clientId}:${windowStart}`;

  const current = parseInt((await kv.get(key)) || '0', 10);
  const allowed = current < maxRequests;
  const remaining = Math.max(0, maxRequests - current - 1);
  const resetAt = windowStart + window * 1000;

  if (allowed) {
    await kv.put(key, (current + 1).toString(), {
      expirationTtl: window,
    });
  }

  return { allowed, remaining, resetAt };
}

// ─── CORS Headers ─────────────────────────────────────────────

function corsHeaders(origin: string): Headers {
  const headers = new Headers();
  headers.set('Access-Control-Allow-Origin', origin || '*');
  headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  headers.set(
    'Access-Control-Allow-Headers',
    'Authorization, Content-Type, X-Device-Id'
  );
  headers.set('Access-Control-Max-Age', '86400');
  return headers;
}

// ─── JSON Response ────────────────────────────────────────────

function json(data: unknown, status: number = 200, env?: Env): Response {
  const headers = new Headers({ 'Content-Type': 'application/json' });
  if (env) {
    const cors = corsHeaders(env.CORS_ORIGIN);
    cors.forEach((val, key) => headers.set(key, val));
  }
  return new Response(JSON.stringify(data), { status, headers });
}

// ─── Logging ──────────────────────────────────────────────────

function logRequest(method: string, path: string, status: number, durationMs: number, clientId: string): void {
  const timestamp = new Date().toISOString();
  console.log(
    JSON.stringify({
      timestamp,
      method,
      path,
      status,
      duration_ms: durationMs,
      client_id: clientId,
    })
  );
}

// ─── Main Worker ──────────────────────────────────────────────

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const startTime = Date.now();
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

    // ─── CORS Preflight ──────────────────────────────────────
    if (method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders(env.CORS_ORIGIN) });
    }

    // ─── Health check (no auth) ──────────────────────────────
    if (path === '/health' || path === '/') {
      return json({ status: 'ok', timestamp: Date.now(), version: '1.0.0' }, 200, env);
    }

    // ─── Extract client ID for rate limiting ─────────────────
    const clientIp = request.headers.get('CF-Connecting-IP') || 'unknown';
    const rateLimitWindow = parseInt(env.RATE_LIMIT_WINDOW, 10) || 60;
    const rateLimitMax = parseInt(env.RATE_LIMIT_MAX, 10) || 100;

    // ─── Rate limit check ────────────────────────────────────
    const rateResult = await checkRateLimit(env.RATE_LIMIT, clientIp, rateLimitWindow, rateLimitMax);
    if (!rateResult.allowed) {
      logRequest(method, path, 429, Date.now() - startTime, clientIp);
      return json(
        { error: 'Rate limit exceeded', retry_after: rateResult.resetAt },
        429,
        env
      );
    }

    // ─── Auth endpoint (no token needed) ─────────────────────
    if (path === '/api/auth/login' && method === 'POST') {
      const db = new Database(env.DB);
      const response = await handleLogin(request, db, env.JWT_SECRET);
      // Add CORS headers
      const corsHeaders_ = corsHeaders(env.CORS_ORIGIN);
      const newResponse = new Response(response.body, {
        status: response.status,
        headers: response.headers,
      });
      corsHeaders_.forEach((val, key) => newResponse.headers.set(key, val));
      logRequest(method, path, newResponse.status, Date.now() - startTime, clientIp);
      return newResponse;
    }

    // ─── Auth: Register (admin only — first user bootstrap) ──
    if (path === '/api/auth/register' && method === 'POST') {
      const db = new Database(env.DB);
      try {
        const body = await request.json() as { username: string; password: string; role?: string };

        if (!body.username || !body.password) {
          return json({ error: 'Username and password required' }, 400, env);
        }

        const hash = await hashPassword(body.password);
        const userId = await db.createUser(body.username, hash, body.role || 'admin');

        const token = await signToken(
          { sub: userId, username: body.username, role: body.role || 'admin' },
          env.JWT_SECRET,
          parseInt(env.JWT_EXPIRY_HOURS, 10) || 24
        );

        return json({ token, user: { id: userId, username: body.username, role: body.role || 'admin' } }, 201, env);
      } catch (err) {
        return json({ error: 'Registration failed', detail: String(err) }, 500, env);
      }
    }

    // ─── Auth middleware for all other /api/ routes ──────────
    if (path.startsWith('/api/')) {
      const authResult = await authMiddleware(request, { JWT_SECRET: env.JWT_SECRET, DB: env.DB });

      if (!authResult.authenticated) {
        logRequest(method, path, 401, Date.now() - startTime, clientIp);
        return json({ error: authResult.error }, 401, env);
      }

      const ctx = authResult.context!;
      const db = new Database(env.DB);

      // ─── Sync Pull ──────────────────────────────────────
      if (path === '/api/sync/pull' && method === 'GET') {
        const response = await handlePull(request, db, ctx);
        logRequest(method, path, response.status, Date.now() - startTime, clientIp);
        return response;
      }

      // ─── Sync Push ──────────────────────────────────────
      if (path === '/api/sync/push' && method === 'POST') {
        const response = await handlePush(request, db, ctx);
        logRequest(method, path, response.status, Date.now() - startTime, clientIp);
        return response;
      }

      // ─── Sync Log ───────────────────────────────────────
      if (path === '/api/sync/log' && method === 'GET') {
        const response = await handleSyncLog(request, db, ctx);
        logRequest(method, path, response.status, Date.now() - startTime, clientIp);
        return response;
      }

      // ─── Sync Conflicts ─────────────────────────────────
      if (path === '/api/sync/conflicts' && method === 'GET') {
        const response = await handleConflicts(request, db, ctx);
        logRequest(method, path, response.status, Date.now() - startTime, clientIp);
        return response;
      }

      // ─── Durable Object: Sync Lock ────────────────────────
      // POST /api/sync/lock — acquire a lock on an entity
      if (path === '/api/sync/lock' && method === 'POST') {
        const lockId = env.SYNC_LOCK.idFromName('global');
        const stub = env.SYNC_LOCK.get(lockId);
        const doRequest = new Request('https://do.internal/lock', { method: 'POST', headers: request.headers, body: await request.text() });
        const response = await stub.fetch(doRequest);
        logRequest(method, path, response.status, Date.now() - startTime, clientIp);
        return response;
      }

      // POST /api/sync/unlock — release a lock
      if (path === '/api/sync/unlock' && method === 'POST') {
        const lockId = env.SYNC_LOCK.idFromName('global');
        const stub = env.SYNC_LOCK.get(lockId);
        const doRequest = new Request('https://do.internal/unlock', { method: 'POST', headers: request.headers, body: await request.text() });
        const response = await stub.fetch(doRequest);
        logRequest(method, path, response.status, Date.now() - startTime, clientIp);
        return response;
      }

      // GET /api/sync/locks — list active locks
      if (path === '/api/sync/locks' && method === 'GET') {
        const lockId = env.SYNC_LOCK.idFromName('global');
        const stub = env.SYNC_LOCK.get(lockId);
        const doRequest = new Request('https://do.internal/status', { method: 'GET', headers: request.headers });
        const response = await stub.fetch(doRequest);
        logRequest(method, path, response.status, Date.now() - startTime, clientIp);
        return response;
      }

      // ─── Durable Object: Realtime WebSocket ───────────────
      // GET /api/realtime — WebSocket upgrade for realtime sync
      if (path === '/api/realtime' && method === 'GET') {
        const upgradeHeader = request.headers.get('Upgrade');
        if (upgradeHeader !== 'websocket') {
          return json({ error: 'WebSocket upgrade required' }, 400, env);
        }
        const lockId = env.SYNC_LOCK.idFromName('global');
        const stub = env.SYNC_LOCK.get(lockId);
        const response = await stub.fetch(request);
        logRequest(method, path, response.status, Date.now() - startTime, clientIp);
        return response;
      }

      // ─── 404 ─────────────────────────────────────────────
      logRequest(method, path, 404, Date.now() - startTime, clientIp);
      return json({ error: 'Not found', path }, 404, env);
    }

    // ─── 404 for non-API routes ───────────────────────────────
    logRequest(method, path, 404, Date.now() - startTime, clientIp);
    return json({ error: 'Not found', path }, 404, env);
  },
};
