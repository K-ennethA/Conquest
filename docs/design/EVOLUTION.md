# EVOLUTION — class evolutions for Conquest

> Design doc for the owner (solo dev) and implementing agents. Verified against
> `Conquest-reconcile` @ `reconcile/cloud-merge`. Companion docs: `OVERWORLD.md`, `DUEL.md`
> (the interfaces this doc expects from them are in §6).

**One-line pitch:** an evolved form is just another `CharacterResource`. A small evolution
graph (data) links the forms. A persistent **roster ledger** records how far each of *your*
units has grown. Evolving swaps the form a unit fields: between battles by default, and
mid-battle via one new `MoveEffect` when a line opts in.

---

## 1. What exists today (and must not break)

### 1.1 Unit identity: `character_id` is everywhere

There is **no per-unit XP, level or individual record** today. I checked: the only "experience"
code is the dead legacy `game/tiles/TileEffect.gd` `EXPERIENCE_BOOST`. A unit's identity is its
`CharacterResource.character_id`, and a "unit" is a species. Every persistent or replicated
system keys on that id:

| System | File | Keyed by | Notes |
|---|---|---|---|
| Roster | `game/characters/CharacterResource.gd`, `CharacterLibrary.gd` (scans `game/characters/roster/*.tres`, id = filename) | `character_id` | Stats, element, tags, moveset (≤4), abilities, `model_scene`, `model_yaw_deg`, `model_scale`, footprint, sight |
| Squad pick | `menus/CharacterSelect.gd` → `GameSettings.selected_squad` (unique picks, `EXCLUDED_IDS`, bosses hidden) | `character_id` list | Open roster: every non-boss character is pickable in every mode |
| Spawn | `game/maps/MapLoader.gd` `_load_units` / `_create_unit_from_spawn` / `resolve_player_squad` | `character_id` | Sets `unit.character_resource` **before** `add_child` |
| Live unit | `tile_objects/units/unit.gd` | `character_resource` | Stats come from `_build_stats_resource_from_character`; moves from `character_resource.moveset`; `get_element()`, footprint, movement profile, facing yaw and scale are all read off the resource |
| Items | `game/items/ItemInventory.gd` (`user://items.json`: `equipped{character_id: item_id}`), `ItemSystem.gd` (`loadout_for(character_id)`) | `character_id` | Equipment only (UNIT / TEAM scope). There are no consumables |
| Skins | `game/skins/SkinResource.gd` (`character_id` field), `PlayerProfile.equipped_skins{character_id: skin_id}`, `Unit.apply_equipped_skin` | `character_id` | A skin can tint or swap the model. `Unit._rebuild_character_model(scene)` already hot-swaps a model |
| Net versus | `systems/net/MatchLoadouts.gd` (card: `squad`, `equipped`, `team`, `skins`, all whitelisted against the libraries) | `character_id` | Units are addressed by `NetUnitIds` (`"<slot>:<n>"`), **not** by character. `NetGameRules.state_digest` rows: id, cell, HP, flags, statuses, cooldowns |
| Replays | `systems/replay/ReplayLog.gd` (header `participants[].squad/equipped/skins`; body = `NetProtocol` commands; `USE_MOVE` addresses a **moveset slot index**), `ReplayRecorder.board_state_rows` (id, cell, hp) | `character_id` in header | Lockstep re-simulation. Checksums must stay stable for old files |
| Battle save | `systems/save/BattleSnapshot.gd` / `BattleSaveManager.restore_units` | `character_id` per unit entry | **Double-apply rule:** it stores inputs (items, statuses), never computed stats. Only current HP is stored |
| Arena | `game/arena/ArenaUnitState.gd` (`character_id`, `augment_ids`, `carried_hp`) | `character_id` | Rebuilt into a live Unit each round |
| Profile | `game/profile/PlayerProfile.gd` (`user://profile.json`), `AchievementData.gd` (pure, retroactive table) | none per unit | Points, rank, skins, achievements |
| Compendium | `menus/CompendiumData.gd` `unit_entries()` (every roster id), `game/ui/screens/UnitPageContent.gd` | `character_id` | `tests/unit/test_compendium.gd` fails if any unit is missing, so new forms must render |
| Portraits | `game/ui/PortraitCache.gd` (captures from `model_scene`, disk cache per id) | `character_id` | A new form gets its portrait for free |

### 1.2 Combat machinery an evolution touches

- **Moves:** `MoveResource` (`move_id`, `element`, `cooldown`, `max_uses`, `is_ultimate`;
  slot 3 is always an ultimate, see `MoveResource.is_ultimate_move`).
  `game/combat/MovesetController.gd` tracks cooldowns and uses **by `move_id`** and has
  `snapshot_state` / `restore_state`.
- **Abilities:** `AbilityResource` (trigger, condition, effects, rule_modifiers) run by
  `game/abilities/AbilitySystem.gd`. The node exists only when the character has abilities.
  Arena `GrantAbilityEffect` adds abilities at runtime. Conditions are composable classes
  (`HealthBelowCondition`, `UnitElementCondition`, `AllCondition` …). Triggers include
  `ON_KILL` and `ON_BATTLE_START`.
- **Elements:** `CharacterResource.element` holds ONE element from the vocabulary `fire water nature
  wind earth holy dark`. It is read through `Unit.get_element()` → `ElementChart.element_of`, and
  `DamageMath` is the one damage chain shared by the forecast and the hit (CONQUEST.md rule 9).
  Changing the element at runtime is automatically consistent because nothing caches it.
- **Stats:** `game/units/components/UnitStats.gd`. Items and augments apply **permanent**
  deltas through `modify_stat(..., is_permanent=true)`. Timed buffs are modifiers.
