# Multi-floor maps (Option B)

Status: **core implemented** (data model, loading, movement, targeting/LOS, height
advantage, AI, tests) and **player-facing layer implemented** (view floor + floor
cycling, cutaway, floor HUD, stairs/edge visuals, camera fit/follow, unit cycling,
multi-floor Map Maker, showcase maps -- see section 10). Still open: step-by-step path
walking/arrows (owned elsewhere), camera rotation.

Showcase maps (Active): `river_crossing.tres` (`game/maps/build_river_crossing.gd`),
`castle_siege.tres` (`game/maps/build_castle_siege.gd`). Screenshots:
`docs/screenshots/multi_floor/`.

Fixture map: `res://game/maps/resources/test_bridge_map.tres` (built by
`game/maps/build_test_bridge_map.gd`, status *Inactive*). Tests:
`tests/unit/test_multi_floor.gd`, `tests/integration/test_multi_floor_loader.gd`.

---

## 1. Coordinates

| Space | Type | Layout | Where |
|---|---|---|---|
| **Cell** (gameplay) | `Vector3i` | `(col, row, floor)` — **z = floor**, 0 = ground | BoardAdapter, CombatServices, MovementResolver, TargetingPattern, MoveContext, AI, SpawnManager, effects, `Unit.home_cell` |
| **Grid coord** (scene) | `Vector3` | `(col, floor, row)` — y is the floor *index* | `Grid`, cursor `tile_position`, all `GameEvents` cell signals, visualizers |
| **World** | `Vector3` | x = col·2+1, z = row·2+1, **y = floor · `Cells.FLOOR_HEIGHT`** | scene nodes |
| **Map data** | `Vector2i` + `floor:int` | `"position"` + optional `"floor"` | `MapResource` entries (the editor/model layer) |

Floor in `z` keeps every `.x/.y` manhattan/direction computation meaningful. Footprints
stay `Vector2i` (a span on one floor).

`game/board/Cells.gd` (`class_name Cells`, all static) is the one place for the
convention:

- `make(col,row,floor=0)`, `floor_of(c)`, `flat(c) -> Vector2i`, `lift(Vector2i, floor)`,
  `with_floor(c,f)`, `same_column(a,b)`, `less(a,b)` (stable ordering)
- `manhattan_2d(a,b)`, **`distance(a,b)` = manhattan + |floor diff|** (the range metric)
- `to_grid(c)`, `from_grid(Vector3)` — cell ↔ grid coord
- `cell_to_world(c)`, `world_to_cell(v)`, `floor_y(f)`, `floor_from_world_y(y)`
- `to_array(c)` / `from_variant(v)` / `pos2_from_variant(v)` — **serialization** (JSON, net).
  `from_variant` accepts Vector3i, Vector2i, `[c,r]`, `[c,r,f]`, `{x,y,z}`, `"(c, r, f)"`.
- `FLOOR_HEIGHT = 2.5` world units (cells are 2 wide; 2.5 gives head-room under a bridge).
  `floor_from_world_y` snaps: floor f covers `[f·H − 0.5, (f+1)·H − 0.5)`.

## 2. Map data (`MapResource`)

- Tile entries gain optional **`"floor": int`** (default 0). **(position, floor) is the
  key.** The `floor` key is only written for floors > 0, so ground entries are byte-identical
  to the old schema. Floor 0 is implicitly *full* (missing entry = default tile); an upper
  floor exists only where an entry is placed (**a gap = air**, e.g. a broken bridge).
- Optional tile key **`"stairs": "north"|"south"|"east"|"west"`** (+ optional
  `"stairs_cost"`): auto-generates a link from `(pos, f)` to the neighbouring column in that
  direction on `f + 1`.
- Spawn entries gain optional **`"floor"`** (must stand on a tile; validated).
- **`links: Array[Dictionary]`** — `{from: Vector3i, to: Vector3i, cost=1, kind="stairs",
  bidirectional=true}`. Ladders, ramps, one-way drops, tower-to-tower bridges.
