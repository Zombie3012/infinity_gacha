import { and, asc, eq, sql } from 'drizzle-orm';
import { v4 as uuid } from 'uuid';
import { heroEffectiveMaxLevel, type HeroClass, type StarRating } from '@infiniti-gacha/shared';
import type { GameTransaction } from '../../database/transaction.js';
import {
  combatPartySlots, currencyTransactions, equipmentInstances, heroDeathRecords, heroLevelConfigs,
  heroInjuries, heroTreatments, buildingWorkerAssignments, heroSurvivalStates,
  heroes, masterLevelConfigs, masters,
} from '../../database/drizzle-schema.js';
import { isV2Origin, originOf, progressionFor } from '../hero/hero-progression.js';
import { medicalService } from '../medical/medical.service.js';
import type { CombatV2Report } from './combat-v2.engine.js';

export interface CombatSettlementInput {
  masterId: string;
  sessionId: string;
  worldId: string;
  floor: number;
  report: CombatV2Report;
  silverReward: number;
  heroExpReward: number;
  transactionType: string;
  now: Date;
}

/** Shared with the retained combat flow: ordinary facilities cannot retain a casualty. */
export async function clearCasualtyActivities(tx: GameTransaction, heroId: string, now: Date) {
  await tx.update(heroTreatments).set({ status: 'CANCELLED', completedAt: now })
    .where(and(eq(heroTreatments.heroId, heroId), sql`${heroTreatments.status} IN ('ACTIVE', 'QUEUED')`));
  await tx.update(heroInjuries).set({ healedAt: now, healedBy: 'DEATH' })
    .where(and(eq(heroInjuries.heroId, heroId), sql`${heroInjuries.healedAt} IS NULL`));
  await tx.delete(buildingWorkerAssignments).where(eq(buildingWorkerAssignments.heroInstanceId, heroId));
  await tx.update(heroSurvivalStates).set({ isResting: false }).where(eq(heroSurvivalStates.heroId, heroId));
}

