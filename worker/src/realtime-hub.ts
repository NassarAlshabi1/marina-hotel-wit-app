// ═══════════════════════════════════════════════════════════════
//  realtime-hub.ts — Durable Object: Realtime WebSocket Hub
//
//  ✅ (2026-09-17) Dedicated hub split out of SyncLockDO('global').
//
//  WHY: the legacy hub kept sessions in an in-memory Map — every
//  `wrangler deploy` (or DO eviction) dropped ALL connected devices
//  into reconnect backoff, and realtime shared its DO instance with
//  the lock traffic. This class is realtime-only and built on the
//  WebSocket Hibernation API:
//    • Sessions are registered with the DO runtime
//      (state.acceptWebSocket) — they SURVIVE restarts, evictions
//      and deploys with zero in-memory cost while idle.
//    • O(1) fan-out: each socket carries an `ent:<entity>` tag, so
//      broadcasts address state.getWebSockets('ent:<entity>') plus
//      the wildcard subscribers `ent:*` — no full-session scan.
//    • Metadata (deviceId/entity) rides on the socket itself via
//      serializeAttachment — readable again after hibernation wake.
//    • Protocol-level ping/pong (the Dart client's IOWebSocketChannel
//      pingInterval) is answered by the runtime even while evicted.
//
//  Wire compatibility: message shapes (welcome/join/leave presence,
//  change events), the /api/realtime?deviceId=..&entity=* URL and the
//  401 auth gate are byte-for-byte identical to the legacy hub —
//  the Flutter client needs ZERO changes.
//
//  Security contract (unchanged): realtime is a server-originated
//  invalidation channel. Client-sent frames are NEVER relayed — an
//  authenticated client must not be able to forge `change` events
//  and force every other device into needless pulls.
// ═══════════════════════════════════════════════════════════════

import type { RealtimeMessage } from './sync-lock';

interface SessionMeta {
  deviceId: string;
  entity: string;
}

/** Max length for a socket tag (defensive — query params are untrusted). */
const MAX_TAG_LEN = 128;

/** Tags only drive fan-out filtering; they must be tame ASCII runs.
 *  Malformed input degrades to a placeholder instead of throwing. */
function sanitizeTag(prefix: string, raw: string | null): string {
  const cleaned = (raw ?? '').replace(/[^\w:.-]/g, '').slice(0, MAX_TAG_LEN);
  return cleaned.length > 0 ? `${prefix}${cleaned}` : `${prefix}unknown`;
}

/** Entity tag — '*' is the wildcard subscription EVERY Flutter client uses;
 *  it must survive sanitization verbatim or wildcard fan-out would break. */
function entityTag(raw: string | null): string {
  const trimmed = (raw ?? '').trim();
  if (trimmed === '*') return 'ent:*';
  return sanitizeTag('ent:', trimmed);
}

export class RealtimeHubDO {
  state: DurableObjectState;

  constructor(state: DurableObjectState) {
    this.state = state;
  }

  // ─── HTTP Handler (broadcast + status + WebSocket upgrade) ──

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    // ─── WebSocket upgrade for realtime ─────────────────────
    if (request.headers.get('Upgrade') === 'websocket') {
      return this.handleWebSocketUpgrade(url);
    }

    // ─── Broadcast change (from the worker push path) ───────
    if (path === '/broadcast' && request.method === 'POST') {
      return this.handleBroadcast(request);
    }

    // ─── Hub status (ops + live verification) ───────────────
    if (path === '/status' && request.method === 'GET') {
      return this.handleStatus();
    }

