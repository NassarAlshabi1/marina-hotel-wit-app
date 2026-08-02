// ═══════════════════════════════════════════════════════════════
//  index.ts — Cloudflare Worker Main Entry
//  Router + Rate Limiting + CORS + Auth Middleware
// ═══════════════════════════════════════════════════════════════

import { Database, isValidEntity } from './database';
import { authMiddleware, handleLogin, hashPassword, signToken } from './auth';
import { handlePull, handlePush, handleSyncLog, handleConflicts, handleMigrate } from './sync';
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
  db: Database,
  clientId: string,
  window: number,
  maxRequests: number
): Promise<{ allowed: boolean; remaining: number; resetAt: number }> {
  const now = Date.now();
  const windowStart = Math.floor(now / (window * 1000)) * (window * 1000);
  const resetAt = windowStart + window * 1000;

  try {
    // Use D1 for rate limiting (no daily write limit, unlike KV)
    // INSERT OR REPLACE atomically increments the counter
    const result = await db.db.prepare(
      'INSERT INTO rate_limits (client_id, window_start, count) VALUES (?, ?, 1) ' +
      'ON CONFLICT (client_id, window_start) DO UPDATE SET count = count + 1 ' +
      'RETURNING count'
    ).bind(clientId, windowStart).first<{ count: number }>();

    const current = result?.count ?? 1;
    const allowed = current <= maxRequests;
    const remaining = Math.max(0, maxRequests - current);

    // Clean up old windows periodically (1% chance per request)
    if (Math.random() < 0.01) {
      const cutoff = now - (window * 1000 * 2); // keep last 2 windows
      await db.db.prepare('DELETE FROM rate_limits WHERE window_start < ?')
        .bind(cutoff).run();
    }

    return { allowed, remaining, resetAt };
  } catch (err) {
    // If D1 fails, allow the request (fail-open for availability)
    console.warn('Rate limit D1 error (allowing request):', err);
    return { allowed: true, remaining: maxRequests, resetAt: now + window * 1000 };
  }
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

    // ─── Ping endpoint for network speed measurement (no auth) ──
    // Returns a ~1KB payload so the client can measure download speed.
    // Used by CloudflareMigrationService to adjust batch size dynamically.
    if (path === '/api/ping') {
      const payload = {
        status: 'ok',
        timestamp: Date.now(),
        server_time: Math.floor(Date.now() / 1000),
        // 1KB of padding for speed measurement
        padding: 'x'.repeat(1024),
      };
      return json(payload, 200, env);
    }

    // ─── Extract client ID for rate limiting ─────────────────
    const clientIp = request.headers.get('CF-Connecting-IP') || 'unknown';
    const rateLimitWindow = parseInt(env.RATE_LIMIT_WINDOW, 10) || 60;
    const rateLimitMax = parseInt(env.RATE_LIMIT_MAX, 10) || 100;

    // ─── Rate limit check (D1-based, no KV daily limit) ─────
    const rateDb = new Database(env.DB);
    const rateResult = await checkRateLimit(rateDb, clientIp, rateLimitWindow, rateLimitMax);
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

      // ─── Migration (raw SQL batch insert) ───────────────
      // Fast path for one-time migration: client sends gzipped SQL
      // INSERT statements, Worker executes them via D1 exec().
      // ~10x faster than /api/sync/push for bulk migration.
      if (path === '/api/sync/migrate' && method === 'POST') {
        const response = await handleMigrate(request, db, ctx);
        logRequest(method, path, response.status, Date.now() - startTime, clientIp);
        return response;
      }

      // ─── Sync Log ───────────────────────────────────────
      if (path === '/api/sync/log' && method === 'GET') {
        const response = await handleSyncLog(request, db, ctx);
        logRequest(method, path, response.status, Date.now() - startTime, clientIp);
        return response;
      }

      // ─── Stats (monitoring endpoint) ────────────────────
      // Returns aggregate stats for monitoring/debugging
      if (path === '/api/stats' && method === 'GET') {
        try {
          const tableCounts: Record<string, number> = {};
          const tables = ['rooms', 'bookings', 'payments', 'expenses', 'employees',
            'debts', 'booking_nights', 'salary_withdrawals', 'guest_infos',
            'booking_price_adjustments', 'devices', 'users', 'rate_limits'];
          for (const t of tables) {
            const r = await db.db.prepare(`SELECT COUNT(*) as c FROM ${t}`).first<{ c: number }>();
            tableCounts[t] = r?.c ?? 0;
          }
          const rlResult = await db.db.prepare(
            'SELECT COUNT(*) as c FROM rate_limits'
          ).first<{ c: number }>();
          logRequest(method, path, 200, Date.now() - startTime, clientIp);
          return json({
            tables: tableCounts,
            rate_limit_entries: rlResult?.c ?? 0,
            server_time: Math.floor(Date.now() / 1000),
            uptime_hint: 'Workers are stateless — no uptime tracking',
          }, 200, env);
        } catch (err) {
          logRequest(method, path, 500, Date.now() - startTime, clientIp);
          return json({ error: 'Stats failed', detail: String(err) }, 500, env);
        }
      }

      // ─── Sync Conflicts ─────────────────────────────────
      if (path === '/api/sync/conflicts' && method === 'GET') {
        const response = await handleConflicts(request, db, ctx);
        logRequest(method, path, response.status, Date.now() - startTime, clientIp);
        return response;
      }

      // ─── Device Management (for FCM) ──────────────────────
      // POST /api/devices/register — register/update device + FCM token
      if (path === '/api/devices/register' && method === 'POST') {
        const db = new Database(env.DB);
        try {
          const body = await request.json() as { deviceId: string; fcmToken?: string; deviceName?: string; platform?: string };
          await db.registerDevice(body.deviceId, body.fcmToken || null, body.deviceName, body.platform);
          logRequest(method, path, 200, Date.now() - startTime, clientIp);
          return json({ registered: true, deviceId: body.deviceId }, 200, env);
        } catch (err) {
          logRequest(method, path, 500, Date.now() - startTime, clientIp);
          return json({ error: 'Device registration failed', detail: String(err) }, 500, env);
        }
      }

      // GET /api/devices/tokens — list all FCM tokens (excludes current device)
      if (path === '/api/devices/tokens' && method === 'GET') {
        const db = new Database(env.DB);
        const excludeDeviceId = url.searchParams.get('exclude') || undefined;
        const tokens = await db.getDeviceTokens(excludeDeviceId);
        logRequest(method, path, 200, Date.now() - startTime, clientIp);
        return json({ tokens, count: tokens.length }, 200, env);
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
