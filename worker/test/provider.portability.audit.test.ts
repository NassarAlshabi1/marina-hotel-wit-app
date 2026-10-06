// Source identity/protocol contract tests for the Cloudflare Android adapter.
// Passing these tests establishes a guard, not a cross-provider data migration.
import { SELF } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import { adminAuthHeader, resetDb } from './helpers';

beforeEach(async () => {
  await resetDb();
});

describe('sync source identity contract', () => {
  it('advertises a stable source id, provider id, and protocol version', async () => {
    const auth = await adminAuthHeader();
    const request = () => SELF.fetch('https://example.com/api/health/d1', {
      headers: { Authorization: auth },
    });

    const first = await request();
    const second = await request();
    expect(first.status).toBe(200);
    expect(second.status).toBe(200);
    const body = (await first.json()) as Record<string, unknown>;
    const repeated = (await second.json()) as Record<string, unknown>;
    expect(body).toMatchObject({
      status: 'ok',
      d1: 'ok',
      expense_kind: true,
      sync_provider: 'cloudflare-d1',
      sync_protocol_version: 1,
    });
    expect(body.sync_source_id).toMatch(/^[a-f0-9]{32}$/);
    expect(repeated.sync_source_id).toBe(body.sync_source_id);
  });
});
