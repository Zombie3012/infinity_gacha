import { and, eq, inArray, or, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import {
  combatPartySlots, heroPersonalityTraits, heroRelationships, heroes, masterItems, masterParties, masters,
} from '../../database/drizzle-schema.js';
import {
  LOYALTY_START, affinityGainForVictory, assignTraits, clampLoyalty, disobedienceChance, loyaltyAfterFavoriteMeal,
  loyaltyAfterVictory, loyaltyCombatMultiplier, loyaltyState, relationshipTier, resonanceMultiplier,
} from './personality-rules.js';

export class PersonalityError extends Error {
  constructor(message: string, readonly statusCode = 400) {
    super(message);
    this.name = 'PersonalityError';
  }
}

export interface HeroPersonalityView {
  heroId: string;
  name: string;
  level: number;
  coreTrait: string;
  socialTrait: string;
  behavioralTrait: string;
  specialTrait: string;
  favoriteFood: string;
  loyaltyScore: number;
  loyaltyState: string;
  combatMultiplier: number;
  disobedienceChance: number;
}

export class PersonalityService {
  /** Every Hero owns exactly one personality row and one relationship row per pair. */
  async ensure(masterId: string) {
    const roster = await db.select({ id: heroes.id }).from(heroes).where(eq(heroes.masterId, masterId));
    if (roster.length === 0) return;

    const existing = await db.select({ heroId: heroPersonalityTraits.heroId }).from(heroPersonalityTraits)
      .where(inArray(heroPersonalityTraits.heroId, roster.map(row => row.id)));
    const known = new Set(existing.map(row => row.heroId));
    const missing = roster.filter(row => !known.has(row.id));
    if (missing.length > 0) {
      const now = new Date();
      await db.insert(heroPersonalityTraits).values(missing.map(row => ({
        heroId: row.id,
        ...assignTraits(row.id),
        loyaltyScore: LOYALTY_START,
        createdAt: now,
        updatedAt: now,
      }))).onConflictDoNothing();
    }

    const ids = roster.map(row => row.id);
    const pairs = await db.select({ heroAId: heroRelationships.heroAId, heroBId: heroRelationships.heroBId })
      .from(heroRelationships).where(eq(heroRelationships.masterId, masterId));
    const knownPairs = new Set(pairs.map(row => `${row.heroAId}|${row.heroBId}`));
    const now = new Date();
    const inserts = [];
    for (let i = 0; i < ids.length; i += 1) {
      for (let j = i + 1; j < ids.length; j += 1) {
        const [a, b] = [ids[i], ids[j]].sort();
        if (knownPairs.has(`${a}|${b}`)) continue;
        inserts.push({ id: uuidv4(), masterId, heroAId: a, heroBId: b, affinityPoints: 0, lastInteractionAt: now, createdAt: now });
      }
    }
    if (inserts.length > 0) await db.insert(heroRelationships).values(inserts).onConflictDoNothing();
  }

  async overview(masterId: string) {
    await this.ensure(masterId);
    const roster = await db.select({
      id: heroes.id, name: heroes.name, level: heroes.level, state: heroes.state, category: heroes.category,
    }).from(heroes).where(eq(heroes.masterId, masterId));
    if (roster.length === 0) return { heroes: [], relationships: [] };

    const traits = await db.select().from(heroPersonalityTraits)
      .where(inArray(heroPersonalityTraits.heroId, roster.map(row => row.id)));
    const traitByHero = new Map(traits.map(row => [row.heroId, row]));
    const relationships = await db.select().from(heroRelationships).where(eq(heroRelationships.masterId, masterId));
    const nameById = new Map(roster.map(row => [row.id, row.name]));

    const heroesView: HeroPersonalityView[] = roster.map(hero => {
      const trait = traitByHero.get(hero.id);
      const loyalty = trait?.loyaltyScore ?? LOYALTY_START;
      return {
        heroId: hero.id,
        name: hero.name,
        level: hero.level,
        coreTrait: trait?.coreTrait ?? 'UNKNOWN',
        socialTrait: trait?.socialTrait ?? 'UNKNOWN',
        behavioralTrait: trait?.behavioralTrait ?? 'UNKNOWN',
        specialTrait: trait?.specialTrait ?? 'UNKNOWN',
        favoriteFood: trait?.favoriteFood ?? 'ROAST_CHICKEN',
        loyaltyScore: loyalty,
        loyaltyState: loyaltyState(loyalty),
        combatMultiplier: loyaltyCombatMultiplier(loyalty),
        disobedienceChance: disobedienceChance(loyalty),
      };
    });

    return {
      heroes: heroesView,
      relationships: relationships.map(row => ({
        id: row.id,
        heroAId: row.heroAId,
        heroBId: row.heroBId,
        heroAName: nameById.get(row.heroAId) ?? '—',
        heroBName: nameById.get(row.heroBId) ?? '—',
        affinityPoints: row.affinityPoints,
        tier: relationshipTier(row.affinityPoints),
        resonanceBonus: resonanceMultiplier(relationshipTier(row.affinityPoints)),
      })).sort((a, b) => b.affinityPoints - a.affinityPoints),
    };
  }

  /**
   * Loyalty and resonance modifiers for the party that is about to deploy.
   * Returns an empty map when the party is empty.
   */
  async combatModifiers(masterId: string, partyId?: string) {
    await this.ensure(masterId);
    const [party] = partyId
      ? await db.select({ id: masterParties.id }).from(masterParties).where(and(eq(masterParties.id, partyId), eq(masterParties.masterId, masterId))).limit(1)
      : await db.select({ id: masterParties.id }).from(masterParties).where(and(eq(masterParties.masterId, masterId), eq(masterParties.isDefault, true))).limit(1);
    if (!party) return {} as Record<string, { loyalty: number; resonance: number; disobedience: number }>;

    const members = await db.select({ heroId: combatPartySlots.heroId }).from(combatPartySlots).where(eq(combatPartySlots.partyId, party.id));
    if (members.length === 0) return {};
    const ids = members.map(row => row.heroId);
    const traits = await db.select().from(heroPersonalityTraits).where(inArray(heroPersonalityTraits.heroId, ids));
    const traitByHero = new Map(traits.map(row => [row.heroId, row]));

    const pairRows = await db.select().from(heroRelationships).where(and(
      eq(heroRelationships.masterId, masterId),
      or(inArray(heroRelationships.heroAId, ids), inArray(heroRelationships.heroBId, ids)),
    ));
    const resonance = new Map<string, number>();
    for (const pair of pairRows) {
      if (!ids.includes(pair.heroAId) || !ids.includes(pair.heroBId)) continue;
      const bonus = resonanceMultiplier(relationshipTier(pair.affinityPoints));
      if (bonus > 1) {
        resonance.set(pair.heroAId, bonus);
        resonance.set(pair.heroBId, bonus);
      }
    }

    const result: Record<string, { loyalty: number; resonance: number; disobedience: number }> = {};
    for (const heroId of ids) {
      const loyalty = traitByHero.get(heroId)?.loyaltyScore ?? LOYALTY_START;
      result[heroId] = {
        loyalty: loyaltyCombatMultiplier(loyalty),
        resonance: resonance.get(heroId) ?? 1,
        disobedience: disobedienceChance(loyalty),
      };
    }
    return result;
  }

  /** Shared victories raise loyalty and pair affinity (scenario 3.1). */
  async recordVictory(masterId: string, heroIds: string[]) {
    if (heroIds.length === 0) return { loyaltyUpdated: 0, pairsUpdated: 0 };
    await this.ensure(masterId);
    const now = new Date();
    const traits = await db.select().from(heroPersonalityTraits).where(inArray(heroPersonalityTraits.heroId, heroIds));
    for (const trait of traits) {
      await db.update(heroPersonalityTraits)
        .set({ loyaltyScore: loyaltyAfterVictory(trait.loyaltyScore), updatedAt: now })
        .where(eq(heroPersonalityTraits.heroId, trait.heroId));
    }

    let pairsUpdated = 0;
    for (let i = 0; i < heroIds.length; i += 1) {
      for (let j = i + 1; j < heroIds.length; j += 1) {
        const [a, b] = [heroIds[i], heroIds[j]].sort();
        await db.update(heroRelationships)
          .set({ affinityPoints: sql`${heroRelationships.affinityPoints} + ${affinityGainForVictory(1)}`, lastInteractionAt: now })
          .where(and(eq(heroRelationships.heroAId, a), eq(heroRelationships.heroBId, b)));
        pairsUpdated += 1;
      }
    }
    return { loyaltyUpdated: traits.length, pairsUpdated };
  }

  /** Scenario 2.3: a favourite meal raises loyalty by 5. */
  async serveFavoriteMeal(masterId: string, heroId: string) {
    await this.ensure(masterId);
    const [trait] = await db.select().from(heroPersonalityTraits).where(eq(heroPersonalityTraits.heroId, heroId)).limit(1);
    if (!trait) throw new PersonalityError('Không tìm thấy hồ sơ tính cách.', 404);
    const [hero] = await db.select({ id: heroes.id }).from(heroes)
      .where(and(eq(heroes.id, heroId), eq(heroes.masterId, masterId))).limit(1);
    if (!hero) throw new PersonalityError('Không tìm thấy Hero.', 404);

    const [item] = await db.select().from(masterItems)
      .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, trait.favoriteFood))).limit(1);
    if (!item || item.quantity < 1) throw new PersonalityError(`Cần 1 ${trait.favoriteFood} trong kho.`, 409);

    const now = new Date();
    const next = loyaltyAfterFavoriteMeal(trait.loyaltyScore);
    await db.transaction(async tx => {
      await tx.update(masterItems).set({ quantity: sql`${masterItems.quantity} - 1`, updatedAt: now })
        .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, trait.favoriteFood)));
      await tx.update(heroPersonalityTraits).set({ loyaltyScore: next, updatedAt: now })
        .where(eq(heroPersonalityTraits.heroId, heroId));
    });
    return { heroId, itemId: trait.favoriteFood, loyaltyScore: next, loyaltyState: loyaltyState(next) };
  }

  async adjustLoyalty(masterId: string, heroId: string, delta: number, reason: string) {
    await this.ensure(masterId);
    const [trait] = await db.select().from(heroPersonalityTraits).where(eq(heroPersonalityTraits.heroId, heroId)).limit(1);
    if (!trait) throw new PersonalityError('Không tìm thấy hồ sơ tính cách.', 404);
    const next = clampLoyalty(trait.loyaltyScore + delta);
    await db.update(heroPersonalityTraits).set({ loyaltyScore: next, updatedAt: new Date() })
      .where(eq(heroPersonalityTraits.heroId, heroId));
    return { heroId, loyaltyScore: next, loyaltyState: loyaltyState(next), reason };
  }

  /** Master progress summary used by the client header. */
  async summary(masterId: string) {
    const rows = await db.select({ loyalty: heroPersonalityTraits.loyaltyScore }).from(heroPersonalityTraits)
      .innerJoin(heroes, eq(heroes.id, heroPersonalityTraits.heroId))
      .where(eq(heroes.masterId, masterId));
    const [master] = await db.select({ id: masters.id }).from(masters).where(eq(masters.id, masterId)).limit(1);
    return {
      heroes: rows.length,
      danger: rows.filter(row => loyaltyState(row.loyalty) === 'DANGER').length,
      devoted: rows.filter(row => loyaltyState(row.loyalty) === 'DEVOTED').length,
      averageLoyalty: rows.length ? Math.round(rows.reduce((sum, row) => sum + row.loyalty, 0) / rows.length) : 0,
      masterFound: Boolean(master),
    };
  }
}

export const personalityService = new PersonalityService();
