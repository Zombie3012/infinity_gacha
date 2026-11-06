/**
 * Combat v2 simulation service.
 *
 * Loads a party and an enemy set, builds Combat v2 units from the persisted
 * base stats (falling back to the legacy columns for pre-v2 demo Heroes) and
 * runs the pure engine. This endpoint is the test harness that will later be
 * wired into the persistent combat session and reward flow.
 */

import { and, asc, desc, eq, inArray } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import {
  combatSessions, enemyTemplates, equipmentInstances, equipmentTemplates, heroDeathRecords, heroElementAffinities, heroes,
  heroImprints, heroLevelConfigs, heroSkillInstances, heroSkillTemplates, heroTemplates, imprintDefinitions, masterLevelConfigs, masters, worlds,
} from '../../database/drizzle-schema.js';
import {
  aggregateEquipment, combatPowerV2, combineImprintEffects, deriveStats, isEmptyImprintEffects, mulberry32,
  type DerivedOffsets, type DerivedStats, type ElementAffinity, type EquipmentItemInput, type EquipmentV2Stats,
  type HeroClass, type ImprintCombatEffects, type StarRating,
} from '@infiniti-gacha/shared';
import { isV2Origin, originOf, progressionFor } from '../hero/hero-progression.js';
import { currencyService } from '../economy/currency.service.js';
import { survivalService } from '../survival/survival.service.js';
import { medicalService } from '../medical/medical.service.js';
import { questService } from '../quest/quest.service.js';
import { leaderboardService } from '../liveops/leaderboard.service.js';
import { personalityService } from '../personality/personality.service.js';
import { resolveBattleV2, type CombatV2Skill, type CombatV2UnitInput } from './combat-v2.engine.js';

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
  ): Promise<CombatV2UnitInput[]> {
    if (heroIds.length === 0) return [];
    const rows = await db.select({ hero: heroes, template: heroTemplates })
      .from(heroes).leftJoin(heroTemplates, eq(heroTemplates.code, heroes.configId))
      .where(and(eq(heroes.masterId, masterId), inArray(heroes.id, heroIds)))
      .orderBy(asc(heroes.createdAt));
    if (rows.length === 0) return [];

    const skills = await db.select({ instance: heroSkillInstances, template: heroSkillTemplates })
      .from(heroSkillInstances).innerJoin(heroSkillTemplates, eq(heroSkillInstances.skillCode, heroSkillTemplates.code))
      .where(and(inArray(heroSkillInstances.heroId, heroIds), eq(heroSkillInstances.isUnlocked, true)));
    const affinities = await db.select().from(heroElementAffinities).where(inArray(heroElementAffinities.heroId, heroIds));

    const imprintRows = await db.select({ owned: heroImprints, definition: imprintDefinitions })
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
    const gearRows = await db.select({ item: equipmentInstances, template: equipmentTemplates })
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

    const [injuryPenalties, personality] = await Promise.all([
      medicalService.penaltyByHero(masterId).catch(() => ({} as Record<string, number>)),
      personalityService.combatModifiers(masterId).catch(() => ({} as Record<string, { loyalty: number; resonance: number }>)),
    ]);
    let readiness: Record<string, number> = {};
    try {
      readiness = (await survivalService.battleReadiness(masterId)).multipliers ?? {};
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
          multiplier: row.template.effectValue,
          cooldownRounds: Math.max(1, row.template.cooldownSeconds),
          effectType: row.template.effectType === 'HEAL_LOWEST_ALLY' ? 'HEAL_LOWEST_ALLY' : 'DAMAGE_SINGLE',
          effectValue: row.template.effectValue,
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

  async simulate(masterId: string, input: {
    heroIds?: unknown; enemyCodes?: unknown; maxRounds?: unknown; seed?: unknown; persist?: unknown;
  }) {
    const heroIds = Array.isArray(input.heroIds) ? input.heroIds.map(String) : [];
    if (heroIds.length === 0) throw new CombatV2Error('ERR_COMBAT_V2_NO_HEROES', 400);
    if (heroIds.length > 5) throw new CombatV2Error('ERR_COMBAT_V2_PARTY_TOO_LARGE', 400);

    const rows = await db.select({ hero: heroes, template: heroTemplates })
      .from(heroes).leftJoin(heroTemplates, eq(heroTemplates.code, heroes.configId))
      .where(and(eq(heroes.masterId, masterId), inArray(heroes.id, heroIds)))
      .orderBy(asc(heroes.createdAt));
    if (rows.length !== heroIds.length) throw new CombatV2Error('ERR_COMBAT_V2_HERO_NOT_FOUND', 404);
    for (const { hero } of rows) {
      if (hero.state === 'DEAD' || hero.state === 'DISABLED' || hero.hp <= 0) {
        throw new CombatV2Error('ERR_COMBAT_V2_HERO_UNAVAILABLE', 409);
      }
    }

    const heroUnits = await this.buildHeroUnits(heroIds, masterId, 'HERO');

    const requestedCodes = Array.isArray(input.enemyCodes) ? input.enemyCodes.map(String) : [];
    const enemyRows = requestedCodes.length > 0
      ? await db.select().from(enemyTemplates).where(and(eq(enemyTemplates.isActive, true), inArray(enemyTemplates.code, requestedCodes)))
      : await db.select().from(enemyTemplates).where(eq(enemyTemplates.isActive, true)).orderBy(asc(enemyTemplates.code)).limit(3);
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
      const [world] = await db.select().from(worlds).where(eq(worlds.masterId, masterId)).limit(1);
      if (!world) throw new CombatV2Error('ERR_COMBAT_V2_NO_WORLD', 409);
      sessionId = uuidv4();
      const now = new Date();
      await db.insert(combatSessions).values({
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

  /** Opens a two-step Combat v2 session; the battle resolves on advance. */
  async start(masterId: string, input: {
    heroIds?: unknown; enemyCodes?: unknown; maxRounds?: unknown; seed?: unknown;
  }) {
    const heroIds = Array.isArray(input.heroIds) ? input.heroIds.map(String) : [];
    if (heroIds.length === 0 || heroIds.length > 5) throw new CombatV2Error('ERR_COMBAT_V2_INVALID_PARTY', 400);
    const owned = await db.select({ id: heroes.id, state: heroes.state, hp: heroes.hp }).from(heroes)
      .where(and(eq(heroes.masterId, masterId), inArray(heroes.id, heroIds)));
    if (owned.length !== heroIds.length) throw new CombatV2Error('ERR_COMBAT_V2_HERO_NOT_FOUND', 404);
    if (owned.some(hero => hero.state === 'DEAD' || hero.state === 'DISABLED' || hero.hp <= 0)) {
      throw new CombatV2Error('ERR_COMBAT_V2_HERO_UNAVAILABLE', 409);
    }

    const [world] = await db.select().from(worlds).where(eq(worlds.masterId, masterId)).limit(1);
    if (!world) throw new CombatV2Error('ERR_COMBAT_V2_NO_WORLD', 409);

    const enemyCodes = Array.isArray(input.enemyCodes) ? input.enemyCodes.map(String) : [];
    // DM-09: expedition rations are charged when the party deploys.
    await survivalService.rationQuote(masterId, 'DUNGEON', heroIds.length, true)
      .catch(error => console.error('[combat-v2] ration charge failed', error));
    const seed = Number.isFinite(Number(input.seed)) ? Number(input.seed) : Date.now() % 2_147_483_647;
    const sessionId = uuidv4();
    const now = new Date();
    await db.transaction(async tx => {
      await tx.update(combatSessions).set({ status: 'COMPLETED', finishedAt: now })
        .where(and(eq(combatSessions.masterId, masterId), eq(combatSessions.status, 'ACTIVE')));
      await tx.insert(combatSessions).values({
        id: sessionId, masterId, worldId: world.id, partyId: null,
        status: 'ACTIVE', createdAt: now,
        combatState: {
          engine: 'V2',
          request: { heroIds, enemyCodes, maxRounds: input.maxRounds, seed },
        } as unknown as Record<string, unknown>,
      });
    });
    return { sessionId, status: 'ACTIVE', heroIds, enemyCodes, seed };
  }

  /** Resolves the stored request, persists the report and pays Silver. */
  async advance(masterId: string, sessionId: string) {
    // Atomically claim the session so two concurrent advances cannot both pay rewards.
    const [session] = await db.update(combatSessions).set({ status: 'RESOLVING' })
      .where(and(
        eq(combatSessions.id, sessionId),
        eq(combatSessions.masterId, masterId),
        eq(combatSessions.status, 'ACTIVE'),
      )).returning();
    if (!session) {
      const [existing] = await db.select({ status: combatSessions.status }).from(combatSessions)
        .where(and(eq(combatSessions.id, sessionId), eq(combatSessions.masterId, masterId))).limit(1);
      if (!existing) throw new CombatV2Error('ERR_COMBAT_V2_SESSION_NOT_FOUND', 404);
      throw new CombatV2Error('ERR_COMBAT_V2_SESSION_FINISHED', 409);
    }

    try {
      return await this.resolveSession(masterId, session);
    } catch (error) {
      // Give the session back if resolution failed before completion.
      await db.update(combatSessions).set({ status: 'ACTIVE' })
        .where(and(eq(combatSessions.id, sessionId), eq(combatSessions.status, 'RESOLVING')))
        .catch(() => undefined);
      throw error;
    }
  }

  private async resolveSession(masterId: string, session: typeof combatSessions.$inferSelect) {
    const sessionId = session.id;
    const request = (session.combatState as { request?: Record<string, unknown> } | null)?.request ?? {};
    const report = await this.simulate(masterId, { ...request, persist: false });

    const foeCodes = Array.isArray(request.enemyCodes) && request.enemyCodes.length > 0
      ? request.enemyCodes.map(String)
      : [];
    const foes = foeCodes.length > 0
      ? await db.select().from(enemyTemplates).where(inArray(enemyTemplates.code, foeCodes))
      : await db.select().from(enemyTemplates).where(eq(enemyTemplates.isActive, true)).orderBy(asc(enemyTemplates.code)).limit(3);
    const won = report.winner === 'HERO';
    const silverReward = won ? foes.reduce((sum, foe) => sum + foe.baseSilverReward, 0) : 0;

    const now = new Date();
    await db.update(combatSessions).set({
      status: 'COMPLETED', finishedAt: now,
      battleReport: report as unknown as Record<string, unknown>,
    }).where(eq(combatSessions.id, sessionId));

    const [world] = await db.select().from(worlds).where(eq(worlds.id, session.worldId)).limit(1);

    // P0 death rules: Normal Heroes die permanently and drop gear;
    // Special/Limited Heroes are disabled instead.
    const deaths: { heroId: string; name: string; state: string }[] = [];
    for (const unit of report.units.filter(row => row.side === 'HERO' && !row.alive)) {
      const [hero] = await db.select().from(heroes).where(eq(heroes.id, unit.id)).limit(1);
      if (!hero || hero.state === 'DEAD' || hero.state === 'DISABLED') continue;
      const gear = await db.select().from(equipmentInstances)
        .where(and(eq(equipmentInstances.equippedHeroId, hero.id), eq(equipmentInstances.location, 'EQUIPPED')));
      const nextState = hero.category === 'NORMAL' ? 'DEAD' : 'DISABLED';
      await db.transaction(async tx => {
        for (const item of gear) {
          await tx.update(equipmentInstances).set({
            equippedHeroId: null, location: 'FLOOR_DROP', dropWorldId: session.worldId,
            dropFloor: world?.currentFloor ?? null, droppedAt: now,
          }).where(eq(equipmentInstances.id, item.id));
        }
        await tx.update(heroes).set({ state: nextState, hp: 0, updatedAt: now }).where(eq(heroes.id, hero.id));
        if (nextState === 'DEAD') {
          await tx.insert(heroDeathRecords).values({
            id: uuidv4(), heroId: hero.id, masterId, combatSessionId: sessionId,
            summonOrigin: hero.category, deathType: 'PERMANENT',
            droppedEquipment: gear.map(item => ({ id: item.id, templateCode: item.templateCode })),
            cause: 'COMBAT_V2', recordedAt: now,
          });
        }
      });
      deaths.push({ heroId: hero.id, name: hero.name, state: nextState });
    }

    if (silverReward > 0) {
      await currencyService.addCurrency(masterId, {
        silverDelta: silverReward, transactionType: 'COMBAT_V2_REWARD',
      }).catch(error => console.error('[combat-v2] silver reward failed', error));
    }

    // P1 medical hook: survivors below the injury threshold are admitted.
    const survivors = report.units
      .filter(unit => unit.side === 'HERO' && unit.alive)
      .map(unit => ({ id: unit.id, hp: unit.hp, maxHp: unit.maxHp }));
    await medicalService.recordBattleInjuries(masterId, survivors)
      .catch(error => console.error('[combat-v2] injury recording failed', error));

    if (won) {
      const expReward = foes.reduce((sum, foe) => sum + foe.baseExpReward, 0);
      const levelConfigs = await db.select().from(heroLevelConfigs).orderBy(asc(heroLevelConfigs.level));
      for (const unit of report.units.filter(row => row.side === 'HERO' && row.alive)) {
        const [hero] = await db.select().from(heroes).where(eq(heroes.id, unit.id)).limit(1);
        if (!hero) continue;
        const totalExp = hero.exp + BigInt(expReward);
        let level = hero.level;
        for (const config of levelConfigs) {
          if (config.level > level && totalExp >= config.cumulativeExpRequired) level = config.level;
        }
        if (level === hero.level) {
          await db.update(heroes).set({ exp: totalExp, updatedAt: now }).where(eq(heroes.id, hero.id));
          continue;
        }
        const snapshot = progressionFor({
          origin: originOf(hero.originStats),
          star: hero.rarity as StarRating,
          level,
          classCode: hero.classCode as HeroClass,
          training: hero.trainingStats,
          hpPct: hero.currentHpPct,
          mpPct: hero.currentMpPct,
        });
        await db.update(heroes).set({
          exp: totalExp, level,
          baseStr: snapshot.base.str, baseInt: snapshot.base.int,
          baseSta: snapshot.base.sta, baseAgi: snapshot.base.agi,
          maxHp: snapshot.maxHp, hp: snapshot.hp,
          attack: snapshot.attack, defense: snapshot.defense, speed: snapshot.speed,
          mp: snapshot.mp, maxMp: snapshot.maxMp, updatedAt: now,
        }).where(eq(heroes.id, hero.id));
      }

      const [masterRow] = await db.select().from(masters).where(eq(masters.id, masterId)).limit(1);
      if (masterRow) {
        const masterExp = masterRow.exp + BigInt(expReward);
        const masterConfigs = await db.select().from(masterLevelConfigs).orderBy(asc(masterLevelConfigs.level));
        let masterLevel = masterRow.level;
        for (const config of masterConfigs) {
          if (config.level > masterLevel && masterExp >= config.expRequired) masterLevel = config.level;
        }
        await db.update(masters).set({ exp: masterExp, level: masterLevel, updatedAt: now })
          .where(eq(masters.id, masterId));
      }

      await questService.recordEvent(masterId, 'WIN_BATTLE', 1)
        .catch(error => console.error('[combat-v2] quest win hook failed', error));
      await questService.recordEvent(masterId, 'CLEAR_FLOOR', 1).catch(() => undefined);
      if (world) {
        await leaderboardService.recordFloor(masterId, world.currentFloor + 1, report.rounds)
          .catch(error => console.error('[combat-v2] leaderboard hook failed', error));
      }
    }

    return { sessionId, status: 'COMPLETED', silverReward, deaths, report };
  }
}

export const combatV2Service = new CombatV2Service();
