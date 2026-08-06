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
##   * a CONTROL POINT at every lane's midpoint, each read as a small STONE CIRCLE (the
##     point cell plus its four orthogonal neighbours, laid in forest dirt) ringed by the
##     SACRED MEADOW heal tiles, which sit BESIDE the point rather than on it;
##   * TALL GRASS down each lane's jungle-facing edge, as ambush cover;
##   * an impassable jungle of TREES with STONE banks along the Riftway, shaping all three
##     lanes, cut by two mirrored jungle CORRIDORS that link a side lane to mid;
##   * two mirrored 1-wide TALL-GRASS TUNNELS through the wood, each linking a jungle
##     corridor to the FAR THIRD of a rim lane -- a flank rotation for whoever knows it;
##   * NEUTRAL CAMPS IN TWO TIERS, all dormant: four OUTER petalfangs deep on the corridor
##     trunks, and two INNER blightcaps holding the tunnel mouths, closer to mid;
##   * ENDLESS creep portals on all six lane heads, and lanes / base_cells / control_points
##     authored on the resource so the mode can read the geometry without re-deriving it.
##
## THE TACTICAL CHECKLIST THIS MAP EMBODIES -- the template every future Conquest map
## follows. A map is not "a shape with two spawns"; it is these five things, and each one is
## a decision a player gets to make:
##
##   1. LANES WITH DISTINCT RISK PROFILES. Never three copies of the same road. Here the two
##      rim lanes are long, safe and slow (one jungle edge each), and the Riftway is short,
##      exposed and stone-banked -- the shortcut you pay for. The shortest route between the
##      two bases must run down a LANE, never through a shortcut the map added later.
##   2. CONTESTED MIDPOINTS. Every lane has one cell worth standing on that neither side owns
##      at the start, and it reads as claimable at a glance (the stone circles). Three of
##      them, so holding all three is a real choice and holding none is a real loss.
##   3. A JUNGLE ECONOMY. Off-lane, dormant, tiered: a cheap outer camp you can clear early
##      and a tougher inner one that pays better and sits where it also denies a route. The
##      camps never block a lane (they are 7+ cells off every waypoint) -- a camp in a lane is
##      a roadblock, not an objective.
##   4. FLANK ROUTES. At least one mirrored path that is NOT the fastest way anywhere, but is
##      much the fastest way SIDEWAYS -- rotation, not advance. It must never open into a base
##      pocket or a sanctum, and it must be narrow enough (1 cell) that meeting somebody in it
##      is a commitment.
##   5. AMBUSH GRASS. Tall grass on the jungle-facing edge of every lane, in the tunnels and
##      around every camp, so there is always cover next to the thing worth fighting over.
##
## FUTURE DIRECTION (nothing here builds for it yet): elemental biome maps -- water and fire
## boards where a unit's element matters through the tile-element chart that already exists
## (`tile_elements` in game/combat/resources/element_chart.tres, CONQUEST.md rule 9).

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

# --- Control points -----------------------------------------------------------
## The three CLAIMABLE MIDPOINTS: one at the Canopy Run's elbow, one at the map's centre on
## the Riftway, and -- derived, never authored twice -- r() of the Canopy one on the Root Run.
## Each is the MIDDLE waypoint of its own lane, so "hold the midpoint" and "hold the lane"
## name the same cell.
const POINT_CANOPY := Vector2i(33, 1)
const POINT_MID := Vector2i(17, 17)

## THE STONE CIRCLE that makes a control point READ as claimable: the point cell plus its four
## orthogonal neighbours, laid in forest dirt so it is visibly not lane grass and visibly not
## meadow. Authored as explicit cells rather than derived from the point, because both circles
## have to be checked against a terrain predicate that is already resolving by cell.
const CIRCLE_CANOPY := [
	Vector2i(33, 1), Vector2i(33, 0), Vector2i(32, 1), Vector2i(34, 1), Vector2i(33, 2),
]
## The mid circle is SELF-MIRRORING (r() maps the set onto itself), which is what lets the
## board's centre carry a point at all. It also plugs the full 3-wide Riftway at y = 17, so
## the short lane cannot be walked without crossing the thing being fought over.
const CIRCLE_MID := [
	Vector2i(17, 17), Vector2i(16, 17), Vector2i(18, 17), Vector2i(17, 16), Vector2i(17, 18),
]

## The sacred meadow at the Canopy Run's elbow: the FOUR DIAGONALS of the elbow's 3x3 block,
## i.e. beside the stone circle rather than on it. Standing on the point is a commitment; the
## heal is one step away, which is the whole tension. Root Run gets r() of these.
const MEADOW_CANOPY := [
	Vector2i(32, 0), Vector2i(34, 0), Vector2i(32, 2), Vector2i(34, 2),
]

