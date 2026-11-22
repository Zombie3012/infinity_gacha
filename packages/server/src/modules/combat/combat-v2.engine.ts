/**
 * Combat v2 engine (pure).
 *
 * Turn model (owner decision): one action per unit per round, order by AGI
 * descending, ties resolved by hero side then slot. Speed is not a stat.
 *
 * Action order inside a round: skills first (if ready and enough MP), otherwise
 * a basic attack that restores 5% Max MP. Damage goes through the shared
 * hit -> mitigation -> affinity -> damage bonus -> crit -> block -> DR pipeline.
 * Skills cost 20% Max MP (minimum 10) and use their configured cooldown.
 *
 * Imprint abilities are folded in at the profile level: crit/evasion/accuracy,
 * ATK/MATK %, MP regen per round, a low-HP damage bonus and one revive.
 */

import {
  affinityMultiplier, applyShield, CAPS, clamp, resolveAttack,
  type DamageElement, type DerivedStats, type ElementAffinity, type ImprintCombatEffects,
  type PveTargetPriority,
} from '@infiniti-gacha/shared';

import { MANA_RESTORE_RATIO, STRENGTH_ATK_MULTIPLIER, type ConsumableConfig } from '../base/alchemy-rules.js';

export type CombatSide = 'HERO' | 'ENEMY';
export type CombatV2Winner = CombatSide | 'DRAW';

export type CombatV2SkillEffect = 'DAMAGE_SINGLE' | 'HEAL_LOWEST_ALLY';

export interface CombatV2Skill {
  code: string;
  multiplier: number;
  cooldownRounds: number;
  effectType: CombatV2SkillEffect;
  effectValue: number;
  mpCost?: number;
  element?: DamageElement;
}

export interface CombatV2UnitInput {
  id: string;
  name: string;
  side: CombatSide;
  slotIndex: number;
  formationSlot?: number;
  targetPriority?: PveTargetPriority;
  skillOrder?: string[];
  consumables?: ConsumableConfig;
  strengthReady?: boolean;
  initialHp?: number;
  initialMp?: number;
  agi: number;
  stats: DerivedStats;
  damageType: 'PHYSICAL' | 'MAGICAL';
  affinity?: ElementAffinity | null;
  skills?: CombatV2Skill[];
  /** Aggregated imprint abilities; omitted when the Hero owns no ability imprint. */
  imprintEffects?: ImprintCombatEffects;
}

export interface CombatV2UnitState extends CombatV2UnitInput {
  hp: number;
  mp: number;
  shield: number;
  cooldowns: Record<string, number>;
  alive: boolean;
  /** Revives left in this battle, seeded from the imprint effect. */
  revivesLeft: number;
}

export interface CombatV2LogEntry {
  round: number;
  actorId: string;
  actorName: string;
  targetId: string | null;
  action: string;
  damage: number;
  heal: number;
  crit: boolean;
  blocked: boolean;
  targetHp: number;
  actorMp: number;
  actorHp?: number;
  targetName?: string;
  actionType?: 'BASIC' | 'SKILL' | 'HEAL' | 'REVIVE' | 'ITEM';
  hit?: boolean;
}

export interface CombatV2Report {
  pending?: { key: string; actorId: string; round: number; skills: { code: string; mpCost: number }[] };
  consumables?: Record<string, ConsumableConfig>;
  ambush?: boolean;
  winner: CombatV2Winner;
  rounds: number;
  log: CombatV2LogEntry[];
  units: {
    id: string; name: string; side: CombatSide; hp: number; maxHp: number; mp: number; maxMp: number; alive: boolean;
    slotIndex?: number;
    effects?: string[];
  }[];
  initialUnits?: CombatV2Report['units'];
  totalDamage: number;
}

export interface CombatChoice { action?: 'BASIC' | 'SKILL'; skillCode?: string; targetId?: string; items?: string[] }
export interface CombatV2Options {
  pauseManual?: boolean;
  choices?: Record<string, CombatChoice>;
  ambush?: boolean;
  maxRounds?: number;
  random?: () => number;
  skillMpCostRatio?: number;
  basicMpGainRatio?: number;
  timeoutIsDraw?: boolean;
}

