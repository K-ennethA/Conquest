extends GutTest

## The decorative surround on a REAL loaded map: it must be scenery and nothing else.
##
## Every assertion here is a *negative space* one -- the surround exists, and the board
## behaves exactly as though it does not:
##   * no board cell added (the tile container and CombatServices' terrain registry are
##     unchanged, and an out-of-bounds decor cell resolves to no tile),
##   * cursor cell resolution at a BORDER-ADJACENT cell is untouched (the live picking
##     maths: ground-plane hit -> Grid.calculate_grid_coordinates -> is_within_bounds),
##   * no collider anywhere in it, so no physics pick can ever reach one,
##   * the camera's FIT rect is identical with and without it (only its PAN slack grows),
##   * it is freed with the map.
##
## What it looks like is the player's playtest; what it cannot break is here.

const MAP_PATH := "res://game/maps/resources/forgotten_forest.tres"
const CAMERA_SCRIPT := preload("res://game/visuals/CameraController.gd")
const SURROUND := preload("res://game/maps/MapSurround.gd")

## The shared board Grid MapLoader resizes to the loaded map (see MapLoader._sync_grid_size).
## It is a cached resource, i.e. process-wide state, so its size is snapshot and restored.
var _grid: Grid = null
var _grid_size_before: Vector3 = Vector3.ZERO
## SceneTree.current_scene is swapped for the camera test (CameraController resolves
## "Map/Tiles" through it) and always put back, even when a test fails part-way.
var _scene_before: Node = null
## The stand-in scene root that swap needs. The engine REQUIRES current_scene to be a
## direct child of the tree root, so this one cannot use add_child_autofree -- it is
## mounted on root by hand and taken down here.
var _mounted_scene: Node = null


func before_each() -> void:
	_grid = load("res://board/Grid.tres") as Grid
	if _grid != null:
		_grid_size_before = _grid.size
	_scene_before = get_tree().current_scene
	# CombatServices' terrain registry is an autoload dictionary the loader writes into.
	if CombatServices:
		CombatServices.clear()


func after_each() -> void:
	# Order matters: put the real scene back BEFORE unmounting ours, so the tree is never
	# left pointing at a node that is about to be freed.
	if get_tree().current_scene != _scene_before:
		get_tree().current_scene = _scene_before
	if _mounted_scene != null and is_instance_valid(_mounted_scene):
		get_tree().root.remove_child(_mounted_scene)
		_mounted_scene.free()
	_mounted_scene = null
	if CombatServices:
		CombatServices.clear()
	if _grid != null:
		_grid.size = _grid_size_before


# --- Fixture -----------------------------------------------------------------

## A loaded battle map inside a GameWorld-shaped root: { scene, map, loader, res }.
func _load_battle() -> Dictionary:
	var res := load(MAP_PATH) as MapResource
	var scene_root := Node3D.new()
	scene_root.name = "TestGameWorld"
	add_child_autofree(scene_root)

	var map_node := Node3D.new()
	map_node.name = "Map"
	scene_root.add_child(map_node)

	var loader := MapLoader.new()
	map_node.add_child(loader)
	loader.load_map(res, map_node)

	return { "scene": scene_root, "map": map_node, "loader": loader, "res": res }


## The same fixture, but mounted on the tree ROOT and installed as current_scene, which
## is the only shape [CameraController] can resolve "Map/Tiles" through (the engine also
## refuses a current_scene that is not a direct child of root). Torn down by after_each.
##
## The swap happens AFTER the map is loaded, on purpose: [method Unit._find_visual_manager]
## conjures the whole battle VISUAL stack under whatever current_scene is set when a unit
## enters the tree. This suite is about board geometry, so loading first keeps it from
## dragging in the HUD -- and from going red for a fault somewhere else in it.
func _load_battle_as_current_scene() -> Dictionary:
	var res := load(MAP_PATH) as MapResource
	var scene_root := Node3D.new()
	scene_root.name = "TestGameWorld"
	get_tree().root.add_child(scene_root)
	_mounted_scene = scene_root

	var map_node := Node3D.new()
	map_node.name = "Map"
	scene_root.add_child(map_node)

	var loader := MapLoader.new()
	map_node.add_child(loader)
	loader.load_map(res, map_node)

	get_tree().current_scene = scene_root
	return { "scene": scene_root, "map": map_node, "loader": loader, "res": res }


## Every node at or under [param node], at any depth.
func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = [node]
	for child in node.get_children():
		found.append_array(_descendants(child))
	return found


# --- It is mounted, and it is mounted in the right place ---------------------

func test_a_battle_map_gets_a_surround_outside_the_tile_container() -> void:
	var battle := _load_battle()
	var map_node: Node3D = battle["map"]

	var surround := map_node.get_node_or_null(SURROUND.NODE_NAME)
	assert_not_null(surround, "loading a battle map mounts the decorative surround")

	var tiles := map_node.get_node_or_null("Tiles")
	assert_not_null(tiles, "the playable tile container is still there")
	assert_null(tiles.get_node_or_null(SURROUND.NODE_NAME),
		"the surround is a SIBLING of Tiles, never inside it -- the camera fits Tiles' children")


