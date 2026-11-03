import 'dotenv/config';
import express, { Request, Response, NextFunction } from 'express';
import cors from 'cors';
import { and, asc, count, desc, eq, gt, inArray, isNull, lte, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { timingSafeEqual } from 'node:crypto';
import { calculateFiveStarRate } from '@infiniti-gacha/shared';
import { db, pool } from './database/db.js';
import { accounts, accountSessions, playerProfiles, banners, masterBannerPity, summonRewardPool, heroes, heroTemplates, heroSkillTemplates, heroSkillInstances, masters, masterParties, combatSessions, worlds, masterSummonInventory, masterItems, weeklyScrollExchanges, summonHistory, equipmentInstances, equipmentTemplates, heroLevelConfigs, heroDevelopmentConfigs, featureUnlockConfigs } from './database/drizzle-schema.js';
import { createAccessToken, hashPassword, readAccessToken, TOKEN_LIFETIME_SECONDS, verifyPassword } from './modules/auth/auth.js';
import { PersistentGachaService, SummonError } from './modules/gacha/persistent-gacha.service.js';
import { WorldSeedGenerator } from './modules/dungeon/world-seed.generator.js';
import { dungeonConfigService } from './modules/dungeon/dungeon-config.service.js';
import { worldSeedService } from './modules/dungeon/world-seed.service.js';
import { dungeonExplorationService } from './modules/dungeon/dungeon-exploration.service.js';
import { inventoryService } from './modules/inventory/inventory.service.js';
import { currencyService } from './modules/economy/currency.service.js';
import { exchangeSilverForNormalScrolls, getWeeklyExchangePeriodKey, ScrollExchangeError } from './modules/economy/scroll-exchange.service.js';
import { CombatSessionError, CombatSessionService } from './modules/combat/combat-session.service.js';
import { TacticalBuffManager } from './modules/combat/tactical-buff.manager.js';
import { EquipmentError, EquipmentService } from './modules/equipment/equipment.service.js';
import { AUDIT_ACTIONS, auditService } from './modules/admin/audit.service.js';
import { CONFIG_KEYS, ConfigError, isConfigKey, systemConfigService } from './modules/admin/system-config.service.js';
import { monitoringService } from './modules/admin/monitoring.service.js';
import { rateGuard, securityAlertService } from './modules/admin/security.service.js';
import { BaseError, buildingService } from './modules/base/building.service.js';
import { SurvivalError, survivalService } from './modules/survival/survival.service.js';
import { MedicalError, medicalService } from './modules/medical/medical.service.js';
import { PersonalityError, personalityService } from './modules/personality/personality.service.js';
import { ShopError, shopService } from './modules/shop/shop.service.js';
import { MailboxError, mailboxService } from './modules/shop/mailbox.service.js';
import { CraftingError, craftingService } from './modules/crafting/crafting.service.js';
import { getBattleRules, getPityRules } from './modules/admin/runtime-rules.js';

type AuthRequest = Request & { accountId?: string; sessionId?: string };

type BannerPoolInput = {
  rewardId: string; rewardName: string; rewardType: string; poolGroup: string;
  heroTemplateCode: string | null; rarity: number | null; weight: number;
};

function bannerPoolIssue(rows: BannerPoolInput[]): string | undefined {
  if (!Array.isArray(rows) || rows.length === 0) return 'Banner pool must contain at least one reward.';
  const rewardKeys = new Set<string>();
  const groups = new Set<string>();
  for (const row of rows) {
    if (!row.rewardId || row.rewardId.length > 50 || !row.rewardName || row.rewardName.length > 100 ||
        !Number.isSafeInteger(row.weight) || row.weight <= 0 || row.weight > 2147483647) return 'Pool reward fields or weight are invalid.';
    const key = `${row.poolGroup}:${row.rewardId}`;
    if (rewardKeys.has(key)) return 'Duplicate rewardId in the same pool group.';
    rewardKeys.add(key); groups.add(row.poolGroup);
    if (row.poolGroup === 'FIVE_STAR_HERO') {
      if (row.rewardType !== 'HERO' || row.rarity !== 5 || !row.heroTemplateCode) return 'FIVE_STAR_HERO rows must reference a 5-star Hero template.';
    } else if (row.poolGroup === 'OTHER_HERO') {
      if (row.rewardType !== 'HERO' || row.rarity === null || row.rarity < 1 || row.rarity > 4 || !row.heroTemplateCode) return 'OTHER_HERO rows must reference a 1–4 star Hero template.';
    } else if (row.poolGroup === 'MATERIAL') {
      if (row.rewardType !== 'MATERIAL' || row.rarity !== null || row.heroTemplateCode !== null) return 'MATERIAL rows cannot reference Hero templates or rarity.';
    } else return 'Unknown banner pool group.';
  }
  if (!['FIVE_STAR_HERO', 'OTHER_HERO', 'MATERIAL'].every(group => groups.has(group))) return 'Pool requires 5-star Hero, 1–4 star Hero, and Material groups.';
  return undefined;
}

const asyncRoute = (handler: (req: AuthRequest, res: Response, next: NextFunction) => unknown) =>
  (req: Request, res: Response, next: NextFunction) => Promise.resolve(handler(req as AuthRequest, res, next)).catch(next);

export function createApp() {
  const app = express();
  app.use(cors({ origin: process.env.CLIENT_ORIGIN ?? 'http://localhost:5173' }));
  app.use(express.json());

  const gachaService = new PersistentGachaService();
  const combatService = new CombatSessionService();
  const equipmentService = new EquipmentService();

  app.get('/health', asyncRoute(async (_req, res) => {
    try {
      await pool.query('select 1');
      return res.json({ status: 'ok', database: 'connected', service: 'Infinite Gacha Game Server', timestamp: new Date().toISOString() });
    } catch {
      return res.status(503).json({ status: 'degraded', database: 'disconnected', service: 'Infinite Gacha Game Server' });
    }
  }));

  app.post('/api/auth/register', asyncRoute(async (req, res) => {
    try {
      const username = typeof req.body.username === 'string' ? req.body.username.trim().toLowerCase() : '';
      const password = typeof req.body.password === 'string' ? req.body.password : '';
      const email = typeof req.body.email === 'string' && req.body.email.trim() ? req.body.email.trim().toLowerCase() : null;
      if (!/^[a-z0-9]{3,32}$/.test(username) || password.length < 8) {
        return res.status(400).json({ error: 'ERR_AUTH_INVALID_REGISTRATION' });
      }
      const accountId = uuidv4();
      const sessionId = uuidv4();
      const passwordHash = await hashPassword(password);
      await db.transaction(async tx => {
        await tx.insert(accounts).values({ id: accountId, username, email, passwordHash });
        await tx.insert(playerProfiles).values({ accountId, displayName: username.slice(0, 32) });
        await tx.insert(accountSessions).values({ id: sessionId, accountId, expiresAt: new Date(Date.now() + TOKEN_LIFETIME_SECONDS * 1000) });
      });
      return res.status(201).json({ accountId, username, accessToken: createAccessToken(accountId, sessionId) });
    } catch (error) {
      if ((error as { code?: string; constraint?: string }).code === '23505') {
        const constraint = (error as { constraint?: string }).constraint ?? '';
        return res.status(409).json({ error: constraint.toLowerCase().includes('username') ? 'ERR_AUTH_USERNAME_EXISTS' : 'ERR_AUTH_EMAIL_EXISTS' });
      }
      return res.status(500).json({ error: 'Không thể tạo tài khoản.' });
    }
  }));

  app.post('/api/auth/login', asyncRoute(async (req, res) => {
    const username = typeof req.body.username === 'string' ? req.body.username.trim().toLowerCase() : '';
    const password = typeof req.body.password === 'string' ? req.body.password : '';
    const [account] = await db.select().from(accounts).where(eq(sql`lower(${accounts.username})`, username)).limit(1);
    if (!account || !(await verifyPassword(password, account.passwordHash))) return res.status(401).json({ error: 'Tên tài khoản hoặc mật khẩu không đúng.' });
    if (account.status !== 'ACTIVE') return res.status(403).json({ error: 'ERR_AUTH_ACCOUNT_RESTRICTED' });
    if (account.passwordHash.startsWith('scrypt$')) {
      await db.update(accounts).set({ passwordHash: await hashPassword(password), updatedAt: new Date() }).where(eq(accounts.id, account.id));
    }
    const sessionId = uuidv4();
    await db.insert(accountSessions).values({ id: sessionId, accountId: account.id, expiresAt: new Date(Date.now() + TOKEN_LIFETIME_SECONDS * 1000) });
    return res.json({ accountId: account.id, username: account.username, accessToken: createAccessToken(account.id, sessionId) });
  }));

  const requireAccount = asyncRoute(async (req, res, next) => {
    const authorization = req.header('authorization') ?? '';
    const token = authorization.startsWith('Bearer ') ? authorization.slice(7) : '';
    const payload = token ? readAccessToken(token) : undefined;
    if (!payload) return res.status(401).json({ error: 'Phiên đăng nhập không hợp lệ hoặc đã hết hạn.' });
    const now = new Date();
    const [liveSession] = await db.select().from(accountSessions).where(and(
      eq(accountSessions.id, payload.sessionId), eq(accountSessions.accountId, payload.accountId),
      isNull(accountSessions.revokedAt), gt(accountSessions.expiresAt, now),
    )).limit(1);
    if (!liveSession) return res.status(401).json({ error: 'ERR_AUTH_SESSION_REVOKED_OR_EXPIRED' });
    const [account] = await db.select({ status: accounts.status }).from(accounts).where(eq(accounts.id, payload.accountId)).limit(1);
    if (!account || account.status !== 'ACTIVE') return res.status(403).json({ error: 'ERR_AUTH_ACCOUNT_RESTRICTED' });

    const verdict = rateGuard.observe(payload.accountId);
    if (verdict.shouldAlert) {
      void securityAlertService.raise({
        accountId: payload.accountId,
        signal: 'RAPID_REQUEST_RATE',
        severity: verdict.severity,
        details: { count: verdict.count, windowMs: Number(process.env.SECURITY_RATE_WINDOW_MS ?? 1000), path: req.path, method: req.method },
      }).then(alert => auditService.record({
        actorId: payload.accountId,
        actorType: 'SYSTEM',
        action: AUDIT_ACTIONS.SECURITY_ALERT_RAISED,
        entityType: 'SECURITY_ALERT',
        entityId: alert.id,
        diff: { signal: alert.signal, severity: alert.severity, count: verdict.count },
      })).catch(error => console.error('[security] alert persistence failed', error));
    }
    if (verdict.blocked) {
      return res.status(429).json({ error: 'ERR_SECURITY_RATE_LIMIT', retryAfterMs: verdict.blockedUntil - Date.now() });
    }

    req.accountId = payload.accountId;
    req.sessionId = payload.sessionId;
    return next();
  });

  app.get('/api/auth/security', requireAccount, asyncRoute(async (req, res) => {
    const [account] = await db.select({ status: accounts.status }).from(accounts).where(eq(accounts.id, req.accountId!)).limit(1);
    const [session] = await db.select({ createdAt: accountSessions.createdAt, expiresAt: accountSessions.expiresAt })
      .from(accountSessions).where(eq(accountSessions.id, req.sessionId!)).limit(1);
    return res.json({ accountStatus: account?.status ?? 'UNKNOWN', session: session ?? null });
  }));

  app.post('/api/auth/logout', requireAccount, asyncRoute(async (req, res) => {
    await db.update(accountSessions).set({ revokedAt: new Date() }).where(and(
      eq(accountSessions.id, req.sessionId!), eq(accountSessions.accountId, req.accountId!), isNull(accountSessions.revokedAt),
    ));
    return res.json({ loggedOut: true });
  }));

  const requireFeature = (featureCode: string) => asyncRoute(async (req, res, next) => {
    const [master] = await db.select({ level: masters.level }).from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    const [feature] = await db.select().from(featureUnlockConfigs)
      .where(and(eq(featureUnlockConfigs.featureCode, featureCode), eq(featureUnlockConfigs.isActive, true))).limit(1);
    if (!feature || master.level < feature.requiredMasterLevel) {
      return res.status(403).json({ error: `Feature ${featureCode} unlocks at Master level ${feature?.requiredMasterLevel ?? 'TBD'}.` });
    }
    return next();
  });

  const requireAdminApiKey = (req: Request, res: Response, next: NextFunction) => {
    const configuredKey = process.env.ADMIN_API_KEY ?? '';
    if (!configuredKey) return res.status(503).json({ error: 'ADMIN_API_KEY_NOT_CONFIGURED' });
    const suppliedKey = req.header('x-admin-api-key') ?? '';
    const expected = Buffer.from(configuredKey);
    const supplied = Buffer.from(suppliedKey);
    if (expected.length !== supplied.length || !timingSafeEqual(expected, supplied)) {
      return res.status(403).json({ error: 'ERR_ADMIN_AUTH_REQUIRED' });
    }
    return next();
  };

  /** Actor code recorded in the audit trail for operator-initiated changes. */
  const adminActor = (req: Request): string => {
    const supplied = req.header('x-operator-id') ?? process.env.ADMIN_OPERATOR_ID ?? 'ACT-04';
    return /^[A-Za-z0-9_-]{2,64}$/.test(supplied) ? supplied : 'ACT-04';
  };

  app.get('/api/me', requireAccount, asyncRoute(async (req, res) => {
    const [account] = await db.select({ id: accounts.id, username: accounts.username }).from(accounts).where(eq(accounts.id, req.accountId!)).limit(1);
    if (!account) return res.status(401).json({ error: 'Tài khoản không tồn tại.' });
    const [master] = await db.select().from(masters).where(eq(masters.accountId, account.id)).limit(1);
    const [world] = master ? await db.select().from(worlds).where(eq(worlds.masterId, master.id)).limit(1) : [];
    const inventory = master ? await db.select().from(masterSummonInventory).where(eq(masterSummonInventory.masterId, master.id)) : [];
    const itemInventory = master ? await db.select({ itemId: masterItems.itemId, quantity: masterItems.quantity }).from(masterItems).where(eq(masterItems.masterId, master.id)) : [];
    const heroDevelopment = await db.select().from(heroDevelopmentConfigs);
    const periodKey = getWeeklyExchangePeriodKey();
    const [weeklyExchange] = master ? await db.select().from(weeklyScrollExchanges)
      .where(and(eq(weeklyScrollExchanges.masterId, master.id), eq(weeklyScrollExchanges.periodKey, periodKey))).limit(1) : [];
    return res.json({
      account,
      master: master ? { ...master, exp: master.exp.toString(), silverCoins: master.silverCoins.toString(), gems: master.gems.toString(), gemDebt: master.gemDebt.toString() } : null,
      world: world ?? null,
      summonInventory: inventory.map(item => ({ scrollType: item.scrollType, quantity: item.quantity })),
      itemInventory,
      heroDevelopmentConfigs: heroDevelopment,
      weeklyScrollExchange: { periodKey, quantity: weeklyExchange?.quantity ?? 0, limit: 50 },
    });
  }));

  app.get('/api/profile', requireAccount, asyncRoute(async (req, res) => {
    const [profile] = await db.select().from(playerProfiles).where(eq(playerProfiles.accountId, req.accountId!)).limit(1);
    if (!profile) return res.status(404).json({ error: 'Player profile not found.' });
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    const [world] = master ? await db.select().from(worlds).where(eq(worlds.masterId, master.id)).limit(1) : [];
    const [heroCount] = master ? await db.select({ total: count() }).from(heroes).where(eq(heroes.masterId, master.id)) : [{ total: 0 }];
    const [activeHeroCount] = master ? await db.select({ total: count() }).from(heroes).where(and(eq(heroes.masterId, master.id), eq(heroes.state, 'ALIVE'))) : [{ total: 0 }];
    const [summonCount] = master ? await db.select({ total: count() }).from(summonHistory).where(eq(summonHistory.masterId, master.id)) : [{ total: 0 }];
    return res.json({
      display_name: profile.displayName,
      avatar_url: profile.avatarUrl,
      settings: profile.settings,
      progress_summary: {
        master_level: master?.level ?? 0,
        world_floor: world?.currentFloor ?? 0,
        heroes_owned: heroCount.total,
        active_heroes: activeHeroCount.total,
        summons_made: summonCount.total,
      },
    });
  }));

  app.patch('/api/profile', requireAccount, asyncRoute(async (req, res) => {
    const [profile] = await db.select().from(playerProfiles).where(eq(playerProfiles.accountId, req.accountId!)).limit(1);
    if (!profile) return res.status(404).json({ error: 'Player profile not found.' });
    const updates: Partial<typeof playerProfiles.$inferInsert> = { updatedAt: new Date() };
    if (Object.hasOwn(req.body ?? {}, 'display_name')) {
      const displayName = typeof req.body.display_name === 'string' ? req.body.display_name.trim() : '';
      const deniedTerms = (process.env.PROFILE_PROFANITY_TERMS ?? '').split(',').map(term => term.trim().toLocaleLowerCase()).filter(Boolean);
      const normalizedName = displayName.toLocaleLowerCase();
      if (displayName.length < 1 || displayName.length > 32 || !/^[\p{L}\p{N} _-]+$/u.test(displayName) || deniedTerms.some(term => normalizedName.includes(term))) {
        return res.status(400).json({ error: 'ERR_PROFILE_INVALID_NAME' });
      }
      updates.displayName = displayName;
    }
    if (Object.hasOwn(req.body ?? {}, 'avatar_url')) {
      const avatarUrl = req.body.avatar_url;
      if (avatarUrl !== null) {
        if (typeof avatarUrl !== 'string' || avatarUrl.length > 255) return res.status(400).json({ error: 'ERR_PROFILE_INVALID_AVATAR_URL' });
        try {
          const parsed = new URL(avatarUrl);
          if (!['http:', 'https:'].includes(parsed.protocol)) return res.status(400).json({ error: 'ERR_PROFILE_INVALID_AVATAR_URL' });
        } catch { return res.status(400).json({ error: 'ERR_PROFILE_INVALID_AVATAR_URL' }); }
      }
      updates.avatarUrl = avatarUrl;
    }
    if (Object.hasOwn(req.body ?? {}, 'settings')) {
      const patch = req.body.settings;
      if (!patch || typeof patch !== 'object' || Array.isArray(patch)) return res.status(400).json({ error: 'ERR_PROFILE_INVALID_SETTINGS' });
      const allowed = new Set(['language', 'soundEnabled', 'notificationsEnabled']);
      if (Object.keys(patch).some(key => !allowed.has(key)) ||
          (patch.language !== undefined && (typeof patch.language !== 'string' || !/^[a-z]{2}(?:-[A-Z]{2})?$/.test(patch.language))) ||
          (patch.soundEnabled !== undefined && typeof patch.soundEnabled !== 'boolean') ||
          (patch.notificationsEnabled !== undefined && typeof patch.notificationsEnabled !== 'boolean')) {
        return res.status(400).json({ error: 'ERR_PROFILE_INVALID_SETTINGS' });
      }
      updates.settings = { ...profile.settings, ...patch };
    }
    if (Object.keys(req.body ?? {}).length === 0 || Object.keys(req.body).some(key => !['display_name', 'avatar_url', 'settings'].includes(key))) {
      return res.status(400).json({ error: 'No profile fields provided or unsupported profile field.' });
    }
    const [updated] = await db.update(playerProfiles).set(updates).where(eq(playerProfiles.accountId, req.accountId!)).returning();
    return res.json({ display_name: updated.displayName, avatar_url: updated.avatarUrl, settings: updated.settings });
  }));

  app.get('/api/master/features', requireAccount, asyncRoute(async (req, res) => {
    const [master] = await db.select({ level: masters.level }).from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    const configs = await db.select().from(featureUnlockConfigs).where(eq(featureUnlockConfigs.isActive, true));
    return res.json(configs.map(feature => ({ ...feature, unlocked: master.level >= feature.requiredMasterLevel })));
  }));

  app.get('/api/master/skills', requireAccount, requireFeature('MASTER_SKILLS'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    return res.json(await combatService.getMasterSkills(master.id));
  }));

  app.post('/api/master/init', requireAccount, asyncRoute(async (req, res) => {
    const masterName = typeof req.body.masterName === 'string' ? req.body.masterName.trim() : '';
    if (masterName.length < 1 || masterName.length > 50) return res.status(400).json({ error: 'Tên Master cần từ 1–50 ký tự.' });
    const id = uuidv4();
    try {
      const master = await db.transaction(async tx => {
        const [created] = await tx.insert(masters).values({ id, accountId: req.accountId!, masterName }).returning();
        await tx.insert(masterParties).values({ id: uuidv4(), masterId: created.id, name: 'Party 1', isDefault: true });
        const initialWorld = WorldSeedGenerator.createWorld(created.id);
        await tx.insert(worlds).values({
          id: initialWorld.worldId,
          masterId: initialWorld.masterId,
          worldSeed: initialWorld.worldSeed,
          seedAlgorithmVersion: initialWorld.seedAlgorithmVersion,
          difficultyMultiplier: initialWorld.difficultyMultiplier,
          currentFloor: initialWorld.currentFloor,
        });
        // P1 starter kit: a small food reserve so the first dungeon run is possible.
        await tx.insert(masterItems).values({ id: uuidv4(), masterId: created.id, itemId: 'FOOD', quantity: 100, updatedAt: new Date() });
        const sampleTemplates = await tx.select({ code: equipmentTemplates.code }).from(equipmentTemplates)
          .where(inArray(equipmentTemplates.code, ['SAMPLE_IRON_SWORD', 'SAMPLE_LEATHER_CHEST', 'SAMPLE_SWIFT_CHARM']));
        if (sampleTemplates.length) await tx.insert(equipmentInstances).values(sampleTemplates.map(template => ({
          id: uuidv4(), masterId: created.id, templateCode: template.code, location: 'INVENTORY',
        })));
        return created;
      });
      return res.status(201).json({ ...master, exp: master.exp.toString(), silverCoins: master.silverCoins.toString(), gems: master.gems.toString(), gemDebt: master.gemDebt.toString() });
    } catch (error) {
      if ((error as { code?: string }).code === '23505') return res.status(409).json({ error: 'Tài khoản này đã có Master.' });
      throw error;
    }
  }));

  app.post('/api/world/create', requireAccount, requireFeature('WORLD_CREATION'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    const world = WorldSeedGenerator.createWorld(master.id);
    const [created] = await db.insert(worlds).values({
      id: world.worldId,
      masterId: world.masterId,
      worldSeed: world.worldSeed,
      seedAlgorithmVersion: world.seedAlgorithmVersion,
      difficultyMultiplier: world.difficultyMultiplier,
      currentFloor: world.currentFloor,
    }).returning();
    return res.status(201).json(created);
  }));

  app.get('/api/world', requireAccount, asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    const [world] = await db.select().from(worlds).where(eq(worlds.masterId, master.id)).limit(1);
    if (!world) return res.status(404).json({ error: 'World chưa được khởi tạo.' });
    return res.json(world);
  }));

  app.get('/api/dungeon/templates', requireAccount, asyncRoute(async (_req, res) => {
    const templates = await dungeonConfigService.listTemplates();
    return res.json(templates);
  }));

  app.get('/api/dungeon/templates/:templateId', requireAccount, asyncRoute(async (req, res) => {
    try {
      const templateId = Array.isArray(req.params.templateId) ? req.params.templateId[0] : req.params.templateId;
      const template = await dungeonConfigService.getTemplateWithFloors(templateId);
      return res.json(template);
    } catch (e) {
      return res.status((e as { statusCode?: number }).statusCode ?? 400).json({ error: (e as Error).message });
    }
  }));

  app.get('/api/dungeon/world-seed/reconstruct/:floorNumber', requireAccount, asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      const world = await worldSeedService.getMasterWorld(master.id);
      const floorParam = Array.isArray(req.params.floorNumber) ? req.params.floorNumber[0] : req.params.floorNumber;
      const floorNumber = Math.max(1, parseInt(floorParam, 10) || 1);
      const reconstruction = worldSeedService.reconstructFloor(
        world.worldSeed,
        floorNumber,
        world.difficultyMultiplier,
        world.seedAlgorithmVersion ?? 1
      );
      return res.json(reconstruction);
    } catch (e) {
      return res.status((e as { statusCode?: number }).statusCode ?? 400).json({ error: (e as Error).message });
    }
  }));

  app.get('/api/dungeon/floors', requireAccount, asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      const templateCode = (req.query.template as string) || 'QUIET_FOREST';
      const result = await dungeonExplorationService.getFloorList(master.id, templateCode);
      return res.json(result);
    } catch (e) {
      return res.status((e as { statusCode?: number }).statusCode ?? 400).json({ error: (e as Error).message });
    }
  }));

  app.get('/api/dungeon/instance/active', requireAccount, asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    const active = await dungeonExplorationService.getActiveInstance(master.id);
    return res.json(active);
  }));

  app.post('/api/dungeon/floor/:floorNumber/enter', requireAccount, asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      const floorParam = Array.isArray(req.params.floorNumber) ? req.params.floorNumber[0] : req.params.floorNumber;
      const floorNumber = Math.max(1, parseInt(floorParam, 10) || 1);
      const templateCode = (req.body?.template as string) || 'QUIET_FOREST';
      const instance = await dungeonExplorationService.enterFloor(master.id, templateCode, floorNumber);
      return res.status(201).json(instance);
    } catch (e) {
      return res.status((e as { statusCode?: number }).statusCode ?? 400).json({ error: (e as Error).message });
    }
  }));

  app.post('/api/dungeon/instance/:instanceId/explore', requireAccount, asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      const instanceId = Array.isArray(req.params.instanceId) ? req.params.instanceId[0] : req.params.instanceId;
      const result = await dungeonExplorationService.exploreRoom(master.id, instanceId);
      return res.json(result);
    } catch (e) {
      return res.status((e as { statusCode?: number }).statusCode ?? 400).json({ error: (e as Error).message });
    }
  }));

  app.post('/api/dungeon/instance/:instanceId/retreat', requireAccount, asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      const instanceId = Array.isArray(req.params.instanceId) ? req.params.instanceId[0] : req.params.instanceId;
      const result = await dungeonExplorationService.handleFailure(master.id, instanceId);
      return res.json(result);
    } catch (e) {
      return res.status((e as { statusCode?: number }).statusCode ?? 400).json({ error: (e as Error).message });
    }
  }));

  app.post('/api/economy/exchange-scrolls', requireAccount, requireFeature('SUMMON'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      const result = await exchangeSilverForNormalScrolls(master.id, req.body.amount);
      return res.json(result);
    } catch (error) {
      if (error instanceof ScrollExchangeError) return res.status(error.statusCode).json({ error: error.message });
      throw error;
    }
  }));

  app.get('/api/inventory', requireAccount, asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    const category = typeof req.query.category === 'string' ? req.query.category : undefined;
    const sort = req.query.sort as 'QUANTITY_DESC' | 'RARITY_DESC' | 'NAME_ASC' | undefined;
    const inventory = await inventoryService.listInventory(master.id, { category, sort });
    return res.json(inventory);
  }));

  app.post('/api/inventory/items/:itemId/use', requireAccount, asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    const itemId = Array.isArray(req.params.itemId) ? req.params.itemId[0] : req.params.itemId;
    const quantity = Math.max(1, parseInt(req.body?.quantity, 10) || 1);
    try {
      const result = await inventoryService.useItem(master.id, itemId, quantity, req.body?.targetHeroId);
      return res.json(result);
    } catch (e) {
      return res.status((e as { statusCode?: number }).statusCode ?? 400).json({ error: (e as Error).message });
    }
  }));

  app.post('/api/inventory/items/:itemId/sell', requireAccount, asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    const itemId = Array.isArray(req.params.itemId) ? req.params.itemId[0] : req.params.itemId;
    const quantity = Math.max(1, parseInt(req.body?.quantity, 10) || 1);
    try {
      const result = await inventoryService.sellItem(master.id, itemId, quantity);
      return res.json(result);
    } catch (e) {
      return res.status((e as { statusCode?: number }).statusCode ?? 400).json({ error: (e as Error).message });
    }
  }));

  app.get('/api/economy/balances', requireAccount, asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    const balances = await currencyService.getBalances(master.id);
    return res.json(balances);
  }));

  app.get('/api/economy/transactions', requireAccount, asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit as string, 10) || 50));
    const list = await currencyService.listTransactions(master.id, limit);
    return res.json(list);
  }));

  app.get('/api/gacha/banners', requireAccount, requireFeature('SUMMON'), asyncRoute(async (_req, res) => {
    const now = new Date();
    const activeBanners = await db.select().from(banners).where(eq(banners.isActive, true));
    return res.json(activeBanners.filter(banner => banner.startDate <= now && (!banner.endDate || banner.endDate > now)));
  }));

  app.get('/api/gacha/banners/:bannerId', requireAccount, requireFeature('SUMMON'), asyncRoute(async (req, res) => {
    const now = new Date();
    const [banner] = await db.select().from(banners).where(and(eq(banners.id, String(req.params.bannerId)), eq(banners.isActive, true))).limit(1);
    if (!banner || banner.startDate > now || (banner.endDate && banner.endDate <= now)) return res.status(404).json({ error: 'Active banner not found.' });
    const [master] = await db.select({ id: masters.id }).from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    const [pity] = master ? await db.select().from(masterBannerPity).where(and(
      eq(masterBannerPity.masterId, master.id), eq(masterBannerPity.bannerId, banner.id),
    )).limit(1) : [];
    const pool = await db.select({
      rewardId: summonRewardPool.rewardId, rewardName: summonRewardPool.rewardName,
      rewardType: summonRewardPool.rewardType, poolGroup: summonRewardPool.poolGroup,
      heroTemplateCode: summonRewardPool.heroTemplateCode, rarity: summonRewardPool.rarity,
    }).from(summonRewardPool).where(and(eq(summonRewardPool.bannerId, banner.id), eq(summonRewardPool.isActive, true)));
    const pityCount = pity?.pityCounter ?? 0;
    const pityRules = await getPityRules();
    const fiveStarChance = calculateFiveStarRate(pityCount + 1, pityRules);
    const remainder = 1 - fiveStarChance;
    return res.json({
      banner, pool,
      rates: {
        fiveStarHeroPercent: fiveStarChance * 100,
        otherHeroPercent: remainder * (49.6 / 99.6) * 100,
        materialPercent: remainder * (50 / 99.6) * 100,
        fiveStarBasePercent: pityRules.baseRate * 100,
      },
      pity: { currentCount: pityCount, nextRoll: pityCount + 1, hardPityAt: pityRules.guaranteeRoll },
    });
  }));

  app.get('/api/admin/banners', requireAdminApiKey, asyncRoute(async (_req, res) => {
    const rows = await db.select().from(banners).orderBy(desc(banners.createdAt));
    return res.json(rows);
  }));

  app.post('/api/admin/banners', requireAdminApiKey, asyncRoute(async (req, res) => {
    const name = typeof req.body?.name === 'string' ? req.body.name.trim() : '';
    const bannerType = req.body?.bannerType;
    if (!name || name.length > 100 || !['NORMAL', 'LIMITED', 'SPECIAL'].includes(bannerType)) {
      return res.status(400).json({ error: 'ERR_BANNER_INVALID_CONFIGURATION' });
    }
    const [created] = await db.insert(banners).values({ id: uuidv4(), name, bannerType, isActive: false, startDate: new Date() }).returning();
    void auditService.record({
      actorId: adminActor(req), actorType: 'ADMIN', action: AUDIT_ACTIONS.BANNER_CREATED,
      entityType: 'BANNER', entityId: created.id, diff: { name, bannerType },
    });
    return res.status(201).json(created);
  }));

  app.patch('/api/admin/banners/:bannerId', requireAdminApiKey, asyncRoute(async (req, res) => {
    const name = typeof req.body?.name === 'string' ? req.body.name.trim() : undefined;
    const bannerType = req.body?.bannerType;
    if ((name !== undefined && (!name || name.length > 100)) ||
        (bannerType !== undefined && !['NORMAL', 'LIMITED', 'SPECIAL'].includes(bannerType))) {
      return res.status(400).json({ error: 'ERR_BANNER_INVALID_CONFIGURATION' });
    }
    if (name === undefined && bannerType === undefined) return res.status(400).json({ error: 'No banner fields provided.' });
    const [current] = await db.select().from(banners).where(eq(banners.id, String(req.params.bannerId))).limit(1);
    if (!current) return res.status(404).json({ error: 'Banner not found.' });
    if (current.isActive) return res.status(409).json({ error: 'Deactivate the banner before editing it.' });
    const [updated] = await db.update(banners).set({ ...(name !== undefined ? { name } : {}), ...(bannerType !== undefined ? { bannerType } : {}) })
      .where(eq(banners.id, String(req.params.bannerId))).returning();
    if (!updated) return res.status(404).json({ error: 'Banner not found.' });
    return res.json(updated);
  }));

  app.put('/api/admin/banners/:bannerId/schedule', requireAdminApiKey, asyncRoute(async (req, res) => {
    const startDate = typeof req.body?.startDate === 'string' ? new Date(req.body.startDate) : new Date('invalid');
    const endDate = typeof req.body?.endDate === 'string' ? new Date(req.body.endDate) : new Date('invalid');
    if (!Number.isFinite(startDate.getTime()) || !Number.isFinite(endDate.getTime()) || endDate <= startDate) {
      return res.status(400).json({ error: 'ERR_BANNER_INVALID_SCHEDULE' });
    }
    const [current] = await db.select().from(banners).where(eq(banners.id, String(req.params.bannerId))).limit(1);
    if (!current) return res.status(404).json({ error: 'Banner not found.' });
    if (current.isActive) return res.status(409).json({ error: 'Deactivate the banner before changing its schedule.' });
    const [updated] = await db.update(banners).set({ startDate, endDate }).where(eq(banners.id, String(req.params.bannerId))).returning();
    if (!updated) return res.status(404).json({ error: 'Banner not found.' });
    return res.json(updated);
  }));

  app.put('/api/admin/banners/:bannerId/pool', requireAdminApiKey, asyncRoute(async (req, res) => {
    const bannerId = String(req.params.bannerId);
    const [banner] = await db.select().from(banners).where(eq(banners.id, bannerId)).limit(1);
    if (!banner) return res.status(404).json({ error: 'Banner not found.' });
    if (banner.isActive) return res.status(409).json({ error: 'Deactivate the banner before changing its pool.' });
    const poolInput = req.body?.pool as BannerPoolInput[];
    const issue = bannerPoolIssue(poolInput);
    if (issue) return res.status(400).json({ error: 'ERR_BANNER_INVALID_POOL', detail: issue });
    const heroCodes = [...new Set(poolInput.filter(row => row.heroTemplateCode).map(row => row.heroTemplateCode!))];
    const templates = heroCodes.length ? await db.select({ code: heroTemplates.code, rarity: heroTemplates.defaultRarity })
      .from(heroTemplates).where(inArray(heroTemplates.code, heroCodes)) : [];
    const rarityByCode = new Map(templates.map(template => [template.code, template.rarity]));
    if (poolInput.some(row => row.heroTemplateCode && rarityByCode.get(row.heroTemplateCode) !== row.rarity)) {
      return res.status(400).json({ error: 'ERR_BANNER_HERO_TEMPLATE_RARITY_MISMATCH' });
    }
    const values = poolInput.map(row => ({ ...row, id: uuidv4(), bannerId, isActive: true }));
    await db.transaction(async tx => {
      await tx.delete(summonRewardPool).where(eq(summonRewardPool.bannerId, bannerId));
      await tx.insert(summonRewardPool).values(values);
    });
    return res.json({ bannerId, pool: values });
  }));

  app.post('/api/admin/banners/:bannerId/activate', requireAdminApiKey, asyncRoute(async (req, res) => {
    const bannerId = String(req.params.bannerId);
    const [banner] = await db.select().from(banners).where(eq(banners.id, bannerId)).limit(1);
    if (!banner) return res.status(404).json({ error: 'Banner not found.' });
    if (!banner.endDate || banner.endDate <= banner.startDate) return res.status(409).json({ error: 'Configure a valid start and end schedule first.' });
    const pool = await db.select().from(summonRewardPool).where(and(eq(summonRewardPool.bannerId, bannerId), eq(summonRewardPool.isActive, true)));
    const issue = bannerPoolIssue(pool);
    if (issue) return res.status(409).json({ error: 'ERR_BANNER_POOL_INCOMPLETE', detail: issue });
    const [updated] = await db.update(banners).set({ isActive: true }).where(eq(banners.id, bannerId)).returning();
    void auditService.record({
      actorId: adminActor(req), actorType: 'ADMIN', action: AUDIT_ACTIONS.BANNER_ACTIVATED,
      entityType: 'BANNER', entityId: bannerId, diff: { previous: { isActive: banner.isActive }, next: { isActive: true } },
    });
    return res.json(updated);
  }));

  app.post('/api/admin/banners/:bannerId/deactivate', requireAdminApiKey, asyncRoute(async (req, res) => {
    const bannerId = String(req.params.bannerId);
    const [updated] = await db.update(banners).set({ isActive: false }).where(eq(banners.id, bannerId)).returning();
    if (!updated) return res.status(404).json({ error: 'Banner not found.' });
    void auditService.record({
      actorId: adminActor(req), actorType: 'ADMIN', action: AUDIT_ACTIONS.BANNER_DEACTIVATED,
      entityType: 'BANNER', entityId: bannerId, diff: { previous: { isActive: true }, next: { isActive: false } },
    });
    return res.json(updated);
  }));

  // --- DM-10 (P1): crafting, enhancement and fusion ---

  const craftingError = (res: Response, error: unknown): boolean => {
    if (error instanceof CraftingError) {
      res.status(error.statusCode).json({ error: error.message });
      return true;
    }
    return false;
  };

  app.get('/api/crafting', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    return res.json(await craftingService.overview(master.id));
  }));

  app.post('/api/crafting/craft', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      const result = await craftingService.craft(master.id, String(req.body?.recipeCode ?? ''));
      void auditService.record({
        actorId: master.id, actorType: 'MASTER', action: 'ITEM_CRAFTED', entityType: 'EQUIPMENT',
        entityId: result.instanceId, diff: { recipeCode: String(req.body?.recipeCode ?? ''), templateCode: result.templateCode, silverSpent: result.silverSpent },
      });
      return res.status(201).json(result);
    } catch (error) {
      if (craftingError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/crafting/equipment/:instanceId/enhance', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.json(await craftingService.enhance(master.id, String(req.params.instanceId)));
    } catch (error) {
      if (craftingError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/crafting/fuse', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.json(await craftingService.fuse(master.id, String(req.body?.templateCode ?? ''), req.body?.starLevel));
    } catch (error) {
      if (craftingError(res, error)) return undefined;
      throw error;
    }
  }));

  // --- DM-11 (P1): base shop and mailbox ---

  const shopError = (res: Response, error: unknown): boolean => {
    if (error instanceof ShopError) {
      res.status(error.statusCode).json({ error: error.message });
      return true;
    }
    if (error instanceof MailboxError) {
      res.status(error.statusCode).json({ error: error.message });
      return true;
    }
    return false;
  };

  app.get('/api/shop', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    return res.json(await shopService.catalog(master.id));
  }));

  app.get('/api/shop/items/:code', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.json(await shopService.detail(master.id, String(req.params.code)));
    } catch (error) {
      if (shopError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/shop/purchase', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      const result = await shopService.purchase(master.id, String(req.body?.itemCode ?? ''), req.body?.quantity);
      void auditService.record({
        actorId: master.id, actorType: 'MASTER', action: 'SHOP_PURCHASE', entityType: 'SHOP_ITEM',
        entityId: String(req.body?.itemCode ?? ''), diff: { purchased: result.purchased, silverSpent: result.silverSpent },
      });
      return res.json(result);
    } catch (error) {
      if (shopError(res, error)) return undefined;
      throw error;
    }
  }));

  app.get('/api/mailbox', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    return res.json(await mailboxService.list(master.id));
  }));

  app.post('/api/mailbox/:messageId/claim', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.json(await mailboxService.claim(master.id, String(req.params.messageId)));
    } catch (error) {
      if (shopError(res, error)) return undefined;
      throw error;
    }
  }));

  app.get('/api/admin/shop', requireAdminApiKey, asyncRoute(async (_req, res) => {
    return res.json(await shopService.listAll());
  }));

  app.post('/api/admin/shop/items', requireAdminApiKey, asyncRoute(async (req, res) => {
    try {
      return res.status(201).json(await shopService.upsertItem(req.body as never));
    } catch (error) {
      if (shopError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/admin/mailbox/send', requireAdminApiKey, asyncRoute(async (req, res) => {
    const username = typeof req.body?.username === 'string' ? req.body.username.trim() : '';
    const requestedMasterId = typeof req.body?.masterId === 'string' ? req.body.masterId : '';
    let masterId = requestedMasterId;
    if (!masterId && username) {
      const [found] = await db.select({ id: masters.id }).from(masters)
        .innerJoin(accounts, eq(accounts.id, masters.accountId))
        .where(eq(accounts.username, username)).limit(1);
      masterId = found?.id ?? '';
    }
    if (!masterId) return res.status(404).json({ error: 'Không xác định được Master nhận thư.' });
    try {
      const sent = await mailboxService.send({
        masterId,
        sender: typeof req.body?.sender === 'string' ? req.body.sender : 'OPERATOR',
        subject: String(req.body?.subject ?? ''),
        body: String(req.body?.body ?? ''),
        attachments: req.body?.attachments,
        lifetimeDays: Number(req.body?.lifetimeDays) || undefined,
      });
      void auditService.record({
        actorId: adminActor(req), actorType: 'ADMIN', action: 'MAIL_SENT', entityType: 'MAIL',
        entityId: sent.id, diff: { masterId, subject: sent.subject, attachments: sent.attachments },
      });
      return res.status(201).json(sent);
    } catch (error) {
      if (shopError(res, error)) return undefined;
      throw error;
    }
  }));

  // --- DM-03 (P1): personality, loyalty and relationships ---

  const personalityError = (res: Response, error: unknown): boolean => {
    if (error instanceof PersonalityError) {
      res.status(error.statusCode).json({ error: error.message });
      return true;
    }
    return false;
  };

  app.get('/api/personality', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    const overview = await personalityService.overview(master.id);
    return res.json({ ...overview, summary: await personalityService.summary(master.id) });
  }));

  app.post('/api/personality/heroes/:heroId/favorite-meal', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.json(await personalityService.serveFavoriteMeal(master.id, String(req.params.heroId)));
    } catch (error) {
      if (personalityError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/personality/heroes/:heroId/loyalty', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    const delta = Number(req.body?.delta);
    if (!Number.isFinite(delta) || delta < -50 || delta > 50) return res.status(400).json({ error: 'delta phải trong khoảng -50..50.' });
    try {
      return res.json(await personalityService.adjustLoyalty(master.id, String(req.params.heroId), delta, String(req.body?.reason ?? 'MANUAL')));
    } catch (error) {
      if (personalityError(res, error)) return undefined;
      throw error;
    }
  }));

  // --- DM-04 (P1): injuries, medical facility and resurrection ---

  const medicalError = (res: Response, error: unknown): boolean => {
    if (error instanceof MedicalError) {
      res.status(error.statusCode).json({ error: error.message });
      return true;
    }
    return false;
  };

  app.get('/api/medical', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    return res.json(await medicalService.overview(master.id));
  }));

  app.get('/api/medical/history', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    return res.json(await medicalService.history(master.id));
  }));

  app.post('/api/medical/treatments', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.status(201).json(await medicalService.admit(master.id, String(req.body?.heroId ?? '')));
    } catch (error) {
      if (medicalError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/medical/emergency', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.json(await medicalService.emergency(master.id, String(req.body?.heroId ?? '')));
    } catch (error) {
      if (medicalError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/medical/resurrect', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      const result = await medicalService.resurrect(master.id, String(req.body?.heroId ?? ''));
      void auditService.record({
        actorId: master.id, actorType: 'MASTER', action: 'HERO_RESURRECTED',
        entityType: 'HERO', entityId: result.heroId,
        diff: { tearsUsed: result.tearsUsed, silverSpent: result.silverSpent, cycleCount: result.cycleCount, cycleReset: result.cycleReset },
      });
      return res.json(result);
    } catch (error) {
      if (medicalError(res, error)) return undefined;
      throw error;
    }
  }));

  // --- DM-09 (P1): hero survival (hunger, fatigue, food) ---

  const survivalError = (res: Response, error: unknown): boolean => {
    if (error instanceof SurvivalError) {
      res.status(error.statusCode).json({ error: error.message });
      return true;
    }
    return false;
  };

  app.get('/api/survival', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    return res.json(await survivalService.overview(master.id));
  }));

  app.get('/api/survival/upkeep', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    return res.json(await survivalService.baseUpkeep(master.id, req.query.hours));
  }));

  app.post('/api/survival/heroes/:heroId/feed', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.json(await survivalService.feed(master.id, String(req.params.heroId), req.body?.quantity));
    } catch (error) {
      if (survivalError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/survival/heroes/:heroId/rest', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.json(await survivalService.setResting(master.id, String(req.params.heroId), true));
    } catch (error) {
      if (survivalError(res, error)) return undefined;
      throw error;
    }
  }));

  app.delete('/api/survival/heroes/:heroId/rest', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.json(await survivalService.setResting(master.id, String(req.params.heroId), false));
    } catch (error) {
      if (survivalError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/survival/kitchen/cook', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.json(await survivalService.cook(master.id, req.body?.quantity));
    } catch (error) {
      if (survivalError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/survival/rations/quote', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    const context = req.body?.context === 'WAR' ? 'WAR' : 'DUNGEON';
    try {
      return res.json(await survivalService.rationQuote(master.id, context, req.body?.heroCount, req.body?.charge === true));
    } catch (error) {
      if (survivalError(res, error)) return undefined;
      throw error;
    }
  }));

  // --- DM-08 (P1): base, construction and production ---

  const requireMaster = async (req: AuthRequest) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    return master;
  };

  const baseError = (res: Response, error: unknown): boolean => {
    if (error instanceof BaseError) {
      res.status(error.statusCode).json({ error: error.message });
      return true;
    }
    return false;
  };

  app.get('/api/base/overview', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    return res.json(await buildingService.overview(master.id));
  }));

  app.post('/api/base/expand', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      const result = await buildingService.expand(master.id);
      void auditService.record({
        actorId: master.id, actorType: 'MASTER', action: AUDIT_ACTIONS.BASE_EXPANDED,
        entityType: 'WORLD', entityId: master.id, diff: { next: result },
      });
      return res.json(result);
    } catch (error) {
      if (baseError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/base/buildings', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      const result = await buildingService.construct(master.id, req.body?.buildingType, req.body?.plotIndex);
      void auditService.record({
        actorId: master.id, actorType: 'MASTER', action: AUDIT_ACTIONS.BUILDING_CONSTRUCTED,
        entityType: 'BUILDING', entityId: result.building.id,
        diff: { buildingType: result.building.buildingType, plotIndex: result.building.plotIndex, silverSpent: result.silverSpent },
      });
      return res.status(201).json(result);
    } catch (error) {
      if (baseError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/base/buildings/:buildingId/upgrade', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      const result = await buildingService.upgrade(master.id, String(req.params.buildingId));
      void auditService.record({
        actorId: master.id, actorType: 'MASTER', action: AUDIT_ACTIONS.BUILDING_UPGRADED,
        entityType: 'BUILDING', entityId: result.building.id,
        diff: { targetLevel: result.targetLevel, silverSpent: result.silverSpent, materialsSpent: result.materialsSpent },
      });
      return res.json(result);
    } catch (error) {
      if (baseError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/base/buildings/:buildingId/demolish', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      const result = await buildingService.demolish(master.id, String(req.params.buildingId));
      void auditService.record({
        actorId: master.id, actorType: 'MASTER', action: AUDIT_ACTIONS.BUILDING_DEMOLISHED,
        entityType: 'BUILDING', entityId: result.demolished, diff: { refundSilver: result.refundSilver },
      });
      return res.json(result);
    } catch (error) {
      if (baseError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/base/buildings/:buildingId/production', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.json(await buildingService.configureProduction(master.id, String(req.params.buildingId), req.body?.resourceType));
    } catch (error) {
      if (baseError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/base/buildings/:buildingId/collect', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      const result = await buildingService.collect(master.id, String(req.params.buildingId));
      if (result.collected > 0) {
        void auditService.record({
          actorId: master.id, actorType: 'MASTER', action: AUDIT_ACTIONS.RESOURCE_COLLECTED,
          entityType: 'BUILDING', entityId: String(req.params.buildingId),
          diff: { resourceType: result.resourceType, quantity: result.collected },
        });
      }
      return res.json(result);
    } catch (error) {
      if (baseError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/base/buildings/:buildingId/workers', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.status(201).json(await buildingService.assignWorker(master.id, String(req.params.buildingId), req.body?.heroId));
    } catch (error) {
      if (baseError(res, error)) return undefined;
      throw error;
    }
  }));

  app.delete('/api/base/buildings/:buildingId/workers/:heroId', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.json(await buildingService.removeWorker(master.id, String(req.params.buildingId), String(req.params.heroId)));
    } catch (error) {
      if (baseError(res, error)) return undefined;
      throw error;
    }
  }));

  // --- DM-14: configuration versioning, audit, monitoring and security ---

  app.get('/api/admin/configs', requireAdminApiKey, asyncRoute(async (req, res) => {
    const key = typeof req.query.key === 'string' ? req.query.key : undefined;
    try {
      return res.json(await systemConfigService.list(key));
    } catch (error) {
      if (error instanceof ConfigError) return res.status(error.statusCode).json({ error: error.message });
      throw error;
    }
  }));

  app.get('/api/admin/configs/active', requireAdminApiKey, asyncRoute(async (req, res) => {
    const key = typeof req.query.key === 'string' ? req.query.key : '';
    if (!isConfigKey(key)) return res.status(400).json({ error: `key must be one of: ${CONFIG_KEYS.join(', ')}.` });
    const active = await systemConfigService.getActive(key);
    if (!active) return res.json({ configKey: key, id: null, version: 0, value: null });
    return res.json({ configKey: key, id: active.id, version: active.version, value: active.value });
  }));

  app.post('/api/admin/configs', requireAdminApiKey, asyncRoute(async (req, res) => {
    try {
      const created = await systemConfigService.createVersion({
        configKey: typeof req.body?.configKey === 'string' ? req.body.configKey : '',
        value: req.body?.configValue ?? req.body?.value,
        updatedBy: typeof req.body?.updatedBy === 'string' ? req.body.updatedBy : adminActor(req),
        activate: req.body?.activate !== false,
      });
      return res.status(201).json(created);
    } catch (error) {
      if (error instanceof ConfigError) return res.status(error.statusCode).json({ error: error.message });
      throw error;
    }
  }));

  app.post('/api/admin/configs/:configId/activate', requireAdminApiKey, asyncRoute(async (req, res) => {
    try {
      const activated = await systemConfigService.activate(String(req.params.configId), adminActor(req));
      if (!activated) return res.status(404).json({ error: 'Configuration version not found.' });
      return res.json(activated);
    } catch (error) {
      if (error instanceof ConfigError) return res.status(error.statusCode).json({ error: error.message });
      throw error;
    }
  }));

  app.get('/api/admin/audit-logs', requireAdminApiKey, asyncRoute(async (req, res) => {
    const limit = Number(req.query.limit ?? 50);
    return res.json(await auditService.list({
      limit: Number.isFinite(limit) ? limit : 50,
      action: typeof req.query.action === 'string' ? req.query.action : undefined,
      entityType: typeof req.query.entityType === 'string' ? req.query.entityType : undefined,
      entityId: typeof req.query.entityId === 'string' ? req.query.entityId : undefined,
      actorId: typeof req.query.actorId === 'string' ? req.query.actorId : undefined,
    }));
  }));

  app.get('/api/admin/monitoring', requireAdminApiKey, asyncRoute(async (_req, res) => {
    return res.json(await monitoringService.snapshot());
  }));

  app.get('/api/admin/security-alerts', requireAdminApiKey, asyncRoute(async (req, res) => {
    const status = typeof req.query.status === 'string' ? req.query.status : undefined;
    const limit = Number(req.query.limit ?? 50);
    return res.json(await securityAlertService.list({ status, limit: Number.isFinite(limit) ? limit : 50 }));
  }));

  app.post('/api/admin/security-alerts/:alertId/resolve', requireAdminApiKey, asyncRoute(async (req, res) => {
    const alertId = String(req.params.alertId);
    const resolved = await securityAlertService.resolve(alertId, adminActor(req));
    if (!resolved) return res.status(404).json({ error: 'Open security alert not found.' });
    void auditService.record({
      actorId: adminActor(req), actorType: 'ADMIN', action: AUDIT_ACTIONS.SECURITY_ALERT_RESOLVED,
      entityType: 'SECURITY_ALERT', entityId: alertId, diff: { severity: resolved.severity, signal: resolved.signal },
    });
    return res.json(resolved);
  }));

  app.get('/api/gacha/history', requireAccount, requireFeature('SUMMON'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    const history = await db.select({
      id: summonHistory.id, sessionId: summonHistory.sessionId, rollNumber: summonHistory.rollNumber,
      pityNumber: summonHistory.pityNumber, rewardType: summonHistory.rewardType,
      rewardId: summonHistory.rewardId, rewardName: summonHistory.rewardName,
      rarity: summonHistory.rarity, wasFiveStar: summonHistory.wasFiveStar,
      wasDuplicate: summonHistory.wasDuplicate, thienMenhGranted: summonHistory.thienMenhGranted,
      summonOrigin: summonHistory.summonOrigin, createdAt: summonHistory.createdAt,
    }).from(summonHistory).where(eq(summonHistory.masterId, master.id)).orderBy(desc(summonHistory.createdAt)).limit(50);
    return res.json(history.map(row => ({ ...row, itemType: row.rewardType, isFiveStar: row.wasFiveStar, isDuplicate: row.wasDuplicate, duplicateBonus: row.thienMenhGranted ? { thienMenhGranted: row.thienMenhGranted } : undefined })));
  }));

  app.get('/api/heroes', requireAccount, requireFeature('HERO_COLLECTION'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    const collection = await db.select().from(heroes).where(eq(heroes.masterId, master.id)).orderBy(desc(heroes.rarity), heroes.name);
    const templateRows = await db.select({ code: heroTemplates.code, heroClass: heroTemplates.heroClass, element: heroTemplates.element })
      .from(heroTemplates);
    const templateByCode = new Map(templateRows.map(template => [template.code, template]));
    const skillTemplates = await db.select().from(heroSkillTemplates).where(eq(heroSkillTemplates.isActive, true));
    const skillInstances = collection.length ? await db.select().from(heroSkillInstances).where(inArray(heroSkillInstances.heroId, collection.map(hero => hero.id))) : [];
    const skillByHeroAndCode = new Map(skillInstances.map(instance => [`${instance.heroId}:${instance.skillCode}`, instance]));
    const levelConfigs = await db.select().from(heroLevelConfigs);
    const expThresholdByLevel = new Map(levelConfigs.map(config => [config.level, config.cumulativeExpRequired.toString()]));
    const developmentConfigs = await db.select().from(heroDevelopmentConfigs).where(eq(heroDevelopmentConfigs.action, 'PROMOTION'));
    const maxLevelByPromotionRank = new Map(developmentConfigs.map(config => [config.rank, config.maxLevelAfter]));
    const equipped = await db.select({ item: equipmentInstances, template: equipmentTemplates })
      .from(equipmentInstances).innerJoin(equipmentTemplates, eq(equipmentInstances.templateCode, equipmentTemplates.code))
      .where(and(eq(equipmentInstances.masterId, master.id), eq(equipmentInstances.location, 'EQUIPPED')));
    const bonuses = new Map<string, { hp: number; attack: number; defense: number; speed: number }>();
    for (const row of equipped) {
      if (!row.item.equippedHeroId) continue;
      const bonus = bonuses.get(row.item.equippedHeroId) ?? { hp: 0, attack: 0, defense: 0, speed: 0 };
      bonus.hp += row.template.bonusHp; bonus.attack += row.template.bonusAttack;
      bonus.defense += row.template.bonusDefense; bonus.speed += row.template.bonusSpeed;
      bonuses.set(row.item.equippedHeroId, bonus);
    }
    return res.json(collection.map(hero => {
      const bonus = bonuses.get(hero.id) ?? { hp: 0, attack: 0, defense: 0, speed: 0 };
      const template = templateByCode.get(hero.configId);
      const skills = skillTemplates.filter(skill => skill.heroClass === template?.heroClass).map(skill => {
        const instance = skillByHeroAndCode.get(`${hero.id}:${skill.code}`);
        return { ...skill, skillLevel: instance?.skillLevel ?? 1, isUnlocked: instance?.isUnlocked ?? false, behaviorMode: instance?.behaviorMode ?? 'AUTO', canUnlock: hero.level >= skill.unlockLevel && hero.state !== 'DEAD' && hero.state !== 'DISABLED', skillEffectValue: skill.effectValue + ((instance?.skillLevel ?? 1) - 1) * skill.upgradeIncrement };
      });
      return {
        ...hero, heroClass: template?.heroClass ?? 'UNKNOWN', element: template?.element ?? 'UNKNOWN', exp: hero.exp.toString(), nextLevelExp: expThresholdByLevel.get(hero.level + 1) ?? null, maxLevel: hero.promotionRank === 0 ? 20 : maxLevelByPromotionRank.get(hero.promotionRank) ?? 20,
        skills,
        derivedStats: { hp: Math.min(hero.hp, hero.maxHp + bonus.hp), maxHp: hero.maxHp + bonus.hp, attack: hero.attack + bonus.attack, defense: hero.defense + bonus.defense, speed: hero.speed + bonus.speed },
      };
    }));
  }));

  app.patch('/api/heroes/:heroId/lock', requireAccount, requireFeature('HERO_COLLECTION'), asyncRoute(async (req, res) => {
    if (typeof req.body?.isLocked !== 'boolean') return res.status(400).json({ error: 'isLocked must be a boolean.' });
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    const [hero] = await db.update(heroes).set({ isLocked: req.body.isLocked, updatedAt: new Date() })
      .where(and(eq(heroes.id, String(req.params.heroId)), eq(heroes.masterId, master.id))).returning({ id: heroes.id, isLocked: heroes.isLocked });
    if (!hero) return res.status(404).json({ error: 'Hero not found.' });
    return res.json(hero);
  }));

  app.post('/api/heroes/:heroId/skills/:skillCode/unlock', requireAccount, requireFeature('HERO_COLLECTION'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    const [hero] = await db.select().from(heroes).where(and(eq(heroes.id, String(req.params.heroId)), eq(heroes.masterId, master.id))).limit(1);
    if (!hero) return res.status(404).json({ error: 'Hero not found.' });
    if (hero.isLocked) return res.status(409).json({ error: 'Hero is locked.' });
    if (hero.state === 'DEAD') return res.status(409).json({ error: 'ERR_HERO_PERMANENTLY_DEAD' });
    if (hero.state === 'DISABLED' || hero.hp <= 0) return res.status(409).json({ error: 'Hero is not available for development.' });
    const [heroTemplate] = await db.select().from(heroTemplates).where(eq(heroTemplates.code, hero.configId)).limit(1);
    const [template] = heroTemplate ? await db.select().from(heroSkillTemplates)
      .where(and(eq(heroSkillTemplates.code, String(req.params.skillCode)), eq(heroSkillTemplates.heroClass, heroTemplate.heroClass), eq(heroSkillTemplates.isActive, true))).limit(1) : [];
    if (!template) return res.status(404).json({ error: 'Skill is not configured for this Hero class.' });
    if (hero.level < template.unlockLevel) return res.status(409).json({ error: `Hero must reach level ${template.unlockLevel} to unlock this skill.` });
    const [instance] = await db.select().from(heroSkillInstances).where(and(eq(heroSkillInstances.heroId, hero.id), eq(heroSkillInstances.skillCode, String(req.params.skillCode)))).limit(1);
    if (instance?.isUnlocked) return res.status(409).json({ error: 'Hero skill is already unlocked.' });
    if (instance) {
      const [updated] = await db.update(heroSkillInstances).set({ isUnlocked: true, updatedAt: new Date() }).where(eq(heroSkillInstances.id, instance.id)).returning();
      return res.json(updated);
    }
    const [created] = await db.insert(heroSkillInstances).values({ id: uuidv4(), heroId: hero.id, skillCode: String(req.params.skillCode), skillLevel: 1, isUnlocked: true, behaviorMode: 'AUTO', updatedAt: new Date() }).returning();
    return res.json(created);
  }));

  app.post('/api/heroes/:heroId/skills/:skillCode/upgrade', requireAccount, requireFeature('HERO_COLLECTION'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    const result = await db.transaction(async tx => {
      const [hero] = await tx.select().from(heroes).where(and(eq(heroes.id, String(req.params.heroId)), eq(heroes.masterId, master.id))).for('update').limit(1);
      if (!hero) return { status: 404, error: 'Hero not found.' } as const;
      if (hero.isLocked) return { status: 409, error: 'Hero is locked.' } as const;
      if (hero.state === 'DEAD') return { status: 409, error: 'ERR_HERO_PERMANENTLY_DEAD' } as const;
      if (hero.state === 'DISABLED' || hero.hp <= 0) return { status: 409, error: 'Hero is not available for development.' } as const;
      const [heroTemplate] = await tx.select().from(heroTemplates).where(eq(heroTemplates.code, hero.configId)).limit(1);
      const [template] = heroTemplate ? await tx.select().from(heroSkillTemplates).where(and(eq(heroSkillTemplates.code, String(req.params.skillCode)), eq(heroSkillTemplates.heroClass, heroTemplate.heroClass), eq(heroSkillTemplates.isActive, true))).limit(1) : [];
      if (!template) return { status: 404, error: 'Skill is not configured for this Hero class.' } as const;
      const [instance] = await tx.select().from(heroSkillInstances).where(and(eq(heroSkillInstances.heroId, hero.id), eq(heroSkillInstances.skillCode, template.code))).for('update').limit(1);
      if (!instance?.isUnlocked) return { status: 409, error: 'Unlock this skill before upgrading it.' } as const;
      if (instance.skillLevel >= template.maxLevel) return { status: 409, error: 'Skill is already at maximum level.' } as const;
      const [book] = await tx.select().from(masterItems).where(and(eq(masterItems.masterId, master.id), eq(masterItems.itemId, 'SAMPLE_HERO_SKILL_BOOK'))).for('update').limit(1);
      if (!book || book.quantity < 1) return { status: 409, error: 'One SAMPLE_HERO_SKILL_BOOK is required.' } as const;
      await tx.update(masterItems).set({ quantity: book.quantity - 1, updatedAt: new Date() }).where(eq(masterItems.id, book.id));
      const [updated] = await tx.update(heroSkillInstances).set({ skillLevel: instance.skillLevel + 1, updatedAt: new Date() }).where(eq(heroSkillInstances.id, instance.id)).returning();
      return { status: 200, skill: updated, effectValue: template.effectValue + (updated.skillLevel - 1) * template.upgradeIncrement, bookQuantity: book.quantity - 1 } as const;
    });
    if (result.status !== 200) return res.status(result.status).json({ error: result.error });
    return res.json(result);
  }));

  app.patch('/api/heroes/:heroId/skills/:skillCode/behavior', requireAccount, requireFeature('HERO_COLLECTION'), asyncRoute(async (req, res) => {
    const mode = req.body?.behaviorMode;
    if (mode !== 'AUTO' && mode !== 'MANUAL') return res.status(400).json({ error: 'behaviorMode must be AUTO or MANUAL.' });
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    const [hero] = await db.select().from(heroes).where(and(eq(heroes.id, String(req.params.heroId)), eq(heroes.masterId, master.id))).limit(1);
    if (!hero) return res.status(404).json({ error: 'Hero not found.' });
    if (hero.isLocked) return res.status(409).json({ error: 'Hero is locked.' });
    const [instance] = await db.select().from(heroSkillInstances).where(and(eq(heroSkillInstances.heroId, hero.id), eq(heroSkillInstances.skillCode, String(req.params.skillCode)))).limit(1);
    if (!instance?.isUnlocked) return res.status(409).json({ error: 'Unlock this skill before configuring its behavior.' });
    const [updated] = await db.update(heroSkillInstances).set({ behaviorMode: mode, updatedAt: new Date() }).where(eq(heroSkillInstances.id, instance.id)).returning();
    return res.json(updated);
  }));

  app.post('/api/heroes/:heroId/level-up', requireAccount, requireFeature('HERO_COLLECTION'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    const result = await db.transaction(async tx => {
      const [hero] = await tx.select().from(heroes).where(and(eq(heroes.id, String(req.params.heroId)), eq(heroes.masterId, master.id))).for('update').limit(1);
      if (!hero) return { status: 404, error: 'Hero not found.' } as const;
      if (hero.isLocked) return { status: 409, error: 'Hero is locked.' } as const;
      if (hero.state === 'DEAD') return { status: 409, error: 'ERR_HERO_PERMANENTLY_DEAD' } as const;
      if (hero.state === 'DISABLED' || hero.hp <= 0) return { status: 409, error: 'Hero is not available for development.' } as const;
      const [promotionConfig] = hero.promotionRank === 0 ? [] : await tx.select().from(heroDevelopmentConfigs).where(and(eq(heroDevelopmentConfigs.action, 'PROMOTION'), eq(heroDevelopmentConfigs.rank, hero.promotionRank))).limit(1);
      const heroLevelCap = promotionConfig?.maxLevelAfter ?? 20;
      const nextConfigs = await tx.select().from(heroLevelConfigs).where(and(gt(heroLevelConfigs.level, hero.level), lte(heroLevelConfigs.level, heroLevelCap))).orderBy(heroLevelConfigs.level).limit(1);
      if (!nextConfigs.length) return { status: 409, error: 'Hero is already at the configured level cap.' } as const;
      const [material] = await tx.select().from(masterItems).where(and(eq(masterItems.masterId, master.id), eq(masterItems.itemId, 'SAMPLE_HERO_EXP_100'))).for('update').limit(1);
      if (!material || material.quantity < 1) return { status: 409, error: 'Not enough SAMPLE_HERO_EXP_100.' } as const;

      const totalExp = hero.exp + 100n;
      const growthConfigs = await tx.select().from(heroLevelConfigs).where(and(gt(heroLevelConfigs.level, hero.level), lte(heroLevelConfigs.level, heroLevelCap))).orderBy(heroLevelConfigs.level);
      let level = hero.level, maxHp = hero.maxHp, hp = hero.hp, attack = hero.attack, defense = hero.defense, speed = hero.speed;
      for (const config of growthConfigs) {
        if (totalExp < config.cumulativeExpRequired) continue;
        const previousMaxHp = maxHp;
        maxHp = Math.floor(maxHp * config.statGrowthMultiplier);
        hp = Math.min(maxHp, hp + maxHp - previousMaxHp);
        attack = Math.floor(attack * config.statGrowthMultiplier);
        defense = Math.floor(defense * config.statGrowthMultiplier);
        speed = Math.floor(speed * config.statGrowthMultiplier);
        level = config.level;
      }
      await tx.update(masterItems).set({ quantity: material.quantity - 1, updatedAt: new Date() }).where(eq(masterItems.id, material.id));
      const [updated] = await tx.update(heroes).set({ exp: totalExp, level, maxHp, hp, attack, defense, speed, updatedAt: new Date() }).where(eq(heroes.id, hero.id)).returning();
      return { status: 200, hero: { id: updated.id, level: updated.level, maxLevel: heroLevelCap, exp: updated.exp.toString(), hp: updated.hp, maxHp: updated.maxHp, attack: updated.attack, defense: updated.defense, speed: updated.speed }, materialQuantity: material.quantity - 1 } as const;
    });
    if (result.status !== 200) return res.status(result.status).json({ error: result.error });
    return res.json(result);
  }));

  app.post('/api/heroes/:heroId/promote', requireAccount, requireFeature('HERO_COLLECTION'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    const result = await db.transaction(async tx => {
      const [hero] = await tx.select().from(heroes).where(and(eq(heroes.id, String(req.params.heroId)), eq(heroes.masterId, master.id))).for('update').limit(1);
      if (!hero) return { status: 404, error: 'Hero not found.' } as const;
      if (hero.isLocked) return { status: 409, error: 'Hero is locked.' } as const;
      if (hero.state === 'DEAD') return { status: 409, error: 'ERR_HERO_PERMANENTLY_DEAD' } as const;
      if (hero.state === 'DISABLED' || hero.hp <= 0) return { status: 409, error: 'Hero is not available for development.' } as const;
      const [config] = await tx.select().from(heroDevelopmentConfigs).where(and(eq(heroDevelopmentConfigs.action, 'PROMOTION'), eq(heroDevelopmentConfigs.rank, hero.promotionRank + 1))).limit(1);
      if (!config) return { status: 409, error: 'No further promotion is configured.' } as const;
      if (hero.level < config.requiredHeroLevel || hero.promotionRank < config.requiredPromotionRank) return { status: 409, error: 'Hero does not meet the configured promotion requirements.' } as const;
      const [material] = await tx.select().from(masterItems).where(and(eq(masterItems.masterId, master.id), eq(masterItems.itemId, config.materialItemId))).for('update').limit(1);
      if (!material || material.quantity < config.materialQuantity) return { status: 409, error: `Promotion requires ${config.materialQuantity} configured materials.` } as const;
      await tx.update(masterItems).set({ quantity: material.quantity - config.materialQuantity, updatedAt: new Date() }).where(eq(masterItems.id, material.id));
      const [updated] = await tx.update(heroes).set({ promotionRank: config.rank, updatedAt: new Date() }).where(eq(heroes.id, hero.id)).returning();
      return { status: 200, heroId: updated.id, promotionRank: updated.promotionRank, maxLevel: config.maxLevelAfter, materialQuantity: material.quantity - config.materialQuantity } as const;
    });
    if (result.status !== 200) return res.status(result.status).json({ error: result.error });
    return res.json(result);
  }));

  app.post('/api/heroes/:heroId/awaken', requireAccount, requireFeature('HERO_COLLECTION'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    const result = await db.transaction(async tx => {
      const [hero] = await tx.select().from(heroes).where(and(eq(heroes.id, String(req.params.heroId)), eq(heroes.masterId, master.id))).for('update').limit(1);
      if (!hero) return { status: 404, error: 'Hero not found.' } as const;
      if (hero.isLocked) return { status: 409, error: 'Hero is locked.' } as const;
      if (hero.state === 'DEAD') return { status: 409, error: 'ERR_HERO_PERMANENTLY_DEAD' } as const;
      if (hero.state === 'DISABLED' || hero.hp <= 0) return { status: 409, error: 'Hero is not available for development.' } as const;
      const [config] = await tx.select().from(heroDevelopmentConfigs).where(and(eq(heroDevelopmentConfigs.action, 'AWAKENING'), eq(heroDevelopmentConfigs.rank, hero.awakeningRank + 1))).limit(1);
      if (!config) return { status: 409, error: 'No further awakening is configured.' } as const;
      if (hero.level < config.requiredHeroLevel || hero.promotionRank < config.requiredPromotionRank) return { status: 409, error: 'Hero does not meet the configured awakening requirements.' } as const;
      const [material] = await tx.select().from(masterItems).where(and(eq(masterItems.masterId, master.id), eq(masterItems.itemId, config.materialItemId))).for('update').limit(1);
      if (!material || material.quantity < config.materialQuantity) return { status: 409, error: `Awakening requires ${config.materialQuantity} configured materials.` } as const;
      const multiplier = config.statGrowthMultiplier;
      const maxHp = Math.floor(hero.maxHp * multiplier);
      const [updated] = await tx.update(heroes).set({ awakeningRank: config.rank, maxHp, hp: Math.min(maxHp, hero.hp + maxHp - hero.maxHp), attack: Math.floor(hero.attack * multiplier), defense: Math.floor(hero.defense * multiplier), speed: Math.floor(hero.speed * multiplier), updatedAt: new Date() }).where(eq(heroes.id, hero.id)).returning();
      await tx.update(masterItems).set({ quantity: material.quantity - config.materialQuantity, updatedAt: new Date() }).where(eq(masterItems.id, material.id));
      return { status: 200, heroId: updated.id, awakeningRank: updated.awakeningRank, stats: { hp: updated.hp, maxHp: updated.maxHp, attack: updated.attack, defense: updated.defense, speed: updated.speed }, materialQuantity: material.quantity - config.materialQuantity } as const;
    });
    if (result.status !== 200) return res.status(result.status).json({ error: result.error });
    return res.json(result);
  }));

  app.get('/api/hero-templates', requireAccount, requireFeature('HERO_COLLECTION'), asyncRoute(async (_req, res) => {
    const templates = await db.select().from(heroTemplates).orderBy(heroTemplates.defaultRarity, heroTemplates.name);
    return res.json(templates);
  }));

  app.get('/api/equipment', requireAccount, requireFeature('EQUIPMENT'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    return res.json(await equipmentService.list(master.id));
  }));

  app.get('/api/equipment/floor-drops', requireAccount, requireFeature('EQUIPMENT'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    return res.json(await equipmentService.floorDrops(master.id));
  }));

  app.put('/api/equipment/:itemId/equip', requireAccount, requireFeature('EQUIPMENT'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    try { return res.json(await equipmentService.equip(master.id, String(req.params.itemId), req.body?.heroId)); }
    catch (error) {
      if (error instanceof EquipmentError) return res.status(error.statusCode).json({ error: error.message });
      throw error;
    }
  }));

  app.post('/api/equipment/:itemId/unequip', requireAccount, requireFeature('EQUIPMENT'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    try { return res.json(await equipmentService.unequip(master.id, String(req.params.itemId))); }
    catch (error) {
      if (error instanceof EquipmentError) return res.status(error.statusCode).json({ error: error.message });
      throw error;
    }
  }));

  app.post('/api/equipment/:itemId/pickup', requireAccount, requireFeature('EQUIPMENT'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    try { return res.json(await equipmentService.pickUp(master.id, String(req.params.itemId))); }
    catch (error) {
      if (error instanceof EquipmentError) return res.status(error.statusCode).json({ error: error.message });
      throw error;
    }
  }));

  app.get('/api/combat/buffs', requireAccount, requireFeature('PVE_COMBAT'), (_req: Request, res: Response) => {
    return res.json(Object.values(TacticalBuffManager.AVAILABLE_BUFFS));
  });

  app.get('/api/parties', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    return res.json(await combatService.listParties(master.id));
  }));

  app.post('/api/parties', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const name = typeof req.body?.name === 'string' ? req.body.name.trim() : '';
    if (!name || name.length > 60 || !/^[\p{L}\p{N} _-]+$/u.test(name)) return res.status(400).json({ error: 'Party name must be 1–60 letters, numbers, spaces, _ or -.' });
    try {
      const created = await db.transaction(async tx => {
        const [master] = await tx.select().from(masters).where(eq(masters.accountId, req.accountId!)).for('update').limit(1);
        if (!master) return null;
        const activeCombat = await tx.select({ id: combatSessions.id }).from(combatSessions).where(and(eq(combatSessions.masterId, master.id), eq(combatSessions.status, 'ACTIVE'))).limit(1);
        if (activeCombat.length) throw new CombatSessionError('Cannot create parties during active combat.', 409);
        const existing = await tx.select({ id: masterParties.id }).from(masterParties).where(eq(masterParties.masterId, master.id));
        const [party] = await tx.insert(masterParties).values({ id: uuidv4(), masterId: master.id, name, isDefault: existing.length === 0 }).returning();
        return party;
      });
      if (!created) return res.status(409).json({ error: 'Initialize a Master first.' });
      return res.status(201).json(await combatService.listParties(created.masterId));
    } catch (error) {
      if ((error as { code?: string }).code === '23505') return res.status(409).json({ error: 'A party with this name already exists.' });
      if (error instanceof CombatSessionError) return res.status(error.statusCode).json({ error: error.message });
      throw error;
    }
  }));

  app.put('/api/parties/:partyId', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const hasName = Object.hasOwn(req.body ?? {}, 'name');
    const hasHeroIds = Object.hasOwn(req.body ?? {}, 'heroIds');
    if (!hasName && !hasHeroIds) return res.status(400).json({ error: 'Provide a party name or heroIds.' });
    const name = hasName && typeof req.body.name === 'string' ? req.body.name.trim() : undefined;
    if (hasName && (!name || name.length > 60 || !/^[\p{L}\p{N} _-]+$/u.test(name))) return res.status(400).json({ error: 'Party name must be 1–60 letters, numbers, spaces, _ or -.' });
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    try {
      await combatService.updateParty(master.id, String(req.params.partyId), name, hasHeroIds ? req.body.heroIds : undefined);
      return res.json(await combatService.listParties(master.id));
    } catch (error) {
      if ((error as { code?: string }).code === '23505') return res.status(409).json({ error: 'A party with this name already exists.' });
      if (error instanceof CombatSessionError) return res.status(error.statusCode).json({ error: error.message });
      throw error;
    }
  }));

  app.patch('/api/parties/:partyId/default', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    const selected = await db.transaction(async tx => {
      await tx.select({ id: masters.id }).from(masters).where(eq(masters.id, master.id)).for('update').limit(1);
      const active = await tx.select({ id: combatSessions.id }).from(combatSessions).where(and(eq(combatSessions.masterId, master.id), eq(combatSessions.status, 'ACTIVE'))).limit(1);
      if (active.length) throw new CombatSessionError('Cannot change the default party during active combat.', 409);
      const [party] = await tx.select().from(masterParties).where(and(eq(masterParties.id, String(req.params.partyId)), eq(masterParties.masterId, master.id))).limit(1);
      if (!party) return false;
      await tx.update(masterParties).set({ isDefault: false, updatedAt: new Date() }).where(eq(masterParties.masterId, master.id));
      await tx.update(masterParties).set({ isDefault: true, updatedAt: new Date() }).where(eq(masterParties.id, party.id));
      return true;
    }).catch(error => {
      if (error instanceof CombatSessionError) return res.status(error.statusCode).json({ error: error.message });
      throw error;
    });
    if (res.headersSent) return;
    if (!selected) return res.status(404).json({ error: 'Party not found.' });
    return res.json(await combatService.listParties(master.id));
  }));

  app.delete('/api/parties/:partyId', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    const deleted = await db.transaction(async tx => {
      await tx.select({ id: masters.id }).from(masters).where(eq(masters.id, master.id)).for('update').limit(1);
      const active = await tx.select({ id: combatSessions.id }).from(combatSessions).where(and(eq(combatSessions.masterId, master.id), eq(combatSessions.status, 'ACTIVE'))).limit(1);
      if (active.length) throw new CombatSessionError('Cannot delete parties during active combat.', 409);
      const [party] = await tx.select().from(masterParties).where(and(eq(masterParties.id, String(req.params.partyId)), eq(masterParties.masterId, master.id))).limit(1);
      if (!party) return false;
      await tx.delete(masterParties).where(eq(masterParties.id, party.id));
      if (party.isDefault) {
        const [nextParty] = await tx.select().from(masterParties).where(eq(masterParties.masterId, master.id)).orderBy(asc(masterParties.createdAt)).limit(1);
        if (nextParty) await tx.update(masterParties).set({ isDefault: true, updatedAt: new Date() }).where(eq(masterParties.id, nextParty.id));
      }
      return true;
    }).catch(error => {
      if (error instanceof CombatSessionError) return res.status(error.statusCode).json({ error: error.message });
      throw error;
    });
    if (res.headersSent) return;
    if (!deleted) return res.status(404).json({ error: 'Party not found.' });
    return res.json(await combatService.listParties(master.id));
  }));

  app.get('/api/combat/party', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    const rows = await combatService.getParty(master.id);
    return res.json(rows.map(row => ({ ...row, hero: { ...row.hero, exp: row.hero.exp.toString() } })));
  }));

  app.put('/api/combat/party', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    try {
      const rows = await combatService.setParty(master.id, req.body?.heroIds);
      return res.json(rows.map(row => ({ ...row, hero: { ...row.hero, exp: row.hero.exp.toString() } })));
    }
    catch (error) {
      if (error instanceof CombatSessionError) return res.status(error.statusCode).json({ error: error.message });
      throw error;
    }
  }));

  app.get('/api/combat/session/active', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    return res.json(await combatService.getActive(master.id));
  }));

  app.post('/api/combat/session/start', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      const partyId = typeof req.body?.partyId === 'string' ? req.body.partyId : undefined;
      const buffId = typeof req.body?.buffId === 'string' ? req.body.buffId : undefined;
      return res.status(201).json(await combatService.start(master.id, { partyId, buffId }));
    }
    catch (error) {
      if (error instanceof CombatSessionError) return res.status(error.statusCode).json({ error: error.message });
      throw error;
    }
  }));

  app.get('/api/combat/session/latest', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    return res.json(await combatService.getLatest(master.id));
  }));

  app.post('/api/combat/session/:sessionId/advance', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    try {
      const session = await combatService.advance(master.id, String(req.params.sessionId));
      const report = session.battleReport as { result?: string; survivors?: { id: string; hp: number; maxHp: number }[] } | null;
      if (report?.survivors?.length) {
        await medicalService.recordBattleInjuries(master.id, report.survivors).catch(error => console.error('[medical] injury recording failed', error));
      }
      if (report?.result === 'VICTORY' && report.survivors?.length) {
        await personalityService.recordVictory(master.id, report.survivors.map(row => row.id))
          .catch(error => console.error('[personality] loyalty update failed', error));
      }
      return res.json(session);
    }
    catch (error) {
      if (error instanceof CombatSessionError) return res.status(error.statusCode).json({ error: error.message });
      throw error;
    }
  }));

  app.post('/api/combat/session/:sessionId/buff', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try { return res.json(await combatService.changeBuff(master.id, String(req.params.sessionId), req.body.buffId)); }
    catch (error) {
      if (error instanceof CombatSessionError) return res.status(error.statusCode).json({ error: error.message });
      throw error;
    }
  }));

  app.post('/api/combat/session/:sessionId/skills/:skillCode/use', requireAccount, requireFeature('PVE_COMBAT'), requireFeature('MASTER_SKILLS'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    try { return res.json(await combatService.useMasterSkill(master.id, String(req.params.sessionId), String(req.params.skillCode))); }
    catch (error) {
      if (error instanceof CombatSessionError) return res.status(error.statusCode).json({ error: error.message });
      throw error;
    }
  }));

  app.post('/api/gacha/summon', requireAccount, requireFeature('SUMMON'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    const { bannerId, rollCount } = req.body;
    if (typeof bannerId !== 'string' || (rollCount !== 1 && rollCount !== 10)) return res.status(400).json({ error: 'bannerId và rollCount (1 hoặc 10) là bắt buộc.' });
    const idempotencyKey = req.header('Idempotency-Key') ?? '';
    try {
      return res.json(await gachaService.summon(master.id, bannerId, rollCount, idempotencyKey));
    } catch (error) {
      if (error instanceof SummonError) return res.status(error.statusCode).json({ error: error.message });
      throw error;
    }
  }));

  app.use((error: unknown, _req: Request, res: Response, _next: NextFunction) => {
    console.error(error);
    return res.status(500).json({ error: 'Lỗi máy chủ.' });
  });

  return app;
}

if (process.env.NODE_ENV !== 'test') {
  const port = Number(process.env.PORT ?? 3000);
  createApp().listen(port, () => console.log(`[Infinite Gacha] API listening on ${port}`));
}
