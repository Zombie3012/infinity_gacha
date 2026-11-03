import { GAME_CONSTANTS } from '@infiniti-gacha/shared';

export interface ITacticalBuff {
  id: string;
  name: string;
  description: string;
  attackMultiplier: number;
  defenseMultiplier: number;
  speedMultiplier: number;
}

export class TacticalBuffManager {
  private activeBuffId: string | null = null;
  private lastBuffChangeTimestamp: number = 0;

  public static readonly AVAILABLE_BUFFS: Record<string, ITacticalBuff> = {
    VANGUARD_RUSH: {
      id: 'VANGUARD_RUSH',
      name: 'Vanguard Rush',
      description: 'Increases Attack by +20%, decreases Defense by -10%',
      attackMultiplier: 1.2,
      defenseMultiplier: 0.9,
      speedMultiplier: 1.0,
    },
    IRONCLAD_AEGIS: {
      id: 'IRONCLAD_AEGIS',
      name: 'Ironclad Aegis',
      description: 'Increases Defense by +30%, decreases Attack by -5%',
      attackMultiplier: 0.95,
      defenseMultiplier: 1.3,
      speedMultiplier: 1.0,
    },
    SWIFT_EVASION: {
      id: 'SWIFT_EVASION',
      name: 'Swift Evasion',
      description: 'Increases Speed by +25%',
      attackMultiplier: 1.0,
      defenseMultiplier: 1.0,
      speedMultiplier: 1.25,
    },
  };

  /**
   * Attempts to switch the active tactical buff.
   * Enforces strict 15-second cooldown between changes.
   */
  public changeBuff(newBuffId: string, currentTimestamp: number = Date.now()): { success: boolean; buff?: ITacticalBuff; remainingCooldownSeconds?: number } {
    const buff = TacticalBuffManager.AVAILABLE_BUFFS[newBuffId];
    if (!buff) {
      throw new Error(`Buff ID ${newBuffId} not recognized.`);
    }

    const { TACTICAL_BUFF_COOLDOWN_SECONDS } = GAME_CONSTANTS.COMBAT;
    const elapsedSeconds = (currentTimestamp - this.lastBuffChangeTimestamp) / 1000;

    if (this.lastBuffChangeTimestamp > 0 && elapsedSeconds < TACTICAL_BUFF_COOLDOWN_SECONDS) {
      return {
        success: false,
        remainingCooldownSeconds: Math.ceil(TACTICAL_BUFF_COOLDOWN_SECONDS - elapsedSeconds),
      };
    }

    this.activeBuffId = newBuffId;
    this.lastBuffChangeTimestamp = currentTimestamp;

    return {
      success: true,
      buff,
    };
  }

  public getActiveBuff(): ITacticalBuff | null {
    return this.activeBuffId ? TacticalBuffManager.AVAILABLE_BUFFS[this.activeBuffId] || null : null;
  }
}
