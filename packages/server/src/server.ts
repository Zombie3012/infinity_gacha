import { alchemyService } from './modules/base/alchemy.service.js';
import 'dotenv/config';
import express, { Request, Response, NextFunction } from 'express';
import cors from 'cors';
import { and, asc, count, desc, eq, gt, inArray, isNull, lte, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { timingSafeEqual } from 'node:crypto';
import { aggregateEquipment, BREAKTHROUGH_SILVER_COST, breakthroughMaxLevel, eligibleClasses, heroEffectiveMaxLevel, roleForClass, rollElementAffinity, starMaxLevel, type EquipmentItemInput, type EquipmentV2Stats, type HeroClass, type StarRating } from '@infiniti-gacha/shared';
import { db, pool } from './database/db.js';
import { accounts, accountSessions, playerProfiles, banners, summonRewardPool, heroes, heroTemplates, heroSkillTemplates, heroSkillInstances, masters, masterParties, combatSessions, worlds, masterSummonInventory, masterItems, weeklyScrollExchanges, summonHistory, equipmentInstances, equipmentTemplates, heroLevelConfigs, heroDevelopmentConfigs, featureUnlockConfigs, heroElementAffinities, heroPersonalityTraits, heroImprints, imprintDefinitions, heroSurvivalStates } from './database/drizzle-schema.js';
import { CLASS_CHANGE_ITEM, CLASS_CHANGE_SILVER, ProgressionError, allocateTraining, classChangeCheck, isV2Origin, originOf, progressionFor } from './modules/hero/hero-progression.js';
import { legacyClassFor } from './modules/hero/hero-generation.js';
import { imprintSlotsFor } from './modules/hero/imprint-rules.js';
import { heroPromotionService } from './modules/hero/hero-promotion.service.js';
import { createAccessToken, hashPassword, readAccessToken, TOKEN_LIFETIME_SECONDS, verifyPassword } from './modules/auth/auth.js';
import { PersistentGachaService, SPECIAL_BANNER_GEM_COST_PER_ROLL, SummonError } from './modules/gacha/persistent-gacha.service.js';
import { WorldSeedGenerator } from './modules/dungeon/world-seed.generator.js';
import { dungeonConfigService } from './modules/dungeon/dungeon-config.service.js';
import { worldSeedService } from './modules/dungeon/world-seed.service.js';
import { dungeonExplorationService } from './modules/dungeon/dungeon-exploration.service.js';
import { inventoryService } from './modules/inventory/inventory.service.js';
import { currencyService } from './modules/economy/currency.service.js';
import { exchangeSilverForNormalScrolls, getWeeklyExchangePeriodKey, ScrollExchangeError } from './modules/economy/scroll-exchange.service.js';
import { CombatSessionError, CombatSessionService } from './modules/combat/combat-session.service.js';
import { CombatV2Error, combatV2Service } from './modules/combat/combat-v2.service.js';
import { TacticalBuffManager } from './modules/combat/tactical-buff.manager.js';
import { EquipmentError, EquipmentService } from './modules/equipment/equipment.service.js';
import { AUDIT_ACTIONS, auditService } from './modules/admin/audit.service.js';
import { CONFIG_KEYS, ConfigError, isConfigKey, systemConfigService } from './modules/admin/system-config.service.js';
import { monitoringService } from './modules/admin/monitoring.service.js';
import { rateGuard, securityAlertService } from './modules/admin/security.service.js';
import { BaseError, buildingService } from './modules/base/building.service.js';
import { SurvivalError, survivalService } from './modules/survival/survival.service.js';
import { applyDrift } from './modules/survival/survival-rules.js';
import { MedicalError, medicalService } from './modules/medical/medical.service.js';
import { heroChronicleService } from './modules/hero/hero-chronicle.service.js';
import { PersonalityError, personalityService } from './modules/personality/personality.service.js';
import { ShopError, shopService } from './modules/shop/shop.service.js';
import { MailboxError, mailboxService } from './modules/shop/mailbox.service.js';
import { CraftingError, craftingService } from './modules/crafting/crafting.service.js';
import { QuestError, questService } from './modules/quest/quest.service.js';
import { AccountError, accountLinkService } from './modules/auth/account.service.js';
import { PaymentError, paymentService } from './modules/payment/payment.service.js';
import { EventError, eventService } from './modules/liveops/event.service.js';
import { LeaderboardError, leaderboardService } from './modules/liveops/leaderboard.service.js';
import { PlayerAdminError, playerAdminService } from './modules/admin/player-admin.service.js';
import { ContentAdminError, contentAdminService } from './modules/admin/content-admin.service.js';
import { AnalyticsService, analyticsService } from './modules/analytics/analytics.service.js';
import { SupportError, supportService } from './modules/support/support.service.js';
import { WorldError, worldService } from './modules/world/world.service.js';
import { ExpeditionError, expeditionService } from './modules/world/expedition.service.js';
import { AirshipError, airshipService } from './modules/world/airship.service.js';
import { AllianceError, allianceService } from './modules/world/alliance.service.js';
import { ChatError, chatService } from './modules/world/chat.service.js';
import { FriendError, friendService } from './modules/world/friend.service.js';
import { ConquestError, conquestService } from './modules/world/conquest.service.js';
import { getBattleRules } from './modules/admin/runtime-rules.js';
import { PveRuleError } from '@infiniti-gacha/shared';
import { PveError, pveService } from './modules/pve/pve.service.js';
import { CombatReadinessError } from './modules/combat/combat-readiness.js';
import { baseBuildings, pveHeroReservations, pveSquads } from './database/drizzle-schema.js';
import { requiredTowerFloorForBuilding } from './modules/base/base-rules.js';

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
      if (row.rewardType !== 'HERO' || row.rarity === null || row.rarity < 1 || row.rarity > 7 || !Number.isInteger(row.rarity) || !row.heroTemplateCode) return 'OTHER_HERO rows must reference a 1-7 star Hero template.';
    } else if (row.poolGroup === 'MATERIAL') {
      if (row.rewardType !== 'MATERIAL' || (row.rarity !== null && (!Number.isInteger(row.rarity) || row.rarity < 1 || row.rarity > 7)) || row.heroTemplateCode !== null) return 'MATERIAL rows require a 1-7 star rarity (or catalogue default) and cannot reference Hero templates.';
    } else return 'Unknown banner pool group.';
  }
  const hasHero = groups.has('FIVE_STAR_HERO') || groups.has('OTHER_HERO');
  if (!hasHero || !groups.has('MATERIAL')) return 'Pool requires at least one Hero group and a Material group.';
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
    if (!feature) {
      return res.status(403).json({ error: `Feature ${featureCode} is unavailable.` });
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
      master: master ? { id: master.id, accountId: master.accountId, masterName: master.masterName, silverCoins: master.silverCoins.toString(), gems: master.gems.toString(), gemDebt: master.gemDebt.toString() } : null,
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
    return res.json(configs.map(feature => ({ ...feature, unlocked: true })));
  }));

  app.get('/api/master/skills', requireAccount, requireFeature('MASTER_SKILLS'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    return res.json(await combatService.getMasterSkills(master.id));
  }));

  app.post(['/api/master/init', '/api/masters/init'], requireAccount, asyncRoute(async (req, res) => {
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
          baseZones: 2,
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
      return res.status(201).json({ id: master.id, accountId: master.accountId, masterName: master.masterName, silverCoins: master.silverCoins.toString(), gems: master.gems.toString(), gemDebt: master.gemDebt.toString() });
    } catch (error) {
      const pgCode = (error as { code?: string }).code ?? (error as { cause?: { code?: string } }).cause?.code;
      if (pgCode === '23505') return res.status(409).json({ error: 'Tài khoản này đã có Master.' });
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

  app.use('/api/dungeon', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    const [world] = await db.select({ currentFloor: worlds.currentFloor }).from(worlds).where(eq(worlds.masterId, master.id)).limit(1);
    if ((world?.currentFloor ?? 1) <= 5) return res.status(403).json({ error: 'Hầm Ngục mở sau khi vượt Tháp tầng 5.' });
    return res.status(503).json({ error: 'Hầm Ngục Cổ Đại đang được phát triển.' });
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

  const computePureBannerRates = (pool: { rewardType: string; rarity: number | null; weight: number }[]) => {
    const totalWeight = pool.reduce((sum, row) => sum + Math.max(0, row.weight), 0);
    const pct = (w: number) => (totalWeight > 0 ? Math.round((w / totalWeight) * 10000) / 100 : 0);
    const heroRows = pool.filter(r => r.rewardType === 'HERO');
    const matWeight = pool.filter(r => r.rewardType === 'MATERIAL').reduce((s, r) => s + r.weight, 0);
    const weightByStar = (star: number) => heroRows.filter(r => r.rarity === star).reduce((s, r) => s + r.weight, 0);
    const fiveW = weightByStar(5);
    const fourW = weightByStar(4);
    const threeW = weightByStar(3);
    const twoW = weightByStar(2);
    const oneW = weightByStar(1);
    const heroTotalW = heroRows.reduce((s, r) => s + r.weight, 0);
    return {
      sevenStarHeroPercent: pct(weightByStar(7)),
      sixStarHeroPercent: pct(weightByStar(6)),
      fiveStarHeroPercent: pct(fiveW),
      fourStarHeroPercent: pct(fourW),
      threeStarHeroPercent: pct(threeW),
      twoStarHeroPercent: pct(twoW),
      oneStarHeroPercent: pct(oneW),
      heroTotalPercent: pct(heroTotalW),
      otherHeroPercent: pct(heroTotalW - fiveW),
      materialPercent: pct(matWeight),
    };
  };

  app.get('/api/gacha/banners', requireAccount, requireFeature('SUMMON'), asyncRoute(async (_req, res) => {
    const now = new Date();
    const activeBanners = await db.select().from(banners).where(eq(banners.isActive, true)).orderBy(asc(banners.id));
    const live = activeBanners.filter(banner => banner.startDate <= now && (!banner.endDate || banner.endDate > now));
    const allPools = live.length
      ? await db.select({
          bannerId: summonRewardPool.bannerId,
          rewardType: summonRewardPool.rewardType,
          rarity: summonRewardPool.rarity,
          weight: summonRewardPool.weight,
        }).from(summonRewardPool).where(and(inArray(summonRewardPool.bannerId, live.map(b => b.id)), eq(summonRewardPool.isActive, true)))
      : [];
    return res.json(live.map(banner => {
      const pool = allPools.filter(row => row.bannerId === banner.id);
      const isSpecial = banner.bannerType === 'SPECIAL';
      const heroStars = pool.filter(r => r.rewardType === 'HERO' && r.rarity !== null).map(r => r.rarity!);
      return {
        ...banner,
        costType: isSpecial ? 'GEMS' : 'SCROLL',
        costPerRoll: isSpecial ? SPECIAL_BANNER_GEM_COST_PER_ROLL : 1,
        minHeroRarity: heroStars.length ? Math.min(...heroStars) : 1,
        maxHeroRarity: heroStars.length ? Math.max(...heroStars) : 3,
        rates: computePureBannerRates(pool),
      };
    }));
  }));

  app.get('/api/gacha/banners/:bannerId', requireAccount, requireFeature('SUMMON'), asyncRoute(async (req, res) => {
    const now = new Date();
    const [banner] = await db.select().from(banners).where(and(eq(banners.id, String(req.params.bannerId)), eq(banners.isActive, true))).limit(1);
    if (!banner || banner.startDate > now || (banner.endDate && banner.endDate <= now)) return res.status(404).json({ error: 'Active banner not found.' });
    const pool = await db.select({
      rewardId: summonRewardPool.rewardId, rewardName: summonRewardPool.rewardName,
      rewardType: summonRewardPool.rewardType, poolGroup: summonRewardPool.poolGroup,
      heroTemplateCode: summonRewardPool.heroTemplateCode, rarity: summonRewardPool.rarity,
      weight: summonRewardPool.weight,
    }).from(summonRewardPool).where(and(eq(summonRewardPool.bannerId, banner.id), eq(summonRewardPool.isActive, true)));
    const isSpecial = banner.bannerType === 'SPECIAL';
    return res.json({
      banner: {
        ...banner,
        costType: isSpecial ? 'GEMS' : 'SCROLL',
        costPerRoll: isSpecial ? SPECIAL_BANNER_GEM_COST_PER_ROLL : 1,
      },
      pool,
      rates: computePureBannerRates(pool),
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

  // --- DM-13 (P3): hero-vs-hero PvP reports and territory defense ---

  const requireTower25 = asyncRoute(async (req, res, next) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    const [world] = await db.select({ currentFloor: worlds.currentFloor }).from(worlds).where(eq(worlds.masterId, master.id)).limit(1);
    if ((world?.currentFloor ?? 1) <= 25) return res.status(403).json({ error: 'Viễn Chinh mở sau khi vượt Tháp tầng 25.' });
    return next();
  });
  app.use(['/api/world/expeditions', '/api/world/tiles', '/api/world/pvp', '/api/world/territories', '/api/world/conquest', '/api/world/global/map', '/api/world/global/tiles'], requireAccount, requireTower25);

  app.get('/api/world/pvp/battles', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    return res.json(await expeditionService.battles(master.id));
  }));

  app.get('/api/world/tiles/:tileId/defense', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    return res.json(await expeditionService.defenseEstimate(String(req.params.tileId)));
  }));

  // --- DM-13 (P3): hero expeditions (no army: heroes travel and fight themselves) ---

  const expeditionError = (res: Response, error: unknown): boolean => {
    if (error instanceof ExpeditionError) {
      res.status(error.statusCode).json({ error: error.message });
      return true;
    }
    return false;
  };

  app.post('/api/world/expeditions', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      const result = await expeditionService.dispatch(
        master.id,
        String(req.body?.tileId ?? ''),
        req.body?.mission,
        req.body?.heroIds,
        {
          airshipId: req.body?.airshipId ? String(req.body.airshipId) : null,
          dungeonId: req.body?.dungeonId ? String(req.body.dungeonId) : null,
          rescueTargetExpeditionId: req.body?.rescueTargetExpeditionId ? String(req.body.rescueTargetExpeditionId) : null,
        },
      );
      void auditService.record({
        actorId: master.id, actorType: 'MASTER', action: 'EXPEDITION_DISPATCHED', entityType: 'EXPEDITION',
        entityId: result.expeditionId, diff: { mission: result.mission, tileId: result.tileId, heroes: result.heroes.length, airshipId: result.airshipId },
      });
      return res.status(201).json(result);
    } catch (error) {
      if (expeditionError(res, error)) return undefined;
      throw error;
    }
  }));

  app.get('/api/world/expeditions', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    return res.json(await expeditionService.list(master.id));
  }));

  app.post('/api/world/expeditions/:expeditionId/recall', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.json(await expeditionService.recall(master.id, String(req.params.expeditionId)));
    } catch (error) {
      if (expeditionError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/world/expeditions/:expeditionId/redirect', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.json(await expeditionService.redirect(master.id, String(req.params.expeditionId), String(req.body?.tileId ?? '')));
    } catch (error) {
      if (expeditionError(res, error)) return undefined;
      throw error;
    }
  }));

  app.get('/api/world/rts/snapshot', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    return res.json(await expeditionService.rtsSnapshot(master.id, {
      cx: req.query.cx,
      cy: req.query.cy,
      radius: req.query.radius,
    }));
  }));

  // --- Airship Port (Bến Thiên Hành): Hangar Grid, Blueprints, Tech Tree ---
  const airshipError = (res: Response, error: unknown): boolean => {
    if (error instanceof AirshipError) {
      res.status(error.statusCode).json({ error: error.message });
      return true;
    }
    return false;
  };

  app.get('/api/base/airships', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    return res.json(await airshipService.getPortState(master.id));
  }));

  app.post('/api/base/airships/tech/:techCode/unlock', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.json(await airshipService.unlockTech(master.id, req.params.techCode));
    } catch (error) {
      if (airshipError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/base/airships/craft', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.status(201).json(await airshipService.craft(master.id, req.body?.blueprintCode, {
        customName: typeof req.body?.name === 'string' ? req.body.name : undefined,
        dockX: req.body?.dockX !== undefined ? Number(req.body.dockX) : undefined,
        dockY: req.body?.dockY !== undefined ? Number(req.body.dockY) : undefined,
        rotation: req.body?.rotation !== undefined ? Number(req.body.rotation) : undefined,
        instant: Boolean(req.body?.instant),
      }));
    } catch (error) {
      if (airshipError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/base/airships/:airshipId/move', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.json(await airshipService.moveOnDock(
        master.id,
        String(req.params.airshipId),
        req.body?.dockX,
        req.body?.dockY,
        req.body?.rotation,
      ));
    } catch (error) {
      if (airshipError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/base/airships/:airshipId/upgrade', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.json(await airshipService.upgrade(master.id, String(req.params.airshipId)));
    } catch (error) {
      if (airshipError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/base/airships/:airshipId/repair', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.json(await airshipService.repair(master.id, String(req.params.airshipId), Boolean(req.body?.instant)));
    } catch (error) {
      if (airshipError(res, error)) return undefined;
      throw error;
    }
  }));

  app.delete('/api/base/airships/:airshipId', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.json(await airshipService.dismantle(master.id, String(req.params.airshipId)));
    } catch (error) {
      if (airshipError(res, error)) return undefined;
      throw error;
    }
  }));

  app.get('/api/world/heroes/away', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    return res.json(await expeditionService.awayHeroes(master.id));
  }));

  // --- DM-13 (P3): global world, exploration and territories ---

  const worldError = (res: Response, error: unknown): boolean => {
    if (error instanceof WorldError) {
      res.status(error.statusCode).json({ error: error.message });
      return true;
    }
    return false;
  };

  app.get('/api/world/global', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    return res.json(await worldService.status(master.id));
  }));

  app.post('/api/world/global/unlock', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      const continentId = typeof req.body?.continentId === 'string' && req.body.continentId.trim()
        ? req.body.continentId.trim()
        : null;
      const result = await worldService.unlock(master.id, { continentId });
      void auditService.record({
        actorId: master.id, actorType: 'MASTER', action: 'GLOBAL_WORLD_UNLOCKED', entityType: 'WORLD',
        entityId: master.id, diff: { base: result.base, shieldUntil: result.shieldUntil },
      });
      return res.status(201).json(result);
    } catch (error) {
      if (worldError(res, error)) return undefined;
      throw error;
    }
  }));

  app.get('/api/world/global/map', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      const cx = req.query.cx !== undefined ? Number(req.query.cx) : undefined;
      const cy = req.query.cy !== undefined ? Number(req.query.cy) : undefined;
      const radius = req.query.radius !== undefined ? Number(req.query.radius) : undefined;
      return res.json(await worldService.map(master.id, { cx, cy, radius }));
    } catch (error) {
      if (worldError(res, error)) return undefined;
      throw error;
    }
  }));

  app.get('/api/world/global/tiles/:tileId', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.json(await worldService.tile(master.id, String(req.params.tileId)));
    } catch (error) {
      if (worldError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/world/global/tiles/:tileId/discover', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.json(await worldService.discover(master.id, String(req.params.tileId)));
    } catch (error) {
      if (worldError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/world/global/tiles/:tileId/claim', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      const result = await worldService.claim(master.id, String(req.params.tileId));
      void auditService.record({
        actorId: master.id, actorType: 'MASTER', action: 'TERRITORY_CLAIMED', entityType: 'TERRITORY',
        entityId: result.territory.id, diff: { tileId: result.territory.tileId, silverSpent: result.silverSpent },
      });
      return res.status(201).json(result);
    } catch (error) {
      if (worldError(res, error)) return undefined;
      throw error;
    }
  }));

  app.get('/api/world/territories', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    return res.json(await worldService.listTerritories(master.id));
  }));

  app.post('/api/world/territories/:territoryId/upgrade', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.json(await worldService.upgrade(master.id, String(req.params.territoryId)));
    } catch (error) {
      if (worldError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/world/territories/:territoryId/abandon', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.json(await worldService.abandon(master.id, String(req.params.territoryId)));
    } catch (error) {
      if (worldError(res, error)) return undefined;
      throw error;
    }
  }));

  app.get('/api/world/territories/history', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    return res.json(await worldService.history(master.id));
  }));

  app.get('/api/world/leaderboard', requireAccount, asyncRoute(async (_req, res) => {
    return res.json(await worldService.leaderboard());
  }));

  // --- DM-13 (P3): alliances (MOD-13-06) ---

  const allianceError = (res: Response, error: unknown): boolean => {
    if (error instanceof AllianceError) {
      res.status(error.statusCode).json({ error: error.message });
      return true;
    }
    return false;
  };

  const requireMasterOrFail = async (req: AuthRequest, res: Response) => {
    const master = await requireMaster(req);
    if (!master) res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    return master;
  };

  app.use('/api/alliance', requireAccount, asyncRoute(async (req, res, next) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    const [world] = await db.select({ currentFloor: worlds.currentFloor }).from(worlds).where(eq(worlds.masterId, master.id)).limit(1);
    if ((world?.currentFloor ?? 1) <= 25) return res.status(403).json({ error: 'Liên Minh mở sau khi vượt Tháp tầng 25.' });
    return next();
  }));

  app.get('/api/alliance', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    return res.json(await allianceService.overview(master.id));
  }));

  app.get('/api/alliance/search', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    return res.json(await allianceService.search(master.id, {
      query: req.query.query, language: req.query.language,
      minCombatPower: req.query.minCombatPower, hasSlots: req.query.hasSlots,
    }));
  }));

  app.post('/api/alliance', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    try {
      const result = await allianceService.create(master.id, req.body ?? {});
      void auditService.record({
        actorId: master.id, actorType: 'MASTER', action: 'ALLIANCE_CREATED', entityType: 'ALLIANCE',
        entityId: result.alliance?.id ?? master.id, diff: { name: result.alliance?.name, cost: result.cost, currency: result.currencySpent },
      });
      return res.status(201).json(result);
    } catch (error) {
      if (allianceError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/alliance/join', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    try {
      return res.status(201).json(await allianceService.requestJoin(
        master.id, String(req.body?.allianceId ?? ''), req.body?.message,
      ));
    } catch (error) {
      if (allianceError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/alliance/requests/:requestId/cancel', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    try {
      return res.json(await allianceService.cancelRequest(master.id, String(req.params.requestId)));
    } catch (error) {
      if (allianceError(res, error)) return undefined;
      throw error;
    }
  }));

  for (const [path, approve] of [['approve', true], ['reject', false]] as const) {
    app.post(`/api/alliance/requests/:requestId/${path}`, requireAccount, asyncRoute(async (req, res) => {
      const master = await requireMasterOrFail(req, res);
      if (!master) return undefined;
      try {
        return res.json(await allianceService.resolveRequest(master.id, String(req.params.requestId), approve));
      } catch (error) {
        if (allianceError(res, error)) return undefined;
        throw error;
      }
    }));
  }

  app.post('/api/alliance/leave', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    try {
      const result = await allianceService.leave(master.id);
      void auditService.record({
        actorId: master.id, actorType: 'MASTER', action: 'ALLIANCE_LEFT', entityType: 'ALLIANCE',
        entityId: result.allianceId, diff: { disbanded: result.disbanded, cooldownUntil: result.cooldownUntil },
      });
      return res.json(result);
    } catch (error) {
      if (allianceError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/alliance/members/:masterId/manage', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    try {
      return res.json(await allianceService.manage(master.id, String(req.params.masterId), req.body?.action));
    } catch (error) {
      if (allianceError(res, error)) return undefined;
      throw error;
    }
  }));

  app.patch('/api/alliance/notice', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    try {
      return res.json(await allianceService.updateNotice(master.id, req.body?.noticeBoard));
    } catch (error) {
      if (allianceError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/alliance/tech/upgrade', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    try {
      return res.json(await allianceService.upgradeTech(master.id));
    } catch (error) {
      if (allianceError(res, error)) return undefined;
      throw error;
    }
  }));

  app.delete('/api/alliance', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    try {
      return res.json(await allianceService.disband(master.id));
    } catch (error) {
      if (allianceError(res, error)) return undefined;
      throw error;
    }
  }));

  app.get('/api/alliance/chat', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    try {
      return res.json(await allianceService.messages(master.id));
    } catch (error) {
      if (allianceError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/alliance/chat', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    try {
      return res.status(201).json(await allianceService.sendMessage(
        master.id, { body: req.body?.body, coordinates: req.body?.coordinates },
      ));
    } catch (error) {
      if (allianceError(res, error)) return undefined;
      throw error;
    }
  }));

  app.get('/api/chat/stream', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    res.setHeader('Content-Type', 'text/event-stream; charset=utf-8');
    res.setHeader('Cache-Control', 'no-cache, no-transform');
    res.setHeader('Connection', 'keep-alive');
    res.flushHeaders?.();
    res.write(`event: connected\ndata: ${JSON.stringify({ masterId: master.id })}\n\n`);

    const unsubscribe = chatService.subscribe(master.id, payload => {
      if (!res.writableEnded) {
        res.write(`event: message\ndata: ${JSON.stringify(payload)}\n\n`);
      }
    });
    const heartbeat = setInterval(() => {
      if (!res.writableEnded) res.write(': ping\n\n');
    }, 25000);

    req.on('close', () => {
      clearInterval(heartbeat);
      unsubscribe();
    });
    return undefined;
  }));

  app.get('/api/chat/world', requireAccount, asyncRoute(async (_req, res) => {
    return res.json(await chatService.listWorld(50));
  }));

  app.post('/api/chat/world', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    try {
      return res.status(201).json(await chatService.sendWorld(master.id, req.body?.body));
    } catch (error) {
      if (error instanceof ChatError) return res.status(error.statusCode).json({ error: error.message });
      throw error;
    }
  }));

  app.get('/api/chat/private', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    const peer = typeof req.query.peer === 'string' ? req.query.peer : undefined;
    return res.json(await chatService.listPrivate(master.id, peer, 50));
  }));

  app.post('/api/chat/private', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    try {
      return res.status(201).json(await chatService.sendPrivate(master.id, req.body ?? {}));
    } catch (error) {
      if (error instanceof ChatError) return res.status(error.statusCode).json({ error: error.message });
      throw error;
    }
  }));

  // --- Friends System (P2-02) ---

  const friendError = (res: Response, error: unknown): boolean => {
    if (error instanceof FriendError) {
      res.status(error.statusCode).json({ error: error.message });
      return true;
    }
    return false;
  };

  app.get('/api/friends', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    return res.json(await friendService.listFriends(master.id));
  }));

  app.get('/api/friends/requests', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    return res.json(await friendService.listRequests(master.id));
  }));

  app.get('/api/friends/search', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    const q = typeof req.query.q === 'string' ? req.query.q : '';
    return res.json(await friendService.searchMasters(master.id, q));
  }));

  app.post('/api/friends/requests', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    try {
      return res.status(201).json(await friendService.sendRequest(master.id, req.body ?? {}));
    } catch (error) {
      if (friendError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/friends/requests/:requestId/accept', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    try {
      return res.json(await friendService.acceptRequest(master.id, String(req.params.requestId)));
    } catch (error) {
      if (friendError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/friends/requests/:requestId/decline', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    try {
      return res.json(await friendService.declineRequest(master.id, String(req.params.requestId)));
    } catch (error) {
      if (friendError(res, error)) return undefined;
      throw error;
    }
  }));

  app.delete('/api/friends/:friendMasterId', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    try {
      return res.json(await friendService.removeFriend(master.id, String(req.params.friendMasterId)));
    } catch (error) {
      if (friendError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/friends/:friendMasterId/block', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    try {
      return res.json(await friendService.blockMaster(master.id, String(req.params.friendMasterId)));
    } catch (error) {
      if (friendError(res, error)) return undefined;
      throw error;
    }
  }));

  app.delete('/api/friends/:friendMasterId/block', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    try {
      return res.json(await friendService.unblockMaster(master.id, String(req.params.friendMasterId)));
    } catch (error) {
      if (friendError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/friends/gifts/claim-all', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    return res.json(await friendService.claimAllGifts(master.id));
  }));

  app.post('/api/friends/:friendMasterId/gift', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    try {
      return res.status(201).json(await friendService.sendGift(master.id, String(req.params.friendMasterId)));
    } catch (error) {
      if (friendError(res, error)) return undefined;
      throw error;
    }
  }));

  app.get('/api/friends/:friendMasterId/profile', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    try {
      return res.json(await friendService.getPublicProfile(master.id, String(req.params.friendMasterId)));
    } catch (error) {
      if (friendError(res, error)) return undefined;
      throw error;
    }
  }));

  app.get('/api/friends/:friendMasterId/base', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    try {
      return res.json(await friendService.getFriendBase(master.id, String(req.params.friendMasterId)));
    } catch (error) {
      if (friendError(res, error)) return undefined;
      throw error;
    }
  }));

  // --- DM-13 (P3): world war and conquest (MOD-13-07) ---

  const conquestError = (res: Response, error: unknown): boolean => {
    if (error instanceof ConquestError) {
      res.status(error.statusCode).json({ error: error.message });
      return true;
    }
    return false;
  };

  app.get('/api/world/conquest', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    return res.json(await conquestService.overview(master.id));
  }));

  app.get('/api/world/conquest/ranking', requireAccount, asyncRoute(async (req, res) => {
    const seasonId = req.query.seasonId ? String(req.query.seasonId) : undefined;
    const limit = Math.max(1, Math.min(50, Number(req.query.limit) || 10));
    return res.json(await conquestService.ranking(seasonId, limit));
  }));

  app.get('/api/world/conquest/seasons', requireAccount, asyncRoute(async (req, res) => {
    return res.json(await conquestService.seasons());
  }));

  app.post('/api/world/conquest/wonder/siege', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    try {
      const result = await conquestService.siegeWonder(master.id);
      void auditService.record({
        actorId: master.id, actorType: 'MASTER', action: 'WONDER_SIEGED', entityType: 'WONDER',
        entityId: 'imperial-wonder', diff: { won: result.won, attackerPower: result.attackerPower, defenderPower: result.defenderPower },
      });
      return res.json(result);
    } catch (error) {
      if (conquestError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/alliance/wars', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    try {
      const result = await conquestService.declareWar(master.id, String(req.body?.targetAllianceId ?? ''));
      void auditService.record({
        actorId: master.id, actorType: 'MASTER', action: 'ALLIANCE_WAR_DECLARED', entityType: 'ALLIANCE_WAR',
        entityId: result.id, diff: { targetAllianceId: result.targetAllianceId, endsAt: result.endsAt },
      });
      return res.status(201).json(result);
    } catch (error) {
      if (conquestError(res, error)) return undefined;
      throw error;
    }
  }));

  app.get('/api/alliance/wars', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    return res.json(await conquestService.listWars(master.id));
  }));

  app.get('/api/alliance/wars/:warId', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMasterOrFail(req, res);
    if (!master) return undefined;
    try {
      return res.json(await conquestService.warDetail(master.id, String(req.params.warId)));
    } catch (error) {
      if (conquestError(res, error)) return undefined;
      throw error;
    }
  }));

  // --- DM-14 (P2): analytics and customer support ---

  const supportError = (res: Response, error: unknown): boolean => {
    if (error instanceof SupportError) {
      res.status(error.statusCode).json({ error: error.message });
      return true;
    }
    return false;
  };

  app.get('/api/admin/analytics', requireAdminApiKey, asyncRoute(async (_req, res) => {
    return res.json(await analyticsService.summary());
  }));

  app.get('/api/admin/analytics/:section', requireAdminApiKey, asyncRoute(async (req, res) => {
    const section = String(req.params.section);
    const service = new AnalyticsService();
    if (section === 'players') return res.json(await service.players());
    if (section === 'gacha') return res.json(await service.gacha());
    if (section === 'economy') return res.json(await service.economy());
    if (section === 'battle') return res.json(await service.battle());
    if (section === 'retention') return res.json(await service.retention());
    return res.status(404).json({ error: 'Không có nhóm phân tích này.' });
  }));

  app.post('/api/support/tickets', requireAccount, asyncRoute(async (req, res) => {
    try {
      return res.status(201).json(await supportService.create(req.accountId!, req.body?.subject, req.body?.body, req.body?.category));
    } catch (error) {
      if (supportError(res, error)) return undefined;
      throw error;
    }
  }));

  app.get('/api/support/tickets', requireAccount, asyncRoute(async (req, res) => {
    return res.json(await supportService.listForAccount(req.accountId!));
  }));

  app.post('/api/support/tickets/:ticketId/messages', requireAccount, asyncRoute(async (req, res) => {
    try {
      return res.json(await supportService.replyAsPlayer(req.accountId!, String(req.params.ticketId), req.body?.body));
    } catch (error) {
      if (supportError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/giftcodes/redeem', requireAccount, asyncRoute(async (req, res) => {
    const rawCode = String(req.body?.code || '').trim().toUpperCase();
    if (!rawCode) return res.status(400).json({ error: 'Mã quà tặng không được để trống.' });

    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });

    type GiftReward = {
      title: string;
      desc: string;
      gems?: number;
      silver?: number;
      food?: number;
      scrolls?: number;
      materials?: { itemId: string; quantity: number }[];
    };

    const CODES: Record<string, GiftReward> = {
      FULL: {
        title: 'Mã Thử Nghiệm FULL',
        desc: 'Đã nhận toàn bộ tài nguyên tối đa (99M Đá Quý, 999M Vàng, 1M Khẩu Phần, 99K Thiên Thư)!',
        gems: 99999999,
        silver: 999999999,
        food: 1000000,
        scrolls: 99999,
        materials: [
          { itemId: 'WOOD', quantity: 100000 },
          { itemId: 'STONE', quantity: 100000 },
          { itemId: 'IRON_ORE', quantity: 100000 },
          { itemId: 'ENHANCEMENT_STONE', quantity: 50000 },
        ],
      },
      VIP999: {
        title: 'Gói Quà VIP 999',
        desc: '10,000 Đá Quý, 500,000 Vàng, 2,000 Khẩu Phần, 50 Thiên Thư',
        gems: 10000,
        silver: 500000,
        food: 2000,
        scrolls: 50,
      },
      INFINITI2026: {
        title: 'Quà Mừng Năm 2026',
        desc: '5,000 Đá Quý, 200,000 Vàng, 1,000 Khẩu Phần, 20 Thiên Thư',
        gems: 5000,
        silver: 200000,
        food: 1000,
        scrolls: 20,
      },
      FREESUMMON: {
        title: 'Vé Triệu Hồi Tân Thủ',
        desc: '3,000 Đá Quý, 100,000 Vàng, 30 Thiên Thư',
        gems: 3000,
        silver: 100000,
        scrolls: 30,
      },
    };

    const reward = CODES[rawCode];
    if (!reward) {
      return res.status(404).json({ error: `Mã quà tặng "${rawCode}" không tồn tại hoặc đã hết hạn.` });
    }

    const now = new Date();
    await db.transaction(async tx => {
      const deltaGems = BigInt(reward.gems ?? 0);
      const deltaSilver = BigInt(reward.silver ?? 0);

      await tx.update(masters).set({
        gems: sql`${masters.gems} + ${deltaGems}`,
        silverCoins: sql`${masters.silverCoins} + ${deltaSilver}`,
        updatedAt: now,
      }).where(eq(masters.id, master.id));

      if (reward.food && reward.food > 0) {
        const [existingFood] = await tx.select().from(masterItems)
          .where(and(eq(masterItems.masterId, master.id), eq(masterItems.itemId, 'FOOD'))).limit(1);
        if (existingFood) {
          await tx.update(masterItems).set({ quantity: existingFood.quantity + reward.food, updatedAt: now }).where(eq(masterItems.id, existingFood.id));
        } else {
          await tx.insert(masterItems).values({ id: uuidv4(), masterId: master.id, itemId: 'FOOD', quantity: reward.food, updatedAt: now });
        }
      }

      if (reward.materials) {
        for (const mat of reward.materials) {
          const [existingMat] = await tx.select().from(masterItems)
            .where(and(eq(masterItems.masterId, master.id), eq(masterItems.itemId, mat.itemId))).limit(1);
          if (existingMat) {
            await tx.update(masterItems).set({ quantity: existingMat.quantity + mat.quantity, updatedAt: now }).where(eq(masterItems.id, existingMat.id));
          } else {
            await tx.insert(masterItems).values({ id: uuidv4(), masterId: master.id, itemId: mat.itemId, quantity: mat.quantity, updatedAt: now });
          }
        }
      }

      if (reward.scrolls && reward.scrolls > 0) {
        await tx.insert(masterSummonInventory).values({
          id: uuidv4(),
          masterId: master.id,
          scrollType: 'NORMAL',
          quantity: reward.scrolls,
          updatedAt: now,
        }).onConflictDoUpdate({
          target: [masterSummonInventory.masterId, masterSummonInventory.scrollType],
          set: {
            quantity: sql`${masterSummonInventory.quantity} + ${reward.scrolls}`,
            updatedAt: now,
          },
        });
      }
    });

    return res.json({
      success: true,
      code: rawCode,
      title: reward.title,
      message: reward.desc,
      rewards: {
        gems: reward.gems ?? 0,
        silver: reward.silver ?? 0,
        food: reward.food ?? 0,
        scrolls: reward.scrolls ?? 0,
      },
    });
  }));

  app.get('/api/admin/support/tickets', requireAdminApiKey, asyncRoute(async (req, res) => {
    const status = typeof req.query.status === 'string' ? req.query.status : undefined;
    return res.json(await supportService.listForOperators(status));
  }));

  app.get('/api/admin/support/tickets/:ticketId', requireAdminApiKey, asyncRoute(async (req, res) => {
    try {
      return res.json(await supportService.detail(String(req.params.ticketId)));
    } catch (error) {
      if (supportError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/admin/support/tickets/:ticketId/reply', requireAdminApiKey, asyncRoute(async (req, res) => {
    try {
      const result = await supportService.replyAsOperator(String(req.params.ticketId), req.body?.body, adminActor(req));
      void auditService.record({
        actorId: adminActor(req), actorType: 'ADMIN', action: 'SUPPORT_REPLIED', entityType: 'TICKET',
        entityId: String(req.params.ticketId), diff: {},
      });
      return res.json(result);
    } catch (error) {
      if (supportError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/admin/support/tickets/:ticketId/status', requireAdminApiKey, asyncRoute(async (req, res) => {
    try {
      const ticket = await supportService.changeStatus(String(req.params.ticketId), req.body?.status);
      void auditService.record({
        actorId: adminActor(req), actorType: 'ADMIN', action: 'SUPPORT_STATUS_CHANGED', entityType: 'TICKET',
        entityId: ticket.id, diff: { status: ticket.status },
      });
      return res.json(ticket);
    } catch (error) {
      if (supportError(res, error)) return undefined;
      throw error;
    }
  }));

  // --- DM-14 (P2): player administration and content configuration ---

  const operatorError = (res: Response, error: unknown): boolean => {
    if (error instanceof PlayerAdminError || error instanceof ContentAdminError) {
      res.status(error.statusCode).json({ error: error.message });
      return true;
    }
    return false;
  };

  app.get('/api/admin/players', requireAdminApiKey, asyncRoute(async (req, res) => {
    return res.json(await playerAdminService.search(req.query.query));
  }));

  app.get('/api/admin/players/:accountId', requireAdminApiKey, asyncRoute(async (req, res) => {
    try {
      return res.json(await playerAdminService.detail(String(req.params.accountId)));
    } catch (error) {
      if (operatorError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/admin/players/:accountId/restrict', requireAdminApiKey, asyncRoute(async (req, res) => {
    try {
      const result = await playerAdminService.restrict(String(req.params.accountId), req.body?.status, req.body?.reason, adminActor(req));
      void auditService.record({
        actorId: adminActor(req), actorType: 'ADMIN', action: 'PLAYER_RESTRICTED', entityType: 'ACCOUNT',
        entityId: String(req.params.accountId), diff: { status: result.status, reason: result.reason },
      });
      return res.json(result);
    } catch (error) {
      if (operatorError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/admin/players/:accountId/restore', requireAdminApiKey, asyncRoute(async (req, res) => {
    try {
      const result = await playerAdminService.restore(String(req.params.accountId), adminActor(req));
      void auditService.record({
        actorId: adminActor(req), actorType: 'ADMIN', action: 'PLAYER_RESTORED', entityType: 'ACCOUNT',
        entityId: String(req.params.accountId), diff: { status: result.status },
      });
      return res.json(result);
    } catch (error) {
      if (operatorError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/admin/players/:accountId/compensation', requireAdminApiKey, asyncRoute(async (req, res) => {
    try {
      const result = await playerAdminService.compensate(String(req.params.accountId), req.body, req.body?.subject, req.body?.body);
      void auditService.record({
        actorId: adminActor(req), actorType: 'ADMIN', action: 'PLAYER_COMPENSATED', entityType: 'ACCOUNT',
        entityId: String(req.params.accountId), diff: { compensation: result.compensation, messageId: result.messageId },
      });
      return res.status(201).json(result);
    } catch (error) {
      if (operatorError(res, error)) return undefined;
      throw error;
    }
  }));

  app.get('/api/admin/content/heroes', requireAdminApiKey, asyncRoute(async (_req, res) => {
    return res.json(await contentAdminService.listHeroes());
  }));

  app.post('/api/admin/content/heroes', requireAdminApiKey, asyncRoute(async (req, res) => {
    try {
      return res.status(201).json(await contentAdminService.upsertHero(req.body ?? {}));
    } catch (error) {
      if (operatorError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/admin/content/heroes/:code/stats', requireAdminApiKey, asyncRoute(async (req, res) => {
    try {
      return res.json(await contentAdminService.updateHeroStats(String(req.params.code), req.body ?? {}));
    } catch (error) {
      if (operatorError(res, error)) return undefined;
      throw error;
    }
  }));

  app.get('/api/admin/content/hero-skills', requireAdminApiKey, asyncRoute(async (_req, res) => {
    return res.json(await contentAdminService.listHeroSkills());
  }));

  app.post('/api/admin/content/hero-skills', requireAdminApiKey, asyncRoute(async (req, res) => {
    try {
      return res.status(201).json(await contentAdminService.upsertHeroSkill(req.body ?? {}));
    } catch (error) {
      if (operatorError(res, error)) return undefined;
      throw error;
    }
  }));

  app.get('/api/admin/content/enemies', requireAdminApiKey, asyncRoute(async (req, res) => {
    return res.json(await contentAdminService.listEnemies(req.query.boss === 'true'));
  }));

  app.post('/api/admin/content/enemies', requireAdminApiKey, asyncRoute(async (req, res) => {
    try {
      return res.status(201).json(await contentAdminService.upsertEnemy(req.body ?? {}));
    } catch (error) {
      if (operatorError(res, error)) return undefined;
      throw error;
    }
  }));

  app.get('/api/admin/content/items', requireAdminApiKey, asyncRoute(async (_req, res) => {
    return res.json(await contentAdminService.listItems());
  }));

  app.post('/api/admin/content/items', requireAdminApiKey, asyncRoute(async (req, res) => {
    try {
      return res.status(201).json(await contentAdminService.upsertItem(req.body ?? {}));
    } catch (error) {
      if (operatorError(res, error)) return undefined;
      throw error;
    }
  }));

  // --- DM-12 (P2): LiveOps events and dual PVE leaderboards ---

  const liveopsError = (res: Response, error: unknown): boolean => {
    if (error instanceof EventError || error instanceof LeaderboardError) {
      res.status(error.statusCode).json({ error: error.message });
      return true;
    }
    return false;
  };

  app.get('/api/events', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    return res.json(await eventService.forMaster(master.id));
  }));

  app.post('/api/events/missions/:missionId/claim', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.json(await eventService.claimMission(master.id, String(req.params.missionId)));
    } catch (error) {
      if (liveopsError(res, error)) return undefined;
      throw error;
    }
  }));

  app.get('/api/leaderboards', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    const board = req.query.board === 'COMBAT_POWER' ? 'COMBAT_POWER' : 'DUNGEON_PROGRESS';
    return res.json(await leaderboardService.view(board, master.id));
  }));

  app.get('/api/leaderboards/me', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    return res.json(await leaderboardService.combatPowerFor(master.id));
  }));

  app.get('/api/admin/events', requireAdminApiKey, asyncRoute(async (_req, res) => {
    return res.json(await eventService.list());
  }));

  app.post('/api/admin/events', requireAdminApiKey, asyncRoute(async (req, res) => {
    try {
      return res.status(201).json(await eventService.createEvent(req.body ?? {}));
    } catch (error) {
      if (liveopsError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/admin/events/:eventId/missions', requireAdminApiKey, asyncRoute(async (req, res) => {
    try {
      return res.status(201).json(await eventService.addMission(String(req.params.eventId), req.body ?? {}));
    } catch (error) {
      if (liveopsError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/admin/events/:eventId/activate', requireAdminApiKey, asyncRoute(async (req, res) => {
    try {
      const event = await eventService.activate(String(req.params.eventId));
      void auditService.record({
        actorId: adminActor(req), actorType: 'ADMIN', action: 'LIVEOPS_EVENT_ACTIVATED', entityType: 'EVENT',
        entityId: event.id, diff: { code: event.code, type: event.eventType },
      });
      return res.json(event);
    } catch (error) {
      if (liveopsError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/admin/events/:eventId/close', requireAdminApiKey, asyncRoute(async (req, res) => {
    try {
      const event = await eventService.close(String(req.params.eventId));
      void auditService.record({
        actorId: adminActor(req), actorType: 'ADMIN', action: 'LIVEOPS_EVENT_CLOSED', entityType: 'EVENT',
        entityId: event.id, diff: { code: event.code },
      });
      return res.json(event);
    } catch (error) {
      if (liveopsError(res, error)) return undefined;
      throw error;
    }
  }));

  app.get('/api/admin/leaderboards/seasons', requireAdminApiKey, asyncRoute(async (req, res) => {
    const board = req.query.board === 'COMBAT_POWER' ? 'COMBAT_POWER' : req.query.board === 'DUNGEON_PROGRESS' ? 'DUNGEON_PROGRESS' : undefined;
    return res.json(await leaderboardService.seasons(board));
  }));

  app.post('/api/admin/leaderboards/:board/close', requireAdminApiKey, asyncRoute(async (req, res) => {
    const board = req.params.board === 'COMBAT_POWER' ? 'COMBAT_POWER' : 'DUNGEON_PROGRESS';
    try {
      const result = await leaderboardService.closeSeason(board, adminActor(req));
      void auditService.record({
        actorId: adminActor(req), actorType: 'ADMIN', action: 'LEADERBOARD_SEASON_CLOSED', entityType: 'LEADERBOARD',
        entityId: result.seasonId, diff: { board, periodKey: result.periodKey, rewarded: result.rewarded },
      });
      return res.json(result);
    } catch (error) {
      if (liveopsError(res, error)) return undefined;
      throw error;
    }
  }));

  // --- DM-11 (P2): IAP packages, receipts and refunds ---

  const paymentError = (res: Response, error: unknown): boolean => {
    if (error instanceof PaymentError) {
      res.status(error.statusCode).json({ error: error.message });
      return true;
    }
    return false;
  };

  app.get('/api/iap/products', requireAccount, asyncRoute(async (_req, res) => {
    return res.json(await paymentService.products());
  }));

  app.post('/api/iap/checkout', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      const result = await paymentService.checkout(master.id, String(req.body?.productCode ?? ''), String(req.body?.store ?? 'APPLE'));
      void auditService.record({
        actorId: master.id, actorType: 'MASTER', action: 'IAP_CHECKOUT_STARTED', entityType: 'PAYMENT',
        entityId: result.transactionId, diff: { productCode: result.product.code, store: result.store },
      });
      return res.status(201).json(result);
    } catch (error) {
      if (paymentError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/iap/receipt', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      const result = await paymentService.confirmReceipt(master.id, req.body ?? {});
      void auditService.record({
        actorId: master.id, actorType: 'MASTER', action: 'IAP_RECEIPT_CONFIRMED', entityType: 'PAYMENT',
        entityId: result.transactionId, diff: { gemsGranted: result.gemsGranted, gemDebtSettled: result.gemDebtSettled },
      });
      return res.json(result);
    } catch (error) {
      if (paymentError(res, error)) return undefined;
      throw error;
    }
  }));

  app.get('/api/iap/transactions', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    return res.json(await paymentService.history(master.id));
  }));

  app.get('/api/admin/iap/transactions', requireAdminApiKey, asyncRoute(async (_req, res) => {
    return res.json(await paymentService.allTransactions());
  }));

  app.post('/api/admin/iap/refund', requireAdminApiKey, asyncRoute(async (req, res) => {
    try {
      const result = await paymentService.refund(String(req.body?.transactionId ?? ''), req.body?.reason);
      void auditService.record({
        actorId: adminActor(req), actorType: 'ADMIN', action: 'IAP_REFUNDED', entityType: 'PAYMENT',
        entityId: result.transactionId, diff: { gemsClawedBack: result.gemsClawedBack, gemDebtAdded: result.gemDebtAdded },
      });
      return res.json(result);
    } catch (error) {
      if (paymentError(res, error)) return undefined;
      throw error;
    }
  }));

  // --- DM-01 (P1): account linking and recovery ---

  const accountError = (res: Response, error: unknown): boolean => {
    if (error instanceof AccountError) {
      res.status(error.statusCode).json({ error: error.message });
      return true;
    }
    return false;
  };

  app.get('/api/account/identities', requireAccount, asyncRoute(async (req, res) => {
    return res.json(await accountLinkService.identities(req.accountId!));
  }));

  app.post('/api/account/identities', requireAccount, asyncRoute(async (req, res) => {
    try {
      const linked = await accountLinkService.link(req.accountId!, req.body?.provider, req.body?.providerUserId, req.body?.providerToken);
      void auditService.record({
        actorId: req.accountId!, actorType: 'PLAYER', action: 'ACCOUNT_LINKED', entityType: 'ACCOUNT',
        entityId: req.accountId!, diff: { provider: linked.provider },
      });
      return res.status(201).json(linked);
    } catch (error) {
      if (accountError(res, error)) return undefined;
      throw error;
    }
  }));

  app.delete('/api/account/identities/:provider', requireAccount, asyncRoute(async (req, res) => {
    try {
      const result = await accountLinkService.unlink(req.accountId!, String(req.params.provider));
      void auditService.record({
        actorId: req.accountId!, actorType: 'PLAYER', action: 'ACCOUNT_UNLINKED', entityType: 'ACCOUNT',
        entityId: req.accountId!, diff: { provider: result.unlinked },
      });
      return res.json(result);
    } catch (error) {
      if (accountError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/account/recovery-token', requireAccount, asyncRoute(async (req, res) => {
    try {
      const issued = await accountLinkService.issueRecoveryToken(req.accountId!);
      void auditService.record({
        actorId: req.accountId!, actorType: 'PLAYER', action: 'RECOVERY_TOKEN_ISSUED', entityType: 'ACCOUNT',
        entityId: req.accountId!, diff: {},
      });
      return res.status(201).json(issued);
    } catch (error) {
      if (accountError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/auth/recover', asyncRoute(async (req, res) => {
    try {
      const result = await accountLinkService.recover(req.body?.username, req.body?.recoveryToken, req.body?.newPassword);
      void auditService.record({
        actorId: String(req.body?.username ?? ''), actorType: 'PLAYER', action: 'ACCOUNT_RECOVERED',
        entityType: 'ACCOUNT', entityId: String(req.body?.username ?? ''), diff: {},
      });
      return res.json(result);
    } catch (error) {
      if (accountError(res, error)) return undefined;
      throw error;
    }
  }));

  // --- DM-12 (P1): quests and achievements ---

  const questError = (res: Response, error: unknown): boolean => {
    if (error instanceof QuestError) {
      res.status(error.statusCode).json({ error: error.message });
      return true;
    }
    return false;
  };

  app.get('/api/quests', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    return res.json(await questService.overview(master.id));
  }));

  app.post('/api/quests/:code/accept', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.status(201).json(await questService.accept(master.id, String(req.params.code)));
    } catch (error) {
      if (questError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/quests/:code/claim', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      const result = await questService.claimQuest(master.id, String(req.params.code));
      void auditService.record({
        actorId: master.id, actorType: 'MASTER', action: 'QUEST_REWARD_CLAIMED', entityType: 'QUEST',
        entityId: String(req.params.code), diff: { reward: result.reward },
      });
      return res.json(result);
    } catch (error) {
      if (questError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/achievements/:code/claim', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      const result = await questService.claimAchievement(master.id, String(req.params.code));
      void auditService.record({
        actorId: master.id, actorType: 'MASTER', action: 'ACHIEVEMENT_CLAIMED', entityType: 'ACHIEVEMENT',
        entityId: String(req.params.code), diff: { reward: result.reward },
      });
      return res.json(result);
    } catch (error) {
      if (questError(res, error)) return undefined;
      throw error;
    }
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
      void questService.recordEvent(master.id, 'CRAFT_ITEM', 1).catch(error => console.error('[quest] craft progress failed', error));
      void eventService.recordEvent(master.id, 'CRAFT_ITEM', 1).catch(error => console.error('[liveops] craft progress failed', error));
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

  app.use('/api/shop', requireAccount, asyncRoute(async (req, res, next) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    const [world] = await db.select({ currentFloor: worlds.currentFloor }).from(worlds).where(eq(worlds.masterId, master.id)).limit(1);
    if ((world?.currentFloor ?? 1) <= 5) return res.status(403).json({ error: 'Thương Thuyền mở sau khi vượt Tháp tầng 5.' });
    return next();
  }));

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
      const result = await shopService.purchase(master.id, String(req.body?.itemCode ?? ''), req.body?.quantity, new Date(), req.get('Idempotency-Key'));
      if (!result.replayed) {
        void questService.recordEvent(master.id, 'SPEND_SILVER', result.silverSpent).catch(error => console.error('[quest] spend progress failed', error));
        void eventService.recordEvent(master.id, 'SPEND_SILVER', result.silverSpent).catch(error => console.error('[liveops] spend progress failed', error));
        void auditService.record({
          actorId: master.id, actorType: 'MASTER', action: 'SHOP_PURCHASE', entityType: 'SHOP_ITEM',
          entityId: String(req.body?.itemCode ?? ''), diff: { purchased: result.purchased, silverSpent: result.silverSpent },
      });
      }
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

  app.post('/api/medical/treatments/batch', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      const heroIds = Array.isArray(req.body?.heroIds) ? req.body.heroIds.map(String) : [];
      return res.status(200).json(await medicalService.batchAdmit(master.id, heroIds));
    } catch (error) {
      if (medicalError(res, error)) return undefined;
      throw error;
    }
  }));

  app.delete('/api/medical/treatments/:heroId', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.json(await medicalService.cancelTreatment(master.id, String(req.params.heroId ?? '')));
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

  app.post('/api/medical/emergency/batch', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      const heroIds = Array.isArray(req.body?.heroIds) ? req.body.heroIds.map(String) : [];
      return res.json(await medicalService.batchEmergency(master.id, heroIds));
    } catch (error) {
      if (medicalError(res, error)) return undefined;
      throw error;
    }
  }));

  app.get('/api/chronicles/heroes', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    return res.json(await heroChronicleService.list(master.id, String(req.query.status ?? ''), Number(req.query.page ?? 1)));
  }));

  app.get('/api/chronicles/heroes/:id', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try { return res.json(await heroChronicleService.detail(master.id, String(req.params.id))); }
    catch (error) { if (medicalError(res, error)) return undefined; throw error; }
  }));

  app.post('/api/chronicles/heroes/:id/resurrect', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      const result = await heroChronicleService.resurrect(master.id, String(req.params.id));
      void auditService.record({ actorId: master.id, actorType: 'MASTER', action: 'HERO_RESURRECTED',
        entityType: 'HERO', entityId: result.heroId, diff: { gemsUsed: result.gemsUsed, silverSpent: result.silverSpent } });
      return res.json(result);
    }
    catch (error) { if (medicalError(res, error)) return undefined; throw error; }
  }));

  app.post('/api/medical/resurrect', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      const result = await medicalService.resurrect(master.id, String(req.body?.heroId ?? ''));
      void auditService.record({
        actorId: master.id, actorType: 'MASTER', action: 'HERO_RESURRECTED',
        entityType: 'HERO', entityId: result.heroId,
        diff: { gemsUsed: result.gemsUsed, silverSpent: result.silverSpent },
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
      const buildingId = req.body && typeof req.body === 'object' && (req.body as { buildingId?: unknown }).buildingId
        ? String((req.body as { buildingId?: unknown }).buildingId)
        : null;
      return res.json(await survivalService.setResting(master.id, String(req.params.heroId), true, buildingId));
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

  app.post('/api/survival/housing/:buildingId/assign', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.json(await survivalService.assignHousing(
        master.id,
        String(req.params.buildingId),
        String(req.body?.heroId ?? ''),
        req.body?.swapWithHeroId ? String(req.body.swapWithHeroId) : null,
      ));
    } catch (error) {
      if (survivalError(res, error)) return undefined;
      throw error;
    }
  }));

  app.delete('/api/survival/housing/heroes/:heroId', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.json(await survivalService.removeHousing(master.id, String(req.params.heroId)));
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

  app.use('/api/base/buildings/:buildingId', requireAccount, asyncRoute(async (req, res, next) => {
    if (req.method === 'DELETE' || req.path === '/demolish') return next();
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    const [[building], [world]] = await Promise.all([
      db.select({ type: baseBuildings.buildingType }).from(baseBuildings)
        .where(and(eq(baseBuildings.id, String(req.params.buildingId)), eq(baseBuildings.masterId, master.id))).limit(1),
      db.select({ currentFloor: worlds.currentFloor }).from(worlds).where(eq(worlds.masterId, master.id)).limit(1),
    ]);
    const requiredFloor = building ? requiredTowerFloorForBuilding(building.type) : 0;
    if ((world?.currentFloor ?? 1) - 1 < requiredFloor) {
      return res.status(403).json({ error: `Cần vượt Tháp tầng ${requiredFloor} để sử dụng công trình.` });
    }
    return next();
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
        void questService.recordEvent(master.id, 'COLLECT_RESOURCE', result.collected).catch(error => console.error('[quest] collect progress failed', error));
        void eventService.recordEvent(master.id, 'COLLECT_RESOURCE', result.collected).catch(error => console.error('[liveops] collect progress failed', error));
      }
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

  app.post('/api/base/buildings/:buildingId/mage-study', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    try {
      return res.json(await buildingService.studyMageInLibrary(master.id, String(req.params.buildingId), req.body?.heroId, req.body?.hours));
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
    const aliveOnly = String(req.query.aliveOnly ?? '').toLowerCase() === 'true';
    const collection = await db.select().from(heroes)
      .where(aliveOnly
        ? and(eq(heroes.masterId, master.id), gt(heroes.hp, 0), sql`${heroes.state} NOT IN ('DEAD', 'DISABLED')`)
        : eq(heroes.masterId, master.id))
      .orderBy(desc(heroes.rarity), heroes.name);
    const survivalRows = collection.length ? await db.select().from(heroSurvivalStates).where(inArray(heroSurvivalStates.heroId, collection.map(hero => hero.id))) : [];
    const survivalByHero = new Map(survivalRows.map(row => [row.heroId, row]));
    const [foodRow] = await db.select({ quantity: masterItems.quantity }).from(masterItems)
      .where(and(eq(masterItems.masterId, master.id), eq(masterItems.itemId, 'FOOD'))).limit(1);
    const hasFood = (foodRow?.quantity ?? 0) > 0;
    const survivalNow = new Date();
    const deployments = collection.length ? await db.select({ heroId: pveHeroReservations.heroId, squadId: pveSquads.id,
      mapId: pveSquads.mapId, name: pveSquads.name }).from(pveHeroReservations)
      .innerJoin(pveSquads, eq(pveSquads.id, pveHeroReservations.squadId)).where(eq(pveHeroReservations.masterId, master.id)) : [];
    const deploymentByHero = new Map(deployments.map(deployment => [deployment.heroId, deployment]));
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
    const itemsByHero = new Map<string, EquipmentItemInput[]>();
    for (const row of equipped) {
      if (!row.item.equippedHeroId) continue;
      const bonus = bonuses.get(row.item.equippedHeroId) ?? { hp: 0, attack: 0, defense: 0, speed: 0 };
      bonus.hp += row.template.bonusHp; bonus.attack += row.template.bonusAttack;
      bonus.defense += row.template.bonusDefense; bonus.speed += row.template.bonusSpeed;
      bonuses.set(row.item.equippedHeroId, bonus);

      const list = itemsByHero.get(row.item.equippedHeroId) ?? [];
      list.push({
        slotType: row.template.slotType,
        bonusHp: row.template.bonusHp,
        bonusAttack: row.template.bonusAttack,
        bonusDefense: row.template.bonusDefense,
        bonusSpeed: row.template.bonusSpeed,
        bonusStr: row.template.bonusStr,
        bonusInt: row.template.bonusInt,
        bonusSta: row.template.bonusSta,
        bonusAgi: row.template.bonusAgi,
        bonusMatk: row.template.bonusMatk,
        bonusMdef: row.template.bonusMdef,
        v2Stats: (row.template.v2Stats as EquipmentV2Stats) ?? null,
        statMultiplier: row.item.statMultiplier ?? 1,
        substats: (row.item.substats as EquipmentV2Stats) ?? null,
      });
      itemsByHero.set(row.item.equippedHeroId, list);
    }
    const imprintRows = collection.length ? await db.select({ owned: heroImprints, definition: imprintDefinitions })
      .from(heroImprints).innerJoin(imprintDefinitions, eq(imprintDefinitions.code, heroImprints.imprintCode))
      .where(inArray(heroImprints.heroId, collection.map(hero => hero.id))) : [];
    const imprintByHero = new Map<string, { str: number; int: number; sta: number; agi: number }>();
    for (const row of imprintRows) {
      const prev = imprintByHero.get(row.owned.heroId) ?? { str: 0, int: 0, sta: 0, agi: 0 };
      prev.str += row.definition.bonusStr;
      prev.int += row.definition.bonusInt;
      prev.sta += row.definition.bonusSta;
      prev.agi += row.definition.bonusAgi;
      imprintByHero.set(row.owned.heroId, prev);
    }
    const affinityRows = collection.length ? await db.select().from(heroElementAffinities)
      .where(inArray(heroElementAffinities.heroId, collection.map(hero => hero.id))) : [];
    const affinityByHero = new Map(affinityRows.map(row => [row.heroId, heroAffinity(row)]));
    return res.json(collection.map(hero => {
      const template = templateByCode.get(hero.configId);
      const effectiveClass = (hero.classCode && hero.classCode !== 'UNCLASSIFIED') ? hero.classCode : (template?.heroClass ?? 'UNCLASSIFIED');
      const legacyCls = legacyClassFor(effectiveClass as HeroClass);
      const skills = skillTemplates.filter(skill =>
        skill.heroClass === effectiveClass
        || skill.heroClass === legacyCls
        || (template?.heroClass && skill.heroClass === template.heroClass)
      ).map(skill => {
        const instance = skillByHeroAndCode.get(`${hero.id}:${skill.code}`);
        return { ...skill, skillLevel: instance?.skillLevel ?? 1, isUnlocked: instance?.isUnlocked ?? false, behaviorMode: instance?.behaviorMode ?? 'AUTO', canUnlock: hero.level >= skill.unlockLevel && hero.state !== 'DEAD' && hero.state !== 'DISABLED', skillEffectValue: skill.effectValue + ((instance?.skillLevel ?? 1) - 1) * skill.upgradeIncrement };
      });
      const isV2 = isV2Origin(hero.originStats);
      let derivedStats = { hp: hero.hp, maxHp: hero.maxHp, attack: hero.attack, defense: hero.defense, speed: hero.speed };
      let v2Stats: any = undefined;
      let effectiveBaseStats: any = undefined;

      if (isV2) {
        const heroGear = itemsByHero.get(hero.id) ?? [];
        const aggregatedGear = aggregateEquipment(heroGear);
        const heroImprint = imprintByHero.get(hero.id) ?? { str: 0, int: 0, sta: 0, agi: 0 };
        const snapshot = progressionFor({
          origin: originOf(hero.originStats),
          star: hero.rarity as StarRating,
          level: hero.level,
          classCode: hero.classCode as HeroClass,
          training: hero.trainingStats,
          awakeningRank: hero.awakeningRank,
          imprint: heroImprint,
          equipmentBase: aggregatedGear.baseStats,
          equipmentOffsets: aggregatedGear.derivedOffsets,
          hpPct: hero.currentHpPct,
          mpPct: hero.currentMpPct,
        });
        derivedStats = {
          hp: snapshot.hp,
          maxHp: snapshot.maxHp,
          attack: snapshot.attack,
          defense: snapshot.defense,
          speed: snapshot.speed,
        };
        v2Stats = snapshot.derived;
        effectiveBaseStats = snapshot.base;
      } else {
        const bonus = bonuses.get(hero.id) ?? { hp: 0, attack: 0, defense: 0, speed: 0 };
        derivedStats = {
          hp: Math.min(hero.hp, hero.maxHp + bonus.hp),
          maxHp: hero.maxHp + bonus.hp,
          attack: hero.attack + bonus.attack,
          defense: hero.defense + bonus.defense,
          speed: hero.speed + bonus.speed,
        };
      }

      if (hero.state === 'DEAD' || hero.state === 'DISABLED' || hero.hp <= 0) derivedStats.hp = 0;
      const elementAffinities = affinityByHero.get(hero.id) ?? (
        effectiveClass === 'MAGE'
          ? { FIRE: 60, WATER: 45, WIND: 40, EARTH: 35, LIGHT: 50, DARK: 30, LIGHTNING: 55 }
          : null
      );
      const strongestElement = elementAffinities
        ? Object.entries(elementAffinities).sort((a, b) => Number(b[1]) - Number(a[1]))[0]?.[0]
        : undefined;

      const survivalState = survivalByHero.get(hero.id);
      const drift = applyDrift(
        survivalState ?? { hungerScore: hero.hunger, fatigueScore: hero.fatigue, isResting: false, lastTickAt: survivalNow },
        survivalNow,
        hasFood,
      );
      const effectiveResting = survivalState?.isResting
        ? (survivalState.fatigueScore <= 0 ? true : drift.isResting)
        : false;

      return {
        ...hero,
        hunger: drift.hungerScore,
        fatigue: drift.fatigueScore,
        isResting: effectiveResting,
        housingBuildingId: survivalState?.housingBuildingId ?? null,
        pveDeployment: deploymentByHero.get(hero.id) ?? null,
        heroClass: effectiveClass, element: strongestElement ?? template?.element ?? 'NEUTRAL', exp: hero.exp.toString(),
        nextLevelExp: expThresholdByLevel.get(hero.level + 1) ?? null,
        currentLevelExp: expThresholdByLevel.get(hero.level) ?? '0',
        maxLevel: heroEffectiveMaxLevel(hero.rarity, hero.promotionRank),
        starCeiling: starMaxLevel(hero.rarity),
        breakthroughCap: breakthroughMaxLevel(hero.promotionRank),
        skills,
        classChangeOptions: isV2 ? eligibleClasses({str:hero.baseStr,int:hero.baseInt,sta:hero.baseSta,agi:hero.baseAgi},hero.level,hero.rarity as StarRating) : [],
        derivedStats,
        elementAffinities,
        ...(v2Stats ? { v2Stats, effectiveBaseStats } : {}),
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
    const allowedClasses = Array.from(new Set([
      hero.classCode,
      legacyClassFor(hero.classCode as HeroClass),
      ...(heroTemplate?.heroClass ? [heroTemplate.heroClass] : []),
    ])).filter(Boolean);
    const [template] = allowedClasses.length ? await db.select().from(heroSkillTemplates)
      .where(and(eq(heroSkillTemplates.code, String(req.params.skillCode)), inArray(heroSkillTemplates.heroClass, allowedClasses), eq(heroSkillTemplates.isActive, true))).limit(1) : [];
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
      const allowedClasses = Array.from(new Set([
        hero.classCode,
        legacyClassFor(hero.classCode as HeroClass),
        ...(heroTemplate?.heroClass ? [heroTemplate.heroClass] : []),
      ])).filter(Boolean);
      const [template] = allowedClasses.length ? await tx.select().from(heroSkillTemplates).where(and(eq(heroSkillTemplates.code, String(req.params.skillCode)), inArray(heroSkillTemplates.heroClass, allowedClasses), eq(heroSkillTemplates.isActive, true))).limit(1) : [];
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

  const EXP_BOOK_VALUES: Record<string, bigint> = {
    SAMPLE_HERO_EXP_100: 1000n,
    SAMPLE_HERO_EXP_1000: 100000n,
    SAMPLE_HERO_EXP_10000: 10000000n,
  };

  app.post('/api/heroes/:heroId/level-up', requireAccount, requireFeature('HERO_COLLECTION'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    const requestedQuantity = Math.max(1, parseInt(String(req.body?.quantity ?? req.body?.amount ?? 1), 10) || 1);
    const toMax = Boolean(req.body?.toMax);
    const bookItemId = String(req.body?.bookItemId ?? 'SAMPLE_HERO_EXP_100');
    const expPerBook = EXP_BOOK_VALUES[bookItemId] ?? 100n;
    const result = await db.transaction(async tx => {
      const [hero] = await tx.select().from(heroes).where(and(eq(heroes.id, String(req.params.heroId)), eq(heroes.masterId, master.id))).for('update').limit(1);
      if (!hero) return { status: 404, error: 'Hero not found.' } as const;
      if (hero.isLocked) return { status: 409, error: 'Hero is locked.' } as const;
      if (hero.state === 'DEAD') return { status: 409, error: 'ERR_HERO_PERMANENTLY_DEAD' } as const;
      if (hero.state === 'DISABLED' || hero.hp <= 0) return { status: 409, error: 'Hero is not available for development.' } as const;
      const heroLevelCap = heroEffectiveMaxLevel(hero.rarity, hero.promotionRank);
      if (hero.level >= heroLevelCap) return { status: 409, error: 'Hero is already at the configured level cap.' } as const;
      const [material] = await tx.select().from(masterItems).where(and(eq(masterItems.masterId, master.id), eq(masterItems.itemId, bookItemId))).for('update').limit(1);
      if (!material || material.quantity < 1) return { status: 409, error: `Not enough ${bookItemId}.` } as const;

      const growthConfigs = await tx.select().from(heroLevelConfigs).where(and(gt(heroLevelConfigs.level, hero.level), lte(heroLevelConfigs.level, heroLevelCap))).orderBy(heroLevelConfigs.level);
      if (!growthConfigs.length) return { status: 409, error: 'Hero is already at the configured level cap.' } as const;

      let booksToUse = requestedQuantity;
      if (toMax) {
        const targetConfig = growthConfigs[growthConfigs.length - 1];
        const neededExp = BigInt(targetConfig.cumulativeExpRequired) - BigInt(hero.exp);
        const neededBooks = neededExp > 0n ? Number((neededExp + expPerBook - 1n) / expPerBook) : 1;
        booksToUse = Math.max(1, Math.min(material.quantity, neededBooks));
      } else {
        booksToUse = Math.min(material.quantity, requestedQuantity);
      }

      const totalExp = BigInt(hero.exp) + BigInt(booksToUse) * expPerBook;
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
      const isV2 = isV2Origin(hero.originStats);
      const imprintBonus = isV2 ? await imprintStatsFor(tx, hero.id) : { str: 0, int: 0, sta: 0, agi: 0 };
      await tx.update(masterItems).set({ quantity: material.quantity - booksToUse, updatedAt: new Date() }).where(eq(masterItems.id, material.id));
      const updateValues = isV2
        ? (() => {
          const snapshot = progressionFor({
            origin: originOf(hero.originStats),
            star: hero.rarity as StarRating,
            level,
            classCode: hero.classCode as HeroClass,
            training: hero.trainingStats,
            awakeningRank: hero.awakeningRank,
            imprint: imprintBonus,
            hpPct: hero.currentHpPct,
            mpPct: hero.currentMpPct,
          });
          return {
            exp: totalExp, level,
            baseStr: snapshot.base.str, baseInt: snapshot.base.int,
            baseSta: snapshot.base.sta, baseAgi: snapshot.base.agi,
            maxHp: snapshot.maxHp, hp: snapshot.hp,
            attack: snapshot.attack, defense: snapshot.defense, speed: snapshot.speed,
            mp: snapshot.mp, maxMp: snapshot.maxMp,
            updatedAt: new Date(),
          };
        })()
        : { exp: totalExp, level, maxHp, hp, attack, defense, speed, updatedAt: new Date() };
      const [updated] = await tx.update(heroes).set(updateValues).where(eq(heroes.id, hero.id)).returning();
      return { status: 200, hero: { id: updated.id, level: updated.level, maxLevel: heroLevelCap, exp: updated.exp.toString(), hp: updated.hp, maxHp: updated.maxHp, attack: updated.attack, defense: updated.defense, speed: updated.speed }, bookItemId, booksUsed: booksToUse, materialQuantity: material.quantity - booksToUse } as const;
    });
    if (result.status !== 200) return res.status(result.status).json({ error: result.error });
    return res.json(result);
  }));

  const imprintStatsFor = async (tx: Parameters<Parameters<typeof db.transaction>[0]>[0], heroId: string) => {
    const rows = await tx.select({ owned: heroImprints, definition: imprintDefinitions })
      .from(heroImprints).innerJoin(imprintDefinitions, eq(imprintDefinitions.code, heroImprints.imprintCode))
      .where(eq(heroImprints.heroId, heroId));
    return rows.reduce((sum, row) => ({
      str: sum.str + row.definition.bonusStr,
      int: sum.int + row.definition.bonusInt,
      sta: sum.sta + row.definition.bonusSta,
      agi: sum.agi + row.definition.bonusAgi,
    }), { str: 0, int: 0, sta: 0, agi: 0 });
  };

  const progressionError = (res: Response, error: unknown): boolean => {
    if (error instanceof ProgressionError) {
      res.status(error.statusCode).json({ error: error.message });
      return true;
    }
    return false;
  };

  const heroAffinity = (row: { fire: number; water: number; wind: number; earth: number; light: number; dark: number; lightning: number }) => ({
    FIRE: row.fire, WATER: row.water, WIND: row.wind, EARTH: row.earth,
    LIGHT: row.light, DARK: row.dark, LIGHTNING: row.lightning,
  });

  app.post('/api/heroes/:heroId/train', requireAccount, requireFeature('HERO_COLLECTION'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    try {
      const result = await db.transaction(async tx => {
        const [hero] = await tx.select().from(heroes)
          .where(and(eq(heroes.id, String(req.params.heroId)), eq(heroes.masterId, master.id))).for('update').limit(1);
        if (!hero) throw new ProgressionError('ERR_HERO_NOT_FOUND', 404);
        if (hero.isLocked) throw new ProgressionError('ERR_HERO_LOCKED', 409);
        if (hero.state === 'DEAD') throw new ProgressionError('ERR_HERO_PERMANENTLY_DEAD', 409);
        if (hero.state === 'DISABLED' || hero.hp <= 0) throw new ProgressionError('ERR_HERO_UNAVAILABLE', 409);
        if (!isV2Origin(hero.originStats)) throw new ProgressionError('ERR_HERO_V2_REQUIRED', 409);

        const { snapshot, training } = allocateTraining({
          origin: originOf(hero.originStats),
          star: hero.rarity as StarRating,
          level: hero.level,
          classCode: hero.classCode as HeroClass,
          training: hero.trainingStats,
          stat: String(req.body?.stat ?? ''),
          points: Number(req.body?.points ?? 0),
          hpPct: hero.currentHpPct,
          mpPct: hero.currentMpPct,
        });

        const [updated] = await tx.update(heroes).set({
          trainingStats: training,
          baseStr: snapshot.base.str, baseInt: snapshot.base.int,
          baseSta: snapshot.base.sta, baseAgi: snapshot.base.agi,
          maxHp: snapshot.maxHp, hp: snapshot.hp,
          attack: snapshot.attack, defense: snapshot.defense, speed: snapshot.speed,
          mp: snapshot.mp, maxMp: snapshot.maxMp,
          updatedAt: new Date(),
        }).where(eq(heroes.id, hero.id)).returning();

        return {
          heroId: updated.id, level: updated.level,
          base: snapshot.base, derived: snapshot.derived, training,
          trainingRemaining: snapshot.trainingRemaining,
          stats: { hp: updated.hp, maxHp: updated.maxHp, attack: updated.attack, defense: updated.defense, speed: updated.speed },
        };
      });
      return res.json(result);
    } catch (error) {
      if (progressionError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/heroes/:heroId/class-change', requireAccount, requireFeature('HERO_COLLECTION'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    try {
      const result = await db.transaction(async tx => {
        const [masterRow] = await tx.select().from(masters).where(eq(masters.id, master.id)).for('update').limit(1);
        const [hero] = await tx.select().from(heroes)
          .where(and(eq(heroes.id, String(req.params.heroId)), eq(heroes.masterId, master.id))).for('update').limit(1);
        if (!hero || !masterRow) throw new ProgressionError('ERR_HERO_NOT_FOUND', 404);
        if (hero.isLocked) throw new ProgressionError('ERR_HERO_LOCKED', 409);
        if (hero.state === 'DEAD') throw new ProgressionError('ERR_HERO_PERMANENTLY_DEAD', 409);
        if (hero.state === 'DISABLED' || hero.hp <= 0) throw new ProgressionError('ERR_HERO_UNAVAILABLE', 409);
        if (!isV2Origin(hero.originStats)) throw new ProgressionError('ERR_HERO_V2_REQUIRED', 409);

        const targetClass = String(req.body?.targetClass ?? '').toUpperCase();
        const currentBase = originOf({
          str: hero.baseStr, int: hero.baseInt, sta: hero.baseSta, agi: hero.baseAgi,
        });
        const [item] = await tx.select().from(masterItems).where(and(
          eq(masterItems.masterId, master.id), eq(masterItems.itemId, CLASS_CHANGE_ITEM),
        )).for('update').limit(1);

        const check = classChangeCheck({
          level: hero.level,
          star: hero.rarity as StarRating,
          base: currentBase,
          currentClass: hero.classCode as HeroClass,
          targetClass,
          silver: masterRow.silverCoins,
          itemQuantity: item?.quantity ?? 0,
        });
        if (!check.ok) throw new ProgressionError(check.reason ?? 'ERR_CLASS_NOT_ELIGIBLE', 409);

        const snapshot = progressionFor({
          origin: originOf(hero.originStats),
          star: hero.rarity as StarRating,
          level: hero.level,
          classCode: targetClass as HeroClass,
          training: hero.trainingStats,
          awakeningRank: hero.awakeningRank,
          imprint: await imprintStatsFor(tx, hero.id),
          hpPct: hero.currentHpPct,
          mpPct: hero.currentMpPct,
        });

        await tx.update(masters).set({
          silverCoins: sql`${masters.silverCoins} - ${CLASS_CHANGE_SILVER}`, updatedAt: new Date(),
        }).where(eq(masters.id, master.id));
        await tx.update(masterItems).set({
          quantity: item!.quantity - 1, updatedAt: new Date(),
        }).where(eq(masterItems.id, item!.id));

        let affinity = null;
        if (targetClass === 'MAGE') {
          const [existing] = await tx.select().from(heroElementAffinities)
            .where(eq(heroElementAffinities.heroId, hero.id)).limit(1);
          if (existing) {
            affinity = heroAffinity(existing);
          } else {
            const rolled = rollElementAffinity();
            await tx.insert(heroElementAffinities).values({
              heroId: hero.id,
              fire: rolled.FIRE, water: rolled.WATER, wind: rolled.WIND, earth: rolled.EARTH,
              light: rolled.LIGHT, dark: rolled.DARK, lightning: rolled.LIGHTNING,
              updatedAt: new Date(),
            });
            affinity = rolled;
          }
        } else {
          await tx.delete(heroElementAffinities).where(eq(heroElementAffinities.heroId, hero.id));
        }

        const [updated] = await tx.update(heroes).set({
          classCode: targetClass,
          combatRole: roleForClass(targetClass as HeroClass),
          baseStr: snapshot.base.str, baseInt: snapshot.base.int,
          baseSta: snapshot.base.sta, baseAgi: snapshot.base.agi,
          maxHp: snapshot.maxHp, hp: snapshot.hp,
          attack: snapshot.attack, defense: snapshot.defense, speed: snapshot.speed,
          mp: snapshot.mp, maxMp: snapshot.maxMp,
          updatedAt: new Date(),
        }).where(eq(heroes.id, hero.id)).returning();

        return {
          heroId: updated.id,
          previousClass: hero.classCode,
          classCode: updated.classCode,
          combatRole: updated.combatRole,
          base: snapshot.base,
          derived: snapshot.derived,
          affinity,
          cost: { silver: CLASS_CHANGE_SILVER, item: CLASS_CHANGE_ITEM, quantity: 1 },
          stats: { hp: updated.hp, maxHp: updated.maxHp, attack: updated.attack, defense: updated.defense, speed: updated.speed },
        };
      });
      void auditService.record({
        actorId: master.id, actorType: 'MASTER', action: 'HERO_CLASS_CHANGED', entityType: 'HERO',
        entityId: result.heroId, diff: { from: result.previousClass, to: result.classCode, cost: result.cost },
      });
      return res.json(result);
    } catch (error) {
      if (progressionError(res, error)) return undefined;
      throw error;
    }
  }));

  const previewBreakthrough = async (req: any, res: Response) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    const [hero] = await db.select().from(heroes).where(and(eq(heroes.id, String(req.params.heroId)), eq(heroes.masterId, master.id))).limit(1);
    if (!hero) return res.status(404).json({ error: 'Hero not found.' });

    const currentRank = hero.promotionRank ?? 0;
    const nextRank = currentRank + 1;
    const isMax = currentRank >= 6;

    const [config] = await db.select().from(heroDevelopmentConfigs)
      .where(and(eq(heroDevelopmentConfigs.action, 'PROMOTION'), eq(heroDevelopmentConfigs.rank, nextRank))).limit(1);

    const requiredHeroLevel = config?.requiredHeroLevel ?? (nextRank * 10);
    const requiredStar = nextRank + 1;
    const materialItemId = config?.materialItemId ?? 'SAMPLE_HERO_PROMOTION_SEAL';
    const materialQuantity = config?.materialQuantity ?? (nextRank * 5);
    const silverCost = BREAKTHROUGH_SILVER_COST[nextRank] ?? (nextRank * 10_000);

    const [material] = await db.select().from(masterItems)
      .where(and(eq(masterItems.masterId, master.id), eq(masterItems.itemId, materialItemId))).limit(1);
    const currentMaterialCount = material?.quantity ?? 0;

    const meetsLevel = hero.level >= requiredHeroLevel;
    const meetsStar = hero.rarity >= requiredStar;
    const hasEnoughMaterial = currentMaterialCount >= materialQuantity;
    const hasEnoughSilver = master.silverCoins >= BigInt(silverCost);

    const canPromote = !isMax && !hero.isLocked && hero.state !== 'DEAD' && hero.state !== 'DISABLED' &&
      meetsLevel && meetsStar && hasEnoughMaterial && hasEnoughSilver;

    const currentMaxLevel = heroEffectiveMaxLevel(hero.rarity, currentRank);
    const nextMaxLevel = heroEffectiveMaxLevel(hero.rarity, nextRank);
    const multiplier = config?.statGrowthMultiplier ?? 1.05;

    return res.json({
      hero: {
        id: hero.id,
        name: hero.name,
        rarity: hero.rarity,
        level: hero.level,
        currentRank,
        nextRank,
        isMax,
        currentMaxLevel,
        nextMaxLevel,
        starCeiling: starMaxLevel(hero.rarity),
        isLocked: hero.isLocked,
        state: hero.state,
      },
      requirements: {
        requiredHeroLevel,
        meetsLevel,
        requiredStar,
        meetsStar,
        materialItemId,
        materialQuantity,
        currentMaterialCount,
        hasEnoughMaterial,
        silverCost,
        currentSilver: master.silverCoins.toString(),
        hasEnoughSilver,
      },
      projected: {
        maxLevel: nextMaxLevel,
        hp: Math.floor(hero.hp * multiplier),
        maxHp: Math.floor(hero.maxHp * multiplier),
        attack: Math.floor(hero.attack * multiplier),
        defense: Math.floor(hero.defense * multiplier),
        speed: Math.floor(hero.speed * multiplier),
      },
      canPromote,
    });
  };

  app.get('/api/heroes/:heroId/promote/preview', requireAccount, requireFeature('HERO_COLLECTION'), asyncRoute(previewBreakthrough));
  app.get('/api/heroes/:heroId/breakthrough/preview', requireAccount, requireFeature('HERO_COLLECTION'), asyncRoute(previewBreakthrough));

  const executeBreakthrough = async (req: any, res: Response) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    const result = await db.transaction(async tx => {
      const [masterRow] = await tx.select().from(masters).where(eq(masters.id, master.id)).for('update').limit(1);
      if (!masterRow) return { status: 404, error: 'Master not found.' } as const;
      const [hero] = await tx.select().from(heroes).where(and(eq(heroes.id, String(req.params.heroId)), eq(heroes.masterId, master.id))).for('update').limit(1);
      if (!hero) return { status: 404, error: 'Hero not found.' } as const;
      if (hero.isLocked) return { status: 409, error: 'Hero is locked.' } as const;
      if (hero.state === 'DEAD') return { status: 409, error: 'ERR_HERO_PERMANENTLY_DEAD' } as const;
      if (hero.state === 'DISABLED' || hero.hp <= 0) return { status: 409, error: 'Hero is not available for development.' } as const;

      const [config] = await tx.select().from(heroDevelopmentConfigs).where(and(eq(heroDevelopmentConfigs.action, 'PROMOTION'), eq(heroDevelopmentConfigs.rank, hero.promotionRank + 1))).limit(1);
      if (!config) return { status: 409, error: 'Đã đạt Bậc Đột Phá tối đa.' } as const;

      const requiredStar = config.rank + 1;
      if (hero.rarity < requiredStar) {
        return { status: 409, error: `Cần Thăng Sao lên ít nhất ${requiredStar}★ trước khi Đột phá Bậc ${config.rank}.` } as const;
      }
      if (hero.level < config.requiredHeroLevel || hero.promotionRank < config.requiredPromotionRank) {
        return { status: 409, error: `Cần đạt Lv.${config.requiredHeroLevel} để Đột phá Bậc ${config.rank}.` } as const;
      }

      const silverCost = BREAKTHROUGH_SILVER_COST[config.rank] ?? (config.rank * 10_000);
      if (masterRow.silverCoins < BigInt(silverCost)) {
        return { status: 409, error: `Không đủ Xu Bạc để Đột phá (Cần ${silverCost.toLocaleString()} Bạc).` } as const;
      }

      const [material] = await tx.select().from(masterItems).where(and(eq(masterItems.masterId, master.id), eq(masterItems.itemId, config.materialItemId))).for('update').limit(1);
      if (!material || material.quantity < config.materialQuantity) {
        return { status: 409, error: `Cần ${config.materialQuantity} Dấu ấn Đột phá (${config.materialItemId}).` } as const;
      }

      await tx.update(masterItems).set({ quantity: material.quantity - config.materialQuantity, updatedAt: new Date() }).where(eq(masterItems.id, material.id));
      await tx.update(masters).set({ silverCoins: masterRow.silverCoins - BigInt(silverCost), updatedAt: new Date() }).where(eq(masters.id, master.id));

      const multiplier = config.statGrowthMultiplier ?? 1.05;
      const maxHp = Math.floor(hero.maxHp * multiplier);
      const attack = Math.floor(hero.attack * multiplier);
      const defense = Math.floor(hero.defense * multiplier);
      const speed = Math.floor(hero.speed * multiplier);

      const [updated] = await tx.update(heroes).set({
        promotionRank: config.rank,
        maxHp,
        hp: Math.min(maxHp, hero.hp + (maxHp - hero.maxHp)),
        attack,
        defense,
        speed,
        updatedAt: new Date()
      }).where(eq(heroes.id, hero.id)).returning();

      const effectiveMax = heroEffectiveMaxLevel(updated.rarity, updated.promotionRank);
      return {
        status: 200,
        heroId: updated.id,
        promotionRank: updated.promotionRank,
        maxLevel: effectiveMax,
        starCeiling: starMaxLevel(updated.rarity),
        silverCost,
        remainingSilver: (masterRow.silverCoins - BigInt(silverCost)).toString(),
        materialQuantity: material.quantity - config.materialQuantity,
        stats: { hp: updated.hp, maxHp: updated.maxHp, attack: updated.attack, defense: updated.defense, speed: updated.speed }
      } as const;
    });
    if (result.status !== 200) return res.status(result.status).json({ error: result.error });
    return res.json(result);
  };

  app.post('/api/heroes/:heroId/promote', requireAccount, requireFeature('HERO_COLLECTION'), asyncRoute(executeBreakthrough));
  app.post('/api/heroes/:heroId/breakthrough', requireAccount, requireFeature('HERO_COLLECTION'), asyncRoute(executeBreakthrough));

  app.get('/api/heroes/:heroId/promote-star/preview', requireAccount, requireFeature('HERO_COLLECTION'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    try {
      const preview = await heroPromotionService.previewStarPromotion(master.id, String(req.params.heroId));
      return res.json(preview);
    } catch (error) {
      if (progressionError(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/heroes/:heroId/promote-star', requireAccount, requireFeature('HERO_COLLECTION'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    try {
      const result = await heroPromotionService.executeStarPromotion(
        master.id,
        String(req.params.heroId),
        req.body?.fodderHeroIds ?? [],
      );
      return res.json(result);
    } catch (error) {
      if (progressionError(res, error)) return undefined;
      throw error;
    }
  }));

  app.get('/api/heroes/:heroId/awaken/preview', requireAccount, requireFeature('HERO_COLLECTION'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    const [hero] = await db.select().from(heroes).where(and(eq(heroes.id, String(req.params.heroId)), eq(heroes.masterId, master.id))).limit(1);
    if (!hero) return res.status(404).json({ error: 'Hero not found.' });

    const currentRank = hero.awakeningRank ?? 0;
    const nextRank = currentRank + 1;
    const maxRank = imprintSlotsFor(hero.rarity);
    const isMax = currentRank >= maxRank;

    const [config] = await db.select().from(heroDevelopmentConfigs).where(and(eq(heroDevelopmentConfigs.action, 'AWAKENING'), eq(heroDevelopmentConfigs.rank, nextRank))).limit(1);
    const materialItemId = config?.materialItemId ?? 'SAMPLE_HERO_AWAKENING_CORE';
    const materialQuantity = config?.materialQuantity ?? (nextRank * 3);
    const requiredHeroLevel = config?.requiredHeroLevel ?? 1;
    const requiredPromotionRank = config?.requiredPromotionRank ?? 0;
    const silverCost = 5000 * nextRank;

    const [material] = await db.select().from(masterItems).where(and(eq(masterItems.masterId, master.id), eq(masterItems.itemId, materialItemId))).limit(1);
    const currentMaterialCount = material?.quantity ?? 0;

    const hasEnoughMaterial = currentMaterialCount >= materialQuantity;
    const hasEnoughSilver = master.silverCoins >= silverCost;
    const meetsLevel = hero.level >= requiredHeroLevel;
    const meetsPromotion = (hero.promotionRank >= requiredPromotionRank) || (hero.rarity >= (requiredPromotionRank + 1)) || requiredPromotionRank === 0;

    const canAwaken = !isMax && !hero.isLocked && hero.state !== 'DEAD' && hero.state !== 'DISABLED' && meetsLevel && meetsPromotion && hasEnoughMaterial && hasEnoughSilver;

    const maxSlots = imprintSlotsFor(hero.rarity);
    const projected = {
      str: hero.baseStr + 10,
      int: hero.baseInt + 10,
      sta: hero.baseSta + 10,
      agi: hero.baseAgi + 10,
      statGrowthMultiplier: config?.statGrowthMultiplier ?? 1.05,
      skillLevelBonus: 1,
      imprintSlots: maxSlots,
      unlockedSlot: Math.min(nextRank, maxSlots)
    };

    return res.json({
      hero: {
        id: hero.id,
        name: hero.name,
        rarity: hero.rarity,
        level: hero.level,
        currentRank,
        nextRank,
        maxRank,
        isMax,
        isLocked: hero.isLocked,
        state: hero.state
      },
      requirements: {
        requiredHeroLevel,
        meetsLevel,
        requiredPromotionRank,
        meetsPromotion,
        materialItemId,
        materialQuantity,
        currentMaterialCount,
        hasEnoughMaterial,
        silverCost,
        hasEnoughSilver,
      },
      projected,
      canAwaken
    });
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
      const maxRank = imprintSlotsFor(hero.rarity);
      if ((hero.awakeningRank ?? 0) >= maxRank) return { status: 409, error: `Hero has already reached maximum awakening rank (+${maxRank}).` } as const;
      const [config] = await tx.select().from(heroDevelopmentConfigs).where(and(eq(heroDevelopmentConfigs.action, 'AWAKENING'), eq(heroDevelopmentConfigs.rank, hero.awakeningRank + 1))).limit(1);
      if (!config) return { status: 409, error: 'No further awakening is configured.' } as const;
      const meetsPromotion = (hero.promotionRank >= config.requiredPromotionRank) || (hero.rarity >= (config.requiredPromotionRank + 1)) || config.requiredPromotionRank === 0;
      if (hero.level < config.requiredHeroLevel || !meetsPromotion) return { status: 409, error: 'Hero does not meet the configured awakening requirements.' } as const;
      const [material] = await tx.select().from(masterItems).where(and(eq(masterItems.masterId, master.id), eq(masterItems.itemId, config.materialItemId))).for('update').limit(1);
      if (!material || material.quantity < config.materialQuantity) return { status: 409, error: `Awakening requires ${config.materialQuantity} configured materials.` } as const;
      const multiplier = config.statGrowthMultiplier;
      const maxHp = Math.floor(hero.maxHp * multiplier);
      let updated;
      let skillAwakened: { code: string; level: number } | null = null;
      let newTrait: string | null = null;
      let imprintGranted: { code: string; rankLevel: number } | null = null;
      if (isV2Origin(hero.originStats)) {
        // Awakening v2: stat growth + skill level + a new special trait.
        const snapshot = progressionFor({
          origin: originOf(hero.originStats),
          star: hero.rarity as StarRating,
          level: hero.level,
          classCode: hero.classCode as HeroClass,
          training: hero.trainingStats,
          hpPct: hero.currentHpPct,
          mpPct: hero.currentMpPct,
          awakeningRank: config.rank,
          imprint: await imprintStatsFor(tx, hero.id),
        });
        const skillRows = await tx.select({ instance: heroSkillInstances, template: heroSkillTemplates })
          .from(heroSkillInstances).innerJoin(heroSkillTemplates, eq(heroSkillInstances.skillCode, heroSkillTemplates.code))
          .where(and(eq(heroSkillInstances.heroId, hero.id), eq(heroSkillInstances.isUnlocked, true)));
        const upgrade = skillRows.find(row => row.instance.skillLevel < row.template.maxLevel);
        if (upgrade) {
          await tx.update(heroSkillInstances).set({
            skillLevel: upgrade.instance.skillLevel + 1, updatedAt: new Date(),
          }).where(eq(heroSkillInstances.id, upgrade.instance.id));
          skillAwakened = { code: upgrade.template.code, level: upgrade.instance.skillLevel + 1 };
        }
        const traits = ['DRAGON_HEART', 'PHOENIX_BLOOD', 'VOID_TOUCH', 'STAR_BLESSED', 'IRON_WILL'];
        newTrait = traits[Math.floor(Math.random() * traits.length)];
        const [traitRow] = await tx.select().from(heroPersonalityTraits).where(eq(heroPersonalityTraits.heroId, hero.id)).limit(1);
        if (traitRow) {
          await tx.update(heroPersonalityTraits).set({ specialTrait: newTrait, updatedAt: new Date() })
            .where(eq(heroPersonalityTraits.heroId, hero.id));
        }
        // Awakening v2: Slots are unlocked by awakening rank, but imprints are found in Dungeons / Raids (no free auto-grant)
        [updated] = await tx.update(heroes).set({
          awakeningRank: config.rank,
          baseStr: snapshot.base.str, baseInt: snapshot.base.int,
          baseSta: snapshot.base.sta, baseAgi: snapshot.base.agi,
          maxHp: snapshot.maxHp, hp: snapshot.hp,
          attack: snapshot.attack, defense: snapshot.defense, speed: snapshot.speed,
          mp: snapshot.mp, maxMp: snapshot.maxMp, updatedAt: new Date(),
        }).where(eq(heroes.id, hero.id)).returning();
      } else {
        [updated] = await tx.update(heroes).set({ awakeningRank: config.rank, maxHp, hp: Math.min(maxHp, hero.hp + maxHp - hero.maxHp), attack: Math.floor(hero.attack * multiplier), defense: Math.floor(hero.defense * multiplier), speed: Math.floor(hero.speed * multiplier), updatedAt: new Date() }).where(eq(heroes.id, hero.id)).returning();
      }
      await tx.update(masterItems).set({ quantity: material.quantity - config.materialQuantity, updatedAt: new Date() }).where(eq(masterItems.id, material.id));
      return { status: 200, heroId: updated.id, awakeningRank: updated.awakeningRank, skillAwakened, newTrait, imprintGranted, stats: { hp: updated.hp, maxHp: updated.maxHp, attack: updated.attack, defense: updated.defense, speed: updated.speed }, materialQuantity: material.quantity - config.materialQuantity } as const;
    });
    if (result.status !== 200) return res.status(result.status).json({ error: result.error });
    return res.json(result);
  }));

  app.get('/api/hero-templates', requireAccount, requireFeature('HERO_COLLECTION'), asyncRoute(async (_req, res) => {
    const templates = await db.select().from(heroTemplates).orderBy(heroTemplates.defaultRarity, heroTemplates.name);
    return res.json(templates);
  }));

  app.get('/api/imprints', requireAccount, requireFeature('HERO_COLLECTION'), asyncRoute(async (_req, res) => {
    return res.json(await db.select().from(imprintDefinitions)
      .where(eq(imprintDefinitions.isEnabled, true))
      .orderBy(asc(imprintDefinitions.rank), asc(imprintDefinitions.tier)));
  }));

  app.get('/api/heroes/:heroId/imprints', requireAccount, requireFeature('HERO_COLLECTION'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    const rows = await db.select({ owned: heroImprints, definition: imprintDefinitions })
      .from(heroImprints).innerJoin(imprintDefinitions, eq(imprintDefinitions.code, heroImprints.imprintCode))
      .innerJoin(heroes, eq(heroes.id, heroImprints.heroId))
      .where(and(eq(heroImprints.heroId, String(req.params.heroId)), eq(heroes.masterId, master.id)))
      .orderBy(asc(imprintDefinitions.rank), asc(imprintDefinitions.tier));
    return res.json(rows);
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

  app.put('/api/equipment/heroes/:heroId/quick-equip', requireAccount, requireFeature('EQUIPMENT'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    try { return res.json(await equipmentService.quickEquip(master.id, String(req.params.heroId))); }
    catch (error) {
      if (error instanceof EquipmentError) return res.status(error.statusCode).json({ error: error.message });
      throw error;
    }
  }));

  app.post('/api/equipment/heroes/:heroId/quick-unequip', requireAccount, requireFeature('EQUIPMENT'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    try { return res.json(await equipmentService.quickUnequip(master.id, String(req.params.heroId))); }
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

  const combatV2Error = (res: Response, error: unknown): boolean => {
    if (error instanceof CombatV2Error) {
      res.status(error.statusCode).json({ error: error.message });
      return true;
    }
    return false;
  };

  app.post('/api/combat/v2/session/start', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    try {
      return res.status(201).json(await combatV2Service.start(master.id, req.body ?? {}));
    } catch (error) {
      if (combatV2Error(res, error)) return undefined;
      throw error;
    }
  }));

  app.post('/api/combat/v2/session/:sessionId/advance', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    try {
      return res.json(await combatV2Service.advance(master.id, String(req.params.sessionId)));
    } catch (error) {
      if (combatV2Error(res, error)) return undefined;
      throw error;
    }
  }));

  app.get('/api/combat/v2/sessions', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    return res.json(await combatV2Service.sessions(master.id));
  }));

  app.post('/api/combat/v2/simulate', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const [master] = await db.select().from(masters).where(eq(masters.accountId, req.accountId!)).limit(1);
    if (!master) return res.status(409).json({ error: 'Initialize a Master first.' });
    try {
      return res.json(await combatV2Service.simulate(master.id, req.body ?? {}));
    } catch (error) {
      if (error instanceof CombatV2Error) return res.status(error.statusCode).json({ error: error.message });
      throw error;
    }
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
      const report = session.battleReport as { result?: string; floor?: number; nextFloor?: number; rounds?: number; survivors?: { id: string; hp: number; maxHp: number }[] } | null;
      if (report?.survivors?.length) {
        await medicalService.recordBattleInjuries(master.id, report.survivors).catch(error => console.error('[medical] injury recording failed', error));
      }
      if (report?.result === 'VICTORY' && report.survivors?.length) {
        await personalityService.recordVictory(master.id, report.survivors.map(row => row.id))
          .catch(error => console.error('[personality] loyalty update failed', error));
      }
      if (report?.result === 'VICTORY') {
        await questService.recordEvent(master.id, 'WIN_BATTLE', 1)
          .catch(error => console.error('[quest] victory progress failed', error));
        await eventService.recordEvent(master.id, 'WIN_BATTLE', 1)
          .catch(error => console.error('[liveops] victory progress failed', error));
        if ((report.nextFloor ?? 0) > (report.floor ?? 0)) {
          await questService.recordEvent(master.id, 'CLEAR_FLOOR', 1)
            .catch(error => console.error('[quest] floor progress failed', error));
          await eventService.recordEvent(master.id, 'CLEAR_FLOOR', 1)
            .catch(error => console.error('[liveops] floor progress failed', error));
          await leaderboardService.recordFloor(master.id, report.nextFloor ?? 0, report.rounds ?? 0)
            .catch(error => console.error('[leaderboard] floor record failed', error));
        }
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

  app.use('/api/alchemy', requireAccount, asyncRoute(async (req, res, next) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'Hãy khởi tạo Master trước.' });
    const [world] = await db.select({ currentFloor: worlds.currentFloor }).from(worlds).where(eq(worlds.masterId, master.id)).limit(1);
    if ((world?.currentFloor ?? 1) <= 10) return res.status(403).json({ error: 'Đại Sảnh Ma Thuật mở sau khi vượt Tháp tầng 10.' });
    return next();
  }));

  app.get('/api/alchemy', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'ERR_PVE_NO_MASTER' });
    return res.json(await alchemyService.state(master.id));
  }));
  for (const operation of ['research', 'craft', 'configure', 'use'] as const) {
    app.post(`/api/alchemy/${operation}`, requireAccount, asyncRoute(async (req, res) => {
      const master = await requireMaster(req);
      if (!master) return res.status(409).json({ error: 'ERR_PVE_NO_MASTER' });
      return res.json(await pveService.command(master.id, `ALCHEMY:${operation}`, req.header('Idempotency-Key') ?? '', req.body, async tx => {
        if (operation === 'research') return alchemyService.research(tx, master.id, String(req.body?.code ?? ''));
        if (operation === 'craft') return alchemyService.craft(tx, master.id, String(req.body?.code ?? ''), req.body?.quantity);
        if (operation === 'use') return alchemyService.use(tx, master.id, String(req.body?.heroId ?? ''), String(req.body?.itemId ?? ''), req.body?.slotIndex);
        return alchemyService.configure(tx, master.id, String(req.body?.heroId ?? ''), req.body?.config);
      }));
    }));
  }

  app.get('/api/pve/state', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'ERR_PVE_NO_MASTER' });
    const cursor = req.query.cursor === undefined ? 0 : Number(req.query.cursor);
    if (!Number.isSafeInteger(cursor) || cursor < 0) return res.status(400).json({ error: 'ERR_PVE_INVALID_CURSOR' });
    return res.json(await pveService.state(master.id, cursor, typeof req.query.mapId === 'string' ? req.query.mapId : undefined));
  }));

  app.post('/api/pve/enter', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'ERR_PVE_NO_MASTER' });
    const rawFloor = req.body && typeof req.body === 'object' ? (req.body as { floor?: unknown }).floor : undefined;
    const requestedFloor = typeof rawFloor === 'number' || (typeof rawFloor === 'string' && rawFloor.trim() !== '')
      ? Number(rawFloor)
      : undefined;
    return res.status(201).json(await pveService.enter(master.id, req.header('Idempotency-Key') ?? '', requestedFloor));
  }));

  app.post('/api/pve/parties', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'ERR_PVE_NO_MASTER' });
    return res.status(201).json(await pveService.saveParty(master.id, req.body, req.header('Idempotency-Key') ?? ''));
  }));

  app.put('/api/pve/parties/:partyId', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'ERR_PVE_NO_MASTER' });
    return res.json(await pveService.saveParty(master.id, req.body, req.header('Idempotency-Key') ?? '', String(req.params.partyId)));
  }));

  app.put('/api/pve/parties/:partyId/plan', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'ERR_PVE_NO_MASTER' });
    return res.json(await pveService.savePlan(master.id, String(req.params.partyId), req.body, req.header('Idempotency-Key') ?? ''));
  }));

  app.post('/api/pve/parties/:partyId/deploy', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'ERR_PVE_NO_MASTER' });
    const forceRecall = Boolean(req.body && typeof req.body === 'object' && (req.body as { forceRecall?: unknown }).forceRecall);
    return res.status(201).json(await pveService.deploy(master.id, String(req.params.partyId), req.header('Idempotency-Key') ?? '', forceRecall));
  }));

  app.post('/api/pve/squads/:squadId/move', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'ERR_PVE_NO_MASTER' });
    return res.json(await pveService.move(master.id, String(req.params.squadId), req.body, req.header('Idempotency-Key') ?? ''));
  }));

  app.post('/api/pve/squads/:squadId/portal', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'ERR_PVE_NO_MASTER' });
    return res.json(await pveService.portal(master.id, String(req.params.squadId), req.body, req.header('Idempotency-Key') ?? ''));
  }));

  app.post('/api/pve/dev/reset-tower', requireAccount, asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'ERR_PVE_NO_MASTER' });
    return res.json(await pveService.resetTower(master.id, req.body, req.header('Idempotency-Key') ?? ''));
  }));

  app.post('/api/pve/squads/:squadId/recall-point', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'ERR_PVE_NO_MASTER' });
    return res.json(await pveService.placeRecallPoint(master.id, String(req.params.squadId), req.body, req.header('Idempotency-Key') ?? ''));
  }));

  app.post('/api/pve/squads/:squadId/recall', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'ERR_PVE_NO_MASTER' });
    return res.json(await pveService.recall(master.id, String(req.params.squadId), req.header('Idempotency-Key') ?? ''));
  }));

  app.post('/api/pve/squads/:squadId/auto', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'ERR_PVE_NO_MASTER' });
    return res.json(await pveService.setAuto(master.id, String(req.params.squadId), req.body, req.header('Idempotency-Key') ?? ''));
  }));

  app.get('/api/pve/battles', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'ERR_PVE_NO_MASTER' });
    return res.json(await pveService.battles(master.id,
      typeof req.query.before === 'string' ? req.query.before : undefined,
      typeof req.query.mapId === 'string' ? req.query.mapId : undefined,
      req.query.limit === undefined ? 30 : Number(req.query.limit)));
  }));

  app.post('/api/pve/consumables/use', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'ERR_PVE_NO_MASTER' });
    return res.json(await pveService.command(master.id, 'CONSUMABLE_USE', req.header('Idempotency-Key') ?? '', req.body,
      tx => alchemyService.use(tx, master.id, String(req.body?.heroId ?? ''), String(req.body?.itemId ?? ''), req.body?.slotIndex)));
  }));

  app.post('/api/pve/battles/:battleId/action', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'ERR_PVE_NO_MASTER' });
    return res.json(await pveService.liveBattle(master.id, String(req.params.battleId), req.body, req.header('Idempotency-Key') ?? ''));
  }));

  app.get('/api/pve/battles/:battleId', requireAccount, requireFeature('PVE_COMBAT'), asyncRoute(async (req, res) => {
    const master = await requireMaster(req);
    if (!master) return res.status(409).json({ error: 'ERR_PVE_NO_MASTER' });
    return res.json(await pveService.battle(master.id, String(req.params.battleId)));
  }));

  app.use((error: unknown, _req: Request, res: Response, _next: NextFunction) => {
    if (error instanceof PveError) return res.status(error.statusCode).json({ error: error.message });
    if (error instanceof CombatReadinessError) return res.status(error.statusCode).json({ error: error.message });
    if (error instanceof PveRuleError) return res.status(error.code.includes('UNDISCOVERED') ? 409 : 400).json({ error: error.code });
    const databaseCause = error as { cause?: { message?: string }; message?: string };
    if ([databaseCause.message, databaseCause.cause?.message].some(message => message?.includes('ERR_PVE_HERO_DEPLOYED'))) {
      return res.status(409).json({ error: 'ERR_PVE_HERO_DEPLOYED' });
    }
    if ([databaseCause.message, databaseCause.cause?.message].some(message => message?.includes('ERR_PVE_MAP_ACTIVE'))) {
      return res.status(409).json({ error: 'ERR_PVE_MAP_ACTIVE' });
    }
    console.error(error);
    return res.status(500).json({ error: 'Lỗi máy chủ.' });
  });

  return app;
}

if (process.env.NODE_ENV !== 'test') {
  const port = Number(process.env.PORT ?? 3000);
  createApp().listen(port, () => console.log(`[Infinite Gacha] API listening on ${port}`));
}
