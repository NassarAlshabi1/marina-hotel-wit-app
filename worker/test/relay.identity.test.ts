// ═══════════════════════════════════════════════════════════════
//  relay.identity.test.ts — ✅ (2026-09-29) C6-WS
//  عقد جسر pages.dev (worker/relay/_worker.js): هوية العميل الحقيقية
//  + توقيع RELAY_SECRET تُرفق على **كل** طلب صاعد — HTTP وWebSocket.
//  كان مسار WebSocket يمرر الطلب بلا x-mh-* فتُحسب ترقيات
//  /api/realtime على دلو عنوان خروج Cloudflare المشترك (مثبت إنتاجياً
//  في rate_limits: 2a06:98c0:3600::103).
//  fetch الصاعد مُعترَض (vi.stubGlobal) — بلا شبكة.
// ═══════════════════════════════════════════════════════════════

import { afterEach, describe, expect, it, vi } from 'vitest';
// @ts-expect-error — relay/_worker.js وحدة JS بلا تصريحات أنواع.
import relay from '../relay/_worker.js';

const UPSTREAM = 'https://marina-hotel-api.adenmarina2.workers.dev';
const SECRET = 'relay-test-secret';

function captureUpstream(): { calls: Request[] } {
  const calls: Request[] = [];
  vi.stubGlobal('fetch', async (input: RequestInfo, init?: RequestInit) => {
    calls.push(new Request(input, init));
    return new Response('ok', { status: 200 });
  });
  return { calls };
}

function clientRequest(path: string, headers: Record<string, string>, init: RequestInit = {}): Request {
  return new Request(`https://marina-hotel-api-relay.pages.dev${path}`, {
    ...init,
    headers: { 'cf-connecting-ip': '203.0.113.7', ...headers },
  });
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('relay: هوية العميل عبر الجسر', () => {
  it('WebSocket: يرفق x-mh-client-ip + التوقيع ويحفظ Upgrade والمسار والاستعلام', async () => {
    const { calls } = captureUpstream();
    await relay.fetch(
      clientRequest('/api/realtime?deviceId=d1&entity=*', {
        Upgrade: 'websocket',
        Connection: 'Upgrade',
        Authorization: 'Bearer t',
      }),
      { RELAY_SECRET: SECRET },
    );

    expect(calls).toHaveLength(1);
    const up = calls[0];
    expect(up.url).toBe(`${UPSTREAM}/api/realtime?deviceId=d1&entity=*`);
    expect(up.headers.get('upgrade')).toBe('websocket');
    expect(up.headers.get('authorization')).toBe('Bearer t');
    expect(up.headers.get('x-mh-client-ip')).toBe('203.0.113.7');
    expect(up.headers.get('x-mh-relay-key')).toBe(SECRET);
    expect(up.headers.get('x-mh-relayed')).toBe('1');
  });

  it('HTTP: نفس الهوية والتوقيع + الجسم يمر كما هو', async () => {
    const { calls } = captureUpstream();
    await relay.fetch(
      clientRequest(
        '/api/auth/login',
        { 'Content-Type': 'application/json' },
        { method: 'POST', body: '{"username":"u","password":"p"}' },
      ),
      { RELAY_SECRET: SECRET },
    );

    expect(calls).toHaveLength(1);
    const up = calls[0];
    expect(up.url).toBe(`${UPSTREAM}/api/auth/login`);
    expect(up.method).toBe('POST');
    expect(await up.text()).toBe('{"username":"u","password":"p"}');
    expect(up.headers.get('x-mh-client-ip')).toBe('203.0.113.7');
    expect(up.headers.get('x-mh-relay-key')).toBe(SECRET);
  });

  it('بلا RELAY_SECRET: لا توقيع (الـ Worker سيهمل x-mh-* — لا انتحال)', async () => {
    const { calls } = captureUpstream();
    await relay.fetch(
      clientRequest('/api/realtime', { Upgrade: 'websocket' }),
      {},
    );
    expect(calls[0].headers.get('x-mh-relay-key')).toBeNull();
  });
});
