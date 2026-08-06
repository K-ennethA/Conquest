extends GutTest

## BIG-MAP CLARITY on a REAL mounted board.
##
## The first Siege playtest of the 35x35 Riftwood reported that "visual clarity is harder on
## this big map". Two fixes, both DATA-DRIVEN, both proven here against the real thing rather
## than against a helper:
##
##   1. OBJECTIVE BANNERS -- a tall team-tinted pole over every cell the map's
##      [member MapResource.base_cells] declares. Driven by that dictionary alone, so any map
##      that authors bases gets them and no mode is ever consulted.
##   2. ZOOM SCALES WITH THE BOARD -- [CameraController]'s pull-back limit is derived from the
##      real board bounds, so a 35x35 map gets headroom a 13x11-era constant never gave it,
##      while a 13x11 map's limit is unchanged to the last float.
##
## ONE LOAD FOR THE WHOLE SUITE. Riftwood is 1225 tiles plus ~22 actors; it is built once in
## [method before_all], installed as current_scene (the only shape [CameraController] can
## resolve "Map/Tiles" through), and torn down in [method after_all]. The tests that MUTATE it
## (injecting a capture) are declared LAST -- GUT runs tests in declaration order.
##
## The pure half (plan / colour / the zoom arithmetic) is unit/test_objective_markers.gd.

const MARKERS := preload("res://game/visuals/ObjectiveMarkers.gd")
const CAMERA_SCRIPT := preload("res://game/visuals/CameraController.gd")
const RIFTWOOD_PATH := "res://game/maps/resources/riftwood.tres"
## 13x11 -- the board size the authored dist_max was tuned against.
const SMALL_MAP_PATH := "res://game/maps/resources/kings_crossing.tres"

## The authored battle camera: 50-degree fov, tilted 50 degrees down (GameWorld.tscn).
const CAMERA_PITCH_DEG: float = -50.0
const CAMERA_FOV: float = 50.0

## The shared board Grid MapLoader resizes to the loaded map -- a cached resource, i.e.
## process-wide state, so its size is snapshot and restored.
var _grid: Grid = null
var _grid_size_before: Vector3 = Vector3.ZERO

## SceneTree.current_scene is swapped for the whole suite and always put back.
var _scene_before: Node = null
## The riftwood fixture. Mounted on the tree ROOT by hand (the engine requires current_scene
## to be a direct child of root), so it cannot use add_child_autofree.
var _scene: Node3D = null
var _map_node: Node3D = null
var _loader: MapLoader = null
var _map_res: MapResource = null

## A second, temporary board some tests stand up (a small map, a synthetic one). Freed by
## after_each even when the test that built it failed part-way.
var _scratch: Node3D = null


func before_all() -> void:
	_grid = load("res://board/Grid.tres") as Grid
	if _grid != null:
		_grid_size_before = _grid.size
	_scene_before = get_tree().current_scene
	if CombatServices:
		CombatServices.clear()

	_map_res = load(RIFTWOOD_PATH) as MapResource

	_scene = Node3D.new()
	_scene.name = "TestBigBoard"
	get_tree().root.add_child(_scene)

	_map_node = Node3D.new()
	_map_node.name = "Map"
	_scene.add_child(_map_node)

	_loader = MapLoader.new()
	_map_node.add_child(_loader)
	_loader.load_map(_map_res, _map_node)

	# The swap happens AFTER the load on purpose: Unit._find_visual_manager conjures the whole
	# battle VISUAL stack under whatever current_scene is set when a unit enters the tree, and
	# this suite is about board geometry.
	get_tree().current_scene = _scene

	if CombatServices:
		CombatServices.rebuild(_map_node)


func after_each() -> void:
	# Any test that swapped in its own board puts riftwood back, so the next test still finds
	# the suite fixture -- this runs even when the test failed on its first assertion.
	if _scene != null and is_instance_valid(_scene) and get_tree().current_scene != _scene:
		get_tree().current_scene = _scene
	if _scratch != null and is_instance_valid(_scratch):
		if _scratch.get_parent() != null:
			_scratch.get_parent().remove_child(_scratch)
		_scratch.free()
	_scratch = null


func after_all() -> void:
	# Order matters: put the real scene back BEFORE unmounting ours.
	if get_tree().current_scene != _scene_before:
		get_tree().current_scene = _scene_before
	if _scene != null and is_instance_valid(_scene):
		get_tree().root.remove_child(_scene)
		_scene.free()
	_scene = null
	_map_node = null
	_loader = null
	if CombatServices:
		CombatServices.clear()
	if _grid != null:
		_grid.size = _grid_size_before


