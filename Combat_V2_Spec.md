# Combat v2 — Specification

| Field | Value |
|---|---|
| Version | 1.0 |
| Status | Implemented prototype; PvP/expedition still on legacy stats (decision b) |
| Code | `packages/shared/src/combat`, `packages/server/src/modules/combat`, `packages/server/src/modules/hero` |
| Migrations | `0039_same_spyke.sql`, `0040_absurd_joshua_kane.sql` |

## 1. Base stats
Four persisted base stats: **STR, INT, STA, AGI**. Every other stat is derived at runtime.

```
ATK   = ATK_base   + 2.5*STR + 0.5*AGI
MATK  = MATK_base  + 3.0*INT
MaxHP = HP_base    + 20*STA
MaxMP = MP_base    + 10*INT
DEF   = DEF_base   + 0.5*STA
MDEF  = MDEF_base  + 0.5*INT
HPRegen = 0.1*STA     MPRegen = 0.1*INT
CritRate = classBase + 0.05*AGI + bonus   (cap 100%)
CritDMG = 150% + bonus                    (cap 300%)
Evasion = 0.05*AGI + bonus                (cap 75%)
Accuracy, BlockRate, BlockEffect, CritRES, CritDMGRes, DR, Tenacity, ArmorPen, MagicPen, Lifesteal are item/skill/buff sources with the caps below.
```

## 2. Stat caps
Crit 100% · CritDMG 300% · Evasion 75% · Block 75% · BlockEffect 85% · DR 70% · Tenacity 70% · Lifesteal 50% · Armor/Magic Pen 80% · Hit chance 5–98%.

## 3. Growth
- Level-1 budget by star: 100 / 130 / 170 / 220 / 280 / **350 (6★ locked)** / **430 (7★ locked)**.
- `Budget(L) = Budget(1) + 8*(L-1) + Compensation(L)`, `Compensation = (target − Budget(1) − 392) * ((L−1)/49)²`.
- 1–5★ all reach **672** points at level 50; 6★ = 742, 7★ = 822 (future).
- 8 points per level: **5 automatic** (class growth, retroactive on class change) + **3 training** (player, 1:1, 60% per-stat cap).
- Random roll at summon: 75% template archetype + 25% wildcard, ±15% noise, min 8/stat, max 45%/stat.

## 4. Classes
| Class | Base crit | STR | INT | STA | AGI | Passive |
|---|---|---|---|---|---|---|
| Warrior | 5% | 1.20 | 0.70 | 1.15 | 0.90 | physical defence |
| Thief | **50%** | 0.95 | 0.75 | 0.85 | 1.30 | crit + evasion |
| Spearman | 5% | 1.20 | 0.65 | 0.95 | 1.10 | armor pen |
| Archer | 5% | 0.95 | 0.75 | 0.85 | 1.30 | accuracy + ranged |
| Mage | 5% | 0.60 | 1.35 | 0.85 | 0.95 | magic + affinity |

- 1–2★ always **Unclassified**; 3★ 40%, 4★ 70%, 5★ 100% classed.
- Class weights among classed: Warrior 35 / Archer 25 / Thief 20 / Spearman 15 / Mage 5; Mage appears on **all** banners.
- Qualification at level 20+: stat share thresholds (Warrior STR≥35%, Thief AGI≥35%, Spearman STR+AGI≥25% each, Archer AGI≥30%, Mage INT≥35% and 3★+).
- Class change costs **50,000 Silver + 1 Class Change Token**, previews retroactive growth; optional item/cond supported by `classChangeCheck`.

## 5. Mage element affinity
Mage only table for FIRE/WATER/WIND/EARTH/LIGHT/DARK/LIGHTNING (0–100).
Generation: primary 60–90, secondary 30–60, others 0–25.
Multiplier: ≥80 ×1.5 · 60–79 ×1.3 · 40–59 ×1.15 · 20–39 ×1.0 · <20 ×0.8.
Non-Mage casts at 1.0 and gets no affinity bonus.

## 6. Damage pipeline
1. Hit check `clamp(90 + accuracy − evasion, 5, 98)`.
2. Mitigation `(ATK×SkillMult + Bonus) × K/(DEFeff + K)`, K=500; `DEFeff = max(0, DEF×(1−pen%) − penFlat)`.
3. Element affinity (magic only).
4. Damage bonus.
5. Crit (rate after CritRES; crit damage after CritDMGRes).
6. Block (rate → effect).
7. Damage reduction.
8. Floor, minimum 1; shield → HP; lifesteal on HP damage; reflect rules external.

## 7. Combat engine
- One action per unit per round, order by **AGI** desc (tie: HERO first, slot asc).
- Skills cost 20% Max MP (min 10), use configured cooldown; basic attack restores 5% Max MP.
- Effects: DAMAGE_SINGLE, HEAL_LOWEST_ALLY; max 30 rounds; winner by side elimination or HP% at cap (DRAW on tie).
- Pre-combat modifiers: equipment (HP/ATK/DEF, Speed→AGI), starvation, injury, loyalty, resonance.
- Rewards on win: Silver, Hero EXP + level-up, Master EXP + level-up; injuries recorded; quests WIN_BATTLE/CLEAR_FLOOR; leaderboard floor. Normal Heroes die permanently and drop gear; Special/Limited become DISABLED.
- Session advance is claimed atomically (`ACTIVE → RESOLVING → COMPLETED`) so rewards pay once.

## 8. Data model (added)
`heroes`: base_str/int/sta/agi, class_code, combat_role, training_stats, origin_stats, mp/max_mp, current_hp_pct/mp_pct.
`hero_templates`: base stats, archetype_weights, class_options, class_code, combat_role, is_enabled.
Tables: `hero_class_definitions`, `subclass_definitions`, `hero_subclasses`, `hero_element_affinities`.
Legacy columns `hp/attack/defense/speed` remain as mirrored display data (decision b) until PvP/expedition move to v2.

## 9. APIs
- `POST /api/heroes/:heroId/train` `{stat, points}`
- `POST /api/heroes/:heroId/class-change` `{targetClass}`
- `POST /api/heroes/:heroId/awaken` (existing endpoint, v2 branch: +10/stat/rank, +1 skill level, new special trait)
- `POST /api/combat/v2/simulate` `{heroIds, enemyCodes?, maxRounds?, seed?, persist?}`
- `POST /api/combat/v2/session/start` `{heroIds, enemyCodes?, seed?, maxRounds?}`
- `POST /api/combat/v2/session/:id/advance`
- `GET /api/combat/v2/sessions`

## 10. Imprints
- `imprint_definitions`: rank **S/A/B**, tier, bonus STR/INT/STA/AGI/HP/ATK/DEF, ability text.
- `hero_imprints`: one row per (Hero, imprint), `rank_level` 1–3.
- Awakening grants the first enabled imprint (rankLevel 1) or raises an owned imprint below rank 3; response returns `imprintGranted`.
- Imprint bonuses are added to base stats before derivation in level-up, training, class change, awakening and Combat v2 sessions.
- APIs: `GET /api/imprints`, `GET /api/heroes/:heroId/imprints`.
- Pending: slot limits by star/rank promotion and ability execution (Phoenix revive, Iron Will CC reduction).

## 11. Known gaps (Unity backlog)
Imprint Evolution UI, trait tiers, skill-choice UI, Rank Promotion flow, client UI/VFX, TTK tuning. See `UNITY_BACKLOG.md`.
