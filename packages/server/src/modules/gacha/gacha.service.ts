import { v4 as uuidv4 } from 'uuid';
import {
  GAME_CONSTANTS,
  calculateFiveStarRate,
  rollForFiveStar,
  HeroCategory,
  HeroRarity,
  HeroState,
  IGachaRollResult,
  IHeroInstance,
} from '@infiniti-gacha/shared';

export interface IBannerState {
  bannerId: string;
  name: string;
  pityCounter: number;
}

export class GachaService {
  private bannerStates: Map<string, IBannerState> = new Map(); // `${masterId}:${bannerId}`
  private ownedHeroesByMaster: Map<string, Map<string, IHeroInstance>> = new Map(); // masterId -> (heroConfigId -> instance)
  private weeklyExchangeCount: Map<string, number> = new Map(); // masterId -> count

  public getOrCreateBanner(bannerId: string, name: string, masterId?: string): IBannerState {
    const stateKey = masterId ? `${masterId}:${bannerId}` : bannerId;
    let state = this.bannerStates.get(stateKey);
    if (!state) {
      state = { bannerId, name, pityCounter: 0 };
      this.bannerStates.set(stateKey, state);
    }
    return state;
  }

  /**
   * Exchanges Silver Coins for Normal Heavenly Scrolls (Cap: 50/week, 10,000 silver each)
   */
  public exchangeScroll(masterId: string, currentSilver: bigint, amount: number): { success: boolean; newSilver: bigint; scrollsGranted: number; error?: string } {
    const currentExchanges = this.weeklyExchangeCount.get(masterId) || 0;
    const { SCROLL_EXCHANGE_COST_SILVER, SCROLL_EXCHANGE_WEEKLY_CAP } = GAME_CONSTANTS.GACHA;

    if (currentExchanges + amount > SCROLL_EXCHANGE_WEEKLY_CAP) {
      return {
        success: false,
        newSilver: currentSilver,
        scrollsGranted: 0,
        error: `Weekly exchange limit exceeded. Limit is ${SCROLL_EXCHANGE_WEEKLY_CAP}/week, already exchanged ${currentExchanges}.`,
      };
    }

    const totalCost = BigInt(amount * SCROLL_EXCHANGE_COST_SILVER);
    if (currentSilver < totalCost) {
      return {
        success: false,
        newSilver: currentSilver,
        scrollsGranted: 0,
        error: `Insufficient Silver Coins. Requires ${totalCost}, have ${currentSilver}.`,
      };
    }

    this.weeklyExchangeCount.set(masterId, currentExchanges + amount);
    return {
      success: true,
      newSilver: currentSilver - totalCost,
      scrollsGranted: amount,
    };
  }

  /**
   * Performs 1 or 10 rolls on a banner.
   */
  public summon(
    masterId: string,
    bannerId: string,
    rollCount: 1 | 10
  ): { results: IGachaRollResult[]; finalPityCounter: number } {
    const masterBannerKey = `${masterId}:${bannerId}`;
    const legacyBannerState = this.bannerStates.get(bannerId);
    const banner = legacyBannerState ?? this.bannerStates.get(masterBannerKey) ?? this.getOrCreateBanner(bannerId, bannerId, masterId);
    if (legacyBannerState) {
      this.bannerStates.delete(bannerId);
      this.bannerStates.set(masterBannerKey, legacyBannerState);
    }
    const results: IGachaRollResult[] = [];

    if (!this.ownedHeroesByMaster.has(masterId)) {
      this.ownedHeroesByMaster.set(masterId, new Map());
    }
    const masterHeroes = this.ownedHeroesByMaster.get(masterId)!;

    for (let i = 0; i < rollCount; i++) {
      banner.pityCounter += 1;
      const isFiveStar = rollForFiveStar(banner.pityCounter);

      let rollResult: IGachaRollResult;

      if (isFiveStar) {
        // Guaranteed or hit 5-Star Hero -> reset pity counter
        banner.pityCounter = 0;
        const heroConfigId = 'HERO_5S_LANCELOT';
        const isDuplicate = masterHeroes.has(heroConfigId);

        let duplicateBonus;
        if (isDuplicate) {
          // Special/Limited duplicate converts to Thien Menh (provisional)
          const existing = masterHeroes.get(heroConfigId)!;
          existing.thienMenh += 1;
          duplicateBonus = { thienMenhGranted: 1 };
        } else {
          // Register new hero
          masterHeroes.set(heroConfigId, {
            id: uuidv4(),
            masterId,
            name: 'Lancelot',
            rarity: HeroRarity.FIVE_STAR,
            category: HeroCategory.SPECIAL,
            state: HeroState.HEALTHY,
            level: 1,
            exp: 0n,
            hp: 1500,
            maxHp: 1500,
            attack: 280,
            defense: 180,
            speed: 110,
            talentPoints: 0,
            thienMenh: 0,
            hunger: 0,
            fatigue: 0,
            loyalty: 100,
            createdAt: new Date(),
          });
        }

        rollResult = {
          rollNumber: i + 1,
          isFiveStar: true,
          itemType: 'HERO',
          rewardId: heroConfigId,
          rewardName: 'Lancelot of the Lake',
          rarity: 5,
          isDuplicate,
          duplicateBonus,
        };
      } else {
        // Non-5-Star: 50% Hero (1-4★), 50% Material
        const isHero = Math.random() < 0.5;
        if (isHero) {
          const heroConfigId = 'HERO_3S_ARCHER';
          const isDuplicate = masterHeroes.has(heroConfigId);
          let duplicateBonus;

          if (isDuplicate) {
            // Every duplicate origin grants one Thien Menh to the owned Hero.
            const existing = masterHeroes.get(heroConfigId)!;
            existing.thienMenh += 1;
            duplicateBonus = { thienMenhGranted: 1 };
          } else {
            masterHeroes.set(heroConfigId, {
              id: uuidv4(),
              masterId,
              name: 'Elven Ranger',
              rarity: HeroRarity.THREE_STAR,
              category: HeroCategory.NORMAL,
              state: HeroState.HEALTHY,
              level: 1,
              exp: 0n,
              hp: 600,
              maxHp: 600,
              attack: 140,
              defense: 70,
              speed: 120,
              talentPoints: 0,
              thienMenh: 0,
              hunger: 0,
              fatigue: 0,
              loyalty: 80,
              createdAt: new Date(),
            });
          }

          rollResult = {
            rollNumber: i + 1,
            isFiveStar: false,
            itemType: 'HERO',
            rewardId: heroConfigId,
            rewardName: 'Elven Ranger',
            rarity: 3,
            isDuplicate,
            duplicateBonus,
          };
        } else {
          // Material
          rollResult = {
            rollNumber: i + 1,
            isFiveStar: false,
            itemType: 'MATERIAL',
            rewardId: 'MAT_IRON_ORE',
            rewardName: 'High-Purity Iron Ore',
            rarity: 2,
            isDuplicate: false,
          };
        }
      }

      results.push(rollResult);
    }

    return {
      results,
      finalPityCounter: banner.pityCounter,
    };
  }

  public getOwnedHeroes(masterId: string): IHeroInstance[] {
    const heroes = this.ownedHeroesByMaster.get(masterId);
    return heroes ? Array.from(heroes.values()) : [];
  }
}
