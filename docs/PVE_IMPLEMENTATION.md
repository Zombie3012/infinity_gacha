# PvE map: implementation and verification

Approved from `thaoluan.md` and the implementation plan, 2026-11-22 (UTC+7). The loop is **explore → command several squads → auto battle → collect → defeat boss → enter next floor**.

## Rules implemented

- Private, persisted 12×12 map per World/floor. Algorithm `pve:v1` uses the existing World Seed in a separate namespace. Legacy dungeon/PvP generation and expedition travel times remain independent.
- Camp, ordinary cells, 18 resource nodes, 18 enemy nodes and one boss. No impassable terrain in v1: every boss is reachable. The first two steps from camp are safe.
- At most three deployed parties, each 1–5 distinct Heroes. Positions 0–8 are saved separately from five-member party membership. Row zero faces the opponent; empty positions confer no stats.
- Four-way movement takes one second per cell. Paths cross discovered cells and may finish on one adjacent unknown frontier cell. Occupied cells and their four neighbors are revealed. Redirecting onto the same next step preserves its ETA.
- Per-squad auto exploration chooses nearby unvisited discovered cells, collects resources and resolves enemies/boss automatically. It stops on defeat, draw or exhaustion; manual movement disables auto. The first surviving party member is the leader displayed on the map.
- A resource is collected once. An uncleared enemy stops the route and automatically resolves Combat v2. Survivors may retry a loss/draw by ordering their occupied enemy cell again.
- Tactics: FRONTLINE (default), LOWEST_HP (HP percentage), HIGHEST_ATK (greater physical/magic attack), and per-Hero skill preferences. Unready skills are skipped; healing skips when no ally needs HP. Evaded skills still consume MP/cooldown; basic attacks restore MP even when evaded.
- Deployment freezes membership, positions and tactics. Full Hero/enemy combat inputs, combat version and RNG seed are captured server-side when an encounter starts. Clients cannot supply enemies, seeds or results.
- AGI-ordered combat has a 30-round PvE limit. Both sides surviving means DRAW. Reports include initial/final HP/MP and positions; lethal damage precedes revival.
- Normal Heroes die permanently and drop equipped gear on the actual floor. Special/Limited become DISABLED and keep gear. Death removes party membership and the fallen Hero's reservation. Survivors retain HP/MP, EXP and existing level caps.
- Deployment atomically charges 10 FOOD/Hero and refuses insufficient stock. Exhaustion pauses that squad. Recall releases Heroes; redeployment incurs a new ration charge.
- Only boss victory clears the map and advances the World floor once. Remaining nodes need not be cleared. Surviving squads are withdrawn and routes cancelled. The player explicitly enters the next floor.

## State and transactions

```mermaid
stateDiagram-v2
    [*] --> IDLE: deploy and reserve Heroes
    IDLE --> MOVING: move order
    MOVING --> MOVING: next cell due
    MOVING --> IDLE: route ends or exhaustion
    MOVING --> FIGHTING: uncleared encounter
    FIGHTING --> IDLE: at least one survivor
    FIGHTING --> DEFEATED: no survivors
    IDLE --> WITHDRAWN: recall or boss victory
    MOVING --> WITHDRAWN: recall or boss victory
    WITHDRAWN --> [*]
    DEFEATED --> [*]
```

`FIGHTING` is transaction-local in this prototype: the engine settles the full encounter immediately. Replay duration does not prolong combat, pause other squads or determine rewards. Commands wait for the short database transaction, not the animation.

Every command/map read locks the Master first, reads PostgreSQL time and settles due arrivals chronologically by arrival time then squad ID. Routes and timestamps persist in PostgreSQL. Offline progress settles on the next read/command without Redis or background timers. A complete catch-up is bounded by three simple paths through 144 cells.

Encounter report, wallet/ledger, EXP/levels, HP/MP, death/gear drops, injuries, node clearance, quest/event progress and boss advancement share one transaction. A failed reward write rolls the encounter back; a later read retries it. Two API processes use the same database locks.

Every mutation requires an `Idempotency-Key`: 1–80 printable ASCII characters without spaces, unique per Master. Its operation/path and canonical body hash must match. Committed keys replay the saved result after restart; changed requests return 409. Failed transactions leave no key record. Reads/replays need no key.

