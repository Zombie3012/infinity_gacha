# P2 Implementation Checklist

## Project Context
- Scope Document: `Phase_Scope_Matrix_P2.csv` (40 functions, 8 modules, 3 domains)
- Specification Reference: `BRD_P2_Draft.md`, `Use_Case_Spec_P2_Draft.md`, `Data_Model_P2_Draft.md`, `Acceptance_Criteria_P2_Draft.md`
- Method: one domain at a time, end to end (schema → service → routes → client → tests → migration), matching P0/P1 delivery.

## Progress Summary
- Domain 11 / MOD-11-03 (Payment & IAP): Done — 7 functions.
- Domain 12 / MOD-12-04, MOD-12-05 (LiveOps Events, Leaderboards): Not started (10 functions).
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

---

## Open items carried forward
- Refund of item attachments is not implemented.
- No reconciliation job compares `payment_transactions` against store reports (no store integration yet).

---

Verification: `npm run verify` passes; 146/146 server tests (12 new payment rules) and 11/11 shared tests. Migration `0031_broken_whiplash.sql` applied and `iap_products.sample.sql` seeded. Live smoke: valid receipt credited 1.000 Gems, bad signature refused, replaying a used store receipt returned `ERR_IAP_DUPLICATE_RECEIPT`, a refund with balance left 500 → 0 debt, and a refund after spending left 200 Gems clawed plus 800 Gem debt.

Updated: 2026-11-04 10:40:00 UTC+7
Signed: DeepSeek Harness, project assistant
