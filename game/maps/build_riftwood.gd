extends SceneTree

## Generates "Riftwood" -- the large three-lane SIEGE (push) map -- into
## game/maps/resources/riftwood.tres.
##
## Run with:
##   godot --headless --path . -s res://game/maps/build_riftwood.gd
##
## WHY A GENERATOR RATHER THAN A HAND-PAINTED .tres. The map is 35x35 = 1225 cells and
## its ENTIRE design claim is that it is a perfect mirror: every cell, spawn point, lane
## waypoint and base cell maps onto its opposite number under a 180 degree rotation
## r(x, y) = (W-1-x, H-1-y). Hand-painting that is a guarantee of an asymmetry nobody
## notices until a ranked match is lost to it. Here the south-west half is DERIVED from
## the north-east half by r() -- symmetry is a property of the code, and
## tests/unit/test_riftwood.gd re-checks it cell by cell on the saved resource.
##
## THE SHAPE (see the module comment on _terrain_id for the exact predicates):
##
##   * two base POCKETS in opposite corners, each a 7x7 room with a walled 2x2 FOUNTAIN
##     sanctum behind the base, reachable through a single doorway;
##   * three LANES between them -- two long L-shaped edge lanes (Canopy Run along the
##     north/east rim, Root Run along the west/south rim) and one short diagonal
##     (the Riftway) straight through the middle;
##   * a SACRED MEADOW at every lane's midpoint;
##   * TALL GRASS down each lane's jungle-facing edge, as ambush cover;
##   * an impassable jungle of TREES with STONE banks along the Riftway, shaping all three
##     lanes, cut by two mirrored jungle CORRIDORS that link a side lane to mid;
##   * a dormant NEUTRAL CAMP of two creatures sitting in each corridor;
##   * ENDLESS creep portals on all six lane heads, and lanes/base_cells authored on the
##     resource so the mode can read the routes without re-deriving them.

const MAP_PATH := "res://game/maps/resources/riftwood.tres"

const W := 35
const H := 35

# --- Tile ids, paired with the coarse tile_type hint each resource declares ----
const TILE_TYPES := {
	"grass_plains": "NORMAL",
	"forest_dirt": "NORMAL",
	"tall_grass": "DIFFICULT_TERRAIN",
	"tree": "DIFFICULT_TERRAIN",
	"sacred_meadow": "SACRED_GROUND",
	"fountain": "SACRED_GROUND",
	"stone_wall": "WALL",
}
const IMPASSABLE_IDS := ["tree", "stone_wall"]
## The four orthogonal steps -- shared by the stone-bank rule and the connectivity flood.
const ORTHO: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

# --- Geometry (the north-east half; the south-west half is r() of it) ----------
## Base pocket: the 7x7 corner room.
const POCKET := 6
## The 2x2 fountain sanctum in the deepest corner, its three enclosing walls, and the
## single doorway cell that is deliberately left open.
const SANCTUM_CELLS := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
const SANCTUM_WALLS := [Vector2i(2, 0), Vector2i(2, 1), Vector2i(0, 2)]
## Where the destructible base itself stands, and the squad chairs ringing it.
const BASE_CELL := Vector2i(3, 3)
const SQUAD_CELLS := [Vector2i(2, 3), Vector2i(3, 2), Vector2i(4, 3), Vector2i(3, 4)]
const GARRISON_CELL := Vector2i(2, 2)

## Lane heads -- also the endless creep portals, and the first waypoint of each lane.
const HEAD_CANOPY := Vector2i(7, 1)
const HEAD_ROOT := Vector2i(1, 7)
const HEAD_RIFT := Vector2i(7, 7)

## The sacred meadow at the Canopy Run's elbow (its midpoint). Root Run gets r() of it.
const MEADOW_CANOPY := [
	Vector2i(33, 0), Vector2i(32, 1), Vector2i(33, 1), Vector2i(34, 1), Vector2i(33, 2),
]

## The north-east jungle corridor, and the two dormant creatures camped in it.
const CAMP_CELLS := [Vector2i(24, 10), Vector2i(24, 13)]