# --- Sneak route ---------------------------------------------------------------
## THE CANOPY TUNNEL: a 1-cell-wide tall-grass cut through the north-east wood, from the NE
## jungle corridor's shoulder at (25, 17) out to the Canopy Run's east arm at (32, 22) -- the
## lane's FAR THIRD, past the elbow control point. Root Run gets r() of it (the Root Tunnel),
## so each side owns the flank into the other's half of a rim lane.
##
## Three things are load-bearing about it and are re-checked in [method _validate]:
##   * it is ONE cell wide -- its only walkable neighbours are its two mouths, so meeting
##     somebody inside it is a commitment rather than a pass-by;
##   * it comes nowhere near a base POCKET or a fountain SANCTUM. The pockets are entered
##     through their lanes and the sanctums through a single doorway cell; a tunnel that
##     opened past either would delete the map's whole defensive geometry;
##   * it is not a HIGHWAY. Base-to-base is 56 steps with the tunnels open and 56 with them
##     walled off -- the shortcut it grants is SIDEWAYS (corridor -> lane far third falls
##     28 -> 12), never forwards. Tall grass is also difficult terrain, so the real movement
##     cost is above the step count; no rubble speed bump is needed on top of that.
const TUNNEL_CANOPY := [
	Vector2i(26, 17), Vector2i(27, 17), Vector2i(28, 17), Vector2i(29, 17), Vector2i(30, 17),
	Vector2i(30, 18), Vector2i(30, 19), Vector2i(30, 20), Vector2i(30, 21), Vector2i(30, 22),
	Vector2i(31, 22),
]

# --- Camps ---------------------------------------------------------------------
## THE OUTER CAMP: two dormant creatures deep on the north-east corridor's trunk, 30 steps
## from EITHER base -- neutral ground, and the early-game objective both sides can reach.
const CAMP_CELLS := [Vector2i(24, 10), Vector2i(24, 13)]
## THE INNER CAMP: one tougher dormant guardian on the corridor's mid-ward shoulder, sitting
## on the tunnel's mouth. Closer to mid than the outer camp (13 steps to the centre point
## against 17 and 20) and NOT equidistant -- 23 steps from player 1's base against 37 from
## player 0's, so each side has a nearer inner camp and r() hands the other side its twin.
## Clearing it opens the flank tunnel; because it is dormant you may also simply creep past.
const INNER_CAMP_CELLS := [Vector2i(24, 17)]

# --- Actors -------------------------------------------------------------------
const BASE_ID := "bastion"
## What an endless portal pours down its lane.
const CREEP_ID := "tree_grunt"
## The garrison a base regrows every few turns.
const GUARD_ID := "gem_knight"
## The OUTER neutral camp creature (the same one the Arena's camps field).
const CAMP_ID := "petalfang"
## The INNER camp's guardian. Picked off the roster BY THREAT: Blightcap is the tankier body
## (52 HP / 9 def / 11 magic def against Petalfang's 42 / 5 / 9) and it punishes the melee
## squad that walks into it -- Deathbloom ruptures on its death and coats whatever felled it.
## A second petalfang pair would have been more of the same fight; this is a different one.
const CAMP_INNER_ID := "blightcap"
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
	res.description = "A 35x35 forest siege. Two fortress-roots sit in opposite corners, each with a walled fountain spring at its back, and three lanes run between them: the Canopy Run along the north and east rim, the Root Run along the west and south, and the short Riftway straight through the middle. A stone circle stands at each lane's midpoint, ringed by sacred meadow -- hold one and the wood answers to you. Everything else is impassable wood and stone, cut by two jungle corridors where wild things sleep in two tiers, and by two grass tunnels barely a body wide that let whoever knows them slip around behind a rim lane. Creeps never stop coming down any of the three lanes. The map is a true 180-degree mirror -- every cell on one side has its twin on the other."
	res.author = "System"
	res.version = "2.0"
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
	# FOG OF WAR. Riftwood is the map the mechanic was designed for: a 35x35 wood whose whole
	# shape is lanes, jungle and ambush cover, where knowing where the enemy is NOT is the
	# information the flank routes and the tunnels are worth walking for. Off on every other
	# map (the field defaults false), so this is the one board that plays in the dark.
	res.fog_of_war = true
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
	var map_tags: Array[String] = [
		"siege", "push", "three-lane", "neutrals", "large", "control-points", "flanks",
	]
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
##   2. THE RIFTWAY   -- the |x - y| <= 1 diagonal band: the mid CONTROL POINT's stone circle
##                       at the centre, meadow around it, tall grass on its two edge
##                       diagonals, grass down the middle.
##   3. THE EDGE LANES-- each an L three cells wide: the elbow CONTROL POINT's stone circle at
##                       the lane's midpoint with meadow on the diagonals beside it, tall
##                       grass on the JUNGLE-facing edge only, else grass.
##   4. THE TUNNELS   -- the two mirrored 1-wide tall-grass sneak routes. Checked BEFORE the
##                       corridors and the jungle, and after the lanes, so a tunnel can be
##                       cut through wood without a lane predicate having to know about it.
##   5. JUNGLE CORRIDOR -- dirt, with a tall-grass brush around every camp, both tiers.
##   6. JUNGLE        -- stone banks where it meets the Riftway, trees everywhere else.
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

	# 2. The Riftway (mid), self-mirroring -- and so is the control circle sitting on it.
	if _in_rift(cell):
		if cell in CIRCLE_MID:
			return "forest_dirt"
		if cell.x >= 16 and cell.x <= 18:
			return "sacred_meadow"
		return "tall_grass" if absi(cell.x - cell.y) == 1 else "grass_plains"

	# 3. The two edge lanes.
	if _in_canopy(cell):
		return _canopy_tile(cell)
	if _in_canopy(mirrored):
		return _canopy_tile(mirrored)

	# 4. The two sneak tunnels.
	if cell in TUNNEL_CANOPY or mirrored in TUNNEL_CANOPY:
		return "tall_grass"

	# 5. The two jungle corridors.
	if _in_corridor(cell) or _in_corridor(mirrored):
		var local := cell if _in_corridor(cell) else mirrored
		for camp in CAMP_CELLS + INNER_CAMP_CELLS:
			if maxi(absi(local.x - camp.x), absi(local.y - camp.y)) <= 1:
				return "tall_grass"
		return "forest_dirt"

	# 6. Jungle. Stone banks the Riftway; wood fills the rest.
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


