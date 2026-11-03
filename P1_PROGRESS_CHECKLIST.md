# P1 Implementation Checklist

## Project Context
- Scope Document: `Phase_Scope_Matrix_P1.csv` (93 functions, 19 modules, 8 domains)
- Specification Reference: `BRD_P1_Draft.md`, `Use_Case_Spec_P1_Draft.md`, `Data_Model_P1_Draft.md`, `Acceptance_Criteria_P1_Draft.md`
- Method: one domain at a time, end to end (schema → service → routes → client → tests → migration), matching the P0 delivery style.

## Progress Summary
- Domain 08 (Base, Construction & Production): Done — 4 modules, 18 functions.
- Domain 09 (Hero Survival: Hunger, Fatigue, Food): Done — 3 modules, 16 functions.
- Domain 04 (Injury, Medical Facility, Treatment & Resurrection): Done — 3 modules, 17 functions.
- Domain 03 (Hero Personality, Loyalty & Relationship): Done — 2 modules, 10 functions.
- Domain 11 (Shop & Mailbox): Done — 2 modules, 12 functions.
- Domain 10 (Crafting & Enhancement): Done — 1 module, 4 functions.
- Domain 12 / 01 (Quests & Achievements, Account Linking): Not started.

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

## Domain 04: Injury, Medical Facility and Resurrection

### MOD-04-02 Injury & Temporary Stat Reduction (5 functions)
- [x] FUN-04-02-001 Classify Injury — HP below 15% after a battle ⇒ SEVERE, below 30% ⇒ MODERATE, below 50% ⇒ MINOR; recorded in `hero_injuries` when the battle report is generated.
- [x] FUN-04-02-002 Apply Temporary Reduction — SEVERE −25%, MODERATE −15%, MINOR −10% ATK/DEF (and speed stays untouched); the multiplier is applied together with the starvation penalty when combat starts.
- [x] FUN-04-02-003 Calculate Recovery Duration — natural timers 2h / 1h / 30m; a Medical Facility shortens treatment by 20% per level above 1 but never below 20% of the base.
- [x] FUN-04-02-004 View Injury Status — `GET /api/medical` lists severity, penalty, natural heal deadline and the resulting combat multiplier.
- [x] FUN-04-02-005 Restore Hero Stats — injuries resolve lazily when the timer expires (or on treatment/emergency) and the Hero returns to HEALTHY once no injury remains.

### MOD-04-03 Medical Facility (4 functions)
- [x] FUN-04-03-001 Construct Medical Facility — uses the DM-08 building flow with the `MEDICAL` type (world level 2, 3,000 Silver).
- [x] FUN-04-03-002 Upgrade Medical Facility — DM-08 upgrade path applies (level, durability, timer).
- [x] FUN-04-03-003 Manage Treatment Capacity — bed capacity is `level + 1` (level 1 ⇒ 2 beds, matching scenario 5.1); admission is refused with `Viện Y Tế đã hết giường` when full.
- [x] FUN-04-03-004 View Medical Facility — overview exposes level, beds used/free and active treatments.

### MOD-04-04 Treatment & Resurrection (8 functions)
- [x] FUN-04-04-001 Start Treatment — `POST /api/medical/treatments` admits an injured Hero into a free bed and starts the accelerated timer.
- [x] FUN-04-04-002 Treatment Queue — active treatments and bed occupancy are part of the overview payload.
- [x] FUN-04-04-003 Emergency Treatment — `POST /api/medical/emergency` consumes 1 MEDICINE and heals instantly (scenario 5.2).
- [x] FUN-04-04-004 Discharge — completed treatments mark the injury healed and restore the Hero to HEALTHY.
- [x] FUN-04-04-005 Resurrection Request — `POST /api/medical/resurrect` opens the Divine Grace flow for DISABLED Heroes.
- [x] FUN-04-04-006 Resurrection Validation — Normal Heroes are rejected with `ERR_RESURRECTION_NORMAL_PERMADEATH` (scenario 6.3); cost is `n` DIVINE_TEAR + 10,000 × n Silver with a 30-day cycle reset (scenarios 6.1/6.2).
- [x] FUN-04-04-007 Process Resurrection — revives to 50% HP, applies +25 fatigue, increments the cycle counter and charges materials/Silver atomically.
- [x] FUN-04-04-008 Recovery History — every treatment and resurrection is stored in `hero_treatments` with cost, and resurrect actions also write an audit entry.