# --- Actors -------------------------------------------------------------------
const BASE_ID := "bastion"
## What an endless portal pours down its lane.
const CREEP_ID := "tree_grunt"
## The garrison a base regrows every few turns.
const GUARD_ID := "gem_knight"
## The neutral camp creature (the same one the Arena's camps field).
const CAMP_ID := "petalfang"
## Slot the neutral faction always occupies -- mirrors PlayerManager.NEUTRAL_PLAYER_INDEX.
const NEUTRAL_SLOT := 2

## Placeholder squad, overwritten per player at match setup (MapLoader._load_units).
const SQUAD_IDS := ["vineweave", "gem_knight", "petalfang", "blightcap"]

## LANE WAYPOINTS, ordered from player 0's side toward player 1's (MapResource.lanes).
const LANE_CANOPY := [
	Vector2i(7, 1), Vector2i(15, 1), Vector2i(24, 1), Vector2i(33, 1),
	Vector2i(33, 10), Vector2i(33, 19), Vector2i(33, 27),
]
const LANE_ROOT := [
	Vector2i(1, 7), Vector2i(1, 15), Vector2i(1, 24), Vector2i(1, 33),
	Vector2i(10, 33), Vector2i(19, 33), Vector2i(27, 33),
]
const LANE_RIFT := [
	Vector2i(7, 7), Vector2i(12, 12), Vector2i(17, 17), Vector2i(22, 22), Vector2i(27, 27),
]


func _initialize() -> void:
	var res := MapResource.new()
	res.map_name = "Riftwood"
	res.description = "A 35x35 forest siege. Two fortress-roots sit in opposite corners, each with a walled fountain spring at its back, and three lanes run between them: the Canopy Run along the north and east rim, the Root Run along the west and south, and the short Riftway straight through the middle. Everything between them is impassable wood and stone, cut by two jungle corridors where a pair of wild things sleeps. Creeps never stop coming down any of the three. The map is a true 180-degree mirror -- every cell on one side has its twin on the other."
	res.author = "System"
	res.version = "1.0"
	res.status = "Active"
	res.width = W
	res.height = H
	res.max_players = 3       # the neutral camps live on slot 2
	res.recommended_players = 2
	res.difficulty = "Normal"
	res.map_type = "Skirmish"
	res.environment_preset = "Forest"
	res.lighting_preset = "Day"
	res.background_color = Color(0.12, 0.16, 0.12, 1.0)
	res.turn_limit = 0
	# Typed locals: a plain Array literal cannot be assigned to an Array[String] property.
	# A siege is won by TAKING the enemy fortress, not by flattening it: a hero of yours has
	# to stand on their base cell and still be standing there when its next turn comes round
	# (see [CaptureBase]). "Capture Enemy Base" is the string WinConditionLibrary compiles
	# into that objective, and it is also one of the two things that arm the Siege runtime --
	# the other being the lanes + base cells declared below.
	var objectives: Array[String] = ["Capture Enemy Base"]
	res.victory_conditions = objectives
	var rules: Array[String] = []
	res.special_rules = rules
	var map_tags: Array[String] = ["siege", "push", "three-lane", "neutrals", "large"]
	res.tags = map_tags
	res.creation_date = "2026-08-04T00:00:00"
	res.last_modified = "2026-08-04T00:00:00"

	_paint(res)
	_place_actors(res)
	_declare_geometry(res)

	if ResourceSaver.save(res, MAP_PATH) != OK:
		push_error("[build_riftwood] Failed to save %s" % MAP_PATH)
		quit(1)
		return
	print("[build_riftwood] Saved %s" % MAP_PATH)
	quit(0 if _validate() else 1)


## The 180-degree rotation that IS this map's symmetry. Player 0's corner maps onto
## player 1's, the Canopy Run onto the Root Run, and the Riftway onto itself reversed.
static func mirror(cell: Vector2i) -> Vector2i:
	return Vector2i(W - 1 - cell.x, H - 1 - cell.y)


# --- Terrain ------------------------------------------------------------------

func _paint(res: MapResource) -> void:
	res.tile_layout.clear()
	for y in range(H):
		for x in range(W):
			var cell := Vector2i(x, y)
			var tile_id: String = _terrain_id(cell)
			res.set_tile_at_position(cell, String(TILE_TYPES[tile_id]), "", tile_id)


