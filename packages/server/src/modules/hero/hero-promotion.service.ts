import { and, eq, inArray } from 'drizzle-orm';
import {
  checkStarPromotionEligibility, heroEffectiveMaxLevel,
  promoteOriginStats, requiredFodderCount, starMaxLevel, starPromotionCost,
  type BaseStats, type HeroClass, type StarRating,
} from '@infiniti-gacha/shared';
import { db } from '../../database/db.js';
import {
  combatPartySlots, currencyTransactions, equipmentInstances,
  heroElementAffinities, heroImprints, heroes, heroPersonalityTraits,
  heroSkillInstances, heroSubclasses, imprintDefinitions, masters,
} from '../../database/drizzle-schema.js';
import { auditService } from '../admin/audit.service.js';
import { isV2Origin, originOf, progressionFor, ProgressionError } from './hero-progression.js';
import { imprintSlotsFor } from './imprint-rules.js';

export interface StarPromotionPreview {
  eligible: boolean;
  reason?: string;
  hero: {
    id: string;
    name: string;
    currentStar: number;
    nextStar: number;
    currentLevel: number;
    currentMaxLevel: number;
    nextMaxLevel: number;
    currentImprintSlots: number;
    nextImprintSlots: number;
  };
  requirements: {
    requiredLevel: number;
    requiredFodderCount: number;
    fodderStar: number;
    silverCost: number;
    currentSilver: string;
    hasEnoughSilver: boolean;
  };
  availableFodders: {
    id: string;
    name: string;
    rarity: number;
    level: number;
    heroClass: string;
  }[];
  projectedStats?: {
    hp: number;
    maxHp: number;
    attack: number;
    defense: number;
    speed: number;
    base: BaseStats;
  };
}

export interface StarPromotionResult {
  heroId: string;
  heroName: string;
  previousStar: number;
  newStar: number;
  level: number;
  maxLevel: number;
  imprintSlots: number;
  consumedFodderIds: string[];
  silverCost: number;
  remainingSilver: string;
  stats: {
    hp: number;
    maxHp: number;
    mp: number;
    maxMp: number;
    attack: number;
    defense: number;
    speed: number;
    baseStr: number;
    baseInt: number;
    baseSta: number;
    baseAgi: number;
  };
}

export class HeroPromotionService {
  async getImprintBonus(
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    executor: any,
    heroId: string,
  ): Promise<BaseStats> {
    const rows = await executor.select({ definition: imprintDefinitions })
      .from(heroImprints)
      .innerJoin(imprintDefinitions, eq(imprintDefinitions.code, heroImprints.imprintCode))
      .where(eq(heroImprints.heroId, heroId));
    return rows.reduce((sum: BaseStats, row: { definition: { bonusStr: number; bonusInt: number; bonusSta: number; bonusAgi: number } }) => ({
      str: sum.str + row.definition.bonusStr,
      int: sum.int + row.definition.bonusInt,
      sta: sum.sta + row.definition.bonusSta,
      agi: sum.agi + row.definition.bonusAgi,
    }), { str: 0, int: 0, sta: 0, agi: 0 });
  }

