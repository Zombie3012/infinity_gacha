import { createHash, createHmac, timingSafeEqual } from 'node:crypto';

/**
 * Domain 01 (P1) account linking helpers.
 *
 * The prototype does not talk to Google or Apple. A provider hand-off is
 * simulated with an HMAC of `provider:providerUserId` keyed by
 * LINK_PROVIDER_SECRET, so the linking and recovery flows can be exercised end
 * to end without pretending to be an OAuth client.
 */

export const SUPPORTED_PROVIDERS = ['GOOGLE', 'APPLE'] as const;
export type AuthProvider = (typeof SUPPORTED_PROVIDERS)[number];

export const RECOVERY_TOKEN_TTL_HOURS = 24;

export function isSupportedProvider(value: string): value is AuthProvider {
  return (SUPPORTED_PROVIDERS as readonly string[]).includes(value);
}

export function providerSignature(secret: string, provider: string, providerUserId: string): string {
  return createHmac('sha256', secret).update(`${provider}:${providerUserId}`).digest('hex');
}

export function verifyProviderSignature(secret: string, provider: string, providerUserId: string, supplied: string): boolean {
  if (!secret || !supplied) return false;
  const expected = Buffer.from(providerSignature(secret, provider, providerUserId));
  const actual = Buffer.from(supplied.trim().toLowerCase());
  if (expected.length !== actual.length) return false;
  return timingSafeEqual(expected, actual);
}

export function recoveryToken(): string {
  return createHmac('sha256', 'infinite-gacha-recovery')
    .update(`${Date.now()}:${Math.random()}`)
    .digest('hex')
    .slice(0, 32)
    .toUpperCase();
}

export function hashRecoveryToken(token: string): string {
  return createHash('sha256').update(token.trim().toUpperCase()).digest('hex');
}

export function recoveryExpiry(now: Date, ttlHours = RECOVERY_TOKEN_TTL_HOURS): Date {
  return new Date(now.getTime() + Math.max(1, ttlHours) * 3_600_000);
}

export function isRecoveryTokenUsable(stored: { expiresAt: Date; usedAt: Date | null }, now: Date): boolean {
  return stored.usedAt === null && stored.expiresAt.getTime() > now.getTime();
}

/** Recovery hints never expose the full username. */
export function maskUsername(username: string): string {
  if (username.length <= 3) return `${username[0] ?? ''}***`;
  return `${username.slice(0, 2)}${'*'.repeat(Math.max(1, username.length - 3))}${username.slice(-1)}`;
}
