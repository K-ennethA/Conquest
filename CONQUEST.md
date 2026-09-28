# Conquest — Design Conventions

Living reference for the game's design rules. Keep it current; when a new convention
is decided, record it here so units, moves, and maps stay consistent.

## Units

- **Footprint:** every unit occupies **1 cell (1×1)** unless explicitly specified
  otherwise. Multi-cell units (e.g. a 2×2 boss) are the deliberate exception and must
  set their footprint on purpose.
- **Names:** a unit's name is **one word** — unless it is a **boss**, which may use a
  multi-word name/title.
  - Examples (heroes / non-boss): Vineweave, Blightcap, Petalfang, Geode, Mycothrall.
  - Examples (bosses, multi-word allowed): Eldroot the Hollow Crown.

## Unit facing

Units always face a grid direction, Fire Emblem-map style. **Purely visual**: only the
unit's `CharacterModel` child rotates (HP bar, selection, board position never do);
combat, AI and the net state digest never read it. `Unit.get_facing() -> Vector2i`
(`(0,1)` = +row / south / toward the camera, `(1,0)` = east) is the accessor a future
facing rule (flanking, back attacks) should read.

- **4-way** by default (`UnitFacing.ALLOW_DIAGONAL = false`; flip for 8-way).
- **Walking**: every step turns the unit toward that step (~0.1 s, battle speed /
  fast-forward scaled, instant with animations off); vertical-only stair steps keep
  the facing. Player, AI and network moves all walk through `UnitAnimator`.
- **Moves**: the caster turns to its aim cell; every unit in the area (enemies and
  healed / buffed allies) turns to the caster (`GameEvents.move_aimed`, fired by
  `Unit.perform_move` on every path). Held ~0.9 s, then rest facing resumes.
- **Rest facing** (board load, spawn, after any move / death / turn start, once walks
  finish): toward the **nearest enemy** by footprint center (manhattan + floor
  difference). Equally-near enemies face their combined direction; an exact diagonal
  breaks toward the enemy army's side, then the current facing (no churn), then the
  row axis. No enemies: the team's forward (its centroid toward the board center).
  Only units whose target direction changed turn.
- **Vertical**: direction ignores floors; a target directly above/below keeps the
  current facing. Multi-cell units use their footprint center.
- **Undo** of a staged move restores the pre-walk facing. Selection / hover never
  re-face anyone.
- **Models** face **+Z** (south) after `CharacterResource.model_yaw_deg`; the Blender
  pipeline exports that way (0). Check a new model with
  `dev_scripts/render_unit_facing.gd` (roster grid in every facing).

One source of truth: `Unit._facing` (the grid direction). The older yaw API
(`facing_yaw`, `set_facing_yaw`, `face_direction`, `face_cell`; 0 = north, PI = south) is
kept as a view over it -- writing a yaw snaps to the nearest cardinal direction.

Code: `game/visuals/UnitFacing.gd` (math), `game/visuals/FacingController.gd` (rules),
`UnitAnimator` (walk turns, lunge along facing). Tests: `tests/unit/test_unit_facing.gd`,
`tests/integration/test_unit_facing_live.gd`. Screenshots: `docs/screenshots/facing/`.

## Coding conventions

Each of these is a bug class that has already cost this project a debugging session. The
named file is the canonical example — read it before you write the same kind of code.

1. **Expected failures return values; they never go to the engine log.** `push_error` /
   `push_warning` is for impossible states only — GUT fails a test on any engine error, so
   logging a *handled* rejection turns every test of that path red.
   → `tile_objects/units/unit.gd` (`perform_move` → `{success, reason}`)

2. **Per-turn logic rides the ACTIVE turn system's `turn_started` / `turn_ended`.** Never
   `PlayerManager.player_turn_started` — those do not fire on AI turns, so anything wired to
   them silently stops ticking the moment the enemy is acting.
   → `game/challenge/ChallengeController.gd` (`turn_system.turn_started.connect`)

3. **A JSON-parsed plain `Array` cannot be assigned to a typed `Array[String]`.** Godot
   raises at runtime; convert element-wise through a small coercion helper instead.
   → `game/maps/resources/MapResource.gd` (`_to_string_array`)

4. **A runtime-spawned unit must be ADOPTED, never bare-spawned.** Assign its owning player
   *and* register it with the active turn system; an ownerless unit fails `are_enemies` on
   both sides, so it can neither attack nor be attacked and never gets a turn.
   → `game/maps/SpawnManager.gd` (`_adopt_spawned_unit`)

5. **`GameEvents.unit_moved` carries GRID coords, not world positions.** Emit
   `(unit, from, to)` as `Vector3(col, floor, row)` (`Cells.to_grid(cell)`; y is the floor
   INDEX, see docs/MULTI_FLOOR.md); listeners assume grid space and silently
   mis-highlight if handed metres. Gameplay cells are `Vector3i(col, row, floor)`.
   → `game/ui/panels/UnitActionsPanel.gd` (`GameEvents.unit_moved.emit`)

