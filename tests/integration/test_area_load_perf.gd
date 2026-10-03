extends GutTest

## AREA TRAVEL PERFORMANCE GUARDS (docs/STORY_MODE.md "Area travel & loading"). Leaving Oakvale
## used to freeze the game for ~1-1.5 s: every tile rebuilt its procedural geometry in GDScript,
## each board cell was found by a linear scan of the layout, and nothing about the next area was
## prepared ahead. These checks are STRUCTURAL -- node budgets, cache hits, "no geometry computed
## on the main thread" -- so they catch the regression without a flaky wall-clock budget.

const Guard := preload("res://tests/helpers/global_state_guard.gd")
const StoryFixture := preload("res://tests/helpers/story_fixture.gd")
const OVERWORLD_SCENE := preload("res://game/overworld/OverworldScene.tscn")
const TEMP_DIR := "user://test_area_load_perf/"
const AREAS: Array[String] = ["oakvale", "oakvale_ruins", "mossway", "crownhaven", "woodland_town"]

## Scene nodes an overworld area may use per board cell (tiles + skirt + actors + UI). Measured
## at ~5.5-6.8 once tiles dropped their unused colliders / effect nodes (it was ~10 before).
const MAX_NODES_PER_CELL := 7.5
## Nodes one tile may carry: a plain tile is 4 (Tile, surface, LowPoly helper, its decor), a tree
## tile 9; the authored magma-vent scene (fissures, embers, rocks) is the heaviest at 12.
const MAX_NODES_PER_TILE := 12

var _guard
var _world: Node = null
var _prev_scene: Node = null


func before_each() -> void:
	_guard = Guard.new()
	_guard.set_setting("animations_enabled", false)
	StorySaveManager.set_save_dir(TEMP_DIR)
	Guard.rm_rf(TEMP_DIR)
	StoryController.end_session()
	StoryController.scene_changes_enabled = false


func after_each() -> void:
	_teardown()
	StoryController.prewarmer().finish(StoryController)
	StoryController.end_session()
	StoryController.scene_changes_enabled = true
	Guard.rm_rf(TEMP_DIR)
	StorySaveManager.set_save_dir(StorySaveManager.DEFAULT_SAVE_DIR)
	PortraitCache.reset()
	_guard.restore()
	await get_tree().process_frame


func _boot(area: String, cell: Vector3i = Cells.INVALID) -> OverworldController:
	if not StoryController.has_session():
		StoryController.new_journey(0)
		StoryFixture.past_opening(StoryController.state())
	var s: StoryState = StoryController.state()
	var a: OverworldAreaResource = StoryController.load_area(area)
	var at: Vector3i = cell if cell != Cells.INVALID else a.entry(a.entry_ids()[0])["cell"]
	if area != s.location_area():
		s.on_area_changed()
	s.set_location(area, at, "south")
	_teardown()
	var w: Node = OVERWORLD_SCENE.instantiate()
	_prev_scene = get_tree().current_scene
	get_tree().root.add_child(w)
	get_tree().current_scene = w
	_world = w
	await get_tree().process_frame
	return w as OverworldController


func _teardown() -> void:
	if _world != null and is_instance_valid(_world):
		get_tree().current_scene = _prev_scene
		_world.get_parent().remove_child(_world)
		_world.free()
	_world = null


func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c


# --- Board lookup ------------------------------------------------------------------------

func test_tile_lookup_matches_the_linear_scan_on_every_shipped_area() -> void:
	for id in AREAS:
		var map: MapResource = StoryController.load_area(id).terrain
		var lookup: Dictionary = map.build_tile_lookup()
		var mismatches := 0
		for x in map.width:
			for y in map.height:
				var p := Vector2i(x, y)
				if MapResource.tile_from_lookup(lookup, p) != map.get_tile_at_position(p):
					mismatches += 1
		assert_eq(mismatches, 0, "%s: the O(1) lookup answers exactly like get_tile_at_position" % id)


