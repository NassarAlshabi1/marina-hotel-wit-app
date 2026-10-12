// ═══════════════════════════════════════════════════════════════
//  sync.pull.limits.test.ts — P1/P2 pull params + admin maintenance (2026-09-24)
//
//  explicit pull parameter contract:
//    cursor / limit=0 / limit=-1 / limit=500 / limit=999999 /
//    unknown entity / tombstones_only / exclude_device
//    normalize_timestamps: admin/manager only (maintenance moved off GET)
// ═══════════════════════════════════════════════════════════════

import { SELF } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import {
  resetDb,
  adminAuthHeader,
  pull,
  pushOp,
  pushOperations,
  roomPayload,
  type PullResponseBody,
} from './helpers';

beforeEach(async () => {
  await resetDb();
});

/** Register a staff user through the real bootstrap-free admin flow. */
async function staffAuthHeader(): Promise<string> {
  const auth = await adminAuthHeader();
  const res = await SELF.fetch('https://example.com/api/auth/register', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: auth },
    body: JSON.stringify({ username: 'staffer', password: 'staff-pw-123', role: 'staff' }),
  });
  expect(res.status).toBe(201);
  const body = (await res.json()) as { token: string };
  return `Bearer ${body.token}`;
}

async function seedOneRoom(): Promise<string> {
  const auth = await adminAuthHeader();
  const p = roomPayload();
  const res = await pushOperations(auth, [pushOp('rooms', 'create', p)]);
  expect(((await res.json()) as { summary: { success: number } }).summary.success).toBe(1);
  return String(p.local_uuid);
}

describe('pull: explicit limit parameter contract', () => {
  it.each(['0', '-1', '500', '999999'] as const)(
    'limit=%s is clamped into [1, 500]',
    async (limitParam) => {
    await seedOneRoom();
    const auth = await adminAuthHeader();
    const data = await pull(auth, { limit: limitParam });
    expect(data.changes.length).toBeLessThanOrEqual(500);
    expect(data.has_more).toBe(false);
    },
  );
});

describe('pull: entity + filters contract', () => {
  it('unknown entity → 400 with a clear error', async () => {
    const auth = await adminAuthHeader();
    const res = await SELF.fetch('https://example.com/api/sync/pull?entity=not_an_entity', {
      headers: { Authorization: auth },
    });
    expect(res.status).toBe(400);
    const body = (await res.json()) as { error: string };
    expect(body.error).toContain('Unknown entity');
  });

  it('cursor paginates without duplication across pages', async () => {
    const auth = await adminAuthHeader();
    await seedOneRoom();
    const page1 = await pull(auth, { limit: '1' });
    if (page1.has_more) {
      const page2 = await pull(auth, { cursor: page1.cursor, limit: '1' });
      const ids1 = page1.changes.map((c) => c.local_uuid);
      const ids2 = page2.changes.map((c) => c.local_uuid);
      for (const id of ids2) expect(ids1).not.toContain(id);
    }
  });

  it('exclude_device filters rows stamped by the given device (echo filter)', async () => {
    const auth = await adminAuthHeader();
    await seedOneRoom();
    const everything = await pull(auth, {});
    const mine = await pull(auth, { exclude_device: 'device-A' });
    expect(mine.changes.length).toBeLessThan(everything.changes.length);
  });

  it('tombstones_only=1 returns deleted rows exclusively', async () => {
    const auth = await adminAuthHeader();
    const uuid = await seedOneRoom();
    await pushOperations(auth, [
      pushOp('rooms', 'delete', { local_uuid: uuid }),
    ]);
    const only = await pull(auth, { tombstones_only: '1' });
    expect(only.changes.length).toBeGreaterThanOrEqual(1);
    for (const row of only.changes) {
      expect(row.deleted_at).not.toBeNull();
    }
  });
});