  async previewStarPromotion(masterId: string, heroId: string): Promise<StarPromotionPreview> {
    const [hero] = await db.select().from(heroes)
      .where(and(eq(heroes.id, heroId), eq(heroes.masterId, masterId)))
      .limit(1);
    if (!hero) throw new ProgressionError('Hero not found.', 404);

    const [master] = await db.select().from(masters).where(eq(masters.id, masterId)).limit(1);
    if (!master) throw new ProgressionError('Master not found.', 404);

    const currentMaxLevel = heroEffectiveMaxLevel(hero.rarity, hero.promotionRank);
    const eligibility = checkStarPromotionEligibility({
      currentStar: hero.rarity,
      currentLevel: hero.level,
      isLocked: hero.isLocked,
      state: hero.state,
    });

    const nextStar = (hero.rarity + 1) as StarRating;
    const nextMaxLevel = starMaxLevel(nextStar);
    const requiredFodders = requiredFodderCount(hero.rarity);
    const cost = starPromotionCost(hero.rarity);
    const masterSilver = master.silverCoins ?? 0n;
    const hasEnoughSilver = masterSilver >= BigInt(cost);

    // Get party heroes to exclude from available fodders
    const partySlots = await db.select({ heroId: combatPartySlots.heroId })
      .from(combatPartySlots)
      .where(eq(combatPartySlots.masterId, masterId));
    const partyHeroIds = new Set(partySlots.map(p => p.heroId));

    // Find candidate fodders (same star, not locked, not dead/disabled, not target, not in party)
    const potentialFodders = await db.select().from(heroes)
      .where(and(
        eq(heroes.masterId, masterId),
        eq(heroes.rarity, hero.rarity),
        eq(heroes.isLocked, false),
      ));

    const availableFodders = potentialFodders
      .filter(f => f.id !== hero.id && f.state !== 'DEAD' && f.state !== 'DISABLED' && !partyHeroIds.has(f.id))
      .map(f => ({
        id: f.id,
        name: f.name,
        rarity: f.rarity,
        level: f.level,
        heroClass: f.classCode ?? 'UNCLASSIFIED',
      }));

    let projectedStats: StarPromotionPreview['projectedStats'];
    if (isV2Origin(hero.originStats) && hero.rarity < 6) {
      const imprintBonus = await this.getImprintBonus(db, hero.id);
      const newOrigin = promoteOriginStats(originOf(hero.originStats), hero.rarity as StarRating, nextStar);
      const snapshot = progressionFor({
        origin: newOrigin,
        star: nextStar,
        level: hero.level,
        classCode: hero.classCode as HeroClass,
        training: hero.trainingStats,
        hpPct: hero.currentHpPct,
        mpPct: hero.currentMpPct,
        awakeningRank: hero.awakeningRank,
        imprint: imprintBonus,
      });
      projectedStats = {
        hp: snapshot.hp,
        maxHp: snapshot.maxHp,
        attack: snapshot.attack,
        defense: snapshot.defense,
        speed: snapshot.speed,
        base: snapshot.base,
      };
    }

    return {
      eligible: eligibility.eligible && availableFodders.length >= requiredFodders && hasEnoughSilver,
      reason: eligibility.reason ?? (availableFodders.length < requiredFodders ? 'ERR_NOT_ENOUGH_FODDER' : (!hasEnoughSilver ? 'ERR_INSUFFICIENT_SILVER' : undefined)),
      hero: {
        id: hero.id,
        name: hero.name,
        currentStar: hero.rarity,
        nextStar,
        currentLevel: hero.level,
        currentMaxLevel,
        nextMaxLevel,
        currentImprintSlots: imprintSlotsFor(hero.rarity),
        nextImprintSlots: imprintSlotsFor(nextStar),
      },
      requirements: {
        requiredLevel: starMaxLevel(hero.rarity),
        requiredFodderCount: requiredFodders,
        fodderStar: hero.rarity,
        silverCost: cost,
        currentSilver: masterSilver.toString(),
        hasEnoughSilver,
      },
      availableFodders,
      projectedStats,
    };
  }

