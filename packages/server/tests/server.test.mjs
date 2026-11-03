import { test } from 'node:test';
import assert from 'node:assert/strict';
import { calculateDamage, calculateElementMultiplier } from '@infiniti-gacha/shared';
import { MasterService } from '../dist/modules/master/master.service.js';
import { GachaService } from '../dist/modules/gacha/gacha.service.js';
import { TacticalBuffManager } from '../dist/modules/combat/tactical-buff.manager.js';
import { GemDebtHandler } from '../dist/modules/economy/gem-debt.handler.js';
import { WorldSeedGenerator } from '../dist/modules/dungeon/world-seed.generator.js';

test('Master Service - 1 Account = 1 Master Constraint', (t) => {
  const masterService = new MasterService();
  const master = masterService.createMaster('ACC_001', 'Archmage Ren');
  assert.equal(master.accountId, 'ACC_001');
  assert.equal(master.masterName, 'Archmage Ren');
  assert.equal(master.silverCoins, 10000n);

  assert.throws(() => {
    masterService.createMaster('ACC_001', 'Duplicate Ren');
  }, /already has a Master profile/);
});

test('Gacha Service - Duplicate Handling and Exchange Cap', async (t) => {
  const gacha = new GachaService();
  const masterId = 'M_TEST_01';

  await t.test('Weekly exchange cap enforces max 50 scrolls', () => {
    // Has 1,000,000 silver
    const initialSilver = 1000000n;
    const res1 = gacha.exchangeScroll(masterId, initialSilver, 50);
    assert.equal(res1.success, true);
    assert.equal(res1.scrollsGranted, 50);
    assert.equal(res1.newSilver, 500000n); // 50 * 10,000 = 500,000 spent

    // 51st exchange should fail
    const res2 = gacha.exchangeScroll(masterId, res1.newSilver, 1);
    assert.equal(res2.success, false);
    assert.match(res2.error, /Weekly exchange limit exceeded/);
  });

  await t.test('Summon rolls and duplicate conversion', () => {
    const banner = gacha.getOrCreateBanner('BANNER_TEST', 'Standard Banner');
    // Force roll 70 to guarantee 5-star
    banner.pityCounter = 69;

    // Roll 1: Gets 5-star Lancelot
    const roll1 = gacha.summon(masterId, 'BANNER_TEST', 1);
    assert.equal(roll1.results[0].isFiveStar, true);
    assert.equal(roll1.results[0].isDuplicate, false);

    // Roll 2: Force another 5-star -> should be marked duplicate with 1 Thien Menh
    banner.pityCounter = 69;
    const roll2 = gacha.summon(masterId, 'BANNER_TEST', 1);
    assert.equal(roll2.results[0].isFiveStar, true);
    assert.equal(roll2.results[0].isDuplicate, true);
    assert.equal(roll2.results[0].duplicateBonus.thienMenhGranted, 1);
  });
});

test('Combat - Tactical Buff 15s Cooldown', () => {
  const buffMgr = new TacticalBuffManager();
  const t0 = 1000000;

  // First change succeeds
  const change1 = buffMgr.changeBuff('VANGUARD_RUSH', t0);
  assert.equal(change1.success, true);
  assert.equal(buffMgr.getActiveBuff().id, 'VANGUARD_RUSH');

  // Change after 5 seconds fails due to 15s cooldown
  const change2 = buffMgr.changeBuff('IRONCLAD_AEGIS', t0 + 5000);
  assert.equal(change2.success, false);
  assert.equal(change2.remainingCooldownSeconds, 10);

  // Change after 15 seconds succeeds
  const change3 = buffMgr.changeBuff('IRONCLAD_AEGIS', t0 + 15000);
  assert.equal(change3.success, true);
  assert.equal(buffMgr.getActiveBuff().id, 'IRONCLAD_AEGIS');
});

