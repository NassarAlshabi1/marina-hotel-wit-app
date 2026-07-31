// ═══════════════════════════════════════════════════════════════
//  sync-lock.ts — Durable Object for Distributed Sync Locks + Realtime
//
//  Each entity (room, booking, payment, etc.) gets its own DO instance.
//  The DO provides:
//    1. Mutex lock — prevents concurrent writes to the same entity
//    2. Realtime notifications — broadcasts changes to connected clients
//    3. Cursor tracking — tracks the last sync cursor per device
// ═══════════════════════════════════════════════════════════════

export interface SyncLockRequest {
  deviceId: string;
  entity: string;
  entityId: string;
  operation: 'create' | 'update' | 'delete';
}

export interface SyncLockResponse {
  granted: boolean;
  lockId?: string;
  heldBy?: string;
  expiresAt?: number;
}

export interface RealtimeMessage {
  type: 'change' | 'lock' | 'unlock' | 'presence';
  entity: string;
  entityId: string;
  operation?: string;
  deviceId?: string;
  timestamp: number;
  data?: unknown;
}

// ═══════════════════════════════════════════════════════════════
//  Durable Object: SyncLockDO
// ═══════════════════════════════════════════════════════════════

export class SyncLockDO {
  state: DurableObjectState;
  sessions: Map<WebSocket, { deviceId: string; entity: string }>;

  constructor(state: DurableObjectState) {
    this.state = state;
    this.sessions = new Map();
  }

  // ─── HTTP Handler (for lock acquire/release) ───────────────

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    // ─── WebSocket upgrade for realtime ─────────────────────
    if (request.headers.get('Upgrade') === 'websocket') {
      return this.handleWebSocket(request);
    }

    // ─── Lock acquire ───────────────────────────────────────
    if (path === '/lock' && request.method === 'POST') {
      return this.handleLockAcquire(request);
    }

    // ─── Lock release ───────────────────────────────────────
    if (path === '/unlock' && request.method === 'POST') {
      return this.handleLockRelease(request);
    }

    // ─── Lock status ────────────────────────────────────────
    if (path === '/status' && request.method === 'GET') {
      return this.handleLockStatus();
    }

    // ─── Broadcast change ───────────────────────────────────
    if (path === '/broadcast' && request.method === 'POST') {
      return this.handleBroadcast(request);
    }

    // ─── Get cursors ────────────────────────────────────────
    if (path === '/cursors' && request.method === 'GET') {
      return this.handleGetCursors();
    }

    // ─── Update cursor ──────────────────────────────────────
    if (path === '/cursor' && request.method === 'POST') {
      return this.handleUpdateCursor(request);
    }