6. **Statuses, modifiers and damage reductions REFRESH — they never stack, sum or multiply.**
   A second source of the same id resets the timer on the one instance; two sources must
   never deepen the effect. A refresh also hands the instance to the NEW applier, so kill
   credit for what it does follows whoever topped it up last.
   → `game/combat/status/StatModifierStatus.gd`, pinned by `tests/unit/test_rubble_slow_status.gd`

   Two **deliberate exceptions**, both authored rather than accidental: `poisoned` STACKS
   (severity is the instance count, capped by `max_stacks`), and Mycothrall's `infested`
   counter is neither refreshed nor stacked while its host is already controlled — it is
   suppressed outright, and wiped when control lapses, so re-taking a host always costs two
   fresh bites. If you add a third, say so in the resource's own docs.
   → `game/combat/effects/InfestEffect.gd`, `game/combat/status/EnthralledStatus.gd`

6a. **A duration counts the AFFLICTED unit's turns, on one of two clocks — and a debuff from
   outside is in force for the victim's next N turns.** "1 turn" means two different things,
   and the old single clock (count down at the unit's turn START) could only say one of them,
   so every 1-turn debuff a foe inflicted expired at the very tick that opened the victim's
   turn — an Ensnared victim moved freely, a Flinch skipped nothing.
   - **AFFLICTION** — forced on the unit from outside: by a **hostile** unit (another owner,
     or a mind-controlled puppet) or by the **environment** (a tile: `MoveContext.environmental`).
     Counts down at the END of each of the unit's turns it was in force for; the turn it
     landed in never counts. So Ensnared (1) stops the victim's next move, Flinched (1) skips
     exactly its next turn, Sunder Guard's -8 defense (2) holds through its next two.
   - **PROTECTIVE** — the unit's own, an ally's, or nobody's (code-built rewards, a restored
     old save): counts down at the unit's turn START, exactly as before. A 1-turn Braced /
     ward / Guarded cast on your turn covers the enemy's reply and is gone as your next turn
     opens; the Abyssal Maw fuse erupts at its caster's next turn start.
   - **Tick counts never change**: tick effects fire at turn start on both clocks, and an
     N-turn poison ticks N times. Only the moment a condition *leaves* moves.
   - The rule is `StatusCondition.is_affliction_from` — ONE function, shared by statuses and
     **timed stat modifiers** (`StatModifierEffect` → `UnitStats.set_modifier_clock`), so a
     debuff status and a debuff modifier can never disagree. A status may pin its clock with
     the authored `clock` field when the timing is its contract whoever applies it (the maw
     fuse pins PROTECTIVE); leave it `AUTO` otherwise. The clock is resolved when the status
     lands and re-resolved on every refresh (the new applier owns it, as in rule 6).
   - Both halves ride the active turn system's per-unit hooks (`_tick_unit_turn_start` /
     `_tick_unit_turn_end`, rule 2): deterministic, no RNG, identical in Traditional (a whole
     side opens/closes), Speed First (one unit) and replays. A turn start counts any earlier
     turn whose end never arrived, so a missed end beat can delay an expiry but never strand
     one. The stun / control latches in `turn_system_base.gd` still sample at turn start:
     that is what makes a PROTECTIVE-clock stun skip anything, and what stops a stun landing
     mid-turn from cutting the current turn short.
   → `game/combat/status/StatusCondition.gd` (`Clock`, `is_affliction_from`),
   `game/combat/status/StatusController.gd` (`tick_all` / `tick_turn_end`), pinned by
   `tests/unit/test_status_clock.gd` and `tests/integration/test_status_clock_live.gd`

7. **Shared materials, profiles and table entries are DUPLICATED before mutation.** They are
   loaded once and handed to every unit, so mutating in place recolours the whole roster.
   → `game/visuals/UnitVisualManager.gd` (`base_material.duplicate()`),
   `game/ui/theme/StatusVisuals.gd`

8. **Untrusted JSON goes through the strict importers; never `ResourceLoader`.** A downloaded
   `.tres` is an arbitrary-code-execution vector — validate the blob, then re-export the
   *validated resource* as inert JSON.
   → `game/community/CommunityClient.gd`, `game/challenge/ChallengeCodec.gd`

