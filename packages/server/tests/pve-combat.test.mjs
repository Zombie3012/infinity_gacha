import { test } from 'node:test';
import assert from 'node:assert/strict';
import { resolveBattleV2 } from '../dist/modules/combat/combat-v2.engine.js';

function unit(id, side, overrides = {}) {
  return { id, name: id, side, slotIndex: 0, agi: side === 'HERO' ? 100 : 1, damageType: 'PHYSICAL',
    ...overrides, stats: { maxHp: 10000, maxMp: 100, atk: 100, matk: 100, def: 0, mdef: 0,
      hpRegen: 0, mpRegen: 0, critRate: 0, critDamage: 150, accuracy: 0, evasion: 0,
      blockRate: 0, blockEffect: 0, critResistance: 0, critDamageReduction: 0, damageReduction: 0,
      tenacity: 0, armorPen: 0, magicPen: 0, damageBonus: 0, lifesteal: 0, ...overrides.stats } };
}
const options = { maxRounds: 1, random: () => 0.5, timeoutIsDraw: true };
const damageSkill = code => ({ code, multiplier: 1, cooldownRounds: 3, effectType: 'DAMAGE_SINGLE', effectValue: 1 });

test('ambush opens with exactly one AGI-ordered action per enemy, then normal turns', () => {
  const heroes = [unit('hero', 'HERO', { agi: 1000 })];
  const enemies = [unit('slow', 'ENEMY', { agi: 5 }), unit('fast', 'ENEMY', { agi: 50 })];
  const report = resolveBattleV2(heroes, enemies, { ...options, ambush: true });
  assert.equal(report.ambush, true);
  assert.deepEqual(report.log.filter(e => e.round === 0).map(e => e.actorId), ['fast', 'slow']);
  assert.equal(report.log.find(e => e.round === 1).actorId, 'hero');
  assert.equal(report.initialUnits[0].hp, heroes[0].stats.maxHp);
  assert.deepEqual(resolveBattleV2(heroes, enemies, { ...options, ambush: true }), report);
  assert.equal(resolveBattleV2(heroes, enemies, options).log[0].round, 1);
});

test('PvE pre-battle policies select frontline, weakest or strongest targets deterministically', () => {
  const enemies = [unit('back-weak', 'ENEMY', { formationSlot: 8, initialHp: 100 }),
    unit('front', 'ENEMY', { formationSlot: 2 }), unit('strong', 'ENEMY', { formationSlot: 4, stats: { atk: 500 } })];
  for (const [priority, target] of [['FRONTLINE', 'front'], ['LOWEST_HP', 'back-weak'], ['HIGHEST_ATK', 'strong']]) {
    const report = resolveBattleV2([unit('hero', 'HERO', { targetPriority: priority })], enemies, options);
    assert.equal(report.log[0].targetId, target);
  }
  assert.equal(resolveBattleV2([unit('hero', 'HERO')], enemies, options).log[0].targetId, 'back-weak', 'legacy default remains weakest HP');
});

test('PvE per-Hero skill preference skips cooldowns and healing that has no eligible target', () => {
  const skills = [damageSkill('FIRE'), damageSkill('ICE')];
  const report = resolveBattleV2([unit('mage', 'HERO', { skills, skillOrder: ['ICE', 'FIRE'] })], [unit('foe', 'ENEMY')], { ...options, maxRounds: 2 });
  assert.deepEqual(report.log.filter(e => e.actorId === 'mage').map(e => e.action), ['ICE', 'FIRE']);
  const heal = { code: 'HEAL', multiplier: 1, cooldownRounds: 2, effectType: 'HEAL_LOWEST_ALLY', effectValue: 1 };
  const full = resolveBattleV2([unit('mage', 'HERO', { skills: [heal, damageSkill('FIRE')], skillOrder: ['HEAL', 'FIRE'] })], [unit('foe', 'ENEMY')], options);
  assert.equal(full.log[0].action, 'FIRE');
  const injured = resolveBattleV2([unit('mage', 'HERO', { skills: [heal, damageSkill('FIRE')] }),
    unit('ally', 'HERO', { agi: 90, initialHp: 100 })], [unit('foe', 'ENEMY')], options);
  assert.equal(injured.log[0].actionType, 'HEAL');
  assert.equal(injured.log[0].targetId, 'ally');
  assert.equal(injured.log[0].targetHp, 200);
});

test('Combat mitigation follows the attack type, independent of the defender class', () => {
  const attack = type => unit('attacker', 'HERO', { damageType: type });
  const armor = type => unit('armored', 'ENEMY', { damageType: type, stats: { def: 1000, mdef: 0 } });
  const magical = resolveBattleV2([attack('MAGICAL')], [armor('PHYSICAL')], options).log[0].damage;
  const physical = resolveBattleV2([attack('PHYSICAL')], [armor('PHYSICAL')], options).log[0].damage;
  assert.ok(magical > physical * 2);
  assert.equal(resolveBattleV2([attack('MAGICAL')], [armor('MAGICAL')], options).log[0].damage, magical);
});

test('Replay contract preserves initial resources and records lethal hit before revival', () => {
  const hero = unit('hero', 'HERO', { initialHp: 123, initialMp: 37, formationSlot: 8, stats: { atk: 10000 } });
  const foe = unit('foe', 'ENEMY', { stats: { maxHp: 100 }, imprintEffects: { revive: { hpPct: 30, times: 1 } } });
  const report = resolveBattleV2([hero], [foe], options);
  assert.equal(report.initialUnits[0].hp, 123);
  assert.equal(report.initialUnits[0].mp, 37);
  assert.equal(report.initialUnits[0].slotIndex, 8);
  assert.equal(report.log[0].action, 'BASIC');
  assert.equal(report.log[0].targetHp, 0);
  assert.equal(report.log[1].action, 'REVIVE');
  assert.equal(report.log[1].targetHp, 30);
});

test('Private PvE rounds expiring cannot manufacture a boss victory from remaining HP', () => {
  const hero = unit('hero', 'HERO', { stats: { atk: 10000, def: 10000 } });
  const foe = unit('foe', 'ENEMY', { stats: { atk: 1, def: 10000 } });
  assert.equal(resolveBattleV2([hero], [foe], options).winner, 'DRAW');
  assert.equal(resolveBattleV2([hero], [foe], { ...options, timeoutIsDraw: false }).winner, 'HERO');
});

test('Evaded actions still spend skill MP/cooldowns and restore basic-attack MP', () => {
  const missed = resolveBattleV2([unit('mage', 'HERO', { skills: [damageSkill('FIRE'), damageSkill('ICE')],
    skillOrder: ['ICE', 'FIRE'] })], [unit('foe', 'ENEMY')], { ...options, maxRounds: 2, random: () => 0.999 });
  const actions = missed.log.filter(entry => entry.actorId === 'mage');
  assert.deepEqual(actions.map(entry => entry.action), ['ICE', 'FIRE']);
  assert.deepEqual(actions.map(entry => entry.actorMp), [80, 60]);
  assert.ok(actions.every(entry => entry.hit === false && entry.damage === 0));
  const basic = resolveBattleV2([unit('fighter', 'HERO', { initialMp: 0 })], [unit('foe', 'ENEMY')],
    { ...options, random: () => 0.999 });
  assert.equal(basic.log[0].actorMp, 5);
});
