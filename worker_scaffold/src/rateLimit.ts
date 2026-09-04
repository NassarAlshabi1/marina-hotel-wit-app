/**
 * KV-backed token-bucket rate limiter.
 * Mirrors the mobile `RATE_LIMIT` constants; prevents bursts on push/pull.
 */

import type { Env } from '../types';

const WINDOW_MS = 60_000;

export async function rateLimit(
  env: Env,
  key: string,
  limit: number,
): Promise<{ allowed: boolean; remaining: number; resetMs: number }> {
  const now = Date.now();
  const bucket = Math.floor(now / WINDOW_MS);
  const kvKey = `rl:${key}:${bucket}`;
  const raw = await env.RATE_KV.get(kvKey);
  const count = raw ? Number(raw) : 0;
  const resetMs = (bucket + 1) * WINDOW_MS - now;
  if (count >= limit) {
    return { allowed: false, remaining: 0, resetMs };
  }
  await env.RATE_KV.put(kvKey, String(count + 1), {
    expirationTtl: Math.ceil(WINDOW_MS / 1000) + 5,
  });
  return { allowed: true, remaining: limit - count - 1, resetMs };
}

export function rateLimitMiddleware(
  env: Env,
  key: string,
  limit: number,
): Promise<ReturnType<typeof rateLimit>> {
  return rateLimit(env, key, limit);
}