9. **Element matchups live in `element_chart.tres`, and preview shares ONE function with
   the live hit.** Every matchup number is data in
   `game/combat/resources/element_chart.tres` — never a constant in code — so retuning a
   matchup is content work; an unknown or unauthored pair is **neutral (1.0)**, never an
   error, so a brand-new element can be authored without touching the framework. The
   damage the forecast shows and the damage the board applies both come from
   `DamageMath.apply_scales` / `DamageMath.preview`. Never re-implement a damage rule in a
   preview path: add it to `DamageMath` and both sides get it.
   → `game/combat/ElementChart.gd`, `game/combat/DamageMath.gd`, pinned by
   `tests/integration/test_element_preview_parity.gd`

   **TILES AND HAZARDS ARE ELEMENTED TOO, from the same file.** A tile effect's element is
   `element_chart.tres`'s `tile_elements` map, keyed on `TileEffectResource.id` — that map
   is the **single authority**, and `TileEffectResource` deliberately carries no element
   field of its own, so elementing new terrain is the same one-file content edit as
   retuning a matchup. An unmapped id is elementless and resolves neutral. Two consequences,
   both data:
   - damage a tile or a `TravelingHazard` deals is scaled by the **matrix alone**
     (`ElementChart.environment_scale_for` — a nature unit resists nature brambles ×0.75).
     The tile amplifier and the own-tile benefit are deliberately *not* folded in: they
     would count "you are standing in it" a second and third time. Tile damage reaches
     that rule by stamping its synthetic move with `ElementChart.mark_environment`;
     hazards reach it through `DamageMath.environment_damage`.
   - what a tile **gives or takes** — a stat modifier, a heal, a shield — is re-scaled for
     an occupant of the tile's own element by `ElementChart.home_effect_amount`
     (`own_tile_effect_bonus` on a benefit, `own_tile_benefit` on a penalty). A **status**
     a tile applies is never modulated: its only knob is a roll chance, and touching that
     would put an RNG draw where an authored 1.0 short-circuits one, desyncing replays.
   → `game/combat/resources/ElementChartResource.gd` (`tile_elements`),
   `game/tiles/effects/TileEffectResource.gd`, pinned by
   `tests/unit/test_tile_elements.gd` and
   `tests/integration/test_terrain_panel_elements.gd`

10. **A glowing tile hurts where you STAND; a TRAP springs where you STEP.** Every tile
    effect is landing-only by default — `ON_ENTER` fires for the cell a unit stops on, and
    walking across is free. A **trap** is the authored exception: `springs_on_pass` makes an
    effect fire on a unit merely crossing the cell, and `halts_movement` additionally ends
    that unit's move ON the trap. Both are flags a designer ticks — trap-ness is never
    inferred from an effect's payload — and the move's traversed cells come from
    `MovementResolver.path_cells`, a deterministic derivation off the same profile and board
    the reachable set was flooded with, so truncation is *resolution* (identical on every
    lockstep peer and in replays) rather than anything a command carries. The preview and
    the live walk share one function, so the ghost stands where the move ends.
    → `game/tiles/effects/TileEffectResource.gd` (`springs_on_pass` / `halts_movement`),
    `game/tiles/effects/TileEffectSystem.gd` (`preview_route` / `resolve_path`),
    `game/world/GameWorldManager.gd` (`_walk_move_path`), pinned by
    `tests/unit/test_pass_through_traps.gd`

11. **A MODE's tuning lives on that mode's RULESET RESOURCE, and the engine reads it through
    ONE surface.** Every number a game mode turns on — Siege's wave cadence, its escalating
    respawn curve, the movement it grants, how long a planted trap lives — is an `@export` on
    the mode's own ruleset (`SiegeRuleset`, `ArenaRuleset`), so retuning a mode is a `.tres`
    edit and a NEW mode gets the same knobs by authoring its own resource. Nothing in the
    engine may hold a mode's constant, and nothing in the engine may reference a mode's
    controller to find one: it asks `ModeTuning.get_int(&"knob_name", neutral)`, which
    resolves the ACTIVE mode's ruleset — the mode's controller registers itself when it arms —
    or hands back the caller's **neutral** value when no mode is armed. So a plain skirmish is
    never "the mode with its knobs at zero"; it consults no ruleset at all and behaves exactly
    as it did before the knob existed. A knob is also **declared, not required**: it is read
    only off a ruleset that actually has a property of that name, so one mode can turn on trap
    expiry while another says nothing about it.

    Anything a mode knob SCHEDULES is **frozen at the moment it is created**, never recomputed
    from the live ruleset — a respawn's wait is stamped from the death round, a placed trap's
    expiry round is stamped at cast time. That is what keeps the numbers lockstep-safe and
    stops a mid-match retune moving something already on the board. The clock they run on is
    the mode's own round counter, edge-detected off the **active turn system's** signals
    (rule 2).
    → `game/modes/ModeTuning.gd`, `game/modes/SiegeRuleset.gd`,
    `game/modes/SiegeController.gd` (`set_armed` registers, `_run_round_start` drives),
    pinned by `tests/unit/test_mode_pacing.gd` and
    `tests/integration/test_mode_pacing_live.gd`

Testing conventions (orphans, global state, temp paths, shared doubles) live in
[tests/README.md](tests/README.md).