## Canopy Run terrain: the control point's stone circle at the elbow with the meadow on the
## four diagonals beside it, tall grass on the jungle-facing edge (the SOUTH row of the north
## arm, the WEST column of the east arm), grass elsewhere.
func _canopy_tile(cell: Vector2i) -> String:
	if cell in CIRCLE_CANOPY:
		return "forest_dirt"
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
	#
	# TWO TIERS, authored identically apart from what stands there: a cheap OUTER pair on each
	# corridor trunk and a single tougher INNER guardian on each corridor's mid-ward shoulder.
	# What clearing one GRANTS is the mode's business (CONQUEST.md rule 11); the map says only
	# where they stand and who stands there.
	for tier in [{"cells": CAMP_CELLS, "id": CAMP_ID}, {"cells": INNER_CAMP_CELLS, "id": CAMP_INNER_ID}]:
		for camp in tier["cells"]:
			for cell in [camp, mirror(camp)]:
				res.set_spawn_point_at_position(cell, NEUTRAL_SLOT,
					MapResource.SPAWN_KIND_REINFORCEMENT, {
						"character_id": String(tier["id"]), "max_spawns": 1, "spawn_turn": 1,
						"ai_stance": "dormant", "leash_radius": 0,
					})


## [param cell] for player 0, or its mirror for player 1.
static func _side(cell: Vector2i, flip: bool) -> Vector2i:
	return mirror(cell) if flip else cell


# --- Lanes + base cells + control points --------------------------------------

