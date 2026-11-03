import { createHash } from 'node:crypto';
import { and, asc, eq, gt, inArray, lte, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { calculateDamage, calculateElementMultiplier, GAME_CONSTANTS } from '@infiniti-gacha/shared';
import { db } from '../../database/db.js';
import {
  combatPartySlots, combatSessions, currencyTransactions, enemyTemplates, equipmentInstances, equipmentTemplates, heroes, masters, worlds, masterParties, heroDeathRecords, dungeonEventTemplates, heroLevelConfigs, heroDevelopmentConfigs, masterLevelConfigs, masterSkillTemplates, heroTemplates, heroSkillInstances, heroSkillTemplates,
} from '../../database/drizzle-schema.js';
import { TacticalBuffManager } from './tactical-buff.manager.js';
import { getBattleRules } from '../admin/runtime-rules.js';
import { survivalService } from '../survival/survival.service.js';
import { medicalService } from '../medical/medical.service.js';

export class CombatSessionError extends Error {
  constructor(message: string, public readonly statusCode: number) { super(message); }
}

export interface StartCombatOptions {
  partyId?: string;
  buffId?: string;
}

export type StatusEffect = {
  type: 'STUN' | 'POISON' | 'BLEED' | 'SHIELD' | 'ATK_BUFF' | 'DEF_DEBUFF';
  value: number;
  remainingRounds: number;
};

export type UnitSkillState = {
  skillCode: string;
  name: string;
  skillLevel: number;
  effectType?: string;
  effectValue: number;
  cooldownRounds?: number;
  cooldownUntilRound?: number;
  behaviorMode: 'AUTO' | 'MANUAL';
};

export type CombatLogEntry = {
  round: number;
  actor: string;
  target: string;
  actionType?: 'ATTACK' | 'SKILL' | 'HEAL' | 'ASSIST' | 'STATUS' | 'CRIT';
  skillName?: string;
  isCritical?: boolean;
  elementMultiplier?: number;
  damage: number;
  heal?: number;
  targetHp: number;
  note?: string;
};

export type UnitState = {
  id: string;
  slotIndex: number;
  name: string;
  templateCode: string;
  heroClass?: string;
  element?: string;
  origin?: string;
  hp: number;
  maxHp: number;
  shield?: number;
  attack: number;
  defense: number;
  speed: number;
  critRate?: number;
  critDamage?: number;
  skills?: UnitSkillState[];
  statusEffects?: StatusEffect[];
};

export type CombatStrategyState = {
  initialBuffId?: string | null;
  name?: string | null;
  configuredAt?: string | null;
};

export type CombatState = {
  round: number;
  floor: number;
  difficultyMultiplier: number;
  partyId?: string | null;
  strategy?: CombatStrategyState | null;
  targetPriority?: 'LOWEST_HP' | 'HIGHEST_ATK' | 'FRONTLINE' | 'BALANCED' | null;
  heroes: UnitState[];
  enemies: UnitState[];
  floorEvent: { code: string; name: string; description: string; eventType: string; silverReward: number; healPercent: number; enemyAttackMultiplier: number };
  log: CombatLogEntry[];
  masterSkillCooldownUntil?: string | null;
  masterSkillEffect?: { skillCode: string; skillName: string; startedAt: string; durationSeconds: number; healPercentPerSecond: number; appliedTicks: number } | null;
};
export type CombatSurvivor = {
  id: string;
  name: string;
  hp: number;
  maxHp: number;
  hpPercent: number;
};

export type CombatFallenHero = {
  id: string;
  name: string;
  origin?: string;
  deathType: 'PERMADEATH' | 'DISABLED';
  droppedEquipmentCount: number;
  droppedEquipment?: unknown[];
};

export type CombatReport = {
  result: 'VICTORY' | 'DEFEAT';
  rounds: number;
  floor: number;
  nextFloor: number;
  floorEvent: { code: string; name: string; description: string; eventType: string };
  expReward: number;
  silverReward: number;
  battleSilverReward: number;
  floorEventSilverReward: number;
  masterExpReward: number;
  masterLevelUps: { fromLevel: number; toLevel: number }[];
  heroLevelUps: { heroId: string; name: string; fromLevel: number; toLevel: number }[];
  survivors: CombatSurvivor[];
  fallenHeroes: CombatFallenHero[];
  log: CombatState['log'];
};

function readCombatState(value: unknown): CombatState {
  if (!value || typeof value !== 'object' || !Array.isArray((value as CombatState).heroes) || !Array.isArray((value as CombatState).enemies)) {
    throw new CombatSessionError('Combat session state is invalid.', 409);
  }
  const state = value as CombatState;
  if (!state.floor) state.floor = 1;
  if (!state.floorEvent) state.floorEvent = {
    code: 'LEGACY_COMBAT', name: 'Legacy encounter', description: 'Encounter created before floor events were added.',
    eventType: 'NONE', silverReward: 0, healPercent: 0, enemyAttackMultiplier: 1,
  };
  if (state.strategy === undefined) state.strategy = null;
  if (state.targetPriority === undefined) state.targetPriority = null;
  return state;
}

function seededIndex(seed: string, max: number): number {
  const digest = createHash('sha256').update(seed).digest();
  return digest.readUInt32BE(0) % max;
}

function seededPick<T extends { weight: number; code: string }>(seed: string, rows: T[]): T {
  const total = rows.reduce((sum, row) => sum + row.weight, 0);
  if (!rows.length || total <= 0) throw new CombatSessionError('Invalid dungeon event weights.', 409);
  let cursor = seededIndex(seed, total);
  for (const row of rows) { cursor -= row.weight; if (cursor < 0) return row; }
  return rows[rows.length - 1];
}

export class CombatSessionService {
  public async getActive(masterId: string) {
    const [session] = await db.select().from(combatSessions)
      .where(and(eq(combatSessions.masterId, masterId), eq(combatSessions.status, 'ACTIVE'))).limit(1);
    if (session && !session.combatState) {
      await db.update(combatSessions).set({ status: 'COMPLETED', finishedAt: new Date() }).where(eq(combatSessions.id, session.id));
      return null;
    }
    return session ?? null;
  }

  public async getParty(masterId: string) {
    const [party] = await db.select().from(masterParties).where(and(eq(masterParties.masterId, masterId), eq(masterParties.isDefault, true))).limit(1);
    if (!party) return [];
    return db.select({ slotIndex: combatPartySlots.slotIndex, hero: heroes })
      .from(combatPartySlots).innerJoin(heroes, eq(combatPartySlots.heroId, heroes.id))
      .where(eq(combatPartySlots.partyId, party.id)).orderBy(asc(combatPartySlots.slotIndex));
  }

  public async listParties(masterId: string) {
    const parties = await db.select().from(masterParties).where(eq(masterParties.masterId, masterId)).orderBy(asc(masterParties.createdAt));
    const slots = parties.length ? await db.select({ slotIndex: combatPartySlots.slotIndex, partyId: combatPartySlots.partyId, hero: heroes })
      .from(combatPartySlots).innerJoin(heroes, eq(combatPartySlots.heroId, heroes.id))
      .where(inArray(combatPartySlots.partyId, parties.map(party => party.id))).orderBy(asc(combatPartySlots.slotIndex)) : [];
    return parties.map(party => ({ ...party, members: slots.filter(slot => slot.partyId === party.id).map(({ slotIndex, hero }) => ({ slotIndex, hero: { ...hero, exp: hero.exp.toString() } })) }));
  }

  public async setParty(masterId: string, heroIds: unknown) {
    const [party] = await db.select().from(masterParties).where(and(eq(masterParties.masterId, masterId), eq(masterParties.isDefault, true))).limit(1);
    if (!party) throw new CombatSessionError('Create a Party and set it as default first.', 409);
    return this.updateParty(masterId, party.id, undefined, heroIds);
  }

  public async updateParty(masterId: string, partyId: string, name: string | undefined, heroIds: unknown) {
    if (heroIds !== undefined && (!Array.isArray(heroIds) || heroIds.length > GAME_CONSTANTS.COMBAT.MAX_COMBAT_HEROES_PER_TEAM || heroIds.some(id => typeof id !== 'string') || new Set(heroIds).size !== heroIds.length)) {
      throw new CombatSessionError('A party can contain at most five different Heroes.', 400);
    }
    return db.transaction(async tx => {
      await tx.select({ id: masters.id }).from(masters).where(eq(masters.id, masterId)).for('update').limit(1);
      const [party] = await tx.select().from(masterParties).where(and(eq(masterParties.id, partyId), eq(masterParties.masterId, masterId))).for('update').limit(1);
      if (!party) throw new CombatSessionError('Party not found.', 404);
      const active = await tx.select({ id: combatSessions.id }).from(combatSessions)
        .where(and(eq(combatSessions.masterId, masterId), eq(combatSessions.status, 'ACTIVE'))).limit(1);
      if (active.length) throw new CombatSessionError('Cannot edit parties during active combat.', 409);
      if (heroIds !== undefined) {
        const owned = heroIds.length ? await tx.select().from(heroes).where(and(eq(heroes.masterId, masterId), inArray(heroes.id, heroIds as string[]))) : [];
        if (owned.length !== heroIds.length || owned.some(hero => hero.state === 'DEAD' || hero.state === 'DISABLED' || hero.hp <= 0)) {
          throw new CombatSessionError('Party may contain only available Heroes owned by this Master.', 400);
        }
      }
      if (name !== undefined) await tx.update(masterParties).set({ name, updatedAt: new Date() }).where(eq(masterParties.id, partyId));
      if (heroIds !== undefined) {
        await tx.delete(combatPartySlots).where(eq(combatPartySlots.partyId, partyId));
        if (heroIds.length) await tx.insert(combatPartySlots).values(heroIds.map((heroId, slotIndex) => ({ id: uuidv4(), masterId, partyId, heroId, slotIndex })));
      }
      return tx.select({ slotIndex: combatPartySlots.slotIndex, hero: heroes })
        .from(combatPartySlots).innerJoin(heroes, eq(combatPartySlots.heroId, heroes.id))
        .where(eq(combatPartySlots.partyId, partyId)).orderBy(asc(combatPartySlots.slotIndex));
    });
  }
  public async start(masterId: string, options?: StartCombatOptions) {
    // DM-09 gate: overexhausted/starving Heroes cannot deploy and travel rations are charged.
    const readiness = await survivalService.battleReadiness(masterId, options?.partyId);
    if (!readiness.ok) throw new CombatSessionError(readiness.message, readiness.statusCode);
    const injuryPenalties = await medicalService.penaltyByHero(masterId);

    return db.transaction(async tx => {
      const [master] = await tx.select().from(masters).where(eq(masters.id, masterId)).for('update').limit(1);
      if (!master) throw new CombatSessionError('Không tìm thấy Master.', 404);
      const [active] = await tx.select().from(combatSessions)
        .where(and(eq(combatSessions.masterId, masterId), eq(combatSessions.status, 'ACTIVE'))).limit(1);
      if (active?.combatState) return active;
      if (active) await tx.update(combatSessions).set({ status: 'COMPLETED', finishedAt: new Date() }).where(eq(combatSessions.id, active.id));

      const [world] = await tx.select().from(worlds).where(eq(worlds.masterId, masterId)).orderBy(asc(worlds.createdAt)).limit(1);
      if (!world) throw new CombatSessionError('Hãy khởi tạo World trước khi vào chiến đấu.', 409);

      let targetParty: typeof masterParties.$inferSelect | undefined;
      if (options?.partyId) {
        const [foundParty] = await tx.select().from(masterParties)
          .where(and(eq(masterParties.id, options.partyId), eq(masterParties.masterId, masterId))).limit(1);
        if (!foundParty) throw new CombatSessionError('Party not found.', 404);
        targetParty = foundParty;
      } else {
        const [defaultParty] = await tx.select().from(masterParties)
          .where(and(eq(masterParties.masterId, masterId), eq(masterParties.isDefault, true))).limit(1);
        if (!defaultParty) throw new CombatSessionError('Set a default Party before starting combat.', 409);
        targetParty = defaultParty;
      }

      let party = await tx.select({ slotIndex: combatPartySlots.slotIndex, hero: heroes, template: heroTemplates })
        .from(combatPartySlots).innerJoin(heroes, eq(combatPartySlots.heroId, heroes.id))
        .leftJoin(heroTemplates, eq(heroes.configId, heroTemplates.code))
        .where(eq(combatPartySlots.partyId, targetParty.id)).orderBy(asc(combatPartySlots.slotIndex));

      const unavailablePartyMembers = party.filter(({ hero }) => hero.state === 'DEAD' || hero.state === 'DISABLED' || hero.hp <= 0);
      if (unavailablePartyMembers.length) {
        await tx.delete(combatPartySlots).where(and(eq(combatPartySlots.masterId, masterId), inArray(combatPartySlots.heroId, unavailablePartyMembers.map(({ hero }) => hero.id))));
        party = party.filter(({ hero }) => hero.state !== 'DEAD' && hero.state !== 'DISABLED' && hero.hp > 0);
      }
      if (!party.length) throw new CombatSessionError('Hãy chọn ít nhất một Hero còn hoạt động cho đội hình.', 409);

      const heroIds = party.map(({ hero }) => hero.id);
      const skillRows = heroIds.length ? await tx.select({ instance: heroSkillInstances, template: heroSkillTemplates })
        .from(heroSkillInstances).innerJoin(heroSkillTemplates, eq(heroSkillInstances.skillCode, heroSkillTemplates.code))
        .where(and(inArray(heroSkillInstances.heroId, heroIds), eq(heroSkillInstances.isUnlocked, true))) : [];
      const skillsByHeroId = new Map<string, UnitSkillState[]>();
      for (const row of skillRows) {
        const list = skillsByHeroId.get(row.instance.heroId) ?? [];
        list.push({
          skillCode: row.template.code,
          name: row.template.name,
          skillLevel: row.instance.skillLevel,
          effectType: row.template.effectType ?? 'DAMAGE_SINGLE',
          effectValue: row.template.effectValue + (row.instance.skillLevel - 1) * row.template.upgradeIncrement,
          cooldownRounds: row.template.cooldownSeconds ?? 3,
          cooldownUntilRound: 0,
          behaviorMode: (row.instance.behaviorMode as 'AUTO' | 'MANUAL') ?? 'AUTO',
        });
        skillsByHeroId.set(row.instance.heroId, list);
      }

      const foes = await tx.select().from(enemyTemplates).where(eq(enemyTemplates.isActive, true)).orderBy(asc(enemyTemplates.code));
      if (foes.length < 1) throw new CombatSessionError('Chưa có cấu hình quái mẫu.', 409);
      const events = await tx.select().from(dungeonEventTemplates).where(eq(dungeonEventTemplates.isActive, true)).orderBy(asc(dungeonEventTemplates.code));
      const floorEvent = seededPick(`${world.worldSeed}:${world.currentFloor}:event`, events);
      const enemyCount = 2 + seededIndex(`${world.worldSeed}:${world.currentFloor}:enemy-count`, 3);
      const encounter = Array.from({ length: enemyCount }, (_, index) => foes[seededIndex(`${world.worldSeed}:${world.currentFloor}:enemy:${index}`, foes.length)]);
      const gearRows = await tx.select({ item: equipmentInstances, template: equipmentTemplates })
        .from(equipmentInstances).innerJoin(equipmentTemplates, eq(equipmentInstances.templateCode, equipmentTemplates.code))
        .where(and(eq(equipmentInstances.masterId, masterId), eq(equipmentInstances.location, 'EQUIPPED'), inArray(equipmentInstances.equippedHeroId, party.map(({ hero }) => hero.id))));
      const gearBonus = new Map<string, { hp: number; attack: number; defense: number; speed: number }>();
      for (const row of gearRows) {
        const heroId = row.item.equippedHeroId!;
        const bonus = gearBonus.get(heroId) ?? { hp: 0, attack: 0, defense: 0, speed: 0 };
        bonus.hp += row.template.bonusHp; bonus.attack += row.template.bonusAttack;
        bonus.defense += row.template.bonusDefense; bonus.speed += row.template.bonusSpeed;
        gearBonus.set(heroId, bonus);
      }

      let initialBuffId: string | null = null;
      let strategy: CombatStrategyState | null = null;
      if (options?.buffId) {
        const buff = TacticalBuffManager.AVAILABLE_BUFFS[options.buffId];
        if (!buff) throw new CombatSessionError('Buff không hợp lệ.', 400);
        initialBuffId = options.buffId;
        strategy = {
          initialBuffId,
          name: buff.name,
          configuredAt: new Date().toISOString(),
        };
      }

      const id = uuidv4();
      // Prototype tuning: enemy stats and rewards rise by 5% per floor after Floor 1.
      const difficultyMultiplier = world.difficultyMultiplier * (1 + Math.max(0, world.currentFloor - 1) * 0.05);
      const state: CombatState = {
        round: 1, floor: world.currentFloor, difficultyMultiplier, partyId: targetParty.id, strategy,
        floorEvent: { code: floorEvent.code, name: floorEvent.name, description: floorEvent.description, eventType: floorEvent.eventType, silverReward: floorEvent.silverReward, healPercent: floorEvent.healPercent, enemyAttackMultiplier: floorEvent.enemyAttackMultiplier },
        heroes: party.map(({ slotIndex, hero, template }) => {
          const bonus = gearBonus.get(hero.id) ?? { hp: 0, attack: 0, defense: 0, speed: 0 };
          const critRate = template?.heroClass === 'ASSASSIN' ? 0.25 : 0.10;
          return {
            id: hero.id, slotIndex, name: hero.name, templateCode: hero.configId, heroClass: template?.heroClass ?? undefined,
            element: template?.element ?? 'EARTH', origin: hero.category,
            hp: Math.min(hero.hp + Math.floor((hero.maxHp + bonus.hp) * floorEvent.healPercent), hero.maxHp + bonus.hp), maxHp: hero.maxHp + bonus.hp,
            shield: 0,
            attack: Math.max(1, Math.floor((hero.attack + bonus.attack) * (readiness.multipliers[hero.id] ?? 1) * (injuryPenalties[hero.id] ?? 1))),
            defense: Math.max(0, Math.floor((hero.defense + bonus.defense) * (readiness.multipliers[hero.id] ?? 1) * (injuryPenalties[hero.id] ?? 1))),
            speed: hero.speed + bonus.speed,
            critRate, critDamage: 0.5, skills: skillsByHeroId.get(hero.id) ?? [], statusEffects: [],
          };
        }),
        enemies: encounter.map((foe, index) => {
          const foeElement = foe.code.includes('MOSS') ? 'EARTH' : (foe.code.includes('BANDIT') ? 'DARK' : 'EARTH');
          return {
            id: `${id}:${index}`, slotIndex: index, name: foe.name, templateCode: foe.code, element: foeElement,
            hp: Math.max(1, Math.floor(foe.baseHp * difficultyMultiplier)),
            maxHp: Math.max(1, Math.floor(foe.baseHp * difficultyMultiplier)),
            shield: 0, attack: Math.max(1, Math.floor(foe.baseAttack * difficultyMultiplier * floorEvent.enemyAttackMultiplier)),
            defense: Math.max(0, Math.floor(foe.baseDefense * difficultyMultiplier)),
            speed: foe.baseSpeed, critRate: 0.05, critDamage: 0.5, statusEffects: [],
          };
        }),
        log: [],
      };
      const [session] = await tx.insert(combatSessions).values({
        id, masterId, worldId: world.id, partyId: targetParty.id, status: 'ACTIVE',
        activeBuffId: initialBuffId, lastBuffChangeAt: initialBuffId ? new Date() : null, cooldownUntil: null,
        createdAt: new Date(), combatState: state as unknown as Record<string, unknown>,
      }).returning();
      return session;
    });
  }

  public async getLatest(masterId: string) {
    const [session] = await db.select().from(combatSessions).where(eq(combatSessions.masterId, masterId))
      .orderBy(sql`${combatSessions.createdAt} DESC`).limit(1);
    return session ?? null;
  }

  public async changeBuff(masterId: string, sessionId: string, buffId: string) {
    const buff = TacticalBuffManager.AVAILABLE_BUFFS[buffId];
    const battleRules = await getBattleRules();
    if (!buff) throw new CombatSessionError('Buff không hợp lệ.', 400);
    return db.transaction(async tx => {
      const [session] = await tx.select().from(combatSessions)
        .where(and(eq(combatSessions.id, sessionId), eq(combatSessions.masterId, masterId))).for('update').limit(1);
      if (!session) throw new CombatSessionError('Không tìm thấy phiên chiến đấu.', 404);
      if (session.status !== 'ACTIVE') throw new CombatSessionError('Phiên chiến đấu đã kết thúc.', 409);
      if (session.activeBuffId === buffId) return { session, buff, remainingCooldownSeconds: 0 };
      const now = new Date();
      if (session.cooldownUntil && session.cooldownUntil > now) {
        const seconds = Math.ceil((session.cooldownUntil.getTime() - now.getTime()) / 1000);
        throw new CombatSessionError(`Buff đang hồi chiêu; cần ${seconds} giây.`, 429);
      }
      const cooldownSeconds = battleRules.tacticalBuffCooldownSeconds;
      const cooldownUntil = new Date(now.getTime() + cooldownSeconds * 1000);
      const [updated] = await tx.update(combatSessions).set({ activeBuffId: buffId, lastBuffChangeAt: now, cooldownUntil })
        .where(eq(combatSessions.id, session.id)).returning();
      return { session: updated, buff, remainingCooldownSeconds: cooldownSeconds };
    });
  }

  public async getMasterSkills(masterId: string) {
    const [master] = await db.select({ level: masters.level }).from(masters).where(eq(masters.id, masterId)).limit(1);
    if (!master) throw new CombatSessionError('Master not found.', 404);
    return db.select().from(masterSkillTemplates).where(and(eq(masterSkillTemplates.isActive, true), sql`${masterSkillTemplates.unlockLevel} <= ${master.level}`));
  }

  public async useMasterSkill(masterId: string, sessionId: string, skillCode: string) {
    return db.transaction(async tx => {
      const [master] = await tx.select().from(masters).where(eq(masters.id, masterId)).for('update').limit(1);
      if (!master) throw new CombatSessionError('Master not found.', 404);
      const [skill] = await tx.select().from(masterSkillTemplates).where(and(eq(masterSkillTemplates.code, skillCode), eq(masterSkillTemplates.isActive, true))).limit(1);
      if (!skill) throw new CombatSessionError('Master skill not found.', 404);
      if (master.level < skill.unlockLevel) throw new CombatSessionError(`This skill unlocks at Master level ${skill.unlockLevel}.`, 403);
      const [session] = await tx.select().from(combatSessions)
        .where(and(eq(combatSessions.id, sessionId), eq(combatSessions.masterId, masterId))).for('update').limit(1);
      if (!session) throw new CombatSessionError('Combat session not found.', 404);
      if (session.status !== 'ACTIVE') throw new CombatSessionError('Combat session has ended.', 409);
      const state = readCombatState(session.combatState);
      const now = new Date();
      const cooldownUntil = state.masterSkillCooldownUntil ? new Date(state.masterSkillCooldownUntil) : null;
      if (cooldownUntil && cooldownUntil > now) throw new CombatSessionError(`Skill is on cooldown for ${Math.ceil((cooldownUntil.getTime() - now.getTime()) / 1000)}s.`, 429);
      const activeEffect = state.masterSkillEffect;
      if (activeEffect && activeEffect.appliedTicks < activeEffect.durationSeconds && now.getTime() < Date.parse(activeEffect.startedAt) + activeEffect.durationSeconds * 1000) {
        throw new CombatSessionError('A Master skill effect is already active.', 409);
      }
      state.masterSkillCooldownUntil = new Date(now.getTime() + skill.cooldownSeconds * 1000).toISOString();
      state.masterSkillEffect = {
        skillCode: skill.code, skillName: skill.name, startedAt: now.toISOString(),
        durationSeconds: skill.durationSeconds, healPercentPerSecond: skill.healMaxHpPercentPerSecond, appliedTicks: 0,
      };
      const [updated] = await tx.update(combatSessions).set({ combatState: state as unknown as Record<string, unknown> })
        .where(eq(combatSessions.id, session.id)).returning();
      return updated;
    });
  }

  public async advance(masterId: string, sessionId: string) {
    return db.transaction(async tx => {
      const [session] = await tx.select().from(combatSessions)
        .where(and(eq(combatSessions.id, sessionId), eq(combatSessions.masterId, masterId))).for('update').limit(1);
      if (!session) throw new CombatSessionError('Không tìm thấy phiên chiến đấu.', 404);
      if (session.status !== 'ACTIVE') return session;
      const state = readCombatState(session.combatState);
      const now = new Date();
      const regen = state.masterSkillEffect;
      if (regen) {
        const dueTicks = Math.min(regen.durationSeconds, Math.floor((now.getTime() - Date.parse(regen.startedAt)) / 1000));
        while (regen.appliedTicks < dueTicks) {
          for (const hero of state.heroes) {
            if (hero.hp <= 0) continue;
            const heal = Math.max(1, Math.floor(hero.maxHp * regen.healPercentPerSecond));
            hero.hp = Math.min(hero.maxHp, hero.hp + heal);
          }
          regen.appliedTicks += 1;
        }
        if (regen.appliedTicks >= regen.durationSeconds) state.masterSkillEffect = null;
      }
      const buff = session.activeBuffId ? TacticalBuffManager.AVAILABLE_BUFFS[session.activeBuffId] : undefined;

      // FUN-06-03-003 Status Effects Processing at Round Start (Poison / Bleed DoT)
      const allCombatants = [...state.heroes, ...state.enemies];
      for (const unit of allCombatants) {
        if (unit.hp <= 0 || !unit.statusEffects || unit.statusEffects.length === 0) continue;
        for (const effect of unit.statusEffects) {
          if (effect.type === 'POISON' || effect.type === 'BLEED') {
            const dotDmg = Math.max(1, Math.floor(effect.value));
            unit.hp = Math.max(0, unit.hp - dotDmg);
            state.log.push({
              round: state.round,
              actor: unit.name,
              target: unit.name,
              actionType: 'STATUS',
              damage: dotDmg,
              targetHp: unit.hp,
              note: `[STATUS] ${unit.name} suffers ${dotDmg} ${effect.type} damage!`,
            });
          }
          effect.remainingRounds -= 1;
        }
        unit.statusEffects = unit.statusEffects.filter(e => e.remainingRounds > 0);
      }

      let result: CombatReport['result'] | null = null;
      if (state.enemies.every(u => u.hp <= 0)) result = 'VICTORY';
      else if (state.heroes.every(u => u.hp <= 0)) result = 'DEFEAT';

      if (!result) {
        const actors = [
          ...state.heroes.map(unit => ({ side: 'HERO' as const, unit })),
          ...state.enemies.map(unit => ({ side: 'ENEMY' as const, unit })),
        ].sort((a, b) => {
          const aSpeed = a.unit.speed * (a.side === 'HERO' ? (buff?.speedMultiplier ?? 1) : 1);
          const bSpeed = b.unit.speed * (b.side === 'HERO' ? (buff?.speedMultiplier ?? 1) : 1);
          return bSpeed - aSpeed || a.side.localeCompare(b.side) || a.unit.id.localeCompare(b.unit.id);
        });

        for (const actor of actors) {
          if (actor.unit.hp <= 0) continue;

          // Check STUN status effect
          const isStunned = actor.unit.statusEffects?.some(e => e.type === 'STUN');
          if (isStunned) {
            state.log.push({
              round: state.round,
              actor: actor.unit.name,
              target: actor.unit.name,
              actionType: 'STATUS',
              damage: 0,
              targetHp: actor.unit.hp,
              note: `[STUN] ${actor.unit.name} is stunned and cannot act!`,
            });
            continue;
          }

          const opponentSide = actor.side === 'HERO' ? state.enemies : state.heroes;
          const allySide = actor.side === 'HERO' ? state.heroes : state.enemies;
          const aliveOpponents = opponentSide.filter(u => u.hp > 0);
          if (!aliveOpponents.length) {
            result = actor.side === 'HERO' ? 'VICTORY' : 'DEFEAT';
            break;
          }

          // FUN-06-02-003 AI Action Selection & FUN-06-02-004 AI Skill Execution
          let chosenSkill: UnitSkillState | null = null;
          if (actor.unit.skills && actor.unit.skills.length > 0) {
            const readySkills = actor.unit.skills.filter(s =>
              s.behaviorMode === 'AUTO' && (!s.cooldownUntilRound || s.cooldownUntilRound <= state.round)
            );
            if (readySkills.length > 0) {
              const healSkill = readySkills.find(s => s.effectType === 'HEAL_LOWEST_ALLY');
              const damagedAlly = allySide.filter(a => a.hp > 0 && a.hp < a.maxHp * 0.85);
              if (healSkill && damagedAlly.length > 0) {
                chosenSkill = healSkill;
              } else {
                chosenSkill = readySkills.find(s => s.effectType !== 'HEAL_LOWEST_ALLY') ?? readySkills[0];
              }
            }
          }

          if (chosenSkill && chosenSkill.effectType === 'HEAL_LOWEST_ALLY') {
            // AI Target Selection for Heal
            const aliveAllies = allySide.filter(u => u.hp > 0);
            aliveAllies.sort((a, b) => (a.hp / a.maxHp) - (b.hp / b.maxHp));
            const target = aliveAllies[0];
            const healAmount = Math.max(1, Math.floor(target.maxHp * chosenSkill.effectValue));
            target.hp = Math.min(target.maxHp, target.hp + healAmount);
            chosenSkill.cooldownUntilRound = state.round + (chosenSkill.cooldownRounds ?? 3);
            state.log.push({
              round: state.round,
              actor: actor.unit.name,
              target: target.name,
              actionType: 'HEAL',
              skillName: chosenSkill.name,
              damage: 0,
              heal: healAmount,
              targetHp: target.hp,
              note: `${actor.unit.name} casts ${chosenSkill.name} (+ ${healAmount} HP)`,
            });
          } else {
            // FUN-06-02-002 AI Target Selection
            let target: UnitState;
            if (aliveOpponents.length === 1) {
              target = aliveOpponents[0];
            } else {
              const lowestHpFoe = [...aliveOpponents].sort((a, b) => a.hp - b.hp)[0];
              const highestAtkFoe = [...aliveOpponents].sort((a, b) => b.attack - a.attack)[0];
              const frontlineFoe = [...aliveOpponents].sort((a, b) => a.slotIndex - b.slotIndex)[0];
              const dice = seededIndex(`${session.id}:${state.round}:${actor.unit.id}:target`, 100);

              if (actor.side === 'HERO' && state.targetPriority === 'LOWEST_HP') {
                target = lowestHpFoe;
              } else if (actor.side === 'HERO' && state.targetPriority === 'HIGHEST_ATK') {
                target = highestAtkFoe;
              } else if (actor.side === 'HERO' && state.targetPriority === 'FRONTLINE') {
                target = frontlineFoe;
              } else if (actor.unit.heroClass === 'ASSASSIN' || actor.unit.heroClass === 'WARRIOR') {
                target = dice < 70 ? lowestHpFoe : (dice < 90 ? highestAtkFoe : frontlineFoe);
              } else if (actor.unit.heroClass === 'TANK') {
                target = dice < 60 ? highestAtkFoe : frontlineFoe;
              } else if (actor.side === 'ENEMY') {
                target = dice < 50 ? lowestHpFoe : (dice < 80 ? frontlineFoe : aliveOpponents[seededIndex(`${session.id}:${state.round}:${actor.unit.id}:rand`, aliveOpponents.length)]);
              } else {
                target = dice < 50 ? lowestHpFoe : (dice < 80 ? highestAtkFoe : frontlineFoe);
              }
            }

            // FUN-06-03-005 Combat Element Advantage
            const elemMult = calculateElementMultiplier(actor.unit.element, target.element);

            let attack = actor.unit.attack;
            let defense = target.defense;
            if (actor.side === 'HERO' && buff) attack = Math.floor(attack * buff.attackMultiplier);
            if (actor.side === 'ENEMY' && buff) defense = Math.floor(defense * buff.defenseMultiplier);

            let skillMultiplier = 1;
            let skillName: string | undefined;
            if (chosenSkill) {
              skillMultiplier = chosenSkill.effectValue;
              skillName = chosenSkill.name;
              chosenSkill.cooldownUntilRound = state.round + (chosenSkill.cooldownRounds ?? 3);

              // Secondary skill mechanics (FUN-06-03-002 / FUN-06-03-003):
              if (chosenSkill.skillCode.includes('TANK')) {
                // Shield Bash grants self a Shield absorbing 15% Max HP
                const shieldGain = Math.floor(actor.unit.maxHp * 0.15);
                actor.unit.shield = (actor.unit.shield ?? 0) + shieldGain;
              } else if (chosenSkill.skillCode.includes('ASSASSIN')) {
                // Shadow Cut inflicts Bleed DoT (8% target Max HP for 2 rounds)
                target.statusEffects = target.statusEffects ?? [];
                target.statusEffects.push({ type: 'BLEED', value: Math.floor(target.maxHp * 0.08), remainingRounds: 2 });
              } else if (chosenSkill.skillCode.includes('ARCHER')) {
                // Piercing Shot ignores 30% of target defense
                defense = Math.floor(defense * 0.7);
              }
            }

            // FUN-06-03-004 Critical Hit Calculation
            const critRoll = seededIndex(`${session.id}:${state.round}:${actor.unit.id}:crit`, 100);
            const isCritical = critRoll < Math.round((actor.unit.critRate ?? 0.10) * 100);

            // FUN-06-03-001 Damage Calculation
            const effectiveAttack = Math.floor(attack * skillMultiplier * elemMult);
            const damageCalc = calculateDamage(effectiveAttack, defense, isCritical, actor.unit.critDamage ?? 0.5);
            let finalDamage = damageCalc.damage;

            // Shield Absorption
            if (target.shield && target.shield > 0) {
              if (target.shield >= finalDamage) {
                target.shield -= finalDamage;
                finalDamage = 0;
              } else {
                finalDamage -= target.shield;
                target.shield = 0;
              }
            }

            target.hp = Math.max(0, target.hp - finalDamage);

            // Log details
            const critPrefix = isCritical ? '[CRIT] ' : '';
            const elemPrefix = elemMult > 1.0 ? '[ELEMENT +25%] ' : (elemMult < 1.0 ? '[ELEMENT -20%] ' : '');
            const skillPrefix = chosenSkill ? `[${skillName}] ` : '';
            const logNote = `${critPrefix}${elemPrefix}${skillPrefix}${actor.unit.name} deals ${damageCalc.damage} dmg to ${target.name}`;

            state.log.push({
              round: state.round,
              actor: actor.unit.name,
              target: target.name,
              actionType: isCritical ? 'CRIT' : (chosenSkill ? 'SKILL' : 'ATTACK'),
              skillName,
              isCritical,
              elementMultiplier: elemMult,
              damage: damageCalc.damage,
              targetHp: target.hp,
              note: logNote,
            });

            // FUN-06-02-006 AI Relationship / Synergy Assist Strike
            if (actor.side === 'HERO' && target.hp > 0) {
              const livingAllies = allySide.filter(u => u.hp > 0 && u.id !== actor.unit.id);
              if (livingAllies.length > 0) {
                const assistRoll = seededIndex(`${session.id}:${state.round}:${actor.unit.id}:assist`, 100);
                if (assistRoll < 15) {
                  const assister = livingAllies[seededIndex(`${session.id}:${state.round}:${actor.unit.id}:assister`, livingAllies.length)];
                  const assistAtk = Math.max(1, Math.floor(assister.attack * 0.3 * (buff?.attackMultiplier ?? 1)));
                  const assistCalc = calculateDamage(assistAtk, target.defense, false);
                  target.hp = Math.max(0, target.hp - assistCalc.damage);
                  state.log.push({
                    round: state.round,
                    actor: assister.name,
                    target: target.name,
                    actionType: 'ASSIST',
                    damage: assistCalc.damage,
                    targetHp: target.hp,
                    note: `[SYNERGY] ${assister.name} executes an Assist Strike for ${assistCalc.damage} dmg!`,
                  });
                }
              }
            }
          }

          if (state.enemies.every(unit => unit.hp <= 0)) { result = 'VICTORY'; break; }
          if (state.heroes.every(unit => unit.hp <= 0)) { result = 'DEFEAT'; break; }
        }
      }
      state.round += 1;

      let report = session.battleReport as CombatReport | null;
      let status = session.status;
      if (result) {
        // FUN-06-05-001 Determine Battle Result: VICTORY or DEFEAT
        status = result;
        const defeated = state.heroes.filter(hero => hero.hp <= 0);

        // FUN-06-05-002 Process Hero Survival: track living heroes and persist remaining HP
        const survivorsList: CombatSurvivor[] = state.heroes
          .filter(hero => hero.hp > 0)
          .map(hero => ({
            id: hero.id,
            name: hero.name,
            hp: hero.hp,
            maxHp: hero.maxHp,
            hpPercent: Math.round((hero.hp / hero.maxHp) * 100),
          }));

        // FUN-06-05-003 Process Battle Casualties: permadeath for normal heroes, disabled for special/limited
        const fallenHeroes: CombatFallenHero[] = [];

        for (const hero of state.heroes) {
          const isFallen = hero.hp <= 0;
          const deathType = isFallen ? (hero.origin === 'NORMAL' ? 'PERMADEATH' : 'DISABLED') : null;
          // FUN-06-05-007 Update Hero Condition: update health condition (DEAD/DISABLED if 0 HP, INJURED if <= 25% maxHp, else HEALTHY)
          const conditionState = isFallen
            ? (deathType === 'PERMADEATH' ? 'DEAD' : 'DISABLED')
            : (hero.hp <= Math.floor(hero.maxHp * 0.25) ? 'INJURED' : 'HEALTHY');

          await tx.update(heroes).set({
            hp: Math.max(0, hero.hp),
            state: conditionState,
            updatedAt: new Date(),
          }).where(and(eq(heroes.id, hero.id), eq(heroes.masterId, masterId)));

          if (deathType) {
            const droppedEquipment: { id: string; templateCode: string; name: string; slotType: string; bonusHp: number; bonusAttack: number; bonusDefense: number; bonusSpeed: number }[] = [];
            if (deathType === 'PERMADEATH') {
              const equipped = await tx.select({ item: equipmentInstances, template: equipmentTemplates })
                .from(equipmentInstances).innerJoin(equipmentTemplates, eq(equipmentInstances.templateCode, equipmentTemplates.code))
                .where(and(eq(equipmentInstances.masterId, masterId), eq(equipmentInstances.equippedHeroId, hero.id), eq(equipmentInstances.location, 'EQUIPPED')))
                .for('update');
              for (const row of equipped) {
                droppedEquipment.push({ id: row.item.id, templateCode: row.template.code, name: row.template.name, slotType: row.template.slotType, bonusHp: row.template.bonusHp, bonusAttack: row.template.bonusAttack, bonusDefense: row.template.bonusDefense, bonusSpeed: row.template.bonusSpeed });
                await tx.update(equipmentInstances).set({
                  location: 'FLOOR_DROP', equippedHeroId: null, dropWorldId: session.worldId,
                  dropFloor: state.floor, droppedAt: new Date(), pickedUpAt: null,
                }).where(eq(equipmentInstances.id, row.item.id));
              }
            }
            await tx.insert(heroDeathRecords).values({
              id: uuidv4(), heroId: hero.id, masterId, combatSessionId: session.id,
              summonOrigin: hero.origin ?? 'NORMAL', deathType, droppedEquipment,
              cause: 'PVE_COMBAT', recordedAt: new Date(),
            });
            await tx.delete(combatPartySlots).where(and(eq(combatPartySlots.masterId, masterId), eq(combatPartySlots.heroId, hero.id)));
            fallenHeroes.push({
              id: hero.id,
              name: hero.name,
              origin: hero.origin,
              deathType,
              droppedEquipmentCount: droppedEquipment.length,
              droppedEquipment,
            });
          }
        }
        let expReward = 0;
        let battleSilverReward = 0;
        const masterExpReward = result === 'VICTORY' ? 300 : 0;
        const masterLevelUps: CombatReport['masterLevelUps'] = [];
        const heroLevelUps: CombatReport['heroLevelUps'] = [];
        if (result === 'VICTORY') {
          const templates = await tx.select().from(enemyTemplates).where(eq(enemyTemplates.isActive, true));
          const templateByCode = new Map(templates.map(row => [row.code, row]));
          for (const enemy of state.enemies) {
            const foe = templateByCode.get(enemy.templateCode);
            if (!foe) continue;
            expReward += Math.floor(foe.baseExpReward * state.difficultyMultiplier);
            battleSilverReward += Math.floor(foe.baseSilverReward * state.difficultyMultiplier);
          }
          const survivors = state.heroes.filter(hero => hero.hp > 0);
          const expEach = survivors.length ? Math.floor(expReward / survivors.length) : 0;
          const remainder = survivors.length ? expReward % survivors.length : 0;
          for (const [index, hero] of survivors.entries()) {
            const award = expEach + (index < remainder ? 1 : 0);
            const [record] = await tx.select().from(heroes).where(and(eq(heroes.id, hero.id), eq(heroes.masterId, masterId))).for('update').limit(1);
            if (!record) continue;
            const totalExp = record.exp + BigInt(award);
            let level = record.level;
            let maxHp = record.maxHp;
            let hp = hero.hp;
            let attack = record.attack;
            let defense = record.defense;
            let speed = record.speed;
            const [promotionConfig] = record.promotionRank === 0 ? [] : await tx.select().from(heroDevelopmentConfigs)
              .where(and(eq(heroDevelopmentConfigs.action, 'PROMOTION'), eq(heroDevelopmentConfigs.rank, record.promotionRank))).limit(1);
            const levelCap = promotionConfig?.maxLevelAfter ?? 20;
            const growth = await tx.select().from(heroLevelConfigs)
              .where(and(gt(heroLevelConfigs.level, record.level), lte(heroLevelConfigs.level, levelCap))).orderBy(asc(heroLevelConfigs.level));
            for (const config of growth) {
              if (totalExp < config.cumulativeExpRequired || config.level <= level) continue;
              const oldMaxHp = maxHp;
              maxHp = Math.floor(maxHp * config.statGrowthMultiplier);
              hp = Math.min(maxHp, hp + maxHp - oldMaxHp);
              attack = Math.floor(attack * config.statGrowthMultiplier);
              defense = Math.floor(defense * config.statGrowthMultiplier);
              speed = Math.floor(speed * config.statGrowthMultiplier);
              level = config.level;
            }
            if (level > record.level) heroLevelUps.push({ heroId: hero.id, name: hero.name, fromLevel: record.level, toLevel: level });
            await tx.update(heroes).set({ exp: totalExp, level, hp, maxHp, attack, defense, speed, updatedAt: new Date() }).where(eq(heroes.id, hero.id));
          }
          const [masterRecord] = await tx.select().from(masters).where(eq(masters.id, masterId)).for('update').limit(1);
          if (masterRecord) {
            let masterExp = masterRecord.exp + BigInt(masterExpReward);
            let masterLevel = masterRecord.level;
            const masterGrowth = await tx.select().from(masterLevelConfigs).where(gt(masterLevelConfigs.level, masterRecord.level)).orderBy(asc(masterLevelConfigs.level));
            for (const config of masterGrowth) {
              if (masterExp < config.expRequired || config.level <= masterLevel) continue;
              masterExp -= config.expRequired;
              masterLevel = config.level;
            }
            if (masterLevel > masterRecord.level) masterLevelUps.push({ fromLevel: masterRecord.level, toLevel: masterLevel });
            await tx.update(masters).set({ exp: masterExp, level: masterLevel, updatedAt: new Date() }).where(eq(masters.id, masterId));
          }
          const floorEventSilverReward = state.floorEvent.eventType === 'CACHE' ? state.floorEvent.silverReward : 0;
          const silverReward = battleSilverReward + floorEventSilverReward;
          const rewardTime = new Date();
          await tx.update(masters).set({ silverCoins: sql`${masters.silverCoins} + ${BigInt(silverReward)}`, updatedAt: rewardTime }).where(eq(masters.id, masterId));
          if (battleSilverReward > 0) await tx.insert(currencyTransactions).values({
            id: uuidv4(), masterId, currencyType: 'SILVER', amountDelta: BigInt(battleSilverReward),
            transactionType: 'BATTLE_REWARD', referenceId: session.id, createdAt: rewardTime,
          });
          if (floorEventSilverReward > 0) await tx.insert(currencyTransactions).values({
            id: uuidv4(), masterId, currencyType: 'SILVER', amountDelta: BigInt(floorEventSilverReward),
            transactionType: 'DUNGEON_EVENT_REWARD', referenceId: session.id, createdAt: rewardTime,
          });
          await tx.update(worlds).set({ currentFloor: state.floor + 1 }).where(eq(worlds.id, session.worldId));
        }
        if (defeated.length) await tx.delete(combatPartySlots).where(and(eq(combatPartySlots.masterId, masterId), inArray(combatPartySlots.heroId, defeated.map(hero => hero.id))));
        const floorEventSilverReward = result === 'VICTORY' && state.floorEvent.eventType === 'CACHE' ? state.floorEvent.silverReward : 0;
        report = {
          result, rounds: state.round - 1, floor: state.floor, nextFloor: result === 'VICTORY' ? state.floor + 1 : state.floor,
          floorEvent: { code: state.floorEvent.code, name: state.floorEvent.name, description: state.floorEvent.description, eventType: state.floorEvent.eventType },
          expReward, silverReward: battleSilverReward + floorEventSilverReward, battleSilverReward, floorEventSilverReward, masterExpReward, masterLevelUps, heroLevelUps, survivors: survivorsList, fallenHeroes, log: state.log,
        };
      }
      const [updated] = await tx.update(combatSessions).set({
        status, combatState: state as unknown as Record<string, unknown>,
        ...(report ? { battleReport: report as unknown as Record<string, unknown>, finishedAt: new Date() } : {}),
      }).where(eq(combatSessions.id, session.id)).returning();
      return updated;
    });
  }


  public async setTargetPriority(masterId: string, sessionId: string, priority: 'LOWEST_HP' | 'HIGHEST_ATK' | 'FRONTLINE' | 'BALANCED') {
    return db.transaction(async tx => {
      const [session] = await tx.select().from(combatSessions)
        .where(and(eq(combatSessions.id, sessionId), eq(combatSessions.masterId, masterId))).for('update').limit(1);
      if (!session) throw new CombatSessionError('Phiên chiến đấu không tồn tại.', 404);
      if (session.status !== 'ACTIVE') throw new CombatSessionError('Phiên chiến đấu đã kết thúc.', 409);

      const state = readCombatState(session.combatState);
      state.targetPriority = priority;
      state.log.push({
        round: state.round,
        actor: 'Master',
        target: 'Tactics',
        actionType: 'STATUS',
        damage: 0,
        targetHp: 0,
        note: `[COMMAND] Master ordered Target Priority: ${priority}`,
      });

      const [updated] = await tx.update(combatSessions).set({
        combatState: state as unknown as Record<string, unknown>,
      }).where(eq(combatSessions.id, session.id)).returning();

      return updated;
    });
  }

  public async retreat(masterId: string, sessionId: string) {
    return db.transaction(async tx => {
      const [session] = await tx.select().from(combatSessions)
        .where(and(eq(combatSessions.id, sessionId), eq(combatSessions.masterId, masterId))).for('update').limit(1);
      if (!session) throw new CombatSessionError('Phiên chiến đấu không tồn tại.', 404);
      if (session.status !== 'ACTIVE') throw new CombatSessionError('Phiên chiến đấu đã kết thúc.', 409);

      const state = readCombatState(session.combatState);
      const survivors: CombatSurvivor[] = state.heroes.filter(h => h.hp > 0).map(h => ({
        id: h.id,
        name: h.name,
        hp: h.hp,
        maxHp: h.maxHp,
        hpPercent: Math.round((h.hp / h.maxHp) * 100),
      }));

      for (const hero of state.heroes) {
        if (hero.hp > 0) {
          const conditionState = hero.hp <= Math.floor(hero.maxHp * 0.25) ? 'INJURED' : 'HEALTHY';
          await tx.update(heroes).set({
            hp: hero.hp,
            state: conditionState,
            updatedAt: new Date(),
          }).where(and(eq(heroes.id, hero.id), eq(heroes.masterId, masterId)));
        }
      }

      state.log.push({
        round: state.round,
        actor: 'Master',
        target: 'Team',
        actionType: 'STATUS',
        damage: 0,
        targetHp: 0,
        note: '[RETREAT] Master ordered tactical retreat. Surviving Heroes preserved!',
      });

      const report: CombatReport = {
        result: 'DEFEAT',
        rounds: state.round,
        floor: state.floor,
        nextFloor: state.floor,
        floorEvent: { code: state.floorEvent.code, name: state.floorEvent.name, description: state.floorEvent.description, eventType: state.floorEvent.eventType },
        expReward: 0,
        silverReward: 0,
        battleSilverReward: 0,
        floorEventSilverReward: 0,
        masterExpReward: 0,
        masterLevelUps: [],
        heroLevelUps: [],
        survivors,
        fallenHeroes: [],
        log: state.log,
      };

      const [updated] = await tx.update(combatSessions).set({
        status: 'DEFEAT',
        combatState: state as unknown as Record<string, unknown>,
        battleReport: report as unknown as Record<string, unknown>,
        finishedAt: new Date(),
      }).where(eq(combatSessions.id, session.id)).returning();

      return updated;
    });
  }

}
