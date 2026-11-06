import pg from 'pg';
import { v4 as uuidv4 } from 'uuid';

async function updatePool() {
  const client = new pg.Client({ connectionString: 'postgres://postgres:postgres@localhost:5433/infinite_gacha' });
  await client.connect();

  const bannerId = 'banner-001';

  // Lấy toàn bộ templates
  const templates = await client.query('SELECT code, name, default_rarity FROM hero_templates ORDER BY default_rarity ASC, code ASC');
  console.log(`Found ${templates.rows.length} hero templates in DB.`);

  for (const t of templates.rows) {
    const rarity = t.default_rarity;
    const poolGroup = rarity >= 5 ? 'FIVE_STAR_HERO' : 'OTHER_HERO';
    const rewardId = t.code;
    const rewardName = t.name;

    await client.query(`
      INSERT INTO summon_reward_pool (
        id, banner_id, reward_id, reward_name, reward_type, pool_group, hero_template_code, rarity, weight, is_active
      ) VALUES (
        $1, $2, $3, $4, 'HERO', $5, $6, $7, 1, TRUE
      )
      ON CONFLICT (banner_id, reward_id, pool_group) DO UPDATE SET
        reward_name = EXCLUDED.reward_name,
        reward_type = EXCLUDED.reward_type,
        hero_template_code = EXCLUDED.hero_template_code,
        rarity = EXCLUDED.rarity,
        weight = EXCLUDED.weight,
        is_active = TRUE;
    `, [uuidv4(), bannerId, rewardId, rewardName, poolGroup, t.code, rarity]);
  }

  const poolSummary = await client.query(`
    SELECT pool_group, count(*) 
    FROM summon_reward_pool 
    WHERE banner_id = $1 AND is_active = TRUE 
    GROUP BY pool_group
  `, [bannerId]);
  console.log('Updated pool summary for banner-001:', poolSummary.rows);

  await client.end();
}

updatePool().catch(console.error);
