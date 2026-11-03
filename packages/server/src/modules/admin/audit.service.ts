import { and, desc, eq } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import { auditLogs } from '../../database/drizzle-schema.js';

export type AuditActorType = 'PLAYER' | 'MASTER' | 'ADMIN' | 'SYSTEM';

export interface AuditEntry {
  actorId: string;
  actorType: AuditActorType;
  action: string;
  entityType: string;
  entityId: string;
  diff?: Record<string, unknown>;
}

export interface AuditQuery {
  limit?: number;
  action?: string;
  entityType?: string;
  entityId?: string;
  actorId?: string;
}

export const AUDIT_ACTIONS = {
  CONFIG_VERSION_CREATED: 'CONFIG_VERSION_CREATED',
  CONFIG_VERSION_ACTIVATED: 'CONFIG_VERSION_ACTIVATED',
  BANNER_CREATED: 'BANNER_CREATED',
  BANNER_ACTIVATED: 'BANNER_ACTIVATED',
  BANNER_DEACTIVATED: 'BANNER_DEACTIVATED',
  SECURITY_ALERT_RAISED: 'SECURITY_ALERT_RAISED',
  SECURITY_ALERT_RESOLVED: 'SECURITY_ALERT_RESOLVED',
  BASE_EXPANDED: 'BASE_EXPANDED',
  BUILDING_CONSTRUCTED: 'BUILDING_CONSTRUCTED',
  BUILDING_UPGRADED: 'BUILDING_UPGRADED',
  BUILDING_DEMOLISHED: 'BUILDING_DEMOLISHED',
  RESOURCE_COLLECTED: 'RESOURCE_COLLECTED',
} as const;

/**
 * Audit writes must never break the caller's request path, so failures are
 * logged and swallowed instead of being rethrown.
 */
export class AuditService {
  async record(entry: AuditEntry): Promise<void> {
    try {
      await db.insert(auditLogs).values({
        id: uuidv4(),
        actorId: entry.actorId,
        actorType: entry.actorType,
        action: entry.action,
        entityType: entry.entityType,
        entityId: entry.entityId,
        diffPayload: entry.diff ?? {},
      });
    } catch (error) {
      console.error('[audit] failed to persist entry', entry.action, error);
    }
  }

  async list(query: AuditQuery = {}) {
    const limit = Math.min(Math.max(Math.trunc(query.limit ?? 50), 1), 200);
    const filters = [
      query.action ? eq(auditLogs.action, query.action) : undefined,
      query.entityType ? eq(auditLogs.entityType, query.entityType) : undefined,
      query.entityId ? eq(auditLogs.entityId, query.entityId) : undefined,
      query.actorId ? eq(auditLogs.actorId, query.actorId) : undefined,
    ].filter((filter): filter is NonNullable<typeof filter> => filter !== undefined);

    return db.select().from(auditLogs)
      .where(filters.length ? and(...filters) : undefined)
      .orderBy(desc(auditLogs.createdAt))
      .limit(limit);
  }
}

export const auditService = new AuditService();
