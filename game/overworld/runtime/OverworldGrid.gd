class_name OverworldGrid
extends RefCounted

## THE WALKABILITY RULES of an overworld area, as pure cell functions (docs/design/OVERWORLD.md
## §3.1: every rule -- collision, sight, triggers, grass -- is a cell function, testable
## headless).
##
## Built from the area's terrain [MapResource] (TileResource.is_passable, plus a short list of
## tiles that are walkable in battle but not on a stroll: water, lava) and the entities present
## under the current flags (a blocking NPC, chest or shrine occupies its cell). M1 walks floor 0;
## the data supports floors/links for M2's bridges and stairs.

## Tiles a unit can wade through in battle but a walker never enters.
const OVERWORLD_BLOCKING_TILES: Array[StringName] = [&"deep_water", &"molten_lava", &"magma_vent"]

const DIRS: Array[Vector2i] = [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
## Blocker ids of visible wild creatures (WildSpawner.BLOCKER_PREFIX).
const WILD_BLOCKER_PREFIX := "wild:"

var width: int = 0
var height: int = 0
var _tile_ids: Array[StringName] = []
var _passable: PackedByteArray = PackedByteArray()
var _blocks_sight: PackedByteArray = PackedByteArray()
## Vector3i -> entity id (String) for blocking entities.
var _blockers: Dictionary = {}


## Build from [param area]'s terrain and the entities present under [param state]. The
## player's own cell is never a blocker.
static func build(area: OverworldAreaResource, state: StoryState) -> OverworldGrid:
	var g := OverworldGrid.new()
	if area == null or area.terrain == null:
		return g
	g._build_terrain(area.terrain)
	g.rebuild_blockers(area, state)
	return g


## Terrain-only grid straight from a map (tests, tools).
static func from_map(map: MapResource) -> OverworldGrid:
	var g := OverworldGrid.new()
	if map != null:
		g._build_terrain(map)
	return g


func _build_terrain(map: MapResource) -> void:
	width = maxi(0, map.width)
	height = maxi(0, map.height)
	var n: int = width * height
	_tile_ids.resize(n)
	_passable.resize(n)
	_blocks_sight.resize(n)
	# One pass over the layout (get_tile_at_position is a linear scan per call).
	var ground: Dictionary = {}
	for e in map.tile_layout:
		if MapResource.entry_floor(e) == 0:
			ground[MapResource.entry_position(e)] = e
	for y in range(height):
		for x in range(width):
			var i: int = y * width + x
			var entry: Dictionary = ground.get(Vector2i(x, y), {"tile_type": "NORMAL", "tile_resource_path": "", "tile_id": ""})
			var res: TileResource = MapLoader.resolve_tile_resource_for_entry(entry)
			var tid: StringName = res.get_id() if res != null else StringName(String(entry.get("tile_id", "")))
			_tile_ids[i] = tid
			var passable: bool = res == null or res.is_passable
			if OVERWORLD_BLOCKING_TILES.has(tid):
				passable = false
			_passable[i] = 1 if passable else 0
			_blocks_sight[i] = 1 if (res != null and res.blocks_line_of_sight) or not passable else 0


## Re-derive the entity blockers (after a flag change: a guard stepped aside, a recruit left).
## Moved actors stand where the state says, not on their authored cell.
func rebuild_blockers(area: OverworldAreaResource, state: StoryState) -> void:
	_blockers.clear()
	if area == null:
		return
	var aid: String = String(area.area_id)
	for e in area.present_entities(state):
		if not e.is_blocking() or not e.has_actor():
			continue
		var ov: Dictionary = state.actor_override(aid, String(e.id)) if state != null else {}
		if not ov.is_empty():
			_blockers[ov.get("cell", e.cell)] = String(e.id)
			continue
		# A multi-cell blocker (a market stall, a well) blocks its whole footprint.
		for c in e.cells():
			_blockers[c] = String(e.id)


## WHERE THE HERO STARTS on an area boot: [param cell] / [param facing] (a save's location, a warp's
## arrival) when the hero can stand there; otherwise -- out of the area's bounds (an area that
## shrank since the save), impassable terrain or a blocking entity -- the area's DEFAULT ENTRY: the
## first entry point (authored order) he can stand on, with that entry's facing, exactly as a normal
## arrival. No standable entry: the nearest standable cell to the first entry (else to the area's
## middle), keeping [param facing]. Nothing standable at all: [param cell] unchanged (never a crash).
## Returns {cell: Vector3i, facing: String, moved: bool, reason: "" / "out_of_bounds" / "blocked"}.
func resolve_start(area: OverworldAreaResource, cell: Vector3i, facing: String) -> Dictionary:
	if is_walkable(cell):
		return {"cell": cell, "facing": facing, "moved": false, "reason": ""}
	var reason: String = "out_of_bounds" if not in_bounds(cell) else "blocked"
	var anchor := Vector3i(width / 2, height / 2, 0)
	var anchored: bool = false
	if area != null:
		for eid in area.entry_ids():
			var e: Dictionary = area.entry(eid)
			if e.is_empty():
				continue
			if is_walkable(e["cell"]):
				return {"cell": e["cell"], "facing": String(e["facing"]), "moved": true, "reason": reason}
			if not anchored:
				anchor = e["cell"]
				anchored = true
	# No entry is standable: the nearest standable cell (deterministic: scan order breaks ties).
	var best := Cells.INVALID
	var best_d: int = 1 << 30
	for y in range(height):
		for x in range(width):
			var c := Vector3i(x, y, 0)
			if not is_walkable(c):
				continue
			var d: int = absi(c.x - anchor.x) + absi(c.y - anchor.y)
			if d < best_d:
				best_d = d
				best = c
	if best == Cells.INVALID:
		return {"cell": cell, "facing": facing, "moved": false, "reason": reason}
	return {"cell": best, "facing": facing, "moved": true, "reason": reason}


func set_blocker(cell: Vector3i, entity_id: String) -> void:
	_blockers[cell] = entity_id


func clear_blocker(cell: Vector3i) -> void:
	_blockers.erase(cell)


## Move a blocker (an NPC walking) from one cell to another.
func move_blocker(entity_id: String, to: Vector3i) -> void:
	for c in _blockers.keys():
		if String(_blockers[c]) == entity_id:
			_blockers.erase(c)
	_blockers[to] = entity_id


func in_bounds(cell: Vector3i) -> bool:
	return cell.z == 0 and cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func _i(cell: Vector3i) -> int:
	return cell.y * width + cell.x


func tile_id_at(cell: Vector3i) -> StringName:
	return _tile_ids[_i(cell)] if in_bounds(cell) else &""


## Terrain alone lets you stand here.
func is_terrain_passable(cell: Vector3i) -> bool:
	return in_bounds(cell) and _passable[_i(cell)] == 1


func blocker_at(cell: Vector3i) -> String:
	return String(_blockers.get(cell, ""))


## Can the walker step onto [param cell]? Terrain passable and no blocking entity (except
## [param ignore_entity], for an NPC pathing through its own cell).
func is_walkable(cell: Vector3i, ignore_entity: String = "") -> bool:
	if not is_terrain_passable(cell):
		return false
	var b: String = blocker_at(cell)
	return b.is_empty() or b == ignore_entity


## Does [param cell] stop a trainer's line of sight? Impassable / LOS-blocking terrain or a
## blocking entity. A visible wild creature ([WildSpawner], blocker id "wild:...") blocks WALKING
## but not sight: a trainer looks over a creature in the grass.
func blocks_sight(cell: Vector3i) -> bool:
	if not in_bounds(cell):
		return true
	if _blocks_sight[_i(cell)] == 1:
		return true
	var b: String = blocker_at(cell)
	return not b.is_empty() and not b.begins_with(WILD_BLOCKER_PREFIX)


## Walkable orthogonal neighbours of [param cell].
func walkable_neighbours(cell: Vector3i, ignore_entity: String = "") -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for d in DIRS:
		var n := Vector3i(cell.x + d.x, cell.y + d.y, cell.z)
		if is_walkable(n, ignore_entity):
			out.append(n)
	return out
