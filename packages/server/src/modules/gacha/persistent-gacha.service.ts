import { randomInt } from 'node:crypto';
import { and, eq, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { calculateFiveStarRate, GAME_CONSTANTS } from '@infiniti-gacha/shared';
import { getPityRules } from '../admin/runtime-rules.js';
import { db } from '../../database/db.js';
import {
  banners, heroes, heroElementAffinities, heroTemplates, masterBannerPity, masterItems,
  masterSummonInventory, masters, summonHistory, summonRewardPool, summonSessions,
} from '../../database/drizzle-schema.js';
import { affinityColumns, buildSummonedHero, HERO_STAR_LOCKED } from '../hero/hero-generation.js';

export class SummonError extends Error {
  constructor(message: string, public readonly statusCode: number) { super(message); }
}

function secureRandom(): number { return randomInt(0, 1_000_000_000) / 1_000_000_000; }

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

function originForBanner(bannerType: string): 'NORMAL' | 'SPECIAL' | 'LIMITED' {
  if (bannerType === 'STANDARD' || bannerType === 'NORMAL') return 'NORMAL';
  if (bannerType === 'SPECIAL') return 'SPECIAL';
  if (bannerType === 'LIMITED') return 'LIMITED';
  throw new SummonError('Loại banner chưa có loại Thiên Thư tương ứng.', 409);
}

function scrollForBanner(bannerType: string): 'NORMAL' | 'SPECIAL' | 'LIMITED' {
  return originForBanner(bannerType);
}

export class PersistentGachaService {
  public async summon(masterId: string, bannerId: string, rollCount: 1 | 10, idempotencyKey: string) {
    if (!idempotencyKey || idempotencyKey.length > 80) throw new SummonError('Thiếu hoặc sai Idempotency-Key.', 400);

    // Read the active pity configuration before opening the transaction so the
    // admin plane is never queried while holding row locks.
    const pityRules = await getPityRules();

    return db.transaction(async (tx) => {
      const [master] = await tx.select().from(masters).where(eq(masters.id, masterId)).for('update').limit(1);
      if (!master) throw new SummonError('Không tìm thấy Master.', 404);

      const [existingSession] = await tx.select().from(summonSessions)
        .where(and(eq(summonSessions.masterId, masterId), eq(summonSessions.idempotencyKey, idempotencyKey))).limit(1);
      if (existingSession) {
        const existingResults = await tx.select().from(summonHistory).where(eq(summonHistory.sessionId, existingSession.id)).orderBy(summonHistory.rollNumber);
        return this.response(existingSession, existingResults);
      }

      const now = new Date();
      const [banner] = await tx.select().from(banners)
        .where(and(eq(banners.id, bannerId), eq(banners.isActive, true))).limit(1);
      if (!banner || banner.startDate > now || (banner.endDate && banner.endDate <= now)) {
        throw new SummonError('Banner không tồn tại hoặc hiện không hoạt động.', 404);
      }

      const scrollType = scrollForBanner(banner.bannerType);
      const [inventory] = await tx.select().from(masterSummonInventory)
        .where(and(eq(masterSummonInventory.masterId, masterId), eq(masterSummonInventory.scrollType, scrollType)))
        .for('update').limit(1);
      if (!inventory || inventory.quantity < rollCount) throw new SummonError(`Không đủ Thiên Thư loại ${scrollType}.`, 409);

      const poolRows = await tx.select().from(summonRewardPool)
        .where(and(eq(summonRewardPool.bannerId, bannerId), eq(summonRewardPool.isActive, true)));
      const fiveStars = poolRows.filter(row => row.poolGroup === 'FIVE_STAR_HERO' && row.rewardType === 'HERO' && row.rarity === 5);
      const otherHeroes = poolRows.filter(row => row.poolGroup === 'OTHER_HERO' && row.rewardType === 'HERO' && row.rarity !== null && row.rarity >= 1 && row.rarity <= 4);
      const materials = poolRows.filter(row => row.poolGroup === 'MATERIAL' && row.rewardType === 'MATERIAL');
      if (!fiveStars.length || !otherHeroes.length || !materials.length || [...fiveStars, ...otherHeroes, ...materials].some(row => row.weight <= 0)) {
        throw new SummonError('Banner chưa được cấu hình đầy đủ pool 5 sao, Hero 1–4 sao và nguyên liệu.', 409);
      }

      const [pity] = await tx.select().from(masterBannerPity)
        .where(and(eq(masterBannerPity.masterId, masterId), eq(masterBannerPity.bannerId, bannerId))).for('update').limit(1);
      let pityCounter = pity?.pityCounter ?? 0;
      const pityBefore = pityCounter;
      const sessionId = uuidv4();
      const origin = originForBanner(banner.bannerType);
      await tx.insert(summonSessions).values({
        id: sessionId, masterId, bannerId, scrollType, rollCount,
        pityBefore, pityAfter: pityBefore, idempotencyKey, createdAt: now,
      });
      const results = [];

      for (let rollNumber = 1; rollNumber <= rollCount; rollNumber++) {
        const pityNumber = pityCounter + 1;
        const fiveStarRate = calculateFiveStarRate(pityNumber, pityRules);
        const wasFiveStar = secureRandom() < fiveStarRate;
        let picked;
        if (wasFiveStar) {
          picked = weightedPick(fiveStars);
          pityCounter = 0;
        } else {
          // Keep the confirmed 49.6:50 ratio within the remaining non-five-star chance.
          const heroShare = 49.6 / (49.6 + 50);
          picked = secureRandom() < heroShare ? weightedPick(otherHeroes) : weightedPick(materials);
          pityCounter = pityNumber;
        }

        let wasDuplicate = false;
        let thienMenhGranted = 0;
        let summonedRewardName = picked.rewardName;
        if (picked.rewardType === 'HERO') {
          const pickedRarity = picked.rarity ?? 1;
          const templateCode = picked.heroTemplateCode;
          // Quy tắc Thiên Mệnh: Chỉ áp dụng khi Hero từ 5★ trở lên VÀ thuộc Banner SPECIAL hoặc LIMITED
          const isSpecialOrLimited5Star = (origin === 'SPECIAL' || origin === 'LIMITED') && pickedRarity >= 5;

          const [template] = templateCode
            ? await tx.select().from(heroTemplates).where(eq(heroTemplates.code, templateCode)).limit(1)
            : [undefined];
          if (isSpecialOrLimited5Star && templateCode && (!template || template.defaultRarity !== pickedRarity)) {
            throw new SummonError(`Hero template '${templateCode}' chưa có hoặc không khớp rarity.`, 409);
          }

          let owned = null;
          if (isSpecialOrLimited5Star && templateCode) {
            [owned] = await tx.select().from(heroes)
              .where(and(eq(heroes.masterId, masterId), eq(heroes.configId, templateCode))).for('update').limit(1);
          }

          wasDuplicate = Boolean(owned);
          if (owned) {
            thienMenhGranted = 1;
            summonedRewardName = owned.name;
            await tx.update(heroes).set({ thienMenh: sql`${heroes.thienMenh} + 1`, updatedAt: now }).where(eq(heroes.id, owned.id));
          } else {
            const heroId = uuidv4();
            // Tướng thường (hoặc <5★) sinh hoàn toàn ngẫu nhiên (tên Fantasy + thiên hướng chỉ số ngẫu nhiên theo số sao), không phụ thuộc template!
            const isProcedural = !isSpecialOrLimited5Star;
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

            await tx.insert(heroes).values({
              id: heroId, masterId, configId: finalConfigId, name: finalHeroName,
              rarity: build.star, category: origin, state: 'HEALTHY', level: 1,
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
          }
        } else {
          await tx.insert(masterItems).values({ id: uuidv4(), masterId, itemId: picked.rewardId, quantity: 1, updatedAt: now })
            .onConflictDoUpdate({
              target: [masterItems.masterId, masterItems.itemId],
              set: { quantity: sql`${masterItems.quantity} + 1`, updatedAt: now },
            });
        }

        const [historyRow] = await tx.insert(summonHistory).values({
          id: uuidv4(), sessionId, masterId, bannerId, rollNumber, pityNumber,
          rewardType: picked.rewardType, rewardId: picked.rewardId, rewardName: summonedRewardName,
          rarity: picked.rarity ?? 0, wasFiveStar, wasDuplicate, thienMenhGranted,
          summonOrigin: picked.rewardType === 'HERO' ? origin : null, createdAt: now,
        }).returning();
        results.push(historyRow);
      }

      await tx.update(masterSummonInventory).set({ quantity: inventory.quantity - rollCount, updatedAt: now }).where(eq(masterSummonInventory.id, inventory.id));
      if (pity) {
        await tx.update(masterBannerPity).set({ pityCounter, updatedAt: now }).where(eq(masterBannerPity.id, pity.id));
      } else {
        await tx.insert(masterBannerPity).values({ id: uuidv4(), masterId, bannerId, pityCounter, updatedAt: now });
      }

      await tx.update(summonSessions).set({ pityAfter: pityCounter }).where(eq(summonSessions.id, sessionId));
      return { sessionId, pityBefore, finalPityCounter: pityCounter, scrollsConsumed: rollCount, results: results.map(row => this.formatResult(row)) };
    });
  }

  private formatResult(row: typeof summonHistory.$inferSelect) {
    return {
      rollNumber: row.rollNumber, pityNumber: row.pityNumber, isFiveStar: row.wasFiveStar,
      rewardType: row.rewardType,
      itemType: row.rewardType, rewardId: row.rewardId, rewardName: row.rewardName,
      rarity: row.rarity, isDuplicate: row.wasDuplicate,
      duplicateBonus: row.thienMenhGranted ? { thienMenhGranted: row.thienMenhGranted } : undefined,
      summonOrigin: row.summonOrigin,
    };
  }

  private response(session: typeof summonSessions.$inferSelect, rows: (typeof summonHistory.$inferSelect)[]) {
    return {
      sessionId: session.id, pityBefore: session.pityBefore, finalPityCounter: session.pityAfter,
      scrollsConsumed: session.rollCount, results: rows.map(row => this.formatResult(row)),
    };
  }
}
