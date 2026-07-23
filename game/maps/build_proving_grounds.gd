extends SceneTree

## Headless builder for the "Proving Grounds" combat-oriented 2-player map (T15).
##
## Run with:
##   godot --headless --path . -s res://game/maps/build_proving_grounds.gd
##
## Mirrors the structure of [code]build_sample_map.gd[/code] (which built the
## "Skirmish Arena"): uses [MapMakerModel] to paint a point-symmetric arena and
## a neutral central throne, then saves the result to
## [code]res://game/maps/resources/proving_grounds.tres[/code].
##
## Unlike the skirmish arena, every spawn here is character-backed (see
## [method MapResource.set_character_spawn_at_position]). [MapMakerModel]'s
## spawn API (place_spawn / to_map_resource) predates the character system and
## does not carry a "character_id" field through, so spawns are applied
## directly to the [MapResource] produced by [method MapMakerModel.to_map_resource]
## rather than routed through the model - the model owns tiles and the throne
## objective only. This is a true MIRROR MATCH: both players field the same five
## heroes at point-symmetric positions, so identical teams meet on symmetric
## terrain - the point of a "proving grounds" map is a clean balance testbed.
##
## After saving, the resource is re-loaded (fresh from disk, plus a live
## [MapLoader] build into a throwaway [Node3D]) and a validation report is
## printed so the run doubles as a self-check. Exit code is 0 on success, 1 on
## any validation failure.

## Grid width in cells. 17 (odd) is used instead of 16 so the map has a single
## true centre column, letting the throne sit exactly on the axis of symmetry
## (same reasoning [code]build_sample_map.gd[/code] uses for its 15x11 grid).
const MAP_WIDTH := 17
## Grid height in cells. 13 (odd) gives a single true centre row for the throne.
const MAP_HEIGHT := 13
## Destination for the generated map resource.
const OUTPUT_PATH := "res://game/maps/resources/proving_grounds.tres"

## Centre cell (8, 6) - lies on both axes of symmetry; hosts the throne.
const CENTRE := Vector2i(8, 6)

## Columns left open (no WALL) in the two lane-divider rows below, carving out
## three approach lanes into the throne band: a west flank lane (x=2..3), a
## narrow centre lane (x=8, directly above/below the throne), and an east
## flank lane (x=13..14). This list is deliberately a palindrome about x=8 so
## mirroring it produces the same set of gaps on both divider rows.
const LANE_GAP_XS: Array = [2, 3, 8, 13, 14]


## Mirrors a cell through the map centre (180-degree point symmetry).
## Guarantees every feature placed for player 0 has an identical counterpart for
## player 1, so neither side gains a positional or terrain advantage.
func _mirror(pos: Vector2i) -> Vector2i:
	return Vector2i((MAP_WIDTH - 1) - pos.x, (MAP_HEIGHT - 1) - pos.y)


## Paints [param tile_type] at [param pos] and at its mirror image.
func _paint_symmetric(model: MapMakerModel, pos: Vector2i, tile_type: String) -> void:
	model.paint_tile(pos, tile_type)
	model.paint_tile(_mirror(pos), tile_type)