## The tile id for one cell. Every predicate below is written for the NORTH-WEST corner /
## north-east half and applied to the far side through [method mirror], so the two halves
## cannot drift.
##
## Resolution order, highest priority first:
##   1. BASE POCKET   -- the 7x7 corner room: fountain sanctum, its walls, else plain grass.
##   2. THE RIFTWAY   -- the |x - y| <= 1 diagonal band: meadow at the map's centre,
##                       tall grass on its two edge diagonals, grass down the middle.
##   3. THE EDGE LANES-- each an L three cells wide: meadow at the elbow (the lane's
##                       midpoint), tall grass on the JUNGLE-facing edge only, else grass.
##   4. JUNGLE CORRIDOR -- dirt, with tall-grass brush around the camp.
##   5. JUNGLE        -- stone banks where it meets the Riftway, trees everywhere else.
func _terrain_id(cell: Vector2i) -> String:
	var mirrored := mirror(cell)

	# 1. Base pockets.
	if _in_pocket(cell) or _in_pocket(mirrored):
		var local := cell if _in_pocket(cell) else mirrored
		if local in SANCTUM_CELLS:
			return "fountain"
		if local in SANCTUM_WALLS:
			return "tree"
		return "grass_plains"

	# 2. The Riftway (mid), self-mirroring.
	if _in_rift(cell):
		if cell.x >= 16 and cell.x <= 18:
			return "sacred_meadow"
		return "tall_grass" if absi(cell.x - cell.y) == 1 else "grass_plains"

	# 3. The two edge lanes.
	if _in_canopy(cell):
		return _canopy_tile(cell)
	if _in_canopy(mirrored):
		return _canopy_tile(mirrored)

	# 4. The two jungle corridors.
	if _in_corridor(cell) or _in_corridor(mirrored):
		var local := cell if _in_corridor(cell) else mirrored
		for camp in CAMP_CELLS:
			if maxi(absi(local.x - camp.x), absi(local.y - camp.y)) <= 1:
				return "tall_grass"
		return "forest_dirt"

	# 5. Jungle. Stone banks the Riftway; wood fills the rest.
	for offset in ORTHO:
		if _in_rift(cell + offset):
			return "stone_wall"
	return "tree"


