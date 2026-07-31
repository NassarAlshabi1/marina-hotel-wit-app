// ═══════════════════════════════════════════════════════════════
//  auth.ts — JWT Authentication + Middleware
//  Self-signed JWT (HMAC-SHA256) — no external dependencies
// ═══════════════════════════════════════════════════════════════

import type { Database } from './database';

// ─── Types ────────────────────────────────────────────────────

export interface JwtPayload {
  sub: string; // user ID
  username: string;
  role: string;
  device_id?: string;
  iat: number; // issued at
  exp: number; // expiration
}

export interface AuthContext {
  userId: string;
  username: string;
  role: string;
  deviceId: string;
}

// ─── HMAC-SHA256 JWT Implementation ───────────────────────────

function base64UrlEncode(data: ArrayBuffer | string): string {
  const bytes = typeof data === 'string' ? new TextEncoder().encode(data) : new Uint8Array(data);
  let binary = '';
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function base64UrlDecode(str: string): string {
  const padded = str.replace(/-/g, '+').replace(/_/g, '/');
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return new TextDecoder().decode(bytes);
}

async function hmacSign(secret: string, message: string): Promise<ArrayBuffer> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );
  return crypto.subtle.sign('HMAC', key, new TextEncoder().encode(message));
}

async function hmacVerify(secret: string, message: string, signature: string): Promise<boolean> {
  const expected = await hmacSign(secret, message);
  const expectedB64 = base64UrlEncode(expected);
  return expectedB64 === signature;
}

// ─── Password Hashing (PBKDF2) ────────────────────────────────

export async function hashPassword(password: string): Promise<string> {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(password),
    'PBKDF2',
    false,
    ['deriveBits']
  );
  const hash = await crypto.subtle.deriveBits(
    {
      name: 'PBKDF2',
      salt,
      iterations: 10000,
      hash: 'SHA-256',
    },
    key,
    256
  );
  const saltHex = Array.from(salt).map((b) => b.toString(16).padStart(2, '0')).join('');
  const hashHex = Array.from(new Uint8Array(hash)).map((b) => b.toString(16).padStart(2, '0')).join('');
  return `${saltHex}:${hashHex}`;
}

export async function verifyPassword(password: string, storedHash: string): Promise<boolean> {
  const [saltHex, hashHex] = storedHash.split(':');
  const salt = new Uint8Array(saltHex.match(/.{2}/g)!.map((byte) => parseInt(byte, 16)));
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(password),
    'PBKDF2',
    false,
    ['deriveBits']
  );
  const hash = await crypto.subtle.deriveBits(
    {
      name: 'PBKDF2',
      salt,
      iterations: 10000,
      hash: 'SHA-256',
    },
    key,
    256
  );
  const computedHex = Array.from(new Uint8Array(hash)).map((b) => b.toString(16).padStart(2, '0')).join('');
  return computedHex === hashHex;
}

// ─── JWT Token ────────────────────────────────────────────────

export async function signToken(payload: Omit<JwtPayload, 'iat' | 'exp'>, secret: string, expiryHours: number = 24): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const fullPayload: JwtPayload = {
    ...payload,
    iat: now,
    exp: now + expiryHours * 3600,
  };

  const header = { alg: 'HS256', typ: 'JWT' };
  const headerB64 = base64UrlEncode(JSON.stringify(header));
  const payloadB64 = base64UrlEncode(JSON.stringify(fullPayload));
  const signingInput = `${headerB64}.${payloadB64}`;
  const signature = base64UrlEncode(await hmacSign(secret, signingInput));

  return `${signingInput}.${signature}`;
}

export async function verifyToken(token: string, secret: string): Promise<JwtPayload | null> {
  const parts = token.split('.');
  if (parts.length !== 3) return null;

  const [headerB64, payloadB64, signature] = parts;
  const signingInput = `${headerB64}.${payloadB64}`;

  const valid = await hmacVerify(secret, signingInput, signature);
  if (!valid) return null;

  try {
    const payload = JSON.parse(base64UrlDecode(payloadB64)) as JwtPayload;
    const now = Math.floor(Date.now() / 1000);
    if (payload.exp < now) return null;
    return payload;
  } catch {
    return null;
  }
}

// ─── Auth Middleware ──────────────────────────────────────────

export async function authMiddleware(
  request: Request,
  env: { JWT_SECRET: string; DB: unknown }
): Promise<{ authenticated: boolean; context?: AuthContext; error?: string }> {
  const authHeader = request.headers.get('Authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return { authenticated: false, error: 'Missing or invalid Authorization header' };
  }

  const token = authHeader.substring(7);
  const payload = await verifyToken(token, env.JWT_SECRET);

  if (!payload) {
    return { authenticated: false, error: 'Invalid or expired token' };
  }

  return {
    authenticated: true,
    context: {
      userId: payload.sub,
      username: payload.username,
      role: payload.role,
      deviceId: payload.device_id || '',
    },
  };
}

// ─── Login Handler ────────────────────────────────────────────

export async function handleLogin(
  request: Request,
  db: Database,
  jwtSecret: string
): Promise<Response> {
  try {
    const body = await request.json() as { username?: string; password?: string; device_id?: string };

    if (!body.username || !body.password) {
      return json({ error: 'Username and password required' }, 400);
    }

    const user = await db.getUser(body.username);
    if (!user) {
      return json({ error: 'Invalid credentials' }, 401);
    }

    const valid = await verifyPassword(body.password, user.password_hash);
    if (!valid) {
      return json({ error: 'Invalid credentials' }, 401);
    }

    const token = await signToken(
      {
        sub: user.id,
        username: body.username,
        role: user.role,
        device_id: body.device_id || '',
      },
      jwtSecret
    );

    return json({
      token,
      user: {
        id: user.id,
        username: body.username,
        role: user.role,
      },
    });
  } catch (err) {
    return json({ error: 'Login failed', detail: String(err) }, 500);
  }
}

// ─── Helper ───────────────────────────────────────────────────

function json(data: unknown, status: number = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