- API: `get_tile_at_position(pos, floor=0)` ({} = air above ground),
  `set_tile_at_position(pos, type, path, id, floor=0)`, `remove_tile_at_position(pos, floor)`,
  `has_tile_at(pos, floor)`, `set_stairs_at_position(pos, dir, floor)`, `get_floor_count()`,
  `get_floors_at(pos)`, `get_tiles_on_floor(f)`, `add_link / remove_link`,
  **`get_links()`** (explicit + stair-generated, normalized), `get_player_spawn_cells()`,
  static `entry_position / entry_floor / entry_cell`, `normalize_link`.
- JSON: positions are written as `[c, r]`, link ends as `[c, r, f]`; import also reads the
  legacy stringified `"(c, r)"` form. Old maps load unchanged as a single floor.

## 3. Loading (`MapLoader`)

- Tiles: `Tiles/Floor_<f>/Tile_<x>_<y>_<f>` at `y = f · FLOOR_HEIGHT` — one container per
  floor so the cutaway can hide/fade a whole floor. Floor 0 is built for every column,
  upper floors only for their entries.
- Every tile registers with `CombatServices.register_tile(cell, res)` (upper-floor tiles
  register even without a resolvable resource, so they still exist for movement).
- Links: `CombatServices.register_link(l)` for each `map.get_links()`, plus a visual per
  link under `Tiles/Links` (`FloorDecor.make_link_visual`: stairs / ladder / hatch
  ladder / ramp; meta `cutaway_floor` = upper floor).
- Dressing: `FloorDecor.build_floor_decor` -> `Tiles/Decor/Floor_<f>/Decor_<x>_<y>`
  (one mesh per upper tile) + `Rubble_<x>_<y>` on the floor below a gap. All derived
  from the map data -- see section 10.
- Units spawn at `floor_y(f) + UNIT_GROUND_Y`; `configure_ai_behavior` gets the Vector3i home.
- `MapLoader.resolve_tile_resource_for_entry(entry)` (static) and
  `BoardAdapter.configure_from_map(map)` build a board **headlessly** (tools, AI sims, tests).

## 4. Board (`BoardAdapter`) — API for the next phase

| Query | Returns |
|---|---|
| `floor_count()` | number of floors (1 on classic maps) |
| `floors_at(col)` | `Array[int]` floors with a tile in a column (Vector2i or Vector3i arg) |
| `top_floor_at(col)` | highest floor with a tile (0 ground-only, −1 off-board) |
| `has_tile(cell)` | floor exists (false = air / off-board) |
| `cells_on_floor(f)` | `Array[Vector3i]` |
| `units_on_floor(f)` | live units anchored on floor f |
| `links()` / `links_from(cell)` / `are_linked(a,b)` | normalized links / outgoing edges `{to,cost,kind}` |
| `cell_to_world(c)` / `world_to_cell(v)` / `floor_world_y(f)` | coordinate conversion |
| `blocks_los_at(c)` / `is_solid_ceiling(c)` | LOS inputs |
| `set_present_cells(d)` / `set_links(a)` / `refresh_floors()` | injection (CombatServices does this in `rebuild`) |

Occupancy is per `Vector3i`: `units_at((3,1,0))` and `units_at((3,1,1))` are independent
(a unit under a bridge and one on it coexist). `move_unit` lifts/lowers the unit by whole
floors, keeping its height above its tile. The live tile node for `set_tile` is found at
`Tiles/Floor_f/Tile_x_y_f`.

`CombatServices`: `register_tile`, `register_link`, `get_links`, `tile_at(cell)`,
`tile_effects_at(cell)` — all `Vector3i`; signal `tile_effects_changed(cell: Vector3i)`.
`board_ready` fires after each rebuild (use it to (re)build floor UI).