Reservations guard legacy equipment, membership, skill/imprint/affinity/subclass changes, work, treatment, expedition assignment and Hero mutation/deletion. Passive survival reads serialize with combat, preserving battle fatigue. Deployed Heroes cannot receive base feeding/rest orders. Medical completion restores display HP and v2 HP percentages together; concurrent resurrection charges once.

Hero star promotion uses the same Master-before-Hero lock order. Breakthrough reads its spendable Silver after acquiring the Master lock, preventing an idle Hero's development from overwriting a concurrently credited PvE reward. A controlled PostgreSQL lock-queue test reproduced the lost reward before this fix and passes after it.

## Persistence and compatibility

| Table | Purpose |
|---|---|
| `pve_maps` | Layout/catalogue snapshot, discovered/cleared/collected IDs, floor status, revision |
| `pve_party_plans` | Positions, targeting and skill preferences for an existing party |
| `pve_squads` | Frozen deployment, position, route, ETA, status and last report |
| `pve_hero_reservations` | Exclusive Hero ownership while deployed |
| `pve_battles` | Immutable report and committed settlement |
| `pve_commands` | Idempotency request hash and saved result |
| `pve_events` | Ordered map revisions for polling |

Migrations 0045–0048 add these tables, guards, query indexes and auto mode. Old migration history, APIs and stored data remain. Completed `combat_sessions` preserve the death-record FK and server-only encounter inputs; map encounters do not use ACTIVE legacy sessions. Active legacy dungeon/combat blocks map entry; an ACTIVE map blocks legacy dungeon/combat start. Deleting a withdrawn party preserves squad/report history through a nullable party reference.

Migration 0046 marks the existing active `SAMPLE_STONE_GOLEM` as a boss only when no active boss is configured. It does not reset configured enemies or re-seed player data.

The local development DB `infinite_gacha` was backed up and migrated through 0047. Counts remained **2 accounts, 190 Heroes and 2 Worlds**, with no maps created for existing players. Backup: `logs/infinite-gacha-before-pve.dump`, archive verified (491 entries). Restoring it to a temporary audit DB confirmed that **93 legacy tables** match by row count/content checksum; the documented enemy boss flag is the only excluded field. Audit: `logs/pve-migration-data-audit.json`. No commit or deployment was performed.

## API and Godot

Detailed requests/responses: [OpenAPI PvE](../openapi.pve.yaml). All routes: [API_Routes.md](../API_Routes.md).

- `GET /api/pve/state`: settle arrivals and return masked map, squads, parties and up to 100 events.
- `POST /api/pve/enter`: explicitly enter the current floor.
- `POST /api/pve/parties`, `PUT /api/pve/parties/:partyId`: atomic name/membership/plan save, including repairing empty parties.
- `PUT /api/pve/parties/:partyId/plan`: positions/tactics only.
- `POST /api/pve/parties/:partyId/deploy`: rations, frozen plan and reservations.
- `POST /api/pve/squads/:squadId/move`, `/recall` or `/auto`: manual movement/retry, withdrawal or auto exploration.
- `GET /api/pve/battles` and `/api/pve/battles/:battleId`: owned history and immutable reports.

Send both `mapId` and the returned event `cursor` on subsequent reads. Cursors for another map reset. Keep paging after 100 events. Battle history has a separate `before` cursor and page size 1–50. `/api/heroes` includes `pveDeployment` or null for base availability.

The **Chinh phạt** portal opens `scenes/pve/pve_map.tscn`. `PveState` polls about every second while map/replay is open. ETA uses server time plus a monotonic elapsed timer. Pending keys/bodies are written before HTTP, never tokens; retries reuse them after timeout/restart. Account changes isolate pending files and discard stale responses. Controls remain locked until the post-command snapshot is refreshed.

The editor preserves drafts after errors and offers retry for ambiguous writes. Long skill lists scroll. The 3D arena reads saved reports, displays two nine-cell formations, replay speed and dynamic camera, with no simulation/demo fallback. Base pickers/cards and food/rest facilities reflect deployed Heroes.

## Verification

Use a disposable DB with all migrations and 23 seeds. Tests create/delete their own accounts.

```powershell
$env:DATABASE_URL='postgres://postgres:postgres@localhost:5433/infinite_gacha_pve_verify_test'
npm run verify
$env:GODOT_BIN='C:\path\to\godot_console.exe'
npm run test:godot:pve
npm run test:godot:pve -- --integration
npm run test:godot:pve:recovery
npm run docs:routes
```

