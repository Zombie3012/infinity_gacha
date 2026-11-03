import { HeroRarity, HeroCategory, HeroState, BannerType, BuildingType, ArmyStatus } from '../enums/index.js';

export interface IMasterProfile {
  id: string;
  accountId: string;
  masterName: string;
  level: number;
  exp: bigint;
  silverCoins: bigint;
  gems: bigint;
  gemDebt: bigint;
  createdAt: Date;
  updatedAt: Date;
}

export interface IHeroInstance {
  id: string;
  masterId: string;
  name: string;
  rarity: HeroRarity;
  category: HeroCategory;
  state: HeroState;
  level: number;
  exp: bigint;
  hp: number;
  maxHp: number;
  attack: number;
  defense: number;
  speed: number;
  talentPoints: number;
  thienMenh: number;
  hunger: number;
  fatigue: number;
  loyalty: number;
  createdAt: Date;
}

export interface IBanner {
  id: string;
  name: string;
  bannerType: BannerType;
  pityCounter: number;
  startDate: Date;
  endDate?: Date;
  isActive: boolean;
}

export interface IGachaRollResult {
  rollNumber: number;
  isFiveStar: boolean;
  itemType: 'HERO' | 'MATERIAL';
  rewardId: string;
  rewardName: string;
  rarity: number;
  isDuplicate: boolean;
  duplicateBonus?: {
    talentPointsGranted?: number;
    thienMenhGranted?: number;
  };
}

export interface IArmy {
  id: string;
  masterId: string;
  armyName: string;
  commanderHeroId: string;
  subHeroIds: string[];
  status: ArmyStatus;
  originX: number;
  originY: number;
  currentX: number;
  currentY: number;
  targetX: number;
  targetY: number;
  departureTime: Date;
  etaTime: Date;
}

export interface IBaseBuilding {
  id: string;
  masterId: string;
  buildingType: BuildingType;
  level: number;
  assignedWorkerHeroIds: string[];
  productionRatePerHour: number;
  updatedAt: Date;
}