func test_the_surround_can_be_switched_off_for_the_true_grid() -> void:
	# The Map Creator's editing view (and any test asserting on raw board geometry) needs
	# the bare board; this is the seam that gives it one.
	var res := load(MAP_PATH) as MapResource
	var scene_root := Node3D.new()
	add_child_autofree(scene_root)
	var map_node := Node3D.new()
	map_node.name = "Map"
	scene_root.add_child(map_node)
	var loader := MapLoader.new()
	map_node.add_child(loader)
	loader.surround_enabled = false
	loader.load_map(res, map_node)

	assert_null(map_node.get_node_or_null(SURROUND.NODE_NAME),
		"surround_enabled = false loads the board with no scenery at all")


# --- Zero board cells added --------------------------------------------------

func test_the_tile_container_holds_exactly_the_playable_cells() -> void:
	var battle := _load_battle()
	var res: MapResource = battle["res"]
	var tiles: Node = (battle["map"] as Node3D).get_node("Tiles")
	assert_eq(tiles.get_child_count(), res.width * res.height,
		"the board is still width x height tiles -- the surround contributed none of them")


func test_no_decor_cell_is_registered_as_terrain() -> void:
	if not CombatServices:
		pending("no CombatServices autoload")
		return
	var battle := _load_battle()
	var res: MapResource = battle["res"]

	assert_not_null(CombatServices.tile_at(Vector2i(0, 0)),
		"the board's own corner cell IS registered terrain")
	assert_null(CombatServices.tile_at(Vector2i(-1, -1)),
		"a ring cell diagonally off the corner is not terrain -- it is scenery")
	assert_null(CombatServices.tile_at(Vector2i(-1, 0)),
		"a ring cell directly west of the board edge is not terrain")
	assert_null(CombatServices.tile_at(Vector2i(res.width, res.height - 1)),
		"a ring cell directly east of the far board edge is not terrain")


func test_the_surround_carries_no_collider() -> void:
	var battle := _load_battle()
	var surround: Node = (battle["map"] as Node3D).get_node(SURROUND.NODE_NAME)
	var colliders: Array[Node] = []
	for node in _descendants(surround):
		if node is CollisionObject3D:
			colliders.append(node)
	assert_eq(colliders.size(), 0,
		"nothing in the surround can be hit by a physics ray, now or by a future picker")


# --- Perf: the scenery must not out-cost the board ---------------------------

func test_the_treeline_is_batched_instead_of_one_node_per_tree() -> void:
	# A tree per node would be ~4 MeshInstance3D each (trunk + three leaf blobs) --
	# hundreds of draw calls for decoration. Everything is merged or multimeshed, so the
	# whole surround is a handful of nodes however big the map is.
	var battle := _load_battle()
	var surround := (battle["map"] as Node3D).get_node(SURROUND.NODE_NAME) as MapSurround
	var planted: int = int(surround.layout["tree_count"])
	assert_gt(planted, 20, "a big forest map really does plant a treeline")

	var nodes: Array[Node] = _descendants(surround)
	assert_lt(nodes.size(), 12,
		"%d trees cost a handful of nodes, not one each (got %d nodes)" % [planted, nodes.size()])

	var batched: int = 0
	for node in nodes:
		if node is MultiMeshInstance3D:
			batched += 1
	assert_gt(batched, 0, "the trees are drawn through MultiMesh instances")


# --- Cursor / cell resolution at the border ----------------------------------

func test_border_adjacent_cells_still_resolve_through_the_live_picking_maths() -> void:
	# This is cursor.gd's _cell_under_mouse tail exactly: the ground-plane hit point is
	# handed to the SHARED Grid the loader just resized, then bounds-checked.
	var battle := _load_battle()
	var res: MapResource = battle["res"]
	assert_not_null(_grid, "the shared board Grid resource loaded")
	assert_eq(_grid.size, Vector3(res.width, 0, res.height),
		"the loader sized the shared grid to the PLAYABLE map, not to the surround")

	var near_corner: Vector3 = _grid.calculate_grid_coordinates(Vector3(1.0, 0.0, 1.0))
	assert_eq(near_corner, Vector3(0, 0, 0),
		"hovering the first board cell still resolves to cell (0,0)")
	assert_true(_grid.is_within_bounds(near_corner),
		"and it is still in bounds, so the cursor lands on it")

	var far_x: float = float(res.width - 1) * 2.0 + 1.0
	var far_z: float = float(res.height - 1) * 2.0 + 1.0
	var far_corner: Vector3 = _grid.calculate_grid_coordinates(Vector3(far_x, 0.0, far_z))
	assert_eq(far_corner, Vector3(res.width - 1, 0, res.height - 1),
		"the last board cell -- the one the ring hugs -- still resolves to itself")
	assert_true(_grid.is_within_bounds(far_corner),
		"the border-adjacent cell is selectable exactly as before")


