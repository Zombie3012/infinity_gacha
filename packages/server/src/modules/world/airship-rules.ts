/**
 * Airship Port (Bến Thiên Hành) & RTS Expedition Rules.
 *
 * Core rules locked with player spec:
 * - Unlocks at Tower Floor 25 (clearedFloor >= 25).
 * - Airship Port levels 1..5 expand base docking grid: Lv.1 = 4x4 ... Lv.5 = 8x8.
 * - Airship Tech Tree unlocks ship blueprints AND further dock grid expansions.
 * - 4 ship classes across 3 size tiers with grid footprints:
 *   - SCOUT_SKIFF (SMALL, 2x2): max 3 heroes, fast 1.8x, radar +2, leaves 1-hour vision trail.
 *   - RESCUE_CUTTER (SMALL, 2x3): max 6 heroes, fast 1.5x, rescues stranded squads/ships.
 *   - WAR_DREADNOUGHT (MEDIUM, 3x3): max 5 heroes, 1.25x, combat power bonus for dungeons/PvP.
 *   - TRANSPORT_CARRIER (LARGE, 4x5): max 15 heroes, 1.05x, mass hero transport for A/S Raid dungeons.
 * - Dynamic Fog of War: always active; scout vision persists for 1 hour (3600s) + tech bonus.
 */

export const AIRSHIP_UNLOCK_FLOOR = 25;
export const MAX_AIRSHIP_LEVEL = 10;
export const MAX_PORT_LEVEL = 5;
export const BASE_VISION_SECONDS = 3600; // 1 hour exact default
export const BASE_HOME_VISION_RADIUS = 2;

export type AirshipBlueprintCode =
  | 'SCOUT_SKIFF'
  | 'RESCUE_CUTTER'
  | 'WAR_DREADNOUGHT'
  | 'TRANSPORT_CARRIER';

export type AirshipSizeClass = 'SMALL' | 'MEDIUM' | 'LARGE';
export type AirshipStatus = 'DOCKED' | 'CRAFTING' | 'DEPLOYED' | 'REPAIRING' | 'STRANDED';

export interface AirshipBlueprint {
  code: AirshipBlueprintCode;
  name: string;
  sizeClass: AirshipSizeClass;
  gridW: number;
  gridH: number;
  maxHeroes: number;
  baseSpeedMult: number;
  radarRadius: number;
  basePowerBonusPct: number;
  baseMaxHp: number;
  craftCostSilver: number;
  craftSeconds: number;
  requiredTech: string;
  roleSummary: string;
}

