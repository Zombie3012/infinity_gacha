import { test } from 'node:test';
import assert from 'node:assert/strict';
import { resolveBattleV2 } from '../dist/modules/combat/combat-v2.engine.js';
import { mulberry32 } from '@infiniti-gacha/shared';

function stats(overrides = {}) {
  return {
    maxHp: 1_000, maxMp: 100, atk: 100, matk: 100, def: 50, mdef: 50,
    hpRegen: 0, mpRegen: 0, critRate: 5, critDamage: 150, accuracy: 0, evasion: 0,
    blockRate: 0, blockEffect: 0, critResistance: 0, critDamageReduction: 0,
    damageReduction: 0, tenacity: 0, armorPen: 0, magicPen: 0, damageBonus: 0, lifesteal: 0,
    ...overrides,
  };
}

const EMPTY_EFFECTS = {
  critRate: 0, evasion: 0, accuracy: 0, atkPercent: 0, matkPercent: 0,
  mpRegenPct: 0, tenacity: 0, lowHp: null, revive: null,
};

function unit(id, side, agi, overrides = {}) {
  return {
    id, name: id, side, slotIndex: 0, agi,
    stats: stats(overrides.stats ?? {}),
    damageType: overrides.damageType ?? 'PHYSICAL',
    affinity: overrides.affinity ?? null,
    skills: overrides.skills ?? [],
    imprintEffects: overrides.imprintEffects,
  };
}

test('Combat v2 engine - turn model', async (t) => {
  await t.test('units act once per round in AGI order', () => {
    const report = resolveBattleV2(
      [unit('hero', 'HERO', 100, { stats: { atk: 1, maxHp: 10_000 } })],
      [unit('enemy', 'ENEMY', 50, { stats: { atk: 1, maxHp: 10_000 } })],
      { maxRounds: 1, random: () => 0.5 },
    );
    assert.equal(report.log.length, 2);
    assert.equal(report.log[0].actorId, 'hero');
    assert.equal(report.log[1].actorId, 'enemy');
    assert.equal(report.rounds, 1);
  });

  await t.test('a stronger AGI unit still acts only once per round', () => {
    const report = resolveBattleV2(
      [unit('fast', 'HERO', 500, { stats: { atk: 1, maxHp: 50_000 } })],
      [unit('slow', 'ENEMY', 10, { stats: { atk: 1, maxHp: 50_000 } })],
      { maxRounds: 3, random: () => 0.5 },
    );
    const roundOne = report.log.filter(entry => entry.round === 1);
    assert.equal(roundOne.length, 2);
    assert.equal(roundOne[0].actorId, 'fast');
  });
});

test('Combat v2 engine - damage and status', async (t) => {
  await t.test('crit and block are reported by the shared pipeline', () => {
    const report = resolveBattleV2(
      [unit('hero', 'HERO', 100, { stats: { atk: 200, critRate: 100 } })],
      [unit('enemy', 'ENEMY', 10, { stats: { maxHp: 10_000, blockRate: 100, blockEffect: 50 } })],
      { maxRounds: 1, random: () => 0 },
    );
    const attack = report.log.find(entry => entry.actorId === 'hero');
    assert.equal(attack.crit, true);
    assert.equal(attack.blocked, true);
    assert.ok(attack.damage > 0);
  });

  await t.test('a lethal hit ends the battle', () => {
    const report = resolveBattleV2(
      [unit('hero', 'HERO', 100, { stats: { atk: 9_999 } })],
      [unit('enemy', 'ENEMY', 10, { stats: { maxHp: 100 } })],
      { random: () => 0.5 },
    );
    assert.equal(report.winner, 'HERO');
    assert.equal(report.log.filter(entry => entry.actorId === 'enemy').length, 0);
  });

  await t.test('max rounds with both sides alive is a draw', () => {
    const report = resolveBattleV2(
      [unit('hero', 'HERO', 100, { stats: { atk: 0 } })],
      [unit('enemy', 'ENEMY', 10, { stats: { atk: 0 } })],
      { maxRounds: 1, random: () => 0.5 },
    );
    assert.equal(report.winner, 'DRAW');
  });
});

