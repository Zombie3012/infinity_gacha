# Acceptance Criteria Specification — Phase P0

> **L?u tr? thi?t k? l?ch s?.** Checklist v? k?t qu? ki?m tra ph?n ?nh th?i ?i?m vi?t; c?c m? t? Web/Unity, pity v? duplicate c? th? ?? ???c thay th?. Xem [README hi?n h?nh](../../README.md) v? [backlog Godot](../../GODOT_BACKLOG.md), c?p nh?t 22/11/2026 (UTC+7).

| Field | Value |
|---|---|
| Document ID | IG-BA-AC-P0-001 |
| Version | 1.0 Draft |
| Project | Infinite Gacha (Hero Management & Survival Strategy RPG) |
| Source Baseline | BRD_P0_Draft.md, Use_Case_Spec_P0_Draft.md, Data_Model_P0_Draft.md |
| Target Scope | 21 Use Cases (164 P0 Functions) |

---

## 1. Overview & Standard Conventions

This document specifies the exact, testable **Acceptance Criteria (AC)** for all 21 Use Cases included in Phase P0. Every scenario is formatted according to standard BDD syntax (**Given - When - Then**) and defines preconditions, positive paths, edge conditions, boundary values, and system error responses.

### Global Testing Assumptions:
- All financial, gacha, and inventory modifications must be committed in single, atomic database transactions (`ACID`).
- Date/Time comparisons for weekly resets use **UTC+7** timezone.
- Floating-point probabilities for Gacha and Combat use deterministic server-side PRNG seeds.

---

## 2. Detailed Acceptance Criteria by Use Case

### UC-P0-01: Create and Access Account
**Covered Functions:** `FUN-01-01-001`, `FUN-01-01-002`, `FUN-01-01-003`, `FUN-01-01-006`

#### Scenario 1.1: Successful Account Registration
- **Given** a new player provides a unique `username` (3–32 alphanumeric chars) and a secure `password` (>= 8 chars).
- **When** the registration request is submitted.
- **Then** the system creates a new record in `accounts` with `status = 'ACTIVE'` and password hashed with Argon2id/Bcrypt.
- **And** an empty profile record is created in `profiles`.
- **And** an HTTP 201 response is returned with authentication token (JWT).

#### Scenario 1.2: Duplicate Username Rejection
- **Given** an existing account with username `"Master01"`.
- **When** another registration attempt is made with `"Master01"` (case-insensitive).
- **Then** the system rejects the registration with error `ERR_AUTH_USERNAME_EXISTS`.
- **And** no duplicate account is created.

#### Scenario 1.3: Successful Login & Session Token Generation
- **Given** an existing active account with valid credentials.
- **When** the player submits matching username and password.
- **Then** the system issues an authenticated session token.
- **And** loads the player's profile and linked Master ID (if already initialized).

#### Scenario 1.4: Suspended or Banned Account Access
- **Given** an account with `status = 'BANNED'` or `'SUSPENDED'`.
- **When** the player attempts to log in.
- **Then** the system denies login with error `ERR_AUTH_ACCOUNT_RESTRICTED`.

#### Scenario 1.5: Logout Revokes the Current Session
- **Given** an authenticated player with a live session token.
- **When** the player logs out.
- **Then** the server revokes that session, and subsequent API requests using its token are rejected.

#### Scenario 1.6: Restricted Account Loses API Access
- **Given** an account status changed to `SUSPENDED` or `BANNED` by a trusted operator.
- **When** the account logs in or uses an existing session.
- **Then** the request is denied with `ERR_AUTH_ACCOUNT_RESTRICTED`.

---

### UC-P0-02: View and Update Player Profile
**Covered Functions:** `FUN-01-02-001`, `FUN-01-02-002`, `FUN-01-02-003`, `FUN-01-02-004`

#### Scenario 2.1: View Profile Information
- **Given** an authenticated player.
- **When** the player requests their profile.
- **Then** the system returns `display_name`, `avatar_url`, custom `settings`, and aggregated `progress_summary`.

#### Scenario 2.2: Update Profile Attributes
- **Given** an authenticated player.
- **When** the player submits an updated `display_name` (1–32 valid characters) or valid `avatar_url`.
- **Then** the system persists changes in `profiles` and returns updated state.