export const AIRSHIP_BLUEPRINTS: Record<AirshipBlueprintCode, AirshipBlueprint> = {
  SCOUT_SKIFF: {
    code: 'SCOUT_SKIFF',
    name: 'Thuyền Trinh Sát',
    sizeClass: 'SMALL',
    gridW: 2,
    gridH: 2,
    maxHeroes: 3,
    baseSpeedMult: 1.8,
    radarRadius: 2,
    basePowerBonusPct: 0,
    baseMaxHp: 100,
    craftCostSilver: 1500,
    craftSeconds: 30,
    requiredTech: 'TECH_SHIP_SCOUT',
    roleSummary: 'Tàu nhỏ (2x2), bay cực nhanh, quét sương mù lưu tầm nhìn 1 giờ dọc tuyến đường.',
  },
  RESCUE_CUTTER: {
    code: 'RESCUE_CUTTER',
    name: 'Tàu Cứu Hộ',
    sizeClass: 'SMALL',
    gridW: 2,
    gridH: 3,
    maxHeroes: 6,
    baseSpeedMult: 1.5,
    radarRadius: 1,
    basePowerBonusPct: 5,
    baseMaxHp: 140,
    craftCostSilver: 2600,
    craftSeconds: 45,
    requiredTech: 'TECH_SHIP_RESCUE',
    roleSummary: 'Tàu nhỏ (2x3), chở tối đa 6 Hero, chuyên ứng cứu và sơ tán tổ đội mắc kẹt.',
  },
  WAR_DREADNOUGHT: {
    code: 'WAR_DREADNOUGHT',
    name: 'Tàu Tấn Công',
    sizeClass: 'MEDIUM',
    gridW: 3,
    gridH: 3,
    maxHeroes: 5,
    baseSpeedMult: 1.25,
    radarRadius: 1,
    basePowerBonusPct: 15,
    baseMaxHp: 220,
    craftCostSilver: 4500,
    craftSeconds: 75,
    requiredTech: 'TECH_SHIP_ATTACK',
    roleSummary: 'Tàu trung bình (3x3), chở 5 Hero, tăng mạnh lực chiến khi đánh Hầm Ngục Nổi & PvP.',
  },
  TRANSPORT_CARRIER: {
    code: 'TRANSPORT_CARRIER',
    name: 'Tàu Vận Tải Hạng Nặng',
    sizeClass: 'LARGE',
    gridW: 4,
    gridH: 5,
    maxHeroes: 15,
    baseSpeedMult: 1.05,
    radarRadius: 1,
    basePowerBonusPct: 10,
    baseMaxHp: 320,
    craftCostSilver: 8000,
    craftSeconds: 120,
    requiredTech: 'TECH_SHIP_TRANSPORT',
    roleSummary: 'Tàu lớn (4x5), chuyên chở thành viên tối đa 15 Hero chinh phạt Hầm Ngục Raid.',
  },
};

export interface AirshipTechNode {
  code: string;
  branch: 'SHIPYARD' | 'DOCK' | 'LOGISTICS';
  name: string;
  description: string;
  costSilver: number;
  requiredPortLevel: number;
  prerequisites: string[];
  dockBonusW?: number;
  dockBonusH?: number;
  visionBonusSeconds?: number;
  repairDiscountPct?: number;
}