test('Combat v2 engine - MP and skills', async (t) => {
  const skill = {
    code: 'FIRE_BOLT', multiplier: 2, cooldownRounds: 2,
    effectType: 'DAMAGE_SINGLE', effectValue: 0, mpCost: 20, element: 'FIRE',
  };

  await t.test('a skill spends MP and then goes on cooldown', () => {
    const report = resolveBattleV2(
      [unit('mage', 'HERO', 100, { damageType: 'MAGICAL', skills: [skill], stats: { maxMp: 100, matk: 1, atk: 1 } })],
      [unit('enemy', 'ENEMY', 10, { stats: { maxHp: 100_000, atk: 0 } })],
      { maxRounds: 2, random: () => 0.5 },
    );
    const actions = report.log.filter(entry => entry.actorId === 'mage');
    assert.equal(actions[0].action, 'FIRE_BOLT');
    assert.equal(actions[0].actorMp, 80);
    assert.equal(actions[1].action, 'BASIC');
    assert.equal(actions[1].actorMp, 85); // basic restores 5%
  });

  await t.test('element affinity raises Mage damage', () => {
    const high = resolveBattleV2(
      [unit('mage', 'HERO', 100, {
        damageType: 'MAGICAL', skills: [skill],
        affinity: { FIRE: 90, WATER: 0, WIND: 0, EARTH: 0, LIGHT: 0, DARK: 0, LIGHTNING: 0 },
        stats: { maxMp: 1_000, matk: 1_000 },
      })],
      [unit('enemy', 'ENEMY', 10, { stats: { maxHp: 500_000, atk: 0 } })],
      { maxRounds: 3, random: mulberry32(7) },
    );
    const low = resolveBattleV2(
      [unit('mage', 'HERO', 100, {
        damageType: 'MAGICAL', skills: [skill],
        affinity: { FIRE: 10, WATER: 0, WIND: 0, EARTH: 0, LIGHT: 0, DARK: 0, LIGHTNING: 0 },
        stats: { maxMp: 1_000, matk: 1_000 },
      })],
      [unit('enemy', 'ENEMY', 10, { stats: { maxHp: 500_000, atk: 0 } })],
      { maxRounds: 3, random: mulberry32(7) },
    );
    assert.ok(high.totalDamage > low.totalDamage);
  });

  await t.test('healing skills restore the lowest-HP ally', () => {
    const heal = {
      code: 'HEAL', multiplier: 0, cooldownRounds: 3,
      effectType: 'HEAL_LOWEST_ALLY', effectValue: 0.5, mpCost: 10,
    };
    const report = resolveBattleV2(
      [
        unit('healer', 'HERO', 200, { damageType: 'MAGICAL', skills: [heal], stats: { matk: 1_000 } }),
        unit('ally', 'HERO', 100, { stats: { maxHp: 1_000 } }),
      ],
      [unit('enemy', 'ENEMY', 150, { stats: { atk: 300, maxHp: 100_000 } })],
      { maxRounds: 2, random: () => 0.5 },
    );
    const healEntry = report.log.find(entry => entry.action === 'HEAL');
    assert.ok(healEntry);
    assert.ok(healEntry.heal > 0);
    const ally = report.units.find(row => row.id === 'ally');
    assert.ok(ally.hp > 0);
  });
});

test('Combat v2 engine - imprint abilities', async (t) => {
  await t.test('PHOENIX_REVIVE restores the Hero once per battle', () => {
    const report = resolveBattleV2(
      [unit('hero', 'HERO', 10, {
        stats: { maxHp: 1_000, atk: 1, def: 0 },
        imprintEffects: { ...EMPTY_EFFECTS, revive: { hpPct: 30, times: 1 } },
      })],
      [unit('enemy', 'ENEMY', 100, { stats: { atk: 5_000, maxHp: 1_000_000 } })],
      { maxRounds: 4, random: () => 0.5 },
    );
    const revives = report.log.filter(entry => entry.action === 'REVIVE');
    assert.equal(revives.length, 1);
    assert.equal(revives[0].actorId, 'hero');
    assert.equal(revives[0].heal, 300); // 30% of 1,000 MaxHP
    // The revive is consumed, so the Hero stays down after the next lethal hit.
    assert.equal(report.winner, 'ENEMY');
    assert.equal(report.units.find(row => row.id === 'hero').alive, false);
  });

  await t.test('LOW_HP_EMPOWER only boosts damage below the HP threshold', () => {
    const fight = (effects) => resolveBattleV2(
      [unit('hero', 'HERO', 100, {
        stats: { maxHp: 1_000, atk: 200, def: 0, critRate: 0 },
        imprintEffects: effects,
      })],
      [unit('enemy', 'ENEMY', 200, { stats: { atk: 100, maxHp: 1_000_000, def: 0 } })],
      { maxRounds: 2, random: () => 0.5 },
    );
    const control = fight({ ...EMPTY_EFFECTS });
    const empowered = fight({
      ...EMPTY_EFFECTS,
      lowHp: { hpThresholdPct: 95, damageBonus: 50, tenacity: 0 },
    });
    const secondHit = report => report.log.filter(entry => entry.actorId === 'hero')[1].damage;
    assert.ok(secondHit(empowered) > secondHit(control));
    assert.ok(secondHit(empowered) >= Math.floor(secondHit(control) * 1.4));
  });

  await t.test('CRIT_EVASION raises the crit rate used by the pipeline', () => {
    const report = resolveBattleV2(
      [unit('hero', 'HERO', 100, {
        stats: { atk: 200, critRate: 0 },
        imprintEffects: { ...EMPTY_EFFECTS, critRate: 100 },
      })],
      [unit('enemy', 'ENEMY', 10, { stats: { maxHp: 100_000 } })],
      { maxRounds: 1, random: () => 0.5 },
    );
    assert.equal(report.log[0].crit, true);
  });

  await t.test('ARCANE_EMPOWER regenerates MP at the end of each round', () => {
    const skill = {
      code: 'FIRE_BOLT', multiplier: 1, cooldownRounds: 5,
      effectType: 'DAMAGE_SINGLE', effectValue: 0, mpCost: 50,
    };
    const report = resolveBattleV2(
      [unit('mage', 'HERO', 100, {
        damageType: 'MAGICAL', skills: [skill], stats: { maxMp: 100, atk: 1, matk: 1 },
        imprintEffects: { ...EMPTY_EFFECTS, mpRegenPct: 10 },
      })],
      [unit('enemy', 'ENEMY', 10, { stats: { maxHp: 1_000_000, atk: 0 } })],
      { maxRounds: 2, random: () => 0.5 },
    );
    // Round 1: 100 - 50 skill + 10 regen = 60. Round 2: basic +5% + 10 regen = 75.
    assert.equal(report.units.find(row => row.id === 'mage').mp, 75);
  });
});

