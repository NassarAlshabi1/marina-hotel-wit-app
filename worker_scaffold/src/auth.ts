/**
 * JWT auth (HS256) — issues/validates device tokens.
 * Replaces Appwrite session/API-key auth.
 */

import { createJWT, jwtVerify } from 'jose';

import type { DeviceContext, Env } from '../types';

const TEXT = new TextEncoder();

export async function issueToken(env: Env, ctx: DeviceContext): Promise<string> {
  const secret = new Uint8Array([...new TextEncoder().encode(env.JWT_SECRET)]);
  const now = Math.floor(Date.now() / 1000);
  return await createJWT(
    {
      sub: ctx.deviceId,
      deviceId: ctx.deviceId,
      hotelId: ctx.hotelId,
      userId: ctx.userId,
      iss: 'marina-sync-worker',
      aud: 'marina-hotel-mobile',
      iat: now,
      exp: now + 12 * 60 * 60,
    },
    secret,
  );
}

export async function verifyToken(
  env: Env,
  token: string,
): Promise<DeviceContext | null> {
  try {
    const secret = new Uint8Array([...new TextEncoder().encode(env.JWT_SECRET)]);
    const { payload } = await jwtVerify(token, secret, {
      issuer: 'marina-sync-worker',
      audience: 'marina-hotel-mobile',
    });
    const deviceId = (payload.deviceId as string) ?? (payload.sub as string);
    const hotelId = (payload.hotelId as string) ?? env.HOTEL_ID;
    if (!deviceId) return null;
    return { deviceId, hotelId, userId: payload.userId as string | undefined };
  } catch {
    return null;
  }
}