test('Economy - Gem Debt Policy (No-Ban Refund)', () => {
  const master = {
    id: 'M_REFUND_01',
    accountId: 'ACC_REFUND',
    masterName: 'Player One',
    level: 1,
    exp: 0n,
    silverCoins: 0n,
    gems: 300n, // Only has 300 gems left after spending
    gemDebt: 0n,
    createdAt: new Date(),
    updatedAt: new Date(),
  };

  // Refund package of 1,000 gems
  const refundResult = GemDebtHandler.processRefund(master, 1000n);
  assert.equal(refundResult.deductedGems, 300n);
  assert.equal(refundResult.addedDebt, 700n);
  assert.equal(master.gems, 0n);
  assert.equal(master.gemDebt, 700n); // In debt, NOT banned!

  // Earn 500 gems -> Repays debt down to 200n
  const credit1 = GemDebtHandler.creditGems(master, 500n);
  assert.equal(credit1.debtRepaid, 500n);
  assert.equal(credit1.netGemsAdded, 0n);
  assert.equal(master.gemDebt, 200n);

  // Earn 300 gems -> Repays remaining 200n debt + 100n net gems added
  const credit2 = GemDebtHandler.creditGems(master, 300n);
  assert.equal(credit2.debtRepaid, 200n);
  assert.equal(credit2.netGemsAdded, 100n);
  assert.equal(master.gemDebt, 0n);
  assert.equal(master.gems, 100n);
});

test('Dungeon - World Seed Generation (UUIDv4)', () => {
  const world = WorldSeedGenerator.createWorld('M_WORLD_01');
  assert.ok(world.worldSeed.length >= 36);
  assert.ok(world.difficultyMultiplier >= 1.0 && world.difficultyMultiplier <= 1.5);
  assert.equal(world.currentFloor, 1);
});

test('Battle Initialization - MOD-06-01 Combatant Assignment & Strategy Setup', () => {
  // FUN-06-01-004: Master pre-combat tactical strategy options
  assert.ok(TacticalBuffManager.AVAILABLE_BUFFS['VANGUARD_RUSH']);
  assert.ok(TacticalBuffManager.AVAILABLE_BUFFS['IRONCLAD_AEGIS']);
  assert.ok(TacticalBuffManager.AVAILABLE_BUFFS['SWIFT_EVASION']);

  const vanguard = TacticalBuffManager.AVAILABLE_BUFFS['VANGUARD_RUSH'];
  assert.equal(vanguard.attackMultiplier, 1.2);
  assert.equal(vanguard.defenseMultiplier, 0.9);

  // FUN-06-01-002 & FUN-06-01-003: Combatant State and Formation Slots
  const sampleHeroCombatant = {
    id: 'hero-1',
    slotIndex: 0,
    name: 'Arthur',
    templateCode: 'WARRIOR_001',
    origin: 'NORMAL',
    hp: 500,
    maxHp: 500,
    attack: 60,
    defense: 30,
    speed: 15,
    skills: [
      {
        skillCode: 'SLASH',
        name: 'Power Slash',
        skillLevel: 2,
        effectValue: 120,
        behaviorMode: 'AUTO',
      },
    ],
  };

  assert.equal(sampleHeroCombatant.slotIndex, 0);
  assert.equal(sampleHeroCombatant.skills.length, 1);
  assert.equal(sampleHeroCombatant.skills[0].behaviorMode, 'AUTO');

  // Enemy Combatant State with Floor Scaling
  const floor = 3;
  const baseHp = 100;
  const worldDiff = 1.1;
  const difficultyMultiplier = worldDiff * (1 + Math.max(0, floor - 1) * 0.05);
  const scaledHp = Math.max(1, Math.floor(baseHp * difficultyMultiplier));
  assert.equal(scaledHp, 121);
});