func test_tile_lookup_keeps_the_first_duplicate_entry_and_upper_floor_air() -> void:
	var map := MapResource.new()
	map.width = 3
	map.height = 3
	map.tile_layout = [
		{"position": Vector2i(1, 1), "tile_type": "WATER", "tile_resource_path": "", "tile_id": "a"},
		{"position": Vector2i(1, 1), "tile_type": "LAVA", "tile_resource_path": "", "tile_id": "b"},
	]
	var lookup: Dictionary = map.build_tile_lookup()
	assert_eq(MapResource.tile_from_lookup(lookup, Vector2i(1, 1)), map.get_tile_at_position(Vector2i(1, 1)),
		"first entry wins, like the scan")
	assert_eq(MapResource.tile_from_lookup(lookup, Vector2i(0, 0)), map.get_tile_at_position(Vector2i(0, 0)),
		"an empty ground cell is the default tile")
	assert_eq(MapResource.tile_from_lookup(lookup, Vector2i(0, 0), 1), {}, "an empty upper cell is air")


# --- Node budgets ------------------------------------------------------------------------------

func test_every_area_builds_within_its_node_budget() -> void:
	for id in AREAS:
		var ow := await _boot(id)
		assert_not_null(ow, "%s boots" % id)
		if ow == null:
			continue
		var cells: int = ow.area.width() * ow.area.height()
		var nodes := _count_nodes(ow)
		assert_lt(float(nodes) / float(cells), MAX_NODES_PER_CELL,
			"%s: %d nodes for %d cells stays under %.1f per cell" % [id, nodes, cells, MAX_NODES_PER_CELL])
		var floor0 := ow.get_node_or_null(^"Map/Tiles/Floor_0")
		assert_not_null(floor0, "%s has its tile floor" % id)
		if floor0 == null:
			continue
		var worst := 0
		var bodies := 0
		var effect_nodes := 0
		for t in floor0.get_children():
			worst = maxi(worst, _count_nodes(t))
			if t.get_node_or_null(^"StaticBody3D") != null:
				bodies += 1
			if t.get_node_or_null(^"EffectParticles") != null or t.get_node_or_null(^"EffectOverlay") != null:
				effect_nodes += 1
		assert_lte(worst, MAX_NODES_PER_TILE, "%s: no tile carries more than %d nodes" % [id, MAX_NODES_PER_TILE])
		assert_eq(bodies, 0, "%s: overworld tiles carry no physics collider (taps use the ground plane)" % id)
		assert_eq(effect_nodes, 0, "%s: effect particles / overlays are only built for a tile with an effect" % id)


func test_battle_boards_keep_their_tile_colliders() -> void:
	var map: MapResource = StoryController.load_area("mossway").terrain
	var root := Node3D.new()
	add_child_autofree(root)
	var ml := MapLoader.new()
	ml.surround_enabled = false
	ml.objective_markers_enabled = false
	root.add_child(ml)
	var map_root := Node3D.new()
	root.add_child(map_root)
	ml.current_map = map
	ml.map_root = map_root
	ml._create_map_containers()
	ml._load_tiles()
	var t := map_root.get_node_or_null(^"Tiles/Floor_0/Tile_3_3_0")
	assert_not_null(t, "the tile exists")
	if t != null:
		assert_not_null(t.get_node_or_null(^"StaticBody3D"), "battles still pick tiles with physics")
	CombatServices.clear()


# --- Neighbour prewarm ---------------------------------------------------------------------------

func test_the_next_area_is_prepared_while_you_walk_and_boots_without_rebuilding_geometry() -> void:
	TileMeshCache.clear()
	var ow := await _boot("oakvale")
	assert_not_null(ow, "Oakvale boots")
	var pw: AreaPrewarmer = StoryController.prewarmer()
	assert_true(pw.pending_areas().has("mossway"), "Oakvale's east exit queues the Mossway")
	# Walk around for a while: the prewarm runs one short step per frame.
	for i in 600:
		await get_tree().process_frame
		if not pw.is_busy() and not TileMeshCache.poll():
			break
	pw.finish(StoryController)
	assert_false(pw.is_busy(), "the prewarm finished")
	assert_true(StoryController.has_area_cached("mossway"), "the Mossway resource was loaded ahead")
	var before: int = TileMeshCache.main_thread_computes
	var moss := await _boot("mossway")
	assert_not_null(moss, "the Mossway boots")
	assert_eq(TileMeshCache.main_thread_computes, before,
		"a prewarmed area builds with NO tile geometry computed on the main thread")


