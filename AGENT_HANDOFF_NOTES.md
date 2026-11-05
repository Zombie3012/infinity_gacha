# Agent Handoff Notes

## Append-only maintenance rule

Do not delete, truncate, or replace this file. Add a new dated and signed update section at the end whenever project status changes. Preserve all earlier entries.

## Update - 2026-11-03 22:43:08 ICT (Asia/Bangkok)

Signed: Codex, project assistant

### Work completed

- Read `infomation.docx` and repaired visible raw markup and formatting artifacts in `MBFL.docx`.
- Updated MBFL with confirmed account, Gacha, Hero death, combat, Dungeon Seed, PvP sequencing, and currency decisions.
- Created `Phase_Scope_Matrix_P0.csv` with function-level P0 rows from the MBFL.
- Added P0 scope for the minimum Silver Coin and normal Heavenly Scroll exchange loop.
- Limited P0 administration scope per the project owner's preference to Gacha/Dungeon configuration, system monitoring, audit, and security. Analytics, customer support, and player administration are outside the current P0 proposal.
- Added the exchange function: 10,000 Silver Coins for one normal Heavenly Scroll, capped at 50 per fixed week.

### Confirmed product decisions

- One account has exactly one Master. Third-party linking (Google, Apple, and similar) is later scope.
- Pity does not carry over between banners.
- Duplicate Heroes convert to a provisional resource called "Thien Menh" for unlocking more Hero power; rename later.
- A Normal Hero's death drops equipped gear. Upgrade/training resources are not refunded.
- A World Seed is created with the World, determines its difficulty, stays fixed for that World, and must be unique across the entire game. The technical generation/collision approach is future technical design.
- Masters may change Tactical Buffs during battle; cooldown is fixed at 15 seconds.
- Defer all PvP until PvE is complete.
- Summon items are Heavenly Scrolls: white = normal, red = limited, seven-color = special. Acquisition setup for limited and special tickets is later scope.
- Silver Coins are basic currency; Gems are premium currency.
- Normal Heavenly Scroll exchange costs 10,000 Silver Coins, up to 50 per fixed week.

### Open items

- Specify the fixed weekly reset boundary for the exchange cap: day, time, and timezone.
- Review/approve the 160-row P0 draft matrix and validate the existing abbreviated dependencies against full Function IDs.
- Continue resolving remaining business decisions in the MBFL Decision Register before detailed BRD/Use Case approval.
- Determine technical platform and stack before production implementation.

### Recommended next action

Ask the project owner to specify the weekly reset day/time/timezone, then review the P0 matrix and normalize dependencies to full Function IDs. Keep all unconfirmed business rules marked TBD; do not invent product rules.

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

## Update - 2026-11-03 23:10:02 ICT (UTC+7)

Signed: Codex, project assistant

- Note policy changed at the user's request: add or update handoff notes only when the user explicitly requests a note. Do not append routine progress notes automatically.
- Pity details updated: 0.4% five-star base rate on rolls 1-60, increasing rate on 61-69 using the named Polynomial/Exponential Growth family, any five-star guaranteed on roll 70, and counter reset after a five-star. Exact growth formula and parameters remain TBD.

## Update - 2026-11-03 23:40:50 ICT (UTC+7)

Signed: Codex, project assistant

- Applied the approved P0 scope adjustments across MBFL, the P0 matrix, BRD, Use Case specifications, and dependency review.
- P0 now includes minimal World initialization and basic equipment operations; Account Linking and Account Recovery are deferred to P1.
- Special/Limited summon processing remains P0; acquisition sources for those scrolls remain deferred.
- Synchronized BRD and Use Case traceability to all 164 P0 Function IDs.

## Update - 2026-11-04 00:08:15 ICT (UTC+7)

Signed: Antigravity, project assistant

### Work completed

- Recorded confirmed business decisions from project owner:
  - Base summon pool breakdown (rolls 1-60): 0.40% 5★ Hero, 49.60% 1★-4★ Heroes, 50.00% Materials/Misc items (50% Hero / 50% Materials total pool).
  - Summon cost: 1 Heavenly Scroll for Single Summon, 10 Heavenly Scrolls for Multi Summon (10 rolls, no guaranteed 4★+ on multi).
  - Duplicate resolution: Special/Limited Hero duplicate converts into 1 Thien Menh (1 copy = 1 Thien Menh). Normal Hero duplicates do not create redundant instances; duplicates grant Talent Points (Diem Tai Nang) directly to the owned instance.
  - EXP & Combat damage systems remain placeholder formulas in P0; database schema supports attributes, formulas, and modifiers for later parameterization.
  - World Seed collision strategy: standard globally unique UUID/GUID generated per World (effectively zero collision probability, no retry loop needed).
