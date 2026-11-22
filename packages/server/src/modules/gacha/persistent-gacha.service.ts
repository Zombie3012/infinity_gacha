import { randomInt } from 'node:crypto';
import { and, eq, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { GAME_CONSTANTS, type ElementAffinity } from '@infiniti-gacha/shared';
import { db } from '../../database/db.js';
import {
  currencyTransactions,
  banners, heroes, heroElementAffinities, heroTemplates, masterItems,
  masterSummonInventory, masters, itemTemplates, summonHistory, summonRewardPool, summonSessions,
} from '../../database/drizzle-schema.js';
import { affinityColumns, buildSummonedHero, HERO_STAR_LOCKED } from '../hero/hero-generation.js';

export const SPECIAL_BANNER_GEM_COST_PER_ROLL = GAME_CONSTANTS.GACHA.SPECIAL_BANNER_GEM_COST_PER_ROLL;

export class SummonError extends Error {
  constructor(message: string, public readonly statusCode: number) { super(message); }
}

function weightedPick<T extends { weight: number }>(rows: T[]): T {
  const total = rows.reduce((sum, row) => sum + row.weight, 0);
  if (total <= 0 || !Number.isSafeInteger(total)) throw new SummonError('Banner có trọng số pool không hợp lệ.', 409);
  let cursor = randomInt(total);
  for (const row of rows) {
    cursor -= row.weight;
    if (cursor < 0) return row;
  }
  return rows[rows.length - 1];
}

function paymentTypeForBanner(bannerType: string): 'NORMAL' | 'SPECIAL' | 'LIMITED' {
  if (bannerType === 'STANDARD' || bannerType === 'NORMAL') return 'NORMAL';
  if (bannerType === 'SPECIAL') return 'SPECIAL';
  if (bannerType === 'LIMITED') return 'LIMITED';
  throw new SummonError('Loại banner chưa có loại Thiên Thư tương ứng.', 409);
}

function scrollForBanner(bannerType: string): 'NORMAL' | 'SPECIAL' | 'LIMITED' {
  return paymentTypeForBanner(bannerType);
}

export interface SummonedHeroPayload {
  id: string;
  name: string;
  rarity: number;
  level: number;
  classCode: string;
  combatRole: string;
  element: string;
  baseStr: number;
  baseInt: number;
  baseSta: number;
  baseAgi: number;
  hp: number;
  maxHp: number;
  attack: number;
  defense: number;
  speed: number;
  elementAffinities?: ElementAffinity | null;
}

export class PersistentGachaService {
  public async summon(masterId: string, bannerId: string, rollCount: 1 | 10, idempotencyKey: string) {
    if (!idempotencyKey || idempotencyKey.length > 80) throw new SummonError('Thiếu hoặc sai Idempotency-Key.', 400);

    return db.transaction(async (tx) => {
      const [master] = await tx.select().from(masters).where(eq(masters.id, masterId)).for('update').limit(1);
      if (!master) throw new SummonError('Không tìm thấy Master.', 404);

      const [existingSession] = await tx.select().from(summonSessions)
        .where(and(eq(summonSessions.masterId, masterId), eq(summonSessions.idempotencyKey, idempotencyKey))).limit(1);
      if (existingSession) {
        const existingResults = await tx.select().from(summonHistory).where(eq(summonHistory.sessionId, existingSession.id)).orderBy(summonHistory.rollNumber);
        return this.response(existingSession, existingResults, master.gems.toString());
      }

      const now = new Date();
      const [banner] = await tx.select().from(banners)
        .where(and(eq(banners.id, bannerId), eq(banners.isActive, true))).limit(1);
      if (!banner || banner.startDate > now || (banner.endDate && banner.endDate <= now)) {
        throw new SummonError('Banner không tồn tại hoặc hiện không hoạt động.', 404);
      }

      const scrollType = scrollForBanner(banner.bannerType);
      const isGemBanner = banner.bannerType === 'SPECIAL';
      const costGems = BigInt(SPECIAL_BANNER_GEM_COST_PER_ROLL * rollCount);

      let inventory: typeof masterSummonInventory.$inferSelect | undefined;
      if (isGemBanner) {
        if (master.gems < costGems) {
          throw new SummonError(`Không đủ Đá Quý (cần ${costGems.toString()} Gem, hiện có ${master.gems.toString()} Gem).`, 409);
        }
      } else {
        [inventory] = await tx.select().from(masterSummonInventory)
          .where(and(eq(masterSummonInventory.masterId, masterId), eq(masterSummonInventory.scrollType, scrollType)))
          .for('update').limit(1);
        if (!inventory || inventory.quantity < rollCount) {
          throw new SummonError(`Không đủ Thiên Thư loại ${scrollType}.`, 409);
        }
      }

      const poolRows = await tx.select().from(summonRewardPool)
        .where(and(eq(summonRewardPool.bannerId, bannerId), eq(summonRewardPool.isActive, true)));
      const heroesPool = poolRows.filter(row => row.rewardType === 'HERO' && row.rarity !== null && row.rarity >= 1 && row.rarity <= 7);
      const materialsPool = poolRows.filter(row => row.rewardType === 'MATERIAL');
      if (!heroesPool.length || !materialsPool.length || poolRows.some(row => row.weight <= 0)) {
        throw new SummonError('Banner chưa được cấu hình đầy đủ pool Hero và nguyên liệu.', 409);
      }

      const sessionId = uuidv4();
      await tx.insert(summonSessions).values({
        id: sessionId, masterId, bannerId, scrollType, rollCount,
        pityBefore: 0, pityAfter: 0, idempotencyKey, createdAt: now,
      });

      const results: { row: typeof summonHistory.$inferSelect; hero?: SummonedHeroPayload }[] = [];

      for (let rollNumber = 1; rollNumber <= rollCount; rollNumber++) {
        // Pure flat-rate weighted random roll (no pity escalation).
        const picked = weightedPick(poolRows);
        const wasFiveStar = picked.rewardType === 'HERO' && picked.rarity === 5;

        const wasDuplicate = false;
        const thienMenhGranted = 0;
        let summonedRewardName = picked.rewardName;
        let heroPayload: SummonedHeroPayload | undefined;
        let rewardRarity = picked.rarity ?? 1;

        if (picked.rewardType === 'HERO') {
          const pickedRarity = picked.rarity ?? 1;
          const templateCode = picked.heroTemplateCode;
          const isProceduralPool = !templateCode || templateCode.startsWith('PROCEDURAL_');
          const isFixedTemplate = !isProceduralPool;

          const [template] = templateCode
            ? await tx.select().from(heroTemplates).where(eq(heroTemplates.code, templateCode)).limit(1)
            : [undefined];
          if (isFixedTemplate && templateCode && (!template || template.defaultRarity !== pickedRarity)) {
            throw new SummonError(`Hero template '${templateCode}' chưa có hoặc không khớp rarity.`, 409);
          }

          const heroId = uuidv4();
          const isProcedural = !isFixedTemplate;
          let build;
          try {
            build = buildSummonedHero({
              star: pickedRarity,
              template: isProcedural ? null : (template ?? null),
              procedural: isProcedural,
              bannerKind: banner.bannerType,
            });
          } catch (error) {
            if ((error as Error).message === HERO_STAR_LOCKED) {
              throw new SummonError('Phẩm cấp Hero này chưa được mở.', 409);
            }
            throw error;
          }
          const finalHeroName = isProcedural ? build.name : (template?.name ?? build.name);
          const finalConfigId = isProcedural ? `PROCEDURAL_${build.star}S` : (template?.code ?? `PROCEDURAL_${build.star}S`);
          summonedRewardName = finalHeroName;

          if (finalConfigId.startsWith('PROCEDURAL_')) {
            await tx.insert(heroTemplates).values({
              id: `procedural-${build.star}s`,
              code: finalConfigId,
              name: `Procedural Hero ${build.star}★`,
              defaultRarity: build.star,
              heroClass: 'WARRIOR',
              element: 'FIRE',
              baseHp: 200,
              baseAttack: 30,
              baseDefense: 15,
              baseSpeed: 60,
            }).onConflictDoNothing();
          }

          await tx.insert(heroes).values({
            id: heroId, masterId, configId: finalConfigId, name: finalHeroName,
            rarity: build.star, category: 'HERO', state: 'HEALTHY', level: 1,
            exp: 0n,
            hp: build.derived.maxHp, maxHp: build.derived.maxHp,
            attack: build.derived.atk, defense: build.derived.def, speed: build.legacySpeed,
            baseStr: build.base.str, baseInt: build.base.int,
            baseSta: build.base.sta, baseAgi: build.base.agi,
            classCode: build.classCode, combatRole: build.combatRole,
            trainingStats: { str: 0, int: 0, sta: 0, agi: 0 },
            originStats: build.base,
            mp: build.derived.maxMp, maxMp: build.derived.maxMp,
            currentHpPct: 1, currentMpPct: 1,
            talentPoints: 0, thienMenh: 0, hunger: 0, fatigue: 0, loyalty: 100,
            createdAt: now, updatedAt: now,
          });
          if (build.elementAffinity) {
            await tx.insert(heroElementAffinities).values({
              heroId, ...affinityColumns(build.elementAffinity), updatedAt: now,
            });
          }

          const strongestElement = build.elementAffinity
            ? Object.entries(build.elementAffinity).sort((a, b) => Number(b[1]) - Number(a[1]))[0]?.[0] ?? 'NEUTRAL'
            : 'NEUTRAL';

          heroPayload = {
            id: heroId,
            name: finalHeroName,
            rarity: build.star,
            level: 1,
            classCode: build.classCode,
            combatRole: build.combatRole,
            element: strongestElement,
            baseStr: build.base.str,
            baseInt: build.base.int,
            baseSta: build.base.sta,
            baseAgi: build.base.agi,
            hp: build.derived.maxHp,
            maxHp: build.derived.maxHp,
            attack: build.derived.atk,
            defense: build.derived.def,
            speed: build.legacySpeed,
            elementAffinities: build.elementAffinity,
          };
        } else {
          const [item] = await tx.select({ rarity: itemTemplates.rarity }).from(itemTemplates).where(eq(itemTemplates.code, picked.rewardId)).limit(1);
          rewardRarity = Math.max(1, Math.min(7, item?.rarity ?? picked.rarity ?? 1));
          await tx.insert(masterItems).values({ id: uuidv4(), masterId, itemId: picked.rewardId, quantity: 1, updatedAt: now })
            .onConflictDoUpdate({
              target: [masterItems.masterId, masterItems.itemId],
              set: { quantity: sql`${masterItems.quantity} + 1`, updatedAt: now },
            });
        }

        const [historyRow] = await tx.insert(summonHistory).values({
          id: uuidv4(), sessionId, masterId, bannerId, rollNumber, pityNumber: 0,
          rewardType: picked.rewardType, rewardId: picked.rewardId, rewardName: summonedRewardName,
          rarity: rewardRarity, wasFiveStar, wasDuplicate, thienMenhGranted,
          summonOrigin: picked.rewardType === 'HERO' ? 'HERO' : null, createdAt: now,
        }).returning();
        results.push({ row: historyRow, hero: heroPayload });
      }

      let remainingGems = master.gems.toString();
      let remainingScrolls: number | undefined;
      if (isGemBanner) {
        const [updatedMaster] = await tx.update(masters)
          .set({ gems: sql`${masters.gems} - ${costGems}`, updatedAt: now })
          .where(eq(masters.id, masterId))
          .returning({ gems: masters.gems });
        remainingGems = updatedMaster.gems.toString();
        await tx.insert(currencyTransactions).values({
          id: uuidv4(),
          masterId,
          currencyType: 'GEMS',
          amountDelta: -costGems,
          transactionType: 'GACHA_SUMMON',
          referenceId: sessionId,
          createdAt: now,
        });
      } else if (inventory) {
        remainingScrolls = inventory.quantity - rollCount;
        await tx.update(masterSummonInventory)
          .set({ quantity: remainingScrolls, updatedAt: now })
          .where(eq(masterSummonInventory.id, inventory.id));
      }

      return {
        sessionId,
        bannerId,
        bannerType: banner.bannerType,
        currencyType: isGemBanner ? 'GEMS' : 'SCROLL',
        currencyConsumed: isGemBanner ? Number(costGems) : rollCount,
        scrollsConsumed: isGemBanner ? 0 : rollCount,
        remainingGems,
        ...(remainingScrolls !== undefined ? { remainingScrolls } : {}),
        results: results.map(item => this.formatResult(item.row, item.hero)),
      };
    });
  }

  private formatResult(row: typeof summonHistory.$inferSelect, hero?: SummonedHeroPayload) {
    return {
      rollNumber: row.rollNumber,
      isFiveStar: row.wasFiveStar,
      rewardType: row.rewardType,
      itemType: row.rewardType,
      rewardId: row.rewardId,
      rewardName: row.rewardName,
      rarity: row.rarity,
      isDuplicate: row.wasDuplicate,
      duplicateBonus: row.thienMenhGranted ? { thienMenhGranted: row.thienMenhGranted } : undefined,
      summonOrigin: row.summonOrigin,
      ...(hero ? { hero } : {}),
    };
  }

  private response(
    session: typeof summonSessions.$inferSelect,
    rows: (typeof summonHistory.$inferSelect)[],
    remainingGems: string,
  ) {
    const isGemBanner = session.scrollType === 'SPECIAL';
    return {
      sessionId: session.id,
      bannerId: session.bannerId,
      currencyType: isGemBanner ? 'GEMS' : 'SCROLL',
      currencyConsumed: isGemBanner ? SPECIAL_BANNER_GEM_COST_PER_ROLL * session.rollCount : session.rollCount,
      scrollsConsumed: isGemBanner ? 0 : session.rollCount,
      remainingGems,
      results: rows.map(row => this.formatResult(row)),
    };
  }
}