const DEFAULT_MAX_ROUNDS = 30;
const DEFAULT_SKILL_MP_RATIO = 0.2;
const DEFAULT_BASIC_MP_RATIO = 0.05;

function initialize(input: CombatV2UnitInput): CombatV2UnitState {
  return {
    ...input,
    stats: { ...input.stats },
    consumables: input.consumables ? structuredClone(input.consumables) : undefined,
    hp: Math.max(0, Math.min(input.stats.maxHp, input.initialHp ?? input.stats.maxHp)),
    mp: Math.max(0, Math.min(input.stats.maxMp, input.initialMp ?? input.stats.maxMp)),
    shield: 0,
    cooldowns: {},
    alive: (input.initialHp ?? input.stats.maxHp) > 0,
    revivesLeft: input.imprintEffects?.revive?.times ?? 0,
  };
}

function turnOrder(units: CombatV2UnitState[]): CombatV2UnitState[] {
  return [...units]
    .filter(unit => unit.alive)
    .sort((a, b) => b.agi - a.agi
      || (a.side === b.side ? 0 : a.side === 'HERO' ? -1 : 1)
      || a.slotIndex - b.slotIndex
      || a.id.localeCompare(b.id));
}

function pickTarget(actor: CombatV2UnitState, units: CombatV2UnitState[]): CombatV2UnitState | null {
  const enemies = units.filter(unit => unit.alive && unit.side !== actor.side);
  if (enemies.length === 0) return null;
  const cell = (unit: CombatV2UnitState) => unit.formationSlot ?? unit.slotIndex;
  const score = (unit: CombatV2UnitState) => actor.targetPriority === 'FRONTLINE'
    ? Math.floor(cell(unit) / 3)
    : actor.targetPriority === 'HIGHEST_ATK' ? -Math.max(unit.stats.atk, unit.stats.matk)
      : unit.hp / unit.stats.maxHp;
  // Preserve the legacy weakest-HP default when no pre-battle policy is supplied.
  return [...enemies].sort((a, b) => score(a) - score(b) || cell(a) - cell(b) || a.id.localeCompare(b.id))[0];
}

function pickHealTarget(actor: CombatV2UnitState, units: CombatV2UnitState[]): CombatV2UnitState | null {
  const allies = units.filter(unit => unit.alive && unit.side === actor.side && unit.hp < unit.stats.maxHp);
  if (allies.length === 0) return null;
  return [...allies].sort((a, b) => (a.hp / a.stats.maxHp) - (b.hp / b.stats.maxHp))[0];
}

function attackProfile(actor: CombatV2UnitState, multiplier: number) {
  const magical = actor.damageType === 'MAGICAL';
  const effects = actor.imprintEffects;
  // LOW_HP_EMPOWER only counts while the attacker is below the HP threshold.
  const hpPct = actor.stats.maxHp > 0 ? (actor.hp / actor.stats.maxHp) * 100 : 0;
  const lowHp = effects?.lowHp && hpPct <= effects.lowHp.hpThresholdPct ? effects.lowHp : null;
  const attackScale = 1 + (magical ? (effects?.matkPercent ?? 0) : (effects?.atkPercent ?? 0)) / 100;
  return {
    attack: (magical ? actor.stats.matk : actor.stats.atk) * attackScale,
    damageType: magical ? 'MAGICAL' as const : 'PHYSICAL' as const,
    skillMultiplier: multiplier,
    bonusDamage: 0,
    damageBonus: actor.stats.damageBonus + (lowHp?.damageBonus ?? 0),
    critRate: clamp(actor.stats.critRate + (effects?.critRate ?? 0), 0, CAPS.critRate),
    critDamage: actor.stats.critDamage,
    accuracy: actor.stats.accuracy + (effects?.accuracy ?? 0),
    penetrationPercent: magical ? actor.stats.magicPen : actor.stats.armorPen,
    penetrationFlat: 0,
  };
}

function defenceProfile(target: CombatV2UnitState, damageType: CombatV2UnitInput['damageType']) {
  const magical = damageType === 'MAGICAL';
  return {
    defense: magical ? target.stats.mdef : target.stats.def,
    evasion: clamp(target.stats.evasion + (target.imprintEffects?.evasion ?? 0), 0, CAPS.evasion),
    blockRate: target.stats.blockRate,
    blockEffect: target.stats.blockEffect,
    critResistance: target.stats.critResistance,
    critDamageReduction: target.stats.critDamageReduction,
    damageReduction: target.stats.damageReduction,
  };
}

