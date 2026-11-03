# Infinite Gacha

Infinite Gacha is a Hero Management and Survival Strategy RPG. The repository contains phase-based business specifications and an early web prototype backed by a Node.js API and PostgreSQL.

## Project Structure

```
infiniti_gacha/
├── packages/
│   ├── shared/                # Shared types, enums, game constants, mathematical formulas (Pity-70, Combat, Movement)
│   ├── server/                # Express API, Drizzle ORM, PostgreSQL migrations and domain services
│   └── client/                # React + Vite Phase 1 Web HUD prototype
├── docker-compose.yml         # Local PostgreSQL instance
├── package.json               # Monorepo root workspace
└── tsconfig.base.json         # Base TypeScript configuration
```

## Project documents

- `infomation.docx` - project concept and broad business-domain information.
- `MBFL.docx` - Master Business Function List, including domains, modules, functions, business rules, decisions, and remaining TBD items.
- `Phase_Scope_Matrix_P0.csv` - draft P0 function-level scope matrix (164 functions across 33 modules).
- `Dependency_Review.csv` - dependency audit and normalization register.
- `BRD_P0_Draft.md` - Business Requirements Document for P0 scope.
- `Use_Case_Spec_P0_Draft.md` - 21 Use Case specifications with traceability to P0 functions.
- `Data_Model_P0_Draft.md` - comprehensive P0 database schema, ERD, and integrity constraints.
- `Acceptance_Criteria_P0_Draft.md` - testable Gherkin acceptance criteria for all 21 P0 Use Cases.
- `Phase_Scope_Matrix_P1.csv` - draft P1 function-level scope matrix (93 functions across 19 modules).
- `BRD_P1_Draft.md` - Business Requirements Document for Phase P1 (Hero & World Management).
- `Use_Case_Spec_P1_Draft.md` - 17 Use Case specifications for Phase P1.
- `Data_Model_P1_Draft.md` - comprehensive P1 database schema extension and ERD.
- `Acceptance_Criteria_P1_Draft.md` - testable Gherkin acceptance criteria for all 17 P1 Use Cases.
- `Phase_Scope_Matrix_P2.csv` - draft P2 function-level scope matrix (40 functions across 8 modules).
- `BRD_P2_Draft.md` - Business Requirements Document for Phase P2 (Economy & Live Operations).
- `Use_Case_Spec_P2_Draft.md` - 8 Use Case specifications for Phase P2.
- `Data_Model_P2_Draft.md` - comprehensive P2 database schema extension and ERD.
- `Acceptance_Criteria_P2_Draft.md` - testable Gherkin acceptance criteria for all 8 P2 Use Cases.
- `Phase_Scope_Matrix_P3.csv` - draft P3 function-level scope matrix (37 functions across 7 modules).
- `BRD_P3_Draft.md` - Business Requirements Document for Phase P3 (Multiplayer & World Conquest).
- `Use_Case_Spec_P3_Draft.md` - 8 Use Case specifications for Phase P3.
- `Data_Model_P3_Draft.md` - comprehensive P3 database schema extension and ERD.
- `Acceptance_Criteria_P3_Draft.md` - testable Gherkin acceptance criteria for all 8 P3 Use Cases.
- `AGENT_HANDOFF_NOTES.md` - append-only progress, decisions, open items, and next steps for agents.

## Current direction

- Build PvE first. Defer all PvP work until PvE is complete.
- Each account has exactly one Master. Third-party account linking (such as Google or Apple) is later scope.
- Summon items are called Heavenly Scrolls: white for normal, red for limited, and seven-color for special summons.
- Duplicate Heroes convert into a provisional resource name, "Thien Menh", which unlocks additional Hero power. The resource name will change later.
- Silver Coins are the basic currency. Gems are premium currency.
- One normal Heavenly Scroll costs 10,000 Silver Coins, with a cap of 50 exchanges per fixed week. Limited and special ticket acquisition will be configured later.
- Pity does not carry across banners.
- Normal Heroes die permanently and drop equipped gear; upgrade and training resources are not refunded.
- A World receives a fixed Seed at creation. The Seed determines World difficulty and must be unique across the game.
- The Master can change Tactical Buffs during battle, with a fixed 15-second cooldown.

## Current implementation

