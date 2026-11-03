import { IMasterProfile } from '@infiniti-gacha/shared';

export class GemDebtHandler {
  /**
   * Processes a refund or chargeback on an IAP package.
   * If master has enough gems, subtracts them directly.
   * If gems are already spent, master's gemDebt increases by the remaining unpaid amount.
   * Account is NEVER banned.
   */
  public static processRefund(master: IMasterProfile, gemsToReclaim: bigint): { deductedGems: bigint; addedDebt: bigint } {
    if (master.gems >= gemsToReclaim) {
      master.gems -= gemsToReclaim;
      master.updatedAt = new Date();
      return { deductedGems: gemsToReclaim, addedDebt: 0n };
    }

    const remainingToReclaim = gemsToReclaim - master.gems;
    const deductedGems = master.gems;
    master.gems = 0n;
    master.gemDebt += remainingToReclaim;
    master.updatedAt = new Date();

    return { deductedGems, addedDebt: remainingToReclaim };
  }

  /**
   * When a player earns or receives gems, debt is repaid first.
   */
  public static creditGems(master: IMasterProfile, gemsEarned: bigint): { debtRepaid: bigint; netGemsAdded: bigint } {
    if (master.gemDebt > 0n) {
      if (gemsEarned <= master.gemDebt) {
        master.gemDebt -= gemsEarned;
        master.updatedAt = new Date();
        return { debtRepaid: gemsEarned, netGemsAdded: 0n };
      } else {
        const debtRepaid = master.gemDebt;
        const netGemsAdded = gemsEarned - master.gemDebt;
        master.gemDebt = 0n;
        master.gems += netGemsAdded;
        master.updatedAt = new Date();
        return { debtRepaid, netGemsAdded };
      }
    }

    master.gems += gemsEarned;
    master.updatedAt = new Date();
    return { debtRepaid: 0n, netGemsAdded: gemsEarned };
  }
}
