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
- Phase P3 has started with the global world: unlock gating (Master 15 + floor 10), a 12x12 Outer Rim map with discovery, territory claiming with protection windows, upgrades, abandonment and an ownership leaderboard.
- Phase P3 PvP is implemented as Hero-vs-Hero: an ATTACK expedition can strike another Master's territory, protected by claim windows and the Novice Shield, with deterministic battle reports and ownership transfer on victory.
- **There is no army entity.** Heroes themselves travel: expeditions of 1–5 Heroes scout or attack tiles, reports carry owner/defender/power data, and claiming a tile requires a won hero attack (`tile_clearances`).
- Phase P3 MOD-13-06 (Alliances) is implemented: founding with Gems or Silver at level 20, search/join requests, the Officer/Leader role matrix, promote/demote/kick/transfer, Alliance Tech member-cap growth, a notice board and guild chat with map-coordinate pings. Leaving or being removed starts a 24-hour re-join cooldown.
- Phase P3 MOD-13-07 (World War & Conquest) is implemented: Leader-declared 24-hour alliance wars scored by hero raids and repelled defences, lazy war settlement with mailbox rewards, dual season rankings, and the Central Imperial Wonder at (500, 500) that can be stormed in the final three days of a 30-day season and held for 8 continuous hours to crown the Conqueror Alliance.
- Phase P2 Domain 14 (analytics & support) is implemented: player/gacha/economy/battle/retention aggregates for operators, and a support ticket flow (player opens and replies, operators answer and advance status).
- Phase P2 Domain 14 (operations) now includes player search/restriction/compensation, and operator configuration for Hero templates, Hero stats, skills, monsters, bosses and the new item catalogue, with `CURRENCY_RULES`/`REWARD_RULES` added to the versioned configuration keys.
- Phase P2 Domain 12 (LiveOps) is implemented: scheduled events with 48h claim grace and overlap/cooldown guards, event missions fed by gameplay events, and two PvE leaderboards (dungeon progress and combat power) whose season close pays rewards through the mailbox.
- Phase P2 has started with Domain 11 (IAP): package catalogue, simulated store receipts with replay protection, gem-debt settlement on purchase, and operator refunds that claw Gems back or book debt.
- Phase P1 Domain 01 (accounts) is implemented: provider identity linking (Google/Apple, HMAC-simulated hand-off) and single-use recovery tokens that rotate the password and revoke sessions.
- Phase P1 Domain 12 (quests) is implemented: main/side quests with explicit acceptance, daily quests rotating at 00:00 UTC+7, weekly quests rolling on Thursday, and lifetime achievements that pay Gems.
- Phase P1 Domain 10 (crafting) is implemented: recipe-based equipment crafting with rolled substats, enhancement by stones and Silver, and three-into-one fusion that raises star rarity by 30% per star.
- Phase P1 Domain 11 (shop & mailbox) is implemented: a rotating Silver shop with per-item daily limits, plus system/operator mail whose Silver and item attachments are claimed into the wallet in one transaction.
- Phase P1 Domain 03 (personality) is implemented: four deterministic traits per Hero, a loyalty score with DEVOTED/NORMAL/DANGER states that scales combat stats and can refuse dispatch, favourite meals, and a Hero-to-Hero affinity graph with a COMRADE resonance bonus.
- Phase P1 Domain 04 (medical) is implemented: battle injuries with temporary ATK/DEF penalties, a Medical Facility with bed capacity and accelerated treatment, emergency healing with MEDICINE, and Divine Grace resurrection with a progressive 30-day cost cycle.
- Phase P1 Domain 09 (survival) is implemented: per-Hero hunger and fatigue that drift with time and activity, feeding and resting, a kitchen that converts raw food into meals, and dungeon rations charged before a run.
- Phase P1 has started with Domain 08 (base, construction and production): zone expansion, a seven-entry building catalogue, offline resource accrual with capacity pause, harvesting into the Master inventory, and Hero work assignments that raise output.
- Redis is part of the selected architecture for later caching, distributed locks, leaderboards, and timers; it is not connected in this step.

