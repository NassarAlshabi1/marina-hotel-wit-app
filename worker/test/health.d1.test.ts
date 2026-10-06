// ═══════════════════════════════════════════════════════════════
//  health.d1.test.ts — ✅ (2026-09-17)
//  GET /api/health/d1: فحص المسار الكامل للبيانات (شبكة → worker →
//  مصادقة → D1) الذي يستدعيه التطبيق تلقائياً عند الفتح.
//  العقد: 401 بلا توكن / 200 + d1:'ok' + latency_ms مع توكن صالح /
//  استعلام SELECT 1 حقيقي يمر عبر D1 فعلاً.
// ═══════════════════════════════════════════════════════════════

import { env, SELF } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import { adminAuthHeader, resetDb } from './helpers';

beforeEach(async () => {
  await resetDb();
});

describe('GET /api/health/d1', () => {
  it('rejects unauthenticated requests with 401 (auth gate intact)', async () => {
    const res = await SELF.fetch('https://example.com/api/health/d1');
    expect(res.status).toBe(401);
    const body = (await res.json()) as { error: string };
    expect(body.error).toBe('Missing or invalid Authorization header');
  });

  it('rejects an invalid bearer token with 401', async () => {
    const res = await SELF.fetch('https://example.com/api/health/d1', {
      headers: { Authorization: 'Bearer not-a-real-jwt' },
    });
    expect(res.status).toBe(401);
  });

  it('returns 200 + d1 ok + latency for an authenticated admin', async () => {
    const auth = await adminAuthHeader();
    const res = await SELF.fetch('https://example.com/api/health/d1', {
      headers: { Authorization: auth },
    });
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      status: string;
      d1: string;
      latency_ms: number;
      server_time: number;
      timestamp: number;
      sync_provider: string;
      sync_source_id: string | null;
      sync_protocol_version: number;
    };
    expect(body.status).toBe('ok');
    expect(body.d1).toBe('ok');
    expect(body.sync_provider).toBe('cloudflare-d1');
    expect(body.sync_source_id).toMatch(/^[a-f0-9]{32}$/);
    expect(body.sync_protocol_version).toBe(1);
    // SELECT 1 عبر miniflare/D1 الحقيقي — زمن غير سالب وصغير.
    expect(body.latency_ms).toBeGreaterThanOrEqual(0);
    expect(body.latency_ms).toBeLessThan(5000);
    // ثواني/ميلي ثانية متسقة (نفس اللحظة).
    expect(body.timestamp).toBeGreaterThanOrEqual(body.server_time * 1000);
  });
  it('advertises expense kind only after the additive schema migration', async () => {
    const auth = await adminAuthHeader();
    const request = () => SELF.fetch('https://example.com/api/health/d1', { headers: { Authorization: auth } });
    expect(await (await request()).json()).toMatchObject({ expense_kind: true });
    await env.DB.prepare('ALTER TABLE expenses DROP COLUMN expense_kind').run();
    expect(await (await request()).json()).toMatchObject({ status: 'ok', d1: 'ok', expense_kind: false });
  });

});