    return new Response('Not found', { status: 404 });
  }

  // ─── WebSocket Upgrade (Hibernation registration) ──────────

  private handleWebSocketUpgrade(url: URL): Response {
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair) as [WebSocket, WebSocket];

    const deviceId = url.searchParams.get('deviceId') || 'unknown';
    const entity = url.searchParams.get('entity') || '*';

    // Hibernation registration. Tags use ent:/dev: prefixes so a
    // deviceId can never collide with an entity name at fan-out time.
    this.state.acceptWebSocket(server, [
      entityTag(entity),
      sanitizeTag('dev:', deviceId),
    ]);
    // True (unsanitized) metadata rides on the socket itself.
    server.serializeAttachment({ deviceId, entity } satisfies SessionMeta);

    // Welcome message — same shape the legacy hub sent on connect.
    server.send(
      JSON.stringify({
        type: 'presence',
        entity,
        entityId: '',
        deviceId: 'server',
        timestamp: Date.now(),
        data: { message: 'Connected', activeConnections: this.state.getWebSockets().length },
      } as RealtimeMessage)
    );

    // Notify others of the new connection (same legacy semantics).
    this.broadcast(
      {
        type: 'presence',
        entity,
        entityId: '',
        deviceId,
        timestamp: Date.now(),
        data: { action: 'join', activeConnections: this.state.getWebSockets().length },
      },
      server
    );

    return new Response(null, { status: 101, webSocket: client });
  }

  // ─── Hibernation lifecycle handlers ────────────────────────
  // These fire even after eviction+wake: the runtime rehydrates the
  // event into a running DO instance with all sockets intact.

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    // Realtime is a server-originated invalidation channel.  Never relay
    // client-supplied JSON: an authenticated client could otherwise forge
    // `change` events and force every other device into needless pulls.
    // Clients only need to receive events; protocol-level ping/pong is
    // answered by the runtime itself and never surfaces here.
    void ws;
    void message;
  }

  async webSocketClose(
    ws: WebSocket,
    code: number,
    reason: string,
    wasClean: boolean
  ): Promise<void> {
    void code;
    void reason;
    void wasClean;
    this.presenceLeave(ws);
  }

  async webSocketError(ws: WebSocket): Promise<void> {
    // The runtime tears the errored socket down and follows up with
    // webSocketClose — leave-presence is emitted there exactly once.
    void ws;
  }

  private presenceLeave(ws: WebSocket): void {
    const meta = this.readMeta(ws);
    this.broadcast({
      type: 'presence',
      entity: meta?.entity ?? '*',
      entityId: '',
      deviceId: meta?.deviceId ?? 'unknown',
      timestamp: Date.now(),
      data: { action: 'leave', activeConnections: this.state.getWebSockets().length },
    });
  }

  private readMeta(ws: WebSocket): SessionMeta | null {
    try {
      return ws.deserializeAttachment() as SessionMeta | null;
    } catch {
      return null;
    }
  }

  // ─── Broadcast (invoked by realtimeBroadcaster after push) ──

  private async handleBroadcast(request: Request): Promise<Response> {
    const body = (await request.json()) as RealtimeMessage;
    const recipients = this.broadcast({ ...body, timestamp: Date.now() });
    return Response.json({ broadcast: true, recipients });
  }

  // ─── Status (ops dashboard + live deploy verification) ──────

  private handleStatus(): Response {
    const sockets = this.state.getWebSockets();
    const byEntity: Record<string, number> = {};
    const deviceIds: string[] = [];
    for (const ws of sockets) {
      const meta = this.readMeta(ws);
      if (!meta) continue;
      byEntity[meta.entity] = (byEntity[meta.entity] ?? 0) + 1;
      deviceIds.push(meta.deviceId);
    }
    return Response.json({
      connections: sockets.length,
      byEntity,
      deviceIds,
      hibernation: true,
    });
  }

  // ─── Fan-out ────────────────────────────────────────────────
  // Addresses entity-tagged + wildcard subscribers directly —
  // hibernated sockets included (the runtime wakes them for delivery).

  private broadcast(message: RealtimeMessage, exclude?: WebSocket): number {
    const data = JSON.stringify(message);
    const targets = new Set<WebSocket>([
      ...this.state.getWebSockets(entityTag(message.entity)),
      ...this.state.getWebSockets('ent:*'),
    ]);
    let recipients = 0;
    for (const ws of targets) {
      if (ws === exclude) continue;
      try {
        ws.send(data);
        recipients += 1;
      } catch {
        // Dead/evicted socket — the runtime reaps it; nothing to do.
      }
    }
    return recipients;
  }
}