func test_revisiting_an_area_reuses_its_tile_geometry() -> void:
	var ow := await _boot("mossway")
	assert_not_null(ow, "the Mossway boots")
	StoryController.prewarmer().enabled = false
	var before: int = TileMeshCache.main_thread_computes
	ow = await _boot("mossway")
	StoryController.prewarmer().enabled = true
	assert_eq(TileMeshCache.main_thread_computes, before, "the second visit computes no geometry")
	# The live tile's decor IS the cached mesh of its cell (built once, shared, not per load).
	var lp: LowPolyTileBuilder = null
	for t in ow.get_node(^"Map/Tiles/Floor_0").get_children():
		lp = t.get_node_or_null(^"LowPoly") as LowPolyTileBuilder
		if lp != null:
			break
	assert_not_null(lp, "a LowPoly tile")
	if lp != null:
		var key := TileMeshCache.key(TileMeshCache.KIND_LOWPOLY, int(lp.style),
			int(round(lp.global_position.x)), int(round(lp.global_position.z)))
		var cached: Dictionary = TileMeshCache.meshes_for(key, func() -> Dictionary: return {})
		assert_same((lp.get_node(^"Decor") as MeshInstance3D).mesh, cached["decor"],
			"the tile shows its cell's cached mesh")


func test_prewarmed_geometry_is_identical_to_geometry_built_inline() -> void:
	# The worker-thread batch and a tile's own build must produce the same arrays (a cached
	# mesh never changes what a tile looks like).
	for st in [LowPolyTileBuilder.Style.GRASS, LowPolyTileBuilder.Style.TALL_GRASS,
			LowPolyTileBuilder.Style.MEADOW, LowPolyTileBuilder.Style.TREE, LowPolyTileBuilder.Style.WALL]:
		var key := TileMeshCache.key(TileMeshCache.KIND_LOWPOLY, st, 17, 9)
		var batch: Dictionary = {}
		LowPolyTileBuilder._prewarm_batch([key], batch)
		var b := LowPolyTileBuilder.new()
		b.style = st
		b._kx = 17
		b._kz = 9
		var inline: Dictionary = b._compute_arrays()
		b.free()
		assert_eq(batch[key], inline, "style %d: worker arrays == inline arrays" % st)
	var pkey := TileMeshCache.key(TileMeshCache.KIND_PAVED, PavedTileBuilder.Style.FLAGSTONE, 7, 3, 0)
	var pbatch: Dictionary = {}
	PavedTileBuilder._prewarm_batch([pkey], pbatch)
	assert_eq(pbatch[pkey]["paving"], PavedTileBuilder.build_arrays(PavedTileBuilder.Style.FLAGSTONE, 7, 3, 0),
		"paving: worker arrays == inline arrays")


# --- World skirt / terrain mask caches --------------------------------------------------------

func test_terrain_mask_is_cached_by_content() -> void:
	var map: MapResource = StoryController.load_area("oakvale").terrain
	var a := TerrainMask.mask_for(map)
	assert_same(TerrainMask.mask_for(map), a, "the same map reuses its mask")
	var edited: MapResource = map.duplicate(true)
	edited.set_tile_at_position(Vector2i(0, 0), "WATER", "", "deep_water")
	assert_ne(TerrainMask.content_key(edited), TerrainMask.content_key(map), "an edit changes the key")


func test_world_skirt_data_is_cached_and_packs_transforms_like_multimesh() -> void:
	var map: MapResource = StoryController.load_area("mossway").terrain
	var d1: Dictionary = WorldSkirt.data_for(map)
	assert_same(WorldSkirt.data_for(map), d1, "the second load reuses the skirt")
	assert_gt(int(d1["tree_count"]), 100, "the skirt grows its forest")
	# MultiMesh TRANSFORM_3D buffer order: basis row 0, origin.x, row 1, origin.y, row 2, origin.z.
	var t := Transform3D(Basis(Vector3.UP, 0.7).scaled(Vector3(1.2, 1.2, 1.2)), Vector3(3, 4, 5))
	var buf := PackedFloat32Array()
	WorldSkirt.pack_xform(buf, t)
	assert_eq(buf.size(), WorldSkirt.FLOATS_PER_XFORM, "12 floats per instance")
	var back := Transform3D(Basis(Vector3(buf[0], buf[4], buf[8]), Vector3(buf[1], buf[5], buf[9]),
		Vector3(buf[2], buf[6], buf[10])), Vector3(buf[3], buf[7], buf[11]))
	assert_true(back.is_equal_approx(t), "the packed rows rebuild the transform")
