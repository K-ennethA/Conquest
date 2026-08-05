extends GutTest

## RIFTWOOD on a REAL board: the authored .tres actually builds, the terrain it declares
## actually registers, and the actors it declares actually stand where it says.
##
## unit/test_riftwood.gd asserts what the RESOURCE says; this asserts what the game does
## with it -- two different failures (a map can be internally perfect and still fail to
## load because a tile id resolves to nothing the loader can instance).
##
## ONE LOAD FOR THE WHOLE SUITE. Riftwood is 35x35 = 1225 tiles plus ~22 actors; loading it
## per test would make this the slowest suite in the run for no extra coverage. The battle
## is built once in [method before_all] and torn down in [method after_all], so the two
## tests that MUTATE it (moving a unit onto a fountain, wounding it) are declared LAST --
## GUT runs tests in declaration order.
##
## TEAM-GATING, AND WHY THE FOUNTAIN HAS NONE. A fountain heals ANY occupant. Gating one to
## its base's owner is not expressible with today's effect machinery: OCCUPANT_ALLIES /
## OCCUPANT_ENEMIES resolve either against a RUNTIME owner_player (stamped only by
## ApplyTileEffect when a unit PLACES a trap) or against one board-wide
## perspective_unit() -- neither of which can say "player 0's fountain" and "player 1's
## fountain" on the same board at the same time. The map buys the same outcome with
## GEOMETRY instead: each fountain sits in a walled 2x2 sanctum behind its own base,
## entered through a single doorway (pinned in unit/test_riftwood.gd). That the heal is
## universal is asserted below, so the gap is a recorded fact rather than a surprise.

const MAP_PATH := "res://game/maps/resources/riftwood.tres"
const BASE_ID := "bastion"
const NEUTRAL_SLOT: int = 2
## The deepest cell of player 0's fountain sanctum.
const FOUNTAIN_CELL := Vector2i(0, 0)
## The middle lane's midpoint meadow.
const MEADOW_CELL := Vector2i(17, 17)

var _map_res: MapResource = null
## Manually managed (not add_child_autofree): the fixture outlives every test in the
## suite, so it is mounted in before_all and freed in after_all.
var _scene_root: Node3D = null
var _map_node: Node3D = null
var _loader: MapLoader = null

## The shared board Grid MapLoader resizes to the loaded map -- a cached resource, i.e.
## process-wide state, so its size is snapshot and restored.
var _grid: Grid = null
var _grid_size_before: Vector3 = Vector3.ZERO


func before_all() -> void:
	_map_res = load(MAP_PATH) as MapResource
	_grid = load("res://board/Grid.tres") as Grid
	if _grid != null:
		_grid_size_before = _grid.size
	if CombatServices:
		CombatServices.clear()

	_scene_root = Node3D.new()
	_scene_root.name = "TestRiftwood"
	add_child(_scene_root)

	_map_node = Node3D.new()
	_map_node.name = "Map"
	_scene_root.add_child(_map_node)

	_loader = MapLoader.new()
	_map_node.add_child(_loader)
	_loader.load_map(_map_res, _map_node)

	# MapLoader fills CombatServices' terrain registry during load_map; the BOARD itself is
	# built by GameWorldManager in production, so this suite builds it the same way.
	if CombatServices:
		CombatServices.rebuild(_map_node)


func after_all() -> void:
	if _scene_root != null and is_instance_valid(_scene_root):
		remove_child(_scene_root)
		_scene_root.free()
	_scene_root = null
	_map_node = null
	_loader = null
	if CombatServices:
		CombatServices.clear()
	if _grid != null:
		_grid.size = _grid_size_before


# --- Helpers -----------------------------------------------------------------

## Every Unit under the map root, keyed by owning player container index.
func _units_by_slot() -> Dictionary:
	var out: Dictionary = {}
	for slot in range(4):
		var container := _map_node.get_node_or_null("Player" + str(slot + 1))
		if container == null:
			continue
		var units: Array = []
		for child in container.get_children():
			if child is Unit:
				units.append(child)
		out[slot] = units
	return out


## The cell a spawned unit stands on. MapLoader places units at
## (x * 2 + 1, _, y * 2 + 1), so this is that mapping read backwards.
func _cell_of(unit) -> Vector2i:
	return Vector2i(int((unit.transform.origin.x - 1) / 2), int((unit.transform.origin.z - 1) / 2))


func _effect_ids_at(cell: Vector2i) -> Array:
	var ids: Array = []
	for te in CombatServices.tile_effects_at(cell):
		ids.append(String(te.id))
	return ids


# --- The board builds ---------------------------------------------------------

func test_the_map_loads_and_sizes_the_shared_grid() -> void:
	assert_not_null(_loader.current_map, "the loader is holding a map")
	assert_eq(_loader.current_map.map_name, "Riftwood")
	if _grid != null:
		assert_eq(int(_grid.size.x), _map_res.width, "the shared grid took the map's width")
		assert_eq(int(_grid.size.z), _map_res.height, "and its height")