- **Statuses:** `StatusController` on the unit. They refresh and never stack (rule 6).
- **Effect pipeline:** `MoveEffect` subclasses resolve against a `MoveContext`. They are
  shared by moves, tiles, statuses and abilities (`docs/DESIGN_ROADMAP.md` §2). `SummonEffect`
  is the precedent for an effect that changes the board through a unit-level API.
- **Presentation:** `game/ui/hud/UltimateCutIn.gd` (CanvasLayer 124, awaited by cast sites,
  animations-off static flash, headless-safe). Other pieces: `StoryDialogue`,
  `UnitPreview3D` (turntable used by Character Select), `GameOverScreen` rewards section (reads
  `ItemSystem.drops_this_battle()`), `FloatingCombatText`, `BattleLog`.
- **Mode tuning:** `ModeTuning.get_int/get_bool(&"knob", neutral)` over the active
  ruleset (rule 11).
- **Model pipeline:** `tools/blender/prepare_unit.py` + `.claude/skills/blender-unit-import`.
  It exports feet-at-origin, fits one cell, and faces +Z, so `model_yaw_deg` is 0. Check the
  result with `dev_scripts/render_unit_facing.gd`.

### 1.3 Invariants this feature must keep

1. **Nothing inside the simulation reads local persistent state.** Items and skins enter a
   battle only through the squad/loadout card and the replay header. Evolution follows the
   same rule, so the roster ledger is never read mid-battle.
2. **Old replays, saves and profiles still load.** Add only optional keys and never bump
   `FORMAT_VERSION` for them.
3. **Expected failures return `{success, reason}`**, with no `push_error` (rule 1).
4. **Balance lives in `.tres`** (rule 11 plus the content-authoring tiers).

---

## 2. Player experience

### 2.1 What it feels like

- Your units **grow**. After a battle, the summary card shows Growth pips next to the loot:
  *"Barkling +1 Growth (3/3) — ready to evolve!"*