## Automated tests and CI

- `npm run verify` runs the encoding guard, builds every workspace and executes the full test suite.
- `npm test` runs **362 server tests** — domain-rule unit tests plus HTTP integration suites (`packages/server/tests/http.*.test.mjs`) that boot the real Express app, register a throwaway account and exercise base construction, crafting, survival, medical, economy/IAP, LiveOps, alliances, world conquest, Combat v2 and administration flows against PostgreSQL — and **56 shared** formula tests.
- HTTP suites skip automatically when the database is unreachable, so the unit suite still works offline.
- Fresh database in two commands: `npm run db:migrate` then `npm run db:seed` (18 idempotent sample seeds).
- CI (`.github/workflows/ci.yml`) starts PostgreSQL 17 as a service, migrates, seeds and runs `npm run verify` on every push and pull request.

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

1. Move alliance chat, war countdowns and Wonder hold timers to Redis (pub/sub and shared TTLs) so multiple API instances agree on time.
2. Review the sample alliance/war/season reward amounts and the Alliance Tech Silver cost before treating them as economy balance.
3. Replace the aggregate-power Wonder siege with the round combat engine once multi-party siege formations are defined.
4. Review sample Hero/enemy/equipment/event balance, Hero EXP thresholds and stat growth, and production battle reward amounts.
5. Add production equipment progression and richer floor exploration after the sample loop is reviewed.
6. Expand the sample Master skill set and add Hero skills, critical hits, and status effects after their rules are defined.
7. Review remaining P0 TBD business rules before treating the prototype as a production implementation.

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

## Update - 2026-11-04 07:22:00 ICT (UTC+7)

Signed: DeepSeek Harness, project assistant

- Completed P1 Domain 09 (Survival): 16 functions across MOD-09-01..03 — hunger/fatigue tracking with lazy time drift, feeding, resting, overexertion blocking, kitchen conversion, base upkeep quotes and dungeon rations.
- Cross-domain integration: harvesting a building now counts as a labour shift (+5 hunger, +8 fatigue, auto-eject at 100 fatigue), combat applies the starvation ATK/DEF penalty and charges 10 rations per Hero, and new Masters start with 100 FOOD.
- New table `hero_survival_states` (migration `0024_normal_magneto.sql`) and a **Sinh tồn** screen in the web client.
- Verified: `npm run verify` green — 70/70 server tests (15 new survival rules), 11/11 shared tests.

## Update - 2026-11-04 07:47:00 ICT (UTC+7)

Signed: DeepSeek Harness, project assistant

- Completed P1 Domain 04 (Medical): 17 functions across MOD-04-02..04 — injury classification after battles, temporary stat penalties, facility beds and treatment timers, emergency treatment, and Divine Grace resurrection with a progressive 30-day cycle.
- New tables `hero_injuries`, `hero_treatments`, `hero_resurrection_cycles` (migration `0025_unknown_miracleman.sql`) and a **Y tế** screen in the web client.
- Combat now stacks the injury multiplier with the starvation penalty, and finished battles record injuries for survivors below 50% HP.
- Fixed a `BigInt` serialization bug that made treatment responses fail with HTTP 500.
- Verified: `npm run verify` green — 81/81 server tests (11 new medical rules), 11/11 shared tests.

## Update - 2026-11-04 08:12:00 ICT (UTC+7)

Signed: DeepSeek Harness, project assistant

- Completed P1 Domain 03 (Personality & Relationships): 10 functions across MOD-03-04..05 — deterministic traits, loyalty states with combat multipliers and a 30% disobedience roll, favourite-meal loyalty, and pair affinity that unlocks a combat resonance.
- New tables `hero_personality_traits` and `hero_relationships` (migration `0026_icy_elektra.sql`) plus a **Tính cách** screen in the web client.
- Verified live: favourite meal 50 → 55 loyalty, a DANGER Hero at 0.65 multiplier refused dispatch once (expected 30% roll), then fought at reduced ATK; the victory raised loyalty and gave both survivors +2 affinity.
- `npm run verify` green — 91/91 server tests (10 new personality rules), 11/11 shared tests.