### Prototype tuning recorded here
- Injury thresholds follow the acceptance scenarios; healing is lazy (no background worker).
- MEDICINE and DIVINE_TEAR are plain `master_items` entries; the prototype seeds neither — operators grant them.
- Injuries are recorded from the `advance` route only; the dungeon retreat path does not create injuries yet.

## Domain 03: Personality, Loyalty and Relationships

### MOD-03-04 Personality & Loyalty (6 functions)
- [x] FUN-03-04-001 Assign Personality — every Hero gets four deterministic traits (core / social / behavioural / special) plus a favourite food, derived from the instance id; loyalty starts at 50 (scenario 2.1).
- [x] FUN-03-04-002 View Personality — `GET /api/personality` lists traits, favourite food, loyalty, state, combat multiplier and disobedience chance.
- [x] FUN-03-04-003 Personality Behavior — traits are exposed to combat (loyalty multiplier + resonance) and recorded as the behavioural profile used by future AI targeting.
- [x] FUN-03-04-004 Calculate Loyalty — victories +1, favourite meal +5, manual adjustment endpoint (−50..50) for testing and operator correction.
- [x] FUN-03-04-005 View Loyalty — loyalty score, state and average/devoted/danger counters in the summary payload.
- [x] FUN-03-04-006 Loyalty State Change — DEVOTED ≥ 80 (+5% stats), NORMAL 20–79, DANGER < 20 (50–78.5% stats and a 30% dispatch refusal with `ERR_HERO_DISOBEDIENCE`). Heroes are never removed from the roster (scenario 2.2).

### MOD-03-05 Relationships (4 functions)
- [x] FUN-03-05-001 Initialize Relationship — one row per Hero pair is created lazily for every Master (`hero_relationships`, unique pair).
- [x] FUN-03-05-002 Update Relationship — shared victories add +2 affinity per pair (five wins ⇒ +10, scenario 3.1); the endpoint supports manual affinity review.
- [x] FUN-03-05-003 View Relationship — overview returns names, affinity, tier (RIVAL / STRANGER / ACQUAINTANCE / COMRADE / TRUSTED_ALLY) and resonance bonus.
- [x] FUN-03-05-004 Relationship Event — COMRADE and above grant a +5% ATK resonance applied in combat when both Heroes deploy together.

### Prototype tuning recorded here
- Trait pools and the favourite-food list are sample data; assignment is hashed from the Hero id so replays and tests stay stable.
- Disobedience uses a real random roll (`Math.random`), so the outcome is not deterministic by design.
- Relationship affinity is currently driven by victories only; shared dormitory/production events are not wired yet.

## Domain 11: Base Shop and Mailbox

### MOD-11-02 Shop Management (6 functions)
- [x] FUN-11-02-001 View Shop — `GET /api/shop` returns today's active catalogue with per-item limits and the rotated-out list.
- [x] FUN-11-02-002 View Product Detail — `GET /api/shop/items/:code` exposes price, availability and remaining daily units.
- [x] FUN-11-02-003 Purchase Item — `POST /api/shop/purchase` deducts Silver and deposits the item atomically; errors are `ERR_SHOP_INSUFFICIENT_FUNDS` / `ERR_SHOP_ITEM_ROTATED_OUT`.
- [x] FUN-11-02-004 Shop Rotation — items carry `rotation_days` (0–6 in UTC+7); items outside their weekdays are hidden and unbuyable.
- [x] FUN-11-02-005 Configure Shop — `GET /api/admin/shop` and `POST /api/admin/shop/items` (admin key) upsert the catalogue, prices and limits.
- [x] FUN-11-02-006 Purchase Limit — per-Master daily counters keyed by UTC+7 date; scenario 13.1 is honoured (buy the remainder, return `ERR_SHOP_DAILY_LIMIT_EXCEEDED` for the excess).

