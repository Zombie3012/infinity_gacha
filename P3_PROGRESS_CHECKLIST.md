# P3 Implementation Checklist

## Project Context
- Scope Document: `Phase_Scope_Matrix_P3.csv` (37 functions, 7 modules, 1 domain DM-13)
- Specification Reference: `BRD_P3_Draft.md`, `Use_Case_Spec_P3_Draft.md`, `Data_Model_P3_Draft.md`, `Acceptance_Criteria_P3_Draft.md`
- Method: module by module, end to end (schema → service → routes → client → tests → migration), matching P0–P2 delivery.

## Progress Summary
- MOD-13-01 (Global World & Map Exploration): Done — 5 functions.
- MOD-13-02 (Territory Control & Expansion): Done — 5 functions.
- MOD-13-03 (Scouting & Intelligence): Not started (3).
- MOD-13-04 (Army Management & Movement): Not started (5).
- MOD-13-05 (PvP Combat & Territory Defense): Not started (7).
- MOD-13-06 (Alliance System): Not started (6).
- MOD-13-07 (World War & Conquest): Not started (6).

---

## Domain 13 part one: Global World and Territories

### MOD-13-01 Global World & Map Exploration (5 functions)
- [x] FUN-13-01-001 Unlock Global World — `POST /api/world/global/unlock` requires Master level 15 and dungeon floor 10 (scenario P3-01), assigns a deterministic random Outer Rim base tile, a 48h Novice Shield and reveals the 5-tile radius.
- [x] FUN-13-01-002 View Global Map — `GET /api/world/global/map` returns every tile with owner, terrain, resource and the caller's discovery state.
- [x] FUN-13-01-003 View Region — `GET /api/world/global/tiles/:id` adds discovery flags and the claim eligibility of one tile.
- [x] FUN-13-01-004 Discover Region — `POST /api/world/global/tiles/:id/discover` enforces the radius/adjacency rule (`ERR_WORLD_TILE_OUT_OF_RANGE`).
- [x] FUN-13-01-005 Global World Progress — `GET /api/world/global` reports unlock state, eligibility reason, shield, discovered tiles and territory usage.

### MOD-13-02 Territory Control & Expansion (5 functions)
- [x] FUN-13-02-001 View Territory — `GET /api/world/territories` lists owned/abandoning territories with hourly yield and the 10-slot cap.
- [x] FUN-13-02-002 Claim Territory — `POST /api/world/global/tiles/:id/claim` requires discovery, an expired Novice Shield, enough combat power, 2,000 Silver and a free slot; grants a 30-minute protection window and records an event.
- [x] FUN-13-02-003 Upgrade Territory — `POST /api/world/territories/:id/upgrade` costs 1,500 × current level, caps at level 5 and raises yield by 50% per level.
- [x] FUN-13-02-004 Abandon Territory — `POST /api/world/territories/:id/abandon` starts a 10-minute countdown; the tile is released lazily and ownership drops.
- [x] FUN-13-02-005 Track Territory Ownership — `GET /api/world/territories/history` returns claim/upgrade/abandon/release events, plus `GET /api/world/leaderboard` ranks owners by tile count.

### Prototype notes
- The map is a seeded 12×12 Outer Rim grid (`world_tiles.sample.sql`); hostile PvP capture arrives with MOD-13-05.
- Guardian combat for a claim is abstracted into a combat-power check (`requiredPower`) instead of a live battle.
- Territory yield is reported per hour and not yet auto-harvested into the warehouse.

---

Verification: `npm run verify` passes; 237/237 server tests (8 world rules + 10 world HTTP tests added) and 11/11 shared tests. Migration `0035_aberrant_tony_stark.sql` applied; `world_tiles.sample.sql` seeded (144 tiles).

Updated: 2026-11-04 13:20:00 UTC+7
Signed: DeepSeek Harness, project assistant