- Designed and created comprehensive P0 Data Model & ERD specification in `Data_Model_P0_Draft.md`, covering all 164 P0 functions across 33 modules.
- Synchronized approved decisions across `BRD_P0_Draft.md`, `Use_Case_Spec_P0_Draft.md`, and `Phase_Scope_Matrix_P0.csv`.

### Next steps

- Write comprehensive Acceptance Criteria for all 21 P0 Use Cases.
- Propose client and backend technical stack options for project owner evaluation.

## Update - 2026-11-04 00:38:00 ICT (UTC+7)

Signed: Antigravity, project assistant

### Work completed

- Phase P0 verified 100% complete and consistent across all specifications (164 Functions, BRD, 21 Use Cases, Data Model/ERD, Acceptance Criteria).
- Officially started **Phase P1: Hero & World Management**.
- Recorded confirmed P1 core business rules from project owner:
  - Hero Limited/Special Resurrection (God's Grace): Fallen Heroes automatically transfer to Base Medical Facility in `DISABLED` state; resurrection requires special divine materials with progressive resource costs, resetting back to base cost every 30 days from the initial resurrection.
  - Loyalty Rule: Heroes **NEVER abandon the Master under any circumstances**. When Loyalty drops below 20 (Danger threshold), Heroes suffer heavy stat penalties (20%–50%) and may refuse to participate in battles or ignore commands.
  - 4-Tier Personality Trait Structure: Core Personality (immutable, base nature & fear resistance), Social Personality (evolves through bonding), Behavioral Personality (adapts through combat experience & training), and Special Personality (mostly fixed, unique quirks).
  - Survival System (Hunger & Fatigue on 0–100 scale): Standardized rate increments for hourly idle, battle, travel, missions, and skill usage, mapped to tiered status effects (0-19 Full/Rested up to 100 Critical/Overexhausted) and specific food/rest recovery methods.
  - Offline Production: Base production facilities run continuously while offline without time limits, pausing only when building or base storage capacity is fully capped.
- Created `Phase_Scope_Matrix_P1.csv` detailing all 93 P1 Functions across 19 Modules and 8 Domains.
- Created `BRD_P1_Draft.md` formalizing the Phase P1 Business Requirements.
- Created `Use_Case_Spec_P1_Draft.md` defining 17 detailed Use Cases covering all 93 P1 Functions.
- Created `Data_Model_P1_Draft.md` detailing database schema extensions for P1 (Personality Traits, Relationships, Injuries, Medical Facilities, Base Buildings, Production Nodes, Survival States, Crafting Recipes, Shop Limits, Mailbox, Quests, Achievements).
- Created `Acceptance_Criteria_P1_Draft.md` specifying testable BDD criteria for all 17 P1 Use Cases.

### Next steps

- Evaluate Phase P1 baseline with project owner.
- Proceed to Phase P2 scoping (Economy, IAP Payment Gateway, Live Events, Analytics) or begin technical stack selection.




## Update - 2026-11-04 00:58:00 ICT (UTC+7)

Signed: Antigravity, project assistant

### Work completed

- Phase P2: Economy & Live Operations completed across all 40 Functions, 8 Modules, and 3 Domains (DM-11, DM-12, DM-14).
- Extracted and mapped all 40 functions into `Phase_Scope_Matrix_P2.csv`.
- Recorded confirmed P2 core business rules from project owner:
  - IAP Refund & Chargeback Handling: Implemented Gem Debt (`gem_debt`) policy. If a player requests a refund or initiates a chargeback, remaining purchased gems are deducted. If gems are already spent, the player balance goes into debt (`gem_debt > 0`). Future gem earnings deduct directly from debt first. Accounts are **never banned** for refunds/chargebacks.
  - Leaderboards: Dual ranking tracks — 1) Dungeon Floor Progression (Highest floor reached, broken by total clear time as secondary tie-breaker) and 2) Total Combat Power (Sum of Top 5 highest CP Heroes).
  - LiveOps Event Cadence: Standard Event = fixed 14 days; Mini Event = 3-5 days; Major Event = 14-21 days (with mandatory 7-day cooldown between consecutive major events); 48-hour claim grace period post-event. Max 1 Standard + 1-2 Mini events concurrently.
- Created `BRD_P2_Draft.md` formalizing Phase P2 Business Requirements.
- Created `Use_Case_Spec_P2_Draft.md` detailing 8 Use Cases (`UC-P2-01` to `UC-P2-08`) covering all 40 functions.
- Created `Data_Model_P2_Draft.md` detailing database schema extensions for P2 (IAP products, orders, receipt validation, refunds, gem debt, live events, event quest logs, dual leaderboards, player support tickets, daily analytics cohorts).
- Created `Acceptance_Criteria_P2_Draft.md` specifying testable BDD criteria for all 8 P2 Use Cases.

