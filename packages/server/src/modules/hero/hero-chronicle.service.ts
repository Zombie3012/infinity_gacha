import { and, desc, eq, sql } from 'drizzle-orm';
import { db } from '../../database/db.js';
import { heroChronicles, masterItems } from '../../database/drizzle-schema.js';
import { MedicalError, medicalService } from '../medical/medical.service.js';
import { RESURRECTION_GEM_ITEM } from '../medical/medical-rules.js';

export const heroChronicleService = {
  async list(masterId: string, status: string, page = 1) {
    const filter = and(eq(heroChronicles.masterId, masterId),
      ['ALIVE', 'DEAD', 'SACRIFICED'].includes(status) ? eq(heroChronicles.status, status) : undefined);
    const safePage = Number.isFinite(page) ? Math.max(1, Math.floor(page)) : 1;
    const [rows, [count], [gem]] = await Promise.all([
      db.select().from(heroChronicles).where(filter)
        .orderBy(desc(heroChronicles.summonedAt), desc(heroChronicles.id)).limit(50).offset((safePage - 1) * 50),
      db.select({ total: sql<number>`count(*)::int` }).from(heroChronicles).where(filter),
      db.select({ quantity: masterItems.quantity }).from(masterItems)
        .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, RESURRECTION_GEM_ITEM))),
    ]);
    return { records: rows, total: count.total, page: safePage, pageSize: 50,
      resurrectionGem: { itemId: RESURRECTION_GEM_ITEM, rarity: 7, quantity: gem?.quantity ?? 0, required: 1, hpPercent: 100 } };
  },
  async detail(masterId: string, id: string) {
    const [record] = await db.select().from(heroChronicles)
      .where(and(eq(heroChronicles.id, id), eq(heroChronicles.masterId, masterId))).limit(1);
    if (!record) throw new MedicalError('Không tìm thấy hồ sơ Hero.', 404);
    return record;
  },
  async resurrect(masterId: string, id: string) {
    const record = await this.detail(masterId, id);
    if (record.status !== 'DEAD' || !record.heroId) throw new MedicalError('Hồ sơ này không có Hero tử trận có thể hồi sinh.', 409);
    return medicalService.resurrect(masterId, record.heroId);
  },
};
