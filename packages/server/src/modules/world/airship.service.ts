import { and, asc, eq, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import {
  baseBuildings, masterAirships, masterAirshipTechs, masters, worlds,
} from '../../database/drizzle-schema.js';
import {
  AIRSHIP_BLUEPRINTS, AIRSHIP_TECH_TREE, AIRSHIP_UNLOCK_FLOOR, MAX_AIRSHIP_LEVEL, TECH_BY_CODE,
  airshipStatsForLevel, canPlaceOnDockGrid, computeDockDimensions, effectiveFootprint,
  findAutoDockPosition, repairCostSilver, repairDiscountPct, visionDurationSeconds,
  type AirshipBlueprintCode, type DockRect,
} from './airship-rules.js';

export class AirshipError extends Error {
  constructor(message: string, readonly statusCode = 400) {
    super(message);
    this.name = 'AirshipError';
  }
}

export class AirshipService {
  /** Settle finished crafting and repairs. */
  async settle(masterId: string, now = new Date()) {
    const craftingDone = await db.select().from(masterAirships).where(and(
      eq(masterAirships.masterId, masterId),
      eq(masterAirships.status, 'CRAFTING'),
      sql`${masterAirships.busyUntil} <= ${now}`,
    ));
    for (const ship of craftingDone) {
      await db.update(masterAirships).set({
        status: 'DOCKED', busyUntil: null, updatedAt: now,
      }).where(eq(masterAirships.id, ship.id));
    }

    const repairsDone = await db.select().from(masterAirships).where(and(
      eq(masterAirships.masterId, masterId),
      eq(masterAirships.status, 'REPAIRING'),
      sql`${masterAirships.busyUntil} <= ${now}`,
    ));
    for (const ship of repairsDone) {
      await db.update(masterAirships).set({
        status: 'DOCKED', hp: ship.maxHp, busyUntil: null, updatedAt: now,
      }).where(eq(masterAirships.id, ship.id));
    }
  }

  private async getPortAndFloor(masterId: string) {
    const [[world], [port]] = await Promise.all([
      db.select().from(worlds).where(eq(worlds.masterId, masterId)).limit(1),
      db.select().from(baseBuildings)
        .where(and(eq(baseBuildings.masterId, masterId), eq(baseBuildings.buildingType, 'AIRSHIP_PORT')))
        .limit(1),
    ]);
    return { clearedFloor: world?.currentFloor ?? 1, port: port ?? null };
  }

  private async getUnlockedTechSet(masterId: string): Promise<Set<string>> {
    const rows = await db.select({ code: masterAirshipTechs.techCode })
      .from(masterAirshipTechs)
      .where(eq(masterAirshipTechs.masterId, masterId));
    return new Set(rows.map(row => row.code));
  }

  private shipRects(ships: Array<typeof masterAirships.$inferSelect>): DockRect[] {
    // Ships reserve their dock footprint while DOCKED, CRAFTING, REPAIRING, or even DEPLOYED
    // so they always have a guaranteed landing berth when returning.
    return ships.map(ship => {
      const { w, h } = effectiveFootprint(ship.gridW, ship.gridH, ship.rotation);
      return { id: ship.id, x: ship.dockX, y: ship.dockY, w, h };
    });
  }

  async getPortState(masterId: string, now = new Date()) {
    await this.settle(masterId, now);
    const [{ clearedFloor, port }, unlockedTechs, ships, [master]] = await Promise.all([
      this.getPortAndFloor(masterId),
      this.getUnlockedTechSet(masterId),
      db.select().from(masterAirships).where(eq(masterAirships.masterId, masterId)).orderBy(asc(masterAirships.createdAt)),
      db.select({ silverCoins: masters.silverCoins }).from(masters).where(eq(masters.id, masterId)).limit(1),
    ]);

    const portLevel = port?.level ?? 0;
    const dock = portLevel > 0 ? computeDockDimensions(portLevel, unlockedTechs) : { width: 0, height: 0 };
    const discount = repairDiscountPct(unlockedTechs);

    return {
      unlockedByFloor: clearedFloor >= AIRSHIP_UNLOCK_FLOOR,
      clearedFloor,
      requiredFloor: AIRSHIP_UNLOCK_FLOOR,
      portBuilt: Boolean(port),
      portBuildingId: port?.id ?? null,
      portLevel,
      dock,
      visionDurationSeconds: visionDurationSeconds(unlockedTechs),
      repairDiscountPct: discount,
      silverCoins: Number(master?.silverCoins ?? 0n),
      unlockedTechs: [...unlockedTechs],
      techTree: AIRSHIP_TECH_TREE.map(node => ({
        ...node,
        unlocked: unlockedTechs.has(node.code),
        canUnlock: Boolean(port)
          && !unlockedTechs.has(node.code)
          && portLevel >= node.requiredPortLevel
          && node.prerequisites.every(req => unlockedTechs.has(req)),
      })),
      blueprints: Object.values(AIRSHIP_BLUEPRINTS).map(bp => ({
        ...bp,
        unlocked: unlockedTechs.has(bp.requiredTech),
      })),
      airships: ships.map(ship => {
        const bp = AIRSHIP_BLUEPRINTS[ship.blueprintCode as AirshipBlueprintCode];
        const stats = airshipStatsForLevel(ship.blueprintCode as AirshipBlueprintCode, ship.level);
        const { w, h } = effectiveFootprint(ship.gridW, ship.gridH, ship.rotation);
        return {
          ...ship,
          footprintW: w,
          footprintH: h,
          speedMult: stats.speedMult,
          powerBonusPct: stats.powerBonusPct,
          maxHeroes: stats.maxHeroes,
          radarRadius: stats.radarRadius,
          upgradeCostSilver: ship.level < MAX_AIRSHIP_LEVEL ? stats.upgradeCostSilver : null,
          repairCostSilver: repairCostSilver(ship.blueprintCode as AirshipBlueprintCode, ship.maxHp - ship.hp, ship.maxHp, discount),
          roleSummary: bp?.roleSummary ?? '',
          secondsRemaining: ship.busyUntil ? Math.max(0, Math.ceil((ship.busyUntil.getTime() - now.getTime()) / 1000)) : 0,
        };
      }),
    };
  }

  async unlockTech(masterId: string, techCodeInput: unknown, now = new Date()) {
    const techCode = String(techCodeInput ?? '').trim();
    const node = TECH_BY_CODE.get(techCode);
    if (!node) throw new AirshipError('Công nghệ không tồn tại.', 404);

    const { clearedFloor, port } = await this.getPortAndFloor(masterId);
    if (clearedFloor < AIRSHIP_UNLOCK_FLOOR) {
      throw new AirshipError(`Cần vượt Tháp tầng ${AIRSHIP_UNLOCK_FLOOR} để sử dụng Cảng Tàu Bay.`, 409);
    }
    if (!port) throw new AirshipError('Hãy xây dựng Bến Thiên Hành (Cảng Tàu Bay) trước.', 409);
    if (port.level < node.requiredPortLevel) {
      throw new AirshipError(`Cần Cảng Tàu Bay cấp ${node.requiredPortLevel}.`, 409);
    }

    return db.transaction(async tx => {
      const [master] = await tx.select().from(masters).where(eq(masters.id, masterId)).for('update');
      if (!master) throw new AirshipError('Không tìm thấy Master.', 404);
      const existing = await tx.select({ code: masterAirshipTechs.techCode })
        .from(masterAirshipTechs).where(eq(masterAirshipTechs.masterId, masterId));
      const unlocked = new Set(existing.map(row => row.code));
      if (unlocked.has(techCode)) throw new AirshipError('Công nghệ này đã được mở khóa.', 409);
      for (const req of node.prerequisites) {
        if (!unlocked.has(req)) {
          const reqNode = TECH_BY_CODE.get(req);
          throw new AirshipError(`Cần nghiên cứu trước: ${reqNode?.name ?? req}.`, 409);
        }
      }
      if (master.silverCoins < BigInt(node.costSilver)) {
        throw new AirshipError(`Không đủ Xu Bạc (cần ${node.costSilver}).`, 409);
      }

      await tx.update(masters).set({
        silverCoins: sql`${masters.silverCoins} - ${node.costSilver}`, updatedAt: now,
      }).where(eq(masters.id, masterId));

      await tx.insert(masterAirshipTechs).values({
        id: uuidv4(), masterId, techCode, unlockedAt: now,
      });

      return { techCode, name: node.name, silverSpent: node.costSilver };
    });
  }

  async craft(
    masterId: string,
    blueprintInput: unknown,
    options: { customName?: string; dockX?: number; dockY?: number; rotation?: number; instant?: boolean } = {},
    now = new Date(),
  ) {
    await this.settle(masterId, now);
    const code = String(blueprintInput ?? '').toUpperCase() as AirshipBlueprintCode;
    const bp = AIRSHIP_BLUEPRINTS[code];
    if (!bp) throw new AirshipError('Loại tàu bay không hợp lệ.', 400);

    const { clearedFloor, port } = await this.getPortAndFloor(masterId);
    if (clearedFloor < AIRSHIP_UNLOCK_FLOOR) {
      throw new AirshipError(`Cần vượt Tháp tầng ${AIRSHIP_UNLOCK_FLOOR} để chế tạo tàu bay.`, 409);
    }
    if (!port) throw new AirshipError('Hãy xây dựng Cảng Tàu Bay trước.', 409);

    return db.transaction(async tx => {
      const [master] = await tx.select().from(masters).where(eq(masters.id, masterId)).for('update');
      if (!master) throw new AirshipError('Không tìm thấy Master.', 404);
      const techRows = await tx.select({ code: masterAirshipTechs.techCode })
        .from(masterAirshipTechs).where(eq(masterAirshipTechs.masterId, masterId));
      const unlocked = new Set(techRows.map(row => row.code));
      if (!unlocked.has(bp.requiredTech)) {
        const techName = TECH_BY_CODE.get(bp.requiredTech)?.name ?? bp.requiredTech;
        throw new AirshipError(`Chưa mở khóa trong Cây Công Nghệ: ${techName}.`, 409);
      }

      const ships = await tx.select().from(masterAirships).where(eq(masterAirships.masterId, masterId));
      const dock = computeDockDimensions(port.level, unlocked);
      const occupied = this.shipRects(ships);

      let placed: { x: number; y: number; rotation: 0 | 90 } | null = null;
      if (Number.isInteger(options.dockX) && Number.isInteger(options.dockY)) {
        const rot: 0 | 90 = options.rotation === 90 ? 90 : 0;
        const { w, h } = effectiveFootprint(bp.gridW, bp.gridH, rot);
        if (canPlaceOnDockGrid(dock.width, dock.height, occupied, { x: options.dockX!, y: options.dockY!, w, h })) {
          placed = { x: options.dockX!, y: options.dockY!, rotation: rot };
        }
      } else {
        placed = findAutoDockPosition(dock.width, dock.height, occupied, bp.gridW, bp.gridH);
      }
      if (!placed) {
        throw new AirshipError(
          `Bãi đậu hiện tại (${dock.width}x${dock.height}) không còn khoảng trống liền kề ${bp.gridW}x${bp.gridH}. Hãy nâng cấp Cảng hoặc mở rộng diện tích trong Cây Công Nghệ.`,
          409,
        );
      }

      if (master.silverCoins < BigInt(bp.craftCostSilver)) {
        throw new AirshipError(`Không đủ Xu Bạc để chế tạo (cần ${bp.craftCostSilver}).`, 409);
      }

      await tx.update(masters).set({
        silverCoins: sql`${masters.silverCoins} - ${bp.craftCostSilver}`, updatedAt: now,
      }).where(eq(masters.id, masterId));

      const id = uuidv4();
      const name = (options.customName ?? '').trim().slice(0, 64) || `${bp.name} #${ships.length + 1}`;
      const status = options.instant ? 'DOCKED' : 'CRAFTING';
      const busyUntil = options.instant ? null : new Date(now.getTime() + bp.craftSeconds * 1000);

      const [ship] = await tx.insert(masterAirships).values({
        id,
        masterId,
        blueprintCode: bp.code,
        name,
        sizeClass: bp.sizeClass,
        gridW: bp.gridW,
        gridH: bp.gridH,
        dockX: placed.x,
        dockY: placed.y,
        rotation: placed.rotation,
        level: 1,
        hp: bp.baseMaxHp,
        maxHp: bp.baseMaxHp,
        status,
        busyUntil,
        createdAt: now,
        updatedAt: now,
      }).returning();

      return { airship: ship, silverSpent: bp.craftCostSilver, dock };
    });
  }

  async moveOnDock(masterId: string, airshipId: string, dockXInput: unknown, dockYInput: unknown, rotationInput: unknown, now = new Date()) {
    await this.settle(masterId, now);
    const dockX = Number(dockXInput);
    const dockY = Number(dockYInput);
    const rotation: 0 | 90 = Number(rotationInput) === 90 ? 90 : 0;
    if (!Number.isInteger(dockX) || !Number.isInteger(dockY)) {
      throw new AirshipError('Tọa độ bãi đậu không hợp lệ.', 400);
    }

    const { port } = await this.getPortAndFloor(masterId);
    if (!port) throw new AirshipError('Chưa có Cảng Tàu Bay.', 409);

    return db.transaction(async tx => {
      const ships = await tx.select().from(masterAirships).where(eq(masterAirships.masterId, masterId));
      const ship = ships.find(row => row.id === airshipId);
      if (!ship) throw new AirshipError('Không tìm thấy tàu bay.', 404);
      if (ship.status === 'DEPLOYED' || ship.status === 'STRANDED') {
        throw new AirshipError('Không thể di chuyển vị trí neo khi tàu đang ở ngoài bản đồ.', 409);
      }

      const techRows = await tx.select({ code: masterAirshipTechs.techCode })
        .from(masterAirshipTechs).where(eq(masterAirshipTechs.masterId, masterId));
      const dock = computeDockDimensions(port.level, techRows.map(row => row.code));
      const { w, h } = effectiveFootprint(ship.gridW, ship.gridH, rotation);
      const occupied = this.shipRects(ships);

      if (!canPlaceOnDockGrid(dock.width, dock.height, occupied, { x: dockX, y: dockY, w, h }, ship.id)) {
        throw new AirshipError('Vị trí ô bãi đậu bị trùng hoặc vượt quá kích thước sàn đậu.', 409);
      }

      const [updated] = await tx.update(masterAirships).set({
        dockX, dockY, rotation, updatedAt: now,
      }).where(eq(masterAirships.id, ship.id)).returning();

      return { airship: updated, dock };
    });
  }

  async upgrade(masterId: string, airshipId: string, now = new Date()) {
    await this.settle(masterId, now);
    return db.transaction(async tx => {
      const [master] = await tx.select().from(masters).where(eq(masters.id, masterId)).for('update');
      if (!master) throw new AirshipError('Không tìm thấy Master.', 404);
      const [ship] = await tx.select().from(masterAirships)
        .where(and(eq(masterAirships.id, airshipId), eq(masterAirships.masterId, masterId))).for('update').limit(1);
      if (!ship) throw new AirshipError('Không tìm thấy tàu bay.', 404);
      if (ship.status !== 'DOCKED') throw new AirshipError('Chỉ có thể nâng cấp khi tàu đang neo tại Cảng.', 409);
      if (ship.level >= MAX_AIRSHIP_LEVEL) throw new AirshipError(`Tàu đã đạt cấp tối đa ${MAX_AIRSHIP_LEVEL}.`, 409);

      const bpCode = ship.blueprintCode as AirshipBlueprintCode;
      const curStats = airshipStatsForLevel(bpCode, ship.level);
      const nextLevel = ship.level + 1;
      const nextStats = airshipStatsForLevel(bpCode, nextLevel);
      if (master.silverCoins < BigInt(curStats.upgradeCostSilver)) {
        throw new AirshipError(`Không đủ Xu Bạc (cần ${curStats.upgradeCostSilver}).`, 409);
      }

      await tx.update(masters).set({
        silverCoins: sql`${masters.silverCoins} - ${curStats.upgradeCostSilver}`, updatedAt: now,
      }).where(eq(masters.id, masterId));

      const hpDelta = Math.max(0, nextStats.maxHp - ship.maxHp);
      const [updated] = await tx.update(masterAirships).set({
        level: nextLevel,
        maxHp: nextStats.maxHp,
        hp: Math.min(nextStats.maxHp, ship.hp + hpDelta),
        updatedAt: now,
      }).where(eq(masterAirships.id, ship.id)).returning();

      return { airship: updated, silverSpent: curStats.upgradeCostSilver };
    });
  }

  async repair(masterId: string, airshipId: string, instant = false, now = new Date()) {
    await this.settle(masterId, now);
    return db.transaction(async tx => {
      const [master] = await tx.select().from(masters).where(eq(masters.id, masterId)).for('update');
      if (!master) throw new AirshipError('Không tìm thấy Master.', 404);
      const [ship] = await tx.select().from(masterAirships)
        .where(and(eq(masterAirships.id, airshipId), eq(masterAirships.masterId, masterId))).for('update').limit(1);
      if (!ship) throw new AirshipError('Không tìm thấy tàu bay.', 404);
      if (ship.status !== 'DOCKED') throw new AirshipError('Chỉ có thể sửa chữa khi tàu đang neo tại Cảng.', 409);
      if (ship.hp >= ship.maxHp) throw new AirshipError('Tàu bay đang ở trạng thái nguyên vẹn.', 409);

      const techRows = await tx.select({ code: masterAirshipTechs.techCode })
        .from(masterAirshipTechs).where(eq(masterAirshipTechs.masterId, masterId));
      const discount = repairDiscountPct(techRows.map(row => row.code));
      const cost = repairCostSilver(ship.blueprintCode as AirshipBlueprintCode, ship.maxHp - ship.hp, ship.maxHp, discount);
      if (master.silverCoins < BigInt(cost)) {
        throw new AirshipError(`Không đủ Xu Bạc để sửa chữa (cần ${cost}).`, 409);
      }

      await tx.update(masters).set({
        silverCoins: sql`${masters.silverCoins} - ${cost}`, updatedAt: now,
      }).where(eq(masters.id, masterId));

      const repairSeconds = Math.max(10, Math.round(30 * (1 - discount / 100)));
      const [updated] = await tx.update(masterAirships).set({
        status: instant ? 'DOCKED' : 'REPAIRING',
        hp: instant ? ship.maxHp : ship.hp,
        busyUntil: instant ? null : new Date(now.getTime() + repairSeconds * 1000),
        updatedAt: now,
      }).where(eq(masterAirships.id, ship.id)).returning();

      return { airship: updated, silverSpent: cost, repairSeconds: instant ? 0 : repairSeconds };
    });
  }

  async dismantle(masterId: string, airshipId: string, now = new Date()) {
    await this.settle(masterId, now);
    return db.transaction(async tx => {
      const [ship] = await tx.select().from(masterAirships)
        .where(and(eq(masterAirships.id, airshipId), eq(masterAirships.masterId, masterId))).for('update').limit(1);
      if (!ship) throw new AirshipError('Không tìm thấy tàu bay.', 404);
      if (ship.status !== 'DOCKED') throw new AirshipError('Chỉ có thể tháo dỡ tàu đang neo tại Cảng.', 409);

      const bp = AIRSHIP_BLUEPRINTS[ship.blueprintCode as AirshipBlueprintCode];
      const refund = Math.round((bp?.craftCostSilver ?? 1000) * 0.4);
      await tx.delete(masterAirships).where(eq(masterAirships.id, ship.id));
      await tx.update(masters).set({
        silverCoins: sql`${masters.silverCoins} + ${refund}`, updatedAt: now,
      }).where(eq(masters.id, masterId));

      return { dismantledId: ship.id, silverRefunded: refund };
    });
  }
}

export const airshipService = new AirshipService();
