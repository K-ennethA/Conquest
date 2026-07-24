extends SceneTree

## Headless builder for the "Skirmish Arena" 2-player tactical map.
##
## Run with:
##   godot --headless --path . -s res://game/maps/build_sample_map.gd
##
## Uses [MapMakerModel] (the pure editing model behind the Map Maker tool) to
## paint a balanced, point-symmetric arena, place two mirrored spawn clusters,
## and drop a neutral central throne, then saves it to
## [code]res://game/maps/resources/skirmish_arena.tres[/code] via the model's own
## [method MapMakerModel.save_to_file].
##
## After saving it re-loads the resource (both through [method MapMakerModel.load_from_file]
## and a live [MapLoader]) and prints a validation report so the run doubles as a
## self-check. The process exit code is 0 on success, 1 on any validation failure.

## Grid width in cells. 15 (odd) is used instead of 14 so the map has a single
## true centre column, letting the throne sit exactly on the axis of symmetry.
const MAP_WIDTH := 15
## Grid height in cells. 11 (odd) gives a single true centre row for the throne.
const MAP_HEIGHT := 11
## Destination for the generated map resource.
const OUTPUT_PATH := "res://game/maps/resources/skirmish_arena.tres"

## Centre cell (7, 5) - lies on both axes of symmetry; hosts the throne.
const CENTRE := Vector2i(7, 5)


## Mirrors a cell through the map centre (180-degree point symmetry).
## Guarantees every feature placed for player 0 has an identical counterpart for
## player 1, so neither side gains a positional advantage.
func _mirror(pos: Vector2i) -> Vector2i:
	return Vector2i((MAP_WIDTH - 1) - pos.x, (MAP_HEIGHT - 1) - pos.y)


## Paints [param tile_type] at [param pos] and at its mirror image.
func _paint_symmetric(model: MapMakerModel, pos: Vector2i, tile_type: String) -> void:
	model.paint_tile(pos, tile_type)
	model.paint_tile(_mirror(pos), tile_type)


func _initialize() -> void:
	var model := MapMakerModel.new(MAP_WIDTH, MAP_HEIGHT)
	model.map_name = "Skirmish Arena"
	model.description = "A 15x11 point-symmetric 2-player arena: three horizontal lanes divided by walls, flanking water pools, a hazardous lava-guarded centre, and a neutral throne to capture."
	model.author = "Map Maker (build_sample_map.gd)"
	model.max_players = 2

	# --- Wall lane-dividers ------------------------------------------------
	# Two horizontal wall rows (y=3 and its mirror y=7) split the arena into a
	# top lane, a central throne band (rows 4-6), and a bottom lane. A gap at the
	# centre column (x=7) plus the open flanks (x<4) let units cross lanes.
	for x in [4, 5, 6, 8, 9, 10]:
		_paint_symmetric(model, Vector2i(x, 3), "WALL")

	# Cover pillars flanking the throne on the central approach lane.
	_paint_symmetric(model, Vector2i(5, 5), "WALL")  # mirror -> (9, 5)

	# --- Water obstacles ---------------------------------------------------
	# A 2x2 pool top-left (auto-mirrored bottom-right) slows flanking routes.
	for cell in [Vector2i(3, 1), Vector2i(4, 1), Vector2i(3, 2), Vector2i(4, 2)]:
		_paint_symmetric(model, cell, "WATER")
	# A smaller pool top-right (auto-mirrored bottom-left) for the other flank.
	for cell in [Vector2i(10, 1), Vector2i(11, 1)]:
		_paint_symmetric(model, cell, "WATER")

	# --- Lava hazard -------------------------------------------------------
	# Lava directly above/below the throne makes the straight central push
	# through column 7 costly, funnelling attackers around the cover pillars.
	_paint_symmetric(model, Vector2i(7, 4), "LAVA")  # mirror -> (7, 6)

	# --- Spawns (mirrored clusters of 3) -----------------------------------
	# Player 0 on the left edge, player 1 on the right edge, identical make-up
	# (2 warriors + 1 archer each) so the match is balanced.
	_place_spawn_pair(model, Vector2i(1, 5), "WARRIOR")  # front
	_place_spawn_pair(model, Vector2i(1, 4), "ARCHER")   # flank support
	_place_spawn_pair(model, Vector2i(1, 6), "WARRIOR")  # front

	# --- Objective ---------------------------------------------------------
	# Neutral throne at the exact centre supports a capture-the-throne win.
	model.set_objective(CENTRE, "THRONE", -1)

	# --- Save --------------------------------------------------------------
	var saved := model.save_to_file(OUTPUT_PATH)
	if not saved:
		push_error("[build_sample_map] Failed to save map to %s" % OUTPUT_PATH)
		quit(1)
		return

	print("[build_sample_map] Saved map to %s" % OUTPUT_PATH)

	var ok := _validate(model)
	quit(0 if ok else 1)