    return new Response('Not found', { status: 404 });
  }

  // ─── Lock Acquire ──────────────────────────────────────────

  async handleLockAcquire(request: Request): Promise<Response> {
    const body = (await request.json()) as SyncLockRequest;
    const lockKey = `${body.entity}:${body.entityId}`;

    // Check existing lock
    const existingLock = (await this.state.storage.get<{ deviceId: string; expiresAt: number }>(
      `lock:${lockKey}`
    )) as { deviceId: string; expiresAt: number } | undefined;

    const now = Date.now();

    if (existingLock) {
      // Lock expired? Take it over
      if (existingLock.expiresAt < now) {
        await this.state.storage.put(`lock:${lockKey}`, {
          deviceId: body.deviceId,
          expiresAt: now + 30000, // 30 second lock
        });

        // Notify connected clients
        this.broadcast({
          type: 'lock',
          entity: body.entity,
          entityId: body.entityId,
          deviceId: body.deviceId,
          timestamp: now,
        });

        return Response.json({
          granted: true,
          lockId: `${lockKey}:${body.deviceId}:${now}`,
          expiresAt: now + 30000,
        } as SyncLockResponse);
      }

      // Same device? Extend the lock
      if (existingLock.deviceId === body.deviceId) {
        await this.state.storage.put(`lock:${lockKey}`, {
          deviceId: body.deviceId,
          expiresAt: now + 30000,
        });

        return Response.json({
          granted: true,
          lockId: `${lockKey}:${body.deviceId}:${now}`,
          expiresAt: now + 30000,
        } as SyncLockResponse);
      }

      // Lock held by another device
      return Response.json({
        granted: false,
        heldBy: existingLock.deviceId,
        expiresAt: existingLock.expiresAt,
      } as SyncLockResponse);
    }

    // No existing lock — acquire it
    await this.state.storage.put(`lock:${lockKey}`, {
      deviceId: body.deviceId,
      expiresAt: now + 30000,
    });

    // Broadcast lock event
    this.broadcast({
      type: 'lock',
      entity: body.entity,
      entityId: body.entityId,
      deviceId: body.deviceId,
      timestamp: now,
    });

    return Response.json({
      granted: true,
      lockId: `${lockKey}:${body.deviceId}:${now}`,
      expiresAt: now + 30000,
    } as SyncLockResponse);
  }

  // ─── Lock Release ──────────────────────────────────────────

  async handleLockRelease(request: Request): Promise<Response> {
    const body = (await request.json()) as SyncLockRequest;
    const lockKey = `${body.entity}:${body.entityId}`;

    const existingLock = (await this.state.storage.get<{ deviceId: string }>(
      `lock:${lockKey}`
    )) as { deviceId: string } | undefined;

    if (existingLock && existingLock.deviceId === body.deviceId) {
      await this.state.storage.delete(`lock:${lockKey}`);

      // Broadcast unlock event
      this.broadcast({
        type: 'unlock',
        entity: body.entity,
        entityId: body.entityId,
        deviceId: body.deviceId,
        timestamp: Date.now(),
      });

      return Response.json({ released: true });
    }

    return Response.json({ released: false, reason: 'Not lock owner' }, { status: 409 });
  }

  // ─── Lock Status ───────────────────────────────────────────

  async handleLockStatus(): Promise<Response> {
    // List all active locks
    const locks: Array<{ key: string; deviceId: string; expiresAt: number }> = [];
    const iter = this.state.storage.list<{ deviceId: string; expiresAt: number }>({
      prefix: 'lock:',
    });

    for await (const [key, value] of iter) {
      if (value.expiresAt > Date.now()) {
        locks.push({ key, deviceId: value.deviceId, expiresAt: value.expiresAt });
      } else {
        // Clean up expired locks
        await this.state.storage.delete(key);
      }
    }

    return Response.json({ locks, count: locks.length });
  }

  // ─── Broadcast Change ──────────────────────────────────────

  async handleBroadcast(request: Request): Promise<Response> {
    const body = (await request.json()) as RealtimeMessage;

    this.broadcast({
      ...body,
      timestamp: Date.now(),
    });

    return Response.json({ broadcast: true, recipients: this.sessions.size });
  }

  // ─── Cursor Management ─────────────────────────────────────

  async handleGetCursors(): Promise<Response> {
    const cursors: Record<string, number> = {};
    const iter = this.state.storage.list<number>({ prefix: 'cursor:' });

    for await (const [key, value] of iter) {
      const deviceId = key.replace('cursor:', '');
      cursors[deviceId] = value;
    }

    return Response.json({ cursors });
  }

  async handleUpdateCursor(request: Request): Promise<Response> {
    const body = (await request.json()) as { deviceId: string; cursor: number };
    await this.state.storage.put(`cursor:${body.deviceId}`, body.cursor);
    return Response.json({ updated: true });
  }

  // ─── WebSocket Realtime ────────────────────────────────────

  handleWebSocket(request: Request): Response {
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);

    // Extract device ID from query params
    const url = new URL(request.url);
    const deviceId = url.searchParams.get('deviceId') || 'unknown';
    const entity = url.searchParams.get('entity') || '*';

    // Accept the connection
    server.accept();

    // Store session
    this.sessions.set(server, { deviceId, entity });

    // Send welcome message
    server.send(
      JSON.stringify({
        type: 'presence',
        entity,
        deviceId: 'server',
        timestamp: Date.now(),
        data: { message: 'Connected', activeConnections: this.sessions.size },
      } as RealtimeMessage)
    );

    // Notify others of new connection
    this.broadcast(
      {
        type: 'presence',
        entity,
        deviceId,
        timestamp: Date.now(),
        data: { action: 'join', activeConnections: this.sessions.size },
      },
      server // Exclude the new connection
    );

    // Handle incoming messages
    server.addEventListener('message', (event: MessageEvent) => {
      try {
        const msg = JSON.parse(event.data as string) as RealtimeMessage;
        // Broadcast to other clients
        this.broadcast({ ...msg, timestamp: Date.now() }, server);
      } catch {
        // Ignore malformed messages
      }
    });

    // Handle close
    server.addEventListener('close', () => {
      this.sessions.delete(server);
      this.broadcast({
        type: 'presence',
        entity,
        deviceId,
        timestamp: Date.now(),
        data: { action: 'leave', activeConnections: this.sessions.size },
      });
    });

    // Handle error
    server.addEventListener('error', () => {
      this.sessions.delete(server);
    });

    return new Response(null, { status: 101, webSocket: client });
  }

  // ─── Broadcast Helper ──────────────────────────────────────

  private broadcast(message: RealtimeMessage, exclude?: WebSocket): void {
    const data = JSON.stringify(message);
    for (const [ws, session] of this.sessions) {
      if (ws === exclude) continue;
      // Only send to clients subscribed to this entity or wildcard
      if (session.entity === '*' || session.entity === message.entity) {
        try {
          ws.send(data);
        } catch {
          this.sessions.delete(ws);
        }
      }
    }
  }
}