#### Scenario 2.3: Reject Invalid Profile Updates
- **Given** a display name containing forbidden characters or profanity.
- **When** the update request is received.
- **Then** the system rejects changes with error `ERR_PROFILE_INVALID_NAME` and retains the old profile.
- **And** the prototype accepts Unicode letters, numbers, spaces, underscores, and hyphens; configured prohibited terms are supplied through `PROFILE_PROFANITY_TERMS`.

---

### UC-P0-03: Initialize and Progress Master
**Covered Functions:** `FUN-01-03-001`, `FUN-01-03-002`, `FUN-01-03-003`, `FUN-01-03-004`, `FUN-01-03-005`, `FUN-01-03-006`, `FUN-08-01-001`

#### Scenario 3.1: Strict Single Master Initialization
- **Given** an authenticated account that has never initialized a Master.
- **When** the player triggers Master initialization with a valid commander name.
- **Then** the system creates exactly 1 record in `masters` with `level = 1`, `current_exp = 0`.
- **And** creates exactly 1 linked `private_worlds` record with a globally unique `world_seed` (UUID).
- **And** initializes `master_currencies` wallet (0 Silver Coins, 0 Scrolls, 0 Gems).

#### Scenario 3.2: Rejection of Second Master
- **Given** an account that already owns a Master record.
- **When** another request to initialize a Master is received for the same `account_id`.
- **Then** the system rejects the transaction with error `ERR_MASTER_ALREADY_EXISTS`.

#### Scenario 3.3: Master EXP Accumulation and Level Up
- **Given** a Master with `level = 1`, `current_exp = 800`, and required EXP for Level 2 is `1000`.
- **When** the system awards `300` Master EXP from combat or quest.
- **Then** `current_exp` increases to `1100`, triggering a level-up event.
- **And** `level` becomes `2`, remaining `current_exp` carries over (`100`).
- **And** `skill_points` increments according to configuration.

#### Scenario 3.4: Sample Master Team Regeneration
- **Given** an active PvE session and the sample `TEAM_REGENERATION` Master skill is unlocked.
- **When** the Master activates the skill.
- **Then** every living party Hero recovers 1% of maximum HP once per real-time second for 5 seconds, capped at maximum HP.
- **And** the skill cannot be activated again until its configured 15-second cooldown expires.

#### Scenario 3.5: Feature Unlock Enforcement
- **Given** feature unlock rows define a minimum Master level for each feature.
- **When** an authenticated Master requests a feature above their level.
- **Then** the API rejects access until the Master reaches the configured level.
- **And** the feature list reports each feature's required level and current unlocked state.

---

### UC-P0-04: Configure and View Summon Banners
**Covered Functions:** `FUN-02-01-001`, `FUN-02-01-002`, `FUN-02-01-003`, `FUN-02-01-004`, `FUN-02-01-005`, `FUN-02-01-006`

#### Scenario 4.1: View Active Banners Only
- **Given** 3 configured banners in database: 1 active, 1 expired, 1 future scheduled.
- **When** a player requests the banner catalog.
- **Then** the system returns only banners where `is_active = TRUE` and `NOW() BETWEEN start_time AND end_time`.

#### Scenario 4.2: Inspect Banner Details & Rate Disclosure
- **Given** an active banner.
- **When** player views banner details.
- **Then** system displays full rate breakdown: 5★ base rate (0.40%), 1★-4★ group rate (49.60%), Materials group rate (50.00%), active Hero pool, and current Pity progress.

---

#### Scenario 4.3: Configure Banner and Hero Pool
- **Given** an operator supplies the configured `ADMIN_API_KEY`.
- **When** the operator creates a banner, sets its type, and configures its pool.
- **Then** the API accepts only pools containing 5-star Heroes, 1–4 star Heroes, and Materials with positive weights and matching Hero templates.
- **And** configuration requests without the admin key are rejected.

#### Scenario 4.4: Schedule, Activate, and Overlap Banners
- **Given** a configured banner has a valid start/end time and complete pool.
- **When** the operator activates it.
- **Then** it appears in the player catalog only during its schedule.
- **And** scheduled banners may overlap, including banners of the same type.

### UC-P0-05: Perform a Normal Summon
**Covered Functions:** `FUN-02-02-001`, `FUN-02-02-002`, `FUN-02-02-003`, `FUN-02-02-004`

