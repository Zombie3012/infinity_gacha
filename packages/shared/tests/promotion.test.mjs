import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  BASE_STAT_BUDGET,
  checkStarPromotionEligibility,
  heroEffectiveMaxLevel,
  promoteOriginStats,
  requiredFodderCount,
  starMaxLevel,
  starPromotionCost,
} from '../dist/index.js';

test('Combat v2 - Star Promotion (Pick Me Up style)', async (t) => {
  await t.test('starMaxLevel follows 10 levels per star rule', () => {
    assert.equal(starMaxLevel(1), 10);
    assert.equal(starMaxLevel(2), 20);
    assert.equal(starMaxLevel(3), 30);
    assert.equal(starMaxLevel(4), 40);
    assert.equal(starMaxLevel(5), 50);
  });

  await t.test('heroEffectiveMaxLevel enforces min(starCeiling, breakthroughCap)', () => {
    assert.equal(heroEffectiveMaxLevel(1, 0), 10);
    assert.equal(heroEffectiveMaxLevel(1, 1), 10); // Star ceiling 10 caps it
    assert.equal(heroEffectiveMaxLevel(2, 0), 10); // Breakthrough cap 10 caps it
    assert.equal(heroEffectiveMaxLevel(2, 1), 20); // Both reach 20
    assert.equal(heroEffectiveMaxLevel(5, 0), 10); // Fresh 5★ starts at cap 10
    assert.equal(heroEffectiveMaxLevel(5, 1), 20); // 5★ at breakthrough 1 reaches 20
    assert.equal(heroEffectiveMaxLevel(5, 4), 50); // 5★ at breakthrough 4 reaches 50
  });

  await t.test('requiredFodderCount requires N heroes of N stars', () => {
    assert.equal(requiredFodderCount(1), 1);
    assert.equal(requiredFodderCount(2), 2);
    assert.equal(requiredFodderCount(3), 3);
    assert.equal(requiredFodderCount(4), 4);
    assert.equal(requiredFodderCount(5), 5);
  });

  await t.test('starPromotionCost scales with star tier', () => {
    assert.equal(starPromotionCost(1), 10_000);
    assert.equal(starPromotionCost(2), 25_000);
    assert.equal(starPromotionCost(3), 50_000);
    assert.equal(starPromotionCost(4), 100_000);
  });

  await t.test('checkStarPromotionEligibility enforces max level and valid state', () => {
    assert.deepEqual(checkStarPromotionEligibility({ currentStar: 1, currentLevel: 10 }), { eligible: true });
    assert.deepEqual(checkStarPromotionEligibility({ currentStar: 2, currentLevel: 20 }), { eligible: true });

    assert.equal(
      checkStarPromotionEligibility({ currentStar: 1, currentLevel: 9 }).reason,
      'ERR_HERO_LEVEL_NOT_MAX',
    );
    assert.equal(
      checkStarPromotionEligibility({ currentStar: 2, currentLevel: 15 }).reason,
      'ERR_HERO_LEVEL_NOT_MAX',
    );
    assert.equal(
      checkStarPromotionEligibility({ currentStar: 1, currentLevel: 10, isLocked: true }).reason,
      'ERR_HERO_LOCKED',
    );
    assert.equal(
      checkStarPromotionEligibility({ currentStar: 1, currentLevel: 10, state: 'DEAD' }).reason,
      'ERR_HERO_PERMANENTLY_DEAD',
    );
    assert.equal(
      checkStarPromotionEligibility({ currentStar: 5, currentLevel: 50 }).reason,
      'ERR_HERO_MAX_STAR',
    );
  });

  await t.test('promoteOriginStats scales budget to the next star while keeping distribution', () => {
    // 1-star origin: 100 points
    const origin1 = { str: 40, int: 20, sta: 25, agi: 15 };
    assert.equal(origin1.str + origin1.int + origin1.sta + origin1.agi, BASE_STAT_BUDGET[1]);

    // Promoted to 2-star: 130 points (+30 points)
    const origin2 = promoteOriginStats(origin1, 1, 2);
    const total2 = origin2.str + origin2.int + origin2.sta + origin2.agi;
    assert.equal(total2, BASE_STAT_BUDGET[2]);
    assert.ok(origin2.str >= origin1.str);
    assert.ok(origin2.int >= origin1.int);
    assert.ok(origin2.sta >= origin1.sta);
    assert.ok(origin2.agi >= origin1.agi);

    // Promoted to 3-star: 170 points (+40 points)
    const origin3 = promoteOriginStats(origin2, 2, 3);
    const total3 = origin3.str + origin3.int + origin3.sta + origin3.agi;
    assert.equal(total3, BASE_STAT_BUDGET[3]);

    // Promoted to 4-star: 220 points (+50 points)
    const origin4 = promoteOriginStats(origin3, 3, 4);
    const total4 = origin4.str + origin4.int + origin4.sta + origin4.agi;
    assert.equal(total4, BASE_STAT_BUDGET[4]);

    // Promoted to 5-star: 280 points (+60 points)
    const origin5 = promoteOriginStats(origin4, 4, 5);
    const total5 = origin5.str + origin5.int + origin5.sta + origin5.agi;
    assert.equal(total5, BASE_STAT_BUDGET[5]);
  });
});