func _initialize() -> void:
	var model := MapMakerModel.new(MAP_WIDTH, MAP_HEIGHT)
	model.map_name = "Proving Grounds"
	model.description = "A 17x13 point-symmetric combat arena: three walled approach lanes (west flank, centre, east flank) converge on a throne boxed in by a lava patch (north/south) and water (east/west). A true mirror match -- both sides field the full hero roster (Vineweave, Blightcap, Petalfang, Tree Grunt, Mycothrall) at symmetric positions, so it's a clean testbed for unit-vs-unit balance."
	model.author = "Map Maker (build_proving_grounds.gd)"
	model.max_players = 2

	# --- Wall lane-dividers -------------------------------------------------
	# Two horizontal wall rows (y=4 and its mirror y=8) split the arena into a
	# top lane, a central throne band (rows 5-7), and a bottom lane. Gaps at
	# LANE_GAP_XS create three chokepoints units must funnel through to reach
	# the throne band: a west flank lane, a narrow centre lane, and an east
	# flank lane.
	for x in range(MAP_WIDTH):
		if x in LANE_GAP_XS:
			continue
		_paint_symmetric(model, Vector2i(x, 4), "WALL")

	# Cover pillars just inside the flank lane mouths, giving units something
	# to duck behind once they cross into the throne band.
	_paint_symmetric(model, Vector2i(3, 6), "WALL")  # mirror -> (13, 6)

	# --- Lava hazard patch ---------------------------------------------------
	# A 3-wide lava patch directly above the throne (mirrored to directly
	# below it) guards the centre lane: pushing straight down column 8 means
	# stepping around fire, funnelling attackers out to the flanks instead.
	for x in [7, 8, 9]:
		_paint_symmetric(model, Vector2i(x, 5), "LAVA")  # mirrors -> row 7

	# --- Water hazard ---------------------------------------------------------
	# Water flanking the throne to the east/west closes off the diagonal
	# shortcuts, leaving only the two cells directly beside the throne
	# ((7,6) and (9,6)) as dry, hazard-free approach tiles.
	_paint_symmetric(model, Vector2i(6, 6), "WATER")  # mirror -> (10, 6)

	# A small decorative pool in each far corner for visual/tactical variety
	# away from the centre (auto-mirrored top-left <-> bottom-right).
	for cell in [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2)]:
		_paint_symmetric(model, cell, "WATER")

	# --- Objective -----------------------------------------------------------
	# Neutral throne at the exact centre supports a capture-the-throne win.
	model.set_objective(CENTRE, "THRONE", -1)

	# --- Build the MapResource, then apply character spawns directly --------
	# MapMakerModel.place_spawn()/to_map_resource() predate character_id and
	# don't carry it through, so spawns are written straight onto the
	# resulting MapResource via set_character_spawn_at_position - the
	# authoritative, character-aware API documented on MapResource.gd.
	var res := model.to_map_resource()
	res.difficulty = "Hard"  # a boss-guarded throne on the AI side warrants the harder rating
	_place_spawns(res)

	# --- Save ------------------------------------------------------------
	var saved := _save_map_resource(res, OUTPUT_PATH)
	if not saved:
		push_error("[build_proving_grounds] Failed to save map to %s" % OUTPUT_PATH)
		quit(1)
		return

	print("[build_proving_grounds] Saved map to %s" % OUTPUT_PATH)

	var ok := _validate(model)
	quit(0 if ok else 1)


## Places every character-backed spawn for both players directly onto
## [param res]. This is a true MIRROR MATCH: player 0 (human) fields the entire
## playable hero roster on the west edge, and player 1 (AI) gets the exact same
## five heroes at point-mirrored positions. Identical teams, symmetric terrain -
## the cleanest testbed for unit-vs-unit balance.
const MIRROR_SQUAD := [
	{"cell": Vector2i(1, 6), "id": "vineweave"},    # vine-armed frontliner (lead)
	{"cell": Vector2i(1, 5), "id": "blightcap"},    # leaping poison harasser
	{"cell": Vector2i(1, 7), "id": "petalfang"},    # thorned control striker
	{"cell": Vector2i(1, 9), "id": "tree_grunt"},   # bark-skinned bruiser
	{"cell": Vector2i(1, 10), "id": "mycothrall"},  # parasite caster (Hard+ gate)
]

func _place_spawns(res: MapResource) -> void:
	# Player 0 (human) on the west edge; player 1 (AI) at each cell's point-mirror.
	for entry in MIRROR_SQUAD:
		var cell: Vector2i = entry["cell"]
		var id: String = entry["id"]
		res.set_character_spawn_at_position(cell, 0, id, "WARRIOR")
		res.set_character_spawn_at_position(_mirror(cell), 1, id, "WARRIOR")


## Saves [param res] to [param path], creating the destination directory if
## needed. Mirrors [method MapMakerModel.save_to_file]'s own behaviour, since
## that helper can't be used here (it rebuilds the MapResource from the model
## internally, which would drop the character_id spawns applied above).
func _save_map_resource(res: MapResource, path: String) -> bool:
	if path.is_empty():
		return false
	var dir := path.get_base_dir()
	if not dir.is_empty() and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	return ResourceSaver.save(res, path) == OK