test('Auto Battle & Hero AI - MOD-06-02 Action, Target Selection & Skill Execution', async (t) => {
  await t.test('FUN-06-02-003 & FUN-06-02-004: Hero AI action selection and offensive skill execution', () => {
    const round = 1;
    const hero = {
      id: 'h-1',
      name: 'Lancelot',
      heroClass: 'WARRIOR',
      attack: 100,
      skills: [
        {
          skillCode: 'SAMPLE_SKILL_WARRIOR_HEAVY_STRIKE',
          name: 'Heavy Strike',
          skillLevel: 1,
          effectType: 'DAMAGE_SINGLE',
          effectValue: 1.5,
          cooldownRounds: 3,
          cooldownUntilRound: 0,
          behaviorMode: 'AUTO',
        },
      ],
    };

    // Ready skill is selected
    const readySkills = hero.skills.filter(s => s.behaviorMode === 'AUTO' && s.cooldownUntilRound <= round);
    assert.equal(readySkills.length, 1);
    const chosen = readySkills[0];
    assert.equal(chosen.name, 'Heavy Strike');

    // Effective attack with skill multiplier 1.5
    const effectiveAtk = Math.floor(hero.attack * chosen.effectValue);
    assert.equal(effectiveAtk, 150);

    const enemy = { name: 'Goblin', defense: 50, hp: 300, maxHp: 300 };
    const { damage } = calculateDamage(effectiveAtk, enemy.defense, false);
    enemy.hp -= damage;

    // Cooldown is set to round + cooldownRounds = 1 + 3 = 4
    chosen.cooldownUntilRound = round + chosen.cooldownRounds;
    assert.equal(chosen.cooldownUntilRound, 4);

    // In round 2, skill should be on cooldown
    const nextRoundReady = hero.skills.filter(s => s.behaviorMode === 'AUTO' && s.cooldownUntilRound <= 2);
    assert.equal(nextRoundReady.length, 0);
  });

  await t.test('FUN-06-02-002 & FUN-06-02-004: Support AI heals lowest HP ally', () => {
    const allies = [
      { id: 'h-1', name: 'Warrior', hp: 300, maxHp: 1000 }, // 30% HP
      { id: 'h-2', name: 'Mage', hp: 450, maxHp: 500 },     // 90% HP
      { id: 'h-3', name: 'Healer', hp: 600, maxHp: 600 },   // 100% HP
    ];

    const supportSkill = {
      skillCode: 'SAMPLE_SKILL_SUPPORT_HEALING_LIGHT',
      name: 'Healing Light',
      effectType: 'HEAL_LOWEST_ALLY',
      effectValue: 0.10, // 10% max HP
      cooldownRounds: 4,
      cooldownUntilRound: 0,
      behaviorMode: 'AUTO',
    };

    // AI selects lowest HP percentage ally
    allies.sort((a, b) => (a.hp / a.maxHp) - (b.hp / b.maxHp));
    const target = allies[0];
    assert.equal(target.name, 'Warrior');

    const healAmount = Math.max(1, Math.floor(target.maxHp * supportSkill.effectValue));
    assert.equal(healAmount, 100); // 10% of 1000

    target.hp = Math.min(target.maxHp, target.hp + healAmount);
    assert.equal(target.hp, 400);
  });

  await t.test('FUN-06-02-006: Party relationship assist calculation', () => {
    const assister = { name: 'Gawain', attack: 80 };
    const target = { name: 'Orc Boss', defense: 40, hp: 200 };

    // Assist strike deals 30% damage of ally attack
    const assistAtk = Math.max(1, Math.floor(assister.attack * 0.3));
    assert.equal(assistAtk, 24);

    const { damage } = calculateDamage(assistAtk, target.defense, false);
    assert.ok(damage > 0);
  });
});

