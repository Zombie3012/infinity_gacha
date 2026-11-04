import { asc, eq } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import {
  enemyTemplates, heroSkillTemplates, heroTemplates, itemTemplates,
} from '../../database/drizzle-schema.js';
import { isValidContentCode } from './admin-rules.js';

export class ContentAdminError extends Error {
  constructor(message: string, readonly statusCode = 400) {
    super(message);
    this.name = 'ContentAdminError';
  }
}

const positive = (value: unknown, field: string): number => {
  const parsed = Math.floor(Number(value));
  if (!Number.isFinite(parsed) || parsed < 0) throw new ContentAdminError(`${field} phải là số không âm.`);
  return parsed;
};

const code = (value: unknown): string => {
  const normalized = String(value ?? '').trim().toUpperCase();
  if (!isValidContentCode(normalized)) throw new ContentAdminError('code phải là chữ in hoa/số/underscore (2–50).');
  return normalized;
};

export class ContentAdminService {
  async listHeroes() {
    return db.select().from(heroTemplates).orderBy(asc(heroTemplates.code));
  }

  /** FUN-14-02-001/002: create or update a Hero template, stats included. */
  async upsertHero(input: Record<string, unknown>) {
    const heroCode = code(input.code);
    const name = String(input.name ?? '').trim();
    if (!name || name.length > 100) throw new ContentAdminError('name phải từ 1–100 ký tự.');
    const rarity = Math.max(1, Math.min(5, positive(input.rarity ?? input.defaultRarity, 'rarity')));
    const heroClass = String(input.heroClass ?? 'WARRIOR').toUpperCase();
    if (!['WARRIOR', 'MAGE', 'ARCHER', 'ASSASSIN', 'PRIEST', 'TANK'].includes(heroClass)) {
      throw new ContentAdminError('heroClass không hợp lệ.');
    }
    const element = String(input.element ?? 'EARTH').toUpperCase();
    if (!['FIRE', 'WATER', 'EARTH', 'WIND', 'LIGHT', 'DARK'].includes(element)) throw new ContentAdminError('element không hợp lệ.');

    const values = {
      name, defaultRarity: rarity, heroClass, element,
      baseHp: positive(input.baseHp ?? 100, 'baseHp'),
      baseAttack: positive(input.baseAttack ?? input.baseAtk ?? 10, 'baseAttack'),
      baseDefense: positive(input.baseDefense ?? input.baseDef ?? 5, 'baseDefense'),
      baseSpeed: positive(input.baseSpeed ?? input.baseSpd ?? 5, 'baseSpeed'),
    };

    const updated = await db.update(heroTemplates).set(values).where(eq(heroTemplates.code, heroCode))
      .returning();
    if (updated.length > 0) return updated[0];
    const [created] = await db.insert(heroTemplates).values({ id: uuidv4(), code: heroCode, ...values }).returning();
    return created;
  }

  /** FUN-14-02-002: stats-only hotfix endpoint. */
  async updateHeroStats(heroCode: string, input: Record<string, unknown>) {
    const values: Record<string, number> = {};
    for (const field of ['baseHp', 'baseAttack', 'baseDefense', 'baseSpeed'] as const) {
      const raw = input[field] ?? input[field.replace('baseA', 'baseA')];
      if (raw === undefined) continue;
      values[field] = positive(raw, field);
    }
    if (Object.keys(values).length === 0) throw new ContentAdminError('Không có chỉ số nào được cung cấp.');
    const [updated] = await db.update(heroTemplates).set(values).where(eq(heroTemplates.code, heroCode.toUpperCase())).returning();
    if (!updated) throw new ContentAdminError('Hero template không tồn tại.', 404);
    return updated;
  }

  async listHeroSkills() {
    return db.select().from(heroSkillTemplates).orderBy(asc(heroSkillTemplates.code));
  }

  async upsertHeroSkill(input: Record<string, unknown>) {
    const skillCode = code(input.code);
    const values = {
      heroClass: String(input.heroClass ?? 'WARRIOR').toUpperCase(),
      name: String(input.name ?? skillCode).slice(0, 100),
      description: String(input.description ?? '').slice(0, 500),
      effectType: String(input.effectType ?? 'DAMAGE_SINGLE').toUpperCase(),
      effectValue: Number(input.effectValue ?? 1),
      upgradeIncrement: Number(input.upgradeIncrement ?? 0.1),
      cooldownSeconds: positive(input.cooldownSeconds ?? 3, 'cooldownSeconds'),
      unlockLevel: Math.max(1, positive(input.unlockLevel ?? 3, 'unlockLevel')),
      maxLevel: Math.max(1, positive(input.maxLevel ?? 5, 'maxLevel')),
      isActive: input.isActive !== false,
    };
    if (!Number.isFinite(values.effectValue)) throw new ContentAdminError('effectValue không hợp lệ.');
    const updated = await db.update(heroSkillTemplates).set(values).where(eq(heroSkillTemplates.code, skillCode)).returning();
    if (updated.length > 0) return updated[0];
    const [created] = await db.insert(heroSkillTemplates).values({ code: skillCode, ...values }).returning();
    return created;
  }

  async listEnemies(bossOnly: boolean) {
    const rows = await db.select().from(enemyTemplates).orderBy(asc(enemyTemplates.code));
    return bossOnly ? rows.filter(row => row.isBoss) : rows;
  }

  /** FUN-14-02-004/005: monsters and bosses share one catalogue via `isBoss`. */
  async upsertEnemy(input: Record<string, unknown>) {
    const enemyCode = code(input.code);
    const values = {
      name: String(input.name ?? enemyCode).slice(0, 100),
      baseHp: positive(input.baseHp ?? 100, 'baseHp'),
      baseAttack: positive(input.baseAttack ?? input.baseAtk ?? 10, 'baseAttack'),
      baseDefense: positive(input.baseDefense ?? input.baseDef ?? 5, 'baseDefense'),
      baseSpeed: positive(input.baseSpeed ?? input.baseSpd ?? 5, 'baseSpeed'),
      baseExpReward: positive(input.baseExpReward ?? 10, 'baseExpReward'),
      baseSilverReward: positive(input.baseSilverReward ?? 10, 'baseSilverReward'),
      isActive: input.isActive !== false,
      isBoss: input.isBoss === true,
    };
    const updated = await db.update(enemyTemplates).set(values).where(eq(enemyTemplates.code, enemyCode)).returning();
    if (updated.length > 0) return updated[0];
    const [created] = await db.insert(enemyTemplates).values({ id: uuidv4(), code: enemyCode, ...values }).returning();
    return created;
  }

  async listItems() {
    return db.select().from(itemTemplates).orderBy(asc(itemTemplates.code));
  }

  /** FUN-14-02-006: item catalogue used by shop, crafting and rewards. */
  async upsertItem(input: Record<string, unknown>) {
    const itemCode = code(input.code);
    const values = {
      name: String(input.name ?? itemCode).slice(0, 100),
      category: String(input.category ?? 'MATERIAL').toUpperCase().slice(0, 30),
      rarity: Math.max(1, Math.min(5, positive(input.rarity ?? 1, 'rarity'))),
      description: String(input.description ?? '').slice(0, 500),
      isActive: input.isActive !== false,
    };
    const updated = await db.update(itemTemplates).set(values).where(eq(itemTemplates.code, itemCode)).returning();
    if (updated.length > 0) return updated[0];
    const [created] = await db.insert(itemTemplates).values({ code: itemCode, ...values }).returning();
    return created;
  }
}

export const contentAdminService = new ContentAdminService();
