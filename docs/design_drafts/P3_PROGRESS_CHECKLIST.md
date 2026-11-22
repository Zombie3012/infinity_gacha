# P3 Implementation Checklist

> **L?u tr? thi?t k? l?ch s?.** Checklist v? k?t qu? ki?m tra ph?n ?nh th?i ?i?m vi?t; c?c m? t? Web/Unity, pity v? duplicate c? th? ?? ???c thay th?. Xem [README hi?n h?nh](../../README.md) v? [backlog Godot](../../GODOT_BACKLOG.md), c?p nh?t 22/11/2026 (UTC+7).

## Project Context
- Scope Document: `Phase_Scope_Matrix_P3.csv` (37 functions, 7 modules, 1 domain DM-13)
- Specification Reference: `BRD_P3_Draft.md`, `Use_Case_Spec_P3_Draft.md`, `Data_Model_P3_Draft.md`, `Acceptance_Criteria_P3_Draft.md`
- Method: module by module, end to end (schema → service → routes → client → tests → migration), matching P0–P2 delivery.

## Progress Summary
- MOD-13-01 (Global World & Map Exploration): Done — 5 functions.
- MOD-13-02 (Territory Control & Expansion): Done — 5 functions.
- MOD-13-03 (Scouting & Intelligence): Done — 3 functions.
- MOD-13-04 (Hero Expeditions & Movement, replaces the army concept): Done — 5 functions.
- MOD-13-05 (PvP Combat & Territory Defense): Done — 7 functions.
- MOD-13-06 (Alliance System): Done — 6 functions.
- MOD-13-07 (World War & Conquest): Done — 6 functions.

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

## Domain 13 part three: PvP and Territory Defense

### MOD-13-05 PvP Combat & Territory Defense (7 functions)
- [x] FUN-13-05-001 Initiate Player Attack — an `ATTACK` expedition can target another Master's owned tile; the party is the attacker's Heroes.
- [x] FUN-13-05-002 Validate PvP Conditions — dispatches are refused while the tile has claim protection (`ERR_TERRITORY_PROTECTED`), while the victim holds a Novice Shield (`ERR_TARGET_SHIELDED`), against your own tile, or when the attacker is at the 10-territory cap.
- [x] FUN-13-05-003 Execute PvP Battle — on arrival the party fights the defender's five strongest Heroes with a +20% defence bonus and +10% per territory level; the outcome is deterministic per expedition seed with a ±10% swing.
- [x] FUN-13-05-004 Process PvP Result — a winning attacker takes ownership (keeping the level), gains a fresh 30-minute protection window and a tile clearance; a losing attacker returns home and the defender keeps the tile.
- [x] FUN-13-05-005 Defend Territory — `GET /api/world/tiles/:tileId/defense` exposes the garrison power, level and protection state of a tile.
- [x] FUN-13-05-006 PvP Protection — claim protection and the Novice Shield both block attacks; every capture refreshes the 30-minute window.
- [x] FUN-13-05-007 PvP Battle Report — `pvp_battles` stores winner, both powers, rounds and a JSON report; `GET /api/world/pvp/battles` lists the caller's attacks and defences.

## Domain 13 part four: Alliances and World Conquest

### MOD-13-06 Alliance System (6 functions)
- [x] FUN-13-06-001 Create Alliance — `POST /api/alliance` requires Master level 20 and charges 5,000 Gems or 500,000 Silver (Gems first); the founder becomes Leader. Names are 3–20 characters and names/tags are unique case-insensitively.
- [x] FUN-13-06-002 Search Alliance — `GET /api/alliance/search` filters by name/tag, language, minimum combat power and free slots, and marks the caller's pending request.
- [x] FUN-13-06-003 Join Alliance — `POST /api/alliance/join` opens a `PENDING` request; officers approve or reject it, and the requester can cancel (`/api/alliance/requests/:id/cancel`).
- [x] FUN-13-06-004 Leave Alliance — `POST /api/alliance/leave` starts a 24-hour re-join cooldown (`alliance_cooldowns`); a Leader with members must transfer first, while a sole Leader disbands the alliance.
- [x] FUN-13-06-005 Manage Alliance Member — approve/reject, promote/demote, kick, transfer leadership, edit the notice board, upgrade Alliance Tech (+10 member slots per level, 30 → 100, paid in Silver) and disband. Enforced by a role matrix (`alliance-rules.ts`).
- [x] FUN-13-06-006 Alliance Communication — `GET/POST /api/alliance/chat` stores text and `(x, y)` coordinate pings (0–1000) with a 300-character cap.

### MOD-13-07 World War & Conquest (6 functions)
- [x] FUN-13-07-001 Declare War — `POST /api/alliance/wars` is Leader-only, lasts 24 hours (`alliance_wars`), and refuses alliances already in an active war.
- [x] FUN-13-07-002 Manage War Progress — `GET /api/alliance/wars` and `/api/alliance/wars/:id` expose both scores, the countdown and the `war_engagements` log.
- [x] FUN-13-07-003 Territory War — winning a hero raid against a member of an enemy alliance scores 100 points for the attacker (repelled attacks score 50 for the defender); the Central Imperial Wonder at (500, 500) can be stormed with `POST /api/world/conquest/wonder/siege` during the final 3 days of a season.
- [x] FUN-13-07-004 Determine War Result — wars settle lazily at `ends_at`: higher score wins, equal scores draw. Holding the Wonder for 8 continuous hours during the contest window concludes the season and crowns the Conqueror Alliance.
- [x] FUN-13-07-005 Distribute War Reward — winner/loser war bundles are mailed, and season bundles (Silver by mail, Gems credited directly, Seven-Color scrolls into the summon inventory) are paid to the top ranks plus the Conqueror.
- [x] FUN-13-07-006 World Conquest Ranking — `GET /api/world/conquest/ranking` (optionally by `seasonId`) ranks alliances by conquest points with shared ranks, and `GET /api/world/conquest/seasons` lists concluded seasons.

### Prototype notes
- Seasons are 30 days and roll over lazily: the first read after `end_time` concludes the old season, pays its rewards and opens the next season with an unclaimed Wonder.
- Wonder siege power is the sum of the five strongest Heroes across the alliance; the defence is the guardian power (25,000) plus half of the holder's power, resolved deterministically with the PvP swing.
- `alliance_cooldowns` and `wonder_holdings` are additional tables beyond the P3 data-model draft (the draft kept the cooldown on the membership row, which is deleted on leave).
- War and season rewards are sample amounts (`conquest-rules.ts`), not approved economy balance.

---

Verification: `npm run verify` passes; 325/325 server tests (20 alliance rule tests, 17 conquest rule tests, 11-step HTTP alliance suite, 9-step HTTP conquest suite; the rest of P0–P3) and 11/11 shared tests. Migrations `0035` … `0038_clear_wong.sql` applied; `world_tiles.sample.sql` seeds 144 outer-rim tiles plus the Wonder at (500, 500).

Updated: 2026-11-04 08:18:00 UTC+7
Signed: DeepSeek Harness, project assistant
