import { v4 as uuidv4 } from 'uuid';

export interface IWorldInstance {
  worldId: string;
  masterId: string;
  worldSeed: string; // Globally unique UUIDv4
  seedAlgorithmVersion: number;
  difficultyMultiplier: number;
  currentFloor: number;
  createdAt: Date;
}

export class WorldSeedGenerator {
  /**
   * Generates a new World instance with a globally unique UUID Seed.
   */
  public static createWorld(masterId: string): IWorldInstance {
    const worldSeed = uuidv4();
    
    // Hash first 8 hex characters into a deterministic base difficulty factor
    const seedInt = parseInt(worldSeed.replace(/-/g, '').slice(0, 8), 16);
    const difficultyMultiplier = 1.0 + (seedInt % 50) / 100.0; // 1.00 to 1.49

    return {
      worldId: uuidv4(),
      masterId,
      worldSeed,
      seedAlgorithmVersion: 1,
      difficultyMultiplier,
      currentFloor: 1,
      createdAt: new Date(),
    };
  }
}