# --- Helpers -----------------------------------------------------------------

func _markers_node() -> Node3D:
	return _map_node.get_node_or_null(MARKERS.NODE_NAME) as Node3D


## A camera carrying the real controller script, posed like the authored battle camera so the
## fit maths sees production's tilt and fov rather than an identity basis.
func _battle_camera() -> Camera3D:
	var cam: Camera3D = CAMERA_SCRIPT.new()
	cam.rotation_degrees = Vector3(CAMERA_PITCH_DEG, 0.0, 0.0)
	cam.fov = CAMERA_FOV
	add_child_autofree(cam)
	return cam


func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = [node]
	for child in node.get_children():
		found.append_array(_descendants(child))
	return found


## A 5x5 map that declares two bases and nothing else -- no lanes, no siege objective, no
## mode. Proves the banners are earned by base_cells alone.
func _synthetic_base_map() -> MapResource:
	var map := MapLoader.create_default_map()
	map.set_base_cell(0, Vector2i(2, 0))
	map.set_base_cell(1, Vector2i(2, 4))
	return map


## Load [param map] into a fresh root-mounted board, returning { map_node, loader }. Freed by
## after_each via [member _scratch].
func _load_scratch(map: MapResource, as_current_scene: bool) -> Dictionary:
	var scene_root := Node3D.new()
	scene_root.name = "TestScratchBoard"
	get_tree().root.add_child(scene_root)
	_scratch = scene_root

	var map_node := Node3D.new()
	map_node.name = "Map"
	scene_root.add_child(map_node)

	var loader := MapLoader.new()
	map_node.add_child(loader)
	loader.load_map(map, map_node)

	if as_current_scene:
		get_tree().current_scene = scene_root
	return { "map_node": map_node, "loader": loader }


# --- The banners exist, where the map said, in the right place ---------------

func test_a_map_that_declares_bases_gets_a_banner_over_each_one() -> void:
	var markers := _markers_node()
	assert_not_null(markers, "loading a map with base_cells mounts the objective banners")
	if markers == null:
		return
	assert_eq(markers.layout.size(), 2, "riftwood declares two bases, so two banners stand")

	for player_id in [0, 1]:
		var marker: Node3D = markers.marker_for(player_id)
		assert_not_null(marker, "player %d's base carries a banner" % player_id)
		if marker == null:
			continue
		var cell: Vector2i = _map_res.get_base_cell(player_id)
		assert_eq(marker.get_meta("cell"), cell,
			"player %d's banner is bound to the cell the MAP declared" % player_id)
		assert_almost_eq(marker.position.x, float(cell.x) * 2.0 + 1.0, 0.001,
			"and stands on that cell's center in X")
		assert_almost_eq(marker.position.z, float(cell.y) * 2.0 + 1.0, 0.001,
			"and on its center in Z")


func test_the_banners_are_a_sibling_of_the_tile_container() -> void:
	var tiles := _map_node.get_node_or_null("Tiles")
	assert_not_null(tiles, "the playable tile container is there")
	assert_null(tiles.get_node_or_null(MARKERS.NODE_NAME),
		"the banners are a SIBLING of Tiles, never inside it -- the camera fits Tiles' children")


func test_each_side_gets_its_own_team_tint_on_its_own_materials() -> void:
	var markers := _markers_node()
	if markers == null:
		pending("no banners mounted")
		return

	var pennant0 := markers.marker_for(0).get_node("Banner/Pennant") as MeshInstance3D
	var pennant1 := markers.marker_for(1).get_node("Banner/Pennant") as MeshInstance3D
	var mat0 := pennant0.material_override as StandardMaterial3D
	var mat1 := pennant1.material_override as StandardMaterial3D

	assert_not_null(mat0, "player 0's pennant carries its own material")
	assert_not_null(mat1, "player 1's pennant carries its own material")
	assert_ne(mat0, mat1,
		"the two banners hold DUPLICATED materials -- tinting one can never recolour the other")
	assert_eq(mat0.albedo_color, MARKERS.color_for_player(0),
		"player 0's banner wears the same team colour the unit tints use")
	assert_eq(mat1.albedo_color, MARKERS.color_for_player(1), "and player 1's wears its own")
	assert_ne(mat0.albedo_color, mat1.albedo_color, "so the two sides read apart at a glance")


