// ═══════════════════════════════════════════════════════════════
//  health.d1.test.ts — ✅ (2026-09-17)
//  GET /api/health/d1: فحص المسار الكامل للبيانات (شبكة → worker →
//  مصادقة → D1) الذي يستدعيه التطبيق تلقائياً عند الفتح.
//  العقد: 401 بلا توكن / 200 + d1:'ok' + latency_ms مع توكن صالح /
//  استعلام SELECT 1 حقيقي يمر عبر D1 فعلاً.
// ═══════════════════════════════════════════════════════════════

import { SELF } from 'cloudflare:test';
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
    };
    expect(body.status).toBe('ok');
    expect(body.d1).toBe('ok');
    // SELECT 1 عبر miniflare/D1 الحقيقي — زمن غير سالب وصغير.
    expect(body.latency_ms).toBeGreaterThanOrEqual(0);
    expect(body.latency_ms).toBeLessThan(5000);
    // ثواني/ميلي ثانية متسقة (نفس اللحظة).
    expect(body.timestamp).toBeGreaterThanOrEqual(body.server_time * 1000);
  });
});
