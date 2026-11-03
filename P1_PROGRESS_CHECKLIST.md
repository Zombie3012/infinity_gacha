# P1 Implementation Checklist

## Project Context
- Scope Document: `Phase_Scope_Matrix_P1.csv` (93 functions, 19 modules, 8 domains)
- Specification Reference: `BRD_P1_Draft.md`, `Use_Case_Spec_P1_Draft.md`, `Data_Model_P1_Draft.md`, `Acceptance_Criteria_P1_Draft.md`
- Method: one domain at a time, end to end (schema → service → routes → client → tests → migration), matching the P0 delivery style.

## Progress Summary
- Domain 08 (Base, Construction & Production): Done — 4 modules, 18 functions.
- Domain 09 (Hero Survival: Hunger, Fatigue, Food): Not started.
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

---

## Open items carried forward
- DM-08 has no automated HTTP coverage yet; the smoke flow (construct → settle → collect → upgrade → assign → expand) was verified live and the arithmetic is covered by unit tests.
- Base construction is not gated behind a `feature_unlock_configs` row; every Master with a world can build.
- Balance values above remain sample data.

---

Verification: `npm run verify` (encoding guard → build → tests) passes; 55/55 server tests (13 new DM-08 rule tests) and 11/11 shared tests. Migration `0023_slimy_dagger.sql` applied. Live smoke on the seeded demo account confirmed: 100 STONE/h mine produced 200 Stone after 2 backdated hours, upgrade blocked without WOOD then accepted, worker raised the rate to 168/h (L2 × 1.05), zone 2 expanded for 2,000 Silver, and zone 3 correctly refused until World Level 2.

Updated: 2026-11-04 06:55:00 UTC+7
Signed: DeepSeek Harness, project assistant
