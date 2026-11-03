import { and, desc, eq, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import { systemConfigs } from '../../database/drizzle-schema.js';
import { AUDIT_ACTIONS, auditService } from './audit.service.js';

/** Runtime rule families covered by UC-P0-19 (FUN-14-03-001..006). */
export const CONFIG_KEYS = [
  'GACHA_RULES',
  'GACHA_PITY',
  'DEATH_RULES',
  'DUNGEON_RULES',
  'SEED_ALGORITHM',
  'BATTLE_RULES',
] as const;

export type ConfigKey = (typeof CONFIG_KEYS)[number];

export const isConfigKey = (value: string): value is ConfigKey =>
  (CONFIG_KEYS as readonly string[]).includes(value);

export class ConfigError extends Error {
  constructor(message: string, readonly statusCode = 400) {
    super(message);
    this.name = 'ConfigError';
  }
}

const MAX_VALUE_BYTES = 16 * 1024;
const OPERATOR_PATTERN = /^[A-Za-z0-9_-]{2,64}$/;

/** Configuration values are opaque JSON objects, but must be storable and bounded. */
export function validateConfigValue(value: unknown): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new ConfigError('configValue must be a JSON object.');
  }
  let encoded: string;
  try {
    encoded = JSON.stringify(value);
  } catch {
    throw new ConfigError('configValue must be JSON-serialisable.');
  }
  if (Buffer.byteLength(encoded, 'utf8') > MAX_VALUE_BYTES) {
    throw new ConfigError(`configValue exceeds ${MAX_VALUE_BYTES} bytes.`);
  }
  return value as Record<string, unknown>;
}

export function validateOperatorId(value: string): string {
  const actor = value.trim();
  if (!OPERATOR_PATTERN.test(actor)) {
    throw new ConfigError('updatedBy must be 2-64 letters, digits, underscore or hyphen.');
  }
  return actor;
}

/** Versions are per config key and start at 1. */
export function nextVersion(existingVersions: readonly number[]): number {
  return existingVersions.length === 0 ? 1 : Math.max(...existingVersions) + 1;
}

export interface CreateConfigInput {
  configKey: string;
  value: unknown;
  updatedBy: string;
  activate?: boolean;
}

interface CachedConfig {
  id: string;
  version: number;
  value: Record<string, unknown>;
  expiresAt: number;
}

export class SystemConfigService {
  private readonly cache = new Map<string, CachedConfig>();
  private readonly ttlMs: number;

  constructor(options: { cacheTtlMs?: number } = {}) {
    this.ttlMs = options.cacheTtlMs ?? Number(process.env.CONFIG_CACHE_TTL_MS ?? 3000);
  }

  /**
   * Store a new version for a rule family. By default it also becomes the
   * active pointer, so the next read (within one cache TTL) serves the new
   * value without a server restart.
   */
  async createVersion(input: CreateConfigInput) {
    if (!isConfigKey(input.configKey)) {
      throw new ConfigError(`Unknown configKey. Expected one of: ${CONFIG_KEYS.join(', ')}.`);
    }
    const configKey = input.configKey;
    const configValue = validateConfigValue(input.value);
    const updatedBy = validateOperatorId(input.updatedBy);
    const activate = input.activate !== false;

    const result = await db.transaction(async (tx) => {
      // Serialise concurrent writers for the same key so versions never collide.
      await tx.execute(sql`select pg_advisory_xact_lock(hashtext(${configKey}))`);
      const versions = await tx.select({ version: systemConfigs.version, isActive: systemConfigs.isActive, id: systemConfigs.id })
        .from(systemConfigs).where(eq(systemConfigs.configKey, configKey));
      const version = nextVersion(versions.map(row => row.version));
      const previousActiveId = versions.find(row => row.isActive)?.id ?? null;

      if (activate) {
        await tx.update(systemConfigs).set({ isActive: false })
          .where(and(eq(systemConfigs.configKey, configKey), eq(systemConfigs.isActive, true)));
      }
      const [inserted] = await tx.insert(systemConfigs).values({
        id: uuidv4(),
        configKey,
        version,
        configValue,
        isActive: activate,
        updatedBy,
      }).returning();
      return { inserted, previousActiveId };
    });

    this.cache.delete(configKey);
    await auditService.record({
      actorId: updatedBy,
      actorType: 'ADMIN',
      action: AUDIT_ACTIONS.CONFIG_VERSION_CREATED,
      entityType: 'CONFIG',
      entityId: result.inserted.id,
      diff: {
        configKey,
        version: result.inserted.version,
        value: configValue,
        activate,
        previousActiveId: result.previousActiveId,
      },
    });
    return result.inserted;
  }

  /** Switch the active pointer to an existing version (rollback / re-publish). */
  async activate(configId: string, updatedBy: string) {
    const actor = validateOperatorId(updatedBy);
    const result = await db.transaction(async (tx) => {
      const [target] = await tx.select().from(systemConfigs).where(eq(systemConfigs.id, configId)).limit(1);
      if (!target) return null;
      await tx.execute(sql`select pg_advisory_xact_lock(hashtext(${target.configKey}))`);
      await tx.update(systemConfigs).set({ isActive: false })
        .where(and(eq(systemConfigs.configKey, target.configKey), eq(systemConfigs.isActive, true)));
      const [activated] = await tx.update(systemConfigs).set({ isActive: true })
        .where(eq(systemConfigs.id, configId)).returning();
      return activated;
    });

    if (!result) return null;
    this.cache.delete(result.configKey);
    await auditService.record({
      actorId: actor,
      actorType: 'ADMIN',
      action: AUDIT_ACTIONS.CONFIG_VERSION_ACTIVATED,
      entityType: 'CONFIG',
      entityId: result.id,
      diff: { configKey: result.configKey, version: result.version },
    });
    return result;
  }

  async list(configKey?: string) {
    if (configKey !== undefined && !isConfigKey(configKey)) {
      throw new ConfigError(`Unknown configKey. Expected one of: ${CONFIG_KEYS.join(', ')}.`);
    }
    return db.select().from(systemConfigs)
      .where(configKey ? eq(systemConfigs.configKey, configKey) : undefined)
      .orderBy(systemConfigs.configKey, desc(systemConfigs.version))
      .limit(200);
  }

  async history(configKey: string) {
    if (!isConfigKey(configKey)) throw new ConfigError('Unknown configKey.');
    return db.select().from(systemConfigs)
      .where(eq(systemConfigs.configKey, configKey))
      .orderBy(desc(systemConfigs.version))
      .limit(100);
  }

  /**
   * Runtime read path: services call this instead of hard-coding a rule, so an
   * activated version takes effect within one cache TTL.
   */
  async getActive(configKey: ConfigKey): Promise<CachedConfig | null> {
    const cached = this.cache.get(configKey);
    if (cached && cached.expiresAt > Date.now()) return cached;

    const [row] = await db.select().from(systemConfigs)
      .where(and(eq(systemConfigs.configKey, configKey), eq(systemConfigs.isActive, true)))
      .orderBy(desc(systemConfigs.version))
      .limit(1);
    if (!row) {
      this.cache.delete(configKey);
      return null;
    }
    const entry: CachedConfig = {
      id: row.id,
      version: row.version,
      value: row.configValue,
      expiresAt: Date.now() + this.ttlMs,
    };
    this.cache.set(configKey, entry);
    return entry;
  }

  clearCache(): void {
    this.cache.clear();
  }
}

export const systemConfigService = new SystemConfigService();