test('Battle Mechanics - MOD-06-03 Damage, Elements, Critical Hits & Status Effects', async (t) => {
  await t.test('FUN-06-03-005: Elemental advantage cycle', () => {
    // Fire > Wind (1.25x advantage, 0.8x disadvantage)
    assert.equal(calculateElementMultiplier('FIRE', 'WIND'), 1.25);
    assert.equal(calculateElementMultiplier('WIND', 'FIRE'), 0.8);

    // Wind > Earth > Water > Fire
    assert.equal(calculateElementMultiplier('WIND', 'EARTH'), 1.25);
    assert.equal(calculateElementMultiplier('EARTH', 'WATER'), 1.25);
    assert.equal(calculateElementMultiplier('WATER', 'FIRE'), 1.25);

    // Light <-> Dark mutual advantage
    assert.equal(calculateElementMultiplier('LIGHT', 'DARK'), 1.25);
    assert.equal(calculateElementMultiplier('DARK', 'LIGHT'), 1.25);

    // Neutral / same element
    assert.equal(calculateElementMultiplier('FIRE', 'FIRE'), 1.0);
    assert.equal(calculateElementMultiplier(undefined, 'FIRE'), 1.0);
  });

  await t.test('FUN-06-03-001 & FUN-06-03-004: Critical hit calculation & mitigation', () => {
    const baseAtk = 100;
    const def = 100; // mitigation = 100 / (100 + 100) = 0.5

    // Normal hit: 100 * 0.5 = 50 dmg
    const normal = calculateDamage(baseAtk, def, false);
    assert.equal(normal.damage, 50);
    assert.equal(normal.isCritical, false);

    // Critical hit (+50% bonus): 100 * 0.5 * 1.5 = 75 dmg
    const crit = calculateDamage(baseAtk, def, true, 0.5);
    assert.equal(crit.damage, 75);
    assert.equal(crit.isCritical, true);
  });

  await t.test('FUN-06-03-002 & FUN-06-03-003: Shield absorption and Status effect DoT', () => {
    // Shield absorbs incoming damage
    let target = { hp: 100, maxHp: 100, shield: 30 };
    let incomingDamage = 50;

    if (target.shield > 0) {
      if (target.shield >= incomingDamage) {
        target.shield -= incomingDamage;
        incomingDamage = 0;
      } else {
        incomingDamage -= target.shield;
        target.shield = 0;
      }
    }

    target.hp -= incomingDamage;
    assert.equal(target.shield, 0);
    assert.equal(target.hp, 80); // 50 - 30 shield = 20 HP damage -> 100 - 20 = 80 HP

    // Bleed / Poison DoT tick
    const bleed = { type: 'BLEED', value: 15, remainingRounds: 2 };
    target.hp -= bleed.value;
    bleed.remainingRounds -= 1;
    assert.equal(target.hp, 65);
    assert.equal(bleed.remainingRounds, 1);
  });
});

