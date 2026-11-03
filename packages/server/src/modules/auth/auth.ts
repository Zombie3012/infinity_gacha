import { createHmac, scrypt as scryptCallback, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';
import argon2 from 'argon2';

const scrypt = promisify(scryptCallback);
export const TOKEN_LIFETIME_SECONDS = 60 * 60 * 24;

function getSecret(): string {
  if (process.env.NODE_ENV === 'production' && !process.env.AUTH_SECRET) {
    throw new Error('AUTH_SECRET must be set in production.');
  }
  return process.env.AUTH_SECRET ?? 'local-development-secret-change-before-deploy';
}

export async function hashPassword(password: string): Promise<string> {
  return argon2.hash(password, { type: argon2.argon2id });
}

export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  if (stored.startsWith('$argon2id$')) {
    try { return await argon2.verify(stored, password); } catch { return false; }
  }
  const [algorithm, saltHex, hashHex] = stored.split('$');
  if (algorithm !== 'scrypt' || !saltHex || !hashHex) return false;
  const expected = Buffer.from(hashHex, 'hex');
  const actual = (await scrypt(password, Buffer.from(saltHex, 'hex'), expected.length)) as Buffer;
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}

interface TokenPayload { accountId: string; sessionId: string; exp: number }

export function createAccessToken(accountId: string, sessionId: string): string {
  const payload: TokenPayload = { accountId, sessionId, exp: Math.floor(Date.now() / 1000) + TOKEN_LIFETIME_SECONDS };
  const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
  const encodedPayload = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const content = `${header}.${encodedPayload}`;
  const signature = createHmac('sha256', getSecret()).update(content).digest('base64url');
  return `${content}.${signature}`;
}

export function readAccessToken(token: string): TokenPayload | undefined {
  const [headerPart, payloadPart, suppliedSignature] = token.split('.');
  if (!headerPart || !payloadPart || !suppliedSignature) return undefined;
  const expectedSignature = createHmac('sha256', getSecret()).update(`${headerPart}.${payloadPart}`).digest();
  let actualSignature: Buffer;
  try { actualSignature = Buffer.from(suppliedSignature, 'base64url'); } catch { return undefined; }
  if (expectedSignature.length !== actualSignature.length || !timingSafeEqual(expectedSignature, actualSignature)) return undefined;
  try {
    const header = JSON.parse(Buffer.from(headerPart, 'base64url').toString()) as { alg?: string; typ?: string };
    if (header.alg !== 'HS256' || header.typ !== 'JWT') return undefined;
    const payload = JSON.parse(Buffer.from(payloadPart, 'base64url').toString()) as TokenPayload;
    if (!payload.accountId || !payload.sessionId || payload.exp <= Math.floor(Date.now() / 1000)) return undefined;
    return payload;
  } catch { return undefined; }
}