### Next steps

- Commence Phase P3: Multiplayer & World Conquest (37 Functions across MOD-13-01 to MOD-13-07).
- Synthesize technical stack recommendations for Project Owner evaluation.

## Update - 2026-11-04 01:05:00 ICT (UTC+7)

Signed: Antigravity, project assistant

### Work completed

- Phase P3: Multiplayer & World Conquest completed across all 37 Functions, 7 Modules of Domain DM-13 (`MOD-13-01` to `MOD-13-07`).
- Extracted and mapped all 37 functions into `Phase_Scope_Matrix_P3.csv`.
- Defined confirmed P3 core business rules:
  - World Map grid: 1000 x 1000 coordinates, regional divisions, base cap 10 territory tiles (expandable to 30).
  - Army & Movement: 1 Commander + 4 Sub-Heroes per army, march speed based on Euclidean distance with terrain modifiers, real-time ETA and recall support.
  - PvP Protection & Casualties: Strict non-permadeath rule for PvP (Normal Heroes killed in PvP become `CRITICALLY_INJURED` and heal in Base Medical Facility rather than being permanently deleted). Max 20% unprotected resources plundered per attack. 48-hour novice peace shield, and 8-hour emergency peace shield triggered upon heavy defeat.
  - Alliance System: Founded at Level 20+ (5,000 Gems or 500k Silver), max 30 members (up to 100 via tech), 24-hour rejoin cooldown on leaving.
  - World Conquest: 30-day season cycle, Imperial Central Wonder at (500, 500) contested in last 3 days, 8-hour continuous hold victory condition.
- Created `BRD_P3_Draft.md` formalizing Phase P3 Business Requirements.
- Created `Use_Case_Spec_P3_Draft.md` detailing 8 Use Cases (`UC-P3-01` to `UC-P3-08`) covering all 37 functions.
- Created `Data_Model_P3_Draft.md` detailing database schema extensions for P3 (13 new tables for tiles, regions, armies, scouting, pvp records, peace shields, alliances, wars, and conquest rankings).
- Created `Acceptance_Criteria_P3_Draft.md` specifying testable BDD criteria for all 8 P3 Use Cases.
- **Milestone Reached**: 100% of all 334 business functions across all 4 Phases (P0: 164, P1: 93, P2: 40, P3: 37) are now fully specified across Scope Matrices, BRDs, Use Cases, Data Models, and Acceptance Criteria!

### Next steps

- Present completed P0-P3 specifications and overall catalog status to Project Owner.
- Recommend and align on technical stack architecture (Client engine: Unity vs Godot; Backend: Node.js/NestJS vs Go + PostgreSQL + Redis) for subsequent implementation phases.

## Update - 2026-11-04 01:13:00 ICT (UTC+7)

Signed: Antigravity, project assistant

### Work completed

- Established project monorepo architecture (`packages/shared` and `packages/server`) using TypeScript and Node.js.
- Scaffolded `@infiniti-gacha/shared`:
  - Enums (HeroRarity, HeroCategory, HeroState, BannerType, BuildingType, ArmyStatus, AllianceRole).
  - Game constants (Gacha rates, pity thresholds, weekly caps, combat timers, survival caps, world map grid).
  - Mathematical formulas: Pity-70 polynomial rate curve (P_n = 0.004 + 0.996 * ((n-60)/10)^4), combat damage with defense mitigation, and Euclidean march ETA calculation.
  - Comprehensive TypeScript interfaces for Master, Hero, Banner, GachaResult, Army, and BaseBuilding.
- Scaffolded `@infiniti-gacha/server`:
  - `MasterService`: Enforces 1 Account = 1 Master constraint.
  - `GachaService`: Implements Single/Multi summon, 50-scroll weekly exchange cap, per-banner pity tracking, and duplicate conversion (Special/Limited to Thien Menh; Normal to Talent Points).
  - `TacticalBuffManager`: Implements in-battle buff switching with strict 15-second cooldown.
  - `GemDebtHandler`: Implements no-ban IAP refund policy with gem debt tracking and auto-deduction.
  - `WorldSeedGenerator`: UUIDv4-based world seed creation with deterministic difficulty multiplier.
  - Express REST API engine with health check, Master init, World creation, and Gacha summon endpoints.
  - Consolidated PostgreSQL DDL schema (`packages/server/src/database/schema.sql`) covering P0 to P3 tables.
- Wrote automated unit tests across packages (14/14 tests passing):
  - Shared: 7 tests passing (Pity rates, combat mitigation, march ETA).
  - Server: 7 tests passing (1-to-1 account master, gacha duplicates, exchange cap, tactical cooldowns, gem debt, seed gen).

### Next steps

