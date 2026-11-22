import type { GameDatabase } from '../../database/transaction.js';
/**
 * Combat v2 simulation service.
 *
 * Loads a party and an enemy set, builds Combat v2 units from the persisted
 * base stats (falling back to the legacy columns for pre-v2 demo Heroes) and
 * runs the pure engine. Persistent sessions and private-map encounters share
 * the transaction-aware settlement helper; simulation never charges rations.
 */

import { and, asc, desc, eq, gt, inArray, isNull } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import {
  heroInjuries, heroSurvivalStates, heroPersonalityTraits, heroRelationships,
  combatSessions, enemyTemplates, equipmentInstances, equipmentTemplates, heroElementAffinities, heroes,
  heroImprints, heroSkillInstances, heroSkillTemplates, heroTemplates, imprintDefinitions, masters, worlds,
} from '../../database/drizzle-schema.js';
import {
  aggregateEquipment, combatPowerV2, combineImprintEffects, isEmptyImprintEffects, mulberry32,
  type DerivedOffsets, type DerivedStats, type ElementAffinity, type EquipmentItemInput, type EquipmentV2Stats,
  type HeroClass, type ImprintCombatEffects, type StarRating,
} from '@infiniti-gacha/shared';
import { isV2Origin, originOf, progressionFor } from '../hero/hero-progression.js';
import { survivalService } from '../survival/survival.service.js';
import { medicalService } from '../medical/medical.service.js';
import { questService } from '../quest/quest.service.js';
import { personalityService } from '../personality/personality.service.js';
import { resolveBattleV2, type CombatV2Skill, type CombatV2UnitInput } from './combat-v2.engine.js';
import { settleCombat } from './combat-settlement.js';
import { eventService } from '../liveops/event.service.js';
import { assertNoPrivatePve, chargeCombatDispatch } from './combat-readiness.js';
import { starvationMultiplier } from '../survival/survival-rules.js';
import { injuryMultiplier } from '../medical/medical-rules.js';
import { loyaltyCombatMultiplier, relationshipTier, resonanceMultiplier } from '../personality/personality-rules.js';

export class CombatV2Error extends Error {
  constructor(message: string, readonly statusCode = 400) {
    super(message);
    this.name = 'CombatV2Error';
  }
}

const EMPTY_DERIVED: Omit<DerivedStats, 'maxHp' | 'maxMp' | 'atk' | 'matk' | 'def' | 'mdef'> = {
  hpRegen: 0, mpRegen: 0, critRate: 5, critDamage: 150, accuracy: 0, evasion: 0,
  blockRate: 0, blockEffect: 0, critResistance: 0, critDamageReduction: 0,
  damageReduction: 0, tenacity: 0, armorPen: 0, magicPen: 0, damageBonus: 0, lifesteal: 0,
};

function legacyStats(hero: typeof heroes.$inferSelect, gear = { hp: 0, attack: 0, defense: 0, speed: 0 }): DerivedStats {
  return {
    ...EMPTY_DERIVED,
    maxHp: hero.maxHp + gear.hp,
    maxMp: Math.max(0, hero.maxMp),
    atk: hero.attack + gear.attack,
    matk: hero.attack + gear.attack,
    def: hero.defense + gear.defense,
    mdef: hero.defense + gear.defense,
  };
}

function affinityFromRow(row: typeof heroElementAffinities.$inferSelect): ElementAffinity {
  return {
    FIRE: row.fire, WATER: row.water, WIND: row.wind, EARTH: row.earth,
    LIGHT: row.light, DARK: row.dark, LIGHTNING: row.lightning,
  };
}

function strongestElement(affinity: ElementAffinity): keyof ElementAffinity {
  return (Object.entries(affinity) as [keyof ElementAffinity, number][])
    .sort((a, b) => b[1] - a[1])[0][0];
}

