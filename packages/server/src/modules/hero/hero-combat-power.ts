import { and, desc, eq, inArray } from 'drizzle-orm';
import { db } from '../../database/db.js';
import {
  equipmentInstances, equipmentTemplates, heroes, heroImprints, imprintDefinitions,
} from '../../database/drizzle-schema.js';
import {
  aggregateEquipment, combatPowerV2, type DerivedStats, type EquipmentItemInput,
  type EquipmentV2Stats, type HeroClass, type StarRating,
} from '@infiniti-gacha/shared';
import { isV2Origin, originOf, progressionFor } from './hero-progression.js';

export function calculateDerivedStatsFromLegacy(hero: {
  hp: number;
  maxHp?: number;
  attack: number;
  defense: number;
  speed: number;
}): DerivedStats {
  const maxHp = Math.max(1, hero.maxHp ?? hero.hp);
  const agi = Math.max(1, hero.speed);
  return {
    maxHp,
    maxMp: 0,
    atk: Math.max(1, hero.attack),
    matk: Math.max(1, hero.attack),
    def: Math.max(0, hero.defense),
    mdef: Math.max(0, hero.defense),
    hpRegen: 0,
    mpRegen: 0,
    critRate: 5,
    critDamage: 150,
    accuracy: 0,
    evasion: Math.round(agi * 0.05 * 10) / 10,
    blockRate: 0,
    blockEffect: 0,
    critResistance: 0,
    critDamageReduction: 0,
    damageReduction: 0,
    tenacity: 0,
    armorPen: 0,
    magicPen: 0,
    damageBonus: 0,
    lifesteal: 0,
  };
}

export function computeHeroCombatPower(
  hero: typeof heroes.$inferSelect,
  gearItems?: EquipmentItemInput[],
  imprintBonusStats?: { str: number; int: number; sta: number; agi: number },
): number {
  if (isV2Origin(hero.originStats)) {
    const agg = gearItems && gearItems.length > 0
      ? aggregateEquipment(gearItems)
      : { baseStats: { str: 0, int: 0, sta: 0, agi: 0 }, derivedOffsets: {} };
    const snapshot = progressionFor({
      origin: originOf(hero.originStats),
      star: hero.rarity as StarRating,
      level: hero.level,
      classCode: hero.classCode as HeroClass,
      training: hero.trainingStats,
      awakeningRank: hero.awakeningRank,
      imprint: imprintBonusStats,
      equipmentBase: agg.baseStats,
      equipmentOffsets: agg.derivedOffsets,
      hpPct: 1,
      mpPct: 1,
    });
    return combatPowerV2(snapshot.derived);
  }
  const derived = calculateDerivedStatsFromLegacy(hero);
  return combatPowerV2(derived);
}

export async function fetchMasterHeroesWithPower(masterId: string): Promise<{ hero: typeof heroes.$inferSelect; combatPower: number }[]> {
  const heroList = await db.select().from(heroes).where(eq(heroes.masterId, masterId));
  if (heroList.length === 0) return [];
  const heroIds = heroList.map(h => h.id);

  const [gearRows, imprintRows] = await Promise.all([
    db.select({ item: equipmentInstances, template: equipmentTemplates })
      .from(equipmentInstances).innerJoin(equipmentTemplates, eq(equipmentInstances.templateCode, equipmentTemplates.code))
      .where(and(
        eq(equipmentInstances.masterId, masterId),
        eq(equipmentInstances.location, 'EQUIPPED'),
        inArray(equipmentInstances.equippedHeroId, heroIds),
      )),
    db.select({ owned: heroImprints, definition: imprintDefinitions })
      .from(heroImprints).innerJoin(imprintDefinitions, eq(imprintDefinitions.code, heroImprints.imprintCode))
      .where(inArray(heroImprints.heroId, heroIds)),
  ]);

  const itemsByHero = new Map<string, EquipmentItemInput[]>();
  for (const row of gearRows) {
    if (!row.item.equippedHeroId) continue;
    const list = itemsByHero.get(row.item.equippedHeroId) ?? [];
    list.push({
      slotType: row.template.slotType,
      bonusHp: row.template.bonusHp,
      bonusAttack: row.template.bonusAttack,
      bonusDefense: row.template.bonusDefense,
      bonusSpeed: row.template.bonusSpeed,
      bonusStr: row.template.bonusStr,
      bonusInt: row.template.bonusInt,
      bonusSta: row.template.bonusSta,
      bonusAgi: row.template.bonusAgi,
      bonusMatk: row.template.bonusMatk,
      bonusMdef: row.template.bonusMdef,
      v2Stats: (row.template.v2Stats as EquipmentV2Stats) ?? null,
      statMultiplier: row.item.statMultiplier ?? 1,
      substats: (row.item.substats as EquipmentV2Stats) ?? null,
    });
    itemsByHero.set(row.item.equippedHeroId, list);
  }

  const imprintByHero = new Map<string, { str: number; int: number; sta: number; agi: number }>();
  for (const row of imprintRows) {
    const prev = imprintByHero.get(row.owned.heroId) ?? { str: 0, int: 0, sta: 0, agi: 0 };
    prev.str += row.definition.bonusStr;
    prev.int += row.definition.bonusInt;
    prev.sta += row.definition.bonusSta;
    prev.agi += row.definition.bonusAgi;
    imprintByHero.set(row.owned.heroId, prev);
  }

  return heroList.map(hero => ({
    hero,
    combatPower: computeHeroCombatPower(hero, itemsByHero.get(hero.id), imprintByHero.get(hero.id)),
  }));
}

