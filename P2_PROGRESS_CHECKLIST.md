# P2 Implementation Checklist

## Project Context
- Scope Document: `Phase_Scope_Matrix_P2.csv` (40 functions, 8 modules, 3 domains)
- Specification Reference: `BRD_P2_Draft.md`, `Use_Case_Spec_P2_Draft.md`, `Data_Model_P2_Draft.md`, `Acceptance_Criteria_P2_Draft.md`
- Method: one domain at a time, end to end (schema → service → routes → client → tests → migration), matching P0/P1 delivery.

## Progress Summary
- Domain 11 / MOD-11-03 (Payment & IAP): Done — 7 functions.
- Domain 12 / MOD-12-04, MOD-12-05 (LiveOps Events, Leaderboards): Done — 10 functions.
- Domain 14 / MOD-14-01, -02, -04 (Player admin + content/economy config): Done — 16 functions.
- Domain 14 / MOD-14-05, -06 (Analytics, Customer Support): Not started (7 functions).

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

## Domain 14: Player Administration, Content & Economy Configuration

### MOD-14-01 Player Administration (5 functions)
- [x] FUN-14-01-001 Search Player — `GET /api/admin/players?query=` matches username or Master name.
- [x] FUN-14-01-002 View Player Data — `GET /api/admin/players/:accountId` returns account, profile, Master currencies, world, Hero count, recent payments and sessions.
- [x] FUN-14-01-003 Restrict Account — `POST .../restrict` sets SUSPENDED/BANNED, revokes live sessions and audits the action; login then fails with `ERR_AUTH_ACCOUNT_RESTRICTED`.
- [x] FUN-14-01-004 Restore Account — `POST .../restore` returns the account to ACTIVE.
- [x] FUN-14-01-005 Player Compensation — `POST .../compensation` mails Silver/items and credits Gems directly, with caps (`ERR_COMPENSATION_*_TOO_HIGH`).

### MOD-14-02 Hero & World Master Configuration (6 functions)
- [x] FUN-14-02-001 Hero Template Configuration — `GET/POST /api/admin/content/heroes` upserts templates.
- [x] FUN-14-02-002 Hero Stats Configuration — `POST /api/admin/content/heroes/:code/stats` changes base stats only.
- [x] FUN-14-02-003 Hero Skill Configuration — `GET/POST /api/admin/content/hero-skills`.
- [x] FUN-14-02-004 Monster Configuration — `GET/POST /api/admin/content/enemies`.
- [x] FUN-14-02-005 Boss Configuration — bosses are enemies with `is_boss = true`, filterable via `?boss=true`.
- [x] FUN-14-02-006 Item Configuration — new `item_templates` catalogue with `GET/POST /api/admin/content/items` (13 seeded items).

### MOD-14-04 Economy & Event Operational Configuration (5 functions)
- [x] FUN-14-04-001 Currency Configuration — `CURRENCY_RULES` added to the versioned configuration keys; published through the existing `/api/admin/configs` flow.
- [x] FUN-14-04-002 Shop Configuration — existing `POST /api/admin/shop/items` (DM-11 P1).
- [x] FUN-14-04-003 Reward Configuration — `REWARD_RULES` added to the configuration keys.
- [x] FUN-14-04-004 Event Configuration — existing `POST /api/admin/events` (DM-12 P2).
- [x] FUN-14-04-005 Banner Configuration — existing `POST /api/admin/banners` (P0 DM-14).

### Operator UI
- Admin console gained **Người chơi** (search, restrict/ban/restore, compensation) and **Nội dung** (item catalogue create, Hero template table) tabs.

---

## Open items carried forward
- Refund of item attachments is not implemented.
- No reconciliation job compares `payment_transactions` against store reports (no store integration yet).

---

Verification: `npm run verify` passes; 165/165 server tests (12 payment, 12 liveops, 7 admin rule tests) and 11/11 shared tests. Migrations `0031` … `0033_messy_giant_girl.sql` applied, with `iap_products`, `liveops_events` and `item_templates` seeds. Live smoke: valid receipt credited 1.000 Gems, bad signature refused, replaying a used store receipt returned `ERR_IAP_DUPLICATE_RECEIPT`, a refund with balance left 500 → 0 debt, and a refund after spending left 200 Gems clawed plus 800 Gem debt.

Updated: 2026-11-04 11:50:00 UTC+7
Signed: DeepSeek Harness, project assistant
