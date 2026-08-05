extends GutTest

## Invariants for RIFTWOOD, the large three-lane siege map.
##
## The map's whole design claim is that it is a PERFECT MIRROR: every cell, spawn point,
## lane waypoint and base cell has its twin under a 180-degree rotation. That is the one
## thing a human cannot check on 1225 cells and the one thing a ranked match is lost to,
## so it is asserted here cell by cell rather than trusted to the generator
## (game/maps/build_riftwood.gd).
##
## The rest pins what the MODE depends on: three lanes with a creep portal on each head,
## a base cell and a destructible base on each side, a fountain sanctum behind each base,
## a healing meadow at every lane's midpoint, and dormant neutral camps that stay dormant.

const MAP_PATH := "res://game/maps/resources/riftwood.tres"
const BASE_ID := "bastion"
## Mirrors PlayerManager.NEUTRAL_PLAYER_INDEX (and ArenaRoundBuilder.NEUTRAL_PLAYER_ID).
const NEUTRAL_SLOT: int = 2
const IMPASSABLE_IDS := ["tree", "stone_wall"]
const ORTHO: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var _map: MapResource
## cell -> tile_id, built once. get_tile_at_position is a linear scan over 1225 entries,
## and the symmetry sweep needs two lookups per cell.
var _tiles: Dictionary = {}


func before_all() -> void:
	_map = load(MAP_PATH) as MapResource
	if _map == null:
		return
	for tile in _map.tile_layout:
		_tiles[tile.get("position", Vector2i(-1, -1))] = str(tile.get("tile_id", ""))


## Compiling this map's rules ARMS two shared singletons (production wiring): the
## BaseAssaultRuntime that registers this map's neutral camps and pays the bounty for felling
## one, and -- now that the objective is "Capture Enemy Base" -- the SiegeController that runs
## the lanes. Disarm BOTH and take them down: each parents itself to the scene-tree ROOT, so
## leaving one there is an orphan in this script's count and a live listener in the next
## suite's. Both sync()s re-check is_instance_valid before reusing their static handle, so
## dropping the nodes is safe -- the next push map simply installs fresh ones.
func after_all() -> void:
	BaseAssaultRuntime.sync(null)
	SiegeController.sync(null)
	for node_name in [BaseAssaultRuntime.NODE_NAME, SiegeController.NODE_NAME]:
		var runtime := get_tree().root.get_node_or_null(node_name)
		if runtime != null:
			get_tree().root.remove_child(runtime)
			runtime.free()
	SiegeController._instance = null


func _mirror(cell: Vector2i) -> Vector2i:
	return Vector2i(_map.width - 1 - cell.x, _map.height - 1 - cell.y)


func _tile_at(cell: Vector2i) -> String:
	return str(_tiles.get(cell, ""))


