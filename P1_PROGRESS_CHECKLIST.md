# P1 Implementation Checklist

## Project Context
- Scope Document: `Phase_Scope_Matrix_P1.csv` (93 functions, 19 modules, 8 domains)
- Specification Reference: `BRD_P1_Draft.md`, `Use_Case_Spec_P1_Draft.md`, `Data_Model_P1_Draft.md`, `Acceptance_Criteria_P1_Draft.md`
- Method: one domain at a time, end to end (schema → service → routes → client → tests → migration), matching the P0 delivery style.

## Progress Summary
- Domain 08 (Base, Construction & Production): Done — 4 modules, 18 functions.
- Domain 09 (Hero Survival: Hunger, Fatigue, Food): Done — 3 modules, 16 functions.
- Domain 04 (Injury, Medical Facility, Treatment & Resurrection): Not started.
- Domain 03 (Hero Personality, Loyalty & Relationship): Not started.
- Domain 10 / 11 / 12 / 01 (Crafting, Shop & Mailbox, Quests & Achievements, Account Linking): Not started.

---

## Domain 08: Base, Construction & Production

### MOD-08-01 Private World Management (4 functions)
- [x] FUN-08-01-002 View World Overview — `GET /api/base/overview` returns world level, zones, plot count, all buildings with live production, and the building catalogue with unlock state.
- [x] FUN-08-01-003 Manage World Progress — world level is derived from PvE progress (`1 + floor((currentFloor - 1) / 3)`, capped at 10) and gates zone expansion and building unlocks.
- [x] FUN-08-01-004 Expand Private World — `POST /api/base/expand`: 2,000 Silver for zone 2, 5,000 for later zones, 3 plots per zone, maximum 6 zones; requires world level `zone - 1`.
- [x] FUN-08-01-005 World Feature Unlock — building types advertise `requiredWorldLevel`; the catalogue marks each type `unlocked` and construction rejects locked types.

### MOD-08-02 Building Management (5 functions)
- [x] FUN-08-02-001 Construct Building — `POST /api/base/buildings` (`buildingType`, `plotIndex`); charges Silver, reserves the plot (unique `master_id + plot_index`), starts a `CONSTRUCTING` timer.
- [x] FUN-08-02-002 Upgrade Building — `POST /api/base/buildings/:id/upgrade`; costs 75% of build price per target level plus WOOD/STONE, sets `UPGRADING` with a countdown, level and capacity apply on completion.
- [x] FUN-08-02-003 Unlock Building — blueprint unlock is driven by world level (`required_world_level`), see FUN-08-01-005.
- [x] FUN-08-02-004 Demolish Building — `POST /api/base/buildings/:id/demolish`; refunds 50% of invested Silver, cascades production node and worker assignments.
- [x] FUN-08-02-005 View Building Status — overview returns status, level/max level, durability, workers, rate, stored/capacity and the `atCapacity` pause flag.

### MOD-08-03 Resource Production (5 functions)
- [x] FUN-08-03-001 Configure Production — `POST /api/base/buildings/:id/production` creates/keeps the node and pins the resource to the building profile.
- [x] FUN-08-03-002 Generate Resources — offline-safe accrual: `stored + rate × hours`, capped by capacity, computed from `last_harvest_at` on every read.
- [x] FUN-08-03-003 Collect Resources — `POST /api/base/buildings/:id/collect`: floors the stored amount into `master_items`, resets the anchor, returns the collected quantity.
- [x] FUN-08-03-004 Upgrade Production — level multiplier `1 + 0.6 × (level - 1)` (Farm 50/h at L1 → 80/h at L2 as specified) and capacity × level.
- [x] FUN-08-03-005 Manage Production Capacity — production pauses at `max_capacity` without losing stored resources.

### MOD-08-04 Hero Assignment to Buildings (4 functions)
- [x] FUN-08-04-001 Assign Hero — `POST /api/base/buildings/:id/workers`; validates ownership, alive state, capacity and the one-building-per-Hero rule.
- [x] FUN-08-04-002 Remove Hero — `DELETE /api/base/buildings/:id/workers/:heroId`.
- [x] FUN-08-04-003 Calculate Work Efficiency — sample rule `1 + 5% × Hero level`, capped at +25%, additive across workers; the overview exposes the resulting rate.
- [x] FUN-08-04-004 Monitor Hero Assignment — overview lists assigned Heroes with their boost so the client can render and revoke assignments.

### Prototype tuning recorded here (not approved balance)
- Building catalogue seeded by `building_types.sample.sql`: Farm 1,200 Silver / 50 FOOD_RAW per hour / capacity 500; Lumber Mill 80 WOOD; Stone Quarry 100 STONE; Smithy 30 IRON (world level 2); Kitchen 20 FOOD (level 2); Dormitory and Medical Facility are non-producing.
- Construction 20s, upgrades 15s × target level. Timers are settled lazily on the next request.
- Demolition returns Silver only; spent WOOD/STONE are not refunded.
- Work shifts do **not** yet raise Hunger/Fatigue: that belongs to DM-09 (next domain) and is a deliberate dependency.