export const AIRSHIP_TECH_TREE: AirshipTechNode[] = [
  // Branch 1: Shipyard Blueprints
  {
    code: 'TECH_SHIP_SCOUT',
    branch: 'SHIPYARD',
    name: 'Khung Thuyền Trinh Sát',
    description: 'Mở khóa chế tạo Thuyền Trinh Sát (Nhỏ 2x2, tối đa 3 Hero, lưu tầm nhìn 1 giờ).',
    costSilver: 500,
    requiredPortLevel: 1,
    prerequisites: [],
  },
  {
    code: 'TECH_SHIP_RESCUE',
    branch: 'SHIPYARD',
    name: 'Tàu Cứu Hộ Khẩn Cấp',
    description: 'Mở khóa chế tạo Tàu Cứu Hộ (Nhỏ 2x3, tối đa 6 Hero, giải cứu tổ đội mắc kẹt).',
    costSilver: 1500,
    requiredPortLevel: 1,
    prerequisites: ['TECH_SHIP_SCOUT'],
  },
  {
    code: 'TECH_SHIP_ATTACK',
    branch: 'SHIPYARD',
    name: 'Giáp Chiến Hạm Trung Cấp',
    description: 'Mở khóa chế tạo Tàu Tấn Công (Trung bình 3x3, 5 Hero, buff lực chiến).',
    costSilver: 3000,
    requiredPortLevel: 1,
    prerequisites: ['TECH_SHIP_SCOUT'],
  },
  {
    code: 'TECH_SHIP_TRANSPORT',
    branch: 'SHIPYARD',
    name: 'Khoang Vận Tải Đại Đội',
    description: 'Mở khóa chế tạo Tàu Vận Tải Hạng Nặng (Lớn 4x5, chở tối đa 15 Hero).',
    costSilver: 6000,
    requiredPortLevel: 2,
    prerequisites: ['TECH_SHIP_ATTACK', 'TECH_SHIP_RESCUE'],
  },
  // Branch 2: Dock Grid Expansion
  {
    code: 'TECH_DOCK_EXPAND_1',
    branch: 'DOCK',
    name: 'Mở Rộng Sàn Đậu I (+1 Ngang)',
    description: 'Tăng thêm +1 cột chiều rộng cho sàn bãi đậu Cảng Tàu Bay.',
    costSilver: 2000,
    requiredPortLevel: 1,
    prerequisites: ['TECH_SHIP_SCOUT'],
    dockBonusW: 1,
  },
  {
    code: 'TECH_DOCK_EXPAND_2',
    branch: 'DOCK',
    name: 'Mở Rộng Sàn Đậu II (+1 Dọc)',
    description: 'Tăng thêm +1 hàng chiều dài cho sàn bãi đậu Cảng Tàu Bay.',
    costSilver: 3500,
    requiredPortLevel: 2,
    prerequisites: ['TECH_DOCK_EXPAND_1'],
    dockBonusH: 1,
  },
  {
    code: 'TECH_DOCK_EXPAND_3',
    branch: 'DOCK',
    name: 'Sàn Neo Đậu Tầng Trên (+1x+1)',
    description: 'Mở rộng thêm +1 cột và +1 hàng cho bãi đậu (tối đa lên tới 10x10 ở Cảng Lv.5).',
    costSilver: 7000,
    requiredPortLevel: 3,
    prerequisites: ['TECH_DOCK_EXPAND_2'],
    dockBonusW: 1,
    dockBonusH: 1,
  },
  // Branch 3: Logistics & Radar
  {
    code: 'TECH_RADAR_PERSIST',
    branch: 'LOGISTICS',
    name: 'Đèn Hiệu Hành Trình (+30p)',
    description: 'Kéo dài thời gian lưu tầm nhìn trên tuyến đường Scout thêm +30 phút (tổng 1h30p).',
    costSilver: 2500,
    requiredPortLevel: 1,
    prerequisites: ['TECH_SHIP_SCOUT'],
    visionBonusSeconds: 1800,
  },
  {
    code: 'TECH_FAST_REPAIR',
    branch: 'LOGISTICS',
    name: 'Xưởng Bảo Trì Tự Động',
    description: 'Giảm 25% chi phí và thời gian sửa chữa tàu bay tại Cảng.',
    costSilver: 3000,
    requiredPortLevel: 2,
    prerequisites: ['TECH_SHIP_RESCUE'],
    repairDiscountPct: 25,
  },
];

export const TECH_BY_CODE = new Map(AIRSHIP_TECH_TREE.map(node => [node.code, node]));

/** Base dock grid size: Lv.1 = 4x4, Lv.2 = 5x5, ..., Lv.5 = 8x8, plus Tech bonuses. */
export function computeDockDimensions(portLevel: number, unlockedTechs: Iterable<string>): { width: number; height: number } {
  const clampedLevel = Math.max(1, Math.min(MAX_PORT_LEVEL, Math.floor(portLevel)));
  let width = 3 + clampedLevel; // Lv.1 -> 4, Lv.5 -> 8
  let height = 3 + clampedLevel;
  for (const code of unlockedTechs) {
    const node = TECH_BY_CODE.get(code);
    if (!node) continue;
    width += node.dockBonusW ?? 0;
    height += node.dockBonusH ?? 0;
  }
  return { width: Math.min(10, width), height: Math.min(10, height) };
}

export function visionDurationSeconds(unlockedTechs: Iterable<string>): number {
  let total = BASE_VISION_SECONDS;
  for (const code of unlockedTechs) {
    const node = TECH_BY_CODE.get(code);
    if (node?.visionBonusSeconds) total += node.visionBonusSeconds;
  }
  return total;
}

export function repairDiscountPct(unlockedTechs: Iterable<string>): number {
  let pct = 0;
  for (const code of unlockedTechs) {
    const node = TECH_BY_CODE.get(code);
    if (node?.repairDiscountPct) pct += node.repairDiscountPct;
  }
  return Math.min(50, pct);
}

export interface DockRect {
  id?: string;
  x: number;
  y: number;
  w: number;
  h: number;
}