| Requirement | Evidence |
|---|---|
| Same seed/floor, reachable boss, four-way fog/path | Shared tests: 100 seeds/every cell, version/floor separation and invalid paths |
| Three squads, exclusive/busy Heroes, frozen plan | PostgreSQL HTTP tests, trigger checks and expedition/deployment races |
| Five-second movement restored after disconnect | Real-clock Godot network and three-process recovery |
| Resource/enemy collisions pay once | HTTP tests and two distinct API processes |
| Tactics, miss costs, heal/revive and draw | Pure engine tests and Godot replay |
| Death/gear and empty-party repair | PostgreSQL defeat tests; v2 treatment/resurrection-to-encounter tests |
| Atomic failure/retry | Injected currency-write failure rolls back combat, rewards, Hero and position |
| Concurrent base actions preserve PvE rewards | Work/treatment/equipment/skill guards and a controlled reward-versus-breakthrough race |
| Boss clear once and explicit next floor | Node/DB and Godot flow; DRAW does not advance |
| Privacy/cursors/account separation | Owner/history tests, 251-event backlog and delayed old-account response |
| Sustained restart/ledger consistency | Three-hour real-clock run below |

Godot **4.7.2.stable.official.ed1daf0bf** ran headlessly. UI/replay/base availability and notifications: **48 checks passed**, with clean shutdown after fixing orphaned preconfigured browser buttons. Network flow: **29 checks passed**, including leaving an active replay. Recovery: **20 checks passed** across three game processes and two API restarts, including the delayed-poll/command synchronization race and a stale response after switching accounts. Project headless editor import also completed without script errors.

Three-hour run, six concurrent players with three squads each: **402 maps**, **62,684 requests**, **26,761 accepted commands**, **6,690 duplicate replies**, **116 API restarts**, **408 ledger/resource audits**, **zero failures**. Final-window p95: 353 ms locally, not a production capacity claim. Evidence: `logs/pve-soak-3h-summary.json`.

A subsequent 20-minute compiled-build run completed **42 maps**, **6,943 requests**, **752 duplicate replies**, **35 restarts** and **48 audits**, also with **zero failures** and clean account cleanup. Evidence: `logs/pve-soak-20m-summary.json`. These are frozen builds; later input-snapshot and breakthrough-lock refinements are verified separately by targeted regressions and full Node verification. New runs record compiled-source hashes in `logs/pve-soak-runtime-*/manifest.json`.

```powershell
$env:DATABASE_URL='postgres://postgres:postgres@localhost:5433/infinite_gacha_pve_soak_test'
node scripts/pve-soak.mjs --minutes=20 --players=6 --restart-seconds=30
```

The soak requires an explicit `_test` DB, snapshots the current build and audits wallet/ledger/node rewards while restarting a child API with active routes. Its summary distinguishes request interruptions: the three-hour run had zero interrupted HTTP requests. The Godot recovery proxy separately proves a committed mutation with a lost response.

## Final verification result

`npm run verify` passed against PostgreSQL after the final Silver race fix: **421 server tests and 69 shared tests**, zero failures and zero skipped tests. Encoding and clean TypeScript builds passed. Godot UI/network/recovery checks total **97**; both real-clock runs completed without failures. OpenAPI validation, current documentation links and `git diff --check` passed. Detailed handoff: [AGENT_HANDOFF_NOTES.md](../AGENT_HANDOFF_NOTES.md).

After the 1-second auto/leader update, the full suite passed **425 server and 69 shared tests**. The subsequent change allowing a second auto squad to attack a previously defeated team's uncleared enemy was rebuilt and passed all four focused PostgreSQL auto/leader/clock tests. Godot checks passed: **50 UI, 31 HTTP gameplay and 20 recovery**. Godot ran headlessly; visual appearance still needs graphical playtesting.

## Prototype limits

No cross-squad combos, ambushes, new morale, PvP redesign, Redis or new economy. Balance and visuals are prototype content. Headless tests verify actual scene execution and interactions; visual quality, camera comfort, audio, exports and player balance need graphical playtesting. Old dungeon and private map progression cannot run concurrently. Offline notifications appear when a client reads state again.