## Update - 2026-11-04 08:37:00 ICT (UTC+7)

Signed: DeepSeek Harness, project assistant

- Completed P1 Domain 11 (Shop & Mailbox): 12 functions across MOD-11-02..04 — rotating catalogue, per-Master daily purchase limits, admin catalogue management, operator mail with attachments, claiming and 30-day expiry purge.
- New tables `shop_items`, `shop_purchase_limits`, `mailbox_messages` (migration `0027_cooing_carlie_cooper.sql`) plus a **Cửa hàng** screen with shop and mailbox tabs.
- Seeded nine shop entries including MEDICINE, DIVINE_TEAR and raw materials, closing the supply gap left by the survival and medical domains.
- Verified live: the daily limit sold 3 of a 5-unit request and flagged `ERR_SHOP_DAILY_LIMIT_EXCEEDED`, weekend-only MOON_CAKE was refused mid-week, mail claiming added 5,000 Silver and 2 FOOD, and an expired message was purged on read.
- `npm run verify` green — 102/102 server tests (11 new shop rules), 11/11 shared tests.

## Update - 2026-11-04 09:02:00 ICT (UTC+7)

Signed: DeepSeek Harness, project assistant

- Completed P1 Domain 10 (Crafting): 4 functions — recipe validation, crafting with deterministic substat rolls, enhancement by ENHANCEMENT_STONE + Silver, and three-into-one star fusion.
- New table `crafting_recipes` and equipment instance columns `star_level`, `enhance_level`, `stat_multiplier`, `substats` (migration `0028_wild_maddog.sql`), plus a **Xưởng** screen in the web client.
- Combat equipment bonuses now scale with fusion/enhancement and add rolled substats.
- Fixed a stacking bug found by live testing: enhancing a fused item used to replace its star multiplier instead of compounding it; covered by a regression test.
- Verified: `npm run verify` green — 116/116 server tests (13 new crafting rules), 11/11 shared tests.

## Update - 2026-11-04 09:32:00 ICT (UTC+7)

Signed: DeepSeek Harness, project assistant

- Completed P1 Domain 12 (Quests & Achievements): 14 functions across MOD-12-01..03 — quest catalogue, side-quest acceptance, event-driven progress for victory/floor clear/craft/spend/harvest, deterministic five-quest daily rotation, Thursday weekly reset, and lifetime achievements.
- New tables `quest_definitions`, `quest_progress`, `achievements`, `achievement_progress` (migration `0029_kind_wendigo.sql`), seeded with 11 quests and 5 achievements, plus a **Nhiệm vụ** screen in the web client.
- Gameplay hooks now feed the quest engine from combat victories, crafting, shop purchases and resource harvesting.
- Verified live: crafting twice completed the accepted side quest and the daily craft quest, claiming paid 2,000 Silver, a dungeon victory completed the main floor-clear quest and the daily win quest, and the hero-count achievement tracked 3/10.
- `npm run verify` green — 125/125 server tests (9 new quest rules), 11/11 shared tests.

## Update - 2026-11-04 10:07:00 ICT (UTC+7)

Signed: DeepSeek Harness, project assistant

- Completed P1 Domain 01 (Account Linking & Recovery): 2 functions — HMAC-verified Google/Apple identity linking with duplicate protection, and 24-hour single-use recovery tokens that rotate the password and revoke sessions.
- New tables `account_external_identities` and `account_recovery_tokens` (migration `0030_ordinary_storm.sql`), `LINK_PROVIDER_SECRET` added to the example environment, plus a **Tài khoản** screen in the web client.
- **Phase P1 is now complete: 93/93 functions across 8 domains and 19 modules**, tracked in `P1_PROGRESS_CHECKLIST.md`.
- Verified live: a tampered provider token was rejected, a valid link was stored, a second account was refused with `ERR_AUTH_EXTERNAL_ID_ALREADY_LINKED`, recovery rotated the password, and replaying the used token failed.
- `npm run verify` green — 134/134 server tests (9 new account rules), 11/11 shared tests.

