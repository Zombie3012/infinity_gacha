-- P2 LiveOps sample event (active window relative to install time).
INSERT INTO live_events (id, code, name, description, event_type, status, start_at, end_at, claim_deadline, activated_at)
VALUES (
  '11111111-2222-4333-8444-555555555555',
  'EVENT_HARVEST_2026',
  'Mùa Thu Hoạch',
  'Sự kiện tiêu chuẩn 14 ngày: chiến đấu, chế tạo và thu thập để nhận thưởng.',
  'STANDARD',
  'ACTIVE',
  now() - interval '7 days',
  now() + interval '7 days',
  now() + interval '9 days',
  now() - interval '7 days'
)
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  status = EXCLUDED.status,
  start_at = EXCLUDED.start_at,
  end_at = EXCLUDED.end_at,
  claim_deadline = EXCLUDED.claim_deadline;

INSERT INTO event_missions (id, event_id, code, name, objective_type, target_count, reward, sort_order)
VALUES
  ('21111111-2222-4333-8444-555555555551', '11111111-2222-4333-8444-555555555555', 'EV_WIN_3', 'Thắng 3 trận Dungeon', 'WIN_BATTLE', 3, '{"silver":3000,"items":[{"itemId":"FOOD","quantity":5}]}'::jsonb, 10),
  ('21111111-2222-4333-8444-555555555552', '11111111-2222-4333-8444-555555555555', 'EV_CLEAR_2', 'Vượt 2 tầng Dungeon', 'CLEAR_FLOOR', 2, '{"gems":50}'::jsonb, 20),
  ('21111111-2222-4333-8444-555555555553', '11111111-2222-4333-8444-555555555555', 'EV_CRAFT_2', 'Chế tạo 2 trang bị', 'CRAFT_ITEM', 2, '{"items":[{"itemId":"ENHANCEMENT_STONE","quantity":5}]}'::jsonb, 30)
ON CONFLICT (event_id, code) DO UPDATE SET
  name = EXCLUDED.name,
  objective_type = EXCLUDED.objective_type,
  target_count = EXCLUDED.target_count,
  reward = EXCLUDED.reward,
  sort_order = EXCLUDED.sort_order;