- Evolution is a **moment**, not a menu toggle. A full-screen grove card reads
  *"Barkling is evolving…"*. The model on the turntable pulses to a white silhouette, bursts,
  and reveals **Oakheart**. A stat diff (green deltas), the new move and the new ability follow,
  plus the element gem if the type changed. You can press **Not now** (Pokémon's B-button) and
  keep the old form. The offer stays open.
- The evolved form is a **real unit** with its own name, model, portrait, Compendium page,
  crest colour, moves and matchups. The Compendium shows the line: *Barkling → Oakheart
  (Growth 3)*.
- Where the content opts in, evolution can also happen **mid-battle**: an ultimate-style
  cut-in, the model swaps on the board, and *"EVOLVED!"* floats over the unit.
  Examples are a boss phase change, or a line whose signature move is its own awakening.

### 2.2 Walkthrough (the first vertical slice)

1. Skirmish on River Crossing with Vineweave, Geode and **Barkling**. You win and Barkling
   survives. The summary shows *Barkling +1 Growth (1/3)*.
2. Two wins later: *(3/3) Ready to evolve!* On the Barkling card in Character Select, three
   gold growth gems are lit and a gold **EVOLVE** button sits in the detail pane.
3. Press it. The Evolution screen plays, then the reveal: **Oakheart**. HP 55 → 96, Atk 14 → 21.
   The ultimate slot, empty on Barkling, is now **Timberfall**. New ability: **Thornskin**.
4. Barkling's equipped *Ironbark Sigil* moved to Oakheart ("item carried over").
   Oakheart now appears in the roster grid. Barkling stays pickable too (see Q1).
5. The achievement toast "Late Bloomer — evolve a unit" appears. That is milestone 3; it is not
   part of the slice.

---

## 3. Data model

### 3.1 Forms are CharacterResources (the core decision)

Each evolved form is a normal roster `.tres` with its own `character_id`, for example
`game/characters/roster/oakheart.tres`. That single choice makes the model, facing, portrait,
Compendium, skins, the map maker, challenge codecs, AI, replays and the MatchLoadouts
whitelist work **unchanged**. To the wire, "an evolved Barkling" is just `"oakheart"`.

**Options considered:**

| Option | How | Pros | Cons |
|---|---|---|---|
| **A. Form = its own CharacterResource + evolution graph** *(recommended)* | New id per form. Separate `EvolutionResource` edges | Zero changes to the 12 identity consumers. Evolving into an **existing** unit ("becomes another unit") is the same data as a continuation. Forms can be authored as ordinary Tier-1 content | Per-id persistence (items, skins) needs a small re-key on evolve; see 3.5 |
| B. `forms[]` overrides inside one CharacterResource | Same id; a form index overlays fields | Items and skins stay keyed | Every reader of `character_resource` (a dozen systems, the Compendium, the portrait cache, facing) must learn "resolved form". The wire, replays and saves need a new field. It cannot evolve into another shipped unit |
| C. Runtime-merged duplicate resource | Duplicate the base and patch fields at spawn | No new ids | Breaks `CharacterLibrary` caching, portraits and the Compendium, and is invisible to the wire. Worst of both |

### 3.2 `EvolutionResource`: one edge of the graph

New file `game/characters/evolution/EvolutionResource.gd`. Content lives under
`game/characters/evolutions/*.tres`, scanned like `ItemLibrary` / `SkinLibrary`.

```gdscript
class_name EvolutionResource extends Resource
@export var id: StringName                  # stable, e.g. &"tree_grunt__oakheart"
@export var from_id: StringName             # roster character_id
@export var to_id: StringName               # roster character_id (new form OR an existing unit)
@export_multiline var flavor: String = ""   # "The sapling finally takes root."
@export_group("Triggers")
## ANY listed trigger being satisfied makes the evolution AVAILABLE (OR). Compose AND with
## an AllTrigger, mirroring AllCondition. Empty = never available out of battle.
@export var triggers: Array[EvolutionTrigger] = []
## Out-of-battle evolutions wait for the player to confirm (Pokémon style). false = automatic
## (for example, story beats).
@export var requires_confirmation: bool = true
@export_group("In battle")
## Opt-in: this edge may ALSO fire mid-battle through EvolveEffect (see §4.3).
@export var allowed_in_battle: bool = false
## BATTLE = reverts after the battle (an "awakening"). PERMANENT = in STORY the ledger
## commits it after the battle; in open modes it is always battle-scoped.
@export_enum("BATTLE", "PERMANENT") var in_battle_persistence: int = 0
@export_group("Carry-over")
@export_enum("KEEP_RATIO", "KEEP_DAMAGE", "FULL_HEAL") var hp_policy: int = 0
@export var carry_statuses: bool = true       # mid-battle only
@export var carry_cooldowns: bool = true      # shared move_ids keep their timers
@export var carry_item: bool = true           # re-key the UNIT item on a permanent evolve
@export var carry_tint_skin: bool = true      # tint-only skins follow the line (M3)
```

**Triggers.** Small subclasses, the same pattern as `AbilityCondition`. They are pure
`is_met(ctx: Dictionary) -> bool` where `ctx` is built **outside** the simulation:

| Trigger | Fields | ctx keys it reads | Milestone |
|---|---|---|---|
| `GrowthTrigger` | `growth_required: int` (cumulative per member) | `growth` | M1 |
| `CatalystTrigger` | `item_id: StringName`, `consume: bool = true` | `owned_items` | M3 |
| `StoryFlagTrigger` | `flag: StringName` | `story_flags` (OVERWORLD) | M4 |
| `AllTrigger` | `triggers: Array[EvolutionTrigger]` | n/a | M3 |

**Branching** means several edges with the same `from_id`, for example Barkling → Oakheart
(Growth 3) and Barkling → Cinderbark (Ember Seed). When more than one is available, the
Evolution screen shows a choice.

**Validation** lives in `EvolutionLibrary.validate()` and is pinned by a test:
- `from_id` and `to_id` resolve in `CharacterLibrary`.
- Each form has **at most one** `from` (a single parent, as in Pokémon), so `line_root(id)` is
  unambiguous.
- There are no cycles.
- A boss can be neither `from` nor `to` for the player, unless the edge has `allowed_in_battle`
  and the form `is_boss` (boss phase changes).
- `allowed_in_battle` edges keep the **same footprint**. A mid-battle footprint change is
  refused (see §4.3).
- The power budget stays in bounds: `to.power_budget()` ≥ `from.power_budget()` and
  ≤ `from × EvolutionRules.max_budget_growth`.

### 3.3 `EvolutionLibrary` (static index, mirrors `ItemLibrary`)

`all()`, `get_edge(id)`, `edges_from(char_id)`, `edge_between(from, to)`, `parent_of(id)`,
`line_root(id)`, `line_of(id)` (root plus descendants, BFS order), `stage_of(id)` (1 = base),
`is_evolved_form(id)`, `validate()`, `rescan()`.

### 3.4 `EvolutionRules`: the balance and progression knobs (one `.tres`)

`game/characters/evolution/evolution_rules.tres` follows the CONQUEST.md convention: every
number is data.

| Knob | Default | Meaning |
|---|---|---|
| `growth_per_win` | 1 | A squad unit that fought and survived a won solo battle |
| `growth_per_ko` | 0 | Bonus per enemy KO (off in the slice; turn on to reward aggression) |
| `growth_ko_cap` | 2 | Maximum KO bonus per battle |
| `growth_on_loss` | 0 | Participation growth on a defeat |
| `growth_modes` | `["skirmish","campaign","challenge"]` | Where growth is earned. Arena and versus are excluded |
| `max_budget_growth` | 1.75 | Validator ceiling (Oakheart is about 1.6×) |
| `hide_locked_forms` | true | Character Select hides forms not yet evolved into (solo) |

Mode knobs go through `ModeTuning`, with neutral values so plain skirmish is unchanged:
- `ModeTuning.get_bool(&"allow_battle_evolution", true)`: Siege or Versus rulesets can turn
  mid-battle evolution off.
- `ModeTuning.get_int(&"max_form_stage", 0)` (0 = unlimited): a "little cup" or a
  fair-versus format (M3).

### 3.5 Persistence: `RosterLedger` (the persistent "roster member")

New static store `game/characters/evolution/RosterLedger.gd`. It deliberately copies
`ItemInventory`: static, lazy-load, **explicit `save()`**, and `set_save_path()` / `reset()`
for tests. File: `user://roster.json`.

```json
{
  "version": 1,
  "members": {
    "tree_grunt": { "line": "tree_grunt", "form": "oakheart", "growth": 3,
                    "evolved": [{"edge": "tree_grunt__oakheart", "at": "2026-09-27T20:01:00"}],
                    "nickname": "" }
  },
  "unlocked_forms": ["oakheart"]
}
```

- **Member uid.** In M1 there is one implicit member per line, and its uid is the line root id
  (`"tree_grunt"`). Story recruitment (OVERWORLD) can later add `"tree_grunt#2"` without a schema
  change. Every API takes a uid, and `member_for_character(id)` resolves it through `line_root`.
- **API:** `growth_of(uid)`, `add_growth(uid, n)`, `form_of(uid)`, `available_evolutions(uid,
  ctx_extra={}) -> Array[EvolutionResource]`, `evolve(uid, edge) -> {success, reason}`,
  `is_form_unlocked(id)` (a base form is always unlocked), `unlocked_forms()`.
- **`evolve()` side effects:** it re-checks availability, sets `form`, appends to `evolved`,
  adds `to_id` to `unlocked_forms`, and consumes a catalyst (M3). If `carry_item` is set it
  calls a new `ItemInventory.rekey_character(from, to)`, which moves the UNIT equip only when
  `to` has none. A tint skin follows through `carry_tint_skin` (M3). It then saves the ledger
  and the inventory.
- **Why a new store instead of `PlayerProfile`:** the profile's API is a fixed contract with
  a skins agent. The ledger is read by menus, the growth tracker, the overworld and the duel, and
  the static-store precedent (`ItemInventory`) is already the project's pattern. Achievements
  read the ledger file retroactively, the same way the profile already reads
  `campaign.json`.

**Identity semantics** (Q1). In **open modes** (Skirmish, Challenge, Versus) evolution is an
**unlock**: both Barkling and Oakheart stay pickable. In **story** (overworld party) the
member itself **becomes** Oakheart (`form`), which is Pokémon's replacement feel. The same
ledger serves both.

---

## 4. Runtime flow

### 4.1 Earning growth (post-battle, local, like item drops)

New `game/characters/evolution/GrowthTracker.gd`. It is **mounted per battle by
`GameWorldManager`**, exactly like `_setup_item_system`. It re-derives the win the way
`ItemSystem._evaluate_outcome` does, once per battle, and then:

- gates: `ReplayPlayback.is_playing()` false (precedent: `CampaignController.story_suppressed`),
  `MatchLoadouts.is_active()` false (no growth in network versus), arena not active, and the
  mode in `growth_modes`;
- for each **human-owned unit that was fielded from the squad and is alive**, maps
  `unit.character_resource.character_id` → `RosterLedger.member_for_character` → `add_growth`;
- latches `growth_this_battle()` as a static list of `{uid, gained, total, ready}`, the same
  pattern as `ItemSystem.drops_this_battle()`, for `GameOverScreen`.

The award math is a **pure static** `compute_awards(rows, won, rules) -> Dictionary` so unit
tests need no scene. The node reads only post-battle live state and never feeds back into the
simulation.

### 4.2 Evolving out of battle (M1 default)

```
Character Select (detail pane) ── EVOLVE ──▶ EvolutionScreen.open(uid, edges)
   │                                              │ player confirms (or picks a branch)
   │                                              ▼
   │                                  RosterLedger.evolve(uid, edge) ─▶ ItemInventory.rekey + save
   ◀──────────── roster grid rebuilt (to-form unlocked, pips reset to next stage) ◀┘
```

The same `EvolutionScreen.open(...)` is called by the **overworld** after a battle or an
event, and by the **duel** results screen (§6). Only the caller changes.

### 4.3 Evolving mid-battle (M2): the one new `MoveEffect`

Mid-battle evolution runs through the **existing effect pipeline**, so it needs **no new net
command and no replay format change**:

- **`EvolveEffect extends MoveEffect`** with `@export var evolution: EvolutionResource`. It
  applies to the caster (or to each target, which gives boss-support content for free) through
  `Unit.apply_form(...)`.
- **Player- or AI-chosen:** put it in a move, e.g. a line's slot-3 "Take Root". The move rides
  the ordinary `USE_MOVE` command, gets the ultimate cut-in for free, and `max_uses = 1`
  limits it.
- **Automatic:** put it in an ability, e.g. `trigger ON_KILL`, condition
  `BattleKillsAtLeastCondition(2)` (new, tiny) or `HealthBelowCondition(0.5)` (boss phase),
  `max_activations 1`. Abilities already fire on every peer inside the apply path.
- **Refusals** return reasons and never reach the engine log: `"not_allowed_in_battle"`
  (the edge lacks `allowed_in_battle`), `"mode_forbids"` (the ModeTuning knob),
  `"footprint_change"`, `"wrong_form"`, `"dead"`.

**`Unit.apply_form(to: CharacterResource, edge: EvolutionResource, presentation := true) ->
Dictionary`.** This is the single runtime swap. It is also used by battle-save restore and by
the duel.

| Step | Detail | Why |
|---|---|---|
| 1. Validate | Alive, same footprint, `to != current` | Footprint changes would re-key board occupancy mid-turn |
| 2. **Stats by DELTA** | For each stat: `modify_stat(stat, to.base − from.base, is_permanent=true)` | Never rebuild from scratch. Item and augment permanent deltas and live modifiers survive. This mirrors the BattleSnapshot double-apply rule |
| 3. HP | `KEEP_RATIO`: `round(hp/old_max × new_max)` (min 1). `KEEP_DAMAGE`: `new_max − damage_taken`. `FULL_HEAL` | Data knob per edge |
| 4. Swap | `character_resource = to`; `stats_resource.unit_name` / `unit_type` updated | Element, movement profile, sight and moves now read the new form, and DamageMath preview/hit parity holds automatically |
| 5. Moves | Nothing to do. `MovesetController` is keyed by `move_id`, so shared moves keep their cooldown (`carry_cooldowns`) and new moves start ready | No "evolve to reset Rooted" exploit |
| 6. Abilities | New `AbilitySystem.replace_character_abilities(old_list, new_list)`: drop abilities that came from the old form and are not in the new one, add the new ones, keep **granted** ones (arena) and keep per-ability state for survivors. Create the node if it is absent. **`ON_BATTLE_START` abilities of the new form do not fire** | Deterministic and documented |
| 7. Statuses | Kept (`carry_statuses`). Refresh semantics are unchanged | A burning Barkling is a burning Oakheart |
| 8. Visual | `_rebuild_character_model(to.model_scene)` (the skin path), `_orient_character_model` (new `model_yaw_deg` / `model_scale`), reset `_applied_skin_id` then `apply_equipped_skin()` | Facing keeps `_facing`; only the authored yaw changes |
| 9. Bookkeeping | `set_meta(&"spawn_form", …)` once and `set_meta(&"form_chain", [...])` | Used by saves, checksums and post-battle commit |
| 10. Announce | `GameEvents.unit_evolved(unit, from, to)` (new signal) | The HUD refreshes the portrait, crest, name and HP bar. BattleLog: "Barkling evolved into Oakheart!". FloatingCombatText: "EVOLVED". `EvolutionCutIn` plays. The vision set recomputes |

Presentation is awaited only by the cast site, the same contract as `UltimateCutIn`. The state
change itself is synchronous inside the effect.

After the battle, in **story**, an edge with `in_battle_persistence = PERMANENT` is committed to
the ledger by `GrowthTracker`. It reads `form_chain` off the surviving unit (post-simulation,
local). In every other case the unit simply spawns in its squad form next battle.

### 4.4 Determinism, networking, replays and saves

| Surface | Pre-battle evolution | Mid-battle evolution |
|---|---|---|
| Squad / `MatchLoadouts` | The form id is in `squad`, already whitelisted by `CharacterLibrary`. **No change** | n/a |
| Commands | n/a | Rides `USE_MOVE` (a move) or no command at all (an ability). **`PROTOCOL_VERSION` unchanged** |
| Lockstep | n/a | `EvolveEffect` runs inside `MoveExecutor` / `AbilitySystem` on every peer. Conditions read **battle state only**; the ledger is never read (invariant 1) |
| `NetGameRules.state_digest` | n/a | Add `String(u.character_resource.character_id)` to each row, so a form divergence is a detected desync. The digest isn't persisted, and the version gate already guarantees both peers run the same build |
| Replay checksum (`board_state_rows`) | n/a | Add `"form"` **only when the current form ≠ `spawn_form`**. Every old replay hashes identically |
| Replay header | Squad already carries the form id | Re-simulated from commands; nothing new |
| `BattleSnapshot` | `character_id` = form, unchanged | Entry gains an optional `"form_chain": ["oakheart"]`. `character_id` stays the **spawn** form. Restore order: spawn → items (`ItemSystem.apply_loadout(unit, spawn id)`) → **`apply_form` per chain link, `presentation=false`** → statuses → moveset state → HP last. No `FORMAT_VERSION` bump, because the key is optional |
| Items mid-battle | n/a | Items were applied to the spawn form as permanent deltas and survive step 2. No re-application is needed |
| AI | Picks the form like any character | BotController scores an `EvolveEffect` move as `to.power_budget − from.power_budget` scaled by remaining HP. Ability-based evolutions need no AI |

### 4.5 Moves, abilities, element and Compendium

- **Moves:** a form's moveset is authored in full on its `.tres`, not as a diff. Reusing
  `MoveResource`s across forms is encouraged, because shared `move_id`s are what carry
  cooldowns. Filling an empty slot 3 makes it the ultimate automatically.
- **Element:** a single field change on the form. `DamageMath` / `ElementChart` need nothing
  new, and `test_element_preview_parity` style coverage extends to "evolved mid-fight, the
  forecast equals the hit".
- **Compendium** (`CompendiumData.unit_entry`): add an **Evolution** block to the unit page.
  It shows the line strip `[url=units:tree_grunt]Barkling[/url] → [url=units:oakheart]Oakheart[/url]`,
  with the trigger text from `EvolutionTrigger.describe()` ("Growth 3", "Ember Seed",
  "In battle: 2 KOs") and "Evolves from … / Evolves into …". It adds keywords so search finds
  "evolve". The **Rules** section gets an "Evolution" entry (growth rules from
  `evolution_rules.tres`, carry-over rules). The page is all data-driven, so new lines appear
  without code.

### 4.6 Looks

- **Model per form** via the Blender pipeline:
  `prepare_unit.py --output game/characters/models/forest/oakheart.glb --name oakheart
  --target-height 1.8`. It exports facing +Z, so `model_yaw_deg = 0`. Bigger silhouettes come
  from `model_scale` (Oakheart 1.2) while the footprint stays 1×1. Verify with
  `dev_scripts/render_unit_facing.gd`.
- **Slice placeholder** (no new sculpt needed): `oakheart.tres` points at `tree_grunt.glb` with
  `model_scale = 1.3`. It's swapped for the real sculpt later with a one-field edit.
- **Skins per form:** a `SkinResource` is authored against the form id (`oakheart_autumn`).
  M3 adds `carry_tint_skin`: a *tint* skin on the parent also dresses the child when the child
  has no equipped skin. `MatchLoadouts.skin_for` / `normalise` accept a skin whose
  `character_id` is a line ancestor of the announced form.
- **Portraits:** automatic per id (`PortraitCache`).
- **Presentation:**
  - `EvolutionScreen`: a menu overlay built on `UnitPreview3D`.
  - `EvolutionCutIn`: a subclass or variant of `UltimateCutIn` with "EVOLVES" and both names.
    It sits on the same layer rules, has an animations-off static flash, and is headless-safe.
  - On the board, a white-flash tint pulse via `SkinLibrary.tinted_material`, then the model
    swap and a ring burst. `MoveFXDispatcher`'s default ring can be reused.

---

## 5. UI screens (grove look, `docs/UI_STYLE.md`)

| Screen | Where | Content | Kit |
|---|---|---|---|
| **Growth pips** | Character Select card + detail pane | "GROWTH" gold small-caps tag plus N `GroveGem`s (lit = earned). "Stage II · from Barkling" `MenuKit.badge` | `GroveGem`, `MenuKit.badge` |
| **EVOLVE button** | Detail pane, beside Equip | `PrimaryButton` (gold tag), shown only when `available_evolutions` is non-empty | Theme variation `PrimaryButton` |
| **Locked form card** | Roster grid (solo, when `hide_locked_forms` is false) | Dim sunk card, silhouette crest, "Evolves from Barkling · Growth 3" | `MenuTheme.inset_box`, disabled rules |
| **Evolution screen** | Overlay CanvasLayer (from Character Select, the overworld or duel results) | Ribbon title "Barkling is evolving…"; `UnitPreview3D` turntable (old → white pulse → new); two crests with element gems; stat diff rows (base → new, `SUCCESS` deltas); "New move" / "New ability" content cards (`UnitPageContent.build_move_card`); buttons **Evolve** / **Not now**; branch = two `OptionCard`s. Controller: `ui_cancel` = Not now | `ConquestTheme.title_ribbon`, `MenuTheme.card_box` + `crest = true`, `UnitPageContent` |
| **Growth rows** | `GameOverScreen` rewards section | "Barkling +1 Growth (3/3) — Ready to evolve!" under the drop rows | Mirrors `_build_drop_row` |
| **In-battle** | HUD | `EvolutionCutIn`; BattleLog line; FloatingCombatText "EVOLVED"; UnitInfoPanel / TurnQueue / UnitDetailPage refresh on `unit_evolved` | `UltimateCutIn` rules |
| **Compendium** | Unit page | Evolution line strip with cross-links; Rules → Evolution entry | `CompendiumData` entries |

Every screen follows the existing rules: gold means focus, the crest only on hero surfaces, the
element on the crest, the team on the edge. Animations-off shows a single static flash. The
screens are headless-safe.

---

## 6. Fit with OVERWORLD and DUEL: the interfaces I expect

**What this doc provides (the evolution API):**

```gdscript
RosterLedger.member_for_character(char_id) -> String     # uid
RosterLedger.form_of(uid) -> StringName                    # what to spawn/field
RosterLedger.add_growth(uid, n); RosterLedger.growth_of(uid)
RosterLedger.available_evolutions(uid, extra_ctx := {}) -> Array[EvolutionResource]
RosterLedger.evolve(uid, edge) -> {success, reason}
EvolutionScreen.open(parent: Node, uid, edges: Array) -> signal finished(evolved: bool, edge)
GrowthTracker.compute_awards(rows, won, rules)             # pure, reusable by the duel
Unit.apply_form(to, edge, presentation := true) -> {success, reason}
EvolveEffect (MoveEffect) ; GameEvents.unit_evolved(unit, from, to)
```

**What I expect from OVERWORLD:**
1. **Party = ordered list of RosterLedger member uids**, stored in the overworld save. It
   spawns `form_of(uid)`. If OVERWORLD also designs a "party member" record, merge it into
   `RosterLedger.members` (one store of individuals, not two).
2. **Story flags store** readable as `extra_ctx["story_flags"]` (a `Dictionary` or `Array`)
   for `StoryFlagTrigger`.
3. **An event/NPC action vocabulary** that includes `evolve_member(uid_or_line, edge_id)` (for
   scripted story evolutions such as "the shrine awakens Barkling") and `grant_item(id)` (for
   evolution catalysts found in the world).
4. **A post-battle hook.** When returning from any encounter, call
   `available_evolutions` for each party member and chain `EvolutionScreen`s before control
   returns. This is the Pokémon "after the battle, X is evolving!" moment.
5. **Encounter results** flow through the same win detection, so `GrowthTracker` awards party
   growth. Add `"story"` to `growth_modes`.

**What I expect from DUEL (1v1 turn-based):**
1. Combatants are **`Unit` instances**, or implement the same `apply_form(to, edge,
   presentation)` contract and read `character_resource` for moves, element and stats. Then
   `EvolveEffect` works in a duel unchanged.
2. Damage through `DamageMath` / `ElementChart` (rule 9), so an evolved type is honoured.
3. A duel "Evolve" action, if they want Mega-style mid-duel evolution, is a **move** with
   `EvolveEffect` (or a duel-level command that calls the same `apply_form`). The cut-in is
   `EvolutionCutIn`.
4. Duel end calls `GrowthTracker.compute_awards` (or the tracker is mounted in the duel
   scene too) and then the overworld's post-battle evolution hook.

---

## 7. Trigger matrix and recommended default

| Trigger | Tactical battle | Duel battle | Overworld | Open modes |
|---|---|---|---|---|
| **Growth** (post-battle, confirm) | Earns growth | Earns growth | Evolution prompt after returning | Skirmish, Campaign, Challenge earn it; Versus and Arena do not |
| **Catalyst item** (M3) | No | No | Use from bag or at an NPC | Character Select "Use Ember Seed" |
| **Story flag / event** (M4) | No | No | Scripted | No |
| **In-battle** `EvolveEffect` (M2, opt-in per edge) | Yes | Yes | No | Yes unless `allow_battle_evolution` is off |
| **Arena augment** "Awaken" (M3) | Rewrites `ArenaUnitState.character_id` at draft; next round spawns the form | No | No | Arena only |

**Default:** evolution is **earned out of battle** through Growth (and catalysts). The player
confirms it on the Evolution screen, and it is permanent (an unlock in open modes, a
replacement in the story party). **Mid-battle evolution is opt-in per edge.** Its first uses
should be boss phase changes and a signature "awakening" line, so it stays special and doesn't
cheapen earning the permanent form.

**Options for mid-battle evolution:**

| Option | Pros | Cons |
|---|---|---|
| (a) None | Zero risk | Loses the most dramatic moment |
| **(b) Opt-in through `EvolveEffect` in moves or abilities** *(recommended)* | No protocol or replay changes; content authors choose; bosses get phase changes for free | Needs the runtime swap (M2) |
| (c) A universal "Evolve" command for any unit that has earned growth | Pokémon-Mega feel everywhere | Reads the ledger in the simulation, which breaks versus and replays. It also needs a new `NetProtocol` action, `PROTOCOL_VERSION` 3 and replay `APPLIABLE_TYPES` |

---

## 8. Phased implementation plan

### M1 — Vertical slice: "Barkling takes root" (out-of-battle, Growth trigger, solo modes)

**Why Barkling (`tree_grunt`):** its lore is *"a lurching sapling animated by the Great Tree's
will"*, so it begs to grow up. It has the lowest budget of any pickable unit (107), and its
**slot 3 is empty**, so evolving literally unlocks its ultimate. Its model is simple enough
that a scaled placeholder reads fine.

**Oakheart** (`oakheart`, nature, 1×1, one-word name per CONQUEST.md):

| Field | Barkling | Oakheart |
|---|---|---|
| HP / Atk / Def / Mag / MDef / Spd / Move | 55 / 14 / 8 / 2 / 6 / 7 / 3 | 96 / 21 / 16 / 4 / 12 / 7 / 3 |
| Power budget | 107 | 171 (1.60×) |
| Moves | Tree Bash, Rooted, Verdant Call | **Bough Sweep**, Rooted, Verdant Call, **Timberfall** (ultimate) |
| Abilities | Nature's Blessing | Nature's Blessing, **Thornskin** (already authored, currently unused) |
| Model | `tree_grunt.glb` | placeholder `tree_grunt.glb` × 1.3, then a real sculpt |

All the moves and abilities already exist, so M1 needs no new combat content.

| Task | Scope and files | Acceptance and tests |
|---|---|---|
| **1.1 Evolution data layer** | `game/characters/evolution/EvolutionResource.gd`, `EvolutionTrigger.gd`, `GrowthTrigger.gd`, `EvolutionLibrary.gd`, `EvolutionRules.gd` + `evolution_rules.tres` | `tests/unit/test_evolution_library.gd`: edges resolve; `line_root("oakheart") == "tree_grunt"`; `stage_of`; branching fixture; `validate()` catches a missing id, a second parent, a cycle and a budget out of bounds (use fixture resources built in code, never files on disk) |
| **1.2 Content** | `game/characters/roster/oakheart.tres`, `game/characters/evolutions/tree_grunt__oakheart.tres` (GrowthTrigger 3) | `test_compendium` passes (Oakheart has an entry); `EvolutionLibrary.validate()` is empty over shipped content; `oakheart.validate()` passes; the budget ratio is ≤ `max_budget_growth` |
| **1.3 RosterLedger** | `game/characters/evolution/RosterLedger.gd`; `ItemInventory.rekey_character(from, to)` | `tests/unit/test_roster_ledger.gd` (`set_save_path` to a temp path, the Guard helper): add/read growth; availability at 2 vs 3; `evolve` unlocks, records and re-keys the item only when `to` has none; a corrupt file recovers blank without an engine error; a round-trip save and load |
| **1.4 GrowthTracker** | `game/characters/evolution/GrowthTracker.gd`; mount in `GameWorldManager` beside `_setup_item_system` | Unit test on pure `compute_awards` (win, loss, dead unit, KO cap). Integration: a small map win, then the ledger grew for the survivor only. Gated off under `MatchLoadouts.is_active()`, the arena and `ReplayPlayback.is_playing()` |
| **1.5 Character Select** | `menus/CharacterSelect.gd`: `_build_roster` filters locked evolved forms (solo); detail-pane growth gems, stage badge, EVOLVE button; refresh after evolving | Pure helper `pickable_ids(all_ids, ledger_unlocked, hide_locked)` unit-tested; a boss is still excluded; `undead` is still excluded |
| **1.6 EvolutionScreen** | `game/ui/evolution/EvolutionScreen.gd` (overlay CanvasLayer, `UnitPreview3D`, stat diff, new move/ability cards, Evolve / Not now) | Headless test: `open()` then confirm calls `RosterLedger.evolve` and emits `finished(true, edge)`; cancel leaves the ledger untouched; animations-off path finishes |
| **1.7 Results line** | `GameOverScreen._populate_rewards`: growth rows from `GrowthTracker.growth_this_battle()` | The existing GameOverScreen test pattern: the rows render from a seeded static list |
| **1.8 Compendium line** | `CompendiumData.unit_entry` Evolution block + Rules → Evolution entry | `test_compendium`: the tree_grunt entry links `units:oakheart` and vice versa |

**M1 done when:** you can win 3 solo battles with Barkling, press Evolve, see the Evolution
screen, and field Oakheart (item carried) in the next skirmish. The full GUT suite stays green,
and the facing render shows Oakheart facing +Z.

### M2 — Runtime form swap: in-battle evolution machinery

| Task | Files | Tests |
|---|---|---|
| 2.1 `Unit.apply_form` | `tile_objects/units/unit.gd`; `AbilitySystem.replace_character_abilities` | `tests/integration/test_apply_form.gd`: +5 HP item survives (delta rule); KEEP_RATIO/KEEP_DAMAGE/FULL_HEAL; shared-move cooldown carries; status carries; granted ability survives; footprint change refused with a reason and no engine error; the model rebuilt with the new yaw and scale |
| 2.2 `EvolveEffect`, `BattleKillsAtLeastCondition`, `GameEvents.unit_evolved` | `game/combat/effects/EvolveEffect.gd`, `game/abilities/BattleKillsAtLeastCondition.gd` | Effect refusals (`not_allowed_in_battle`, `mode_forbids`); an ability ON_KILL evolves exactly once |
| 2.3 Determinism | `NetGameRules.state_digest` form column; `ReplayRecorder.board_state_rows` conditional `form`; `BattleSnapshot` `form_chain` + restore order | Old replay fixtures still verify; replay of a battle with an evolution re-simulates to the same checksums; save → resume round-trip of an evolved unit has identical stats; a two-peer lockstep test (existing net harness) with an evolving move |
| 2.4 Element parity | none (tests only) | Evolve nature→fire mid-fight: `DamageMath.preview == apply` (extend `test_element_preview_parity`) |
| 2.5 Presentation | `game/ui/hud/EvolutionCutIn.gd`, HUD refresh on `unit_evolved`, BattleLog, FloatingCombatText | Cut-in always emits `finished` (awaited-caller rule); headless no-op |
| 2.6 AI + mode knob | BotController scoring; `allow_battle_evolution` on Siege/Arena rulesets | The AI uses an evolve move when healthy; the knob blocks it |
| 2.7 First content (pick per Q4) | e.g. Eldroot phase change at 50% HP, or a Barkling "Take Root" awakening | Content test |

### M3 — Catalysts, branching, skins, arena, tiers, achievements

- `ItemResource.Kind { EQUIPMENT, CATALYST }`. Catalysts are never equippable, never applied by
  `ItemSystem`, and are rejected by the `MatchLoadouts` whitelist. They get a drop-table weight.
  Add `CatalystTrigger`, a bag row in Character Select, and the **Cinderbark** branch (fire;
  recolour placeholder, then a sculpt).
- Branch choice cards on the Evolution screen.
- Arena `EvolveAugmentEffect` (rewrites `ArenaUnitState.character_id`).
- `carry_tint_skin` plus the `MatchLoadouts.skin_for` / `normalise` ancestor rule.
- `ModeTuning max_form_stage` enforced in Character Select and the Versus lobby.
- Achievements `first_evolution` ("Late Bloomer") and `full_line`, with a retroactive read of
  `user://roster.json` in `PlayerProfile._build_achievement_context`.

### M4 — Story integration (with OVERWORLD / DUEL)

- Party of member uids, recruit-created members (`"line#n"`) and nicknames.
- `StoryFlagTrigger`, the overworld `evolve_member` event action and the post-encounter
  evolution chain.
- `PERMANENT` in-battle evolutions committed after story battles.
- Duel: `apply_form` contract, growth from duels, and Mega-style duel evolution if DUEL wants it.

---

## 9. Testing strategy (summary)

- **Pure unit tests** (no tree, no disk; `tests/README.md`): `EvolutionLibrary`, triggers,
  `compute_awards`, `pickable_ids`, ledger logic via `set_save_path` + `reset()`.
- **Content gates:** `EvolutionLibrary.validate()` over shipped content, the budget ratio, and
  `test_compendium` coverage of every form.
- **Integration:** `apply_form` on a real unit (items, statuses, abilities, cooldowns);
  `GrowthTracker` on a tiny map; Evolution screen confirm and cancel.
- **Determinism:** snapshot round-trip; replay fixture unchanged and a replay with an evolution;
  net digest includes the form; the multiprocess net check with an evolving move
  (`dev_scripts/net_multiprocess_check.sh`).
- **Visual:** `dev_scripts/render_unit_facing.gd` includes new forms, and the Evolution
  screen gets a screenshot pass in `docs/screenshots/evolution/`.

---

## 10. Open questions for you (most important first, with my default)

1. **Is evolving an unlock or a replacement?** In open modes (Skirmish, Challenge), do both
   Barkling and Oakheart stay pickable, or does your Barkling *become* Oakheart?
   **Default:** unlock in open modes and replacement in the story party. The same ledger
   serves both.
2. **Levels, or growth only?** Should units gain per-level stat growth (FE/Pokémon), or is
   "Growth" purely the evolution meter, with stats coming only from the form?
   **Default:** growth only, which keeps versus balance and determinism simple. Revisit with
   the overworld.
3. **Pacing:** how many wins to the first evolution, and do KOs count?
   **Default:** 3 won battles surviving, KOs off (`evolution_rules.tres`, easy to retune).
4. **In-battle evolution scope:** who gets it first?
   **Default:** boss phase changes (for example, Eldroot at 50% HP) plus at most one signature
   player "awakening" line. Not universal.
5. **Versus fairness:** are evolved forms freely pickable in network versus, or only if you
   unlocked them, or capped by a format stage limit?
   **Default:** all forms available in versus (no grind for PvP), with an optional
   `max_form_stage` format knob.
6. **Art direction for forms:** a new Blender sculpt per evolved form, or scaled/recoloured
   continuations for cheaper lines?
   **Default:** a real sculpt for every stage-2 form (Oakheart first), with the scaled
   placeholder in the meantime.
   *(Also yours to decide: single-element forms stay. Dual types would need a `DamageMath`
   change and are out of scope unless you want them.)*