func test_the_authored_terrain_registers_on_the_live_board() -> void:
	assert_has(_effect_ids_at(FOUNTAIN_CELL), "fountain",
		"the sanctum cell behind player 0's base carries the fountain effect")
	assert_has(_effect_ids_at(MEADOW_CELL), "sacred_meadow",
		"the middle lane's midpoint carries the meadow heal")
	assert_eq(_effect_ids_at(_map_res.get_base_cell(0)), [],
		"and the plain grass under the base carries nothing")


func test_the_jungle_is_impassable_and_the_pocket_is_not() -> void:
	var board := CombatServices.board()
	assert_not_null(board, "a board was built over the loaded map")
	# (5, 5) is inside player 0's pocket; (7, 3) is the wood just south of the Canopy Run's
	# mouth. If the wood were walkable, the three lanes would not be lanes.
	assert_false(board.is_blocked(Vector2i(5, 5)), "the base pocket is walkable")
	assert_true(board.is_blocked(Vector2i(7, 3)), "the jungle beside the lane mouth is not")


# --- The actors stand where the map says --------------------------------------

func test_both_bases_spawn_on_their_declared_base_cells() -> void:
	var by_slot: Dictionary = _units_by_slot()
	for player_id in [0, 1]:
		var bases: Array = []
		for unit in by_slot.get(player_id, []):
			if String(unit.name).begins_with(BASE_ID):
				bases.append(unit)
		assert_eq(bases.size(), 1, "player %d's base was spawned exactly once" % player_id)
		assert_eq(_cell_of(bases[0]), _map_res.get_base_cell(player_id),
			"player %d's base stands on its declared base cell" % player_id)


func test_both_sides_field_the_same_number_of_actors() -> void:
	var by_slot: Dictionary = _units_by_slot()
	var p0: int = (by_slot.get(0, []) as Array).size()
	var p1: int = (by_slot.get(1, []) as Array).size()
	assert_gte(p0, 4, "player 0 fielded a squad plus its base furniture")
	assert_eq(p0, p1, "and a mirror map hands the other side exactly as many")


func test_the_jungle_camps_spawn_neutral_and_dormant() -> void:
	var camps: Array = _units_by_slot().get(NEUTRAL_SLOT, [])
	assert_gte(camps.size(), 2, "the camps were spawned onto the neutral slot")
	for unit in camps:
		assert_true(unit.is_dormant(), "a camp creature holds until it is struck")
		assert_false(unit.provoked, "and nothing has struck it yet")


func test_the_fountain_heals_whoever_is_standing_in_it() -> void:
	# The recorded gap (see the suite note): a map-authored tile effect carries no owner, so
	# it cannot be gated to one team. An enemy that fights all the way into the sanctum is
	# healed by it too -- the sanctum's walls, not the effect, are what protect it.
	var fountain: TileEffectResource = load("res://game/tiles/effects/resources/fountain.tres")
	assert_eq(fountain.affected_factions, TileEffectResource.AffectedFactions.ALL,
		"no team gate is expressible on map-authored terrain today")
	assert_null(fountain.owner_player,
		"and authored terrain never carries the runtime owner a placed trap does")


# --- Mutating tests: declared LAST, they move and wound a live unit ------------

func test_the_fountain_mends_a_wounded_occupant_at_turn_start() -> void:
	var patient = _a_living_hero()
	if patient == null:
		pending("no non-structure unit was spawned to stand in the fountain")
		return

	patient.transform.origin = Vector3(
		FOUNTAIN_CELL.x * 2 + 1, patient.transform.origin.y, FOUNTAIN_CELL.y * 2 + 1)
	var board := CombatServices.board()
	assert_eq(board.cell_of(patient), FOUNTAIN_CELL, "the unit really is standing in it")

	var max_hp: int = patient.get_base_stat("health")
	patient.take_damage(max_hp - 1)
	var wounded: int = patient.get_stat("health")
	assert_lt(wounded, max_hp, "the unit is actually hurt going in")

	var system: TileEffectSystem = add_child_autofree(TileEffectSystem.new())
	system.on_turn_start(patient, board)

	var healed: int = patient.get_stat("health") - wounded
	assert_gt(healed, 0, "standing in the fountain at turn start restores health")
	assert_gte(healed, 20, "and it is a STRONG heal, not a meadow's trickle (got %d)" % healed)


## The first spawned unit that is a mobile hero rather than the immobile base structure.
func _a_living_hero():
	for unit in _units_by_slot().get(0, []):
		if String(unit.name).begins_with(BASE_ID):
			continue
		if unit.get_base_stat("health") > 1:
			return unit
	return null
