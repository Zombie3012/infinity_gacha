export const HERB = 'ALCHEMY_HERB_1';
export const POTION_CRAFT_SILVER = 100;
export const POTION_CRAFT_HERBS = 3;
export const MANA_RESTORE_RATIO = 0.5;
export const STRENGTH_ATK_MULTIPLIER = 1.2;
export const POTIONS = ['MEDICINE', 'MANA_POTION', 'STRENGTH_POTION'] as const;
export const ALCHEMY_TECH = [
  { code: 'ALCHEMY_FOUNDATION', name: 'Nền tảng giả kim', prerequisite: null, silver: 1000, herbs: 5, itemId: null },
  { code: 'ALCHEMY_MEDICINE', name: 'Dược học hồi phục', prerequisite: 'ALCHEMY_FOUNDATION', silver: 2000, herbs: 10, itemId: 'MEDICINE' },
  { code: 'ALCHEMY_MANA', name: 'Tinh chế ma lực', prerequisite: 'ALCHEMY_FOUNDATION', silver: 2000, herbs: 10, itemId: 'MANA_POTION' },
  { code: 'ALCHEMY_STRENGTH', name: 'Dược học cường lực', prerequisite: 'ALCHEMY_FOUNDATION', silver: 2000, herbs: 10, itemId: 'STRENGTH_POTION' },
];
export const POTION_NAMES: Record<string, string> = { MEDICINE: 'Thuốc điều trị', MANA_POTION: 'Thuốc ma lực', STRENGTH_POTION: 'Thuốc cường lực' };
export type ConsumableSlot = { itemId: string; quantity: number } | null;
export type ConsumableConfig = { slots: ConsumableSlot[]; autoHpBelow?: number; autoManaBelow: number; autoStrength: boolean };
export function validateConsumables(input: unknown): ConsumableConfig {
  const c = input as ConsumableConfig;
  if (!c || !Array.isArray(c.slots) || c.slots.length !== 5 || !Number.isInteger(c.autoManaBelow)
    || c.autoManaBelow < 0 || c.autoManaBelow > 100 || typeof c.autoStrength !== 'boolean') throw new Error('ERR_CONSUMABLE_CONFIG');
  if (c.slots.some(s => s !== null && (!s || !POTIONS.includes(s.itemId as typeof POTIONS[number])
    || !Number.isInteger(s.quantity) || s.quantity < 1 || s.quantity > 4))) throw new Error('ERR_CONSUMABLE_CONFIG');
  if (c.autoHpBelow !== undefined && (!Number.isInteger(c.autoHpBelow) || c.autoHpBelow < 0 || c.autoHpBelow > 100)) throw new Error('ERR_CONSUMABLE_CONFIG');
  return { slots: c.slots.map(s => s ? { itemId: s.itemId, quantity: s.quantity } : null), autoHpBelow: c.autoHpBelow ?? 30, autoManaBelow: c.autoManaBelow, autoStrength: c.autoStrength };
}