func test_a_banner_is_tall_enough_to_find_from_full_zoom_out() -> void:
	var markers := _markers_node()
	if markers == null:
		pending("no banners mounted")
		return

	assert_gte(markers.top_height(), 3.0 * MARKERS.CELL,
		"a banner is at least three board cells tall -- that is what makes it findable at range")

	var pole := markers.marker_for(0).get_node("Pole") as MeshInstance3D
	var pole_mesh := pole.mesh as BoxMesh
	assert_almost_eq(pole_mesh.size.y, markers.pole_height, 0.001,
		"the mast really is the authored height (it is built from primitives, not a scene)")

	var banner := markers.marker_for(0).get_node("Banner") as Node3D
	assert_almost_eq(banner.position.y, markers.pole_height, 0.001,
		"the pennant hangs at the TOP of the mast, clear of every unit and tree on the board")


# --- ...and it is decoration and nothing else --------------------------------

func test_the_banners_add_no_board_cells() -> void:
	var tiles := _map_node.get_node("Tiles")
	assert_eq(tiles.get_child_count(), _map_res.width * _map_res.height,
		"the board is still width x height tiles -- the banners contributed none of them")


func test_the_base_cell_is_still_exactly_the_terrain_the_map_authored() -> void:
	if not CombatServices:
		pending("no CombatServices autoload")
		return
	var cell: Vector2i = _map_res.get_base_cell(0)
	assert_not_null(CombatServices.tile_at(cell),
		"the base cell is still registered terrain, exactly as before")
	var effects: Array = CombatServices.tile_effects_at(cell)
	assert_eq(effects.size(), 0,
		"and the banner standing on it registered no tile effect of its own")


func test_the_banners_carry_no_collider() -> void:
	var markers := _markers_node()
	if markers == null:
		pending("no banners mounted")
		return
	var colliders: Array[Node] = []
	for node in _descendants(markers):
		if node is CollisionObject3D:
			colliders.append(node)
	assert_eq(colliders.size(), 0,
		"nothing in the banners can be hit by a physics ray, now or by a future picker")


func test_the_whole_banner_set_is_a_handful_of_nodes() -> void:
	var markers := _markers_node()
	if markers == null:
		pending("no banners mounted")
		return
	var nodes: Array[Node] = _descendants(markers)
	# Budget scales with what the map authors: ~7 nodes per base banner and ~4 per
	# control-point marker (Riftwood: 2 bases + 3 points), with slack for a root.
	# The claim is PER-MARKER economy, not a frozen total from before control
	# points existed.
	var base_count: int = 2
	var cp_count: int = 3
	var budget: int = base_count * 8 + cp_count * 5 + 2
	assert_lt(nodes.size(), budget,
		"markers cost a handful of nodes each on a 1225-cell board (got %d, budget %d)"
		% [nodes.size(), budget])


# --- Zoom scales with the board ----------------------------------------------

func test_the_big_board_earns_more_pull_back_than_the_authored_limit() -> void:
	var cam := _battle_camera()
	cam.fit_to_map()

	assert_true(cam._has_bounds, "the camera found the 35x35 board")
	assert_gt(cam._dist_max_runtime, cam.dist_max,
		"a 35x35 board may pull back further than the 13x11-era authored dist_max")

	var diagonal: float = Vector2(70.0, 70.0).length()
	assert_almost_eq(cam._dist_max_runtime, cam.zoom_out_board_factor * diagonal, 0.01,
		"and the new limit is exactly the board diagonal times the exported factor")

	assert_gt(cam._dist_max_runtime, cam.dist_max * 1.35,
		"and it is a MEANINGFUL grow, not a rounding error -- half again the old budget")

	# Viewport-independent on purpose: the fit distance depends on the window aspect, so the
	# headroom is stated as a multiple of whatever this viewport framed at.
	var fit: float = cam._current_distance()
	assert_gt(cam._dist_max_runtime, fit * 1.25,
		"which restores real HEADROOM above the framing distance -- the clarity complaint")


func test_the_close_zoom_is_untouched_by_any_of_this() -> void:
	var cam := _battle_camera()
	cam.fit_to_map()
	assert_eq(cam.dist_min, 10.0, "the near clamp is still the authored one")
	cam._set_distance(0.0)
	assert_almost_eq(cam._current_distance(), cam.dist_min, 0.01,
		"and zooming all the way in still stops exactly at it")


