import type { GameDatabase } from '../../database/transaction.js';
import { isLivingHero } from '@infiniti-gacha/shared';
import { and, asc, desc, eq, gt, inArray, isNull, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import {
  baseBuildings, heroInjuries, heroResurrectionCycles, heroSurvivalStates, heroTreatments, heroes, masterItems, masters,
} from '../../database/drizzle-schema.js';
import {
  RESURRECTION_GEM_ITEM, MEDICINE_ITEM, bedCapacityForLevel, classifyInjury, injuryMultiplier,
  revivedHpPercent, treatmentSeconds, type InjurySeverity,
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
  private async facilityRow(masterId: string, database: GameDatabase = db) {
    const [row] = await database.select().from(baseBuildings)
      .where(and(eq(baseBuildings.masterId, masterId), eq(baseBuildings.buildingType, FACILITY_TYPE))).limit(1);
    return row;
  }

  private async itemQuantity(masterId: string, itemId: string, database: GameDatabase = db): Promise<number> {
    const [row] = await database.select().from(masterItems)
      .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, itemId))).limit(1);
    return row?.quantity ?? 0;
  }

  /** Natural healing and treatment timers resolve lazily on the next read. */
  async settle(masterId: string, now = new Date()) {
    return db.transaction(async tx => {
      // Completing a treatment and healing its Hero must precede any new deployment.
      await tx.select({ id: masters.id }).from(masters).where(eq(masters.id, masterId)).for('update');
      // Old/stale treatment rows must never revive a casualty through ordinary care.
      const pending = await tx.select({ id: heroTreatments.id, hero: heroes }).from(heroTreatments)
        .innerJoin(heroes, eq(heroes.id, heroTreatments.heroId))
        .where(and(eq(heroTreatments.masterId, masterId), inArray(heroTreatments.status, ['ACTIVE', 'QUEUED'])));
      for (const row of pending) if (!isLivingHero(row.hero)) {
        await tx.update(heroTreatments).set({ status: 'CANCELLED', completedAt: now }).where(eq(heroTreatments.id, row.id));
      }
      const expired = await tx.select().from(heroInjuries)
        .where(and(eq(heroInjuries.masterId, masterId), isNull(heroInjuries.healedAt)));
      for (const injury of expired) {
        if (injury.naturalHealAt > now) continue;
        await tx.update(heroInjuries).set({ healedAt: now, healedBy: 'NATURAL' }).where(eq(heroInjuries.id, injury.id));
      }

      const active = await tx.select().from(heroTreatments)
        .where(and(eq(heroTreatments.masterId, masterId), eq(heroTreatments.status, 'ACTIVE')));
      for (const treatment of active) {
        if (!treatment.finishesAt || treatment.finishesAt > now) continue;
        await tx.update(heroTreatments).set({ status: 'COMPLETED', completedAt: now }).where(eq(heroTreatments.id, treatment.id));
        if (treatment.injuryId) {
          await tx.update(heroInjuries).set({ healedAt: now, healedBy: 'TREATMENT' })
            .where(and(eq(heroInjuries.id, treatment.injuryId), isNull(heroInjuries.healedAt)));
        }
        const remaining = await tx.select({ id: heroInjuries.id }).from(heroInjuries)
          .where(and(eq(heroInjuries.heroId, treatment.heroId), isNull(heroInjuries.healedAt)));
        await tx.update(heroes).set({
          state: remaining.length === 0 ? 'HEALTHY' : 'INJURED',
          hp: sql`${heroes.maxHp}`,
          currentHpPct: 1,
          updatedAt: now,
        }).where(eq(heroes.id, treatment.heroId));
      }

      // Auto-promote QUEUED treatments to ACTIVE if bed capacity is available
      const facility = await this.facilityRow(masterId, tx);
      if (facility) {
        const capacity = bedCapacityForLevel(facility.level);
        const currentActive = await tx.select({ id: heroTreatments.id }).from(heroTreatments)
          .where(and(eq(heroTreatments.masterId, masterId), eq(heroTreatments.status, 'ACTIVE'), eq(heroTreatments.treatmentType, 'INJURY')));
        let freeBeds = Math.max(0, capacity - currentActive.length);
        if (freeBeds > 0) {
          const queued = await tx.select().from(heroTreatments)
            .where(and(eq(heroTreatments.masterId, masterId), eq(heroTreatments.status, 'QUEUED'), eq(heroTreatments.treatmentType, 'INJURY')))
            .orderBy(asc(heroTreatments.startedAt));
          for (const q of queued) {
            if (freeBeds <= 0) break;
            let sec = 180;
            if (q.injuryId) {
              const [inj] = await tx.select().from(heroInjuries).where(eq(heroInjuries.id, q.injuryId)).limit(1);
              if (inj) {
                const remainingSeconds = Math.max(0, (inj.naturalHealAt.getTime() - now.getTime()) / 1000);
                sec = treatmentSeconds(remainingSeconds, facility.level);
              }
            }
            await tx.update(heroTreatments).set({
              status: 'ACTIVE',
              startedAt: now,
              finishesAt: new Date(now.getTime() + sec * 1000),
            }).where(eq(heroTreatments.id, q.id));
            freeBeds -= 1;
          }
        }
      }
    });
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
  async recordBattleInjuries(masterId: string, survivors: { id: string; hp: number; maxHp: number }[], database: GameDatabase = db, now = new Date()) {
    if (survivors.length === 0) return { injured: 0 };
    const ids = survivors.map(row => row.id);
    const existing = await database.select().from(heroInjuries)
      .where(and(inArray(heroInjuries.heroId, ids), isNull(heroInjuries.healedAt)));
    const alreadyInjured = new Set(existing.map(row => row.heroId));
    let injured = 0;

    for (const survivor of survivors) {
      if (survivor.hp <= 0) continue;
      const [living] = await database.select({ state: heroes.state, hp: heroes.hp }).from(heroes)
        .where(and(eq(heroes.id, survivor.id), eq(heroes.masterId, masterId)));
      if (!living || !isLivingHero(living)) continue;
      if (alreadyInjured.has(survivor.id)) continue;
      if (survivor.maxHp <= 0) continue;
      const hpPercent = (survivor.hp / survivor.maxHp) * 100;
      const profile = classifyInjury(hpPercent);
      if (!profile) continue;
      await database.insert(heroInjuries).values({
        id: uuidv4(),
        heroId: survivor.id,
        masterId,
        severity: profile.severity,
        penaltyPercent: profile.penaltyPercent,
        naturalHealAt: new Date(now.getTime() + profile.naturalHealSeconds * 1000),
        startedAt: now,
      });
      await database.update(heroes).set({ state: 'INJURED', updatedAt: now })
        .where(and(eq(heroes.id, survivor.id), eq(heroes.masterId, masterId), gt(heroes.hp, 0), sql`${heroes.state} NOT IN ('DEAD','DISABLED')`));
      injured += 1;
    }
    return { injured };
  }

  async overview(masterId: string) {
    await this.settle(masterId);
    const facility = await this.facilityRow(masterId);
    const level = facility?.level ?? 0;
    const capacity = facility ? bedCapacityForLevel(level) : 0;
    const maxQueue = capacity * 3;

    const treatments = await db.select({
      id: heroTreatments.id,
      heroId: heroTreatments.heroId,
      heroName: heroes.name,
      heroClass: heroes.classCode,
      heroLevel: heroes.level,
      heroRarity: heroes.rarity,
      heroHp: heroes.hp,
      heroMaxHp: heroes.maxHp,
      treatmentType: heroTreatments.treatmentType,
      status: heroTreatments.status,
      startedAt: heroTreatments.startedAt,
      finishesAt: heroTreatments.finishesAt,
      completedAt: heroTreatments.completedAt,
      costSilver: heroTreatments.costSilver,
    }).from(heroTreatments).innerJoin(heroes, eq(heroes.id, heroTreatments.heroId))
      .where(eq(heroTreatments.masterId, masterId)).orderBy(desc(heroTreatments.startedAt)).limit(40);

    const now = new Date();
    const serialisedTreatments = treatments.map(row => {
      const started = row.startedAt.getTime();
      const finishes = row.finishesAt ? row.finishesAt.getTime() : started;
      const totalSec = Math.max(1, Math.round((finishes - started) / 1000));
      const remSec = Math.max(0, Math.round((finishes - now.getTime()) / 1000));
      const progress = row.status === 'COMPLETED' ? 1.0 : Math.min(1.0, Math.max(0.0, 1.0 - remSec / totalSec));
      return {
        ...row,
        costSilver: row.costSilver.toString(),
        totalSeconds: totalSec,
        secondsRemaining: remSec,
        progressPercent: Math.round(progress * 100),
      };
    });

    const activeTreatments = serialisedTreatments.filter(row => row.status === 'ACTIVE');
    const queuedTreatments = serialisedTreatments.filter(row => row.status === 'QUEUED');
    const bedsUsed = activeTreatments.filter(row => row.treatmentType === 'INJURY').length;
    const bedsFree = Math.max(0, capacity - bedsUsed);

    const activeHeroIds = new Set(activeTreatments.map(t => t.heroId));
    const queuedHeroIds = new Set(queuedTreatments.map(t => t.heroId));

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
      .where(and(eq(heroInjuries.masterId, masterId), isNull(heroInjuries.healedAt), gt(heroes.hp, 0), sql`${heroes.state} NOT IN ('DEAD', 'DISABLED')`))
      .orderBy(desc(heroInjuries.startedAt));

    const injuredHeroMap = new Map(injuries.map(inj => [inj.heroId, inj]));

    // All Heroes of this Master to build full Candidates list
    const allHeroes = await db.select().from(heroes).where(eq(heroes.masterId, masterId)).orderBy(asc(heroes.hp));
    const candidates = allHeroes.filter(isLivingHero).map(h => {
      const curHp = Number(h.hp);
      const maxHp = Math.max(1, Number(h.maxHp));
      const hpPct = Math.round((curHp / maxHp) * 100);
      const isInjured = injuredHeroMap.has(h.id) || h.state === 'INJURED';
      const isTreating = activeHeroIds.has(h.id);
      const isQueued = queuedHeroIds.has(h.id);
      const needsHeal = curHp < maxHp || isInjured;
      return {
        id: h.id,
        name: h.name,
        rarity: h.rarity,
        level: h.level,
        classCode: h.classCode,
        hp: curHp,
        maxHp,
        hpPercent: hpPct,
        state: h.state,
        needsHeal,
        isInjured,
        isTreating,
        isQueued,
        injury: injuredHeroMap.get(h.id) ?? null,
      };
    });

    const deceased = await db.select({ id: heroes.id, name: heroes.name, rarity: heroes.rarity, maxHp: heroes.maxHp })
      .from(heroes).where(and(eq(heroes.masterId, masterId), eq(heroes.state, 'DEAD')));
    const gemsOwned = await this.itemQuantity(masterId, RESURRECTION_GEM_ITEM);
    const resurrection = deceased.map(hero => ({ heroId: hero.id, name: hero.name, rarity: hero.rarity,
      gemItemId: RESURRECTION_GEM_ITEM, gemsRequired: 1, gemsOwned, silver: 0, affordable: gemsOwned >= 1 }));

    return {
      facility: facility ? { buildingId: facility.id, level, capacity, bedsUsed, bedsFree, maxQueue } : null,
      capacity,
      bedsUsed,
      bedsFree,
      maxQueue,
      activeTreatments,
      queuedTreatments,
      candidates,
      injuries: injuries.map(row => ({ ...row, attackMultiplier: injuryMultiplier(row.penaltyPercent) })),
      treatments: serialisedTreatments,
      resurrection,
      medicineStored: await this.itemQuantity(masterId, MEDICINE_ITEM),
    };
  }

  async admit(masterId: string, heroId: string) {
    await this.settle(masterId);
    return db.transaction(async tx => {
      await tx.select({ id: masters.id }).from(masters).where(eq(masters.id, masterId)).for('update');
      const facility = await this.facilityRow(masterId, tx);
      if (!facility) throw new MedicalError('Chưa xây Trung Tâm Hồi Phục (Recovery Center).', 409);
      const capacity = bedCapacityForLevel(facility.level);
      const maxQueue = capacity * 3;

      const [hero] = await tx.select().from(heroes)
        .where(and(eq(heroes.id, heroId), eq(heroes.masterId, masterId))).for('update').limit(1);
      if (!hero) throw new MedicalError('Không tìm thấy Hero.', 404);
      if (!isLivingHero(hero)) {
        throw new MedicalError('Hero đã tử trận. Hãy hồi sinh trước khi đưa vào chữa trị.', 409);
      }

      const [injury] = await tx.select().from(heroInjuries)
        .where(and(eq(heroInjuries.heroId, heroId), eq(heroInjuries.masterId, masterId), isNull(heroInjuries.healedAt))).limit(1);
      if (!injury && hero.hp >= hero.maxHp) {
        throw new MedicalError('Hero đã đầy 100% HP và không có thương tích cần chữa trị.', 409);
      }

      const [existing] = await tx.select({ id: heroTreatments.id, status: heroTreatments.status }).from(heroTreatments)
        .where(and(eq(heroTreatments.heroId, heroId), inArray(heroTreatments.status, ['ACTIVE', 'QUEUED']))).limit(1);
      if (existing) {
        throw new MedicalError(existing.status === 'ACTIVE' ? 'Hero đang được điều trị trên giường bệnh.' : 'Hero đang trong Hàng chờ hồi phục.', 409);
      }

      const occupied = await tx.select({ id: heroTreatments.id }).from(heroTreatments)
        .where(and(eq(heroTreatments.masterId, masterId), eq(heroTreatments.status, 'ACTIVE'), eq(heroTreatments.treatmentType, 'INJURY')));

      const now = new Date();
      const canBedNow = occupied.length < capacity;

      if (!canBedNow) {
        const queuedCount = await tx.select({ id: heroTreatments.id }).from(heroTreatments)
          .where(and(eq(heroTreatments.masterId, masterId), eq(heroTreatments.status, 'QUEUED'), eq(heroTreatments.treatmentType, 'INJURY')));
        if (queuedCount.length >= maxQueue) {
          throw new MedicalError(`Hàng chờ hồi phục đã đầy (tối đa ${maxQueue} Hero).`, 409);
        }

        const [treatment] = await tx.insert(heroTreatments).values({
          id: uuidv4(), masterId, heroId, buildingId: facility.id, injuryId: injury?.id ?? null,
          treatmentType: 'INJURY', status: 'QUEUED', startedAt: now,
          finishesAt: null, costSilver: 0n, costItems: {},
        }).returning();
        return { treatment: { ...treatment, costSilver: treatment.costSilver.toString() }, isQueued: true, seconds: 0 };
      }

      let remainingSeconds = 180;
      if (injury) {
        remainingSeconds = Math.max(60, (injury.naturalHealAt.getTime() - now.getTime()) / 1000);
      } else {
        const lostHpPct = Math.max(0.05, 1.0 - (hero.hp / hero.maxHp));
        remainingSeconds = Math.round(lostHpPct * 1200);
      }
      const seconds = treatmentSeconds(remainingSeconds, facility.level);

      const [treatment] = await tx.insert(heroTreatments).values({
        id: uuidv4(), masterId, heroId, buildingId: facility.id, injuryId: injury?.id ?? null,
        treatmentType: 'INJURY', status: 'ACTIVE', startedAt: now,
        finishesAt: new Date(now.getTime() + seconds * 1000), costSilver: 0n, costItems: {},
      }).returning();
      return { treatment: { ...treatment, costSilver: treatment.costSilver.toString() }, isQueued: false, seconds };
    });
  }

  async batchAdmit(masterId: string, heroIds: string[]) {
    if (!Array.isArray(heroIds) || heroIds.length === 0) {
      throw new MedicalError('Danh sách Hero hồi phục không được để trống.');
    }
    const admitted: string[] = [];
    const queued: string[] = [];
    const errors: { heroId: string; message: string }[] = [];

    for (const hid of heroIds) {
      try {
        const res = await this.admit(masterId, hid);
        if (res.isQueued) queued.push(hid);
        else admitted.push(hid);
      } catch (err: unknown) {
        errors.push({ heroId: hid, message: err instanceof Error ? err.message : String(err) });
      }
    }
    return { admitted, queued, errors };
  }

  async emergency(masterId: string, heroId: string) {
    await this.settle(masterId);
    const stored = await this.itemQuantity(masterId, MEDICINE_ITEM);
    if (stored < 1) throw new MedicalError(`Cần 1 ${MEDICINE_ITEM} (Bình thuốc hồi phục) để chữa trị khẩn cấp.`, 409);

    const [hero] = await db.select().from(heroes)
      .where(and(eq(heroes.id, heroId), eq(heroes.masterId, masterId))).limit(1);
    if (!hero) throw new MedicalError('Không tìm thấy Hero.', 404);
    if (!isLivingHero(hero)) {
      throw new MedicalError('Hero đã tử trận. Cần dùng Nước Mắt Nữ Thần để Hồi Sinh.', 409);
    }

    const [injury] = await db.select().from(heroInjuries)
      .where(and(eq(heroInjuries.heroId, heroId), eq(heroInjuries.masterId, masterId), isNull(heroInjuries.healedAt))).limit(1);

    if (!injury && hero.hp >= hero.maxHp) {
      throw new MedicalError('Hero đã đầy 100% HP và không có thương tích.', 409);
    }

    const now = new Date();
    await db.transaction(async tx => {
      await tx.select({ id: masters.id }).from(masters).where(eq(masters.id, masterId)).for('update');
      const [current] = await tx.select().from(heroes).where(and(eq(heroes.id, heroId), eq(heroes.masterId, masterId))).for('update');
      if (!current || !isLivingHero(current)) throw new MedicalError('Hero không còn sống hoặc đang chờ hồi sinh.', 409);
      const [currentInjury] = await tx.select().from(heroInjuries).where(and(eq(heroInjuries.heroId, heroId), isNull(heroInjuries.healedAt))).limit(1);
      if (!currentInjury && current.hp >= current.maxHp) throw new MedicalError('Hero đã đầy HP và không có thương tích.', 409);
      const [spent] = await tx.update(masterItems).set({ quantity: sql`${masterItems.quantity} - 1`, updatedAt: now })
        .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, MEDICINE_ITEM), gt(masterItems.quantity, 0))).returning({ id: masterItems.id });
      if (!spent) throw new MedicalError(`Cần 1 ${MEDICINE_ITEM}.`, 409);
      if (currentInjury) {
        await tx.update(heroInjuries).set({ healedAt: now, healedBy: 'EMERGENCY' }).where(eq(heroInjuries.id, currentInjury.id));
      }
      await tx.update(heroTreatments).set({ status: 'COMPLETED', completedAt: now })
        .where(and(eq(heroTreatments.heroId, heroId), inArray(heroTreatments.status, ['ACTIVE', 'QUEUED'])));
      await tx.update(heroes).set({ state: 'HEALTHY', hp: sql`${heroes.maxHp}`, currentHpPct: 1, updatedAt: now })
        .where(and(eq(heroes.id, heroId)));
    });
    return { heroId, healed: true, medicineUsed: 1 };
  }

  async batchEmergency(masterId: string, heroIds: string[]) {
    if (!Array.isArray(heroIds) || heroIds.length === 0) {
      throw new MedicalError('Danh sách Hero Quick Heal không được để trống.');
    }
    const healed: string[] = [];
    const errors: { heroId: string; message: string }[] = [];
    for (const hid of heroIds) {
      try {
        await this.emergency(masterId, hid);
        healed.push(hid);
      } catch (err: unknown) {
        errors.push({ heroId: hid, message: err instanceof Error ? err.message : String(err) });
      }
    }
    return { healed, errors };
  }

  async cancelTreatment(masterId: string, heroId: string) {
    const [treatment] = await db.select().from(heroTreatments)
      .where(and(eq(heroTreatments.masterId, masterId), eq(heroTreatments.heroId, heroId), inArray(heroTreatments.status, ['ACTIVE', 'QUEUED']))).limit(1);
    if (!treatment) throw new MedicalError('Không tìm thấy ca điều trị đang diễn ra của Hero này.', 404);

    const now = new Date();
    await db.update(heroTreatments).set({ status: 'CANCELLED', completedAt: now }).where(eq(heroTreatments.id, treatment.id));
    await this.settle(masterId, now);
    return { cancelled: true, heroId };
  }

  async resurrect(masterId: string, heroId: string) {
    await this.settle(masterId);
    return db.transaction(async tx => {
      const [master] = await tx.select({ silverCoins: masters.silverCoins }).from(masters).where(eq(masters.id, masterId)).for('update');
      const [hero] = await tx.select().from(heroes)
        .where(and(eq(heroes.id, heroId), eq(heroes.masterId, masterId))).for('update');
      if (!hero) throw new MedicalError('Không tìm thấy Hero.', 404);
      if (hero.state !== 'DEAD' || hero.hp > 0) throw new MedicalError('Hero chưa tử trận.', 409);
      const now = new Date();
      const [cycle] = await tx.select().from(heroResurrectionCycles).where(eq(heroResurrectionCycles.heroId, heroId)).limit(1);
      const [spent] = await tx.update(masterItems).set({ quantity: sql`${masterItems.quantity} - 1`, updatedAt: now })
        .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, RESURRECTION_GEM_ITEM), gt(masterItems.quantity, 0)))
        .returning({ quantity: masterItems.quantity });
      if (!spent) throw new MedicalError('ERR_RESURRECTION_GEM_REQUIRED', 409);
      const revivedHp = Math.max(1, Math.floor(hero.maxHp * revivedHpPercent()));
      await tx.update(heroInjuries).set({ healedAt: now, healedBy: 'RESURRECTION' })
        .where(and(eq(heroInjuries.heroId, heroId), isNull(heroInjuries.healedAt)));
      await tx.update(heroes).set({ state: 'HEALTHY', hp: revivedHp, currentHpPct: revivedHp / Math.max(1, hero.maxHp), updatedAt: now }).where(eq(heroes.id, heroId));
      const nextCount = (cycle?.resurrectionCount ?? 0) + 1;
      await tx.insert(heroResurrectionCycles).values({
        heroId, cycleStartAt: cycle?.cycleStartAt ?? now,
        resurrectionCount: nextCount, lastResurrectedAt: now,
      }).onConflictDoUpdate({
        target: [heroResurrectionCycles.heroId],
        set: {
          cycleStartAt: cycle?.cycleStartAt ?? now,
          resurrectionCount: nextCount,
          lastResurrectedAt: now,
        },
      });
      await tx.insert(heroSurvivalStates).values({
        heroId, hungerScore: 0, fatigueScore: 0, isResting: false, lastTickAt: now,
      }).onConflictDoUpdate({
        target: [heroSurvivalStates.heroId],
        set: { isResting: false, lastTickAt: now },
      });
      await tx.insert(heroTreatments).values({
        id: uuidv4(), masterId, heroId, buildingId: null, injuryId: null,
        treatmentType: 'RESURRECTION', status: 'COMPLETED', startedAt: now,
        finishesAt: now, completedAt: now, costSilver: 0n,
        costItems: { [RESURRECTION_GEM_ITEM]: 1 },
      });
      return { heroId, hp: revivedHp, gemItemId: RESURRECTION_GEM_ITEM, gemsUsed: 1, gemsRemaining: spent.quantity, silverSpent: 0 };
    });
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