## Places a spawn for player 0 at [param pos] and the mirrored spawn for player 1.
func _place_spawn_pair(model: MapMakerModel, pos: Vector2i, unit_type: String) -> void:
	model.place_spawn(pos, 0, unit_type)
	model.place_spawn(_mirror(pos), 1, unit_type)


## Reloads the saved resource and reports whether it is a clean, playable map.
## Returns true only if every check passes.
func _validate(source_model: MapMakerModel) -> bool:
	print("\n==== VALIDATION ====")
	var ok := true

	# 1. Re-load through the model's own loader (round-trip check).
	var reloaded := MapMakerModel.load_from_file(OUTPUT_PATH)
	if reloaded == null:
		push_error("[validate] MapMakerModel.load_from_file returned null")
		return false

	# 2. Load as a MapResource for dimension / spawn / rule inspection.
	var res := load(OUTPUT_PATH) as MapResource
	if res == null:
		push_error("[validate] Loaded resource is not a MapResource")
		return false

	# 3. Dimensions.
	print("Name:        %s" % res.map_name)
	print("Dimensions:  %dx%d (expected %dx%d)" % [res.width, res.height, MAP_WIDTH, MAP_HEIGHT])
	if res.width != MAP_WIDTH or res.height != MAP_HEIGHT:
		push_error("[validate] Dimension mismatch")
		ok = false

	# 4. Tile composition.
	var counts := {}
	for tile in res.tile_layout:
		var t: String = tile.get("tile_type", "NORMAL")
		counts[t] = counts.get(t, 0) + 1
	print("Tile count:  %d (expected %d)" % [res.tile_layout.size(), MAP_WIDTH * MAP_HEIGHT])
	print("Composition: %s" % str(counts))
	if res.tile_layout.size() != MAP_WIDTH * MAP_HEIGHT:
		push_error("[validate] Tile layout is not fully populated")
		ok = false

	# 5. Spawns per player.
	var p0 := res.get_total_units_for_player(0)
	var p1 := res.get_total_units_for_player(1)
	print("Spawns:      player0=%d  player1=%d" % [p0, p1])
	print("  P0 cells:  %s" % str(res.get_player_spawn_positions(0)))
	print("  P1 cells:  %s" % str(res.get_player_spawn_positions(1)))
	if p0 < 2 or p1 < 2:
		push_error("[validate] Each player needs at least 2 spawns")
		ok = false
	if p0 != p1:
		push_error("[validate] Spawn counts are not balanced between players")
		ok = false

	# 6. Throne / objective presence (decoded by the model).
	var thrones := 0
	var throne_cell := Vector2i(-1, -1)
	for y in range(res.height):
		for x in range(res.width):
			var obj := reloaded.get_objective(Vector2i(x, y))
			if not obj.is_empty() and obj.get("marker_type", "") == "THRONE":
				thrones += 1
				throne_cell = Vector2i(x, y)
	print("Throne:      count=%d  cell=%s" % [thrones, str(throne_cell)])
	if thrones != 1:
		push_error("[validate] Expected exactly one throne objective")
		ok = false
	elif throne_cell != CENTRE:
		push_error("[validate] Throne is not at the map centre %s" % str(CENTRE))
		ok = false

	# 7. Symmetry sanity: source model tile/spawn/objective counts survived save.
	if reloaded.get_spawn_count() != source_model.get_spawn_count():
		push_error("[validate] Spawn count changed across save/load")
		ok = false

	# 8. MapResource's own validator.
	var report: Dictionary = res.validate_map()
	print("validate_map(): valid=%s issues=%s warnings=%s" % [
		str(report.get("valid", false)),
		str(report.get("issues", [])),
		str(report.get("warnings", [])),
	])
	if not report.get("valid", false):
		push_error("[validate] MapResource.validate_map() reported the map invalid")
		ok = false

	# 9. Full live load through MapLoader (strongest end-to-end check).
	ok = _validate_via_maploader(res) and ok

	print("==== RESULT: %s ====" % ("PASS" if ok else "FAIL"))
	return ok


## Instantiates a real [MapLoader], builds the map into a throwaway [Node3D],
## and confirms it loads without emitting a failure. Non-fatal issues are logged.
func _validate_via_maploader(res: MapResource) -> bool:
	var loader := MapLoader.new()
	get_root().add_child(loader)

	var failed := false
	var fail_msg := ""
	loader.map_load_failed.connect(func(msg: String):
		failed = true
		fail_msg = msg)

	var map_root := Node3D.new()
	map_root.name = "SkirmishArenaRoot"
	get_root().add_child(map_root)

	var loaded: bool = loader.load_map(res, map_root)
	var tiles_node := map_root.get_node_or_null("Tiles")
	var tile_children := tiles_node.get_child_count() if tiles_node != null else 0
	print("MapLoader.load_map: returned=%s  failed_signal=%s  tiles_built=%d" % [
		str(loaded), str(failed), tile_children])
	if failed:
		push_error("[validate] MapLoader failure: %s" % fail_msg)

	map_root.queue_free()
	loader.queue_free()
	return loaded and not failed