export function effectiveFootprint(gridW: number, gridH: number, rotation: number): { w: number; h: number } {
  return rotation === 90 ? { w: gridH, h: gridW } : { w: gridW, h: gridH };
}

export function canPlaceOnDockGrid(
  dockW: number,
  dockH: number,
  occupied: readonly DockRect[],
  candidate: DockRect,
  ignoreId?: string,
): boolean {
  if (candidate.x < 0 || candidate.y < 0) return false;
  if (candidate.x + candidate.w > dockW || candidate.y + candidate.h > dockH) return false;
  for (const rect of occupied) {
    if (ignoreId && rect.id === ignoreId) continue;
    const overlapX = candidate.x < rect.x + rect.w && candidate.x + candidate.w > rect.x;
    const overlapY = candidate.y < rect.y + rect.h && candidate.y + candidate.h > rect.y;
    if (overlapX && overlapY) return false;
  }
  return true;
}

export function findAutoDockPosition(
  dockW: number,
  dockH: number,
  occupied: readonly DockRect[],
  gridW: number,
  gridH: number,
  ignoreId?: string,
): { x: number; y: number; rotation: 0 | 90 } | null {
  const rotations: Array<0 | 90> = gridW === gridH ? [0] : [0, 90];
  for (const rotation of rotations) {
    const { w, h } = effectiveFootprint(gridW, gridH, rotation);
    for (let y = 0; y <= dockH - h; y++) {
      for (let x = 0; x <= dockW - w; x++) {
        if (canPlaceOnDockGrid(dockW, dockH, occupied, { x, y, w, h }, ignoreId)) {
          return { x, y, rotation };
        }
      }
    }
  }
  return null;
}

export function airshipStatsForLevel(code: AirshipBlueprintCode, level: number) {
  const bp = AIRSHIP_BLUEPRINTS[code];
  const lvl = Math.max(1, Math.min(MAX_AIRSHIP_LEVEL, Math.floor(level)));
  const step = lvl - 1;
  return {
    speedMult: Math.round((bp.baseSpeedMult + step * 0.06) * 100) / 100,
    powerBonusPct: bp.basePowerBonusPct + step * 2,
    maxHp: Math.round(bp.baseMaxHp * (1 + step * 0.15)),
    maxHeroes: bp.maxHeroes,
    radarRadius: bp.radarRadius,
    upgradeCostSilver: Math.round(bp.craftCostSilver * (0.45 + step * 0.3)),
  };
}

export function repairCostSilver(code: AirshipBlueprintCode, missingHp: number, maxHp: number, discountPct = 0): number {
  if (missingHp <= 0 || maxHp <= 0) return 0;
  const bp = AIRSHIP_BLUEPRINTS[code];
  const ratio = Math.min(1, missingHp / maxHp);
  const raw = Math.max(100, Math.round(bp.craftCostSilver * 0.25 * ratio));
  return Math.max(50, Math.round(raw * (1 - discountPct / 100)));
}

/** Trace integer grid coordinates from origin to destination (Bresenham line) for flight vision corridor. */
export function traceFlightPath(
  from: { x: number; y: number },
  to: { x: number; y: number },
): Array<{ x: number; y: number }> {
  const points: Array<{ x: number; y: number }> = [];
  let x0 = Math.round(from.x);
  let y0 = Math.round(from.y);
  const x1 = Math.round(to.x);
  const y1 = Math.round(to.y);
  const dx = Math.abs(x1 - x0);
  const dy = Math.abs(y1 - y0);
  const sx = x0 < x1 ? 1 : -1;
  const sy = y0 < y1 ? 1 : -1;
  let err = dx - dy;

  while (true) {
    points.push({ x: x0, y: y0 });
    if (x0 === x1 && y0 === y1) break;
    const e2 = 2 * err;
    if (e2 > -dy) {
      err -= dy;
      x0 += sx;
    }
    if (e2 < dx) {
      err += dx;
      y0 += sy;
    }
  }
  return points;
}
