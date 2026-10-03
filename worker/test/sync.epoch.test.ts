// Sync epoch contract: stable value, admin-only rotation, and fail-open
// behavior while an installation is missing migration 0010.
import { env, SELF } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import migrationSql0010 from '../migrations/0010_sync_meta.sql?raw';
import { adminAuthHeader, pull, resetDb, schemaStatements } from './helpers';

beforeEach(async () => {
  await resetDb();
});

async function staffAuthHeader(): Promise<string> {
  const admin = await adminAuthHeader();
  const response = await SELF.fetch('https://example.com/api/auth/register', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: admin,
    },
    body: JSON.stringify({
      username: 'epoch-staff',
      password: 'staff-pw-123',
      role: 'staff',
    }),
  });
  expect(response.status).toBe(201);
  const body = (await response.json()) as { token: string };
  return `Bearer ${body.token}`;
}

function rotate(auth: string): Promise<Response> {
  return SELF.fetch('https://example.com/api/admin/sync/rotate-epoch', {
    method: 'POST',
    headers: { Authorization: auth },
  });
}

describe('sync epoch', () => {
  it('pull returns a non-empty, stable generation', async () => {
    const auth = await adminAuthHeader();
    const first = await pull(auth);
    const second = await pull(auth, { cursor: '5' });

    expect(first.epoch).toMatch(/^[0-9a-f]{32}$/);
    expect(second.epoch).toBe(first.epoch);
  });

  it('admin rotation changes the generation returned by pull', async () => {
    const auth = await adminAuthHeader();
    const before = (await pull(auth)).epoch;
    const response = await rotate(auth);

    expect(response.status).toBe(200);
    const body = (await response.json()) as { success: boolean; epoch: string };
    expect(body.success).toBe(true);
    expect(body.epoch).not.toBe(before);
    expect((await pull(auth)).epoch).toBe(body.epoch);
  });

  it('rejects epoch rotation for non-admin users', async () => {
    const admin = await adminAuthHeader();
    const before = (await pull(admin)).epoch;
    const staff = await staffAuthHeader();

    expect((await rotate(staff)).status).toBe(403);
    expect((await pull(admin)).epoch).toBe(before);
  });

  it('continues pulling with epoch=null when migration 0010 is absent', async () => {
    const auth = await adminAuthHeader();
    await env.DB.prepare('DROP TABLE IF EXISTS sync_meta').run();

    const body = await pull(auth);
    expect(body.epoch).toBeNull();
    expect(Array.isArray(body.changes)).toBe(true);
  });

  it('migration 0010 is idempotent and preserves an existing generation', async () => {
    const auth = await adminAuthHeader();
    const seeded = (await pull(auth)).epoch;

    for (const statement of schemaStatements(migrationSql0010)) {
      await env.DB.prepare(statement).run();
    }
    expect((await pull(auth)).epoch).toBe(seeded);
  });

  it('migration 0010 seeds a generation on an existing database', async () => {
    await env.DB.prepare('DROP TABLE IF EXISTS sync_meta').run();
    for (const statement of schemaStatements(migrationSql0010)) {
      await env.DB.prepare(statement).run();
    }

    const row = await env.DB
      .prepare("SELECT v FROM sync_meta WHERE k = 'epoch'")
      .first<{ v: string }>();
    expect(row?.v).toMatch(/^[0-9a-f]{32}$/);
  });
});