## Player 0's 7x7 base pocket.
func _in_pocket(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x <= POCKET and cell.y >= 0 and cell.y <= POCKET


## The Riftway: a three-wide diagonal band between the two pockets.
func _in_rift(cell: Vector2i) -> bool:
	if cell.x < 6 or cell.x > 28 or cell.y < 6 or cell.y > 28:
		return false
	return absi(cell.x - cell.y) <= 1


## The Canopy Run: three cells wide along the north rim, then down the east rim.
func _in_canopy(cell: Vector2i) -> bool:
	if cell.y >= 0 and cell.y <= 2 and cell.x >= 7:
		return true
	return cell.x >= 32 and cell.y <= 27


## Canopy Run terrain: meadow at the elbow, tall grass on the jungle-facing edge (the
## SOUTH row of the north arm, the WEST column of the east arm), grass elsewhere.
func _canopy_tile(cell: Vector2i) -> String:
	if cell in MEADOW_CANOPY:
		return "sacred_meadow"
	if cell.y == 2 or cell.x == 32:
		return "tall_grass"
	return "grass_plains"


## The north-east jungle corridor: a trunk dropping from the Canopy Run and a spur
## reaching west to the Riftway, with the camp sitting on the trunk.
func _in_corridor(cell: Vector2i) -> bool:
	if cell.x >= 23 and cell.x <= 25 and cell.y >= 3 and cell.y <= 19:
		return true
	return cell.x >= 22 and cell.x <= 25 and cell.y >= 19 and cell.y <= 21


# --- Actors -------------------------------------------------------------------

func _place_actors(res: MapResource) -> void:
	res.unit_spawns.clear()

	for player_id in [0, 1]:
		var flip: bool = player_id == 1

		# The destructible base. NOT a "Start" point: Start points are the squad chairs
		# Character Select fills, and a base overwritten by a squad pick would break the
		# whole mode (see MapLoader._load_units and tests/unit/test_kings_crossing.gd).
		res.set_spawn_point_at_position(_side(BASE_CELL, flip), player_id,
			MapResource.SPAWN_KIND_REINFORCEMENT, {
				"character_id": BASE_ID, "max_spawns": 1, "spawn_turn": 1,
				"ai_stance": "defensive", "aggro_range": 1, "leash_radius": 0,
			})

		# Squad chairs.
		for i in range(SQUAD_CELLS.size()):
			res.set_character_spawn_at_position(
				_side(SQUAD_CELLS[i], flip), player_id, SQUAD_IDS[i], "")

		# The base garrison, regrowing on a slow timer.
		res.set_spawn_point_at_position(_side(GARRISON_CELL, flip), player_id,
			MapResource.SPAWN_KIND_RESPAWN, {
				"character_id": GUARD_ID, "max_spawns": -1, "respawn_interval": 4,
			})

		# One endless creep portal per lane head, so a spawner that works off SPAWN POINTS
		# has them, and one that works off MapResource.lanes finds a portal on the first
		# (player 0) / last (player 1) waypoint of every lane.
		for head in [HEAD_CANOPY, HEAD_ROOT, HEAD_RIFT]:
			res.set_spawn_point_at_position(_side(head, flip), player_id,
				MapResource.SPAWN_KIND_ENDLESS, {
					"character_id": CREEP_ID, "max_spawns": -1, "respawn_interval": 3,
				})

	# The neutral camps: one pack per jungle corridor, mirrored.
	#
	# REINFORCEMENT rather than Respawn, deliberately. A dormant creature holds and does
	# nothing until it is struck (Unit.is_dormant), but MapLoader.resolve_default_ai_stance
	# FORCES "aggressive" on every Respawn / Endless point -- so authoring a camp as a
	# respawning one would silently wake it and send it down a lane. Reinforcement honours
	# the authored stance, and spawn_turn 1 still places it at map load
	# (MapResource.is_initial_spawn). It is also not a squad chair, so Character Select
	# cannot overwrite what the camp fields.
	for camp in CAMP_CELLS:
		for cell in [camp, mirror(camp)]:
			res.set_spawn_point_at_position(cell, NEUTRAL_SLOT,
				MapResource.SPAWN_KIND_REINFORCEMENT, {
					"character_id": CAMP_ID, "max_spawns": 1, "spawn_turn": 1,
					"ai_stance": "dormant", "leash_radius": 0,
				})


## [param cell] for player 0, or its mirror for player 1.
static func _side(cell: Vector2i, flip: bool) -> Vector2i:
	return mirror(cell) if flip else cell


# --- Lanes + base cells -------------------------------------------------------

func _declare_geometry(res: MapResource) -> void:
	res.lanes = []
	res.add_lane(LANE_CANOPY)
	res.add_lane(LANE_ROOT)
	res.add_lane(LANE_RIFT)
	res.base_cells = {}
	res.set_base_cell(0, BASE_CELL)
	res.set_base_cell(1, mirror(BASE_CELL))


# --- Validation ---------------------------------------------------------------

func _validate() -> bool:
	print("\n==== VALIDATION ====")
	var ok := true
	var res := load(MAP_PATH) as MapResource
	if res == null:
		push_error("[validate] reload failed")
		return false

	print("Name: %s | status=%s | %dx%d | max_players=%d" % [
		res.map_name, res.status, res.width, res.height, res.max_players])

	# Every cell painted, every id resolving.
	var composition: Dictionary = {}
	for tile in res.tile_layout:
		var tid: String = str(tile.get("tile_id", ""))
		composition[tid] = int(composition.get(tid, 0)) + 1
		if TileCatalog.find_by_id(StringName(tid)) == null:
			push_error("[validate] tile_id '%s' does not resolve" % tid)
			ok = false
	if res.tile_layout.size() != W * H:
		push_error("[validate] %d cells painted, expected %d" % [res.tile_layout.size(), W * H])
		ok = false
	print("Tiles: %s" % str(composition))

	# Mirror symmetry, cell by cell.
	var asymmetric: int = 0
	for y in range(H):
		for x in range(W):
			var a: String = str(res.get_tile_at_position(Vector2i(x, y)).get("tile_id", ""))
			var b: String = str(res.get_tile_at_position(mirror(Vector2i(x, y))).get("tile_id", ""))
			if a != b:
				asymmetric += 1
	if asymmetric > 0:
		push_error("[validate] %d cells break the 180-degree mirror" % asymmetric)
		ok = false
	print("Mirror: %d asymmetric cells" % asymmetric)

	# Every spawn on passable ground, every character resolving.
	var per_player: Dictionary = {}
	for sd in res.unit_spawns:
		var pid: int = int(sd.get("player_id", -1))
		per_player[pid] = int(per_player.get(pid, 0)) + 1
		var pos = sd.get("position", Vector2i(-1, -1))
		var tid: String = str(res.get_tile_at_position(pos).get("tile_id", ""))
		if tid in IMPASSABLE_IDS:
			push_error("[validate] spawn at %s sits on '%s'" % [str(pos), tid])
			ok = false
		var cid: String = str(sd.get("character_id", ""))
		if CharacterLibrary.get_character(cid) == null:
			push_error("[validate] character_id '%s' does not resolve" % cid)
			ok = false
	print("Spawns per player: %s" % str(per_player))

	# Walkable connectivity: everything reachable from player 0's base.
	var reachable: int = _flood(res)
	var walkable: int = 0
	for tile in res.tile_layout:
		if not (str(tile.get("tile_id", "")) in IMPASSABLE_IDS):
			walkable += 1
	print("Walkable: %d cells, %d reachable from player 0's base" % [walkable, reachable])
	if reachable != walkable:
		push_error("[validate] %d walkable cells are walled off" % (walkable - reachable))
		ok = false

	# Lanes + base cells round-trip off disk.
	print("Lanes: %d | base_cells: %s" % [res.lane_count(), str(res.base_cells)])
	if res.lane_count() != 3:
		push_error("[validate] expected 3 lanes")
		ok = false
	# The rotation maps the Canopy Run onto the Root Run and the Riftway onto itself, so a
	# lane is NOT its own mirror -- the SET of lanes is what has to be closed under it.
	for i in range(res.lane_count()):
		var lane: Array[Vector2i] = res.get_lane(i)
		print("  lane %d: %d waypoints, %s -> %s" % [
			i, lane.size(), str(res.lane_head(i, 0)), str(res.lane_head(i, 1))])
		var flipped: Array[Vector2i] = []
		for k in range(lane.size() - 1, -1, -1):
			flipped.append(mirror(lane[k]))
		var matched := false
		for j in range(res.lane_count()):
			if res.get_lane(j) == flipped:
				matched = true
		if not matched:
			push_error("[validate] lane %d's mirror image is not a lane on this map" % i)
			ok = false

	var report: Dictionary = res.validate_map(true)
	print("validate_map(strict): valid=%s issues=%s" % [
		str(report.get("valid", false)), str(report.get("issues", []))])
	if not report.get("valid", false):
		ok = false

	if not MapCatalog.is_versus_eligible(res):
		push_error("[validate] map is not versus-eligible")
		ok = false

	print("==== RESULT: %s ====" % ("PASS" if ok else "FAIL"))
	return ok


## Count the cells reachable on foot from player 0's base cell.
func _flood(res: MapResource) -> int:
	var blocked: Dictionary = {}
	for tile in res.tile_layout:
		if str(tile.get("tile_id", "")) in IMPASSABLE_IDS:
			blocked[tile.get("position", Vector2i(-1, -1))] = true
	var seen: Dictionary = {}
	var queue: Array[Vector2i] = [BASE_CELL]
	seen[BASE_CELL] = true
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for offset in ORTHO:
			var next: Vector2i = cell + offset
			if next.x < 0 or next.x >= W or next.y < 0 or next.y >= H:
				continue
			if seen.has(next) or blocked.has(next):
				continue
			seen[next] = true
			queue.append(next)
	return seen.size()