## Update - 2026-11-04 10:42:00 ICT (UTC+7)

Signed: DeepSeek Harness, project assistant

- Started Phase P2 with Domain 11 (Payment & IAP): 7 functions — package catalogue, checkout, receipt validation, reward granting with Gem-debt settlement, payment history and operator refunds.
- New tables `iap_products` and `payment_transactions` (migration `0031_broken_whiplash.sql`), seeded with four packages, `PAYMENT_GATEWAY_SECRET` added to the example environment, plus a **Nạp Ngọc** screen in the web client.
- Store receipts are simulated with an HMAC hand-off (no Apple/Google SDK), and refunds claw back Gems or book them as Gem debt without locking the account.
- Verified live: 1.000 Gems credited, invalid signature refused, reused store receipt returned `ERR_IAP_DUPLICATE_RECEIPT`, refund with balance reached 0/0, refund after spending produced 800 Gem debt.
- `npm run verify` green — 146/146 server tests (12 new payment rules), 11/11 shared tests. P2 progress is tracked in `P2_PROGRESS_CHECKLIST.md`.

## Update - 2026-11-04 11:17:00 ICT (UTC+7)

Signed: DeepSeek Harness, project assistant

- Completed P2 Domain 12 (LiveOps & Leaderboards): 10 functions — event scheduling/activation/closure with overlap and MAJOR-cool-down guards, event missions fed by the gameplay event pipeline, mission claims with a 48h grace window, dual PVE leaderboards and season settlement paid via mailbox.
- New tables `live_events`, `event_missions`, `event_mission_progress`, `floor_records`, `leaderboard_seasons`, `leaderboard_rewards` (migration `0032_pretty_morg.sql`), seeded sample event, and a **Sự kiện** screen in the web client.
- Verified live: two crafts completed the event craft mission and paid its reward, a dungeon victory advanced both event missions and ranked the Master #1 by floor/rounds, and closing the season delivered a rank-1 reward mail.
- `npm run verify` green — 158/158 server tests (12 new liveops rules), 11/11 shared tests.

## Update - 2026-11-04 11:52:00 ICT (UTC+7)

Signed: DeepSeek Harness, project assistant

- Delivered P2 Domain 14 part one (16 functions): player administration (search, detail, restrict/restore, compensation) and content/economy configuration (Hero templates, stats, skills, enemies, bosses, item catalogue, currency/reward config keys).
- New `item_templates` table and `enemy_templates.is_boss` (migration `0033_messy_giant_girl.sql`), seeded with 13 items shared by the shop, crafting and reward flows.
- Admin console gained **Người chơi** and **Nội dung** tabs.
- Verified live: suspend blocked login with `ERR_AUTH_ACCOUNT_RESTRICTED`, restore re-enabled it, compensation mailed 5.000 Silver and credited 10 Gems, item/Hero/stats/boss upserts worked, and `CURRENCY_RULES` published as version 1.
- `npm run verify` green — 165/165 server tests (7 new admin rules), 11/11 shared tests.

## Update - 2026-11-04 12:27:00 ICT (UTC+7)

Signed: DeepSeek Harness, project assistant

- Completed P2 Domain 14 part two (7 functions): analytics for players, gacha, economy, battles and retention, plus customer-support tickets with operator replies and guarded status transitions.
- New tables `support_tickets` and `support_ticket_messages` (migration `0034_tidy_valeria_richards.sql`), an admin **Phân tích** tab and a player **Hỗ trợ** page.
- **Phase P2 is now complete: 40/40 functions across 3 domains and 8 modules**, tracked in `P2_PROGRESS_CHECKLIST.md`.
- Verified live: a ticket went OPEN → IN_PROGRESS (operator reply) → RESOLVED → CLOSED, reopening was refused with `ERR_SUPPORT_INVALID_TRANSITION`, and the analytics summary reported accounts, rolls, win rate and retention from real data.
- `npm run verify` green — 174/174 server tests (9 new support/analytics rules), 11/11 shared tests.