  async executeStarPromotion(
    masterId: string,
    heroId: string,
    fodderHeroIds: string[],
  ): Promise<StarPromotionResult> {
    return await db.transaction(async tx => {
      // 1. Fetch & lock Target Hero
      const [hero] = await tx.select().from(heroes)
        .where(and(eq(heroes.id, heroId), eq(heroes.masterId, masterId)))
        .for('update')
        .limit(1);
      if (!hero) throw new ProgressionError('Hero not found.', 404);

      // 2. Validate Target Hero state
      const eligibility = checkStarPromotionEligibility({
        currentStar: hero.rarity,
        currentLevel: hero.level,
        isLocked: hero.isLocked,
        state: hero.state,
      });
      if (!eligibility.eligible) {
        throw new ProgressionError(eligibility.reason ?? 'ERR_HERO_NOT_ELIGIBLE', 409);
      }

      const nextStar = (hero.rarity + 1) as StarRating;
      const requiredFodders = requiredFodderCount(hero.rarity);
      const cost = starPromotionCost(hero.rarity);

      // 3. Validate fodder ids
      if (!Array.isArray(fodderHeroIds) || fodderHeroIds.length !== requiredFodders) {
        throw new ProgressionError(`Star promotion requires exactly ${requiredFodders} fodder Heroes of ${hero.rarity}★.`, 400);
      }
      if (fodderHeroIds.includes(hero.id)) {
        throw new ProgressionError('Target Hero cannot be used as fodder.', 400);
      }
      const uniqueFodderIds = Array.from(new Set(fodderHeroIds));
      if (uniqueFodderIds.length !== requiredFodders) {
        throw new ProgressionError('Duplicate fodder Heroes selected.', 400);
      }

      // 4. Fetch & lock Fodders
      const fodders = await tx.select().from(heroes)
        .where(and(
          eq(heroes.masterId, masterId),
          inArray(heroes.id, uniqueFodderIds),
        ))
        .for('update');

      if (fodders.length !== requiredFodders) {
        throw new ProgressionError('One or more selected fodder Heroes were not found.', 404);
      }

      for (const fodder of fodders) {
        if (fodder.rarity !== hero.rarity) {
          throw new ProgressionError(`Fodder Hero ${fodder.name} must be ${hero.rarity}★ (has ${fodder.rarity}★).`, 409);
        }
        if (fodder.isLocked) {
          throw new ProgressionError(`Fodder Hero ${fodder.name} is locked.`, 409);
        }
        if (fodder.state === 'DEAD' || fodder.state === 'DISABLED') {
          throw new ProgressionError(`Fodder Hero ${fodder.name} is unavailable (${fodder.state}).`, 409);
        }
      }

      // 5. Clean up party slots if fodders were assigned
      await tx.delete(combatPartySlots).where(inArray(combatPartySlots.heroId, uniqueFodderIds));

      // 6. Safely unequip all equipment on fodders back to Master inventory
      await tx.update(equipmentInstances)
        .set({ location: 'INVENTORY', equippedHeroId: null })
        .where(inArray(equipmentInstances.equippedHeroId, uniqueFodderIds));

      // 7. Check and deduct Master Silver
      const [master] = await tx.select().from(masters).where(eq(masters.id, masterId)).for('update').limit(1);
      if (!master) throw new ProgressionError('Master not found.', 404);
      const masterSilver = master.silverCoins ?? 0n;
      if (masterSilver < BigInt(cost)) {
        throw new ProgressionError(`Insufficient Silver coins. Required: ${cost}, available: ${masterSilver}.`, 409);
      }

      const nextSilver = masterSilver - BigInt(cost);
      await tx.update(masters).set({ silverCoins: nextSilver, updatedAt: new Date() }).where(eq(masters.id, master.id));
      await tx.insert(currencyTransactions).values({
        id: (await tx.execute<{ id: string }>('select gen_random_uuid()::text as id')).rows[0].id,
        masterId: master.id,
        currencyType: 'SILVER',
        amountDelta: -BigInt(cost),
        transactionType: 'HERO_STAR_PROMOTION',
        referenceId: hero.id,
      });

      // 8. Delete / consume fodders
      await tx.delete(heroSkillInstances).where(inArray(heroSkillInstances.heroId, uniqueFodderIds));
      await tx.delete(heroPersonalityTraits).where(inArray(heroPersonalityTraits.heroId, uniqueFodderIds));
      await tx.delete(heroImprints).where(inArray(heroImprints.heroId, uniqueFodderIds));
      await tx.delete(heroSubclasses).where(inArray(heroSubclasses.heroId, uniqueFodderIds));
      await tx.delete(heroElementAffinities).where(inArray(heroElementAffinities.heroId, uniqueFodderIds));
      await tx.delete(heroes).where(inArray(heroes.id, uniqueFodderIds));

      // 9. Update Target Hero with promoted star & recomputed stats
      let updated;
      const nextMaxLevel = starMaxLevel(nextStar);
      if (isV2Origin(hero.originStats)) {
        const newOrigin = promoteOriginStats(originOf(hero.originStats), hero.rarity as StarRating, nextStar);
        const imprintBonus = await this.getImprintBonus(tx, hero.id);
        const snapshot = progressionFor({
          origin: newOrigin,
          star: nextStar,
          level: hero.level,
          classCode: hero.classCode as HeroClass,
          training: hero.trainingStats,
          hpPct: hero.currentHpPct,
          mpPct: hero.currentMpPct,
          awakeningRank: hero.awakeningRank,
          imprint: imprintBonus,
        });

        [updated] = await tx.update(heroes).set({
          rarity: nextStar,
          originStats: newOrigin,
          baseStr: snapshot.base.str,
          baseInt: snapshot.base.int,
          baseSta: snapshot.base.sta,
          baseAgi: snapshot.base.agi,
          maxHp: snapshot.maxHp,
          hp: snapshot.hp,
          attack: snapshot.attack,
          defense: snapshot.defense,
          speed: snapshot.speed,
          mp: snapshot.mp,
          maxMp: snapshot.maxMp,
          updatedAt: new Date(),
        }).where(eq(heroes.id, hero.id)).returning();
      } else {
        // Legacy fallback
        const maxHp = Math.round(hero.maxHp * 1.25);
        [updated] = await tx.update(heroes).set({
          rarity: nextStar,
          maxHp,
          hp: Math.min(maxHp, hero.hp + (maxHp - hero.maxHp)),
          attack: Math.round(hero.attack * 1.25),
          defense: Math.round(hero.defense * 1.25),
          speed: Math.round(hero.speed * 1.1),
          updatedAt: new Date(),
        }).where(eq(heroes.id, hero.id)).returning();
      }

      // 10. Audit log
      void auditService.record({
        actorId: master.id,
        actorType: 'MASTER',
        action: 'HERO_STAR_PROMOTED',
        entityType: 'HERO',
        entityId: hero.id,
        diff: {
          fromStar: hero.rarity,
          toStar: nextStar,
          fodders: uniqueFodderIds,
          silverCost: cost,
          newLevelCap: nextMaxLevel,
        },
      });

      return {
        heroId: updated.id,
        heroName: updated.name,
        previousStar: hero.rarity,
        newStar: updated.rarity,
        level: updated.level,
        maxLevel: nextMaxLevel,
        imprintSlots: imprintSlotsFor(updated.rarity),
        consumedFodderIds: uniqueFodderIds,
        silverCost: cost,
        remainingSilver: nextSilver.toString(),
        stats: {
          hp: updated.hp,
          maxHp: updated.maxHp,
          mp: updated.mp ?? 0,
          maxMp: updated.maxMp ?? 0,
          attack: updated.attack,
          defense: updated.defense,
          speed: updated.speed,
          baseStr: updated.baseStr ?? 0,
          baseInt: updated.baseInt ?? 0,
          baseSta: updated.baseSta ?? 0,
          baseAgi: updated.baseAgi ?? 0,
        },
      };
    });
  }
}

export const heroPromotionService = new HeroPromotionService();