#### Scenario 5.1: Normal Single Summon Success
- **Given** an authenticated Master with `white_scrolls >= 1` on an active Normal Banner.
- **When** the player requests a Single Summon.
- **Then** the system atomically deducts exactly `1` white scroll from `master_currencies`.
- **And** generates 1 roll based on Pity counter and pool weights.
- **And** increments `player_banner_pity.pity_count` by 1 (unless 5★ obtained).
- **And** inserts roll record into `summon_history`.

#### Scenario 5.2: Normal Multi Summon Success (10 Rolls)
- **Given** an authenticated Master with `white_scrolls >= 10`.
- **When** the player requests a Multi Summon.
- **Then** the system atomically deducts exactly `10` white scrolls.
- **And** evaluates 10 sequential rolls, updating the pity counter after each roll.
- **And** does NOT force-guarantee any 4★ or higher item simply for doing a Multi summon.

#### Scenario 5.3: Insufficient Normal Scrolls
- **Given** an authenticated Master with `white_scrolls = 0`.
- **When** a Single Summon is requested.
- **Then** the request is rejected with `ERR_GACHA_INSUFFICIENT_SCROLLS`.
- **And** no rolls occur; wallet remains unchanged.

---

### UC-P0-06: Perform a Special or Limited Summon
**Covered Functions:** `FUN-02-03-001`, `FUN-02-03-002`, `FUN-02-03-003`, `FUN-02-03-004`, `FUN-02-03-005`, `FUN-02-03-006`

#### Scenario 6.1: Limited Single Summon Success
- **Given** an active Limited Banner and Master wallet with `red_scrolls >= 1`.
- **When** player executes Limited Single Summon.
- **Then** system consumes 1 red scroll.
- **And** any summoned Hero receives immutable origin `summon_origin = 'LIMITED'`.

#### Scenario 6.2: Special Single Summon Success
- **Given** an active Special Banner and Master wallet with `seven_color_scrolls >= 1`.
- **When** player executes Special Single Summon.
- **Then** system consumes 1 seven-color scroll.
- **And** any summoned Hero receives immutable origin `summon_origin = 'SPECIAL'`.

---

### UC-P0-07: Calculate Summon Probability and Pity
**Covered Functions:** `FUN-02-04-001`, `FUN-02-04-002`, `FUN-02-04-003`, `FUN-02-04-004`, `FUN-02-04-005`, `FUN-02-04-006`

#### Scenario 7.1: Base Rate on Rolls 1 to 60
- **Given** a banner pity counter between `0` and `59`.
- **When** a summon roll is evaluated.
- **Then** the 5★ Hero probability is strictly `0.004` (0.40%).
- **And** remaining probability is divided: `0.496` for 1★-4★ Heroes, `0.500` for Materials.

#### Scenario 7.2: Polynomial Rate Growth on Rolls 61 to 69
- **Given** a banner pity counter at roll $n \in [61, 69]$.
- **When** the probability is calculated.
- **Then** the 5★ chance equals $P_n = 0.004 + (1 - 0.004) \times \left(\frac{n - 60}{10}\right)^4$.
- **And** the remaining probability is divided between 1★-4★ Heroes and Materials in the base ratio `49.6:50`.
- **Examples:**
  - At roll 65: $P_{65} = 0.4\% + 99.6\% \times (0.5)^4 = 0.4\% + 6.225\% = 6.625\%$.
  - At roll 69: $P_{69} = 0.4\% + 99.6\% \times (0.9)^4 = 0.4\% + 65.347\% = 65.747\%$.

#### Scenario 7.3: Guaranteed 5★ on Roll 70
- **Given** a banner pity counter reaching `70` without any 5★ pulled.
- **When** roll 70 is resolved.
- **Then** 5★ probability is guaranteed ($100\%$).
- **And** any 5★ Hero present in the active banner pool is awarded.
- **And** `player_banner_pity.pity_count` resets to `0`.

#### Scenario 7.4: Pity Reset on Natural 5★ Pull
- **Given** a banner pity counter at `42`.
- **When** the player pulls a 5★ Hero naturally.
- **Then** `player_banner_pity.pity_count` immediately resets to `0`.