func test_hovering_the_scenery_resolves_to_nothing_selectable() -> void:
	var battle := _load_battle()
	var res: MapResource = battle["res"]

	var west: Vector3 = _grid.calculate_grid_coordinates(Vector3(-1.0, 0.0, 1.0))
	assert_false(_grid.is_within_bounds(west),
		"a ring cell west of the board is out of bounds -- the cursor refuses it")

	var east_x: float = float(res.width) * 2.0 + 1.0
	var east: Vector3 = _grid.calculate_grid_coordinates(Vector3(east_x, 0.0, 1.0))
	assert_false(_grid.is_within_bounds(east),
		"a ring cell east of the board is out of bounds too -- picking cannot leave the board")


# --- Camera: the fit rect must not notice the surround -----------------------

func test_the_camera_fit_rect_is_identical_with_and_without_the_surround() -> void:
	var battle := _load_battle_as_current_scene()
	var map_node: Node3D = battle["map"]

	var cam := Camera3D.new()
	cam.set_script(CAMERA_SCRIPT)
	add_child_autofree(cam)

	assert_true(cam._compute_board_bounds(), "the camera found the board")
	var min_with: Vector2 = cam._board_min
	var max_with: Vector2 = cam._board_max
	var margin_with: float = cam._surround_pan_margin

	# Now take the scenery away and measure the same board again.
	var surround := map_node.get_node_or_null(SURROUND.NODE_NAME)
	assert_not_null(surround, "the surround was mounted before we removed it")
	map_node.remove_child(surround)
	surround.free()

	assert_true(cam._compute_board_bounds(), "the camera still finds the board")
	assert_eq(cam._board_min, min_with,
		"the fit rect's near corner is unchanged -- scenery never inflates the framing")
	assert_eq(cam._board_max, max_with,
		"the fit rect's far corner is unchanged either")
	assert_eq(cam._surround_pan_margin, 0.0,
		"with no surround the camera falls back to exactly the old pan clamp")
	assert_gt(margin_with, 0.0,
		"with a surround the player gets extra PAN slack to peek at the treeline")
	assert_lte(margin_with, cam.surround_pan_margin_max,
		"that slack is capped, so nobody can pan off into the void")


# --- Backdrop atmosphere ------------------------------------------------------

func test_the_battle_environment_carries_the_depth_fog() -> void:
	# Layer 3 of the fix: HEIGHT fog, so the dirt skirt and the backdrop plane below the
	# board fade into atmosphere while the play area itself stays crisp.
	#
	# Asserted on the scene FILE rather than by load()ing GameWorld.tscn: that scene pulls
	# in the whole battle HUD, so a compile error anywhere in game/ui would turn a fog
	# assertion into someone else's red test. The two halves below together prove the same
	# thing a load would -- the properties are authored, and they are real properties of
	# Environment (a misspelling here is the ONLY way this could ship broken).
	var file := FileAccess.open("res://game/world/GameWorld.tscn", FileAccess.READ)
	assert_not_null(file, "GameWorld.tscn is readable")
	if file == null:
		return
	var text: String = file.get_as_text()
	file.close()

	var authored := {
		"fog_enabled = true": "fog is on, so the void below the board reads as depth",
		"fog_height_density = 0.14":
			"it is HEIGHT fog -- it thickens below the board, not across the play area",
		"fog_density = 0.0015":
			"distance fog stays negligible, so the board's own colours are not washed out",
		"fog_sky_affect = 0.0":
			"the sky is left alone -- ground atmosphere, not a lighting restyle",
	}
	for line in authored:
		assert_true(text.contains(line),
			"%s (expected \"%s\" in the WorldEnvironment)" % [authored[line], line])

	# And every one of those keys is a genuine Environment property, so the scene parses.
	var probe: Environment = Environment.new()
	var known: Dictionary = {}
	for prop in probe.get_property_list():
		known[String(prop["name"])] = true
	for key in ["fog_enabled", "fog_density", "fog_height", "fog_height_density",
			"fog_sky_affect", "fog_light_color", "fog_light_energy", "fog_sun_scatter"]:
		assert_true(known.has(key),
			"Environment.%s exists in this engine build -- the scene will parse clean" % key)


# --- Teardown ----------------------------------------------------------------

func test_the_surround_is_freed_with_the_map() -> void:
	var battle := _load_battle()
	var map_node: Node3D = battle["map"]
	var loader: MapLoader = battle["loader"]
	var surround := map_node.get_node_or_null(SURROUND.NODE_NAME)
	assert_not_null(surround, "there is a surround to tear down")

	loader.clear_current_map()

	assert_null(map_node.get_node_or_null(SURROUND.NODE_NAME),
		"clearing the map takes the scenery with it -- no orphaned ring survives a reload")
	assert_null(loader.map_surround, "and the loader drops its reference to it")


func test_reloading_a_map_never_stacks_two_surrounds() -> void:
	var battle := _load_battle()
	var map_node: Node3D = battle["map"]
	var loader: MapLoader = battle["loader"]
	var res: MapResource = battle["res"]

	loader.load_map(res, map_node)

	var count: Array[int] = [0]
	for child in map_node.get_children():
		if child.name == SURROUND.NODE_NAME:
			count[0] += 1
	assert_eq(count[0], 1,
		"a second load replaces the ring rather than laying another one on top of it")
