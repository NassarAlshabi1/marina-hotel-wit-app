// ═══════════════════════════════════════════════════════════════
//  sync.push.gzip.test.ts — P1 payload limits (2026-09-24)
//
//  يحرس السقف المزدوج لـ /api/sync/push:
//    compressed size <= 5MB   (ببايتات الشبكة الفعلية — حتى بلا
//                              Content-Length)
//    decompressed size <= 5MB (حماية gzip bomb — مضغوط عنيف يتضخم)
// ═══════════════════════════════════════════════════════════════

import { SELF } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import {
  resetDb,
  adminAuthHeader,
  pushOp,
  roomPayload,
  type PushResponseBody,
} from './helpers';

beforeEach(async () => {
  await resetDb();
});

const MAX_PAYLOAD_SIZE = 5 * 1024 * 1024; // 5MB — نفس ثابت sync.ts

async function gzipAsync(data: Uint8Array): Promise<Uint8Array> {
  const cs = new CompressionStream('gzip');
  const writer = cs.writable.getWriter();
  void writer.write(data);
  void writer.close();
  const buf = await new Response(cs.readable).arrayBuffer();
  return new Uint8Array(buf);
}

async function pushGzip(
  auth: string,
  body: Uint8Array,
  extraHeaders: Record<string, string> = {}
): Promise<Response> {
  return SELF.fetch('https://example.com/api/sync/push', {
    method: 'POST',
    headers: {
      Authorization: auth,
      'Content-Type': 'application/json',
      'Content-Encoding': 'gzip',
      ...extraHeaders,
    },
    body: body as unknown as BodyInit,
  });
}

describe('push: gzip payload limits (P1)', () => {
  it('valid gzip payload is decompressed and processed normally', async () => {
    const auth = await adminAuthHeader();
    const payload = roomPayload();
    const op = pushOp('rooms', 'create', payload);
    const plain = new TextEncoder().encode(JSON.stringify({ operations: [op] }));
    const gz = await gzipAsync(plain);

    const res = await pushGzip(auth, gz);
    expect(res.status).toBe(200);
    const body = (await res.json()) as PushResponseBody;
    expect(body.summary.success).toBe(1);
  });

  it('invalid gzip body → structured error (no crash, no partial write)', async () => {
    const auth = await adminAuthHeader();
    const garbage = new TextEncoder().encode('this is not gzip at all');

    const res = await pushGzip(auth, garbage);
    expect(res.status).toBe(500);
    const body = (await res.json()) as { error: string };
    expect(body.error).toBe('Push failed');
  });

  it('decompressed >5MB (gzip bomb: tiny compressed, huge expansion) → 413', async () => {
    const auth = await adminAuthHeader();
    // 6MB من حرف واحد: مضغوط ≈ 6KB لكن مفكوكه فوق السقف
    const huge = new TextEncoder().encode(
      JSON.stringify({ padding: 'a'.repeat(6 * 1024 * 1024) })
    );
    expect(huge.byteLength).toBeGreaterThan(MAX_PAYLOAD_SIZE);
    const gz = await gzipAsync(huge);
    expect(gz.byteLength).toBeLessThan(1024 * 1024); // مضغوط بشدة فعلاً

    const res = await pushGzip(auth, gz);
    expect(res.status).toBe(413);
    const body = (await res.json()) as { error: string; scope?: string };
    expect(body.error).toContain('too large');
    expect(body.scope).toBe('decompressed');
  }, 30_000);

  it('compressed >5MB with a lying/absent Content-Length → 413 by byte counting', async () => {
    const auth = await adminAuthHeader();
    // جسم مضغوط فعلاً أكبر من 5MB (عشوائي شبه غير قابل للضغط)
    // getRandomValues محدود بـ 64K للاستدعاء — نملأ على دفعات
    const raw = new Uint8Array(6 * 1024 * 1024);
    const CHUNK = 65536;
    for (let off = 0; off < raw.byteLength; off += CHUNK) {
      crypto.getRandomValues(raw.subarray(off, Math.min(off + CHUNK, raw.byteLength)));
    }
    const gz = await gzipAsync(raw);
    expect(gz.byteLength).toBeGreaterThan(MAX_PAYLOAD_SIZE);

    // بلا Content-Length أصلاً — العدّاد أثناء القراءة هو الحارس
    const res = await pushGzip(auth, gz);
    expect(res.status).toBe(413);
    const body = (await res.json()) as { error: string; scope?: string };
    expect(body.error).toContain('too large');
    expect(body.scope).toBe('compressed');
  }, 30_000);
});