func test_fit_to_map_still_frames_exactly_the_playable_rect() -> void:
	var cam := _battle_camera()
	cam.fit_to_map()

	# Tiles are placed at (col * 2 + 1, _, row * 2 + 1) -- their origins at cell CENTERS --
	# and the bounds expand half a cell each way, so the rect is exactly (0, 0)..(2w, 2h)
	# of PLAYABLE cells. Nothing decorative (surround, banners) may appear in that span.
	assert_eq(cam._board_min, Vector2(0.0, 0.0), "the fit rect starts at the board's true corner")
	assert_eq(cam._board_max - cam._board_min,
		Vector2(float(_map_res.width) * 2.0, float(_map_res.height) * 2.0),
		"and spans exactly the 35x35 playable rect -- no decoration inflated it")

	# The center of that rect: (0 + 70) / 2 on both axes.
	var focus: Vector3 = cam._camera_focus_ground()
	assert_almost_eq(focus.x, 35.0, 0.05, "the fit centres the camera on the board in X")
	assert_almost_eq(focus.z, 35.0, 0.05, "and in Z")

	var fit: float = cam._current_distance()
	assert_gt(fit, cam.dist_min, "the framing distance sits inside the zoom range")
	assert_lt(fit, cam._dist_max_runtime, "and below the new pull-back limit, so there is room to go out")


func test_the_banners_never_change_how_the_board_is_framed() -> void:
	var cam := _battle_camera()
	assert_true(cam._compute_board_bounds(), "the camera found the board")
	var min_with: Vector2 = cam._board_min
	var max_with: Vector2 = cam._board_max

	var markers := _markers_node()
	assert_not_null(markers, "the banners were mounted before we took them away")
	if markers == null:
		return
	_map_node.remove_child(markers)

	assert_true(cam._compute_board_bounds(), "the camera still finds the board")
	assert_eq(cam._board_min, min_with, "the fit rect's near corner is unchanged")
	assert_eq(cam._board_max, max_with, "and its far corner is unchanged too")

	# Put the fixture back for the tests that follow.
	_map_node.add_child(markers)


func test_a_thirteen_by_eleven_board_keeps_the_authored_limit_exactly() -> void:
	# THE PIN. Every map that shipped before the big boards must feel identical.
	var small := load(SMALL_MAP_PATH) as MapResource
	assert_eq(small.width, 13, "the pinned map really is 13 wide")
	assert_eq(small.height, 11, "and 11 deep")
	if CombatServices:
		CombatServices.clear()
	_load_scratch(small, true)

	var cam := _battle_camera()
	cam.fit_to_map()
	assert_true(cam._has_bounds, "the camera found the small board")
	assert_eq(cam._board_max - cam._board_min, Vector2(26.0, 22.0),
		"and measured it as the 13x11 rect it is")
	assert_almost_eq(cam._dist_max_runtime, cam.dist_max, 0.0001,
		"a 13x11 board's pull-back limit is STILL exactly the authored dist_max")

	# Rebuild the suite fixture's board registry, which the clear above dropped.
	get_tree().current_scene = _scene
	if CombatServices:
		CombatServices.clear()
		CombatServices.rebuild(_map_node)


func test_a_map_with_no_bases_mounts_no_banners_at_all() -> void:
	var small := load(SMALL_MAP_PATH) as MapResource
	assert_true(small.base_cells.is_empty(), "the pinned map declares no bases")
	var scratch := _load_scratch(small, false)
	var map_node: Node3D = scratch["map_node"]
	assert_null(map_node.get_node_or_null(MARKERS.NODE_NAME),
		"a map with no base_cells pays nothing -- not even an empty node")
	assert_null((scratch["loader"] as MapLoader).objective_markers,
		"and the loader holds no reference to one")


# --- Genericity + lifecycle, on a synthetic map ------------------------------

