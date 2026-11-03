import { and, desc, eq } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import { securityAlerts } from '../../database/drizzle-schema.js';

export type SecuritySeverity = 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL';

export interface RateGuardOptions {
  windowMs: number;
  threshold: number;
  blockMs: number;
  alertCooldownMs: number;
}

export const DEFAULT_RATE_GUARD: RateGuardOptions = {
  windowMs: 1000,
  threshold: 100,
  blockMs: 60_000,
  alertCooldownMs: 60_000,
};

export interface RateVerdict {
  count: number;
  exceeded: boolean;
  blocked: boolean;
  blockedUntil: number;
  shouldAlert: boolean;
  severity: SecuritySeverity;
}

interface RateState {
  count: number;
  windowStart: number;
  blockedUntil: number;
  lastAlertAt: number;
}

/**
 * Sliding-window request counter used by the anti-cheat signal
 * (FUN-14-06-004) and abuse detection (FUN-14-06-005).
 *
 * Kept free of I/O so the decision logic is unit-testable; persisting an
 * alert stays in SecurityAlertService.
 */
export class RateGuard {
  private readonly state = new Map<string, RateState>();

  constructor(private readonly options: RateGuardOptions = DEFAULT_RATE_GUARD) {}

  observe(key: string, now = Date.now()): RateVerdict {
    const { windowMs, threshold, blockMs, alertCooldownMs } = this.options;
    let state = this.state.get(key);
    if (!state) {
      state = { count: 0, windowStart: now, blockedUntil: 0, lastAlertAt: 0 };
      this.state.set(key, state);
    }
    if (now - state.windowStart >= windowMs) {
      state.windowStart = now;
      state.count = 0;
    }
    state.count += 1;

    const exceeded = state.count >= threshold;
    let shouldAlert = false;
    let severity: SecuritySeverity = 'HIGH';

    if (exceeded) {
      severity = state.count >= threshold * 2 ? 'CRITICAL' : 'HIGH';
      if (state.lastAlertAt === 0 || now - state.lastAlertAt >= alertCooldownMs) {
        state.lastAlertAt = now;
        shouldAlert = true;
      }
      if (state.blockedUntil < now) state.blockedUntil = now + blockMs;
    }

    return {
      count: state.count,
      exceeded,
      blocked: state.blockedUntil > now,
      blockedUntil: state.blockedUntil,
      shouldAlert,
      severity,
    };
  }

  isBlocked(key: string, now = Date.now()): boolean {
    const state = this.state.get(key);
    return state !== undefined && state.blockedUntil > now;
  }

  reset(key: string): void {
    this.state.delete(key);
  }

  /** Drop idle entries so a long-running process does not leak memory. */
  prune(now = Date.now()): number {
    let removed = 0;
    for (const [key, state] of this.state) {
      const idle = now - state.windowStart > this.options.windowMs * 10;
      if (idle && state.blockedUntil <= now) {
        this.state.delete(key);
        removed += 1;
      }
    }
    return removed;
  }

  size(): number {
    return this.state.size;
  }
}

export interface SecurityAlertInput {
  accountId: string;
  signal: string;
  severity: SecuritySeverity;
  details: Record<string, unknown>;
}

export class SecurityAlertService {
  async raise(input: SecurityAlertInput) {
    const [alert] = await db.insert(securityAlerts).values({
      id: uuidv4(),
      accountId: input.accountId,
      signal: input.signal,
      severity: input.severity,
      status: 'OPEN',
      details: input.details,
    }).returning();
    return alert;
  }

  async list(options: { status?: string; limit?: number } = {}) {
    const limit = Math.min(Math.max(Math.trunc(options.limit ?? 50), 1), 200);
    const status = options.status;
    return db.select().from(securityAlerts)
      .where(status && (status === 'OPEN' || status === 'RESOLVED') ? eq(securityAlerts.status, status) : undefined)
      .orderBy(desc(securityAlerts.createdAt))
      .limit(limit);
  }

  async resolve(alertId: string, resolvedBy: string) {
    const [updated] = await db.update(securityAlerts)
      .set({ status: 'RESOLVED', resolvedAt: new Date(), resolvedBy })
      .where(and(eq(securityAlerts.id, alertId), eq(securityAlerts.status, 'OPEN')))
      .returning();
    return updated;
  }
}

const numeric = (value: string | undefined, fallback: number): number => {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
};

export const rateGuard = new RateGuard({
  windowMs: numeric(process.env.SECURITY_RATE_WINDOW_MS, DEFAULT_RATE_GUARD.windowMs),
  threshold: numeric(process.env.SECURITY_RATE_LIMIT, DEFAULT_RATE_GUARD.threshold),
  blockMs: numeric(process.env.SECURITY_BLOCK_MS, DEFAULT_RATE_GUARD.blockMs),
  alertCooldownMs: numeric(process.env.SECURITY_ALERT_COOLDOWN_MS, DEFAULT_RATE_GUARD.alertCooldownMs),
});

export const securityAlertService = new SecurityAlertService();
