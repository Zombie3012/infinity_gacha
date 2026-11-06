import http from 'http';
import pg from 'pg';

async function testGachaSummon() {
  const client = new pg.Client({ connectionString: 'postgres://postgres:postgres@localhost:5433/infinite_gacha' });
  await client.connect();

  const countBefore = await client.query(`
    SELECT count(*) FROM heroes h 
    JOIN masters m ON h.master_id = m.id 
    WHERE m.account_id = (SELECT id FROM accounts WHERE username = 'demo')
  `);
  console.log('Heroes in demo barracks BEFORE summon:', countBefore.rows[0].count);

  // Login
  const loginRes = await new Promise((resolve, reject) => {
    const req = http.request('http://localhost:3000/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, (res) => {
      let body = '';
      res.on('data', c => body += c);
      res.on('end', () => resolve(JSON.parse(body)));
    });
    req.on('error', reject);
    req.write(JSON.stringify({ username: 'demo', password: 'demo12345' }));
    req.end();
  });

  const token = loginRes.accessToken;

  // Triệu hồi 10 lần
  const summonRes = await new Promise((resolve, reject) => {
    const req = http.request('http://localhost:3000/api/gacha/summon', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + token,
        'Idempotency-Key': 'test-gacha-' + Date.now()
      }
    }, (res) => {
      let body = '';
      res.on('data', c => body += c);
      res.on('end', () => resolve(JSON.parse(body)));
    });
    req.on('error', reject);
    req.write(JSON.stringify({ bannerId: 'banner-001', rollCount: 10 }));
    req.end();
  });

  console.log('Summon rolls:');
  for (const r of summonRes.results) {
    console.log(`  - Roll #${r.rollNumber}: [${r.rewardType}] ${r.rewardName} (${r.rarity}★)`);
  }

  const countAfter = await client.query(`
    SELECT count(*) FROM heroes h 
    JOIN masters m ON h.master_id = m.id 
    WHERE m.account_id = (SELECT id FROM accounts WHERE username = 'demo')
  `);
  console.log('Heroes in demo barracks AFTER summon:', countAfter.rows[0].count);

  // Hiển thị 5 hero mới nhất trong DB
  const latestHeroes = await client.query(`
    SELECT h.name, h.rarity, h.class_code, h.base_str, h.base_int, h.base_sta, h.base_agi,
           (h.base_str + h.base_int + h.base_sta + h.base_agi) as total_base,
           h.created_at
    FROM heroes h
    JOIN masters m ON h.master_id = m.id
    WHERE m.account_id = (SELECT id FROM accounts WHERE username = 'demo')
    ORDER BY h.created_at DESC
    LIMIT 6
  `);
  console.log('\nLatest heroes generated with random base stats:');
  console.table(latestHeroes.rows);

  await client.end();
}

testGachaSummon().catch(console.error);