function chooseSkill(actor: CombatV2UnitState, skillMpRatio: number, units: CombatV2UnitState[]): { skill: CombatV2Skill | null; mpCost: number } {
  const rank = (code: string) => { const index = actor.skillOrder?.indexOf(code) ?? -1; return index < 0 ? Infinity : index; };
  const skills = actor.skillOrder?.length ? [...(actor.skills ?? [])].sort((a, b) => rank(a.code) - rank(b.code)) : actor.skills ?? [];
  for (const skill of skills) {
    if (skill.effectType === 'HEAL_LOWEST_ALLY' && !pickHealTarget(actor, units)) continue;
    const cooldown = actor.cooldowns[skill.code] ?? 0;
    const cost = skill.mpCost ?? Math.max(10, Math.round(actor.stats.maxMp * skillMpRatio));
    if (cooldown <= 0 && actor.mp >= cost) return { skill, mpCost: cost };
  }
  return { skill: null, mpCost: 0 };
}

/** Resolves a full Combat v2 battle without touching the database. */
export function resolveBattleV2(
  heroes: CombatV2UnitInput[],
  enemies: CombatV2UnitInput[],
  options: CombatV2Options = {},
): CombatV2Report {
  const random = options.random ?? Math.random;
  const maxRounds = Math.max(1, options.maxRounds ?? DEFAULT_MAX_ROUNDS);
  const skillMpRatio = options.skillMpCostRatio ?? DEFAULT_SKILL_MP_RATIO;
  const basicMpGain = options.basicMpGainRatio ?? DEFAULT_BASIC_MP_RATIO;

  const units = [...heroes, ...enemies].map(initialize);
  const unitSnapshot = (unit: CombatV2UnitState) => ({
    id: unit.id, name: unit.name, side: unit.side, hp: unit.hp, maxHp: unit.stats.maxHp,
    mp: unit.mp, maxMp: unit.stats.maxMp, alive: unit.alive, slotIndex: unit.formationSlot ?? unit.slotIndex,
    effects: unit.strengthReady ? ['STRENGTH_POTION'] : [],
  });
  for (const unit of units) if (unit.strengthReady) unit.stats.atk *= STRENGTH_ATK_MULTIPLIER;
  const initialUnits = units.map(unitSnapshot);
  const log: CombatV2LogEntry[] = [];
  let rounds = 0;
  let totalDamage = 0;
  let pending: CombatV2Report['pending'];

  roundsLoop: for (let round = options.ambush ? 0 : 1; round <= maxRounds; round += 1) {
    rounds = round;
    const order = turnOrder(units).filter(unit => round !== 0 || unit.side === 'ENEMY');
    if (order.length === 0) break;

    for (const actor of order) {
      if (!actor.alive) continue;
      if (units.every(unit => unit.side === actor.side || !unit.alive)) break;

      const key = `${round}:${actor.id}`;
      const choice = options.choices?.[key];
      const items = choice ? (choice.items ?? []) : (!options.pauseManual && actor.consumables ? [
        ...(actor.consumables.autoStrength && !actor.strengthReady ? ['STRENGTH_POTION'] : []),
        ...(actor.stats.maxMp > 0 && actor.mp / actor.stats.maxMp * 100 < actor.consumables.autoManaBelow ? ['MANA_POTION'] : []),
      ].filter(code => actor.consumables!.slots.some(s => s?.itemId === code && s.quantity > 0)) : []);
      if (items.length > 2 || new Set(items).size !== items.length) throw new Error('ERR_COMBAT_ITEM_LIMIT');
      for (const code of items) {
        const slot = actor.consumables?.slots.find(s => s?.itemId === code && s.quantity > 0);
        if (!slot || !['MANA_POTION', 'STRENGTH_POTION'].includes(code) || !actor.alive) throw new Error('ERR_COMBAT_ITEM_INVALID');
        if (code === 'MANA_POTION') {
          if (actor.stats.maxMp <= 0 || actor.mp >= actor.stats.maxMp) throw new Error('ERR_COMBAT_MP_FULL');
          actor.mp = Math.min(actor.stats.maxMp, actor.mp + Math.ceil(actor.stats.maxMp * MANA_RESTORE_RATIO));
        } else {
          if (actor.strengthReady) throw new Error('ERR_COMBAT_BUFF_ACTIVE');
          actor.strengthReady = true; actor.stats.atk *= STRENGTH_ATK_MULTIPLIER;
        }
        slot.quantity--;
        log.push({ round, actorId: actor.id, actorName: actor.name, targetId: actor.id, targetName: actor.name,
          action: code, actionType: 'ITEM', damage: 0, heal: 0, crit: false, blocked: false, hit: true,
          actorHp: actor.hp, targetHp: actor.hp, actorMp: actor.mp });
      }
      if (options.pauseManual && actor.side === 'HERO' && !choice?.action) {
        pending = { key, actorId: actor.id, round, skills: (actor.skills ?? []).map(s=>({code:s.code,mpCost:s.mpCost ?? Math.max(10,Math.round(actor.stats.maxMp*skillMpRatio))})).filter(s=>(actor.cooldowns[s.code] ?? 0)<=0 && actor.mp>=s.mpCost) }; break roundsLoop;
      }
      let { skill, mpCost } = chooseSkill(actor, skillMpRatio, units);
      if (choice?.action === 'BASIC') { skill = null; mpCost = 0; }
      if (choice?.action === 'SKILL') {
        skill = actor.skills?.find(s => s.code === choice.skillCode) ?? null;
        mpCost = skill?.mpCost ?? Math.max(10, Math.round(actor.stats.maxMp * skillMpRatio));
        if (!skill || (actor.cooldowns[skill.code] ?? 0) > 0 || actor.mp < mpCost) throw new Error('ERR_COMBAT_SKILL_UNAVAILABLE');
      }
      const chosenTarget = choice?.targetId ? units.find(u => u.id === choice.targetId && u.alive) : undefined;
      if (choice?.targetId && !chosenTarget) throw new Error('ERR_COMBAT_TARGET');

      if (skill?.effectType === 'HEAL_LOWEST_ALLY') {
        const target = chosenTarget ?? pickHealTarget(actor, units);
        if (target && target.side !== actor.side) throw new Error('ERR_COMBAT_TARGET');
        if (target) {
          const heal = Math.max(1, Math.round(skill.effectValue * actor.stats.matk));
          target.hp = Math.min(target.stats.maxHp, target.hp + heal);
          actor.mp = Math.max(0, actor.mp - mpCost);
          actor.cooldowns[skill.code] = Math.max(1, skill.cooldownRounds);
          log.push({
            round, actorId: actor.id, actorName: actor.name, targetId: target.id, action: skill.code,
            damage: 0, heal, crit: false, blocked: false, targetHp: target.hp, actorMp: actor.mp,
            actorHp: actor.hp, targetName: target.name, actionType: 'HEAL', hit: true,
          });
          continue;
        }
        // Nobody needs healing: fall back to a basic attack.
        skill = null;
        mpCost = 0;
      }

      const target = chosenTarget ?? pickTarget(actor, units);
      if (target && target.side === actor.side) throw new Error('ERR_COMBAT_TARGET');
      if (!target) break;

      const multiplier = skill ? skill.multiplier : 1;
      const affinity = actor.damageType === 'MAGICAL' && skill?.element && actor.affinity
        ? affinityMultiplier(actor.affinity[skill.element])
        : 1;
      const result = resolveAttack(attackProfile(actor, multiplier), defenceProfile(target, actor.damageType), {
        elementMultiplier: affinity,
        random,
      });

      // Executing an action consumes its resources even when the target evades.
      if (skill) {
        actor.mp = Math.max(0, actor.mp - mpCost);
        actor.cooldowns[skill.code] = Math.max(1, skill.cooldownRounds);
      } else {
        actor.mp = Math.min(actor.stats.maxMp, actor.mp + Math.round(actor.stats.maxMp * basicMpGain));
      }

      if (result.hit && result.damage > 0) {
        let reviveEntry: CombatV2LogEntry | null = null;
        const shield = applyShield(result.damage, target.shield);
        target.shield = shield.shieldRemaining;
        target.hp = Math.max(0, target.hp - shield.toHp);
        totalDamage += shield.toHp;

        if (actor.stats.lifesteal > 0 && shield.toHp > 0) {
          const heal = Math.floor(shield.toHp * clamp(actor.stats.lifesteal, 0, 100) / 100);
          actor.hp = Math.min(actor.stats.maxHp, actor.hp + heal);
        }
        if (target.hp <= 0) {
          target.alive = false;
          // PHOENIX_REVIVE: one comeback per battle (times may be tuned above 1).
          const revive = target.imprintEffects?.revive;
          if (revive && target.revivesLeft > 0) {
            target.revivesLeft -= 1;
            target.alive = true;
            target.hp = Math.max(1, Math.round(target.stats.maxHp * clamp(revive.hpPct, 1, 100) / 100));
            reviveEntry = {
              round, actorId: target.id, actorName: target.name, targetId: target.id, action: 'REVIVE',
              damage: 0, heal: target.hp, crit: false, blocked: false, targetHp: target.hp, actorMp: target.mp,
              actorHp: target.hp, targetName: target.name, actionType: 'REVIVE', hit: true,
            };
          }
        }

        log.push({
          round, actorId: actor.id, actorName: actor.name, targetId: target.id,
          action: skill?.code ?? 'BASIC', damage: shield.toHp, heal: 0,
          crit: result.crit, blocked: result.blocked, targetHp: reviveEntry ? 0 : target.hp, actorMp: actor.mp,
          actorHp: actor.hp, targetName: target.name, actionType: skill ? 'SKILL' : 'BASIC', hit: true,
        });
        if (reviveEntry) log.push(reviveEntry);
      } else {
        log.push({
          round, actorId: actor.id, actorName: actor.name, targetId: target.id,
          action: skill?.code ?? 'BASIC', damage: 0, heal: 0,
          crit: result.crit, blocked: result.blocked, targetHp: target.hp, actorMp: actor.mp,
          actorHp: actor.hp, targetName: target.name, actionType: skill ? 'SKILL' : 'BASIC', hit: result.hit,
        });
      }
    }

    // The ambush opening is an extra action phase, not a cooldown/regen round.
    for (const unit of round === 0 ? [] : units) {
      if (unit.alive) {
        const mpRegenPct = unit.imprintEffects?.mpRegenPct ?? 0;
        if (mpRegenPct > 0 && unit.stats.maxMp > 0) {
          unit.mp = Math.min(unit.stats.maxMp, unit.mp + Math.round(unit.stats.maxMp * mpRegenPct / 100));
        }
      }
      for (const code of Object.keys(unit.cooldowns)) {
        unit.cooldowns[code] = Math.max(0, unit.cooldowns[code] - 1);
      }
    }

    const heroesAlive = units.some(unit => unit.side === 'HERO' && unit.alive);
    const enemiesAlive = units.some(unit => unit.side === 'ENEMY' && unit.alive);
    if (!heroesAlive || !enemiesAlive) break;
  }

  const heroesAlive = units.some(unit => unit.side === 'HERO' && unit.alive);
  const enemiesAlive = units.some(unit => unit.side === 'ENEMY' && unit.alive);
  let winner: CombatV2Winner = 'DRAW';
  if (heroesAlive && !enemiesAlive) winner = 'HERO';
  else if (!heroesAlive && enemiesAlive) winner = 'ENEMY';
  else if (heroesAlive && enemiesAlive && !options.timeoutIsDraw) {
    const heroHp = units.filter(unit => unit.side === 'HERO').reduce((sum, unit) => sum + unit.hp / unit.stats.maxHp, 0);
    const enemyHp = units.filter(unit => unit.side === 'ENEMY').reduce((sum, unit) => sum + unit.hp / unit.stats.maxHp, 0);
    winner = heroHp === enemyHp ? 'DRAW' : heroHp > enemyHp ? 'HERO' : 'ENEMY';
  }

  return {
    ...(options.ambush ? { ambush: true } : {}),
    ...(pending ? { pending } : {}),
    consumables: Object.fromEntries(units.filter(u => u.consumables).map(u => [u.id, { ...u.consumables!, slots: u.consumables!.slots.map(s => s && s.quantity > 0 ? s : null) }])),
    winner,
    rounds,
    log,
    totalDamage,
    initialUnits,
    units: units.map(unitSnapshot),
  };
}
