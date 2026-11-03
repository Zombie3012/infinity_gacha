import { v4 as uuidv4 } from 'uuid';
import { IMasterProfile } from '@infiniti-gacha/shared';

export class MasterService {
  private mastersByAccountId: Map<string, IMasterProfile> = new Map();
  private mastersById: Map<string, IMasterProfile> = new Map();

  /**
   * Initializes a new Master profile for an account. Enforces 1 Account = 1 Master.
   */
  public createMaster(accountId: string, masterName: string): IMasterProfile {
    if (this.mastersByAccountId.has(accountId)) {
      throw new Error(`Account ${accountId} already has a Master profile.`);
    }

    const newMaster: IMasterProfile = {
      id: uuidv4(),
      accountId,
      masterName: masterName.trim(),
      level: 1,
      exp: 0n,
      silverCoins: 10000n, // Initial starter silver
      gems: 0n,
      gemDebt: 0n,
      createdAt: new Date(),
      updatedAt: new Date(),
    };

    this.mastersByAccountId.set(accountId, newMaster);
    this.mastersById.set(newMaster.id, newMaster);
    return newMaster;
  }

  public getMasterByAccountId(accountId: string): IMasterProfile | undefined {
    return this.mastersByAccountId.get(accountId);
  }

  public getMasterById(masterId: string): IMasterProfile | undefined {
    return this.mastersById.get(masterId);
  }
}