#### Scenario 7.5: Per-Banner Counter Isolation (No Carry-over)
- **Given** Master has `pity_count = 45` on Limited Banner A.
- **When** Limited Banner B opens.
- **Then** Limited Banner B begins with `pity_count = 0`.
- **And** counter on Banner A remains isolated and unaffected.

---

### UC-P0-08: Convert Duplicates and Record Summon Origin
**Covered Functions:** `FUN-02-05-001`, `FUN-02-05-002`, `FUN-02-05-003`, `FUN-02-05-004`

#### Scenario 8.1: First-Time Hero Acquisition
- **Given** a summon result generates Hero Template `HERO_VALKYRIE_01` which the Master does not own.
- **When** the summon is resolved.
- **Then** a new record in `hero_instances` is inserted with `template_id = 'HERO_VALKYRIE_01'`, `level = 1`, `status = 'ALIVE'`.
- **And** `summon_origin` is set to the current banner's origin (`NORMAL`, `SPECIAL`, or `LIMITED`).

#### Scenario 8.2: Duplicate 5★+ Hero on Special/Limited Banner (Thiên Mệnh Conversion)
- **Given** Master already owns a 5★ Hero `HERO_SOLAR_01` with `summon_origin = 'LIMITED'` or `'SPECIAL'` and `thien_menh = 0`.
- **When** another copy of `HERO_SOLAR_01` is pulled from a Limited or Special banner.
- **Then** the system does NOT create a second instance in `heroes`.
- **And** increments `thien_menh` by `1` (`thien_menh = 1`).

#### Scenario 8.3: Normal Banner and 1★–4★ Summons Create Independent Instances
- **Given** Master already owns a `NORMAL` Hero `HERO_WARRIOR_01`.
- **When** another copy of `HERO_WARRIOR_01` is pulled from a Normal banner.
- **Then** the system creates a NEW independent record in `heroes` with its own unique `id`.
- **And** dynamically rolls level-1 base stats (STR, INT, STA, AGI) according to its star rating budget.
- **And** the new instance can be trained, specialized, or used as fodder for Star Promotion (Pick Me Up style).

---

### UC-P0-09: View and Organize Hero Collection
**Covered Functions:** `FUN-03-01-001`, `FUN-03-01-002`, `FUN-03-01-003`, `FUN-03-01-004`, `FUN-03-01-005`, `FUN-03-01-006`

#### Scenario 9.1: List and Filter Heroes
- **Given** Master owns 15 Heroes of varying Classes, Rarities, and Statuses.
- **When** player applies filter `class = 'MAGE'` and `status = 'ALIVE'`.
- **Then** system returns only matching Hero instances.

#### Scenario 9.2: Toggle Hero Lock
- **Given** an unlocked Hero instance (`is_locked = FALSE`).
- **When** the player triggers lock toggle.
- **Then** system updates `is_locked = TRUE`, preventing accidental disposal or reset.

---

### UC-P0-10: Develop Hero Attributes and Skills
**Covered Functions:** `FUN-03-02-001` through `FUN-03-02-006`, `FUN-03-03-001` through `FUN-03-03-004`

#### Scenario 10.1: Hero Level Up
- **Given** an alive Hero with `level = 10` and Master possesses sufficient EXP materials.
- **When** the player commits level-up action.
- **Then** materials are deducted and Hero `level` increases.
- **And** derived base attributes (HP, ATK, DEF) increase according to growth coefficients.

#### Scenario 10.2: Prevent Development on Dead Normal Hero
- **Given** a Normal Hero instance with `status = 'DEAD'`.
- **When** any level-up or skill upgrade is attempted.
- **Then** system rejects with error `ERR_HERO_PERMANENTLY_DEAD`.

---

### UC-P0-11: Resolve Hero Death
**Covered Functions:** `FUN-04-01-001`, `FUN-04-01-002`, `FUN-04-01-003`, `FUN-04-01-004`, `FUN-04-01-005`, `FUN-04-01-006`

