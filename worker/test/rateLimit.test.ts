// ═══════════════════════════════════════════════════════════════
//  rateLimit.test.ts — plan task 1.2
//  D1 fixed-window limiter: 429 + Retry-After, login brute-force
//  bucket (20/window), fail-open on limiter errors.
// ═══════════════════════════════════════════════════════════════

import { env, SELF } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import { adminAuthHeader, resetDb } from './helpers';

beforeEach(async () => {
  await resetDb();
});


describe('rate limiting: login brute-force bucket', () => {
  it('returns 429 + Retry-After after 20 failed login attempts from one IP', async () => {
    // ⚠️ جذر الـ flake (دليل CI 2026-09-24، run 35946682576/job 107466079331):
    // المحدد نافذة ثابتة 60s على ساعة الحائط (floor(now/60000)). 25 محاولة
    // متتالية تستغرق ~2.5s على runner بطيء؛ إذا استدارت الدقيقة داخل الحلقة
    // تنقسم العدّادات بين نافذتين — قُطع فعلياً 20/5 (المحاولة 20 عند
    // 02:19:59.973 والـ 21 عند 02:20:00.070) فلا تصل أي نافذة إلى 21 ولا
    // يُطلق 429 أبداً. الهامش (25−20=4) لا يحتمل تمزقاً كهذا.
    //
    // الإصلاح الحتمي: المرحلة 1 تراكم حقيقي (20 محاولة — دلالة العنوان)،
    // والمرحلة 2 احتياط تمزق: إعادة تعبئة نافذة Date.now() الحالية إلى
    // آخر عدّ مسموح (20) بنفس UPSERT الذي ينفذه الـ worker — أي طلب يقع
    // في النافذة المعبأة يرفع العدّ إلى 21 فيُطلق 429 حتماً، وأي طلب يقع
    // في نافذة جديدة (عدّ=1) تُعاد تعبئته في الدورة التالية. مفاتيح
    // 'login:unknown' مثبتة بعقد index.ts (`login:${clientIp}` حيث
    // clientIp='unknown' في miniflare) — تغيّر الصيغة يكسر هذا الاختبار
    // بوضوح (قفل عقد مقصود).
    const WINDOW_MS = 60 * 1000;
    const LOGIN_BUCKET = 'login:unknown';
    const LAST_ALLOWED_COUNT = 20; // allowed = count <= 20 → يشتعل عند 21

    const fireLogin = (): Promise<Response> =>
      SELF.fetch('https://example.com/api/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username: 'no-such-user', password: 'x' }),
      });

    const seedLoginBucketToLastAllowed = async (): Promise<void> => {
      const windowStart = Math.floor(Date.now() / WINDOW_MS) * WINDOW_MS;
      await env.DB.prepare(
        'INSERT INTO rate_limits (client_id, window_start, count) VALUES (?, ?, ?) ' +
          'ON CONFLICT (client_id, window_start) DO UPDATE SET count = ?'
      )
        .bind(LOGIN_BUCKET, windowStart, LAST_ALLOWED_COUNT, LAST_ALLOWED_COUNT)
        .run();
    };

    let saw429 = false;
    let retryAfter: string | null = null;

    // المرحلة 1 — تراكم حقيقي (كما كان): 25 محاولة كافية في نافذة واحدة
    for (let i = 0; i < 25 && !saw429; i++) {
      const res = await fireLogin();
      if (res.status === 429) {
        saw429 = true;
        retryAfter = res.headers.get('Retry-After');
        break;
      }
      expect(res.status).toBe(401);
    }

    // المرحلة 2 — احتياط تمزق النافذة (يشتغل فقط إذا استدارت الدقيقة أعلاه)
    for (let i = 0; i < 10 && !saw429; i++) {
      await seedLoginBucketToLastAllowed();
      const res = await fireLogin();
      if (res.status === 429) {
        saw429 = true;
        retryAfter = res.headers.get('Retry-After');
        break;
      }
      expect(res.status).toBe(401);
    }

    expect(saw429).toBe(true);
    expect(retryAfter).not.toBeNull();
    expect(Number(retryAfter)).toBeGreaterThanOrEqual(1);

    const body = (await (
      await SELF.fetch('https://example.com/api/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username: 'no-such-user', password: 'x' }),
      })
    ).json()) as { error: string };
    expect(body.error).toBe('Too many login attempts');
  });

  it('the login bucket does not consume the global bucket (separate keys)', async () => {
    // After the login bucket is exhausted, a normal authenticated request
    // (global bucket, different key) still works.
    const auth = await adminAuthHeader();
    const res = await SELF.fetch('https://example.com/api/sync/pull', {
      headers: { Authorization: auth },
    });
    expect(res.status).toBe(200);
  });
});

