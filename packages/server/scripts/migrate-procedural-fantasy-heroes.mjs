import pg from 'pg';
import { generateFantasyHeroName } from '../../shared/dist/combat/generation.js';

async function run() {
  const client = new pg.Client({ connectionString: 'postgres://postgres:postgres@localhost:5433/infinite_gacha' });
  await client.connect();

  console.log('1. Dropping foreign key constraint heroes_config_id_hero_templates_code_fk if exists...');
  await client.query('ALTER TABLE heroes DROP CONSTRAINT IF EXISTS heroes_config_id_hero_templates_code_fk;');

  const constraints = await client.query("SELECT conname, contype FROM pg_constraint WHERE conrelid = 'heroes'::regclass;");
  console.log('Remaining constraints on heroes:', constraints.rows);

  // 2. Rename existing demo heroes that still have generic template names into unique Fantasy names
  const demoHeroes = await client.query(`
    SELECT h.id, h.name, h.rarity, h.category, h.config_id
    FROM heroes h
    JOIN masters m ON h.master_id = m.id
    WHERE m.account_id = (SELECT id FROM accounts WHERE username = 'demo')
    ORDER BY h.created_at ASC
  `);

  const usedNames = new Set();
  for (const h of demoHeroes.rows) {
    let fantasyName = generateFantasyHeroName();
    while (usedNames.has(fantasyName)) {
      fantasyName = generateFantasyHeroName();
    }
    usedNames.add(fantasyName);
    const newConfigId = `PROCEDURAL_${h.rarity}S`;
    await client.query('UPDATE heroes SET name = $1, config_id = $2 WHERE id = $3', [fantasyName, newConfigId, h.id]);
    console.log(`  Renamed [${h.rarity}★] "${h.name}" -> "${fantasyName}" (${newConfigId})`);
  }

  await client.end();
}

run().catch(console.error);
