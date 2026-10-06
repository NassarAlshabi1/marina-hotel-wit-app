import { env, SELF } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import migrationSql from '../migrations/0016_sync_source_identity.sql?raw';
import {
  adminAuthHeader,
  pushOp,
  pushOperations,
  resetDb,
  roomPayload,
  schemaStatements,
} from './helpers';

beforeEach(async () => {
  await resetDb();
});

async function healthSourceId(auth: string): Promise<string> {
  const response = await SELF.fetch('https://example.com/api/health/d1', {
    headers: { Authorization: auth },
  });
  expect(response.status).toBe(200);
  const body = (await response.json()) as { sync_source_id: string | null };
  expect(body.sync_source_id).toMatch(/^[a-f0-9]{32}$/);
  return body.sync_source_id!;
}

describe('sync source identity migration and request guard', () => {
  it('migration 0016 seeds exactly one stable identity and is safe to re-run', async () => {
    await env.DB.prepare("DELETE FROM sync_meta WHERE k = 'source_id'").run();
    for (const statement of schemaStatements(migrationSql)) await env.DB.prepare(statement).run();
    const first = await env.DB.prepare("SELECT v FROM sync_meta WHERE k = 'source_id'").first<{ v: string }>();
    for (const statement of schemaStatements(migrationSql)) await env.DB.prepare(statement).run();
    const second = await env.DB.prepare("SELECT v FROM sync_meta WHERE k = 'source_id'").first<{ v: string }>();

    expect(first?.v).toBe('607f109083b14281975fd81b8f6154e7');
    expect(second?.v).toBe(first?.v);
  });

  it('health does not invent an identity when migration data is missing', async () => {
    await env.DB.prepare("DELETE FROM sync_meta WHERE k = 'source_id'").run();
    const auth = await adminAuthHeader();
    const response = await SELF.fetch('https://example.com/api/health/d1', {
      headers: { Authorization: auth },
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      status: 'ok',
      d1: 'ok',
      sync_provider: 'cloudflare-d1',
      sync_source_id: null,
      sync_protocol_version: 1,
    });
  });

  it('rejects a push and pull bound to another source before their handlers run', async () => {
    const auth = await adminAuthHeader();
    const actualSourceId = await healthSourceId(auth);
    const otherSourceId = actualSourceId === '00000000000000000000000000000000'
      ? '11111111111111111111111111111111'
      : '00000000000000000000000000000000';

    const pull = await SELF.fetch('https://example.com/api/sync/pull?cursor=0&limit=1', {
      headers: { Authorization: auth, 'X-Sync-Source-Id': otherSourceId },
    });
    const push = await SELF.fetch('https://example.com/api/sync/push', {
      method: 'POST',
      headers: {
        Authorization: auth,
        'Content-Type': 'application/json',
        'X-Sync-Source-Id': otherSourceId,
      },
      body: '{malformed-json-is-not-read-before-the-source-check',
    });

    expect(pull.status).toBe(409);
    expect(await pull.json()).toMatchObject({ code: 'sync_source_mismatch' });
    expect(push.status).toBe(409);
    expect(await push.json()).toMatchObject({ code: 'sync_source_mismatch' });
  });

  it('accepts a correctly bound pull and rejects bound requests if identity is unavailable', async () => {
    const auth = await adminAuthHeader();
    const sourceId = await healthSourceId(auth);
    const accepted = await SELF.fetch('https://example.com/api/sync/pull?cursor=0&limit=1', {
      headers: { Authorization: auth, 'X-Sync-Source-Id': sourceId },
    });
    expect(accepted.status).toBe(200);
    const pushed = await pushOperations(
      auth,
      [pushOp('rooms', 'create', roomPayload())],
      { 'X-Sync-Source-Id': sourceId }
    );
    expect(pushed.status).toBe(200);
    expect(await pushed.json()).toMatchObject({ summary: { success: 1 } });

    await env.DB.prepare("DELETE FROM sync_meta WHERE k = 'source_id'").run();
    const blocked = await SELF.fetch('https://example.com/api/sync/push', {
      method: 'POST',
      headers: {
        Authorization: auth,
        'Content-Type': 'application/json',
        'X-Sync-Source-Id': sourceId,
      },
      body: JSON.stringify({ operations: [] }),
    });
    expect(blocked.status).toBe(409);
    expect(await blocked.json()).toMatchObject({ code: 'sync_source_mismatch' });
  });
});