/** All effects share the caller's transaction; a report is never completed with partially paid rewards. */
export async function settleCombat(tx: GameTransaction, input: CombatSettlementInput) {
  const { masterId, sessionId, worldId, floor, report, now } = input;
  const won = report.winner === 'HERO';
  const silverReward = won ? input.silverReward : 0;
  const heroExpReward = won ? input.heroExpReward : 0;
  const deaths: { heroId: string; name: string; state: string; droppedEquipmentIds: string[] }[] = [];
  const heroProgress: { heroId: string; expGranted: number; fromLevel: number; toLevel: number }[] = [];
  const configs = await tx.select().from(heroLevelConfigs).orderBy(asc(heroLevelConfigs.level));

  for (const unit of report.units.filter(row => row.side === 'HERO')) {
    const [hero] = await tx.select().from(heroes).where(and(eq(heroes.id, unit.id), eq(heroes.masterId, masterId))).for('update');
    if (!hero) throw new Error('Combat settlement lost a participating Hero.');
    if (hero.state === 'DEAD' || hero.state === 'DISABLED') throw new Error('Combat Hero was changed while resolving.');
    if (!unit.alive || unit.hp <= 0) {
      const state = 'DEAD';
      const gear = await tx.select().from(equipmentInstances)
        .where(and(eq(equipmentInstances.equippedHeroId, hero.id), eq(equipmentInstances.location, 'EQUIPPED')));
      for (const item of gear) await tx.update(equipmentInstances).set({
        equippedHeroId: null, location: 'FLOOR_DROP', dropWorldId: worldId, dropFloor: floor, droppedAt: now,
      }).where(eq(equipmentInstances.id, item.id));
      await tx.update(heroes).set({ state, hp: 0, currentHpPct: 0, mp: unit.mp,
        currentMpPct: unit.maxMp > 0 ? unit.mp / unit.maxMp : 0, updatedAt: now }).where(eq(heroes.id, hero.id));
      await clearCasualtyActivities(tx, hero.id, now);
      await tx.insert(heroDeathRecords).values({
        id: uuid(), heroId: hero.id, masterId, combatSessionId: sessionId, summonOrigin: hero.category,
        deathType: 'DEATH',
        droppedEquipment: gear.map(item => ({ id: item.id, templateCode: item.templateCode })),
        cause: input.transactionType, recordedAt: now,
      });
      await tx.delete(combatPartySlots).where(and(eq(combatPartySlots.masterId, masterId), eq(combatPartySlots.heroId, hero.id)));
      deaths.push({ heroId: hero.id, name: hero.name, state, droppedEquipmentIds: gear.map(item => item.id) });
      continue;
    }

    const exp = hero.exp + BigInt(heroExpReward);
    const cap = heroEffectiveMaxLevel(hero.rarity, hero.promotionRank);
    let level = hero.level;
    for (const config of configs) if (config.level > level && config.level <= cap && exp >= config.cumulativeExpRequired) level = config.level;
    const hpPct = unit.maxHp > 0 ? unit.hp / unit.maxHp : 0;
    const mpPct = unit.maxMp > 0 ? unit.mp / unit.maxMp : 0;
    const baseUpdate = { exp, level, currentHpPct: hpPct, currentMpPct: mpPct, updatedAt: now };
    if (isV2Origin(hero.originStats)) {
      // Stored display stats exclude equipment/imprints; those are recomputed by buildHeroUnits.
      const snapshot = progressionFor({
        origin: originOf(hero.originStats), star: hero.rarity as StarRating, level,
        classCode: hero.classCode as HeroClass, training: hero.trainingStats, awakeningRank: hero.awakeningRank,
        hpPct, mpPct,
      });
      await tx.update(heroes).set({ ...baseUpdate,
        baseStr: snapshot.base.str, baseInt: snapshot.base.int, baseSta: snapshot.base.sta, baseAgi: snapshot.base.agi,
        hp: Math.max(1, snapshot.hp), maxHp: snapshot.maxHp, mp: snapshot.mp, maxMp: snapshot.maxMp,
        attack: snapshot.attack, defense: snapshot.defense, speed: snapshot.speed,
      }).where(eq(heroes.id, hero.id));
    } else {
      let growth = 1;
      for (const config of configs) if (config.level > hero.level && config.level <= level) growth *= config.statGrowthMultiplier;
      const maxHp = Math.max(1, Math.round(hero.maxHp * growth));
      await tx.update(heroes).set({ ...baseUpdate, maxHp, hp: Math.max(1, Math.round(maxHp * hpPct)),
        mp: Math.round(hero.maxMp * mpPct), attack: Math.round(hero.attack * growth),
        defense: Math.round(hero.defense * growth), speed: Math.round(hero.speed * growth),
      }).where(eq(heroes.id, hero.id));
    }
    heroProgress.push({ heroId: hero.id, expGranted: heroExpReward, fromLevel: hero.level, toLevel: level });
  }

  const [master] = await tx.select().from(masters).where(eq(masters.id, masterId)).for('update');
  if (!master) throw new Error('Master missing during settlement.');
  await tx.update(masters).set({
    silverCoins: sql`${masters.silverCoins} + ${BigInt(silverReward)}`, updatedAt: now,
  }).where(eq(masters.id, masterId));
  if (silverReward > 0) await tx.insert(currencyTransactions).values({
    id: uuid(), masterId, currencyType: 'SILVER', amountDelta: BigInt(silverReward),
    transactionType: input.transactionType, referenceId: sessionId, createdAt: now,
  });
  const survivors = report.units.filter(unit => unit.side === 'HERO' && unit.alive && unit.hp > 0)
    .map(unit => ({ id: unit.id, hp: unit.hp, maxHp: unit.maxHp }));
  await medicalService.recordBattleInjuries(masterId, survivors, tx, now);
  return { silverReward, heroExpReward, deaths, heroProgress };
}
