import { and, desc, eq, inArray, isNull, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import {
  baseBuildings, heroInjuries, heroResurrectionCycles, heroSurvivalStates, heroTreatments, heroes, masterItems, masters,
} from '../../database/drizzle-schema.js';
import {
  DIVINE_TEAR_ITEM, MEDICINE_ITEM, bedCapacityForLevel, classifyInjury, injuryMultiplier, resurrectionQuote,
  revivedFatigueGain, revivedHpPercent, treatmentSeconds, type InjurySeverity,
} from './medical-rules.js';

export class MedicalError extends Error {
  constructor(message: string, readonly statusCode = 400) {
    super(message);
    this.name = 'MedicalError';
  }
}

const FACILITY_TYPE = 'MEDICAL';

export interface InjuredHeroView {
  heroId: string;
  name: string;
  hp: number;
  maxHp: number;
  injuryId: string;
  severity: InjurySeverity;
  penaltyPercent: number;
  naturalHealAt: string;
}

export class MedicalService {
  private async facilityRow(masterId: string) {
    const [row] = await db.select().from(baseBuildings)
      .where(and(eq(baseBuildings.masterId, masterId), eq(baseBuildings.buildingType, FACILITY_TYPE))).limit(1);
    return row;
  }

  private async itemQuantity(masterId: string, itemId: string): Promise<number> {
    const [row] = await db.select().from(masterItems)
      .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, itemId))).limit(1);
    return row?.quantity ?? 0;
  }

  /** Natural healing and treatment timers resolve lazily on the next read. */
  async settle(masterId: string, now = new Date()) {
    const expired = await db.select().from(heroInjuries)
      .where(and(eq(heroInjuries.masterId, masterId), isNull(heroInjuries.healedAt)));
    for (const injury of expired) {
      if (injury.naturalHealAt > now) continue;
      await db.update(heroInjuries).set({ healedAt: now, healedBy: 'NATURAL' }).where(eq(heroInjuries.id, injury.id));
    }

    const active = await db.select().from(heroTreatments)
      .where(and(eq(heroTreatments.masterId, masterId), eq(heroTreatments.status, 'ACTIVE')));
    for (const treatment of active) {
      if (!treatment.finishesAt || treatment.finishesAt > now) continue;
      await db.update(heroTreatments).set({ status: 'COMPLETED', completedAt: now }).where(eq(heroTreatments.id, treatment.id));
      if (treatment.injuryId) {
        await db.update(heroInjuries).set({ healedAt: now, healedBy: 'TREATMENT' })
          .where(and(eq(heroInjuries.id, treatment.injuryId), isNull(heroInjuries.healedAt)));
      }
      const remaining = await db.select({ id: heroInjuries.id }).from(heroInjuries)
        .where(and(eq(heroInjuries.heroId, treatment.heroId), isNull(heroInjuries.healedAt)));
      if (remaining.length === 0) {
        await db.update(heroes).set({ state: 'HEALTHY', updatedAt: now })
          .where(and(eq(heroes.id, treatment.heroId), eq(heroes.state, 'INJURED')));
      }
    }
  }

  /** Multipliers applied to combat stats for every Hero carrying an active injury. */
  async penaltyByHero(masterId: string): Promise<Record<string, number>> {
    const rows = await db.select().from(heroInjuries)
      .where(and(eq(heroInjuries.masterId, masterId), isNull(heroInjuries.healedAt)));
    const result: Record<string, number> = {};
    for (const row of rows) {
      const multiplier = injuryMultiplier(row.penaltyPercent);
      result[row.heroId] = Math.min(result[row.heroId] ?? 1, multiplier);
    }
    return result;
  }

  /** Called after a battle resolves; records injuries for survivors below 50% HP. */
  async recordBattleInjuries(masterId: string, survivors: { id: string; hp: number; maxHp: number }[]) {
    if (survivors.length === 0) return { injured: 0 };
    const ids = survivors.map(row => row.id);
    const existing = await db.select().from(heroInjuries)
      .where(and(inArray(heroInjuries.heroId, ids), isNull(heroInjuries.healedAt)));
    const alreadyInjured = new Set(existing.map(row => row.heroId));
    const now = new Date();
    let injured = 0;

    for (const survivor of survivors) {
      if (alreadyInjured.has(survivor.id)) continue;
      if (survivor.maxHp <= 0) continue;
      const hpPercent = (survivor.hp / survivor.maxHp) * 100;
      const profile = classifyInjury(hpPercent);
      if (!profile) continue;
      await db.insert(heroInjuries).values({
        id: uuidv4(),
        heroId: survivor.id,
        masterId,
        severity: profile.severity,
        penaltyPercent: profile.penaltyPercent,
        naturalHealAt: new Date(now.getTime() + profile.naturalHealSeconds * 1000),
        startedAt: now,
      });
      await db.update(heroes).set({ state: 'INJURED', updatedAt: now })
        .where(and(eq(heroes.id, survivor.id), eq(heroes.masterId, masterId)));
      injured += 1;
    }
    return { injured };
  }

  async overview(masterId: string) {
    await this.settle(masterId);
    const facility = await this.facilityRow(masterId);
    const level = facility?.level ?? 0;
    const capacity = facility ? bedCapacityForLevel(level) : 0;

    const treatments = await db.select({
      id: heroTreatments.id,
      heroId: heroTreatments.heroId,
      heroName: heroes.name,
      treatmentType: heroTreatments.treatmentType,
      status: heroTreatments.status,
      startedAt: heroTreatments.startedAt,
      finishesAt: heroTreatments.finishesAt,
      completedAt: heroTreatments.completedAt,
      costSilver: heroTreatments.costSilver,
    }).from(heroTreatments).innerJoin(heroes, eq(heroes.id, heroTreatments.heroId))
      .where(eq(heroTreatments.masterId, masterId)).orderBy(desc(heroTreatments.startedAt)).limit(30);

    const serialisedTreatments = treatments.map(row => ({ ...row, costSilver: row.costSilver.toString() }));
    const activeTreatments = serialisedTreatments.filter(row => row.status === 'ACTIVE');
    const bedsUsed = activeTreatments.filter(row => row.treatmentType === 'INJURY').length;

    const injuries = await db.select({
      id: heroInjuries.id,
      heroId: heroInjuries.heroId,
      heroName: heroes.name,
      hp: heroes.hp,
      maxHp: heroes.maxHp,
      severity: heroInjuries.severity,
      penaltyPercent: heroInjuries.penaltyPercent,
      naturalHealAt: heroInjuries.naturalHealAt,
    }).from(heroInjuries).innerJoin(heroes, eq(heroes.id, heroInjuries.heroId))
      .where(and(eq(heroInjuries.masterId, masterId), isNull(heroInjuries.healedAt)))
      .orderBy(desc(heroInjuries.startedAt));

    const disabled = await db.select({ id: heroes.id, name: heroes.name, category: heroes.category, maxHp: heroes.maxHp })
      .from(heroes).where(and(eq(heroes.masterId, masterId), eq(heroes.state, 'DISABLED')));

    const now = new Date();
    const resurrection = [];
    for (const hero of disabled) {
      const [cycle] = await db.select().from(heroResurrectionCycles).where(eq(heroResurrectionCycles.heroId, hero.id)).limit(1);
      const quote = resurrectionQuote(cycle?.resurrectionCount ?? 0, cycle?.cycleStartAt ?? now, now);
      resurrection.push({
        heroId: hero.id,
        name: hero.name,
        category: hero.category,
        tears: quote.tears,
        silver: quote.silver,
        cycleCount: quote.cycleCount,
        cycleReset: quote.cycleReset,
        tearsOwned: await this.itemQuantity(masterId, DIVINE_TEAR_ITEM),
        affordable: false,
      });
    }
    const [master] = await db.select({ silverCoins: masters.silverCoins }).from(masters).where(eq(masters.id, masterId)).limit(1);
    const silver = Number(master?.silverCoins ?? 0n);
    for (const row of resurrection) row.affordable = row.tearsOwned >= row.tears && silver >= row.silver;

    return {
      facility: facility ? { buildingId: facility.id, level, capacity, bedsUsed, bedsFree: Math.max(0, capacity - bedsUsed) } : null,
      capacity,
      bedsUsed,
      injuries: injuries.map(row => ({ ...row, attackMultiplier: injuryMultiplier(row.penaltyPercent) })),
      treatments: serialisedTreatments,
      activeTreatments,
      resurrection,
      medicineStored: await this.itemQuantity(masterId, MEDICINE_ITEM),
    };
  }

  async admit(masterId: string, heroId: string) {
    await this.settle(masterId);
    const facility = await this.facilityRow(masterId);
    if (!facility) throw new MedicalError('Chưa xây Viện Y Tế.', 409);
    const capacity = bedCapacityForLevel(facility.level);
    const occupied = await db.select({ id: heroTreatments.id }).from(heroTreatments)
      .where(and(eq(heroTreatments.masterId, masterId), eq(heroTreatments.status, 'ACTIVE'), eq(heroTreatments.treatmentType, 'INJURY')));
    if (occupied.length >= capacity) throw new MedicalError('Viện Y Tế đã hết giường.', 409);

    const [injury] = await db.select().from(heroInjuries)
      .where(and(eq(heroInjuries.heroId, heroId), eq(heroInjuries.masterId, masterId), isNull(heroInjuries.healedAt))).limit(1);
    if (!injury) throw new MedicalError('Hero không có thương tích cần điều trị.', 409);
    const [duplicate] = await db.select({ id: heroTreatments.id }).from(heroTreatments)
      .where(and(eq(heroTreatments.heroId, heroId), eq(heroTreatments.status, 'ACTIVE'))).limit(1);
    if (duplicate) throw new MedicalError('Hero đang được điều trị.', 409);

    const [hero] = await db.select({ id: heroes.id }).from(heroes)
      .where(and(eq(heroes.id, heroId), eq(heroes.masterId, masterId))).limit(1);
    if (!hero) throw new MedicalError('Không tìm thấy Hero.', 404);

    const now = new Date();
    const remainingSeconds = Math.max(0, (injury.naturalHealAt.getTime() - now.getTime()) / 1000);
    const seconds = treatmentSeconds(remainingSeconds, facility.level);
    const [treatment] = await db.insert(heroTreatments).values({
      id: uuidv4(), masterId, heroId, buildingId: facility.id, injuryId: injury.id,
      treatmentType: 'INJURY', status: 'ACTIVE', startedAt: now,
      finishesAt: new Date(now.getTime() + seconds * 1000), costSilver: 0n, costItems: {},
    }).returning();
    return { treatment: { ...treatment, costSilver: treatment.costSilver.toString() }, seconds };
  }

  async emergency(masterId: string, heroId: string) {
    await this.settle(masterId);
    const stored = await this.itemQuantity(masterId, MEDICINE_ITEM);
    if (stored < 1) throw new MedicalError(`Cần 1 ${MEDICINE_ITEM} để chữa trị khẩn cấp.`, 409);
    const [injury] = await db.select().from(heroInjuries)
      .where(and(eq(heroInjuries.heroId, heroId), eq(heroInjuries.masterId, masterId), isNull(heroInjuries.healedAt))).limit(1);
    if (!injury) throw new MedicalError('Hero không có thương tích cần điều trị.', 409);

    const now = new Date();
    await db.transaction(async tx => {
      await tx.update(masterItems).set({ quantity: sql`${masterItems.quantity} - 1`, updatedAt: now })
        .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, MEDICINE_ITEM)));
      await tx.update(heroInjuries).set({ healedAt: now, healedBy: 'EMERGENCY' }).where(eq(heroInjuries.id, injury.id));
      await tx.update(heroTreatments).set({ status: 'COMPLETED', completedAt: now })
        .where(and(eq(heroTreatments.heroId, heroId), eq(heroTreatments.status, 'ACTIVE')));
      await tx.update(heroes).set({ state: 'HEALTHY', updatedAt: now })
        .where(and(eq(heroes.id, heroId), eq(heroes.state, 'INJURED')));
    });
    return { heroId, healed: true, medicineUsed: 1 };
  }

  async resurrect(masterId: string, heroId: string) {
    await this.settle(masterId);
    const [hero] = await db.select().from(heroes)
      .where(and(eq(heroes.id, heroId), eq(heroes.masterId, masterId))).limit(1);
    if (!hero) throw new MedicalError('Không tìm thấy Hero.', 404);
    // Scenario 6.3: Normal Heroes die permanently.
    if (hero.category === 'NORMAL') throw new MedicalError('ERR_RESURRECTION_NORMAL_PERMADEATH', 409);
    if (hero.state === 'HEALTHY' || hero.state === 'INJURED') throw new MedicalError('Hero vẫn còn sống.', 409);

    const now = new Date();
    const [cycle] = await db.select().from(heroResurrectionCycles).where(eq(heroResurrectionCycles.heroId, heroId)).limit(1);
    const quote = resurrectionQuote(cycle?.resurrectionCount ?? 0, cycle?.cycleStartAt ?? now, now);
    const tearsOwned = await this.itemQuantity(masterId, DIVINE_TEAR_ITEM);
    if (tearsOwned < quote.tears) throw new MedicalError(`Cần ${quote.tears} ${DIVINE_TEAR_ITEM}.`, 409);
    const [master] = await db.select({ silverCoins: masters.silverCoins }).from(masters).where(eq(masters.id, masterId)).limit(1);
    if (!master || master.silverCoins < BigInt(quote.silver)) throw new MedicalError('Không đủ Xu Bạc để hồi sinh.', 409);

    const revivedHp = Math.max(1, Math.floor(hero.maxHp * revivedHpPercent()));
    await db.transaction(async tx => {
      await tx.update(masters).set({ silverCoins: sql`${masters.silverCoins} - ${quote.silver}`, updatedAt: now })
        .where(eq(masters.id, masterId));
      await tx.update(masterItems).set({ quantity: sql`${masterItems.quantity} - ${quote.tears}`, updatedAt: now })
        .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, DIVINE_TEAR_ITEM)));
      await tx.update(heroes).set({ state: 'HEALTHY', hp: revivedHp, updatedAt: now }).where(eq(heroes.id, heroId));
      const nextCount = quote.cycleCount + 1;
      await tx.insert(heroResurrectionCycles).values({
        heroId, cycleStartAt: quote.cycleReset ? now : (cycle?.cycleStartAt ?? now),
        resurrectionCount: nextCount, lastResurrectedAt: now,
      }).onConflictDoUpdate({
        target: [heroResurrectionCycles.heroId],
        set: {
          cycleStartAt: quote.cycleReset ? now : (cycle?.cycleStartAt ?? now),
          resurrectionCount: nextCount,
          lastResurrectedAt: now,
        },
      });
      await tx.insert(heroSurvivalStates).values({
        heroId, hungerScore: 0, fatigueScore: revivedFatigueGain(), isResting: false, lastTickAt: now,
      }).onConflictDoUpdate({
        target: [heroSurvivalStates.heroId],
        set: { fatigueScore: sql`least(100, ${heroSurvivalStates.fatigueScore} + ${revivedFatigueGain()})`, lastTickAt: now },
      });
      await tx.insert(heroTreatments).values({
        id: uuidv4(), masterId, heroId, buildingId: null, injuryId: null,
        treatmentType: 'RESURRECTION', status: 'COMPLETED', startedAt: now,
        finishesAt: now, completedAt: now, costSilver: BigInt(quote.silver),
        costItems: { [DIVINE_TEAR_ITEM]: quote.tears },
      });
    });

    return { heroId, hp: revivedHp, tearsUsed: quote.tears, silverSpent: quote.silver, cycleCount: quote.cycleCount + 1, cycleReset: quote.cycleReset };
  }

  async history(masterId: string) {
    const rows = await db.select({
      id: heroTreatments.id,
      heroName: heroes.name,
      treatmentType: heroTreatments.treatmentType,
      status: heroTreatments.status,
      startedAt: heroTreatments.startedAt,
      completedAt: heroTreatments.completedAt,
      costSilver: heroTreatments.costSilver,
      costItems: heroTreatments.costItems,
    }).from(heroTreatments).innerJoin(heroes, eq(heroes.id, heroTreatments.heroId))
      .where(eq(heroTreatments.masterId, masterId)).orderBy(desc(heroTreatments.startedAt)).limit(50);
    return rows.map(row => ({ ...row, costSilver: row.costSilver.toString() }));
  }
}

export const medicalService = new MedicalService();
