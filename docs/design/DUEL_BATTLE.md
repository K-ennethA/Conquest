# Duel Battle — design (feature 3b)

A Pokémon/JRPG-style battle: two units face each other on a small 3D stage. There is no grid
movement, just turns. Each turn a unit uses one of its moves. Duels launch from overworld
encounters (the OVERWORLD agent's design) and can also be picked from the Solo menu.

> **In one line:** a duel is **a tactical battle on a two-cell board where everything is in
> reach**. The combat core runs unchanged, including MoveExecutor, DamageMath, ElementChart,
> statuses, abilities, weather, MovesetController and the per-turn ticks. The duel adds four
> pieces:
> - a board that declares "everything is in reach",
> - a compiler that adapts position-dependent moves,
> - a speed-ordered turn system,
> - its own stage, camera and HUD.
>
> No second copy of any combat rule is written.

All paths are relative to the repo root (`Conquest-reconcile`, branch `reconcile/cloud-merge`).

---

## 1. What exists today (and must not break)

### 1.1 The combat core the duel reuses unchanged

| System | Path | What the duel relies on |
|---|---|---|
| Move model | `game/combat/MoveResource.gd`, `TargetingPattern.gd`, `CombatTypes.gd` | Targeting and effects; alt-mode moves (`targeting_for`/`effects_for`, e.g. Prism Bulwark); `is_ultimate_move(move, slot)` (slot 3 = ultimate) |
| Resolution | `game/combat/MoveExecutor.gd` (`execute(move, caster, board, aim, rng)`), `MoveContext.gd` | Validation, AoE expansion, one hit/crit roll per target, injected seedable RNG |
| Forecast = hit | `game/combat/DamageMath.gd` (`preview`, `apply_scales`), `MoveExecutor.preview_vs` | CONQUEST rule 9. The duel HUD and AI must read these, never re-derive damage. |
| Elements | `game/combat/ElementChart.gd`, `resources/element_chart.tres` | Matchups are data (self-resist 0.75, opposites 1.25) |
| Effects | `game/combat/effects/*.gd` (20 types) | Audited per type in §3.3 |
| Statuses | `game/combat/status/*` (`StatusController.tick_all(board)`) | braced, guarded, flinched (stun), poisoned (stacks), prism_guard, … |
| Abilities | `game/abilities/*` (`AbilitySystem.trigger(trigger, unit, board)`) | ON_TURN_START / ON_ATTACK / ON_DAMAGED / ON_KILL / ON_DEATH / ON_BATTLE_START, passive modifiers |
| Cooldowns | `game/combat/MovesetController.gd` (`can_use`, `on_used`, `tick_cooldowns`, `snapshot_state`) | Per-move cooldowns and charges |
| Per-turn ticks | `systems/turn_system_base.gd` `_tick_unit_turn_start` (line ~363) | Weather advance, stun/control latch, stat-mod expiry, cooldown tick, status tick, weather turn-start rules, ON_TURN_START. **Board-gated:** these do nothing when `CombatServices.board()` is null. |
| Speed order | `systems/speed_first_turn_system.gd` | Per-unit turns sorted by current speed. The tie-break compares display names, which is unstable for mirror matches. |
| The board seam | `game/combat/CombatServices.gd` (autoload, `board() -> BoardAdapter`, `rebuild(map_root)`, `register_tile`, `match_rng`, `weather`), `BoardAdapter.gd` (cell = f(world position)) | The duel installs its own board here |
| Commands / RNG | `systems/net/CommandApplier.gd` (`apply_command`), `NetGameRules.gd` (USE_MOVE → `perform_move` + `_book_move_use`), `MatchRng.gd`, `NetCommitReveal.gd` | One deterministic apply path |
| Units | `tile_objects/units/unit.gd` (`perform_move(slot, aim, board, rng)`, `set_facing`), `game/characters/CharacterUnit.tscn` | Set `character_resource` before `add_child` and `_ready` builds UnitStats, MovesetController, StatusController and AbilitySystem. `tests/integration/test_status_tick_lifecycle.gd:140-162` already builds a map-less board this way. |

### 1.2 Presentation the duel reuses (all driven by GameEvents, none needs GameWorldManager)

| Piece | Path | Duel use |
|---|---|---|
| UnitAnimator (autoload) | `game/visuals/UnitAnimator.gd` | `move_performed` → attack clip or lunge; `damage_dealt` → hit; `unit_eliminated` → death; `play_clip(unit, base)` |
| MoveFXDispatcher | `game/visuals/MoveFXDispatcher.gd` (+ `MoveFXResource`) | Draws at `GRID.calculate_map_position(cell)`, so **units must stand at real Grid cell centres** |
| ImpactFX | mounted by `GameWorldManager._setup_impact_fx` | Sparks borrowed by MoveFX |
| FloatingCombatText | `game/visuals/FloatingCombatText.gd` | Works with any Camera3D; `track_unit(unit)` |
| UltimateCutIn | `game/ui/hud/UltimateCutIn.gd` | `GameEvents.ultimate_casting` → await `finished` (as in `UnitActionsPanel._await_ultimate_cutin`) |
| BattleLog | `game/ui/hud/BattleLog.gd` | Free-floating listener; static `damage_line` / `source_text` |
| Theme factories | `ConquestTheme.hp_bar/tint_hp_bar/portrait/chip`, `GroveGem`, `ElementVisuals.make_badge/effectiveness_text`, `MoveStatVisuals.cooldown_badge/make_recharge_bar/update_recharge_bar`, `StatusVisuals.chip_text`, `ShieldVisuals.hp_text`, `MenuKit.*`, `UnitPageContent.build_move_card` | Build the duel HUD from these; do not hand-roll StyleBoxes (UI_STYLE.md) |
| WeatherChip / WeatherFX / WorldLook | `game/ui/hud/WeatherChip.gd`, `game/visuals/weather/`, `WorldLook` | Stage weather and lighting |
| AudioManager | `game/audio/AudioManager.gd` | Automatic SFX from GameEvents. Battle music only starts for scenes in `battle_scene_paths`, so the duel adds its scene there or calls `enter_battle()`. |
| InputActions | `game/ui/input/InputActions.gd` | `confirm/cancel/cursor_*/unit_info/map_menu/fast_forward/cycle_*`, `hint()` |

**Not reused:** `CameraController` (tied to board fit and panning), `UnitActionsPanel` (the
tactical state machine), `FacingController` (rest-facing rules), `BotTurnDriver` (movement
pacing), `MapLoader` (grid tile meshes).

### 1.3 Gaps found while auditing (they shape the design)

- **Solo actions bypass the seeded RNG.** `UnitActionsPanel.gd:2811` and
  `BotTurnDriver.gd:865` call `perform_move` without an RNG, so solo replays may not reproduce
  hit/crit rolls. **Every duel action goes through `CommandApplier`**, which fixes this for
  duels from day one.
- **`BotController._estimate_damage` (line ~547) re-implements damage.** It skips element,
  abilities, weather and hit chance, so it violates the spirit of rule 9. A duel is mostly
  *about* elements, so the duel AI scores with `MoveExecutor.preview_vs` instead (§5). Moving
  BotController onto `DamageMath.preview` is a separate cleanup worth doing.
- **No XP, levels, owned units or consumable items exist.** `PlayerProfile` stores
  points/ranks/skins/stats. Items (`game/items`) are passive equipment; `ItemSystem.apply_loadout_items(unit, items)` applies them without a board.
- **No generic launch/return contract exists.** Arena, Campaign and Challenge each stage state
  in their own autoload and catch results their own way. The duel defines a clean one (§8),
  and the overworld can reuse it for tactical encounters too.

---

## 2. Player experience

**Walkthrough (story mode).** Kael's party is Vineweave (lead) and Geode. Kael walks into tall
grass and the screen does a grove-leaf wipe.

1. **Intro (about 2 s).** The camera sweeps over a small forest clearing, painterly ground
   matching the overworld biome, with light drizzle because it was raining on the map. A wild
   Petalfang stands on the right and Vineweave steps in on the left. A ribbon reads "A wild
   Petalfang blocks the path!" Both units turn to face each other and idle.
2. **HUD.** The foe card is top-left: crest, name, element gem, HP bar, status chips. The
   player card is bottom-right. The bottom panel is a 2×2 grid of Vineweave's four moves. Each
   row shows an element gem, name, category glyph, power and accuracy, and a cooldown badge.
   The focused row also shows a live forecast chip: "▼ Resisted · ~11 · 95%". The right column
   has **Party / Items / Flee / Info**.
3. **Round 1.** Vineweave (speed 12) is faster than Petalfang (speed 10), so Vineweave acts
   first. The player focuses **Bramble Cleave**. The chip reads "▼ Resisted · Grass Cutter
   +50%": nature resists nature, but Vineweave's passive hunts nature foes. The forecast
   explains both, straight from `DamageMath.preview`. On confirm the camera punches in, the
   attack clip plays, the move's FX land on Petalfang, and the number floats up. Petalfang
   answers with Thorn Spit and CRIT! pops in gold.
4. **Round 2.** Vineweave's 4th move, **Strangling Roots**, is its ultimate. When it is ready
   the row glints gold. Picking it plays the **full-screen ultimate cut-in**, then roots burst
   under Petalfang. The chip "Ensnared" appears and the narration reads "Petalfang is
   ensnared!" In a duel that has no movement effect, but it keeps Petalfang "restricted" for
   predation bonuses.
5. **KO.** Petalfang's death clip plays and the outcome ribbon reads "Victory". The results
   card shows growth pips (EVOLUTION's `GrowthTracker`), then "Petalfang wants to join you!"
   (recruit offer, open question Q3). **Continue** fades back to the overworld with
   Vineweave's HP carried over.

**Standalone (testing and quick play):** *Solo → Duel* opens a small setup screen:
- pick your unit and the foe (roster carousels),
- pick a stage biome and weather,
- pick AI difficulty,
- pick the turn mode.

Then Fight. After the battle: Rematch, Change units, or Menu.

---

## 3. Core approach: reuse the tactical engine on a two-station board

### 3.1 Options

| | A. **Tiny real board** (recommended) | B. Separate `DuelEngine` calling DamageMath | C. Run GameWorld on a 1×N map, movement disabled |
|---|---|---|---|
| Idea | A `DuelBoard` (a BoardAdapter subclass) with two **stations**, installed in `CombatServices`; real `Unit` nodes; `MoveExecutor` resolves everything | A new loop: pick a move, call `DamageMath.apply_scales`, apply HP | Author a tiny map, reuse GameWorldManager and the HUD with movement off |
| Statuses, abilities, weather, shields, lifesteal, ON_ATTACK/ON_DAMAGED, alt modes, delayed bursts | **All work** unchanged (same ticks, same effects) | Every one must be re-implemented. This violates rule 9 and "one pipeline" (DESIGN_ROADMAP §2). | Work |
| FX, animations, combat text | Work (GameEvents) | Must be re-triggered by hand | Work |
| Presentation freedom (stage, camera, HUD) | Full | Full | Poor: grid tiles, board-fit camera, tactical HUD and UnitActionsPanel all come along |
| Core changes | 2 narrow seams (§3.2) | None, but a parallel engine | Many "if duel" branches inside GameWorldManager and UnitActionsPanel |
| Replay / network | Existing CommandApplier path | New command vocabulary and new digests | Existing path |

**Recommendation: A.** The combat core is already board-agnostic. It talks to a duck-typed
board (see the `MoveContext` header), and tests already run it on a map-less board. The only
real incompatibilities are *reach* and *position-dependent effects*. Each is solved once, in
one place: reach by the board, effects by a compiler.

### 3.2 The two core seams (the only edits to existing framework code)

1. **`TargetingPattern` reach hook (about 6 lines).** In `in_reach()` and `is_aim_allowed()`,
   before the range test:
   ```gdscript
   # A board may declare that distance is abstract (the duel): every aim is in reach.
   # Narrowing constraints (requires_*, aim_rule) still apply afterwards.
   if board != null and board.has_method("reach_is_unbounded") and board.reach_is_unbounded():
   	pass  # skip the range test only
   ```
   Authored `min_range`/`max_range` stay untouched. That matters because `Weather.is_ranged`
   (Desert Storm's ranged penalty) and `Elevation.range_bonus` read `max_range`. Rewriting
   ranges to 0..99 in the duel (the rejected alternative) would make every move "ranged".
   `BoardAdapter` never declares the method, so tactical play is byte-identical.
   A test pins this.
2. **`CombatServices.install_board(adapter: BoardAdapter)`.** Sets `_board` and emits
   `board_ready`. It is the sibling of `rebuild(map_root)`, which always constructs a plain
   BoardAdapter. `clear()` already tears it down.

### 3.3 `DuelBoard` (new, `game/duel/DuelBoard.gd`, `extends BoardAdapter`)

- **Stations.** Station A is `Vector3i(0,0,0)` (challenger or player) and station B is
  `Vector3i(gap,0,0)` (foe). `gap` is `DuelRuleset.station_gap` (default **4**, i.e. 8 m).
  - Units stand at real Grid cell centres, so `cell_of` (derived from world position),
    `MoveFXDispatcher` and `FloatingCombatText` all work unmodified.
  - A gap of 4 guarantees that no authored AoE aimed at the foe covers the caster's station.
    The largest in the roster is Crushing Quake, SQUARE 2.
- **Terrain.** `CombatServices.register_tile(station, stage.station_tile)` for both stations.
  - Terrain-conditioned rules then read the stage biome: tall-grass evasion
    (`TerrainStats`) applies to both sides, and a forest stage turns on Eldroot's Grovebound.
  - Every other cell is "in bounds, no tile".
- **Overrides:**
  - `reach_is_unbounded() -> true`
  - `move_unit()`: no-op (stations never change)
  - `can_fit()`: false except a unit's own station
  - `units_at()` / `all_units()`: only the *active* combatants (benched party members are
    invisible to the board)
- **Other constants.** Fog is off, so `VisionSystem.gatherable` is the identity. There is a
  single floor, so height is ×1.0. There are no walls, so LOS always holds.

### 3.4 Position audit: what every effect and rule does in a duel

`DuelMoveCompiler` (new) turns each unit's authored moveset into its **duel moveset** when the
duel starts.
- **Rule 7:** it works on a private shallow copy of the `CharacterResource` and deep
  duplicates of the moves, following the `game/arena/effects/MoveModEffect.gd` precedent.
- **Data-driven:** the policy table is data on `DuelRuleset`, keyed by effect class name.
- **Per-move override:** a move may author `@export var duel_variant: MoveResource` on
  `MoveResource`. When set, the variant is used as-is.
- **Aim:** the compiler also fixes the aim. ENEMY/ANY/TILE moves aim at the **foe's station**
  and SELF moves at the **caster's station**. The HUD never asks the player for a cell.

| Feature / effect | Duel policy | Roster moves affected |
|---|---|---|
| `DamageEffect` (incl. lifesteal, `StackConsumeDamageEffect`) | **Keep** | most |
| AoE shapes SINGLE/CROSS/SQUARE/DIAMOND/LINE/ARC | **Keep.** Every shape contains the aim cell, so it hits the one foe once. (In future doubles: "spread" = hits all foes.) | Bramble Cleave, Umbral Claw, Refraction Lance, Splinter Volley, Strangling Roots… |
| `group_crit_bonus_per_extra_target` | Keep. With N=1 it rolls the base crit (Splinter Volley is a bit weaker in duels; tunable via a variant). | Splinter Volley |
| Range, min-range dead zone, LOS, height, melee-across-stairs | **Neutralised** by `reach_is_unbounded` / one floor | all |
| `requires_empty_cell` / `requires_adjacent_enemy` / `aim_rule` | **Cleared** on the compiled pattern (these are landing constraints) | Spore Leap, Infesting Lunge, Voidstep |
| `HealEffect`, `ShieldEffect`, `StatModifierEffect`, `ApplyStatusEffect`, `PercentHealthLossEffect`, `DreadBrandEffect`, `InfestEffect` | **Keep** | many |
| Target kind **ALLY** (no allies in 1v1) | **Reinterpret → SELF** (`target_kind = SELF`, `affects_caster_tile = true`) | Soothing Light, Rallying Hymn |
| `KnockbackEffect` | **Drop** (no displacement; keeps the log clean) | Crushing Quake, Gale Shove |
| `LeapEffect` | **Drop**; the move becomes a plain strike | Spore Leap, Infesting Lunge (still applies Braced) |
| `DashThroughEffect` | **Convert** to a `DamageEffect` with the same power/scale/category | Shadow Dash (legacy, no roster user) |
| `VoidstepEffect` (teleport anchors) | **Exclude** (pure mobility) → needs a `duel_variant` or the slot is empty | Voidstep (Duskmaw) |
| `TileTransformEffect` | **Drop** in v1 (nobody moves onto the changed tile). v2 could keep it when the new tile's effects fire for a stationary occupant. | Ember Storm, Crushing Quake |
| `ApplyTileEffect` | **Keep** only if the tile effect fires for a *stationary* occupant (`ON_TURN_START_WHILE_OCCUPYING`, `PASSIVE_WHILE_OCCUPYING`; e.g. a field "burn" under the foe). **Exclude** ON_ENTER/ON_EXIT/`springs_on_pass` traps (nobody steps). | Scree Trap, Vine Trap → excluded |
| `DelayedBurstEffect` | **Keep.** The fuse on the caster erupts next turn on the foe's station, a telegraphed "future sight" hit. | Abyssal Maw |
| `SpawnHazardEffect` (crawling vine) | **Exclude** in v1 (it needs `HazardManager` mounted; M3 may mount it for a multi-turn telegraphed attack) | Forest Barrage |
| `SummonEffect` | **Exclude** in strict 1v1 (a third body breaks the format) | Undying Legion |
| `SetWeatherEffect` | **Keep** (weather is global; WeatherChip shows it) | Verdant Call |
| `EvolveEffect` (EVOLUTION M2: mid-battle evolution) | **Keep**; on `unit_evolved` the compiler re-runs for the new form (§8.4) | none yet |
| Status: movement-only (`entangled`, `rubble_slowed`, `void_surge` movement −2, `range_bonus` mods, canto) | Keep. **Inert** except that "restricted" still powers Thornlust and predation (`DamageMath.is_movement_restricted`). Chips render dimmed with the tooltip "No effect in duels". | Gathering Vines, Ingrained |
| Status: `immobilized` (Ensnared, Ingrained) | Keep (predation bonus only) | Strangling Roots, Grave Grasp |
| Status: `stunned` (Flinched), `invulnerable` (Guarded, Submerged), `damage_taken_scale` (Braced, Prism Guard), poison stacks | **Keep.** They map directly onto genre expectations (flinch, protect, guard, poison). | Timberfall, Voidwalk, Thornward, Prism Bulwark, Blight Burst |
| Status: `controlled` (Enthralled) | Keep. The existing forced-control drive (`_auto_resolve_control`) inverts allegiance, finds no ally to hit, and spends the turn. In 1v1, **control acts as a stun**, which is correct and needs no code. | Mycothrall (Parasitic Hold) |
| Abilities ON_MOVE / ON_TILE_ENTER | Never fire (inert) | none on roster |
| Terrain conditions (`OnTerrainCondition`, `OnTerrainTagCondition`) | Read the **station tile** (the stage biome) | Grovebound |
| ON_KILL spawners (Mortis's **Reanimate**) | **Disable** in duels: a KO ends the duel. Policy row `ability:reanimate = DISABLE`. | Mortis |
| ON_DEATH area (Deathbloom) | Keep (hits nothing at gap 4; harmless) | Blightcap |
| Facing | Set once, face to face (`unit.set_facing`); FacingController not mounted | all |
| Footprint (2×2 bosses) | Works (the station is the anchor; the stage scales the model) | Eldroot as a "boss duel" |

**Ultimate slot integrity.** The compiler re-packs slots when moves are excluded. When a move
that was the ultimate under the original slot rule ends up in another slot, the copy gets
`is_ultimate = true` so the cut-in still fires (`MoveResource.is_ultimate_move`).

**Struggle fallback.** When no compiled move is ready (all on cooldown), or a unit compiled to
zero moves, the HUD offers **Desperate Strike** (`game/duel/moves/desperate_strike.tres`):
neutral, power 8, no cooldown, accuracy 1.0. Units that compile to zero moves (e.g. Bastion,
which has a single self-guard) are flagged `duel_eligible = false` in the Solo picker.

---

## 4. Turn order, party, items, flee, capture

### 4.1 Turn model: options

| | **Sequential speed order** (recommended v1) | Simultaneous choice, resolved by priority then speed (Pokémon) | CTB timeline (FFX: speed sets frequency) |
|---|---|---|---|
| Flow | Each round both units act once, faster first; the slower chooses after seeing the result | Both choose blind; resolve in order `(priority desc, speed desc, seeded coin)` | Fast units act more often |
| Reuse | `SpeedFirstTurnSystem` as-is (per-unit ticks, stun skip, control, ON_BATTLE_START, `turn_started` for rule-2 listeners) | New `DuelTurnSystem extends TurnSystemBase` (inherits `_tick_unit_turn_start`) plus a `priority` field on MoveResource | New scheduler |
| Balance | Speed = tempo; the slower side has an information edge. Fits the cooldown-based kits, which were designed to act with information. | Mind games; guard moves need priority | Speed swings dominate |
| Network | Existing NetSession sequential intent flow | Needs commit-reveal of *choices* (a new phase) | New |

**Recommendation.**
- Ship **sequential** first as `DuelTurnSystem extends SpeedFirstTurnSystem`. It overrides the
  tie-break to a **seeded coin flip per round** (the name compare is unstable for mirror
  matches) and disables the turn timer outside PvP.
- Add **simultaneous** in M3 as `DuelRuleset.turn_mode` (open question Q1).
- Details for M3, so the implementer does not rediscover them:
  - Tick both units at round start, *before* choosing, so cooldowns and stuns are current.
  - Before each queued action resolves, check the `stunned` rule flag. If set, cancel the
    action ("Petalfang flinched!") **and remove the flinch status**. Otherwise the stun latch
    in `_tick_unit_turn_start` would also skip next round.
  - A unit KO'd before its action skips it.
  - `MoveResource.priority: int = 0`: guard moves (Thornward, Prism Bulwark's guard mode,
    Voidwalk) get +1. Tactical play ignores the field.

**Cooldown semantics** stay tactical: `tick_cooldowns` runs at the unit's own turn start, so
"cooldown 2" means usable every third turn in both modes. The HUD shows it with the existing
recharge bar.

### 4.2 Party size: options

1. **Strict 1v1.** Simplest; a KO ends the duel.
2. **Party of up to 3, KO-replacement plus voluntary switch** (switching costs the turn).
   **Recommended target.** It matches squad sizes and keeps duels short.
3. **Pokémon 6-party.** Long battles; mostly an overworld pacing question.

Implementation note for 2 and 3:
- Benched units exist as `Unit` nodes parked off-board. They are hidden, not in
  `DuelBoard.units_at`, and not registered with the turn system.
- A switch unregisters the outgoing unit, registers the incoming one (**adopt it**, rule 4),
  places it on the station, and marks it acted this round.
- Switching out clears statuses; cooldowns freeze while benched.
- The **v1 slice is strict 1v1.** Party support is M3.

### 4.3 Items, flee, capture

- **Equipment:** duel units get their loadout via `ItemSystem.apply_loadout_items` (no board
  needed), exactly as in tactical battles.
- **Consumable battle items (potions etc.)** do not exist in the codebase. They would be a new
  `ItemResource` kind plus a `USE_ITEM` command. That belongs with the overworld inventory, so
  the duel reserves the HUD slot and the command id and builds it in M3 only if the overworld
  design adds consumables.
- **Flee** (wild encounters only, `DuelRuleset.allow_flee`):
  - chance = `clamp(flee_base + (my_speed − foe_speed) × flee_per_speed + attempts × flee_per_attempt, 0.1, 1.0)`
  - Knobs live on the ruleset (rule 11). The roll is seeded (MatchRng). A failed flee costs
    the turn.
- **Capture / recruit:** open question Q3. Recommended default: **no capture action**. Instead,
  after beating a *wild* unit, roll `recruit_chance` and show a "wants to join" offer on the
  results card. The overworld/evolution side owns the party roster (§8.3).

---

## 5. Opponent AI: `DuelBrain`

- **Location:** `game/duel/DuelBrain.gd`, RefCounted, pure.
- **Input:** actor, foe, compiled moveset, board, difficulty, and an injectable RNG.
- **Output:** `{slot, aim_cell, reason, score}`, which becomes a `USE_MOVE` command
  (or `SWITCH`/`FLEE` later).

**Scoring** reads the shared forecast and never estimates damage itself (rule 9):
- **Damage move:** `f = MoveExecutor.preview_vs(move, actor, foe, board)`, then
  `EV = hit% × (damage + crit% × (crit_damage − damage))`.
  - The forecast already includes element, abilities, weather, invulnerability and hidden-ness.
  - `+lethal_bonus` if `f.lethal` and hit% ≥ 70. Prefer the most accurate lethal move.
- **Status / debuff:** a flat value per rule flag (stun > control > poison stack > stat
  debuff), times hit%.
  - **0 if the foe already has that status id**, because statuses refresh rather than stack
    (rule 6). The exception is `poisoned` below `max_stacks`.
- **Guard / self-buff:** valued when the foe's best expected hit next turn (its own
  `preview_vs` against the actor) is ≥ `guard_threshold × actor HP`, and the actor is not
  already guarded.
- **Heal:** valued by missing HP. Zero above 80% HP.
- **Cooldown economy:** a small penalty for spending a long-cooldown move on a low-value turn.
  Ultimates are held while the foe is guarded or invulnerable.

**Difficulty:**
- EASY: softmax over scores with the seeded RNG.
- NORMAL: greedy.
- HARD: greedy, plus it models the foe's best reply (1-ply lookahead on the forecast only;
  no state cloning).
- BRUTAL: HARD with an element-aware switch in M3.

**Why not `BotController.plan(actor, moveset, board, reachable=[])`?** It is the closest
existing no-movement planner, but its `_estimate_damage` ignores elements and abilities. A
duel AI that cannot see type matchups would feel broken. Reusing its *difficulty
vocabulary* (EASY..BRUTAL) and ready check (`_move_is_ready` → `MovesetController.can_use`)
is fine.

**Determinism:** only EASY draws RNG, from a stream derived from the duel seed. The chosen
command is recorded, so replays never re-run the brain.

---

## 6. Presentation

### 6.1 Stage (`game/duel/DuelStage.tscn` + `DuelStage.gd`)

```
DuelStage (Node3D)                      <- scene root; added to AudioManager.battle_scene_paths
├── Map (Node3D)                        <- units live here (names match the TurnSystemManager scan)
│   ├── Player1 / <Unit>                <- station A (0,0,0)
│   └── Player2 / <Unit>                <- station B (gap,0,0)
├── StageSet (Node3D)                   <- biome ground disc (stylized_grass shader), props (TreeBuilder), skirt
├── WorldLook, WeatherFX                <- lighting + weather (apply_weather_look)
├── DuelCamera (Camera3D)               <- fixed rig + shot list; implements impulse_shake(strength)
├── ImpactFX, MoveFXDispatcher          <- mounted like GameWorldManager._setup_impact_fx/_setup_move_fx
├── FloatingCombatText, UltimateCutIn   <- as in GameWorldManager
└── DuelHUD (CanvasLayer)
```

- **Stage data:** `DuelStageResource` has `biome_id`, `station_tile: TileResource`, `ground_palette`, `props_scene`, `weather_id`, `music`, `camera_profile`. The overworld maps its biome to a stage.
- **Units:** `CharacterUnit.tscn` with the private compiled `CharacterResource` (skin applied by
  `apply_equipped_skin`). Station A faces east `(1,0)` and B faces west `(-1,0)`
  (`unit.set_facing`). Emit `GameEvents.unit_spawned` so the idle bob starts. Hide the 3D HP
  bar (`UnitVisualManager`), since the HUD cards replace it.
- **Camera shots** (DuelCamera, tweened, scaled by battle speed / fast-forward):
  - *establishing* orbit on intro;
  - *neutral*: behind and left of A, looking toward B, so the player is near-left and the foe
    far-right (the genre's framing);
  - *cast punch-in* on the attacker for about 0.4 s, then *impact* framing on the target;
  - *ultimate*: dolly around the caster after the cut-in;
  - *KO* slow push on the fallen unit.
  - Settings → reduced motion switches every shot to hard cuts.
- **Sequence of one action:**
  1. `CommandApplier.apply_command(USE_MOVE)` runs `perform_move` and emits
     `move_aimed`/`move_performed`.
  2. UnitAnimator plays the attack clip; MoveFX draws on the station cells.
  3. `damage_dealt` triggers the hit clip, FloatingCombatText, and AudioManager SFX.
  4. The director waits for `UnitAnimator.is_any_animation_playing() == false` plus a beat,
     then hands the turn on.
  - For an ultimate, emit `GameEvents.ultimate_casting` first and await `UltimateCutIn.finished`.
- **Presentation-only:** nothing in the stage or camera reads RNG or writes state, so replays
  and network play are unaffected.

### 6.2 HUD (`game/duel/ui/DuelHUD.gd`, grove look, 1280×720 base)

| Region | Content | Built from |
|---|---|---|
| Top-left | **Foe card**: crest (team rim, element field), name ribbon, element gem, HP bar + numbers, shield, status chips, speed pip | `ConquestTheme.unit_card_box/portrait/hp_bar/tint_hp_bar`, `ShieldVisuals.hp_text`, `StatusVisuals.chip_text`, `GroveGem` |
| Bottom-right, above the panel | **Player card** (same parts plus exact HP) | same |
| Top-centre | Round ribbon, turn-order strip (two crests, speed order), WeatherChip | `ConquestTheme.title_ribbon`, `WeatherChip` |
| Bottom strip | **Command panel**: a 2×2 **move grid**. Each row: element gem, name (Cinzel), category glyph, PWR, ACC, cooldown badge + recharge bar, forecast chip vs the current foe ("▲ Effective · ~24 · 95%"). Ultimate row gets a gold crest marker and a glint when ready. Disabled rows are sunk. Right column: Party / Items / Flee / Info. | `MenuKit.option_card/accent_card`, `MoveStatVisuals.*`, `ElementVisuals.effectiveness_text/color`, `MoveExecutor.preview_vs` |
| Focus detail | `move.full_description()`, hit/crit %, damage and crit damage, "no effect in duels" notes from the compiler | `UnitPageContent.build_move_card` |
| Narration ribbon | One line per event ("Vineweave used Bramble Cleave! It's effective!"), advanced by beats | `BattleLog.damage_line/source_text` |
| Log drawer | Full BattleLog, toggled | `BattleLog.new()` |
| Results card | Outcome ribbon, per-unit growth pips (`GrowthTracker.compute_awards`), recruit offer, Continue / Rematch | `MenuKit`, `ConquestTheme` |

**Input.**
- `cursor_*` moves in the grid; `confirm` picks; `cancel` backs out of a submenu.
- `unit_info` opens the Compendium unit page overlay (`Compendium.open_overlay`) for the focused unit.
- `map_menu` opens PauseMenu (settings, forfeit).
- Hold `fast_forward` for fast animations. `cycle_next/prev` switch between Moves and Party tabs.
- Glyphs come from `InputActions.hint()`.
- **Touch:** rows are ≥ 64 px buttons (`MobileDisplay.ui_scale`, `apply_safe_area`); tap picks, long-press shows info.
- **Gamepad:** focus rings via `MenuNav`.
- While it is not the player's turn, the panel collapses to a "Foe is thinking…" ribbon, and
  input is blocked through `InputActions.gameplay_input_blocked`.

---

## 7. Determinism, replay, save, network

- **One apply path.** Every duel action is a command applied by `CommandApplier.apply_command(cmd, duel_board, {"turn_system": ts})`: human, AI, replay, and later network. `USE_MOVE` (`NetProtocol.use_move(unit_id, slot, aim)`) with `aim` = the station cell already works. `NetGameRules._apply` books the cooldown (`_book_move_use`) and marks the unit acted.
  - New actions `SWITCH` (M3), `FLEE` (M3) and `USE_ITEM` (if consumables exist) are appended
    to `NetProtocol.Action`, with `PROTOCOL_VERSION` bumped.
- **Seeding.**
  - `DuelRequest.seed` comes from the overworld's RNG (so an encounter is reproducible from a
    save) or is random for standalone.
  - `NetSession.begin_solo_match_rng()`-style: `MatchRng.rng_for(seq)` per action, also
    installed as `CombatServices.match_rng`, so ability, status and tile contexts built outside
    MoveExecutor draw from the same stream.
  - The duel-only draws (tie-break coin, flee roll, EASY AI) use separate salts so they never
    shift combat rolls.
- **Replay.**
  - Add `ReplayLog.MODE_DUEL = "duel"`. The header carries `DuelRequest.to_dict()`.
  - `ReplayRecorder` works as-is: it listens to `command_committed` and checksums on
    `turn_ended`.
  - Playback re-creates the DuelStage from the header and re-applies the commands.
  - **The header is untrusted JSON** (shared replays), so `DuelRequest.from_dict` validates
    ids against `CharacterLibrary`/`MoveLibrary` and never loads a path (rule 8).
- **Mid-duel suspend (M4).** `BattleSnapshot.capture_unit` already stores HP, shield, statuses,
  cooldowns and cell (the cell = the station). Add `context.mode = "duel"` plus the request
  dict in `BattleSaveManager`. The speed-first turn capture (`_capture_turn_state`) covers the
  queue.
  - Gap to fix while here: AbilitySystem cooldowns and the RNG position are not captured.
    Store `seq` so `rng_for(seq)` resumes.
- **Network duel (open question Q6, M5).**
  - Sequential mode rides the existing host-authoritative NetSession intent flow. The match
    config gets `mode: "duel"` and the lobby launches DuelStage instead of GameWorld.
  - Simultaneous mode needs a *choice* commit-reveal phase: each peer commits the hash of
    `(choice, nonce)` and reveals it after both commits. This reuses `NetCommitReveal`'s
    hash-chain idea.
  - Nothing in M1–M4 blocks either path.

---

## 8. Launch / return contract with the overworld and evolution

This section is aligned with the contracts OVERWORLD.md (§4.6, §7.2) and EVOLUTION.md (§6)
publish. Where they already define a type, the duel **adopts** it instead of inventing a
parallel one.

### 8.1 Entry points

- **Story (from OVERWORLD).**
  - `StoryController` calls `DuelLauncher.launch(request: BattleRequest)` (kind `"duel"`).
  - The duel feature registers its real launcher at startup:
    `DuelLauncher.register(DuelController.launch_from_story)`. This replaces the overworld's
    `DuelStub` with no overworld change.
  - At the end the duel calls **`StoryController.report_battle_result(result: BattleResult)`
    exactly once and does not change scene itself.** StoryController applies rewards, HP,
    flags and evolution checks and returns to the overworld.
- **Standalone / Versus / replays.** `DuelController.start(request: DuelRequest) -> {success, reason}` (rule 1). DuelController owns the return (DuelSetup, rematch, menu).
- **`DuelController`** (new autoload, `game/duel/DuelController.gd`) holds the active request.
  It converts a story `BattleRequest` into the duel's internal `DuelRequest`
  (`DuelRequest.from_battle_request`), changes scene to `DuelStage.tscn`, and exposes
  `is_active()`, `active_request()`, `last_result()` and `signal duel_finished(result: DuelResult)`.
  The same pattern as Arena/Campaign/Challenge: stage state in an autoload, then change scene.

### 8.2 Data in

**Story → duel** (OVERWORLD's `BattleRequest`, fields the duel consumes):

| BattleRequest field | Duel use |
|---|---|
| `seed` | Duel RNG root (§7) |
| `party[] {member_id, character_id, current_hp, item_id, growth}` | Combatants in order. The lead healthy member starts; the rest are the bench when `party_size > 1` (M3). `character_id` **is already the evolved form** (`RosterLedger.form_of`). HP starts at `current_hp` (−1 = full). The item is applied via `ItemSystem.apply_loadout_items`, **not** `ItemInventory` (per OVERWORLD). |
| `opponent {name, speaker_id, portrait, team[{character_id, strength, moves?}]}` | Foe party. `moves` = moveset override. `strength` is opaque upstream (a level or a stat scale, pending EVOLUTION Q2). The duel applies it through one function, `DuelScaling.apply(unit, strength)` (permanent stat modifiers), so the meaning can change later in one place. |
| `backdrop {area_id, tile_id, environment_preset, lighting_preset, weather}` | `DuelStageResource` lookup by `tile_id`/`area_id`. `tile_id` also becomes the **station tile** (the grass you stood in gives both sides tall-grass evasion). `WorldLook` preset; `CombatServices.configure_weather`. |
| `rules {can_flee, can_befriend, defeat_policy}` | `DuelRuleset.allow_flee`; befriend = the recruit offer (Q3). `defeat_policy` is StoryController's business. |
| `intro_scene` / `outro_scene` | Played on the duel stage through the existing StoryDialogue seam |
| `encounter_id` | Echoed in the result |

**Internal `DuelRequest`** (RefCounted, `to_dict` / strict `from_dict`, rule 8). It is what the
stage, replays and saves use:
- `kind` WILD / TRAINER / STORY / STANDALONE / VERSUS
- `player_party`, `foe_party`: `Array[DuelCombatant{member_id, character_id, moveset_override, strength, current_hp, item_ids, skin_id}]`
- `stage_id`, `station_tile_id`, `weather_id`, `ruleset_id`, `seed`, `encounter_id`
- `origin`: `"story"` or `"standalone"`, which decides who gets the result

**`DuelRuleset`** (resource; tuning via `ModeTuning`, rule 11; DuelController registers it
while armed):
- `turn_mode`, `party_size`, `allow_switch`, `allow_flee`, `allow_items`
- `station_gap = 4`
- `flee_base` / `flee_per_speed` / `flee_per_attempt`
- `struggle_move`, `ai_difficulty`, `recruit_chance`
- `effect_policies`, `ability_policies` (the §3.4 table as data)

### 8.3 Data out

**Story:** OVERWORLD's `BattleResult`, built by `DuelResultBuilder` and delivered via
`report_battle_result`:
- `encounter_id`
- `outcome`: `"victory" | "defeat" | "fled" | "befriended" | "aborted"` (`aborted` = forfeit or app quit)
- `party_after[] {member_id, current_hp, wounded}`: `wounded` = KO'd in this duel. Bench members
  who never fought keep their HP.
- `defeated[]` (character_ids), `befriended` (character_id or ""), `turns`

**Standalone:** `DuelResult` (a superset, used by the results card, replays and profile stats):
- all of the above, plus `rounds`
- per combatant: `damage_dealt`, `damage_taken`, `kos`, `moves_used{move_id: n}`
- `replay_path`

The duel records `PlayerProfile.notify_battle_result("duel", won, meta)` in both cases.
**It never writes the story save, gold, flags, inventory or the RosterLedger.**

### 8.4 Evolution and growth hooks (EVOLUTION.md §6)

- **Units are real `Unit` nodes, and damage goes through DamageMath/ElementChart**, so
  EVOLUTION's `Unit.apply_form(...)` and **`EvolveEffect` work in a duel unchanged.** The
  compiler policy for `EvolveEffect` is **KEEP**.
- **Re-compile on form change.** The duel adds one hook: on `GameEvents.unit_evolved(unit, from, to)` it re-runs `DuelMoveCompiler` for that unit's new form. The new moveset is
  duel-adapted; shared `move_id`s keep their cooldowns, as EVOLUTION specifies. The HUD card
  and move grid rebuild, and `EvolutionCutIn` plays in place of the ultimate cut-in.
- **Growth.** The results card calls the pure `GrowthTracker.compute_awards(rows, won, rules)`
  with the duel's rows (fielded, alive, member uid via `RosterLedger.member_for_character`) and
  animates the growth pips. Gates match tactical: not during replay playback, not in network
  Versus.
- **Who opens `EvolutionScreen`:**
  - **Story:** the overworld's post-battle hook does it, after `report_battle_result`. The duel
    never opens it, so there is no double prompt.
  - **Standalone:** the duel results card opens `EvolutionScreen.open(parent, uid, edges)`
    when `RosterLedger.available_evolutions(uid)` is non-empty.
- **What EVOLUTION can rely on:** `DuelCombatant.character_id` is always the member's current
  form; `strength` goes through the single `DuelScaling.apply`.

## 9. Menus

- **Solo → "Duel" card** in `SoloModeSelect._build_ui`, with a new `MatchConfigPanel.MODE_DUEL = "duel"`. It goes to a small `menus/DuelSetup.tscn` (not MatchSetup and not CharacterSelect; both are map/squad oriented). Options:
  - two roster carousels (only `duel_eligible` units),
  - stage/biome and weather,
  - AI difficulty,
  - turn mode (once M3 lands).
  It builds a `DuelRequest{kind: STANDALONE}` and calls `DuelController.start`.
- **Versus → "Duel (hotseat)"** (M2, cheap: both sides human, the HUD hands over between
  turns). **Network duel** (M5).
- **Compendium** Rules tab gains a "Duels" entry, derived from `DuelRuleset` plus the compiler
  policy table, so it stays data-driven. Unit pages show each unit's *duel moveset* and flag
  inert moves.
- Dev: `dev_scripts/duel_smoke.gd` runs AI vs AI headless and prints the log and winner.

---

## 10. Testing strategy (GUT, per tests/README.md)

| Suite | Kind | Pins |
|---|---|---|
| `test_targeting_reach_hook.gd` | unit | `BoardAdapter` never unbounded (tactical is unchanged); a mock board with `reach_is_unbounded` passes any aim; `requires_*`/`aim_rule` still narrow; `Weather.is_ranged` is still true for a max-range-4 move on a DuelBoard |
| `test_duel_move_compiler.gd` | unit | Every policy row in §3.4 using real roster `.tres`: Spore Leap → no LeapEffect and constraints cleared; Scree/Vine Trap excluded; Soothing Light → SELF; Voidstep excluded; `duel_variant` wins; ultimate flag preserved after re-pack; Bastion → ineligible; **the shared roster resources are untouched** (rule 7) |
| `test_duel_board.gd` | unit | Stations, `move_unit` no-op, `units_at` active only, station tile drives `TerrainStats` |
| `test_duel_brain.gd` | unit, mock board + real moves | Takes a lethal when available; prefers the ▲ effective move (reads `preview_vs`, not its own math); does not re-apply a refreshing status; guards under threat; EASY is seeded-reproducible |
| `test_duel_turn_order.gd` | integration | Faster acts first; `Stone Sling`'s −4 speed flips order next round; mirror-match tie-break is identical across two runs with the same seed and differs across seeds |
| **`test_duel_determinism.gd`** | integration | **The key test.** Vineweave vs Geode, seed 1234, NORMAL vs NORMAL, headless, animations off. Run to completion twice and compare the command list, per-action HP sequence, status timeline and winner: all identical. A different seed must produce a different roll sequence. Also replay the recorded commands into a fresh stage and compare `CommandApplier.hash_match_state()` per turn. |
| `test_duel_lifecycle.gd` | integration | Braced expires at the owner's next turn start; Prism Bulwark switches to alt mode after its guard; Firstward (ON_BATTLE_START) grants its ward once; cooldowns booked through the applier; Flinched skips exactly one turn; `ultimate_casting` emitted for the ultimate |
| `test_duel_controller.gd` | integration | `start()` rejects a bad request with `{success:false, reason}` and no engine error (rule 1); `finish()` emits once and returns to scene; `DuelRequest.from_dict` rejects unknown ids (rule 8) |
| `test_duel_stage_mount.gd` | integration | Stage mounts FCT/MoveFX/CutIn/HUD with zero engine errors and zero orphans; the HUD move grid shows 4 rows with the right cooldowns |

---

## 11. Phased implementation plan

### M1: Vertical slice (smallest playable)

Vineweave (nature, speed 12) vs Geode (earth, speed 8).
- **Vineweave's 4 moves are all duel-clean:** Bramble Cleave, Thornward, Splinter Volley,
  Strangling Roots (the ultimate).
- **Geode:** Prism Bulwark (alt-mode guard/release), Stone Sling (speed debuff, so it
  visibly flips turn order), and Refraction Lance (ultimate). Scree Trap is an ON_ENTER trap,
  so it gets a **`duel_variant`**, which proves that mechanism: *Scree Shower* (earth
  physical 12, target evasion −10 for 2 turns). The content name and numbers are the user's
  call; a placeholder is fine.
- Firstward and Reprisal abilities work unchanged.

| # | Task | Files | Acceptance |
|---|---|---|---|
| 1.1 | Reach hook + `install_board` | `game/combat/TargetingPattern.gd`, `game/combat/CombatServices.gd` | `test_targeting_reach_hook.gd` green; full suite unchanged |
| 1.2 | `DuelBoard` | `game/duel/DuelBoard.gd` | `test_duel_board.gd` |
| 1.3 | `DuelRuleset` + default `.tres` + `ModeTuning` registration; `DuelMoveCompiler` (policy table as data); `MoveResource.duel_variant`; `desperate_strike.tres`; Scree Shower variant | `game/duel/DuelRuleset.gd`, `game/duel/rulesets/default_duel.tres`, `game/duel/DuelMoveCompiler.gd`, `game/combat/MoveResource.gd`, `game/duel/moves/*.tres` | `test_duel_move_compiler.gd` |
| 1.4 | `DuelTurnSystem extends SpeedFirstTurnSystem` (seeded coin tie-break, timer off); wire it the way `GameWorldManager` does (PlayerManager players, `TurnSystemManager` register+activate, `Map/Player1|2` scan). Adopt units (rule 4). | `game/duel/DuelTurnSystem.gd` | `test_duel_turn_order.gd` |
| 1.5 | `DuelRequest`/`DuelCombatant`/`DuelResult` + `DuelController` autoload (standalone only) | `game/duel/*.gd`, `project.godot` | `test_duel_controller.gd` |
| 1.6 | `DuelStage` scene: units at stations, face to face, fixed neutral camera with `impulse_shake`, FX/FCT/CutIn mounts, WorldLook, plain ground disc, music hook. The action loop goes through `CommandApplier`; KO → result. | `game/duel/DuelStage.tscn/.gd`, `game/duel/DuelCamera.gd` | `test_duel_stage_mount.gd`; manual playthrough |
| 1.7 | `DuelHUD` v1: two unit cards, 2×2 move grid with gem/PWR/ACC/cooldown/forecast chip, narration ribbon, log drawer, results card (outcome only). Keyboard, gamepad and touch. | `game/duel/ui/DuelHUD.gd` (+ small row/card helpers) | Screenshot pass at 1280×720 and 375-wide; focus works on a pad |
| 1.8 | `DuelBrain` EASY + NORMAL | `game/duel/DuelBrain.gd` | `test_duel_brain.gd` |
| 1.9 | Solo menu card + minimal `DuelSetup` (pick 2 units, difficulty) | `menus/SoloModeSelect.gd`, `menus/MatchConfigPanel.gd`, `menus/DuelSetup.tscn/.gd` | Reachable from the main menu; Back works |
| 1.10 | Determinism + lifecycle tests, `dev_scripts/duel_smoke.gd` | `tests/integration/test_duel_determinism.gd`, `test_duel_lifecycle.gd` | Green; `tests/run_tests.gd` exits 0, no orphans |

### M2: Feel and polish
- Camera shot list and intro/outro.
- Biome stages from `DuelStageResource` (grass, forest, desert, cave), plus weather FX.
- Pacing with battle speed and fast-forward.
- Ultimate glint; turn-order strip; results screen polish.
- Compendium "Duels" entry and duel movesets on unit pages.
- Hotseat duel.
- Duel variants for the other excluded roster moves (Voidstep, Vine Trap, Undying Legion,
  Forest Barrage, Ingrained). About 5 small `.tres` files; list them for the user's sign-off.

### M3: Depth
- Party (≤3) with KO-replacement and switching (`SWITCH` command).
- `turn_mode = SIMULTANEOUS` + `MoveResource.priority` (flinch-consume rule, §4.1).
- Flee (`FLEE` command).
- HARD/BRUTAL brain.
- Optional: mount HazardManager to allow Forest Barrage; `TileTransformEffect` "field
  effects".
- Consumable items if the overworld adds them.

### M4: Overworld and evolution integration
- `DuelRequest` from encounters; stage/weather/biome mapping.
- HP carry-over, white-out, `encounter_id` bookkeeping.
- Register the real launcher with `DuelLauncher`; `DuelResultBuilder` → `StoryController.report_battle_result`; growth pips via `GrowthTracker.compute_awards`; standalone `EvolutionScreen` handoff; `unit_evolved` re-compile.
- Recruit offer.
- `ReplayLog.MODE_DUEL` + replay playback.
- Mid-duel suspend via BattleSnapshot (+ AbilitySystem cooldowns and RNG `seq`).

### M5: Network duel (if in scope)
- Sequential mode over NetSession (the lobby launches DuelStage).
- Simultaneous mode with choice commit-reveal.
- Digests already cover HP, statuses and cooldowns.

---

## 12. Conventions checklist (CONQUEST.md)

- **Rule 1:** `DuelController.start`, the compiler and the brain return `{success, reason}`
  and never `push_error` on handled rejections.
- **Rule 2:** per-turn logic rides the active turn system's `turn_started`/`turn_ended`
  (DuelTurnSystem is the active one).
- **Rule 4:** duel and switched-in units are adopted (owner + turn system).
- **Rule 6:** no stacking introduced; the brain respects refresh.
- **Rule 7:** private `CharacterResource` copy, deep-duplicated moves.
- **Rule 8:** `DuelRequest.from_dict` is a strict importer.
- **Rule 9:** HUD forecast and AI use `preview_vs`/`DamageMath`; no damage math in `game/duel`.
- **Rule 11:** every duel number is on `DuelRuleset`, read through `ModeTuning`.

---

## 13. Open questions for the user (most important first; each has a default)

1. **Turn model.** Sequential speed order (faster acts first, each side chooses on its turn)
   or Pokémon-style simultaneous blind choice with move priority? **Default: sequential for
   v1** (reuses Speed First and suits the cooldown kits). Add simultaneous later as a ruleset
   option if you want the genre's mind games.
2. **Party size and switching.** Strict 1v1, up to 3 with switching, or up to 6? **Default:
   field the lead plus up to 2 bench members from the (6-slot) overworld party, with
   KO-replacement and a switch that costs the turn.** Wild encounters are 1 foe. The M1 slice
   is strict 1v1.
3. **Recruiting from the overworld.** A capture action (items, HP-based chance), a
   post-victory "wants to join" offer, or story-only recruits? **Default (matches
   OVERWORLD Q5): no recruiting in v1; in M3 a post-victory "wants to join" offer for wild
   units** (`DuelRuleset.recruit_chance`, reported as `BattleResult.befriended`). No capture items.
4. **Duel variants of position-heavy moves.** Should moves like Voidstep, traps, summons and
   Ingrained get small duel-only substitutes (new `.tres`, your naming), or should units just
   fight with fewer moves (plus Desperate Strike)? **Default: author variants.** About 6 moves
   across the roster; Geode's *Scree Shower* in the slice is the first.
5. **HP between battles** (same decision as OVERWORLD Q2; the duel just follows it). Does damage carry across overworld duels until you heal at a town,
   and what happens on a loss? **Default: HP carries; statuses and cooldowns reset after each
   duel; a loss returns you to the last rest point with the party healed and no other penalty.**
6. **Networked PvP duels.** In scope? **Default: later (M5).** The design keeps it possible
   because every action is already a deterministic command.
