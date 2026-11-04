/**
 * Domain 14 (P2) operator tooling rules: account restriction and compensation.
 * Pure helpers so the guard conditions are unit-testable.
 */

export const RESTRICTION_STATUSES = ['SUSPENDED', 'BANNED'] as const;
export type RestrictionStatus = (typeof RESTRICTION_STATUSES)[number];

export const ACCOUNT_STATUSES = ['ACTIVE', 'SUSPENDED', 'BANNED'] as const;

export function isRestrictionStatus(value: string): value is RestrictionStatus {
  return (RESTRICTION_STATUSES as readonly string[]).includes(value);
}

export interface Compensation {
  silver: number;
  gems: number;
  items: { itemId: string; quantity: number }[];
}

export function normalizeCompensation(raw: unknown): Compensation {
  const source = raw && typeof raw === 'object' ? raw as Record<string, unknown> : {};
  const itemsRaw = Array.isArray(source.items) ? source.items : [];
  return {
    silver: Math.max(0, Math.floor(Number(source.silver) || 0)),
    gems: Math.max(0, Math.floor(Number(source.gems) || 0)),
    items: itemsRaw
      .map(entry => {
        const row = entry as Record<string, unknown>;
        return { itemId: String(row.itemId ?? '').trim().toUpperCase(), quantity: Math.max(0, Math.floor(Number(row.quantity) || 0)) };
      })
      .filter(row => /^[A-Z0-9_]{2,50}$/.test(row.itemId) && row.quantity > 0),
  };
}

export function hasCompensationValue(value: Compensation): boolean {
  return value.silver > 0 || value.gems > 0 || value.items.length > 0;
}

/** Compensation caps keep a mistyped payload from minting absurd amounts. */
export const COMPENSATION_LIMITS = { silver: 5_000_000, gems: 100_000, itemQuantity: 999 };

export function validateCompensation(value: Compensation): string | null {
  if (value.silver > COMPENSATION_LIMITS.silver) return 'ERR_COMPENSATION_SILVER_TOO_HIGH';
  if (value.gems > COMPENSATION_LIMITS.gems) return 'ERR_COMPENSATION_GEMS_TOO_HIGH';
  if (value.items.some(row => row.quantity > COMPENSATION_LIMITS.itemQuantity)) return 'ERR_COMPENSATION_ITEM_TOO_HIGH';
  return null;
}

export function isValidContentCode(value: string): boolean {
  return /^[A-Z0-9_]{2,50}$/.test(value);
}