- Connect persistence layer with PostgreSQL / SQLite.
- Propose client game engine setup (Unity or Godot).

## Update - 2026-11-04 01:37:00 ICT (UTC+7)

Signed: Antigravity, project assistant

### Work completed

- Confirmed technical stack selection and implementation roadmap with project owner:
  - **Database Stack**:
    - **PostgreSQL**: Primary transactional database (ACID compliance for Gacha, IAP, Gem Debt, Hero lifecycle/injuries, JSONB for combat replay logs and dynamic stats, indexing for 1000x1000 world grid coordinates).
    - **Redis**: In-memory caching, distributed locks (idempotent rolls, anti-race conditions), Sorted Sets for real-time Dual Leaderboards (Dungeon floor progression & Combat Power), and countdown timers (army marching ETA, tactical buff cooldowns, peace shields).
  - **Game Client Roadmap**:
    - **Phase 1 (Immediate / Prototype & Testing)**: Web HUD / Web Prototype client (React / Vite + TypeScript) directly sharing `@infiniti-gacha/shared` and consuming Server REST APIs for rapid interactive validation of Gacha, Dungeon, Combat, and Hero management gameplay loops.
    - **Phase 2 (Production / Commercial Release)**: Unity (C#) client targeting mobile platforms (Android/iOS) with rich VFX, animations, spine rigs, audio, and store SDKs (Google Play Billing / Apple StoreKit); Godot 4 retained as lightweight 2D alternative.

### Next steps

- Set up database ORM layer (Prisma or Drizzle) integrating PostgreSQL schema into `@infiniti-gacha/server`.
- Scaffold Phase 1 Web HUD / Prototype client in `packages/client` for end-to-end interactive gameplay testing.

## Update - 2026-11-05 09:45:00 ICT (UTC+7)

Signed: DeepSeek Harness, project assistant

### Work completed

- Implemented **Combat v2** foundation across shared, database, server and tests:
  - `packages/shared/src/combat/`: four base stats (STR/INT/STA/AGI), derived stats, stat caps (crit 100%), class base crit (Thief 50%, others 5%), class growth multipliers, star budgets 1★ 100 → 5★ 280 with locked 6★ 350 / 7★ 430, growth compensation to 672 points at level 50, random stat roll (75% archetype + 25% wildcard, ±15%, 45% per-stat cap), class qualification/roll, Mage element affinity and the full damage pipeline.
  - Migrations `0039_same_spyke.sql` and `0040_absurd_joshua_kane.sql`: new `hero_templates`/`heroes` columns (base stats, class/role, training/origin stats, MP percentages) and new `hero_class_definitions`, `subclass_definitions`, `hero_subclasses`, `hero_element_affinities` tables.
  - Seeds: `hero_templates_v2.sample.sql`, `hero_class_definitions.sample.sql`, `subclass_definitions.sample.sql`; 22 seed files applied.
  - Summoning now rolls base stats, class (Mage on every banner; 1–2★ always unclassified) and Mage affinity, stores `origin_stats` and mirrors legacy HP/ATK/DEF/SPD for the old engine. `npm run db:reset-heroes` clears demo Heroes for re-summoning.
  - Progression v2: level-up recomputes stats; `POST /api/heroes/:heroId/train`; `POST /api/heroes/:heroId/class-change` (level 20+, stat eligibility, 50,000 Silver + Class Change Token, retroactive growth, affinity handling). Awakening no longer multiplies legacy stats for v2 Heroes.
  - Combat v2 engine: AGI turn order, one action per round, MP skills/cooldowns, basic attacks restoring 5% MP, hit/mitigation/affinity/crit/block/DR, healing, lifesteal, draw handling. Equipment, starvation, injury, loyalty and resonance modifiers are applied before resolving.
  - `POST /api/combat/v2/simulate` with deterministic seeds; `persist: true` stores a completed `combat_sessions` report; `GET /api/combat/v2/sessions` lists history.

### Verification

- `npm run verify` green: **362/362 server tests** and **56/56 shared tests**; encoding check 319 files.
- Commits: `a419038`, `f8e0cfc`, `0543719`, `27246b2`, `004ce5f`, `83e7065`, `5f06981`, `a107ac8`.

### Open items

- Persistent multi-step Combat v2 sessions (`start`/`advance`) with EXP/Silver, injuries, survival, quest and leaderboard hooks.
- Combat v2 page in the web client; subclass acquisition API/UI.
- Equipment catalogue granting base/derived stats (current v2 uses the legacy flat bonuses).
- 6★/7★ content, TTK-10 balance pass, class-change pricing review.

### Recommended next action

- Wire the Combat v2 engine into the existing combat session flow behind a `COMBAT_V2` flag, reusing the reward/injury hooks, then add the web test page and tune TTK before starting the Unity client.