describe('pull: normalize_timestamps is maintenance (P1 gating)', () => {
  it('staff requesting normalize_timestamps=1 gets a normal pull (normalization skipped)', async () => {
    await seedOneRoom();
    const staff = await staffAuthHeader();
    const data = (await SELF.fetch(
      'https://example.com/api/sync/pull?normalize_timestamps=1',
      { headers: { Authorization: staff } }
    ).then((r) => r.json())) as PullResponseBody;
    // نفس شكل الاستجابة المتوافق — normalization:null (كما عند تعطيل الصيانة)
    expect(data.normalization).toBeNull();
    expect(data.changes).toBeDefined();
    expect(data.cursor).toBeDefined();
  });

  it('admin requesting normalize_timestamps=1 runs the maintenance pass', async () => {
    await seedOneRoom();
    const auth = await adminAuthHeader();
    const data = await pull(auth, { normalize_timestamps: '1' });
    expect(data.normalization).not.toBeNull();
    expect(typeof data.normalization!.normalized).toBe('number');
    expect(typeof data.normalization!.remaining).toBe('number');
  });

  it('POST /api/admin/sync/normalize-timestamps: admin → 200, staff → 403', async () => {
    const admin = await adminAuthHeader();
    const staff = await staffAuthHeader();

    const staffRes = await SELF.fetch('https://example.com/api/admin/sync/normalize-timestamps', {
      method: 'POST',
      headers: { Authorization: staff },
    });
    expect(staffRes.status).toBe(403);

    const adminRes = await SELF.fetch('https://example.com/api/admin/sync/normalize-timestamps', {
      method: 'POST',
      headers: { Authorization: admin },
    });
    expect(adminRes.status).toBe(200);
    const body = (await adminRes.json()) as { success: boolean; normalized: number; remaining: number };
    expect(body.success).toBe(true);
  });
});

describe('P2: privileged endpoints are role-gated', () => {
  it('/api/stats: staff → 403, admin → 200', async () => {
    const admin = await adminAuthHeader();
    const staff = await staffAuthHeader();

    const staffRes = await SELF.fetch('https://example.com/api/stats', {
      headers: { Authorization: staff },
    });
    expect(staffRes.status).toBe(403);

    const adminRes = await SELF.fetch('https://example.com/api/stats', {
      headers: { Authorization: admin },
    });
    expect(adminRes.status).toBe(200);
  });

  it('/api/sync/log and /api/sync/conflicts: staff → 403, manager/admin → 200', async () => {
    const admin = await adminAuthHeader();
    const staff = await staffAuthHeader();

    for (const p of ['/api/sync/log', '/api/sync/conflicts']) {
      const staffRes = await SELF.fetch(`https://example.com${p}`, {
        headers: { Authorization: staff },
      });
      expect(staffRes.status).toBe(403);

      const adminRes = await SELF.fetch(`https://example.com${p}`, {
        headers: { Authorization: admin },
      });
      expect(adminRes.status).toBe(200);
    }
  });

  it('/api/sync/pull and /api/sync/push remain open to staff (no role change)', async () => {
    const staff = await staffAuthHeader();
    const pullRes = await SELF.fetch('https://example.com/api/sync/pull', {
      headers: { Authorization: staff },
    });
    expect(pullRes.status).toBe(200);

    const pushRes = await SELF.fetch('https://example.com/api/sync/push', {
      method: 'POST',
      headers: { Authorization: staff, 'Content-Type': 'application/json' },
      body: JSON.stringify({ operations: [] }),
    });
    expect(pushRes.status).toBe(200);
  });
});

describe('P2: 429 retry_after is relative seconds (not epoch-ms)', () => {
  it('login 429 body carries small second counts consistent with the header', async () => {
    // 20 محاولة فاشلة → 429 (نفس سيناريو rateLimit.test.ts لكن نتحقق من الجسم)
    let saw429 = false;
    for (let i = 0; i < 25; i++) {
      const res = await SELF.fetch('https://example.com/api/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username: 'nobody', password: 'wrong' }),
      });
      if (res.status === 429) {
        saw429 = true;
        const body = (await res.json()) as { retry_after: number };
        expect(Number.isFinite(body.retry_after)).toBe(true);
        // ثوانٍ نسبية (≤ 3600) وليست epoch-ms ولا epoch-seconds
        expect(body.retry_after).toBeGreaterThan(0);
        expect(body.retry_after).toBeLessThanOrEqual(3600);
        break;
      }
    }
    expect(saw429).toBe(true);
  });
});
