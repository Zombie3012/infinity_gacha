#!/usr/bin/env node
/**
 * Combat v2 reset helper.
 *
 * Deletes every Hero of one demo account so summoning can regenerate them with
 * the new base-stat/class model. Cascade rules remove skills, affinities,
 * expeditions and training rows. Pass a username as the first argument:
 *
 *   npm run db:reset-heroes            # defaults to "demo"
 *   npm run db:reset-heroes -- alice
 */
import pg from 'pg';

const username = process.argv[2] ?? 'demo';
const url = process.env.DATABASE_URL ?? 'postgres://postgres:postgres@localhost:5433/infinite_gacha';
const pool = new pg.Pool({ connectionString: url });

try {
  const masters = await pool.query(
    `select m.id, a.username from masters m join accounts a on a.id = m.account_id where a.username = $1`,
    [username],
  );
  if (masters.rowCount === 0) {
    console.log(`[reset-heroes] no Master found for account "${username}"`);
  } else {
    const ids = masters.rows.map(row => row.id);
    const deleted = await pool.query('delete from heroes where master_id = any($1::varchar[])', [ids]);
    console.log(`[reset-heroes] deleted ${deleted.rowCount} Hero(es) for "${username}"`);
  }
} finally {
  await pool.end();
}