func _declare_geometry(res: MapResource) -> void:
	res.lanes = []
	res.add_lane(LANE_CANOPY)
	res.add_lane(LANE_ROOT)
	res.add_lane(LANE_RIFT)
	res.base_cells = {}
	res.set_base_cell(0, BASE_CELL)
	res.set_base_cell(1, mirror(BASE_CELL))
	# The three claimable midpoints. Unowned by construction: the mid point is its OWN mirror
	# and the two rim points are each other's, so the set is closed under r() and neither side
	# starts nearer to more of them than the other (32 / 32 / 28 steps from either base).
	res.control_points = []
	res.add_control_point(POINT_CANOPY)
	res.add_control_point(mirror(POINT_CANOPY))
	res.add_control_point(POINT_MID)


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

	# Control points: three of them, all walkable, and the SET closed under r() (the mid one
	# is its own mirror; the two rim ones are each other's).
	var points: Array[Vector2i] = res.get_control_points()
	print("Control points: %s" % str(points))
	if points.size() != 3:
		push_error("[validate] expected 3 control points, got %d" % points.size())
		ok = false
	for point in points:
		var point_tile: String = str(res.get_tile_at_position(point).get("tile_id", ""))
		if point_tile in IMPASSABLE_IDS:
			push_error("[validate] control point %s sits on '%s'" % [str(point), point_tile])
			ok = false
		if not points.has(mirror(point)):
			push_error("[validate] control point %s has no mirror twin" % str(point))
			ok = false
		# It has to READ as claimable, and the meadow has to be beside it rather than on it.
		var ringed := false
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if str(res.get_tile_at_position(point + Vector2i(dx, dy)).get(
						"tile_id", "")) == "sacred_meadow":
					ringed = true
		if point_tile != "forest_dirt" or not ringed:
			push_error("[validate] control point %s is not a stone circle ringed by meadow" % str(point))
			ok = false

	# The tunnels: 1 cell wide, no base-pocket contact, and NOT the new highway.
	var blocked: Dictionary = _blocked_cells(res)
	var tunnel_cells: Dictionary = {}
	for cell in TUNNEL_CANOPY:
		tunnel_cells[cell] = true
		tunnel_cells[mirror(cell)] = true
	var mouths: Array[Vector2i] = []
	for cell in tunnel_cells.keys():
		if str(res.get_tile_at_position(cell).get("tile_id", "")) != "tall_grass":
			push_error("[validate] tunnel cell %s is not tall grass" % str(cell))
			ok = false
		if _in_pocket(cell) or _in_pocket(mirror(cell)):
			push_error("[validate] tunnel cell %s opens into a base pocket" % str(cell))
			ok = false
		for offset in ORTHO:
			var next: Vector2i = cell + offset
			if next.x < 0 or next.x >= W or next.y < 0 or next.y >= H:
				continue
			if blocked.has(next) or tunnel_cells.has(next):
				continue
			mouths.append(next)
	# Four openings: each tunnel has exactly two, so neither is wider than one cell anywhere.
	print("Tunnels: %d cells, mouths %s" % [tunnel_cells.size(), str(mouths)])
	if mouths.size() != 4:
		push_error("[validate] tunnels have %d openings, expected 4 (2 each)" % mouths.size())
		ok = false

	# THE HIGHWAY CHECK. Base to base must be no shorter with the tunnels open than with them
	# walled off -- a flank that shortens the push is not a flank, it is a fourth lane.
	var sealed: Dictionary = blocked.duplicate()
	for cell in tunnel_cells.keys():
		sealed[cell] = true
	var base_to_base: int = _distance(blocked, BASE_CELL, mirror(BASE_CELL))
	var base_to_base_sealed: int = _distance(sealed, BASE_CELL, mirror(BASE_CELL))
	if base_to_base != base_to_base_sealed:
		push_error("[validate] tunnels shorten base-to-base (%d open vs %d sealed)" % [
			base_to_base, base_to_base_sealed])
		ok = false

	# The walk-distance table, printed so a retune can be read against the last one.
	print("\n---- WALK DISTANCES (4-neighbour, unit cost) ----")
	print("  base 0 -> base 1                : %d  (sealed tunnels: %d)" % [
		base_to_base, base_to_base_sealed])
	for label_point in [["canopy point", POINT_CANOPY], ["root point", mirror(POINT_CANOPY)],
			["mid point", POINT_MID]]:
		print("  base 0 / base 1 -> %-14s: %d / %d" % [
			str(label_point[0]),
			_distance(blocked, BASE_CELL, label_point[1]),
			_distance(blocked, mirror(BASE_CELL), label_point[1])])
	for camp in CAMP_CELLS + INNER_CAMP_CELLS:
		print("  base 0 / base 1 -> camp %-8s: %d / %d   (-> mid point: %d)" % [
			str(camp), _distance(blocked, BASE_CELL, camp),
			_distance(blocked, mirror(BASE_CELL), camp),
			_distance(blocked, camp, POINT_MID)])
	print("  flank rotation, corridor (25,17) -> canopy far third (32,22): %d  (sealed: %d)" % [
		_distance(blocked, Vector2i(25, 17), Vector2i(32, 22)),
		_distance(sealed, Vector2i(25, 17), Vector2i(32, 22))])
	print("")

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


## cell -> true for every impassable cell on the saved map.
func _blocked_cells(res: MapResource) -> Dictionary:
	var blocked: Dictionary = {}
	for tile in res.tile_layout:
		if str(tile.get("tile_id", "")) in IMPASSABLE_IDS:
			blocked[tile.get("position", Vector2i(-1, -1))] = true
	return blocked


## Shortest four-neighbour walk between two cells over [param blocked], or -1 if unreachable.
func _distance(blocked: Dictionary, from: Vector2i, to: Vector2i) -> int:
	var seen: Dictionary = { from: 0 }
	var queue: Array[Vector2i] = [from]
	var head: int = 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		if cell == to:
			return int(seen[cell])
		for offset in ORTHO:
			var next: Vector2i = cell + offset
			if next.x < 0 or next.x >= W or next.y < 0 or next.y >= H:
				continue
			if seen.has(next) or blocked.has(next):
				continue
			seen[next] = int(seen[cell]) + 1
			queue.append(next)
	return -1


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
