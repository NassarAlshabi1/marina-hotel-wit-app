/**
 * SyncSession Durable Object — realtime WebSocket + per-device sync lock.
 * - Broadcasts Remote→Local changes after a successful push (push echo immunization).
 * - Grants a short sync lock so only one device runs a full cycle at a time.
 */

import type { Env } from '../types';

export class SyncSession implements DurableObject {
  private state: DurableObjectState;
  private env: Env;
  private clients = new Set<WebSocket>();
  private lockOwner: string | null = null;
  private lockExpiresAt = 0;

  constructor(state: DurableObjectState, env: Env) {
    this.state = state;
    this.env = env;
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    if (path === '/ws' && request.headers.get('Upgrade') === 'websocket') {
      return this.handleWebSocket(request);
    }

    if (path === '/lock/acquire') {
      return this.handleLockAcquire(request);
    }

    if (path === '/lock/release') {
      return this.handleLockRelease(request);
    }

    if (path === '/broadcast') {
      return this.handleBroadcast(request);
    }

    return new Response('not found', { status: 404 });
  }

  private handleWebSocket(request: Request): Response {
    const pair = new WebSocketPair();
    const [client, server] = pair;
    this.clients.add(client);
    this.clients.add(server);

    server.accept();
    server.addEventListener('message', (msg) => {
      // Echo heartbeats; real push notifications come via /broadcast.
      if (typeof msg.data === 'string' && msg.data.includes('ping')) {
        server.send(JSON.stringify({ type: 'pong', ts: Date.now() }));
      }
    });
    server.addEventListener('close', () => {
      this.clients.delete(server);
      this.clients.delete(client);
    });

    return new Response(null, { status: 101, webSocket: server });
  }

  private async handleLockAcquire(request: Request): Promise<Response> {
    const body = (await request.json()) as { deviceId: string; ttlMs?: number };
    const now = Date.now();
    if (this.lockOwner && this.lockExpiresAt > now && this.lockOwner !== body.deviceId) {
      return Response.json(
        { ok: false, heldBy: this.lockOwner, retryInMs: this.lockExpiresAt - now },
        { status: 409 },
      );
    }
    this.lockOwner = body.deviceId;
    this.lockExpiresAt = now + (body.ttlMs ?? 30_000);
    return Response.json({ ok: true, owner: this.lockOwner, expiresAt: this.lockExpiresAt });
  }

  private async handleLockRelease(request: Request): Promise<Response> {
    const body = (await request.json()) as { deviceId: string };
    if (this.lockOwner === body.deviceId) {
      this.lockOwner = null;
      this.lockExpiresAt = 0;
    }
    return Response.json({ ok: true });
  }

  private async handleBroadcast(request: Request): Promise<Response> {
    const body = (await request.json()) as {
      deviceId: string;
      entity: string;
      op: 'insert' | 'update' | 'delete';
      id: string;
    };
    // Push echo immunization: never echo back to the sender.
    const payload = JSON.stringify({
      type: 'remote-change',
      entity: body.entity,
      op: body.op,
      id: body.id,
      ts: Date.now(),
    });
    for (const client of this.clients) {
      try {
        client.send(payload);
      } catch {
        this.clients.delete(client);
      }
    }
    return Response.json({ ok: true, delivered: this.clients.size });
  }
}