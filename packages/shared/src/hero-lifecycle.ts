/** A terminal state always outranks an HP display; zero HP cannot perform living-Hero actions. */
export function isLivingHero(hero: { state: string; hp: number }): boolean {
  return hero.state !== 'DEAD' && hero.state !== 'DISABLED' && Number.isFinite(hero.hp) && hero.hp > 0;
}
