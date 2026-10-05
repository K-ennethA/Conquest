# PROGRESSION — levels, XP, stats, regional bands, bond and catch rates (story mode)

Owner decisions: DECISIONS.md #65, #68, #76, #78, #79-#82. **DECISIONS.md wins over this file.**
Every number here is a default on ONE tuning resource (`ProgressionRules`, CONQUEST.md rule 11:
tuning lives on data, not in code). Nothing below is a hard-coded constant.

## 1. Levels and XP
- Every story party member (creatures now; humans when they become units, #54) has a **level**
  (1 .. `max_level`, default **50**) and **XP**.
- **Curve:** cumulative XP to reach level L = `round(xp_curve_k * L ^ xp_curve_pow)`
  (defaults k = 1, pow = 3, so level 50 = 125,000 XP). XP past the cap is discarded.
- **XP for a defeated foe** (computed per receiving member, with that member's own level):
  `xp = base_yield(species) * foe_level / xp_level_divisor * level_factor * battle_mult * share`
  - `level_factor = ((2*Lf + 10) / (Lf + Lm + 10)) ^ xp_level_exp` (default exp 2.5): a stronger foe
    gives MORE, an equal one the baseline, a weaker one LESS (#79: anti-grind).
  - **Anti-grind floor:** a foe `xp_grey_gap` (default 5) or more levels below the member gives
    `xp_grey_mult` (default 0.1) of that; never below `xp_min` (default 1).
  - `base_yield`: per species on CharacterResource (`xp_yield`, default derived from its stat
    budget so stronger species give more).
  - `battle_mult`: wild 1.0, trainer/scripted 1.5, chief/legend 2.0 (knobs).
  - `share`: fought and survived 1.0; fought and fell `xp_share_fallen` (0.5); benched
    `xp_share_bench` (0.0, a knob for an Exp-Share style setting). A loss / flee / spar gives
    `xp_on_loss_mult` (0) unless the ruleset says otherwise.
- **Level up:** stats recomputed; current HP keeps its ratio. The results screen lists XP gained and
  any level-ups; the party page shows Lv + an XP bar.
- **Joining:** a member joins at an authored level (`JoinPartyCommand.level`; caught creatures keep
  the level they were met at). The starter joins at `starter_level` (default 5).

## 2. Stats
- `stat(L) = round(base * (1 + growth_s * (L - 1)))` per stat, with `growth_s` from the species'
  per-stat growth (the `*_growth` fields on UnitStatsResource / CharacterResource), falling back to
  `default_growth` (0.04 per level: level 50 is about 3x base). HP, ATK, DEF, MAG, MDEF scale; SPEED
  scales by `speed_growth_mult` (0.5 of its growth); MOVEMENT never scales.
- ONE function computes it and BOTH battle types use it, on a duplicated resource (CONQUEST.md
  rule 7): the duel (alongside the existing `strength` multiplier, which stays for compatibility)
  and the tactical board (at spawn). Player side and enemy side alike.

## 3. Enemy levels, regional bands, scaling (#76, #80, #81)
- Each area has a **level band** (`OverworldAreaResource.level_band`, min..max). Wild encounter
  rows roll a level in the zone's band (seeded, deterministic). Proposed bands:

  | Region | Levels |
  |---|---|
  | The Heartlands (Oakvale, Mossway, River Crossing, Crownhaven) | 2-8 |
  | The Deep Woods (Sparse Forest, Woodland Town, Deepwood) | 8-15 |
  | The Sunlit Coast / isles | 12-20 |
  | The Snowy Peaks (Frostpeak) | 18-26 |
  | The Rocky Badlands (Redrock, the enemy base) | 22-30 |
  | The Northern Mountains (Mountain Base) | 25-35 |
  | The Mountain Pass and beyond | 35+ |

- Trainers / scripted battles: `BattleSpec` opponents carry a **level** (team rows and tactical
  map spawns). `level_mode`:
  - **FIXED** (default): the authored level. Main-line bosses (Mountain Base, the Mountain Pass,
    the enemy base, the finale) are FIXED and rise steadily -- the linear spine.
  - **SCALED**: `clamp(party_top_level + scale_offset, scale_min, scale_max)`. **Chiefs are
    SCALED** within their region's band, so they can be taken in any order (#80).
  - **Legends are FIXED and do NOT scale**: authored ABOVE their area's band (band max +
    `legend_over_band`, default +5) to be a real challenge (#81).
- Going somewhere early is allowed; its creatures are simply too strong (the soft gate). Hard gates
  stay few: field moves (trees, sea) and story beats.

## 4. Bond level (#65, #67, #68)
- Per party member: `bond_xp` and **bond level** (0 .. `bond_max`, default 10).
- Earned by **fighting alongside** the creature: every battle it is fielded in gives
  `bond_per_battle` (win `bond_per_win`), whatever the outcome but a flee.
- Read by the stone boost (later): the boost works to its full potential at max bond. The bonuses
  themselves are defined later (#65) -- for now only the level exists and is shown.

## 5. Catch / bond rate per species (#78)
- `CharacterResource.catch_rate` (0..1, default by stat budget: strong species are hard). It
  multiplies the existing befriend/catch chance.
- Ordinary trainers, new shard users and chain-using villains draw their teams mostly from
  high-catch-rate (easy) species; a content validator warns when a non-boss trainer fields a
  low-catch-rate species.

## 6. Evolution
Evolution keeps its existing triggers (Growth, feats, items, places, flags...). A **LevelTrigger**
(level >= N) is added as one more trigger kind; no existing edge is migrated. How each line
evolves is decided later (#82).

## 7. Saves
`StoryPartyMember` gains `level`, `xp`, `bond_xp` (format_version stays 2: a save without them
loads every member at `legacy_level` (default 5) with 0 XP and 0 bond).

## 8. As built (2026-10-04) -- choices the spec left open, and where the build differs
Implementation map: docs/STORY_MODE.md "Progression". Knobs: `game/overworld/content/progression_rules.tres`.
- **Numbers the spec did not fix:** `xp_level_divisor` 7 and `xp_yield_per_budget` 0.5 (a level-5
  Barkling-class foe pays ~38 XP wild; level 5 -> 6 needs 91), `xp_yield_min` 10. Bond levels are
  linear: bond level = bond_xp / `bond_xp_per_level` (5), capped at `bond_max`.
- **Catch-rate default:** 1.0 at or below power budget `catch_budget_easy` (130), `catch_rate_min`
  (0.2) at or above `catch_budget_hard` (240), linear between -- every current base form is 1.0
  (easy), evolved / knight-class forms land around 0.4-0.7, Eldroot 0.2. The content check
  (`BattleSpec.catch_warnings`, threshold `low_catch_rate` 0.5) is an advisory a test PRINTS; it does
  not fail the build, since several existing (placeholder) trainers field strong forms.
- **Spar XP** has its own multiplier, `xp_spar_mult` (0), instead of sharing `xp_on_loss_mult`; a
  flee / abort always pays 0. Spars still build BOND (fighting alongside, #68).
- **No XP split:** each member that fought earns the full per-foe formula with its own level and
  share (the spec's formula has no participant divisor).
- **Per-species growth** lives on `CharacterResource` (`health_growth` ... `speed_growth`, negative =
  `default_growth`). The old `UnitStatsResource.*_growth` fields (default 1.0, a different meaning)
  are left unused.
- **SCALED** sets EVERY foe of the battle to the one scaled level (rows' own levels are overridden);
  `BattleSpec.make_chief(spec, band, offset)` scales inside the region band. `make_legend(spec,
  band)` sets the band max + `legend_over_band` on every foe and marks it a boss battle.
- **Boss multiplier** is opt-in per battle (`BattleSpec.boss_battle`), set by the chief / legend helpers.
- **Guest allies** on a story tactical board (map units that are not party members) fight at the
  party's top level.
- **The Mossway's grass** is narrowed to 2-5 inside the Heartlands' 2-8 (the first route).
- **Tactical replays** of a story battle spawn at roster base (a replay is not a live story battle),
  the same existing gap as carried HP. Duel replays carry the levels (`DuelCombatant.level`).
