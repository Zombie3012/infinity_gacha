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
  combatSessions, enemyTemplates, equipmentInstances, equipmentTemplates, heroElementAffinities, heroes,
  heroSkillInstances, heroSkillTemplates, heroTemplates, worlds,
} from '../../database/drizzle-schema.js';
import {
  deriveStats, mulberry32, type DerivedStats, type ElementAffinity, type HeroClass, type StarRating,
} from '@infiniti-gacha/shared';
import { isV2Origin, originOf, progressionFor } from '../hero/hero-progression.js';
import { survivalService } from '../survival/survival.service.js';
import { medicalService } from '../medical/medical.service.js';
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

    const skills = await db.select({ instance: heroSkillInstances, template: heroSkillTemplates })
      .from(heroSkillInstances).innerJoin(heroSkillTemplates, eq(heroSkillInstances.skillCode, heroSkillTemplates.code))
      .where(and(inArray(heroSkillInstances.heroId, heroIds), eq(heroSkillInstances.isUnlocked, true)));
    const affinities = await db.select().from(heroElementAffinities).where(inArray(heroElementAffinities.heroId, heroIds));

    const gearRows = await db.select({ item: equipmentInstances, template: equipmentTemplates })
      .from(equipmentInstances).innerJoin(equipmentTemplates, eq(equipmentInstances.templateCode, equipmentTemplates.code))
      .where(and(
        eq(equipmentInstances.masterId, masterId),
        eq(equipmentInstances.location, 'EQUIPPED'),
        inArray(equipmentInstances.equippedHeroId, heroIds),
      ));
    const gearByHero = new Map<string, { hp: number; attack: number; defense: number; speed: number }>();
    for (const row of gearRows) {
      const heroId = row.item.equippedHeroId!;
      const bonus = gearByHero.get(heroId) ?? { hp: 0, attack: 0, defense: 0, speed: 0 };
      const multiplier = row.item.statMultiplier ?? 1;
      const substats = row.item.substats ?? { hp: 0, attack: 0, defense: 0, speed: 0 };
      bonus.hp += Math.round(row.template.bonusHp * multiplier) + substats.hp;
      bonus.attack += Math.round(row.template.bonusAttack * multiplier) + substats.attack;
      bonus.defense += Math.round(row.template.bonusDefense * multiplier) + substats.defense;
      bonus.speed += Math.round(row.template.bonusSpeed * multiplier) + substats.speed;
      gearByHero.set(heroId, bonus);
    }

    // Existing P1 systems: injury, starvation and loyalty/resonance multipliers.
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

    const heroUnits: CombatV2UnitInput[] = rows.map(({ hero, template }, index) => {
      const useV2 = isV2Origin(hero.originStats);
      const snapshot = useV2
        ? progressionFor({
          origin: originOf(hero.originStats),
          star: hero.rarity as StarRating,
          level: hero.level,
          classCode: hero.classCode as HeroClass,
          training: hero.trainingStats,
          hpPct: 1,
          mpPct: 1,
        })
        : null;
      const gear = gearByHero.get(hero.id) ?? { hp: 0, attack: 0, defense: 0, speed: 0 };
      const classCode = hero.classCode as HeroClass;
      const stats = snapshot
        ? deriveStats(snapshot.base, classCode, {
          hpBase: gear.hp, atkBase: gear.attack, defBase: gear.defense, agi: gear.speed,
        })
        : legacyStats(hero, gear);
      const modified = applyCombatModifiers(
        stats,
        (readiness[hero.id] ?? 1) * (injuryPenalties[hero.id] ?? 1),
        personality[hero.id]?.loyalty ?? 1,
        personality[hero.id]?.resonance ?? 1,
      );
      const affinityRow = affinities.find(row => row.heroId === hero.id);
      const affinity = affinityRow ? affinityFromRow(affinityRow) : null;
      const element = affinity ? strongestElement(affinity) : undefined;

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
        side: 'HERO',
        slotIndex: index,
        agi: (snapshot?.base.agi ?? Math.max(1, hero.speed)) + gear.speed,
        stats: modified,
        damageType: classCode === 'MAGE' ? 'MAGICAL' : 'PHYSICAL',
        affinity,
        skills: unitSkills,
      };
    });

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
      heroes: heroUnits.map(unit => ({ id: unit.id, name: unit.name, classCode: unit.side === 'HERO' ? rows.find(row => row.hero.id === unit.id)?.hero.classCode : undefined })),
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
}

export const combatV2Service = new CombatV2Service();
