# Unity Backlog — items deliberately left for the game client team

These items are **not** required for the backend prototype. They are marked
here so the Unity team owns them when the real client starts. The API/DB side
already exposes the data or is ready to be extended.

## 1. Hero Awakening presentation
- Imprint Evolution (rank S/A/B, extra Trait/Ability) needs a content design and
  new tables (`imprint_definitions`, `hero_imprints`). Backend currently skips it.
- Trait tiers: awakening currently assigns a random special trait; Unity should
  show the new trait card, before/after comparison, and animation.
- Skill Awakening selection: backend upgrades the first unlocked skill below max
  level. Unity should let the player choose which skill to awaken.
- Awakening cinematic, VFX, SFX, voice-over and stat-delta reveal.

## 2. Rank Promotion (separate from Awakening)
- Star promotion (2★→3★, 3★→4★…) with level cap, skill cap, imprint unlock and
  portrait refresh must be designed as a separate flow. Backend only handles the
  current `promotionRank` level cap.

## 3. Combat v2 client
- Stat sheet: STR/INT/STA/AGI, derived stats, class, affinity table, training
  budget, awakening rank.
- Combat HUD: HP/MP bars, skill cooldowns, crit/block numbers, turn order by AGI.
- Session flow: start → advance (currently one resolution step), report replay,
  damage numbers, death/drop presentation.
- Comparison UI for class change (retroactive growth preview and cost).

## 4. Content and art
- 6★/7★ content (budgets already defined, locked in backend).
- Mage element affinity visuals and elemental spell VFX.
- Class portraits, awakening forms, subclasses icons.

## 5. Production services
- Google Play Billing / Apple StoreKit receipt validation (backend currently
  simulates receipts with HMAC).
- Push notifications, deep links, account linking SDKs.

## 6. Balance
- TTK = 10 hits tuning with real parties and gear.
- Class-change pricing and awakening material costs.