## Reloads the saved resource and reports whether it is a clean, playable map.
## Returns true only if every check passes.
func _validate(source_model: MapMakerModel) -> bool:
	print("\n==== VALIDATION ====")
	var ok := true

	# 1. Load as a MapResource for dimension / spawn / rule inspection. This is
	# the authoritative load path (character_id lives only on the MapResource
	# spawn dicts, not the MapMakerModel, per the note above).
	var res := load(OUTPUT_PATH) as MapResource
	if res == null:
		push_error("[validate] Loaded resource is not a MapResource")
		return false

	# 2. Dimensions.
	print("Name:        %s" % res.map_name)
	print("Dimensions:  %dx%d (expected %dx%d)" % [res.width, res.height, MAP_WIDTH, MAP_HEIGHT])
	if res.width != MAP_WIDTH or res.height != MAP_HEIGHT:
		push_error("[validate] Dimension mismatch")
		ok = false

	# 3. Tile composition.
	var counts := {}
	for tile in res.tile_layout:
		var t: String = tile.get("tile_type", "NORMAL")
		counts[t] = counts.get(t, 0) + 1
	print("Tile count:  %d (expected %d)" % [res.tile_layout.size(), MAP_WIDTH * MAP_HEIGHT])
	print("Composition: %s" % str(counts))
	if res.tile_layout.size() != MAP_WIDTH * MAP_HEIGHT:
		push_error("[validate] Tile layout is not fully populated")
		ok = false

	# 4. Spawns per player, including character_id and boss status.
	var p0 := res.get_total_units_for_player(0)
	var p1 := res.get_total_units_for_player(1)
	print("Spawns:      player0=%d  player1=%d" % [p0, p1])
	if p0 < 2 or p1 < 2:
		push_error("[validate] Each player needs at least 2 spawns")
		ok = false

	var boss_found := false
	for spawn_data in res.unit_spawns:
		var pos: Vector2i = spawn_data.get("position", Vector2i(-1, -1))
		var player_id = spawn_data.get("player_id", -1)
		var character_id: String = spawn_data.get("character_id", "")
		if character_id.is_empty():
			push_error("[validate] Spawn at %s has no character_id" % str(pos))
			ok = false
			continue
		var character := CharacterLibrary.get_character(character_id)
		if character == null:
			push_error("[validate] character_id '%s' does not resolve via CharacterLibrary" % character_id)
			ok = false
			continue
		var is_boss: bool = character.is_boss
		if is_boss:
			boss_found = true
			if player_id != 1:
				push_error("[validate] Boss '%s' must belong to player 1 (AI side), found player_id=%d" % [character_id, player_id])
				ok = false
		print("  pos=%s player=%d character_id=%s is_boss=%s" % [str(pos), player_id, character_id, str(is_boss)])
	if not boss_found:
		push_error("[validate] No boss (is_boss=true) unit found among spawns")
		ok = false

	# 5. Throne / objective presence, decoded via a fresh MapMakerModel load
	# (tiles/objectives round-trip cleanly through the model; only spawn
	# character_id does not, per the note on _place_spawns).
	var reloaded_model := MapMakerModel.load_from_file(OUTPUT_PATH)
	if reloaded_model == null:
		push_error("[validate] MapMakerModel.load_from_file returned null")
		ok = false
	else:
		var thrones := 0
		var throne_cell := Vector2i(-1, -1)
		for y in range(res.height):
			for x in range(res.width):
				var obj := reloaded_model.get_objective(Vector2i(x, y))
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

	# 6. MapResource's own validator.
	var report: Dictionary = res.validate_map()
	print("validate_map(): valid=%s issues=%s warnings=%s" % [
		str(report.get("valid", false)),
		str(report.get("issues", [])),
		str(report.get("warnings", [])),
	])
	if not report.get("valid", false):
		push_error("[validate] MapResource.validate_map() reported the map invalid")
		ok = false

	# 7. Full live load through MapLoader (strongest end-to-end check).
	ok = _validate_via_maploader(res) and ok

	print("==== RESULT: %s ====" % ("PASS" if ok else "FAIL"))
	return ok


## Instantiates a real [MapLoader], builds the map into a throwaway [Node3D],
## and confirms it loads without emitting a failure and that both player
## containers end up with the expected unit counts. Non-fatal issues are logged.
func _validate_via_maploader(res: MapResource) -> bool:
	var loader := MapLoader.new()
	get_root().add_child(loader)

	var failed := false
	var fail_msg := ""
	loader.map_load_failed.connect(func(msg: String):
		failed = true
		fail_msg = msg)

	var map_root := Node3D.new()
	map_root.name = "ProvingGroundsRoot"
	get_root().add_child(map_root)

	var loaded: bool = loader.load_map(res, map_root)
	var tiles_node := map_root.get_node_or_null("Tiles")
	var tile_children := tiles_node.get_child_count() if tiles_node != null else 0

	var player1_node := map_root.get_node_or_null("Player1")  # player_id 0
	var player2_node := map_root.get_node_or_null("Player2")  # player_id 1
	var p0_units := player1_node.get_child_count() if player1_node != null else 0
	var p1_units := player2_node.get_child_count() if player2_node != null else 0

	print("MapLoader.load_map: returned=%s  failed_signal=%s  tiles_built=%d  player0_units=%d  player1_units=%d" % [
		str(loaded), str(failed), tile_children, p0_units, p1_units])
	if failed:
		push_error("[validate] MapLoader failure: %s" % fail_msg)

	var maploader_ok := loaded and not failed and p0_units == 3 and p1_units == 4
	if p0_units != 3 or p1_units != 4:
		push_error("[validate] Unexpected unit counts: player0=%d (expected 3) player1=%d (expected 4)" % [p0_units, p1_units])

	map_root.queue_free()
	loader.queue_free()
	return maploader_ok
