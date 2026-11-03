import { count, eq, gte, sql } from 'drizzle-orm';
import { db, pool } from '../../database/db.js';
import { accounts, auditLogs, combatSessions, masters, securityAlerts } from '../../database/drizzle-schema.js';

export interface MonitoringSnapshot {
  status: 'ok' | 'degraded';
  timestamp: string;
  uptimeSeconds: number;
  database: {
    connected: boolean;
    latencyMs: number;
    pool: { total: number; idle: number; waiting: number };
  };
  process: {
    nodeVersion: string;
    rssMb: number;
    heapUsedMb: number;
  };
  counts: {
    accounts: number;
    masters: number;
    activeCombatSessions: number;
    openSecurityAlerts: number;
    auditEntries24h: number;
  };
}

const mb = (bytes: number): number => Math.round((bytes / 1024 / 1024) * 10) / 10;

/**
 * Operational health surface for FUN-14-05-006 (system monitoring).
 * Everything is read-only and safe to poll from an operator dashboard.
 */
export class MonitoringService {
  async snapshot(): Promise<MonitoringSnapshot> {
    const startedAt = process.hrtime.bigint();
    let connected = true;
    let latencyMs = 0;
    try {
      await db.execute(sql`select 1`);
      latencyMs = Number(process.hrtime.bigint() - startedAt) / 1_000_000;
    } catch {
      connected = false;
    }

    const since = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const [accountTotals, masterTotals, combatTotals, alertTotals, auditTotals] = await Promise.all([
      db.select({ total: count() }).from(accounts),
      db.select({ total: count() }).from(masters),
      db.select({ total: count() }).from(combatSessions).where(eq(combatSessions.status, 'ACTIVE')),
      db.select({ total: count() }).from(securityAlerts).where(eq(securityAlerts.status, 'OPEN')),
      db.select({ total: count() }).from(auditLogs).where(gte(auditLogs.createdAt, since)),
    ]);

    const memory = process.memoryUsage();
    return {
      status: connected ? 'ok' : 'degraded',
      timestamp: new Date().toISOString(),
      uptimeSeconds: Math.round(process.uptime()),
      database: {
        connected,
        latencyMs: Math.round(latencyMs * 100) / 100,
        pool: { total: pool.totalCount, idle: pool.idleCount, waiting: pool.waitingCount },
      },
      process: {
        nodeVersion: process.version,
        rssMb: mb(memory.rss),
        heapUsedMb: mb(memory.heapUsed),
      },
      counts: {
        accounts: accountTotals[0]?.total ?? 0,
        masters: masterTotals[0]?.total ?? 0,
        activeCombatSessions: combatTotals[0]?.total ?? 0,
        openSecurityAlerts: alertTotals[0]?.total ?? 0,
        auditEntries24h: auditTotals[0]?.total ?? 0,
      },
    };
  }

  /** Lightweight liveness payload used by `/health`. */
  async ping(): Promise<{ connected: boolean; latencyMs: number }> {
    const startedAt = process.hrtime.bigint();
    try {
      await db.execute(sql`select 1`);
      return { connected: true, latencyMs: Math.round(Number(process.hrtime.bigint() - startedAt) / 1_000_000 * 100) / 100 };
    } catch {
      return { connected: false, latencyMs: 0 };
    }
  }
}

export const monitoringService = new MonitoringService();