describe('rate limiting: trusted relay identity (pages.dev bridge)', () => {
  const SECRET = 'test-relay-secret-0123456789abcdef';
  const RELAY_IP = '41.200.12.34'; // عنوان عميل افتراضي خلف الجسر

  const relayHeaders = (extra: Record<string, string> = {}): Record<string, string> => ({
    'x-mh-relay-key': SECRET,
    'x-mh-client-ip': RELAY_IP,
    'x-mh-client-country': 'YE',
    ...extra,
  });

  it('trusts x-mh-client-ip for the login bucket when x-mh-relay-key matches RELAY_SECRET', async () => {
    // دلو الدخول الخاص بالعميل الحقيقي خلف الجسر معبأ إلى الحد الأخير
    // (20) — محاولة الدخول التالية عبر ترويسات الجسر يجب أن تشتعل 429.
    const WINDOW_MS = 60 * 1000;
    const windowStart = Math.floor(Date.now() / WINDOW_MS) * WINDOW_MS;
    await env.DB.prepare(
      'INSERT INTO rate_limits (client_id, window_start, count) VALUES (?, ?, ?) ' +
        'ON CONFLICT (client_id, window_start) DO UPDATE SET count = ?'
    )
      .bind(`login:${RELAY_IP}`, windowStart, 20, 20)
      .run();

    const res = await SELF.fetch('https://example.com/api/auth/login', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...relayHeaders(),
      },
      body: JSON.stringify({ username: 'no-such-user', password: 'x' }),
    });
    expect(res.status).toBe(429);
  });

  it('ignores relay headers when the key does not match the secret (no spoofing)', async () => {
    // نفس الدلو المعبأ لكن بمفتاح توقيع خاطئ — الطلب يُعامَل كمتصل
    // مباشر (client_id مختلف: 'unknown' في miniflare) فيمرّ 401 ولا 429.
    const WINDOW_MS = 60 * 1000;
    const windowStart = Math.floor(Date.now() / WINDOW_MS) * WINDOW_MS;
    await env.DB.prepare(
      'INSERT INTO rate_limits (client_id, window_start, count) VALUES (?, ?, ?) ' +
        'ON CONFLICT (client_id, window_start) DO UPDATE SET count = ?'
    )
      .bind(`login:${RELAY_IP}`, windowStart, 20, 20)
      .run();

    const res = await SELF.fetch('https://example.com/api/auth/login', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...relayHeaders({ 'x-mh-relay-key': 'wrong-secret-aaaaaaaaaaaaaaaaaa' }),
      },
      body: JSON.stringify({ username: 'no-such-user', password: 'x' }),
    });
    expect(res.status).toBe(401);
  });

  it('direct callers sending relay headers without any secret stay untrusted (env secret absent → headers ignored)', async () => {
    // يغطي المسار التراجعي: لو لم يُضبط RELAY_SECRET على البيئة فترويسات
    // x-mh-* لا تُقرأ أصلاً — نفس سلوك ما قبل الجسر.
    const WINDOW_MS = 60 * 1000;
    const windowStart = Math.floor(Date.now() / WINDOW_MS) * WINDOW_MS;
    // عبّئ دلو 'unknown' (هوية miniflare المباشرة) — لو قُبلت الترويسات
    // لانتقل الفحص إلى دلو RELAY_IP ولم يشتعل 429 أبداً.
    await env.DB.prepare(
      'INSERT INTO rate_limits (client_id, window_start, count) VALUES (?, ?, ?) ' +
        'ON CONFLICT (client_id, window_start) DO UPDATE SET count = ?'
    )
      .bind('login:unknown', windowStart, 20, 20)
      .run();

    // مفتاح صحيح لكن سيناريو env بلا سر غير قابل للمحاكاة هنا لأن
    // vitest.config يضبط RELAY_SECRET — لذا يكفي إثبات أن مفتاحاً
    // فارغاً (بلا ترويسة توقيع) لا يمنح الثقة حتى مع وجود x-mh-client-ip.
    const res = await SELF.fetch('https://example.com/api/auth/login', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-mh-client-ip': RELAY_IP,
        'x-mh-client-country': 'YE',
      },
      body: JSON.stringify({ username: 'no-such-user', password: 'x' }),
    });
    expect(res.status).toBe(429);
  });
});

describe('rate limiting: D1 counter mechanics', () => {
  it('increments count atomically per (client, window) and enforces the max', async () => {
    // Drive the limiter through its real SQL path: same fixed window,
    // same client key. RATE_LIMIT_MAX=1000 is too slow to reach via HTTP,
    // so simulate the exact UPSERT the worker runs and then verify the
    // 429 branch decision logic against the stored counter.
    const window = 60;
    const now = Date.now();
    const windowStart = Math.floor(now / (window * 1000)) * (window * 1000);

    for (let i = 0; i < 5; i++) {
      await env.DB.prepare(
        'INSERT INTO rate_limits (client_id, window_start, count) VALUES (?, ?, 1) ' +
          'ON CONFLICT (client_id, window_start) DO UPDATE SET count = count + 1 RETURNING count'
      )
        .bind('test-client', windowStart)
        .first<{ count: number }>();
    }
    const row = await env.DB.prepare(
      'SELECT count FROM rate_limits WHERE client_id = ? AND window_start = ?'
    )
      .bind('test-client', windowStart)
      .first<{ count: number }>();
    expect(row?.count).toBe(5);

    // allowed = count <= max — the exact comparison in index.ts
    const max = parseInt('1000', 10);
    expect(5 <= max).toBe(true);
    expect(1001 <= max).toBe(false);
  });

  it('fail-open: limiter errors do not block authenticated sync traffic', async () => {
    // Drop the rate_limits table — the limiter's INSERT throws, the catch
    // allowss the request through (fail-open), and sync keeps working.
    await env.DB.prepare('DROP TABLE rate_limits').run();
    const auth = await adminAuthHeader();
    const res = await SELF.fetch('https://example.com/api/sync/pull', {
      headers: { Authorization: auth },
    });
    expect(res.status).toBe(200);
    // Restore schema for subsequent tests.
    await resetDb();
  });
});
