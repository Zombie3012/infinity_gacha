-- 0063: Support GARRISON (Tập kết / Đồn trú) mission and GARRISONED status on hero_expeditions

ALTER TABLE "hero_expeditions" DROP CONSTRAINT IF EXISTS "expedition_mission_check";
ALTER TABLE "hero_expeditions" ADD CONSTRAINT "expedition_mission_check"
  CHECK ("mission" IN ('SCOUT', 'ATTACK', 'DUNGEON', 'RESCUE', 'GARRISON'));

ALTER TABLE "hero_expeditions" DROP CONSTRAINT IF EXISTS "expedition_status_check";
ALTER TABLE "hero_expeditions" ADD CONSTRAINT "expedition_status_check"
  CHECK ("status" IN ('TRAVELING', 'RETURNING', 'GARRISONED', 'STRANDED', 'COMPLETED', 'RECALLED'));