## Update - 2026-11-04 12:55:00 ICT (UTC+7)

Signed: DeepSeek Harness, project assistant

- Added HTTP integration coverage: six suites (`http.base`, `http.crafting`, `http.survival`, `http.medical`, `http.economy`, `http.liveops`, `http.admin`) drive the real API in-process and clean up after themselves. Total suite is now 216 tests.
- Added `scripts/apply-seeds.mjs` (`npm run db:seed`) which applies all 18 sample seeds in dependency order and is safe to re-run; two seeds had a UTF-8 BOM stripped.
- Added GitHub Actions CI (`.github/workflows/ci.yml`): PostgreSQL 17 service, migrations, seeds, then `npm run verify` with test files serialised (`--test-concurrency=1`) so database fixtures never collide.
- Fixed three integration-test assumptions that the HTTP layer surfaced: restriction revokes the caller's session, the starter equipment kit counts toward crafted gear, and food storage capacity caps the kitchen.

## Update - 2026-11-04 13:22:00 ICT (UTC+7)

Signed: DeepSeek Harness, project assistant

- Started Phase P3 (Multiplayer & World Conquest) with MOD-13-01 and MOD-13-02: 10 functions covering global-world unlock, discovery radius, map/region views, territory claiming with a 30-minute protection window, upgrades, abandonment and ownership tracking.
- New tables `world_tiles`, `master_world_status`, `tile_discoveries`, `territories`, `territory_events` (migration `0035_aberrant_tony_stark.sql`), a seeded 12×12 Outer Rim map and a **Thế giới** screen in the web client.
- Verified: `npm run verify` green — 237/237 server tests (8 world-rule tests + a 10-step HTTP world suite) and 11/11 shared tests. P3 progress is tracked in `P3_PROGRESS_CHECKLIST.md`.

## Update - 2026-11-04 13:55:00 ICT (UTC+7)

Signed: DeepSeek Harness, project assistant

- Design correction from the owner: the army concept is dropped. Heroes are the only mobile unit and they scout and attack personally.
- Implemented MOD-13-03 and MOD-13-04 as hero expeditions: `hero_expeditions`, `expedition_members`, `tile_clearances` (migration `0036_illegal_squadron_supreme.sql`), 30s-per-tile travel, SCOUT reports, ATTACK battles against the tile guardian, recall and movement tracking.
- Territory claiming now requires a cleared tile (`ERR_TERRITORY_NOT_CLEARED`); the old combat-power shortcut was removed.
- The **Thế giới** page gained a party picker (max 5 Heroes) and an expedition list with live countdowns and recall.
- Verified: `npm run verify` green — 250/250 server tests (7 expedition rule tests + a 6-step HTTP expedition suite) and 11/11 shared tests.

## Update - 2026-11-04 14:30:00 ICT (UTC+7)

Signed: DeepSeek Harness, project assistant

- Completed P3 MOD-13-05 (PvP & Territory Defense): 7 functions — hero raids on enemy territories, protection/shield validation, deterministic hero-vs-hero battles, ownership transfer with a fresh protection window, a defence estimate endpoint and a PvP battle log.
- New table `pvp_battles` (migration `0037_zippy_solo.sql`); the **Thế giới** page now shows recent PvP reports.
- Verified: `npm run verify` green — 268/268 server tests (8 PvP rule tests + a 6-step HTTP PvP suite) and 11/11 shared tests.

## Update - 2026-11-04 08:18:00 ICT (UTC+7)

Signed: DeepSeek Harness, project assistant

