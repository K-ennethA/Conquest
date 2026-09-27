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

Code: `game/visuals/UnitFacing.gd` (math), `game/visuals/FacingController.gd` (rules),
`UnitAnimator` (walk turns, lunge along facing). Tests: `tests/unit/test_unit_facing.gd`,
`tests/integration/test_unit_facing_live.gd`. Screenshots: `docs/screenshots/facing/`.
