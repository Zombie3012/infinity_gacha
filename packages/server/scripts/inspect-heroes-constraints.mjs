import pg from 'pg';

const client = new pg.Client({ connectionString: 'postgres://postgres:postgres@localhost:5433/infinite_gacha' });
await client.connect();
const res = await client.query("SELECT conname, contype FROM pg_constraint WHERE conrelid = 'heroes'::regclass;");
console.log('Heroes constraints:', res.rows);
await client.end();