- Completed P3 MOD-13-06 (Alliance System) and MOD-13-07 (World War & Conquest): 12 functions, closing Phase P3 at **37/37 functions**.
- Alliances: level-20 founding paid in 5,000 Gems or 500,000 Silver, search, join requests with officer approval, the Leader/Officer/Member matrix, promote/demote/kick/leadership transfer, Alliance Tech (30 → 100 members), notice board, guild chat plus coordinate pings, and a 24-hour re-join cooldown.
- World conquest: Leader-declared 24-hour wars scored by hero raids and repelled defences (`war_engagements`), lazy settlement with mailbox rewards, 30-day seasons, dual season ranking, and the Central Imperial Wonder at (500, 500) — stormable in the final 3 days and conquerable after an 8-hour continuous hold.
- New tables `alliances`, `alliance_members`, `alliance_join_requests`, `alliance_cooldowns`, `alliance_messages`, `alliance_wars`, `war_engagements`, `world_conquest_seasons`, `world_conquest_rankings`, `wonder_holdings` (migration `0038_clear_wong.sql`); `world_tiles.sample.sql` now seeds the Wonder tile.
- New API surface under `/api/alliance` (overview, search, create, join/approve/reject/cancel, leave, member management, notice, tech, disband, chat) and `/api/world/conquest` (overview, ranking, seasons, Wonder siege) plus `/api/alliance/wars`; a **Liên minh** screen was added to the web client with overview, roster, chat and war tabs.
- PvP settlement now feeds war scoring, and the Wonder tile is excluded from the client's local map grid.
- Verified: `npm run verify` green — 325/325 server tests (20 alliance rule tests, 17 conquest rule tests, an 11-step HTTP alliance suite and a 9-step HTTP conquest suite) and 11/11 shared tests.

## Update - 2026-11-05 09:45:00 ICT (UTC+7)

Signed: DeepSeek Harness, project assistant

- Started **Combat v2** (based on the STR/INT/STA/AGI design) and completed its foundation: stat calculator, class/affinity rules, progression, engine, simulation and report persistence.
- Confirmed design decisions: no Speed stat (one action per round, AGI order), Thief crit 50% / others 5% with a 100% crit cap, growth compensation to 672 points at level 50 for 1–5★, Mage available on every banner, 6★/7★ data-ready but locked, random stats with per-star budgets, class changes cost 50,000 Silver + 1 Class Change Token.
- `packages/shared/src/combat/`: base/derived stats, caps, class growth (Warrior/Thief/Spearman/Archer/Mage), summon class roll, stat roll (75% archetype + 25% wildcard), growth compensation, Mage affinity, damage pipeline and Hero generation. Shared suite is now 56 tests.
- Database migrations `0039_same_spyke.sql` and `0040_absurd_joshua_kane.sql` add `hero_templates`/`heroes` base stats, class/role, training and origin stats, plus `hero_class_definitions`, `subclass_definitions`, `hero_subclasses` and `hero_element_affinities`; 22 seeds were applied.
- Summoning now rolls base stats, class and Mage affinity, mirrors the legacy HP/ATK/DEF/SPD columns for the current engine, and stores `origin_stats`. `npm run db:reset-heroes` clears old demo Heroes so they can be re-summoned.
- Progression v2: level-up recomputes from origin/class/training; `POST /api/heroes/:heroId/train` allocates training points (3 per level, 60% per-stat cap); `POST /api/heroes/:heroId/class-change` enforces level/stat/resource conditions, recomputes growth retroactively and manages Mage affinity.
- Combat v2 engine (`combat-v2.engine.ts`): AGI turn order, one action per round, MP skills with cooldowns, basic attacks restoring 5% MP, shared hit/mitigation/affinity/crit/block/DR pipeline, healing, lifesteal and draw handling. Equipment, starvation, injury, loyalty and resonance modifiers are applied before combat.
- `POST /api/combat/v2/simulate` resolves a deterministic battle report; `persist: true` stores it as a completed `combat_sessions` row and `GET /api/combat/v2/sessions` lists recent reports.
- Awakening no longer multiplies legacy stats for Combat v2 Heroes; their stats stay on the recompute path.
- Verified: `npm run verify` green — **362/362 server tests** and **56/56 shared tests**.
- Remaining before Unity: persistent multi-step combat sessions with EXP/Silver, injury and quest/leaderboard hooks; a Combat v2 page in the web client; subclass acquisition API/UI; an equipment catalogue that grants base/derived stats; 6★/7★ content and TTK tuning.