#### Scenario 11.1: Permadeath of Normal Hero with Equipment Drop
- **Given** a Hero with `summon_origin = 'NORMAL'` and `status = 'ALIVE'` equipped with a sword and shield.
- **When** HP reaches 0 in battle and combat finishes.
- **Then** the Hero's status updates to `status = 'DEAD'`, and `death_at` is set to `NOW()`.
- **And** each equipped item is moved to a `FLOOR_DROP` at the current World and floor, and is not available in inventory until picked up.
- **And** the Master can retrieve the drop from their own World and move it to inventory.
- **And** a `hero_death_records` row is inserted with `death_type = 'PERMADEATH'` and a snapshot of dropped items.
- **And** previously spent upgrade/training resources are strictly NOT refunded.

#### Scenario 11.2: Disabled State for Special or Limited Hero
- **Given** a Hero with `summon_origin = 'LIMITED'` or `'SPECIAL'`.
- **When** HP reaches 0 in battle.
- **Then** Hero status updates to `status = 'DISABLED'`.
- **And** equipped gear is NOT dropped.
- **And** Hero becomes ineligible for active party slots until recovered.

---

### UC-P0-12: Create a Party and Formation
**Covered Functions:** `FUN-05-01-001` through `FUN-05-01-005`, `FUN-05-02-001` through `FUN-05-02-004`, `FUN-05-03-001` through `FUN-05-03-004`

#### Scenario 12.1: Valid Squad Assignment (1 to 5 Heroes)
- **Given** Master owns available, alive Heroes.
- **When** player assigns 3 Heroes into slots 1, 2, and 3 of Party 1.
- **Then** system saves `formation_slots` mappings and marks squad as valid.

#### Scenario 12.2: Rejection of Dead or Disabled Hero
- **Given** a Hero with `status = 'DEAD'` or `status = 'DISABLED'`.
- **When** player attempts to assign this Hero to a formation slot.
- **Then** system rejects with error `ERR_FORMATION_HERO_UNAVAILABLE`.

#### Scenario 12.3: Rejection of Duplicate Hero in Same Party
- **Given** Hero instance `H-001` is already in slot 1 of Party 1.
- **When** player attempts to assign `H-001` to slot 2 of Party 1.
- **Then** system rejects the assignment with `ERR_FORMATION_DUPLICATE_HERO`.

---

### UC-P0-13: Initialize and Execute Auto Battle
**Covered Functions:** `FUN-06-01-001` through `FUN-06-01-004`, `FUN-06-02-001` through `FUN-06-02-006`, `FUN-06-03-001` through `FUN-06-03-005`, `FUN-06-04-001` through `FUN-06-04-006`

#### Scenario 13.1: Autonomous Combat Execution
- **Given** a valid party of alive Heroes entering an encounter.
- **When** battle starts.
- **Then** AI selects actions and targets autonomously based on Hero stats, skills, and threat priority.
- **And** combat resolves sequentially without requiring manual turn-by-turn input.

#### Scenario 13.2: Tactical Buff Invocation & Cooldown
- **Given** Master has an active battle.
- **When** Master applies a Tactical Buff (e.g. +10% ATK).
- **Then** the buff is applied to the combat state.
- **And** a 15-second cooldown timer starts (`cooldown_expires_at = NOW() + 15s`).

#### Scenario 13.3: Rejection of Tactical Buff During Cooldown
- **Given** a Tactical Buff was invoked 7 seconds ago.
- **When** Master attempts to switch or reapply a Tactical Buff.
- **Then** system rejects action with error `ERR_TACTICAL_BUFF_COOLDOWN_ACTIVE` (8 seconds remaining).

---

### UC-P0-14: Process Battle Result and Report
**Covered Functions:** `FUN-06-05-001` through `FUN-06-05-007`

#### Scenario 14.1: Victory Resolution
- **Given** all enemy combatants reach 0 HP.
- **When** battle terminates.
- **Then** `result = 'VICTORY'`.
- **And** eligible surviving Heroes receive Battle EXP.
- **And** rewards are generated and added to `inventory_items` / `master_currencies`.
- **And** full battle turn report is saved in `battles.battle_report`.

#### Scenario 14.2: Defeat Resolution
- **Given** all player Heroes reach 0 HP.
- **When** battle terminates.
- **Then** `result = 'DEFEAT'`.
- **And** death consequences (UC-P0-11) are triggered for all fallen Heroes.

---

