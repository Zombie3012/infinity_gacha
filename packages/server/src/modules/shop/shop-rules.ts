/**
 * Domain 11 (P1) shop and mailbox rules.
 *
 * Sample tuning:
 * - purchase limits reset daily at 00:00 UTC+7
 * - shop items may rotate by weekday (empty rotationDays = available daily)
 * - mail expires 30 days after it is sent unless an explicit expiry is given
 */

export const SHOP_TIME_ZONE_OFFSET_MINUTES = 7 * 60;
export const DEFAULT_MAIL_LIFETIME_DAYS = 30;

export interface MailAttachments {
  silver: number;
  items: { itemId: string; quantity: number }[];
}

export function dailyPeriodKey(now: Date): string {
  const shifted = new Date(now.getTime() + SHOP_TIME_ZONE_OFFSET_MINUTES * 60_000);
  return shifted.toISOString().slice(0, 10);
}

/** 0 = Sunday … 6 = Saturday, evaluated in UTC+7. */
export function localWeekday(now: Date): number {
  const shifted = new Date(now.getTime() + SHOP_TIME_ZONE_OFFSET_MINUTES * 60_000);
  return shifted.getUTCDay();
}

export function isAvailableNow(rotationDays: readonly number[], now: Date): boolean {
  if (rotationDays.length === 0) return true;
  return rotationDays.includes(localWeekday(now));
}

/**
 * Scenario 13.1: with 4 of 5 daily units already bought, requesting 2 units
 * yields 1 purchasable unit and a limit error for the remainder.
 */
export function resolvePurchaseQuantity(remaining: number | null, requested: number): { allowed: number; blocked: boolean } {
  const want = Math.max(1, Math.floor(requested));
  if (remaining === null) return { allowed: want, blocked: false };
  const left = Math.max(0, Math.floor(remaining));
  if (left <= 0) return { allowed: 0, blocked: true };
  return { allowed: Math.min(want, left), blocked: want > left };
}

export function normalizeAttachments(raw: unknown): MailAttachments {
  const source = raw && typeof raw === 'object' ? raw as Record<string, unknown> : {};
  const silver = Math.max(0, Math.floor(Number(source.silver) || 0));
  const itemsRaw = Array.isArray(source.items) ? source.items : [];
  const items = itemsRaw
    .map(entry => {
      const row = entry as Record<string, unknown>;
      return { itemId: String(row.itemId ?? ''), quantity: Math.max(0, Math.floor(Number(row.quantity) || 0)) };
    })
    .filter(row => row.itemId.length > 0 && row.itemId.length <= 50 && row.quantity > 0);
  return { silver, items };
}

export function mailExpiresAt(sentAt: Date, lifetimeDays = DEFAULT_MAIL_LIFETIME_DAYS): Date {
  return new Date(sentAt.getTime() + Math.max(1, lifetimeDays) * 86_400_000);
}

export function isExpired(expiresAt: Date, now: Date): boolean {
  return expiresAt.getTime() <= now.getTime();
}

export function totalSilverFor(priceSilver: number, quantity: number): number {
  return Math.max(0, Math.floor(priceSilver)) * Math.max(1, Math.floor(quantity));
}
