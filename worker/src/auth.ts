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

function base64UrlDecodeBytes(str: string): Uint8Array {
  const padded = str.replace(/-/g, '+').replace(/_/g, '/');
  const withPadding = padded + '='.repeat((4 - (padded.length % 4)) % 4);
  const binary = atob(withPadding);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

// ─── Constant-time comparison (prevents timing oracles) ───────

function constantTimeEqual(a: Uint8Array, b: Uint8Array): boolean {
  const maxLen = Math.max(a.length, b.length);
  let diff = a.length ^ b.length;
  for (let i = 0; i < maxLen; i++) {
    diff |= (a[i] ?? 0) ^ (b[i] ?? 0);
  }
  return diff === 0;
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
  let provided: Uint8Array;
  try {
    provided = base64UrlDecodeBytes(signature);
  } catch {
    return false;
  }
  // ✅ Constant-time compare — string equality leaked signature prefix
  // matches through timing.
  return constantTimeEqual(new Uint8Array(expected), provided);
}

// ─── Password Hashing (PBKDF2, versioned) ─────────────────────

// 25,000 iterations: ≈2.5× stronger than the legacy 10,000 while staying
// inside the Workers free-plan CPU budget (WebCrypto PBKDF2 is native).
// The format is versioned so the count can rise later without breaking
// stored hashes. verifyPassword supports BOTH formats.
const PBKDF2_ITERATIONS = 25_000;
const PBKDF2_LEGACY_ITERATIONS = 10_000;

function toHex(bytes: Uint8Array): string {
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, '0')).join('');
}

function hexToBytes(hex: string): Uint8Array | null {
  if (hex.length === 0 || hex.length % 2 !== 0 || !/^[0-9a-fA-F]+$/.test(hex)) return null;
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

async function pbkdf2Derive(password: string, salt: Uint8Array, iterations: number): Promise<ArrayBuffer> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(password),
    'PBKDF2',
    false,
    ['deriveBits']
  );
  return crypto.subtle.deriveBits(
    {
      name: 'PBKDF2',
      salt: salt as BufferSource,
      iterations,
      hash: 'SHA-256',
    },
    key,
    256
  );
}

export async function hashPassword(password: string): Promise<string> {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const hash = await pbkdf2Derive(password, salt, PBKDF2_ITERATIONS);
  const saltHex = toHex(salt);
  const hashHex = toHex(new Uint8Array(hash));
  return `pbkdf2$${PBKDF2_ITERATIONS}$${saltHex}$${hashHex}`;
}

export async function verifyPassword(password: string, storedHash: string): Promise<boolean> {
  try {
    let salt: Uint8Array;
    let expectedHash: Uint8Array;
    let iterations: number;

    if (storedHash.startsWith('pbkdf2$')) {
      // Versioned format: pbkdf2$<iterations>$<saltHex>$<hashHex>
      const parts = storedHash.split('$');
      if (parts.length !== 4) return false;
      const parsedIterations = parseInt(parts[1] ?? '', 10);
      const s = hexToBytes(parts[2] ?? '');
      const h = hexToBytes(parts[3] ?? '');
      if (!s || !h || !Number.isFinite(parsedIterations) || parsedIterations < 1 || parsedIterations > 1_000_000) {
        return false;
      }
      iterations = parsedIterations;
      salt = s;
      expectedHash = h;
    } else {
      // Legacy format: <saltHex>:<hashHex> with 10,000 iterations
      const parts = storedHash.split(':');
      if (parts.length !== 2) return false;
      const s = hexToBytes(parts[0] ?? '');
      const h = hexToBytes(parts[1] ?? '');
      if (!s || !h) return false;
      iterations = PBKDF2_LEGACY_ITERATIONS;
      salt = s;
      expectedHash = h;
    }

    const derived = new Uint8Array(await pbkdf2Derive(password, salt, iterations));
    // ✅ Constant-time compare — the old string equality leaked hash prefix
    // matches through timing, and a malformed stored hash used to THROW
    // (match on undefined) instead of failing the login cleanly.
    return constantTimeEqual(derived, expectedHash);
  } catch {
    return false;
  }
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