function applyCombatModifiers(
  stats: DerivedStats,
  readiness: number,
  loyalty: number,
  resonance: number,
): DerivedStats {
  return {
    ...stats,
    atk: Math.max(1, Math.round(stats.atk * readiness * loyalty * resonance)),
    matk: Math.max(1, Math.round(stats.matk * readiness * loyalty * resonance)),
    def: Math.max(0, Math.round(stats.def * readiness * loyalty)),
    mdef: Math.max(0, Math.round(stats.mdef * readiness * loyalty)),
  };
}

export class CombatV2Service {
  async buildHeroUnits(
    heroIds: string[],
    masterId: string,
    side: 'HERO' | 'ENEMY' = 'HERO',
    context?: { database: GameDatabase; readiness: Record<string, number>; injuries: Record<string, number>; personality: Record<string, { loyalty: number; resonance: number }> },
  ): Promise<CombatV2UnitInput[]> {
    if (heroIds.length === 0) return [];
    const database = context?.database ?? db;
    const rows = await database.select({ hero: heroes, template: heroTemplates })
      .from(heroes).leftJoin(heroTemplates, eq(heroTemplates.code, heroes.configId))
      .where(and(eq(heroes.masterId, masterId), inArray(heroes.id, heroIds)))
      .orderBy(asc(heroes.createdAt));
    if (rows.length === 0) return [];

    const skills = await database.select({ instance: heroSkillInstances, template: heroSkillTemplates })
      .from(heroSkillInstances).innerJoin(heroSkillTemplates, eq(heroSkillInstances.skillCode, heroSkillTemplates.code))
      .where(and(inArray(heroSkillInstances.heroId, heroIds), eq(heroSkillInstances.isUnlocked, true)));
    const affinities = await database.select().from(heroElementAffinities).where(inArray(heroElementAffinities.heroId, heroIds));

    const imprintRows = await database.select({ owned: heroImprints, definition: imprintDefinitions })
      .from(heroImprints).innerJoin(imprintDefinitions, eq(imprintDefinitions.code, heroImprints.imprintCode))
      .where(inArray(heroImprints.heroId, heroIds));
    const imprintBonus = (heroId: string) => imprintRows
      .filter(row => row.owned.heroId === heroId)
      .reduce((sum, row) => ({
        str: sum.str + row.definition.bonusStr,
        int: sum.int + row.definition.bonusInt,
        sta: sum.sta + row.definition.bonusSta,
        agi: sum.agi + row.definition.bonusAgi,
        hp: sum.hp + row.definition.bonusHp,
        atk: sum.atk + row.definition.bonusAtk,
        def: sum.def + row.definition.bonusDef,
      }), { str: 0, int: 0, sta: 0, agi: 0, hp: 0, atk: 0, def: 0 });

    const imprintEffectsFor = (heroId: string): ImprintCombatEffects => combineImprintEffects(
      imprintRows
        .filter(row => row.owned.heroId === heroId)
        .map(row => ({
          abilityCode: row.definition.abilityCode,
          abilityParams: row.definition.abilityParams,
          rankLevel: row.owned.rankLevel,
        })),
    );
    const gearRows = await database.select({ item: equipmentInstances, template: equipmentTemplates })
      .from(equipmentInstances).innerJoin(equipmentTemplates, eq(equipmentInstances.templateCode, equipmentTemplates.code))
      .where(and(
        eq(equipmentInstances.masterId, masterId),
        eq(equipmentInstances.location, 'EQUIPPED'),
        inArray(equipmentInstances.equippedHeroId, heroIds),
      ));
    const itemsByHero = new Map<string, EquipmentItemInput[]>();
    for (const row of gearRows) {
      if (!row.item.equippedHeroId) continue;
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

    const [injuryPenalties, personality] = context ? [context.injuries, context.personality] as const : await Promise.all([
      medicalService.penaltyByHero(masterId).catch(() => ({} as Record<string, number>)),
      personalityService.combatModifiers(masterId).catch(() => ({} as Record<string, { loyalty: number; resonance: number }>)),
    ]);
    let readiness: Record<string, number> = {};
    try {
      readiness = context?.readiness ?? (await survivalService.battleReadiness(masterId, undefined, false)).multipliers ?? {};
    } catch {
      readiness = {};
    }

    return rows.map(({ hero, template }, index) => {
      const useV2 = isV2Origin(hero.originStats);
      const heroGear = itemsByHero.get(hero.id) ?? [];
      const aggregatedGear = aggregateEquipment(heroGear);
      const imprint = imprintBonus(hero.id);
      const classCode = hero.classCode as HeroClass;

      const combinedOffsets: DerivedOffsets = {
        ...aggregatedGear.derivedOffsets,
        hpBase: (aggregatedGear.derivedOffsets.hpBase ?? 0) + imprint.hp,
        atkBase: (aggregatedGear.derivedOffsets.atkBase ?? 0) + imprint.atk,
        defBase: (aggregatedGear.derivedOffsets.defBase ?? 0) + imprint.def,
      };

      const snapshot = useV2
        ? progressionFor({
          origin: originOf(hero.originStats),
          star: hero.rarity as StarRating,
          level: hero.level,
          classCode,
          training: hero.trainingStats,
          awakeningRank: hero.awakeningRank,
          imprint: {
            str: imprint.str,
            int: imprint.int,
            sta: imprint.sta,
            agi: imprint.agi,
          },
          equipmentBase: aggregatedGear.baseStats,
          equipmentOffsets: combinedOffsets,
          hpPct: 1,
          mpPct: 1,
        })
        : null;

      const stats = snapshot
        ? snapshot.derived
        : legacyStats(hero, {
          hp: aggregatedGear.derivedOffsets.hpBase ?? 0,
          attack: aggregatedGear.derivedOffsets.atkBase ?? 0,
          defense: aggregatedGear.derivedOffsets.defBase ?? 0,
          speed: (aggregatedGear.baseStats.agi ?? 0) + (aggregatedGear.derivedOffsets.agi ?? 0),
        });
      if (!snapshot) {
        stats.maxHp += imprint.hp;
        stats.atk += imprint.atk;
        stats.matk += imprint.atk;
        stats.def += imprint.def;
        stats.mdef += imprint.def;
      }
      const modified = applyCombatModifiers(
        stats,
        (readiness[hero.id] ?? 1) * (injuryPenalties[hero.id] ?? 1),
        personality[hero.id]?.loyalty ?? 1,
        personality[hero.id]?.resonance ?? 1,
      );
      const affinityRow = affinities.find(row => row.heroId === hero.id);
      const affinity = affinityRow ? affinityFromRow(affinityRow) : null;
      const element = affinity ? strongestElement(affinity) : undefined;
      const imprintEffects = imprintEffectsFor(hero.id);

      const unitSkills: CombatV2Skill[] = skills
        .filter(row => row.instance.heroId === hero.id)
        .map(row => ({
          code: row.template.code,
          multiplier: row.template.effectValue + (row.instance.skillLevel - 1) * row.template.upgradeIncrement,
          cooldownRounds: Math.max(1, row.template.cooldownSeconds),
          effectType: row.template.effectType === 'HEAL_LOWEST_ALLY' ? 'HEAL_LOWEST_ALLY' : 'DAMAGE_SINGLE',
          effectValue: row.template.effectValue + (row.instance.skillLevel - 1) * row.template.upgradeIncrement,
          element: classCode === 'MAGE' && row.template.effectType !== 'HEAL_LOWEST_ALLY' ? element : undefined,
        }));

      return {
        id: hero.id,
        name: hero.name,
        side,
        slotIndex: index,
        agi: snapshot
          ? (snapshot.base.agi + (aggregatedGear.derivedOffsets.agi ?? 0))
          : (Math.max(1, hero.speed) + (aggregatedGear.baseStats.agi ?? 0) + (aggregatedGear.derivedOffsets.agi ?? 0)),
        stats: modified,
        damageType: classCode === 'MAGE' ? 'MAGICAL' : 'PHYSICAL',
        affinity,
        skills: unitSkills,
        imprintEffects: isEmptyImprintEffects(imprintEffects) ? undefined : imprintEffects,
      };
    });
  }

  /** Transactional unit loading must not call global services that open another connection. */
  private async unitContext(database: GameDatabase, masterId: string, heroIds: string[]) {
    const now = new Date();
    const survival = await database.select().from(heroSurvivalStates).where(inArray(heroSurvivalStates.heroId, heroIds));
    const injuries = await database.select().from(heroInjuries).where(and(inArray(heroInjuries.heroId, heroIds), isNull(heroInjuries.healedAt), gt(heroInjuries.naturalHealAt, now)));
    const traits = await database.select().from(heroPersonalityTraits).where(inArray(heroPersonalityTraits.heroId, heroIds));
    const relations = await database.select().from(heroRelationships).where(and(eq(heroRelationships.masterId, masterId), inArray(heroRelationships.heroAId, heroIds), inArray(heroRelationships.heroBId, heroIds)));
    const context = { database, readiness: {} as Record<string, number>, injuries: {} as Record<string, number>, personality: {} as Record<string, { loyalty: number; resonance: number }> };
    for (const heroId of heroIds) {
      context.readiness[heroId] = starvationMultiplier(survival.find(row => row.heroId === heroId)?.hungerScore ?? 0);
      context.injuries[heroId] = Math.min(1, ...injuries.filter(row => row.heroId === heroId).map(row => injuryMultiplier(row.penaltyPercent)));
      context.personality[heroId] = {
        loyalty: loyaltyCombatMultiplier(traits.find(row => row.heroId === heroId)?.loyaltyScore ?? 50),
        resonance: Math.max(1, ...relations.filter(row => row.heroAId === heroId || row.heroBId === heroId).map(row => resonanceMultiplier(relationshipTier(row.affinityPoints)))),
      };
    }
    return context;
  }

  async simulate(masterId: string, input: {
    heroIds?: unknown; enemyCodes?: unknown; maxRounds?: unknown; seed?: unknown; persist?: unknown;
  }, transaction?: GameDatabase) {
    const database = transaction ?? db;
    const heroIds = Array.isArray(input.heroIds) ? input.heroIds.map(String) : [];
    if (heroIds.length === 0) throw new CombatV2Error('ERR_COMBAT_V2_NO_HEROES', 400);
    if (heroIds.length > 5) throw new CombatV2Error('ERR_COMBAT_V2_PARTY_TOO_LARGE', 400);

    const rows = await database.select({ hero: heroes, template: heroTemplates })
      .from(heroes).leftJoin(heroTemplates, eq(heroTemplates.code, heroes.configId))
      .where(and(eq(heroes.masterId, masterId), inArray(heroes.id, heroIds)))
      .orderBy(asc(heroes.createdAt));
    if (rows.length !== heroIds.length) throw new CombatV2Error('ERR_COMBAT_V2_HERO_NOT_FOUND', 404);
    for (const { hero } of rows) {
      if (hero.state === 'DEAD' || hero.state === 'DISABLED' || hero.hp <= 0) {
        throw new CombatV2Error('ERR_COMBAT_V2_HERO_UNAVAILABLE', 409);
      }
    }

    const context = transaction ? await this.unitContext(transaction, masterId, heroIds) : undefined;
    const heroUnits = await this.buildHeroUnits(heroIds, masterId, 'HERO', context);

    const requestedCodes = Array.isArray(input.enemyCodes) ? input.enemyCodes.map(String) : [];
    const enemyRows = requestedCodes.length > 0
      ? await database.select().from(enemyTemplates).where(and(eq(enemyTemplates.isActive, true), inArray(enemyTemplates.code, requestedCodes)))
      : await database.select().from(enemyTemplates).where(eq(enemyTemplates.isActive, true)).orderBy(asc(enemyTemplates.code)).limit(3);
    if (enemyRows.length === 0) throw new CombatV2Error('ERR_COMBAT_V2_NO_ENEMIES', 409);

    const enemyUnits: CombatV2UnitInput[] = enemyRows.map((foe, index) => ({
      id: foe.code,
      name: foe.name,
      side: 'ENEMY',
      slotIndex: index,
      agi: Math.max(1, foe.baseSpeed),
      damageType: 'PHYSICAL',
      stats: {
        ...EMPTY_DERIVED,
        maxHp: foe.baseHp,
        maxMp: 0,
        atk: foe.baseAttack,
        matk: foe.baseAttack,
        def: foe.baseDefense,
        mdef: foe.baseDefense,
      },
      skills: [],
    }));

    const seed = Number.isFinite(Number(input.seed)) ? Number(input.seed) : Date.now() % 2_147_483_647;
    const maxRounds = Number.isFinite(Number(input.maxRounds)) ? Number(input.maxRounds) : undefined;
    const report = resolveBattleV2(heroUnits, enemyUnits, {
      maxRounds, random: mulberry32(seed),
    });

    let sessionId: string | null = null;
    if (input.persist === true) {
      const [world] = await database.select().from(worlds).where(eq(worlds.masterId, masterId)).limit(1);
      if (!world) throw new CombatV2Error('ERR_COMBAT_V2_NO_WORLD', 409);
      sessionId = uuidv4();
      const now = new Date();
      await database.insert(combatSessions).values({
        id: sessionId, masterId, worldId: world.id, partyId: null,
        status: 'COMPLETED', createdAt: now, finishedAt: now,
        combatState: { engine: 'V2', seed } as unknown as Record<string, unknown>,
        battleReport: report as unknown as Record<string, unknown>,
      });
    }

    return {
      ...report,
      seed,
      sessionId,
      heroes: heroUnits.map(unit => ({
        id: unit.id,
        name: unit.name,
        classCode: unit.side === 'HERO' ? rows.find(row => row.hero.id === unit.id)?.hero.classCode : undefined,
        combatPower: combatPowerV2(unit.stats),
        imprintEffects: unit.imprintEffects ?? null,
      })),
    };
  }

  async sessions(masterId: string) {
    return db.select({
      id: combatSessions.id,
      status: combatSessions.status,
      createdAt: combatSessions.createdAt,
      finishedAt: combatSessions.finishedAt,
      battleReport: combatSessions.battleReport,
    }).from(combatSessions)
      .where(eq(combatSessions.masterId, masterId))
      .orderBy(desc(combatSessions.createdAt)).limit(20);
  }

  /** Opens a two-step session; validation, rations and session creation commit together. */
  async start(masterId: string, input: {
    heroIds?: unknown; enemyCodes?: unknown; maxRounds?: unknown; seed?: unknown;
  }) {
    const heroIds = Array.isArray(input.heroIds) ? input.heroIds.map(String) : [];
    if (heroIds.length === 0 || heroIds.length > 5 || new Set(heroIds).size !== heroIds.length) throw new CombatV2Error('ERR_COMBAT_V2_INVALID_PARTY', 400);
    const enemyCodes = Array.isArray(input.enemyCodes) ? input.enemyCodes.map(String) : [];
    const seed = Number.isFinite(Number(input.seed)) ? Number(input.seed) : Date.now() % 2_147_483_647;
    const maxRounds = input.maxRounds === undefined ? 30 : Number(input.maxRounds);
    if (!Number.isInteger(maxRounds) || maxRounds < 1 || maxRounds > 100) throw new CombatV2Error('ERR_COMBAT_V2_INVALID_ROUNDS', 400);
    return db.transaction(async tx => {
      await tx.select({ id: masters.id }).from(masters).where(eq(masters.id, masterId)).for('update');
      await assertNoPrivatePve(masterId, tx);
      const [active] = await tx.select({ id: combatSessions.id }).from(combatSessions)
        .where(and(eq(combatSessions.masterId, masterId), inArray(combatSessions.status, ['ACTIVE', 'RESOLVING'])));
      if (active) throw new CombatV2Error('ERR_COMBAT_V2_SESSION_ACTIVE', 409);
      const owned = await tx.select().from(heroes).where(and(eq(heroes.masterId, masterId), inArray(heroes.id, heroIds))).orderBy(asc(heroes.id)).for('update');
      if (owned.length !== heroIds.length) throw new CombatV2Error('ERR_COMBAT_V2_HERO_NOT_FOUND', 404);
      if (owned.some(hero => hero.state === 'DEAD' || hero.state === 'DISABLED' || hero.hp <= 0)) throw new CombatV2Error('ERR_COMBAT_V2_HERO_UNAVAILABLE', 409);
      const [world] = await tx.select().from(worlds).where(eq(worlds.masterId, masterId)).orderBy(asc(worlds.createdAt), asc(worlds.id)).limit(1);
      if (!world) throw new CombatV2Error('ERR_COMBAT_V2_NO_WORLD', 409);
      if (enemyCodes.length) {
        const foes = await tx.select({ code: enemyTemplates.code }).from(enemyTemplates).where(and(eq(enemyTemplates.isActive, true), inArray(enemyTemplates.code, enemyCodes)));
        if (foes.length !== new Set(enemyCodes).size) throw new CombatV2Error('ERR_COMBAT_V2_NO_ENEMIES', 409);
      }
      const now = new Date();
      await chargeCombatDispatch(tx, masterId, heroIds, now);
      const sessionId = uuidv4();
      await tx.insert(combatSessions).values({
        id: sessionId, masterId, worldId: world.id, partyId: null, status: 'ACTIVE', createdAt: now,
        combatState: { engine: 'V2', request: { heroIds, enemyCodes, maxRounds, seed } },
      });
      return { sessionId, status: 'ACTIVE', heroIds, enemyCodes, seed };
    });
  }

  /** Resolve and settle atomically. Legacy callers still receive 409 for a finished session. */
  async advance(masterId: string, sessionId: string) {
    return db.transaction(async tx => {
      await tx.select({ id: masters.id }).from(masters).where(eq(masters.id, masterId)).for('update');
      const [session] = await tx.select().from(combatSessions)
        .where(and(eq(combatSessions.id, sessionId), eq(combatSessions.masterId, masterId))).for('update');
      if (!session) throw new CombatV2Error('ERR_COMBAT_V2_SESSION_NOT_FOUND', 404);
      if (session.status !== 'ACTIVE') throw new CombatV2Error('ERR_COMBAT_V2_SESSION_FINISHED', 409);
      await tx.update(combatSessions).set({ status: 'RESOLVING' }).where(eq(combatSessions.id, session.id));
      const request = (session.combatState as { request?: Record<string, unknown> } | null)?.request ?? {};
      const report = await this.simulate(masterId, { ...request, persist: false }, tx);
      const codes = Array.isArray(request.enemyCodes) ? request.enemyCodes.map(String) : [];
      const foes = codes.length
        ? await tx.select().from(enemyTemplates).where(inArray(enemyTemplates.code, codes))
        : await tx.select().from(enemyTemplates).where(eq(enemyTemplates.isActive, true)).orderBy(asc(enemyTemplates.code)).limit(3);
      const [world] = await tx.select().from(worlds).where(eq(worlds.id, session.worldId));
      const now = new Date();
      const expReward = foes.reduce((sum, foe) => sum + foe.baseExpReward, 0);
      const settlement = await settleCombat(tx, {
        masterId, sessionId, worldId: session.worldId, floor: world?.currentFloor ?? 1, report,
        silverReward: foes.reduce((sum, foe) => sum + foe.baseSilverReward, 0),
        heroExpReward: expReward, masterExpReward: expReward, transactionType: 'COMBAT_V2_REWARD', now,
      });
      if (report.winner === 'HERO') {
        await questService.recordEvent(masterId, 'WIN_BATTLE', 1, now, tx);
        await eventService.recordEvent(masterId, 'WIN_BATTLE', 1, now, tx);
      }
      await tx.update(combatSessions).set({ status: 'COMPLETED', finishedAt: now,
        battleReport: report as unknown as Record<string, unknown>,
      }).where(eq(combatSessions.id, sessionId));
      return { sessionId, status: 'COMPLETED', ...settlement, report };
    });
  }

}

export const combatV2Service = new CombatV2Service();
