# P2 Implementation Checklist

## Project Context
- Scope Document: `Phase_Scope_Matrix_P2.csv` (40 functions, 8 modules, 3 domains)
- Specification Reference: `BRD_P2_Draft.md`, `Use_Case_Spec_P2_Draft.md`, `Data_Model_P2_Draft.md`, `Acceptance_Criteria_P2_Draft.md`
- Method: one domain at a time, end to end (schema → service → routes → client → tests → migration), matching P0/P1 delivery.

## Progress Summary
- Domain 11 / MOD-11-03 (Payment & IAP): Done — 7 functions.
- Domain 12 / MOD-12-04, MOD-12-05 (LiveOps Events, Leaderboards): Done — 10 functions.
- Domain 14 / MOD-14-01, -02, -04, -05, -06 (Administration, content config, analytics, support): Not started (23 functions).

---

## Domain 11: Payment & IAP (MOD-11-03)

- [x] FUN-11-03-001 View Purchase Package — `GET /api/iap/products` lists active packages with a formatted store price.
- [x] FUN-11-03-002 Initiate Payment — `POST /api/iap/checkout` opens a `PENDING` `payment_transactions` row for APPLE/GOOGLE.
- [x] FUN-11-03-003 Process Payment — the store hand-off is modelled by the receipt payload submitted to `POST /api/iap/receipt`.
- [x] FUN-11-03-004 Validate Payment — receipt HMAC is verified (`ERR_IAP_INVALID_RECEIPT`), replayed store transaction ids are refused (`ERR_IAP_DUPLICATE_RECEIPT`, backed by `UNIQUE(store, store_transaction_id)`).
- [x] FUN-11-03-005 Grant Purchase Reward — gems clear `gem_debt` first (scenario 1.6), then Silver and items are deposited in one transaction.
- [x] FUN-11-03-006 Payment History — `GET /api/iap/transactions` (player) and `GET /api/admin/iap/transactions` (operator) with status and price.
- [x] FUN-11-03-007 Refund Processing — `POST /api/admin/iap/refund` claws back available Gems and books the shortfall as `masters.gem_debt` (scenarios 2.1/2.2); the account is never locked.

### Prototype boundary
- No Apple/Google SDK is present: a receipt is simulated with `HMAC-SHA256(PAYMENT_GATEWAY_SECRET, "store:storeTransactionId")`, and `PAYMENT_GATEWAY_SECRET` must be configured (`PAYMENT_GATEWAY_NOT_CONFIGURED` otherwise).
- Refunds claw back Gems only; attached items/Silver from the package are not revoked.
- The client page requires the operator/tester to paste the simulated receipt token, mirroring the account-linking screen.

## Domain 12: LiveOps Events and Dual PVE Leaderboards

### MOD-12-04 Event Management (7 functions)
- [x] FUN-12-04-001 Configure Event — `POST /api/admin/events` registers a STANDARD/MAJOR/MINOR event.
- [x] FUN-12-04-002 Schedule Event — `eventWindow` derives `end_at` (14/21/7 days) and `claim_deadline` (+48h); scenario 3.1 is unit-tested.
- [x] FUN-12-04-003 Activate Event — `POST /api/admin/events/:id/activate` refuses overlapping STANDARD events (`ERR_LIVEOPS_STANDARD_EVENT_OVERLAP`) and MAJOR events inside the 7-day cooldown (`ERR_MAJOR_EVENT_COOLDOWN_VIOLATION`).
- [x] FUN-12-04-004 View Event — `GET /api/events` returns running events with the caller's mission progress and phase (ACTIVE/GRACE).
- [x] FUN-12-04-005 Event Mission — `POST /api/admin/events/:id/missions` defines missions; progress is fed by the same gameplay hooks as quests (victory, floor clear, craft, spend, harvest).
- [x] FUN-12-04-006 Event Reward — `POST /api/events/missions/:id/claim` grants the mission reward until the 48h claim deadline (`ERR_LIVEOPS_CLAIM_EXPIRED` after).
- [x] FUN-12-04-007 Close Event — `POST /api/admin/events/:id/close` blocks further progress and stamps the closure.

### MOD-12-05 Ranking & Leaderboard (3 functions)
- [x] FUN-12-05-001 Calculate Ranking — DUNGEON_PROGRESS ranks by highest cleared floor then fewest combat rounds (scenario 4.1); COMBAT_POWER sums the five strongest Heroes (scenario 4.2).
- [x] FUN-12-05-002 View Leaderboard — `GET /api/leaderboards?board=` returns the top 50 with the caller's own rank, and `GET /api/leaderboards/me` exposes personal combat power.
- [x] FUN-12-05-003 Distribute Ranking Reward — `POST /api/admin/leaderboards/:board/close` snapshots the season, books rewards per rank tier and posts them to each Master's mailbox (scenario 4.3).

### Integration and seed data
- Combat victories now write `floor_records` (best rounds per floor) and push WIN_BATTLE/CLEAR_FLOOR into event missions.
- `liveops_events.sample.sql` seeds one running STANDARD event with three missions.

---

## Open items carried forward
- Refund of item attachments is not implemented.
- No reconciliation job compares `payment_transactions` against store reports (no store integration yet).

---

Verification: `npm run verify` passes; 158/158 server tests (12 payment + 12 liveops rule tests) and 11/11 shared tests. Migrations `0031_broken_whiplash.sql` and `0032_pretty_morg.sql` applied, with `iap_products.sample.sql` and `liveops_events.sample.sql` seeded. Live smoke: valid receipt credited 1.000 Gems, bad signature refused, replaying a used store receipt returned `ERR_IAP_DUPLICATE_RECEIPT`, a refund with balance left 500 → 0 debt, and a refund after spending left 200 Gems clawed plus 800 Gem debt.

Updated: 2026-11-04 11:15:00 UTC+7
Signed: DeepSeek Harness, project assistant
