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
   never deepen the effect.
   → `game/combat/status/StatModifierStatus.gd`, pinned by `tests/unit/test_rubble_slow_status.gd`

7. **Shared materials, profiles and table entries are DUPLICATED before mutation.** They are
   loaded once and handed to every unit, so mutating in place recolours the whole roster.
   → `game/visuals/UnitVisualManager.gd` (`base_material.duplicate()`),
   `game/ui/theme/StatusVisuals.gd`

8. **Untrusted JSON goes through the strict importers; never `ResourceLoader`.** A downloaded
   `.tres` is an arbitrary-code-execution vector — validate the blob, then re-export the
   *validated resource* as inert JSON.
   → `game/community/CommunityClient.gd`, `game/challenge/ChallengeCodec.gd`

Testing conventions (orphans, global state, temp paths, shared doubles) live in
[tests/README.md](tests/README.md).
