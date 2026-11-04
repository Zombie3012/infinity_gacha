#!/usr/bin/env node
/**
 * Apply the sample seed files in dependency-safe order.
 *
 * Used by CI and by `npm run db:seed`. Every seed is written with ON CONFLICT
 * upserts, so running it twice is safe.
 */
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import pg from 'pg';

const SEED_ORDER = [
  'hero_templates.sample.sql',
  'hero_level_configs.sample.sql',
  'hero_development_configs.sample.sql',
  'hero_skill_templates.sample.sql',
  'master_level_configs.sample.sql',
  'master_skills.sample.sql',
  'feature_unlocks.sample.sql',
  'equipment_templates.sample.sql',
  'enemy_templates.sample.sql',
  'dungeon_events.sample.sql',
  'banner_001.sample.sql',
  'item_templates.sample.sql',
  'shop_items.sample.sql',
  'crafting_recipes.sample.sql',
  'iap_products.sample.sql',
  'building_types.sample.sql',
  'quests.sample.sql',
  'liveops_events.sample.sql',
  'world_tiles.sample.sql',
];

const seedDirectory = join(process.cwd(), 'packages', 'server', 'src', 'database', 'seeds');
const url = process.env.DATABASE_URL ?? 'postgres://postgres:postgres@localhost:5433/infinite_gacha';

const present = readdirSync(seedDirectory).filter(file => file.endsWith('.sql'));
const unknown = present.filter(file => !SEED_ORDER.includes(file));
if (unknown.length > 0) {
  console.warn(`[seed] files not in the ordered list (run manually): ${unknown.join(', ')}`);
}

const client = new pg.Client({ connectionString: url });
await client.connect();

let applied = 0;
try {
  for (const file of SEED_ORDER) {
    const sql = readFileSync(join(seedDirectory, file), 'utf8').replace(/^\uFEFF/, '');
    try {
      await client.query(sql);
      applied += 1;
      console.log(`[seed] ok   ${file}`);
    } catch (error) {
      console.error(`[seed] FAIL ${file}: ${error.message}`);
      throw error;
    }
  }
  console.log(`[seed] applied ${applied} seed file(s)`);
} finally {
  await client.end();
}