func test_any_map_that_authors_bases_gets_banners_with_no_mode_involved() -> void:
	# A plain 5x5 skirmish with two base cells bolted on: no lanes, no capture objective, no
	# siege controller anywhere. The banners are earned by the DATA alone.
	var scratch := _load_scratch(_synthetic_base_map(), false)
	var markers := (scratch["map_node"] as Node3D).get_node_or_null(MARKERS.NODE_NAME)
	assert_not_null(markers, "declaring base_cells is the whole opt-in")
	if markers == null:
		return
	assert_eq(markers.layout.size(), 2, "both declared bases got a banner")
	var cells: Dictionary = markers.marker_cells()
	assert_eq(cells.get(0), Vector2i(2, 0), "slot 0's banner stands on the cell the map named")
	assert_eq(cells.get(1), Vector2i(2, 4), "and slot 1's on its own")


func test_the_banners_are_freed_with_the_map() -> void:
	var scratch := _load_scratch(_synthetic_base_map(), false)
	var map_node: Node3D = scratch["map_node"]
	var loader: MapLoader = scratch["loader"]
	assert_not_null(map_node.get_node_or_null(MARKERS.NODE_NAME), "there are banners to tear down")

	loader.clear_current_map()

	assert_null(map_node.get_node_or_null(MARKERS.NODE_NAME),
		"clearing the map takes the banners with it -- no orphaned pole survives a reload")
	assert_null(loader.objective_markers, "and the loader drops its reference to them")


func test_reloading_a_map_never_stacks_two_banner_sets() -> void:
	var map := _synthetic_base_map()
	var scratch := _load_scratch(map, false)
	var map_node: Node3D = scratch["map_node"]
	var loader: MapLoader = scratch["loader"]

	loader.load_map(map, map_node)

	var count: Array[int] = [0]
	for child in map_node.get_children():
		if child.name == MARKERS.NODE_NAME:
			count[0] += 1
	assert_eq(count[0], 1,
		"a second load replaces the banners rather than planting another set on top")


# --- Capture urgency (declared LAST: it mutates the shared fixture) ----------

## A stand-in mode controller. Duck-typed exactly like [SiegeController]: the banners never
## reference that class, they only ask whatever object exposes capturing_by().
class StubMode extends Node:
	var side: int = -1
	var cell: Vector2i = Vector2i(-1, -1)

	func capturing_by() -> int:
		return side

	func capture_state() -> Dictionary:
		if side < 0:
			return {}
		return { "player_id": side, "cell": cell }


func test_a_capture_in_flight_makes_that_base_pulse_faster_and_brighter() -> void:
	var markers := _markers_node()
	if markers == null:
		pending("no banners mounted")
		return

	var stub := StubMode.new()
	stub.name = "StubMode"
	markers.add_child(stub)
	markers.mode_controller_path = NodePath("StubMode")

	markers.refresh_urgency()
	var calm_seconds: float = markers.bob_seconds_for(1)
	var calm_emission: float = markers.emission_peak_for(1)
	assert_false(markers.is_urgent(0), "nothing is being captured, so nobody is urgent")
	assert_false(markers.is_urgent(1), "on either side")

	# Player 0 is capturing player 1's base.
	stub.side = 0
	stub.cell = _map_res.get_base_cell(1)
	markers.refresh_urgency()

	assert_true(markers.is_urgent(1), "the CONTESTED base's banner escalates")
	assert_false(markers.is_urgent(0),
		"and the attacker's own untouched base keeps bobbing calmly")
	assert_lt(markers.bob_seconds_for(1), calm_seconds,
		"the contested banner pulses FASTER (%0.2fs vs %0.2fs)"
			% [markers.bob_seconds_for(1), calm_seconds])
	assert_gt(markers.emission_peak_for(1), calm_emission,
		"and BRIGHTER, so the thing about to lose the battle is the loudest thing on screen")

	# The capture lapses; the board calms back down.
	stub.side = -1
	markers.refresh_urgency()
	assert_false(markers.is_urgent(1), "a lapsed capture puts the banner back to its idle bob")
	assert_almost_eq(markers.bob_seconds_for(1), calm_seconds, 0.0001,
		"at exactly the calm rate it started at")

	markers.mode_controller_path = NodePath()
	markers.remove_child(stub)
	stub.free()
	markers.refresh_urgency()


func test_with_no_mode_controller_the_urgency_degrades_to_nothing() -> void:
	# A banner set with no tree around it can reach no controller at all -- which is the
	# situation on every map that is not a push/siege map, and it must be silent.
	var lone: Node3D = autofree(MARKERS.new())
	assert_eq(lone.urgent_cell(), MARKERS.NO_CELL,
		"no mode controller means no urgent cell, and no error either")
	assert_false(lone.is_urgent(0), "and no banner is ever escalated")
