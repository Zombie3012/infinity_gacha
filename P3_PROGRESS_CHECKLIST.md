# P3 Implementation Checklist

## Project Context
- Scope Document: `Phase_Scope_Matrix_P3.csv` (37 functions, 7 modules, 1 domain DM-13)
- Specification Reference: `BRD_P3_Draft.md`, `Use_Case_Spec_P3_Draft.md`, `Data_Model_P3_Draft.md`, `Acceptance_Criteria_P3_Draft.md`
- Method: module by module, end to end (schema → service → routes → client → tests → migration), matching P0–P2 delivery.

## Progress Summary
- MOD-13-01 (Global World & Map Exploration): Done — 5 functions.
- MOD-13-02 (Territory Control & Expansion): Done — 5 functions.
- MOD-13-03 (Scouting & Intelligence): Done — 3 functions.
- MOD-13-04 (Hero Expeditions & Movement, replaces the army concept): Done — 5 functions.
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

### Design correction (owner decision, 2026-11-04)
- **There is no army entity.** Heroes are the only mobile unit: they personally scout and attack tiles. The former "army management" module is implemented as **hero expeditions** (`hero_expeditions`, `expedition_members`).
- Claiming a tile now requires a **won hero attack** (`tile_clearances`) instead of a passive combat-power comparison.

### Prototype notes
- The map is a seeded 12×12 Outer Rim grid (`world_tiles.sample.sql`); hostile PvP capture arrives with MOD-13-05.
- Guardian battles resolve deterministically from party combat power vs the tile guardian (and half of the defender's power), not through the full round combat engine.
- Territory yield is reported per hour and not yet auto-harvested into the warehouse.

## Domain 13 part two: Scouting and Hero Expeditions

### MOD-13-03 Scouting & Intelligence (3 functions)
- [x] FUN-13-03-001 Scout Player — a SCOUT expedition reports the tile owner, their level and the defender Hero count/power.
- [x] FUN-13-03-002 Scout Territory — the report includes terrain, resource type, guardian power and the party's own power.
- [x] FUN-13-03-003 View Scouting Report — `GET /api/world/expeditions` exposes each report (`result.kind = SCOUT_REPORT`) with its countdown.

### MOD-13-04 Hero Expeditions & Movement (5 functions)
- [x] FUN-13-04-001 Create Expedition — `POST /api/world/expeditions` with 1–5 idle Heroes and a SCOUT/ATTACK mission.
- [x] FUN-13-04-002 Assign Hero — the party is validated (ownership, alive, 1–5 slots, no duplicates); a Hero can only be in one active expedition (`ERR_EXPEDITION_HERO_BUSY`).
- [x] FUN-13-04-003 Deploy Expedition — travel is 30s per tile; status flows TRAVELING → RETURNING → COMPLETED.
- [x] FUN-13-04-004 Recall Expedition — `POST /api/world/expeditions/:id/recall` returns the party immediately.
- [x] FUN-13-04-005 Track Movement — the expedition list reports phase and remaining seconds; `GET /api/world/heroes/away` lists Heroes currently away.

---

Verification: `npm run verify` passes; 237/237 server tests (8 world rules + 10 world HTTP tests added) and 11/11 shared tests. Migration `0035_aberrant_tony_stark.sql` applied; `world_tiles.sample.sql` seeded (144 tiles).

Updated: 2026-11-04 13:20:00 UTC+7
Signed: DeepSeek Harness, project assistant