export async function fetchMasterTopCombatPower(masterId: string, limit = 5): Promise<number> {
  const heroesWithPower = await fetchMasterHeroesWithPower(masterId);
  return heroesWithPower
    .map(h => h.combatPower)
    .sort((a, b) => b - a)
    .slice(0, limit)
    .reduce((sum, v) => sum + v, 0);
}

export async function fetchPartyCombatPower(heroIds: string[]): Promise<number> {
  if (heroIds.length === 0) return 0;
  const heroList = await db.select().from(heroes).where(inArray(heroes.id, heroIds));
  if (heroList.length === 0) return 0;

  const [gearRows, imprintRows] = await Promise.all([
    db.select({ item: equipmentInstances, template: equipmentTemplates })
      .from(equipmentInstances).innerJoin(equipmentTemplates, eq(equipmentInstances.templateCode, equipmentTemplates.code))
      .where(and(
        eq(equipmentInstances.location, 'EQUIPPED'),
        inArray(equipmentInstances.equippedHeroId, heroIds),
      )),
    db.select({ owned: heroImprints, definition: imprintDefinitions })
      .from(heroImprints).innerJoin(imprintDefinitions, eq(imprintDefinitions.code, heroImprints.imprintCode))
      .where(inArray(heroImprints.heroId, heroIds)),
  ]);

  const itemsByHero = new Map<string, EquipmentItemInput[]>();
  for (const row of gearRows) {
    if (!row.item.equippedHeroId) continue;
    const list = itemsByHero.get(row.item.equippedHeroId) ?? [];
    list.push({
      slotType: row.template.slotType,
      bonusHp: row.template.bonusHp,
      bonusAttack: row.template.bonusAttack,
      bonusDefense: row.template.bonusDefense,
      bonusSpeed: row.template.bonusSpeed,
      bonusStr: row.template.bonusStr,
      bonusInt: row.template.bonusInt,
      bonusSta: row.template.bonusSta,
      bonusAgi: row.template.bonusAgi,
      bonusMatk: row.template.bonusMatk,
      bonusMdef: row.template.bonusMdef,
      v2Stats: (row.template.v2Stats as EquipmentV2Stats) ?? null,
      statMultiplier: row.item.statMultiplier ?? 1,
      substats: (row.item.substats as EquipmentV2Stats) ?? null,
    });
    itemsByHero.set(row.item.equippedHeroId, list);
  }

  const imprintByHero = new Map<string, { str: number; int: number; sta: number; agi: number }>();
  for (const row of imprintRows) {
    const prev = imprintByHero.get(row.owned.heroId) ?? { str: 0, int: 0, sta: 0, agi: 0 };
    prev.str += row.definition.bonusStr;
    prev.int += row.definition.bonusInt;
    prev.sta += row.definition.bonusSta;
    prev.agi += row.definition.bonusAgi;
    imprintByHero.set(row.owned.heroId, prev);
  }

  return heroList
    .map(hero => computeHeroCombatPower(hero, itemsByHero.get(hero.id), imprintByHero.get(hero.id)))
    .reduce((sum, v) => sum + v, 0);
}
