// ═══════════════════════════════════════════════════════════════
//  auth.longlived.test.ts — عقد التوكن طويل الأجل (2026-09-15)
//  العقد: JWT_EXPIRY_HOURS="0" → توكن بلا exp لا ينتهي تلقائياً؛
//  الإبطال المقصود = تدوير JWT_SECRET يدوياً فقط.
// ═══════════════════════════════════════════════════════════════

import { SELF } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import { resetDb } from './helpers';
import { resolveExpiryHours } from '../src/auth';

beforeEach(async () => {
  await resetDb();
});

const REGISTER_URL = 'https://example.com/api/auth/register';
const LOGIN_URL = 'https://example.com/api/auth/login';
const PULL_URL = 'https://example.com/api/sync/pull?entity=payments&cursor=0&limit=1';

function b64urlDecodeJson(part: string): Record<string, unknown> {
  const padded = part.replace(/-/g, '+').replace(/_/g, '/');
  const binary = atob(padded + '='.repeat((4 - (padded.length % 4)) % 4));
  return JSON.parse(new TextDecoder().decode(Uint8Array.from(binary, (c) => c.charCodeAt(0))));
}

function b64urlEncodeJson(obj: unknown): string {
  return btoa(JSON.stringify(obj)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

// توقيع HMAC-SHA256 بالمفتاح المعروف من vitest.config.ts — لبناء توكن
// تاريخي منتهي الصلاحية (اختبار مسار رفض exp القديم بعد العقد الجديد).
const TEST_SECRET = 'test-only-secret-0123456789abcdef';

async function hmacSignHex(message: string, secret: string = TEST_SECRET): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(message));
  return btoa(String.fromCharCode(...new Uint8Array(sig)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

async function registerAndLogin(username: string): Promise<{ token: string }> {
  await SELF.fetch(REGISTER_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, password: 'pw-123456', role: 'admin' }),
  });
  const login = await SELF.fetch(LOGIN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, password: 'pw-123456' }),
  });
  expect(login.status).toBe(200);
  return (await login.json()) as { token: string };
}

describe('contract: resolveExpiryHours parsing', () => {
  it('"0" = long-lived → null (honored, not swallowed by a || 24 fallback)', () => {
    expect(resolveExpiryHours('0')).toBeNull();
  });

  it('positive values pass through (backward compatibility)', () => {
    expect(resolveExpiryHours('24')).toBe(24);
    expect(resolveExpiryHours('168')).toBe(168);
  });

  it('missing/garbage values fall back to the historical 24', () => {
    expect(resolveExpiryHours(undefined)).toBe(24);
    expect(resolveExpiryHours('')).toBe(24);
    expect(resolveExpiryHours('abc')).toBe(24);
  });
});

describe('contract: long-lived token (no auto-expiry)', () => {
  it('login issues a token WITHOUT exp claim', async () => {
    const { token } = await registerAndLogin('ll-contract-user');
    const [, payloadB64] = token.split('.');
    const payload = b64urlDecodeJson(payloadB64);
    expect(payload.exp).toBeUndefined();
    expect(payload.iat).toBeTypeOf('number');
  });

  it('long-lived token authenticates protected endpoints (middleware accepts)', async () => {
    const { token } = await registerAndLogin('ll-mw-user');
    const res = await SELF.fetch(PULL_URL, {
      headers: { Authorization: `Bearer ${token}` },
    });
    // 200 = وصل للمعالج؛ أي 401 يعني الوسيط رفض التوكن طويل الأجل
    expect(res.status).toBe(200);
  });

  it('legacy tokens carrying exp are still honored while unexpired', async () => {
    const now = Math.floor(Date.now() / 1000);
    const header = b64urlEncodeJson({ alg: 'HS256', typ: 'JWT' });
    const body = b64urlEncodeJson({
      sub: 'u', username: 'u', role: 'admin', iat: now, exp: now + 3600,
    });
    const sig = await hmacSignHex(`${header}.${body}`);
    const res = await SELF.fetch(PULL_URL, {
      headers: { Authorization: `Bearer ${header}.${body}.${sig}` },
    });
    expect(res.status).toBe(200);
  });

  it('expired tokens (exp in the past) are still rejected — exp is enforced when present', async () => {
    const now = Math.floor(Date.now() / 1000);
    const header = b64urlEncodeJson({ alg: 'HS256', typ: 'JWT' });
    const body = b64urlEncodeJson({
      sub: 'u', username: 'u', role: 'admin', iat: now - 7200, exp: now - 3600,
    });
    const sig = await hmacSignHex(`${header}.${body}`);
    const res = await SELF.fetch(PULL_URL, {
      headers: { Authorization: `Bearer ${header}.${body}.${sig}` },
    });
    expect(res.status).toBe(401);
  });

  it('revocation semantics: rotation (different secret) invalidates a long-lived token', async () => {
    // محاكاة ما بعد تدوير JWT_SECRET: التوكن القديم طويل الأجل وقّعه
    // المفتاح القديم بينما الـ worker يحمل المفتاح الجديد (binding) →
    // 401. هذا هو «الإبطال اليدوي المقصود» بالعقد الجديد.
    const now = Math.floor(Date.now() / 1000);
    const header = b64urlEncodeJson({ alg: 'HS256', typ: 'JWT' });
    const body = b64urlEncodeJson({
      sub: 'u', username: 'u', role: 'admin', iat: now, // بلا exp — طويل الأجل
    });
    const oldSecretSig = await hmacSignHex(`${header}.${body}`, 'old-secret-pre-rotation-000000');
    const res = await SELF.fetch(PULL_URL, {
      headers: { Authorization: `Bearer ${header}.${body}.${oldSecretSig}` },
    });
    // وقّع بالمفتاح القديم ≠ JWT_SECRET الحالي (binding) → 401
    expect(res.status).toBe(401);
  });

  it('tampered long-lived token is rejected', async () => {
    const { token } = await registerAndLogin('ll-tamper-user');
    const parts = token.split('.');
    const forged = `${parts[0]}.${parts[1]}.AAAA`;
    const res = await SELF.fetch(PULL_URL, {
      headers: { Authorization: `Bearer ${forged}` },
    });
    expect(res.status).toBe(401);
  });
});
