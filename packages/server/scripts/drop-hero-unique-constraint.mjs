import pg from 'pg';

async function run() {
  const client = new pg.Client({ connectionString: 'postgres://postgres:postgres@localhost:5433/infinite_gacha' });
  await client.connect();

  console.log('Dropping uq_master_hero_template constraint if exists...');
  await client.query('ALTER TABLE heroes DROP CONSTRAINT IF EXISTS uq_master_hero_template;');

  // Kiểm tra lại constraints
  const res = await client.query("SELECT conname, contype FROM pg_constraint WHERE conrelid = 'heroes'::regclass;");
  console.log('Remaining heroes constraints:', res.rows);

  await client.end();
}

run().catch(console.error);
