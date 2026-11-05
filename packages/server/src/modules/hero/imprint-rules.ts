/**
 * Imprint slot rules.
 * Slots grow with star rating (Rank Promotion is the intended long-term gate):
 * 1-2★ = 1 slot, 3★ = 2, 4★ = 3, 5★+ = 4.
 */
export const MAX_IMPRINT_RANK_LEVEL = 3;

export function imprintSlotsFor(star: number): number {
  const safe = Math.max(1, Math.min(7, Math.floor(star) || 1));
  if (safe <= 2) return 1;
  if (safe === 3) return 2;
  if (safe === 4) return 3;
  return 4;
}