- The API persists account registration, revocable JWT sessions, ACTIVE/SUSPENDED/BANNED account status, Player Profiles, Master initialization, World creation, currency exchange, summons, summon history, and Hero instances through Drizzle ORM and PostgreSQL. Passwords use Argon2id; legacy scrypt hashes upgrade to Argon2id on successful login. Account status changes are reserved to trusted operators; an admin interface is not included in this prototype.
- Banner detail displays the active Hero/material pool, next-roll probability split, and banner-specific Pity. Operator configuration APIs create banners, replace their pool, set schedules, and activate/deactivate them; these routes require `x-admin-api-key` matching `ADMIN_API_KEY` in the server environment.
- Player Profile exposes editable display name/avatar, language/sound/notification preferences, and a live progress summary derived from Master, World, Hero, and summon records. Display names accept Unicode letters, digits, spaces, underscores, and hyphens; optional prohibited terms come from `PROFILE_PROFANITY_TERMS`.
- PostgreSQL migrations cover account, world, gacha, Hero, combat, saved parties, enemy samples, equipment templates/instances, floor drops, and Hero death records.
- Normal scroll exchanges now atomically deduct 10,000 Silver, add one white scroll, record the transaction, and enforce the 50-per-week cap using the Thursday 00:00 UTC+7 period.
- Summon requests atomically consume matching scrolls, resolve the shared Pity curve, split the remaining chance in the approved 49.6:50 base ratio, save history, create Heroes or materials, and convert each duplicate into 1 Thiên Mệnh on that Hero.
- The web client includes account access, Master/World setup, scroll exchange, configured-banner summons, persistent Hero collection, and a combat screen connected to persistent session and Tactical Buff APIs.
- Hero, Hero level progression, Banner 001, enemy, equipment, and floor-event seeds are development samples. PvE supports saved parties of up to five active Heroes, deterministic World-Seed/floor encounters and weighted events, speed-ordered server turns, Tactical Buff effects, persisted reports, sample EXP/Silver rewards, and floor progression on victory. Surviving Heroes receive EXP; editable cumulative thresholds grant levels and multiply HP/ATK/DEF/SPD by the configured sample growth rate. Normal Hero gear drops at that World floor and must be picked up; Special/Limited Heroes become Disabled and retain their gear.
- Master progression currently awards 300 sample EXP per PvE victory and uses editable per-level requirements (Level 2 requires 1,000 EXP); overflow carries into the next level as in P0 acceptance criteria. The sample Master skill heals each living party Hero by 1% max HP per real-time second for 5 seconds, with a configurable default 15-second cooldown. Feature availability is configured per minimum Master level and enforced by the API; current prototype features unlock at level 1 to preserve the first-play loop.
- Hero skill templates are sample, data-driven settings by class: each skill has a configured effect, unlock level, cooldown, and maximum level. Unlocks and upgrades are persisted; behavior mode is saved for future combat AI integration.
- DM-14 administration is implemented as an API-only operator plane guarded by `x-admin-api-key`: versioned rule configuration (`system_configs`), audit logging (`audit_logs`), system monitoring, and rate-based anti-cheat alerts (`security_alerts`).
- The web client includes a **Quản trị** screen for that plane: enter the admin key once per browser session, then publish or roll back configuration versions, review the audit trail, read monitoring counters, and resolve security alerts.
- Active configuration is consumed at runtime: `GACHA_PITY` drives the five-star pity curve in summoning and the banner rate preview, and `BATTLE_RULES.tacticalBuffCooldownSeconds` drives the Tactical Buff cooldown. Both fall back to the approved constants when no version is active or the database is unreachable.
- Phase P1 has started with Domain 08 (base, construction and production): zone expansion, a seven-entry building catalogue, offline resource accrual with capacity pause, harvesting into the Master inventory, and Hero work assignments that raise output.
- Redis is part of the selected architecture for later caching, distributed locks, leaderboards, and timers; it is not connected in this step.

## Run locally

Requirements: Node.js 20.19+ and Docker Compose.

