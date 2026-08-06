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

5. **`GameEvents.unit_moved` carries GRID cells, not world positions.** Emit
   `(unit, from_cell, to_cell)` as `Vector2i`; listeners assume cell space and silently
   mis-highlight if handed metres.
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