### UC-P0-15: Configure Dungeon, Seed, and Generation
**Covered Functions:** `FUN-07-01-001` through `FUN-07-01-004`, `FUN-07-02-001` through `FUN-07-02-005`, `FUN-07-03-001` through `FUN-07-03-005`

#### Scenario 15.1: Immutable World Seed Generation
- **Given** a newly initialized Private World.
- **When** `FUN-07-02-001` executes.
- **Then** a standard Version 4 UUID is stored as `private_worlds.world_seed`.
- **And** this Seed remains strictly permanent across the lifetime of this World.

#### Scenario 15.2: Deterministic Procedural Reconstruction
- **Given** a World with Seed `S` and Dungeon Floor `F`.
- **When** the floor map, room layout, and monster distribution are generated.
- **Then** supplying Seed `S` and Floor `F` into the generation algorithm always produces the exact identical floor structure.

---

### UC-P0-16: Progress Through Dungeon and Claim Rewards
**Covered Functions:** `FUN-07-04-001` through `FUN-07-04-006`, `FUN-07-05-001` through `FUN-07-05-006`, `FUN-07-06-001` through `FUN-07-06-004`

#### Scenario 16.1: Floor Completion & Unlock
- **Given** player clears Floor 1 Boss room.
- **When** floor is marked completed.
- **Then** system flags Floor 1 as cleared, grants first-clear / clear rewards.
- **And** unlocks Floor 2 access in `player_dungeon_progress`.

#### Scenario 16.2: Floor Failure Does Not Regenerate Seed
- **Given** player squad suffers defeat on Floor 3.
- **When** `Handle Floor Failure` executes.
- **Then** the exploration instance ends with `status = 'FAILED'`.
- **And** `private_worlds.world_seed` remains unchanged.

---

### UC-P0-17: Manage Basic Inventory
**Covered Functions:** `FUN-10-01-001` through `FUN-10-01-007`

#### Scenario 17.1: Add and Stack Inventory Items
- **Given** player already holds 5 `MATERIAL_IRON` in bag (stack limit 9999).
- **When** player acquires 10 more `MATERIAL_IRON`.
- **Then** system updates existing stack quantity to 15.

#### Scenario 17.2: Item Removal and Overdraw Prevention
- **Given** player holds 3 potion items.
- **When** a consumption event requests 4 potions.
- **Then** system rejects transaction with `ERR_INVENTORY_INSUFFICIENT_QUANTITY`.
- **And** quantity remains 3.

---

### UC-P0-18: Manage Currency and Exchange Normal Scrolls
**Covered Functions:** `FUN-11-01-001` through `FUN-11-01-007`

#### Scenario 18.1: Successful Silver Coin to Scroll Exchange
- **Given** Master has `silver_coins = 50,000` and current week exchange count is `0`.
- **When** Master requests exchange for `3` white Normal Heavenly Scrolls (30,000 Silver Coins).
- **Then** system deducts `30,000` Silver Coins (`balance = 20,000`).
- **And** increments `white_scrolls` by `3`.
- **And** updates `weekly_exchange_limits.exchanges_count` from `0` to `3`.
- **And** logs transaction in `currency_transactions`.

#### Scenario 18.2: Weekly Cap Reached (Max 50)
- **Given** Master has already exchanged `48` scrolls in the current weekly window.
- **When** Master requests exchange for `5` scrolls.
- **Then** system rejects transaction with error `ERR_EXCHANGE_WEEKLY_CAP_EXCEEDED` (only 2 remaining).
- **And** no coins are deducted; no scrolls granted.

#### Scenario 18.3: Weekly Reset at Thursday 00:00 UTC+7
- **Given** Master reached `exchanges_count = 50` during week `W44`.
- **When** wall-clock time passes Thursday 00:00:00 UTC+7 into new week `W45`.
- **Then** system initializes a new `weekly_exchange_limits` entry for week `W45` with `exchanges_count = 0`.
- **And** Master is immediately allowed to exchange up to 50 scrolls again.

---

### UC-P0-19: Configure Gacha and Dungeon Rules
**Covered Functions:** `FUN-14-03-001` through `FUN-14-03-006`

#### Scenario 19.1: Administrative Rule Update with Versioning
- **Given** an authorized Game Designer (ACT-06) updating Pity exponent parameter $k$.
- **When** new configuration is submitted.
- **Then** system creates an incremented version in `system_configs` with `updated_by = 'ACT-06'`.
- **And** logs the change in `audit_logs`.
- **And** active runtime pointer switches to the new version without server restart.