func _cells_with(tile_id: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell in _tiles.keys():
		if _tiles[cell] == tile_id:
			out.append(cell)
	return out


func _spawns_for(player_id: int) -> Array:
	var out: Array = []
	for sd in _map.unit_spawns:
		if int(sd.get("player_id", -1)) == player_id:
			out.append(_map.normalize_spawn(sd))
	return out


# --- Identity ----------------------------------------------------------------

func test_map_loads_and_is_offered_to_players() -> void:
	assert_not_null(_map, "the Riftwood map resource should load")
	assert_eq(_map.map_name, "Riftwood")
	assert_true(_map.is_active(), "must be Active so it lists in the map picker")
	assert_eq(String(_map.victory_conditions[0]), "Capture Enemy Base",
		"a siege is won by TAKING the other base -- standing a hero on its cell and holding "
		+ "it for a turn -- not by flattening a structure")


func test_the_map_is_large_and_within_the_shared_size_cap() -> void:
	# Deliberately near MAX_MAP_SIZE: three lanes plus a jungle between them needs the room.
	assert_eq(_map.width, 35)
	assert_eq(_map.height, 35)
	assert_lte(_map.width, MapResource.MAX_MAP_SIZE, "within the shareable-map size cap")
	assert_gte(_map.width, 30, "and genuinely large -- a short lane is not a lane")


func test_declares_three_player_slots_for_the_neutral_faction() -> void:
	assert_gte(_map.max_players, 3, "the jungle camps need a third slot")


func test_it_is_listed_as_a_builtin_and_is_versus_eligible() -> void:
	assert_has(MapLoader.get_available_maps(false), MAP_PATH,
		"an Active builtin is offered by the map picker")
	assert_true(MapCatalog.is_versus_eligible(_map),
		"two sides own squad chairs, so a versus match can be played on it")


func test_map_passes_its_own_strict_validator() -> void:
	var report: Dictionary = _map.validate_map(true)
	assert_true(report.get("valid", false),
		"strict validation issues: %s" % str(report.get("issues", [])))


# --- Terrain -----------------------------------------------------------------

func test_every_cell_is_painted_and_resolves() -> void:
	assert_eq(_map.tile_layout.size(), _map.width * _map.height, "every cell painted")
	var composition: Dictionary = {}
	for tile_id in _tiles.values():
		composition[tile_id] = int(composition.get(tile_id, 0)) + 1
	for tile_id in composition.keys():
		assert_not_null(TileCatalog.find_by_id(StringName(tile_id)),
			"tile_id '%s' must resolve via TileCatalog" % tile_id)
	assert_gt(int(composition.get("tall_grass", 0)), 0, "lanes are edged with ambush cover")
	assert_gt(int(composition.get("tree", 0)), 0, "impassable wood shapes the lanes")
	assert_gt(int(composition.get("stone_wall", 0)), 0, "and rock banks the middle")
	assert_gt(int(composition.get("forest_dirt", 0)), 0, "the jungle corridors are walkable")


func test_the_board_is_a_perfect_one_eighty_mirror() -> void:
	# Array counter, not an int: a GUT lambda would capture an int BY VALUE.
	var broken: Array[Vector2i] = []
	for cell in _tiles.keys():
		if _tile_at(cell) != _tile_at(_mirror(cell)):
			broken.append(cell)
	assert_eq(broken.size(), 0,
		"neither side may have terrain the other does not (first offender: %s)" % (
			str(broken[0]) if not broken.is_empty() else "none"))


func test_every_walkable_cell_is_reachable_from_player_zeros_base() -> void:
	# A lane, a camp or a fountain sealed behind the wood is scenery, not a map.
	var walkable: int = 0
	for tile_id in _tiles.values():
		if not (tile_id in IMPASSABLE_IDS):
			walkable += 1
	assert_eq(_flood_from(_map.get_base_cell(0)), walkable,
		"every walkable cell is connected to player 0's base")


## Cells reachable on foot from [param origin], four-neighbour.
func _flood_from(origin: Vector2i) -> int:
	var seen: Dictionary = { origin: true }
	var queue: Array[Vector2i] = [origin]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for offset in ORTHO:
			var next: Vector2i = cell + offset
			if seen.has(next) or not _tiles.has(next):
				continue
			if _tile_at(next) in IMPASSABLE_IDS:
				continue
			seen[next] = true
			queue.append(next)
	return seen.size()


# --- Bases + fountains --------------------------------------------------------

func test_both_bases_are_declared_and_are_mirrors_of_each_other() -> void:
	assert_eq(_map.get_base_cell(0), Vector2i(3, 3), "player 0's base sits in its corner")
	assert_eq(_map.get_base_cell(1), _mirror(_map.get_base_cell(0)),
		"and player 1's is the exact opposite cell")


func test_a_destructible_base_actually_stands_on_each_declared_base_cell() -> void:
	# base_cells is a DECLARATION; the structure is a spawn. If they disagree, a mode that
	# trusts either one is reasoning about the wrong cell.
	for player_id in [0, 1]:
		var found: Array[Vector2i] = []
		for sd in _spawns_for(player_id):
			if String(sd["character_id"]) == BASE_ID:
				found.append(sd["position"])
		assert_eq(found.size(), 1, "player %d fields exactly one base" % player_id)
		assert_eq(found[0], _map.get_base_cell(player_id),
			"player %d's base stands on its declared base cell" % player_id)


func test_the_base_is_placed_at_load_and_never_comes_back() -> void:
	for sd in _map.unit_spawns:
		if str(sd.get("character_id", "")) != BASE_ID:
			continue
		var norm: Dictionary = _map.normalize_spawn(sd)
		assert_true(_map.is_initial_spawn(sd), "a base stands from turn one")
		assert_eq(int(norm["max_spawns"]), 1, "a destroyed base must NOT respawn")
		assert_ne(String(norm["spawn_kind"]), MapResource.SPAWN_KIND_START,
			"the base must not sit in a squad chair Character Select would overwrite")


func test_each_base_has_a_fountain_sanctum_behind_it() -> void:
	var fountains: Array[Vector2i] = _cells_with("fountain")
	assert_eq(fountains.size(), 8, "four fountain cells per side")
	for cell in fountains:
		assert_eq(_tile_at(_mirror(cell)), "fountain", "%s has its mirror" % str(cell))


func test_the_fountain_sanctum_is_deeper_in_the_pocket_than_the_base() -> void:
	# There is no team-gating on a map-authored tile effect (see the suite note in
	# integration/test_riftwood_board.gd), so the fountains earn their safety by GEOMETRY:
	# every one of them is further from the middle of the board than its own base is.
	var centre := Vector2i(_map.width / 2, _map.height / 2)
	for cell in _cells_with("fountain"):
		var owner_id: int = 0 if cell.x < centre.x else 1
		var base: Vector2i = _map.get_base_cell(owner_id)
		var fountain_reach: int = absi(cell.x - centre.x) + absi(cell.y - centre.y)
		var base_reach: int = absi(base.x - centre.x) + absi(base.y - centre.y)
		assert_gt(fountain_reach, base_reach,
			"fountain %s sits behind player %d's base, not in front of it" % [str(cell), owner_id])


func test_the_fountain_heals_harder_than_a_sacred_meadow() -> void:
	var fountain: TileEffectResource = load("res://game/tiles/effects/resources/fountain.tres")
	var meadow: TileEffectResource = load("res://game/tiles/effects/resources/sacred_meadow.tres")
	assert_eq(fountain.trigger, TileEffectResource.Trigger.ON_TURN_START_WHILE_OCCUPYING,
		"a fountain mends whoever is standing in it at the start of its turn")
	var fountain_heal: int = int(fountain.home_summary_for(null)["authored"])
	var meadow_heal: int = int(meadow.home_summary_for(null)["authored"])
	assert_eq(fountain.home_summary_for(null)["kind"], &"heal", "and what it gives is health")
	assert_gt(fountain_heal, meadow_heal,
		"a base fountain (%d) must out-heal a lane meadow (%d)" % [fountain_heal, meadow_heal])


func test_the_fountain_is_elemented_water_by_the_chart() -> void:
	# Water is the element with NO roster content, so no squad collects the own-element
	# heal bonus at its own fountain -- which is what keeps a mirror map a mirror.
	var fountain: TileEffectResource = load("res://game/tiles/effects/resources/fountain.tres")
	assert_eq(fountain.element(), &"water",
		"the element comes from element_chart.tres's tile_elements, the single authority")


# --- Lanes --------------------------------------------------------------------

func test_it_declares_three_lanes_from_player_zero_toward_player_one() -> void:
	assert_eq(_map.lane_count(), 3, "two rim lanes and one through the middle")
	for i in range(_map.lane_count()):
		assert_gte(_map.get_lane(i).size(), 3, "lane %d has a route, not just two ends" % i)


func test_the_set_of_lanes_is_unchanged_by_the_mirror() -> void:
	# A 180-degree rotation does NOT map a rim lane onto itself: it maps the Canopy Run onto
	# the Root Run (and the Riftway onto itself, reversed). What has to hold -- and what
	# makes the two sides face the same three routes -- is that the SET of lanes is closed
	# under the rotation: every lane's mirror image, walked the other way, is also a lane.
	for i in range(_map.lane_count()):
		var lane: Array[Vector2i] = _map.get_lane(i)
		var flipped: Array[Vector2i] = []
		for k in range(lane.size() - 1, -1, -1):
			flipped.append(_mirror(lane[k]))
		var twin: int = -1
		for j in range(_map.lane_count()):
			if _map.get_lane(j) == flipped:
				twin = j
		assert_gte(twin, 0, "lane %d's mirror image is also a lane on this map" % i)


func test_the_middle_lane_is_its_own_mirror() -> void:
	# The diagonal runs corner to corner, so the rotation maps it onto itself reversed --
	# which is why it is the one lane both sides enter at the same distance from their base.
	var mid: Array[Vector2i] = _map.get_lane(2)
	assert_eq(_mirror(mid[0]), mid[mid.size() - 1],
		"the Riftway's two heads are each other's mirror")


func test_every_lane_waypoint_stands_on_walkable_ground() -> void:
	for i in range(_map.lane_count()):
		for waypoint in _map.get_lane(i):
			assert_false(_tile_at(waypoint) in IMPASSABLE_IDS,
				"lane %d waypoint %s is walkable (it is '%s')" % [i, str(waypoint), _tile_at(waypoint)])


func test_a_creep_portal_sits_on_both_heads_of_every_lane() -> void:
	# The mode may drive waves off the lane list OR off spawn points; both have to agree,
	# or one of them spawns creeps somewhere the other never routes them.
	var portals: Dictionary = {}
	for sd in _map.unit_spawns:
		if _map.get_spawn_kind(sd) == MapResource.SPAWN_KIND_ENDLESS:
			portals[sd.get("position", Vector2i(-1, -1))] = int(sd.get("player_id", -1))
	assert_eq(portals.size(), 6, "three lanes, two ends, one portal each")
	for i in range(_map.lane_count()):
		for player_id in [0, 1]:
			var head: Vector2i = _map.lane_head(i, player_id)
			assert_true(portals.has(head), "lane %d has a portal on player %d's head %s" % [
				i, player_id, str(head)])
			assert_eq(int(portals[head]), player_id, "and that portal belongs to player %d" % player_id)


func test_the_middle_lane_is_the_short_one() -> void:
	# The classic three-lane shape: the diagonal is the risky shortcut, the rim lanes are long.
	var lengths: Array[int] = []
	for i in range(_map.lane_count()):
		lengths.append(_route_length(_map.get_lane(i)))
	var mid: int = lengths[2]
	assert_lt(mid, lengths[0], "the Riftway is shorter than the Canopy Run")
	assert_lt(mid, lengths[1], "and shorter than the Root Run")
	assert_eq(lengths[0], lengths[1], "the two rim lanes are exactly the same length")


## Manhattan length of a waypoint route.
func _route_length(lane: Array[Vector2i]) -> int:
	var total: int = 0
	for i in range(1, lane.size()):
		total += absi(lane[i].x - lane[i - 1].x) + absi(lane[i].y - lane[i - 1].y)
	return total


func test_every_lane_has_a_healing_meadow_at_its_midpoint() -> void:
	for i in range(_map.lane_count()):
		var lane: Array[Vector2i] = _map.get_lane(i)
		var midpoint: Vector2i = lane[lane.size() / 2]
		assert_eq(_tile_at(midpoint), "sacred_meadow",
			"lane %d's midpoint %s is a meadow to fight over" % [i, str(midpoint)])


# --- Spawn economy ------------------------------------------------------------

func test_both_sides_get_squad_chairs_a_garrison_and_portals() -> void:
	for player_id in [0, 1]:
		var kinds: Dictionary = {}
		for sd in _spawns_for(player_id):
			var kind: String = String(sd["spawn_kind"])
			kinds[kind] = int(kinds.get(kind, 0)) + 1
		assert_gt(int(kinds.get(MapResource.SPAWN_KIND_START, 0)), 0,
			"player %d picks a squad" % player_id)
		assert_gt(int(kinds.get(MapResource.SPAWN_KIND_RESPAWN, 0)), 0,
			"player %d has a regrowing garrison" % player_id)
		assert_eq(int(kinds.get(MapResource.SPAWN_KIND_ENDLESS, 0)), 3,
			"player %d has one creep portal per lane" % player_id)


func test_the_two_sides_spawn_points_are_exact_mirrors() -> void:
	var p1_cells: Dictionary = {}
	for sd in _spawns_for(1):
		p1_cells[sd["position"]] = String(sd["character_id"]) + "/" + String(sd["spawn_kind"])
	var unmatched: Array[Vector2i] = []
	for sd in _spawns_for(0):
		var twin: Vector2i = _mirror(sd["position"])
		var signature: String = String(sd["character_id"]) + "/" + String(sd["spawn_kind"])
		if String(p1_cells.get(twin, "")) != signature:
			unmatched.append(sd["position"])
	assert_eq(unmatched.size(), 0,
		"every player-0 spawn has an identical mirrored twin (first offender: %s)" % (
			str(unmatched[0]) if not unmatched.is_empty() else "none"))


func test_every_spawn_names_a_character_that_resolves() -> void:
	for sd in _map.unit_spawns:
		var cid: String = str(sd.get("character_id", ""))
		assert_false(cid.is_empty(), "every spawn point on this map names what it fields")
		assert_not_null(CharacterLibrary.get_character(cid),
			"spawn character '%s' must resolve" % cid)


func test_the_portals_are_paced_and_unbounded() -> void:
	for sd in _map.unit_spawns:
		var norm: Dictionary = _map.normalize_spawn(sd)
		var kind: String = String(norm["spawn_kind"])
		if kind != MapResource.SPAWN_KIND_RESPAWN and kind != MapResource.SPAWN_KIND_ENDLESS:
			continue
		assert_gte(int(norm["respawn_interval"]), 2, "waves are staggered, not one per turn")
		assert_eq(int(norm["max_spawns"]), -1, "a portal is unbounded")


# --- Neutral camps ------------------------------------------------------------

func test_the_jungle_camps_are_dormant_anchored_and_mirrored() -> void:
	var camps: Array = _spawns_for(NEUTRAL_SLOT)
	assert_gte(camps.size(), 2, "there is a camp to clear")
	assert_lte(camps.size(), 4, "2-4 creatures, not an army")
	var cells: Dictionary = {}
	for sd in camps:
		cells[sd["position"]] = true
		assert_eq(String(sd["ai_stance"]), "dormant",
			"a wild thing at %s attacks nobody until it is struck" % str(sd["position"]))
		# NOT Respawn/Endless: MapLoader.resolve_default_ai_stance FORCES "aggressive" on
		# those kinds, which would silently wake the camp and send it down a lane.
		assert_eq(String(sd["spawn_kind"]), MapResource.SPAWN_KIND_REINFORCEMENT,
			"the kind that honours an authored dormant stance")
		assert_true(_map.is_initial_spawn(sd), "and still stands there from turn one")
		assert_eq(int(sd["leash_radius"]), 0, "a camp creature never leaves its camp")
		var character := CharacterLibrary.get_character(String(sd["character_id"]))
		assert_not_null(character, "camp character resolves")
		# MapLoader's difficulty gate silently drops a non-player unit whose character
		# demands a harder setting -- a side objective that vanishes on Normal is none.
		assert_eq(character.get_min_difficulty(), 0, "a camp must spawn at every difficulty")
	for cell in cells.keys():
		assert_true(cells.has(_mirror(cell)), "camp cell %s has its mirror" % str(cell))


func test_the_camps_sit_in_the_jungle_rather_than_in_a_lane() -> void:
	# A camp standing in a lane is a roadblock, not a side objective.
	for sd in _spawns_for(NEUTRAL_SLOT):
		var cell: Vector2i = sd["position"]
		for i in range(_map.lane_count()):
			for waypoint in _map.get_lane(i):
				assert_gt(absi(cell.x - waypoint.x) + absi(cell.y - waypoint.y), 2,
					"camp %s is off lane %d's route" % [str(cell), i])


# --- Objective ----------------------------------------------------------------

func test_the_objective_compiles_to_a_capture_base_rule_set() -> void:
	var rules := WinConditionLibrary.build_rules(_map.victory_conditions, 0)
	assert_eq(rules.win_conditions.size(), 1, "one compiled objective")
	assert_true(rules.win_conditions[0] is CaptureBase, "compiles to CaptureBase")
	assert_eq((rules.win_conditions[0] as CaptureBase).faction, 0, "scored for the side asked for")


func test_the_map_arms_the_siege_runtime_and_counts_as_map_authored() -> void:
	# Two separate consequences of the objective string, both load-bearing:
	var rules := WinConditionLibrary.build_rules(_map.victory_conditions, 0)
	assert_true(SiegeController._rules_want_runtime(rules),
		"the compiled objective alone arms the Siege runtime (waves, respawns, march AI)")
	assert_true(BaseAssaultRuntime._rules_want_runtime(rules),
		"and the push-map runtime that registers this map's neutral camps and pays the "
		+ "bounty for felling one -- which used to be keyed to DestroyBase alone")
	assert_true(WinConditionLibrary.rules_are_map_authored(rules),
		"and the rules read as AUTHORED, so a VERSUS Riftwood is decided by the capture "
		+ "rather than by last-side-standing (which a push map can never reach)")


func test_the_map_declares_the_geometry_that_arms_the_runtime_on_its_own() -> void:
	# The second, independent opt-in: even a Siege map that named a different objective still
	# gets the lanes pushed, because the GEOMETRY is what the wave scheduler needs.
	assert_gt(_map.lane_count(), 0, "lanes are declared")
	assert_false(_map.base_cells.is_empty(), "and a base cell per side")