### MOD-11-04 Rewards & Mailbox (6 functions)
- [x] FUN-11-04-001 Generate Reward — operator payloads accept Silver and item attachments (`normalizeAttachments`).
- [x] FUN-11-04-002 Distribute Reward — claiming credits `masters.silver_coins` and `master_items` in one transaction.
- [x] FUN-11-04-003 Send Mail — `POST /api/admin/mailbox/send` addresses a Master directly or by username, with audit logging.
- [x] FUN-11-04-004 View Mailbox — `GET /api/mailbox` splits unclaimed/claimed mail and reports how many expired messages were purged.
- [x] FUN-11-04-005 Claim Mail Attachment — `POST /api/mailbox/:id/claim` is idempotent-safe (`Thư đã được nhận`) and refuses expired mail (`ERR_MAIL_EXPIRED`).
- [x] FUN-11-04-006 Mail Expiration — expiry is 30 days by default (configurable per send) and expired mail is purged lazily on read.

### Seed data added
- `shop_items.sample.sql`: nine entries, including MEDICINE, DIVINE_TEAR, FOOD and raw materials that the previous domains were missing, plus MOON_CAKE rotating on weekends only.

## Domain 10: Crafting, Enhancement and Fusion

- [x] FUN-10-03-001 Craft Item — `POST /api/crafting/craft` consumes recipe materials + Silver and rolls a new `equipment_instances` row with deterministic substats inside rarity brackets (scenario 12.1).
- [x] FUN-10-03-002 Upgrade Equipment — `POST /api/crafting/equipment/:id/enhance` costs `level + 1` ENHANCEMENT_STONE and 500 × (level + 1) Silver for +10% base stats per level, capped at +15.
- [x] FUN-10-03-003 Item Fusion — `POST /api/crafting/fuse` consumes three identical inventory instances (same template and star) into one at the next star with ×1.3 base stats; unenhanced copies are consumed first (scenario 12.2).
- [x] FUN-10-03-004 Material Requirement — `validateCraft` reports missing materials, missing Silver and forge-level shortfall separately, surfaced on every recipe in `GET /api/crafting`.

### Integration and seed data
- Equipment bonuses in combat now scale by the instance multiplier and add rolled substats (`Math.round(base × multiplier) + substat`).
- `crafting_recipes.sample.sql` seeds three recipes (Iron Sword, Leather Chest, Swift Charm) gated by Forge level.
- Shop catalogue gained ENHANCEMENT_STONE so the enhancement loop is reachable without SQL.

### Bug found and fixed during verification
- Enhancement used to overwrite the fusion multiplier (a 2-star ×1.3 item dropped to ×1.1 on the first enhance). Multipliers now stack: `effectiveMultiplier(star, level) = 1.3^(star-1) × (1 + 0.1 × level)`, covered by a regression test.

---

## Open items carried forward
- DM-08/DM-09 rely on unit tests for the arithmetic plus live smoke flows; the HTTP layer still has no automated domain coverage.
- Food consumption for Heroes idling in the base is quoted but not yet charged on a schedule (no scheduler in the prototype).
- Base construction is not gated behind a `feature_unlock_configs` row; every Master with a world can build.
- Balance values above remain sample data.

---

Verification: `npm run verify` passes; 116/116 server tests (13 DM-08, 15 DM-09, 11 DM-04, 10 DM-03, 11 DM-11, 13 DM-10 rule tests) and 11/11 shared tests. Migrations `0023` … `0028_wild_maddog.sql` applied. Live smoke confirmed: cooking 5 meals from 10 raw food, feeding a Hero (−20 hunger), 4 hours of rest taking fatigue 80 → 20, dungeon rations quoting 40 for 4 Heroes, combat refused with `ERR_INSUFFICIENT_RATIONS` then allowed after stocking 100 FOOD, a starving Hero entering battle at the 60% multiplier, and 30 rations deducted on dispatch.

Updated: 2026-11-04 09:00:00 UTC+7
Signed: DeepSeek Harness, project assistant
