// ═══════════════════════════════════════════════════════════════
//  sync.epoch.test.ts — ✅ (2026-09-29) جيل بيانات المزامنة
//  عقود: السحب يعيد epoch ثابتاً بين الطلبات؛ التدوير admin فقط ويغيّره؛
//  غياب الجدول (نشر لم يطبّق 0010) لا يكسر السحب؛ الترحيل 0010
//  idempotent على قاعدة قائمة ولا يغيّر جيلاً مزروعاً.
// ═══════════════════════════════════════════════════════════════

import { env, SELF } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import migrationSql0010 from '../migrations/0010_sync_meta.sql?raw';
import { adminAuthHeader, pull, resetDb, schemaStatements } from './helpers';

beforeEach(async () => {
  await resetDb();
});

async function staffAuthHeader(): Promise<string> {
  const auth = await adminAuthHeader();
  const res = await SELF.fetch('https://example.com/api/auth/register', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: auth },
    body: JSON.stringify({ username: 'epoch-staff', password: 'staff-pw-123', role: 'staff' }),
  });
  expect(res.status).toBe(201);
  return `Bearer ${((await res.json()) as { token: string }).token}`;
}

function rotate(auth: string): Promise<Response> {
  return SELF.fetch('https://example.com/api/admin/sync/rotate-epoch', {
    method: 'POST',
    headers: { Authorization: auth },
  });
}

describe('sync epoch', () => {
  it('السحب يعيد epoch غير فارغ وثابتاً بين الطلبات', async () => {
    const auth = await adminAuthHeader();
    const a = await pull(auth);
    const b = await pull(auth, { cursor: '5' });
    expect(typeof a.epoch).toBe('string');
    expect(a.epoch!.length).toBeGreaterThanOrEqual(16);
    expect(b.epoch).toBe(a.epoch);
  });

  it('التدوير (admin) يغيّر الجيل والسحب التالي يعكسه', async () => {
    const auth = await adminAuthHeader();
    const before = (await pull(auth)).epoch;
    const res = await rotate(auth);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { success: boolean; epoch: string };
    expect(body.success).toBe(true);
    expect(body.epoch).not.toBe(before);
    expect((await pull(auth)).epoch).toBe(body.epoch);
  });

  it('التدوير ممنوع لغير admin (403) ولا يغيّر الجيل', async () => {
    const admin = await adminAuthHeader();
    const before = (await pull(admin)).epoch;
    const staff = await staffAuthHeader();
    expect((await rotate(staff)).status).toBe(403);
    expect((await pull(admin)).epoch).toBe(before);
  });

  it('جدول sync_meta غائب → السحب 200 مع epoch=null (لا كسر)', async () => {
    const auth = await adminAuthHeader();
    await env.DB.prepare('DROP TABLE IF EXISTS sync_meta').run();
    const body = await pull(auth);
    expect(body.epoch).toBeNull();
    expect(Array.isArray(body.changes)).toBe(true);
  });

  it('الترحيل 0010 idempotent ولا يستبدل جيلاً مزروعاً', async () => {
    const auth = await adminAuthHeader();
    const seeded = (await pull(auth)).epoch;
    for (const stmt of schemaStatements(migrationSql0010)) {
      await env.DB.prepare(stmt).run();
    }
    expect((await pull(auth)).epoch).toBe(seeded);
  });

  it('الترحيل 0010 على قاعدة بلا الجدول يزرع جيلاً', async () => {
    await env.DB.prepare('DROP TABLE IF EXISTS sync_meta').run();
    for (const stmt of schemaStatements(migrationSql0010)) {
      await env.DB.prepare(stmt).run();
    }
    const row = await env.DB.prepare("SELECT v FROM sync_meta WHERE k = 'epoch'").first<{ v: string }>();
    expect(row?.v).toMatch(/^[0-9a-f]{32}$/);
  });
});