1. Start PostgreSQL: `docker compose up -d postgres` (project database listens on host port 5433 to avoid colliding with a local PostgreSQL service on 5432).
2. Copy `packages/server/.env.example` to `packages/server/.env` and set a private `AUTH_SECRET`. Set `ADMIN_API_KEY` to a private value to enable banner configuration routes; operator requests send it in `x-admin-api-key`.
3. Apply the database migration: `npm run db:migrate`
   Optional sample data: apply `hero_templates.sample.sql`, `hero_level_configs.sample.sql`, `hero_development_configs.sample.sql`, `hero_skill_templates.sample.sql`, `master_level_configs.sample.sql`, `master_skills.sample.sql`, `feature_unlocks.sample.sql`, `banner_001.sample.sql`, `enemy_templates.sample.sql`, `equipment_templates.sample.sql`, and `dungeon_events.sample.sql` from `packages/server/src/database/seeds/` in that order. Hero EXP uses lifetime cumulative thresholds (level 2 starts at 100 EXP; each next level's required EXP grows by 1.5×); each level currently multiplies the four base stats by 1.05. Master level requirements use a sample 1.5× per-level curve starting at 1,000 EXP. These values are editable prototype data, not approved production balance. A Master initialized afterward receives the sample equipment kit; if a Master already exists, rerun the equipment seed.
4. Start the API: `npm run dev:server`
5. Copy `packages/client/.env.example` to `packages/client/.env` if the API URL differs from `http://localhost:3000`.
6. In another terminal, start the web client: `npm run dev:client` and open the Vite URL shown in the terminal.

`npm run db:generate` creates a migration from the Drizzle schema after a schema change. The existing consolidated `packages/server/src/database/schema.sql` remains the broader P0–P3 reference schema; do not apply it on top of the initial Drizzle migration because both define some of the same tables.

## Next steps

1. Review sample Hero/enemy/equipment/event balance, Hero EXP thresholds and stat growth, and production battle reward amounts.
2. Add production equipment progression and richer floor exploration after the sample loop is reviewed.
3. Expand the sample Master skill set and add Hero skills, critical hits, and status effects after their rules are defined.
4. Review remaining P0 TBD business rules before treating the prototype as a production implementation.
5. Add Redis when a feature requires distributed locks, shared timers, or live leaderboards.

## Update record

Updated: 2026-11-03 22:43:08 ICT (Asia/Bangkok)
Signed: Codex, project assistant

## Update - 2026-11-03 22:44:54 ICT (UTC+7)

Signed: Codex, project assistant

The fixed weekly limit of 50 normal Heavenly Scroll exchanges uses UTC+7 as its reference timezone. The specific reset day and time are still TBD.


## Update - 2026-11-03 22:49:37 ICT (UTC+7)

Signed: Codex, project assistant

- Reviewed all 22 registered decisions. The remaining P0 scheduling detail is the exact weekday and time for the 50-scroll cap reset; its timezone is set to UTC+7.
- Audited abbreviated dependencies and created `Dependency_Review.csv`. Under the MBFL same-module convention, 249 abbreviated references generate 6 dependency cycles, including self-references. Do not apply those tentative expansions automatically; each target needs semantic review. Fourteen references point to Domains rather than Functions.
- `Phase_Scope_Matrix_P0.csv` now points to the dependency audit; source dependency values remain unchanged.
- Next: confirm the weekly reset weekday/time; review the six dependency cycles and 14 Domain-level references, then normalize only approved links.

## Update - 2026-11-03 22:57:43 ICT (UTC+7)

Signed: Codex, project assistant

- Weekly exchange cap reset is at 00:00 UTC+7; weekday remains TBD.
- Recorded Pity-70 proposal for Special/Limited banners in MBFL and the P0 matrix: rolls 1-50 base rate, rolls 61-69 increasing rate, roll 70 guarantees any 5-star Hero. Rolls 51-60, exact increments, and reset behavior remain TBD.
- Replaced the contradictory Pity Carry-over function label with per-banner Pity counter isolation to match the confirmed no-carryover rule.
- Dependency question clarified for the project owner: a dependency means a prerequisite function that must happen before another function. Examples and candidate fixes are pending owner review.

## Update - 2026-11-03 22:58:42 ICT (UTC+7)

Signed: Codex, project assistant

- Clarified the exchange cap reset to 00:00 UTC+7 every fixed week. The weekday is still TBD.
- Expanded the Pity open question to include the base 5-star probability, behavior on rolls 51-60, and the incremental rate on rolls 61-69. Reset behavior after a 5-star remains a separate TBD.
- Kept the P0 dependency values unchanged pending confirmation of the proposed prerequisite links; see `Dependency_Review.csv` for examples of self-references and cycles.

## Update - 2026-11-03 23:00:24 ICT (UTC+7)

Signed: Codex, project assistant

- Weekly reset is now Thursday at 00:00 UTC+7.
- Applied the approved dependency corrections for profile/login, Master initialization, active banners, and Gacha pool/rate/Pity sequencing. Expanded remaining documented short IDs to full IDs in MBFL and the P0 matrix.
- One self-dependency remains in Assign Summon Origin (`FUN-02-05-003`); it was not covered by the approved proposal and remains visible in `Dependency_Review.csv` for owner confirmation. Domain-level dependency references were retained.

## Update - 2026-11-03 23:01:04 ICT (UTC+7)

Signed: Codex, project assistant

- Replaced the unapproved self-dependency on `FUN-02-05-003` with an explicit TBD in MBFL and the P0 matrix. The owner still needs to confirm which summon-result function precedes Summon Origin assignment.

## Update - 2026-11-04 00:58:00 ICT (UTC+7)

Signed: Antigravity, project assistant

- Phase P2 (Economy & Live Operations) completed across 40 functions, 8 modules, and 3 domains (DM-11, DM-12, DM-14).
- Created `Phase_Scope_Matrix_P2.csv`, `BRD_P2_Draft.md`, `Use_Case_Spec_P2_Draft.md`, `Data_Model_P2_Draft.md`, and `Acceptance_Criteria_P2_Draft.md`.
- Ready to proceed to Phase P3 (Multiplayer & World Conquest - 37 Functions).

## Update - 2026-11-04 01:05:00 ICT (UTC+7)

Signed: Antigravity, project assistant

- Phase P3 (Multiplayer & World Conquest) completed across 37 functions and 7 modules of Domain DM-13 (`MOD-13-01` to `MOD-13-07`).
- Created `Phase_Scope_Matrix_P3.csv`, `BRD_P3_Draft.md`, `Use_Case_Spec_P3_Draft.md`, `Data_Model_P3_Draft.md`, and `Acceptance_Criteria_P3_Draft.md`.
- Milestone: 100% of all 334 functions across P0, P1, P2, and P3 are completely specified with BRDs, Use Cases, Data Models, and Acceptance Criteria!

## Update - 2026-11-04 01:13:00 ICT (UTC+7)

Signed: Antigravity, project assistant

- Scaffolded TypeScript Monorepo (`packages/shared` and `packages/server`).
- Implemented Gacha Pity-70 polynomial formula, combat formulas, Master profile constraints, Tactical Buff 15s cooldown, Gem Debt handling, and World Seed generator.
- Added comprehensive PostgreSQL DDL schema (`packages/server/src/database/schema.sql`).
- All 14/14 automated unit tests passed across workspaces.

## Update - 2026-11-04 01:37:00 ICT (UTC+7)

Signed: Antigravity, project assistant

- Recorded confirmed technology roadmap into project notes:
  - Database: PostgreSQL (ACID primary store, JSONB logs) + Redis (Dual Leaderboards via Sorted Sets, locks, march timers).
  - Client: Phase 1 Web HUD / Prototype (React/Vite) for rapid interactive validation; Phase 2 Unity (C#) for commercial mobile production.






## Update - 2026-11-04 06:40:00 ICT (UTC+7)

Signed: DeepSeek Harness, project assistant

- Completed DM-14 (P0 phase closed): versioned configuration for all six rule families, audit trail, monitoring snapshot, and rate-based anti-cheat/abuse alerts with operator resolution.
- Added the operator console to the web client (`Quản trị` in the sidebar); the admin key is stored per browser session only.
- Wired active configuration into gameplay: the pity curve and banner rate preview read `GACHA_PITY`, the Tactical Buff cooldown reads `BATTLE_RULES`.
- Added an HTTP smoke test that boots the real API in-process and exercises register → Master → exchange → summon (including idempotent replay) plus the admin plane; it skips automatically when PostgreSQL is unreachable.
- Fixed the root workspace scripts: `npm run build` now builds `shared` first, and `npm test` no longer fails on the package without a test script.
- Verified: 42/42 server tests and 11/11 shared tests pass; live checks confirmed a published `GACHA_PITY` version changed the banner base rate to 2% and `BATTLE_RULES` changed the buff cooldown to 5s without a restart.
- Repaired remaining encoding damage: double-encoded UI symbols in the client (for example the `∞` brand mark) and four lossy Vietnamese error strings in the combat service.

## Update - 2026-11-04 06:58:00 ICT (UTC+7)

Signed: DeepSeek Harness, project assistant

- Started Phase P1 with Domain 08 (Base, Construction & Production): 18 functions across MOD-08-01..04.
- New tables `building_types`, `base_buildings`, `base_production_nodes`, `building_worker_assignments`, plus `worlds.base_zones`; migration `0023_slimy_dagger.sql` applied; catalogue seeded by `building_types.sample.sql`.
- New API surface under `/api/base` (overview, expand, construct, upgrade, demolish, production, collect, assign/remove worker) and a **Căn cứ** screen in the web client with plot grid, production readout and Hero assignment.
- Progress is tracked domain by domain in `P1_PROGRESS_CHECKLIST.md`, mirroring the P0 checklist.
- Repository hygiene: git baseline created, `npm run verify` (encoding guard + build + tests) added, P1/P2 scope matrices repaired from CP437 mojibake and the duplicated `FUN-08-02-001` row rebuilt from the MBFL source.
- Verified: `npm run verify` green — 55/55 server tests (13 new), 11/11 shared tests.
