# P0 Implementation Checklist

> **L?u tr? thi?t k? l?ch s?.** Checklist v? k?t qu? ki?m tra ph?n ?nh th?i ?i?m vi?t; c?c m? t? Web/Unity, pity v? duplicate c? th? ?? ???c thay th?. Xem [README hi?n h?nh](../../README.md) v? [backlog Godot](../../GODOT_BACKLOG.md), c?p nh?t 22/11/2026 (UTC+7).

## Project Context
- Scope Document: `Phase_Scope_Matrix_P0.csv`
- Specification Reference: `Use_Case_Spec_P0_Draft.md` & `Data_Model_P0_Draft.md`
- Monorepo Packages: `@infiniti-gacha/shared`, `@infiniti-gacha/server`, `@infiniti-gacha/client`

## Progress Summary
- Domain 01 (Authentication & Authorization): Done
- Domain 02 (Master System & Profile): Done
- Domain 03 (Hero System): Done (Levels 1–20, EXP table, Promotion & Awakening stats/caps, Skill instances & leveling, Lock/Unlock)
- Domain 04 (Permadeath & Survival): Done (Normal permadeath with floor drop, Special/Limited disable, Death records)
- Domain 05 (Formation & Party Management): Done (Parties CRUD, default party, formation slot assignment, order reordering, active hero validations)
- Domain 06 (Combat & Battle Mechanics): Done (MOD-06-01 to MOD-06-05 complete: initialization, AI auto battle, assist strikes, mechanics, buffs, target priorities, retreat, battle report, casualties, reward distribution)
- Domain 07 (World & Dungeon System): Done (MOD-07-01 to MOD-07-06 complete: dungeon templates, floor configurations, unlock requirements, base & first-clear rewards, deterministic World Seed generation, algorithmic versioning, procedural room layouts, encounters & events, floor progression, and reward distribution)
- Domain 08 (Private World Management): Done (MOD-08-01: Auto-initialization on Master creation, manual creation, GET /api/world anchor, fixed World Seed binding)
- Domain 10 (Inventory & Equipment Management): Done (MOD-10-01 Item Inventory View, Filter, Sort, Add, Remove, Use EXP books, Sell for Silver; MOD-10-02 Equipment equip/unequip, slot replacement, floor drop recovery)
- Domain 11 (Currency Management): Done (MOD-11-01 View Silver & Summon tickets, Add/Deduct currency with validation, transaction history, weekly 50-scroll exchange limit with Thursday 00:00 UTC+7 reset)
- Domain 14 (Administration, Operations & Security): Done (MOD-14-03 versioned rule configuration for all six rule families, MOD-14-05 system monitoring, MOD-14-06 audit log + rate-based anti-cheat/abuse alerts + alert resolution).

---

### Detailed Domain Checklists

#### Domain 08: Private World Management
- [x] DM-08 / MOD-08-01 Private World Management:
  - FUN-08-01-001: Initialize Private World (auto-created during `POST /api/master/init` and manual via `POST /api/world/create`; returns World Seed, difficulty multiplier, algorithm version).
  - API endpoint: `GET /api/world` returning Master's active world details.

#### Domain 10: Inventory Management & Basic Equipment
- [x] DM-10 / MOD-10-01 Inventory Management:
  - FUN-10-01-001: View Inventory (`GET /api/inventory` returning enriched items with metadata and summon scroll counts).
  - FUN-10-01-002: Filter Inventory (by category: ALL, DEVELOPMENT, MATERIAL).
  - FUN-10-01-003: Sort Inventory (QUANTITY_DESC, RARITY_DESC, NAME_ASC).
  - FUN-10-01-004: Add Item (`inventoryService.addItem(masterId, itemId, quantity)`).
  - FUN-10-01-005: Remove Item (`inventoryService.removeItem(masterId, itemId, quantity)`).
  - FUN-10-01-006: Use Item (`POST /api/inventory/items/:itemId/use` for Hero EXP books, leveling up hero respecting promotion cap).
  - FUN-10-01-007: Sell Item (`POST /api/inventory/items/:itemId/sell` exchanging items for Silver coins and logging currency transactions).
- [x] DM-10 / MOD-10-02 Equipment Management (basic P0 scope):
  - FUN-10-02-001: View Equipment (`GET /api/equipment` listing inventory and equipped gear).
  - FUN-10-02-002: Equip Item (`POST /api/equipment/:id/equip` with automatic same-slot unequip).
  - FUN-10-02-003: Unequip Item (`POST /api/equipment/:id/unequip`).
  - FUN-10-02-004: Validate Equipment (validates ownership, slot compatibility, alive hero state).
  - FUN-10-02-005: Calculate Equipment Stats (bonus HP, ATK, DEF, SPD added to hero in combat).
  - Floor drop recovery (`GET /api/equipment/floor-drops`, `POST /api/equipment/:id/pickup`).

#### Domain 11: Currency Management
- [x] DM-11 / MOD-11-01 Currency Management:
  - FUN-11-01-001: View Currency (`GET /api/economy/balances` returning Silver coins and Normal/Special summon tickets).
  - FUN-11-01-002: Add Currency (`currencyService.addCurrency` with transaction recording).
  - FUN-11-01-003: Deduct Currency (`currencyService.deductCurrency` with balance validation).
  - FUN-11-01-004: Validate Balance (`currencyService.validateBalance`).
  - FUN-11-01-005: Currency Transaction (`GET /api/economy/transactions` returning audit history).
  - FUN-11-01-006: Currency Limit (fixed weekly cap of 50 Normal scrolls).
  - FUN-11-01-007: Exchange Silver for Normal Summon Ticket (`POST /api/economy/exchange-scrolls`, 10,000 Silver per ticket, reset Thursday 00:00 UTC+7).