## 5. Movement rules (`MovementResolver`)

- Stepping shapes move within the unit's floor on cells that **have a tile**, plus across
  **link edges**. A link step costs the link's `cost` (default 1) instead of terrain cost.
- **GROUND / PHASING** never enter air. Walking onto an upper floor requires a tile (a
  broken bridge's gap is impassable); no stepping off an edge.
- **FLYING**: may fly *through* air on upper floors (never stop in it) and change floor
  vertically at any column (cost = destination enter cost; 1 for air) — crosses gaps,
  hops onto ramparts without stairs.
- KNIGHT jumps stay on the floor; TELEPORT uses `Cells.distance` over every floor.
- **Paths:** after `reachable_cells()`, `path_to(dest)` → `[origin … dest]` (every step incl.
  link hops), `cost_to(dest)`, `last_costs()`. `travel_distances(origin, board, kind, cap)`
  gives unit-ignoring step distances (AI planning).
- The open list is now a binary heap (was O(n²)).

## 6. Targeting & line of sight

- **Range** = `Cells.distance` (manhattan + |Δfloor|).
- **Melee** (authored `max_range <= 1`) hits its own floor only, or the far end of a
  **link** (top/bottom of a stair) — `TargetingPattern.in_reach` / `MoveResource.can_aim_at(…, board)`.
  A unit directly above is never melee-reachable.
- **LOS** (`game/combat/LineOfSight.gd`, `TargetingPattern.line_of_sight`):
  `AUTO` (default) checks only **cross-floor** aims — same-floor results are exactly the
  pre-multi-floor ones; `ALWAYS` also checks same-floor (walls/trees block); `NEVER` skips.
  Rules: same column + different floors → blocked by any solid ceiling between; **cover**:
  a solid ceiling above the lower endpoint (up to the higher floor) blocks; otherwise the
  eye-to-eye segment is sampled — `blocks_line_of_sight` tiles in intermediate columns
  block, and crossing a floor plane where that floor has a solid tile blocks, except the
  plane the shooter / target stands on in its own column. `TileResource.solid_ceiling`
  (default true) lets see-through decks opt out. Linked melee skips LOS.
- **AOE** patterns stay on the **aim's floor**.
- **Height advantage** (`game/combat/Elevation.gd`, all constants there): attacker higher →
  +1 max range (ranged only), ×1.15 damage, +10 hit; lower → ×0.85 damage, −10 hit.
  Applied in `DamageEffect.apply`, mirrored in `MoveExecutor.preview_vs` and
  `MoveContext.hit_chance`. Exactly neutral on a shared floor.

## 7. AI

Cells are Vector3i throughout. On **multi-floor boards** the advance ("nearest hostile",
"which reachable cell gets closer") uses **walking distance** (`travel_distances`) so bots
take the stairs rather than hugging the wall below their target; single-floor boards keep
the historical Manhattan behaviour byte-for-byte. Leash / aggro / threat radii use
`Cells.distance`. Melee plans across stair links work through `can_target`.

## 8. Overlays

- Mouse picking ray-marches floors from the **view floor** down and returns the top-most
  tile's grid coord (`Vector3(col, floor, row)`).
- Movement/attack/AOE overlays are raised to the cell's floor (grid coords carry the floor).
- `UnitActionsPanel` sweeps every floor for legal aim cells.

## 9. Known gaps / next phase

- The camera never rotates (the local-fade occlusion rule assumes the camera looks
  from +row / south).
- The map_creator editor addon only has a minimal Floor field (its grid/3D preview show
  the ground); use the in-game Map Maker for real floor editing. The in-game Map Maker
  scene (`game/mapmaker/MapMakerScene.tscn`) opens from the main menu (Map Creator) and
  from the Compendium; Back returns to whichever opened it (`MapMakerScene.open_from`).
- Units walk the `path_to()` route cell by cell, stairs included (`PathArrow`,
  `UnitAnimator.walk_path`); move range / fringe / danger-zone overlays sit on each
  cell's floor.
- AI stand-cell tie-break uses `Cells.distance`, not exact path cost.
- Traveling hazards and knockback stay on their floor; knockback never pushes into air.
- `NetProtocol` still documents `to: Vector2i` — serialize cells with `Cells.to_array` /
  `Cells.from_variant`.

## 10. Player-facing layer (view floor, cutaway, HUD, camera, authoring)

**View floor** (`board/cursor/cursor.gd`, rules in `game/board/FloorNav.gd`, tested in
`tests/unit/test_floor_nav.gd`). The cursor owns `view_floor` (reset to the top floor on
every `board_ready`) and broadcasts `GameEvents.view_floor_changed(view, cut, count)`.

| Input | Effect |
|---|---|
| Arrows / d-pad | step; land on the top-most tile **at or below** the view floor (rides over bridges at the top view, drops off a bridge end, walks under it at view 0) |
| `floor_up` / `floor_down` (PgUp/PgDn, RT/LT) | next floor up/down **in the cursor's column** (view follows); on a single-floor column only the view floor moves |
| `cycle_next` / `cycle_prev` (Tab,R / Shift+Tab,Q; RB/LB) | jump to the human player's next/previous **ready** unit (reading order row, col, floor); the selection follows if a unit is selected; ignored while aiming / a tentative move is staged |
| Mouse | picks the top-most tile at or below the view floor |

`focus_cell(cell)` (cycling, turn start) snaps the view to the unit: a covered unit
lowers the view to its floor, a higher one raises it. Turn start puts the cursor on the
player's last selected unit if it can still act, else the first ready unit.

**Cut floor** = the view floor, lowered to the cursor's / selected unit's floor while
either is directly under a deck. `game/visuals/FloorCutaway.gd` ghosts every floor above
it (tiles, decor, links, the units there; their HP bars hide) by swapping in one shared
translucent material per floor and tweening its alpha (~0.18 s). It also ghosts, one cell
at a time, the few deck cells that hide the cursor / selected unit on screen (directly
above, and one row further south per floor of height). Material swapping instead of
`GeometryInstance3D.transparency` because Compatibility ignores the latter.

**HUD** (`TerrainInfoPanel`): the terrain card gains the cell's floor, its links
("Stairs ▲ Upper", "Ladder ▼ Ground (cost 2)") and "Under cover"; a floor badge above it
("Floor 2 / 3 · Upper", pips, key hint) appears on multi-floor maps only.

**Camera** (`CameraController`): board bounds read `Tiles/Floor_<f>/Tile_*`; the fit is
refined in screen space (perspective, upper floors, room for the turn banner); the focus
plane sits at the view floor's height; `follow_world_point` (called by the cursor for
keyboard / cycle / turn-start moves only, never mouse hover) keeps the cursor inside an
18 % screen margin with an eased pan.

**Dressing** (`game/maps/FloorDecor.gd`, `ProcMesh.gd`): masonry under ramparts (tile
below impassable), deck beam + piers over water, parapets (crenellated on castle walls,
plain toward `flagstones` courtyards) or timber rails (wood-ish tile ids), jagged broken
edge + rubble when the same floor continues two cells on (a one-cell gap), open edges
where a link arrives. New tiles `structures/flagstones` and `structures/wooden_planks`
(`PavedTileBuilder`).

**Map Maker** (`game/mapmaker/`): `MapMakerModel` keys tiles/spawns by Vector3i and takes
a trailing `floor_index` everywhere; `set_stairs`, `add_link/remove_link/get_links_at`,
`validate()` (spawn on air, link/stairs into missing cells, same-floor neighbour links,
unreachable decks). `MapMakerScene`: floor selector (PgUp/PgDn), floor below ghosted,
Stairs and two-click Link tools, validation list. Tests in
`tests/unit/test_mapmaker_model.gd`.