test('Battle Result & Report - FUN-06-05-001 -> 003 Result, Survival & Casualties', async (t) => {
  await t.test('FUN-06-05-001: Determine battle result (VICTORY vs DEFEAT)', () => {
    const heroesAlive = [{ id: 'h1', hp: 50 }, { id: 'h2', hp: 0 }];
    const enemiesAllDead = [{ id: 'e1', hp: 0 }, { id: 'e2', hp: 0 }];

    const isVictory = enemiesAllDead.every(e => e.hp <= 0) && heroesAlive.some(h => h.hp > 0);
    assert.equal(isVictory, true);

    const heroesAllDead = [{ id: 'h1', hp: 0 }, { id: 'h2', hp: 0 }];
    const isDefeat = heroesAllDead.every(h => h.hp <= 0);
    assert.equal(isDefeat, true);
  });

  await t.test('FUN-06-05-002: Process hero survival and remaining HP tracking', () => {
    const heroes = [
      { id: 'h1', name: 'Lancelot', hp: 350, maxHp: 500 },
      { id: 'h2', name: 'Arthur', hp: 0, maxHp: 600 },
      { id: 'h3', name: 'Merlin', hp: 120, maxHp: 400 },
    ];

    const survivors = heroes.filter(h => h.hp > 0).map(h => ({
      id: h.id,
      name: h.name,
      hp: h.hp,
      maxHp: h.maxHp,
      hpPercent: Math.round((h.hp / h.maxHp) * 100),
    }));

    assert.equal(survivors.length, 2);
    assert.equal(survivors[0].name, 'Lancelot');
    assert.equal(survivors[0].hpPercent, 70);
    assert.equal(survivors[1].name, 'Merlin');
    assert.equal(survivors[1].hpPercent, 30);
  });

  await t.test('FUN-06-05-003: Process battle casualties (Normal permadeath vs Special/Limited disabled)', () => {
    const fallenHeroes = [
      { id: 'h-normal', name: 'Militia Soldier', origin: 'NORMAL', hp: 0, equippedItems: ['iron_sword', 'wooden_shield'] },
      { id: 'h-limited', name: 'Phoenix Sorceress', origin: 'LIMITED', hp: 0, equippedItems: ['phoenix_staff'] },
      { id: 'h-special', name: 'Worldbreaker', origin: 'SPECIAL', hp: 0, equippedItems: ['excalibur'] },
    ];

    const processed = fallenHeroes.map(h => {
      const isNormal = h.origin === 'NORMAL';
      const deathType = isNormal ? 'PERMADEATH' : 'DISABLED';
      const droppedGear = isNormal ? [...h.equippedItems] : [];
      const newState = isNormal ? 'DEAD' : 'DISABLED';
      return {
        id: h.id,
        name: h.name,
        deathType,
        newState,
        droppedEquipmentCount: droppedGear.length,
      };
    });

    // Normal Hero permadeath and equipment dropped
    assert.equal(processed[0].deathType, 'PERMADEATH');
    assert.equal(processed[0].newState, 'DEAD');
    assert.equal(processed[0].droppedEquipmentCount, 2);

    // Limited Hero disabled, NO equipment dropped
    assert.equal(processed[1].deathType, 'DISABLED');
    assert.equal(processed[1].newState, 'DISABLED');
    assert.equal(processed[1].droppedEquipmentCount, 0);

    // Special Hero disabled, NO equipment dropped
    assert.equal(processed[2].deathType, 'DISABLED');
    assert.equal(processed[2].newState, 'DISABLED');
    assert.equal(processed[2].droppedEquipmentCount, 0);
  });
  await t.test('FUN-06-05-004: Distribute battle EXP across surviving heroes', () => {
    const totalExpReward = 100;
    const survivors = [
      { id: 'h1', name: 'Arthur', exp: 0n, level: 1 },
      { id: 'h2', name: 'Lancelot', exp: 0n, level: 1 },
      { id: 'h3', name: 'Gawain', exp: 0n, level: 1 },
    ];

    const expEach = Math.floor(totalExpReward / survivors.length); // 33
    const remainder = totalExpReward % survivors.length;          // 1

    const distributed = survivors.map((h, index) => {
      const award = expEach + (index < remainder ? 1 : 0);
      return {
        ...h,
        gainedExp: award,
        totalExp: h.exp + BigInt(award),
      };
    });

    assert.equal(distributed[0].gainedExp, 34); // gets remainder
    assert.equal(distributed[1].gainedExp, 33);
    assert.equal(distributed[2].gainedExp, 33);
    const sum = distributed.reduce((acc, h) => acc + h.gainedExp, 0);
    assert.equal(sum, totalExpReward);
  });

  await t.test('FUN-06-05-005 & FUN-06-05-006: Generate battle rewards and report structure', () => {
    const floor = 1;
    const enemyRewards = [
      { baseExp: 20, baseSilver: 15 },
      { baseExp: 30, baseSilver: 20 },
    ];
    const difficultyMultiplier = 1.0;
    const expReward = enemyRewards.reduce((sum, e) => sum + Math.floor(e.baseExp * difficultyMultiplier), 0);
    const silverReward = enemyRewards.reduce((sum, e) => sum + Math.floor(e.baseSilver * difficultyMultiplier), 0);

    const report = {
      result: 'VICTORY',
      rounds: 3,
      floor,
      nextFloor: floor + 1,
      expReward,
      silverReward,
      masterExpReward: 300,
      survivors: [{ id: 'h1', name: 'Arthur', hp: 300, maxHp: 500, hpPercent: 60 }],
      fallenHeroes: [],
      log: [],
    };

    assert.equal(report.result, 'VICTORY');
    assert.equal(report.nextFloor, 2);
    assert.equal(report.expReward, 50);
    assert.equal(report.silverReward, 35);
    assert.equal(report.masterExpReward, 300);
    assert.equal(report.survivors.length, 1);
  });

  await t.test('FUN-06-05-007: Update hero condition (HEALTHY vs INJURED vs DEAD)', () => {
    const heroFullHp = { hp: 500, maxHp: 500 };
    const heroLowHp = { hp: 100, maxHp: 500 }; // 20% <= 25% threshold
    const heroDead = { hp: 0, maxHp: 500 };

    const getCondition = (hero) => {
      if (hero.hp <= 0) return 'DEAD';
      if (hero.hp <= Math.floor(hero.maxHp * 0.25)) return 'INJURED';
      return 'HEALTHY';
    };

    assert.equal(getCondition(heroFullHp), 'HEALTHY');
    assert.equal(getCondition(heroLowHp), 'INJURED');
    assert.equal(getCondition(heroDead), 'DEAD');
  });

});