---

### Domain 14: Administration, Operations & Security
- [x] DM-14 / MOD-14-03 Configuration (UC-P0-19):
  - `system_configs` stores versioned JSON rule sets per `config_key`; version numbers are per key and serialised with a Postgres advisory lock so concurrent writers cannot collide.
  - FUN-14-03-001 Gacha rules, FUN-14-03-002 Pity parameters, FUN-14-03-003 Death rules, FUN-14-03-004 Dungeon rules, FUN-14-03-005 Seed algorithm parameters, FUN-14-03-006 Battle rules — keys `GACHA_RULES`, `GACHA_PITY`, `DEATH_RULES`, `DUNGEON_RULES`, `SEED_ALGORITHM`, `BATTLE_RULES`.
  - `POST /api/admin/configs` creates a version and (by default) activates it; `activate: false` stages it for later publishing.
  - `POST /api/admin/configs/:configId/activate` re-points the active version, which is also the rollback path.
  - `GET /api/admin/configs?key=` lists versions, `GET /api/admin/configs/active?key=` returns the runtime pointer. Runtime reads go through `systemConfigService.getActive()` with a short TTL cache invalidated on write, so an activation takes effect without a server restart.
  - Only `x-admin-api-key` callers may change configuration; `updatedBy` is constrained to 2–64 letters/digits/`_`/`-`.
- [x] DM-14 / MOD-14-05 Monitoring (FUN-14-05-006):
  - `GET /api/admin/monitoring` returns DB connectivity and latency, pool counters, process memory, uptime, and counts for accounts, Masters, active combat sessions, open security alerts, and 24h audit entries.
  - Existing `GET /health` remains the unauthenticated liveness probe.
- [x] DM-14 / MOD-14-06 Audit & Security (FUN-14-06-003/004/005/006):
  - `audit_logs` records actor, actor type, action, entity and a JSON before/after payload; writes are fire-and-forget and never break the caller's request.
  - Audited actions: config version created/activated, banner created/activated/deactivated, security alert raised/resolved.
  - `GET /api/admin/audit-logs` filters by `action`, `entityType`, `entityId`, `actorId` (limit ≤ 200).
  - FUN-14-06-004/005 anti-cheat: `RateGuard` counts authenticated requests per account in a sliding window (default 100 requests / 1 second) and, when crossed, blocks the account (`429 ERR_SECURITY_RATE_LIMIT`) and records a `security_alerts` row (`HIGH`, escalated to `CRITICAL` at 2× threshold) with a 60s alert cooldown.
  - `GET /api/admin/security-alerts` lists alerts; `POST /api/admin/security-alerts/:alertId/resolve` closes one and writes an audit entry.
  - Thresholds are configurable through `SECURITY_RATE_WINDOW_MS`, `SECURITY_RATE_LIMIT`, `SECURITY_BLOCK_MS`, `SECURITY_ALERT_COOLDOWN_MS`, and the admin actor through `ADMIN_OPERATOR_ID`.

### Remaining TBD (product decisions, not implementation gaps)
- Configuration approval workflow, activation timing, and who may roll back (UC-P0-19 alternate paths) are unspecified; the prototype allows any admin-key holder plus `activate: false` staging.
- Anti-cheat detection thresholds, incident workflow, retention, and alert routing are unspecified; current values are documented defaults.
- `GACHA_PITY` now drives the live five-star curve (summon resolution and banner rate preview); `BATTLE_RULES.tacticalBuffCooldownSeconds` drives the Tactical Buff cooldown. `GACHA_RULES`, `DEATH_RULES`, `DUNGEON_RULES` and `SEED_ALGORITHM` are versioned and publishable but not yet consumed by gameplay code.

### Delivered after the DM-14 pass
- Admin console in the web client (sidebar **Quản trị**): publish/rollback configuration versions, read the audit trail, monitoring counters and security alerts. The admin key is stored in `sessionStorage` only.
- Automated HTTP smoke test (`packages/server/tests/api.smoke.test.mjs`) boots the real API in-process and covers register → Master → exchange → summon (with idempotent replay) plus the admin plane; it skips when PostgreSQL is unreachable.
- Root scripts fixed: `npm run build` builds `shared` first; `npm test` uses `--if-present` so the client workspace no longer breaks the run.

---

Verification: `npm.cmd run build` (ordered shared → server → client) passed; `npm.cmd test` covers every workspace — 42/42 server tests (14 DM-14 unit tests plus a 4-step HTTP smoke suite) and 11/11 shared tests, nothing skipped while PostgreSQL is up. Migration `0022_stale_namora.sql` applied. Live checks: a published `GACHA_PITY` version moved the banner base rate 0.4% → 2% and `BATTLE_RULES` moved the Tactical Buff cooldown to 5s without a restart; a request burst produced `429` + `HIGH` alert + resolve.

Updated: 2026-11-04 06:45:00 UTC+7  
Signed: DeepSeek Harness, project assistant