---

### UC-P0-20: Monitor and Protect the Game
**Covered Functions:** `FUN-14-05-006`, `FUN-14-06-003`, `FUN-14-06-004`, `FUN-14-06-005`, `FUN-14-06-006`

#### Scenario 20.1: Anti-Cheat & Rapid Request Detection
- **Given** an account issuing 100 combat completion requests within 1 second.
- **When** anomaly monitor processes the inbound rate.
- **Then** system flags account in `security_alerts` with `severity = 'HIGH'`.
- **And** temporarily restricts session to prevent database exploitation.

---

### UC-P0-21: Manage Basic Equipped Items
**Covered Functions:** `FUN-10-02-001` through `FUN-10-02-005`

#### Scenario 21.1: Equip Compatible Item
- **Given** an alive Hero and an unequipped sword in player's `equipment_instances`.
- **When** player equips the sword to the Hero's `MAIN_HAND` slot.
- **Then** sword record updates to `hero_instance_id = Hero.id` and `is_equipped = TRUE`.
- **And** Hero derived stats immediately reflect the sword's bonus ATK.

#### Scenario 21.2: Unequip Item
- **Given** a Hero currently wearing armor in `CHEST` slot.
- **When** player unequips the armor.
- **Then** armor updates to `hero_instance_id = NULL` and `is_equipped = FALSE`.
- **And** Hero derived DEF stats are reduced accordingly.

#### Scenario 21.3: Slot Conflict Replacement
- **Given** Hero already has Sword A in `MAIN_HAND`.
- **When** player equips Sword B to `MAIN_HAND`.
- **Then** Sword A is automatically unequipped (`hero_instance_id = NULL`), and Sword B is equipped.

---

## 3. Summary of Core Verification Matrix

| Category | Target Rule | Verification Path |
|---|---|---|
| **Account** | 1 Account = 1 Master | `masters.account_id` Unique constraint test |
| **Gacha Rate** | 50% Hero / 50% Material | Monte Carlo roll tests on base pool |
| **Pity Curve** | 0.4% at roll 1-60; $k=4$ polynomial on 61-69; 100% on 70 | Formula evaluation test at $n=60, 65, 69, 70$ |
| **Duplicate** | 5★+ Special/Limited -> +1 Thiên Mệnh; Normal & 1★–4★ -> New Instance with rolled stats | Gacha resolution tests |
| **Hero Death** | Normal -> Permadeath + Gear drop; Special -> Disabled | Battle casualty resolution tests |
| **Seed** | Globally unique UUID; fixed for World | World initialization and regeneration test |
| **Buff** | 15s Tactical Buff Cooldown | Cooldown timer boundary tests (at 14s vs 16s) |
| **Economy** | 10k Silver = 1 Scroll; max 50 / week; Reset Thu 00:00 UTC+7 | Transaction limit and scheduled reset tests |

#### Scenario 21.4: Collect Gear Dropped by a Normal Hero
- **Given** a Normal Hero is equipped with an item and dies during a PvE battle.
- **When** the battle result is committed.
- **Then** the equipment instance is stored as a `FLOOR_DROP` linked to the same World and floor.
- **And** the item is absent from the equipment inventory until explicitly picked up.
- **When** the owning Master picks up the item from their World drop list.
- **Then** the item returns to `INVENTORY` and can be equipped again.

#### Scenario 16.1: Deterministic Sample Floor Content
- **Given** a World Seed and current floor with active sample enemy and event configuration.
- **When** the Master starts the same floor again after a defeat.
- **Then** the selected sample event and enemy roster are derived from the same World Seed and floor.
- **And** a sample cache reward is granted only after floor victory.

#### Scenario 16.2: Advance Floor on Victory
- **Given** a battle is active on the World's current floor.
- **When** all enemies are defeated.
- **Then** the battle report stores the completed floor and the World current floor advances by one.

#### Scenario 16.3: Keep Floor on Defeat
- **Given** a battle is active on the World's current floor.
- **When** all party Heroes are defeated.
- **Then** the report records defeat and the World's current floor remains unchanged.
