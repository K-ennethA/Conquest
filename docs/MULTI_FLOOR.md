# Multi-floor maps (Option B) — core

Status: **core implemented** (data model, loading, movement, targeting/LOS, height
advantage, AI, tests). **Next phase** (not done here): cursor floor-cycling, camera,
cutaway/fade of upper floors, floor HUD indicator, Map Maker editor UI, showcase maps,
step-by-step path walking/arrows.

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
- Links: `CombatServices.register_link(l)` for each `map.get_links()`, plus a simple
  ramp marker under `Tiles/Links` (placeholder art).
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

## 8. UI keep-alive (minimal, next phase owns the real UX)

- Mouse picking ray-marches floors top-down and returns the **top-most** tile's grid coord
  (`Vector3(col, floor, row)`); the cursor bracket sits on that floor. Keyboard movement
  stays on the cursor's current floor.
- Movement/attack/AOE overlays are raised to the cell's floor (grid coords carry the floor).
- `UnitActionsPanel` sweeps every floor for legal aim cells.

## 9. Known gaps / next phase

- No floor cycling: a cell *under* a bridge can only be picked by keyboard (mouse picks the deck).
- No cutaway/fade: units under a bridge are visually hidden by the deck.
- Map Maker / map_creator addon still edit floor 0 only; showcase maps not built.
- Units teleport+glide to the destination; walk the `path_to()` route for stairs animation.
- AI stand-cell tie-break uses `Cells.distance`, not exact path cost.
- Traveling hazards and knockback stay on their floor; knockback never pushes into air.
- `NetProtocol` still documents `to: Vector2i` — serialize cells with `Cells.to_array` /
  `Cells.from_variant`.