## Domain 09: Hero Survival (Hunger, Fatigue, Food)

### MOD-09-01 Hunger Management (5 functions)
- [x] FUN-09-01-001 Track Hero Hunger — `hero_survival_states` keeps a 0–100 score per Hero with the tiers FULL / SATISFIED / HUNGRY / STARVING / CRITICAL.
- [x] FUN-09-01-002 Calculate Hunger Consumption — passive +1/hour (+2/hour when the warehouse is empty), +8 per battle, +5 per labour shift; state settles lazily from `last_tick_at`.
- [x] FUN-09-01-003 Distribute Food — `POST /api/survival/heroes/:id/feed` consumes FOOD (1 food = −20 hunger, max 10 per call) and rejects when the store is empty.
- [x] FUN-09-01-004 Process Starvation — at 60+ hunger the Hero fights at 60% ATK/DEF (applied to combat stats); at 100 the Hero cannot be dispatched (`ERR_HERO_STARVING_MUST_FEED`).
- [x] FUN-09-01-005 View Hunger Status — `GET /api/survival` returns score, tier, attack multiplier and per-Master counters.

### MOD-09-02 Fatigue Management (6 functions)
- [x] FUN-09-02-001 Track Hero Fatigue — 0–100 score with tiers RESTED / NORMAL / TIRED / EXHAUSTED / CRITICAL / OVEREXHAUSTED.
- [x] FUN-09-02-002 Calculate Fatigue Increase — +2/hour awake, +12 per battle, +8 per labour shift.
- [x] FUN-09-02-003 Start Hero Rest — `POST /api/survival/heroes/:id/rest`; refuses Heroes still assigned to a building.
- [x] FUN-09-02-004 Process Fatigue Recovery — resting drains 15 points/hour (80 → 20 after 4 hours, matching scenario 10.2) and stops at zero.
- [x] FUN-09-02-005 View Fatigue Status — included in the survival roster payload and in the new client page.
- [x] FUN-09-02-006 Prevent Overexertion — at 100 fatigue the Hero is Overexhausted: `POST /api/combat/session/start` returns `ERR_HERO_OVEREXHAUSTED_MUST_REST`, and a labour shift that reaches 100 auto-removes the Hero from its building.

### MOD-09-03 Food Storage & Consumption (5 functions)
- [x] FUN-09-03-001 Manage Food Storage — FOOD lives in `master_items`; capacity is `max(100, Kitchen level × 200)`.
- [x] FUN-09-03-002 Produce Food — `POST /api/survival/kitchen/cook` converts 2 FOOD_RAW into 1 FOOD, capped by storage capacity.
- [x] FUN-09-03-003 Consume Base Resources — `GET /api/survival/upkeep?hours=` quotes two meals per healthy Hero per day; an empty store doubles hunger gain.
- [x] FUN-09-03-004 Consume Dungeon Resources — 10 rations per party Hero are validated and deducted before a dungeon run starts (`ERR_INSUFFICIENT_RATIONS` when short).
- [x] FUN-09-03-005 Consume War Resources — `POST /api/survival/rations/quote` prices war dispatch at 15 rations per Hero (army dispatch itself is P3 scope).

### Integration delivered with this domain
- Harvesting a production building now charges one labour shift to every assigned Hero (+5 hunger, +8 fatigue) and ejects anyone reaching Overexhausted.
- Combat applies the starvation multiplier to ATK/DEF and charges travel rations before the session is created.
- New Masters receive 100 FOOD as a starter kit so the first dungeon run is possible.

---

## Open items carried forward
- DM-08/DM-09 rely on unit tests for the arithmetic plus live smoke flows; the HTTP layer still has no automated domain coverage.
- Food consumption for Heroes idling in the base is quoted but not yet charged on a schedule (no scheduler in the prototype).
- Base construction is not gated behind a `feature_unlock_configs` row; every Master with a world can build.
- Balance values above remain sample data.

---

Verification: `npm run verify` passes; 70/70 server tests (13 DM-08 + 15 DM-09 rule tests) and 11/11 shared tests. Migrations `0023_slimy_dagger.sql` and `0024_normal_magneto.sql` applied. Live smoke confirmed: cooking 5 meals from 10 raw food, feeding a Hero (−20 hunger), 4 hours of rest taking fatigue 80 → 20, dungeon rations quoting 40 for 4 Heroes, combat refused with `ERR_INSUFFICIENT_RATIONS` then allowed after stocking 100 FOOD, a starving Hero entering battle at the 60% multiplier, and 30 rations deducted on dispatch.

Updated: 2026-11-04 07:20:00 UTC+7
Signed: DeepSeek Harness, project assistant
