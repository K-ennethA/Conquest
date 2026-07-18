extends SceneTree

## Headless builder for "Elemental Crossroads", a medium 2-player combat
## testbed built to showcase terrain tile effects.
##
## Run with:
##   godot --headless --path . -s res://game/maps/build_elemental_crossroads.gd
##
## Mirrors the structure of [code]build_proving_grounds.gd[/code]: uses
## [MapMakerModel] to paint a point-symmetric arena, then saves the result to
## [code]res://game/maps/resources/elemental_crossroads.tres[/code]. Unlike
## Proving Grounds this map carries no throne objective and no boss - it is a
## plain, balanced 3v3 skirmish whose whole point is to put a unit on every
## kind of terrain effect the tile-effect pipeline actually wires up live:
##
##   * LAVA tiles      -> CombatServices resolves canonical id "lava" to
##                        res://game/tiles/effects/resources/fire.tres
##                        (burns any occupant each turn start).
##   * WATER tiles     -> canonical id "water" resolves to
##                        res://game/tiles/effects/resources/empowering_water.tres
##                        (attack buff, gated to aquatic-tagged units).
##   * SACRED_GROUND    -> canonical id "sacred_ground" resolves to
##     tiles              res://game/tiles/effects/resources/fortify.tres
##                        (defense buff + "fortified" rule flag) IF the tile
##                        gets registered with CombatServices as a live
##                        TileResource. See the NOTE below - this map paints
##                        SACRED_GROUND the same way the existing
##                        create_default_maps.gd sample already does, but that
##                        registration currently depends on MapLoader's
##                        built-in tile_type->TileResource table, which today
##                        only covers NORMAL/GRASS/PLAINS/WATER/WALL/LAVA (see
##                        MapLoader._resolve_tile_resource). Painting the tiles
##                        here is still correct, forward-compatible authoring
##                        - it is the same pattern already shipped elsewhere in
##                        this codebase - but flagged in this build's report so
##                        whoever owns MapLoader/CombatServices can extend that
##                        table (or add a sacred_ground TileResource) if live
##                        fortify activation is desired. Nothing in this script
##                        touches MapLoader.gd or CombatServices.gd.
##
## After saving, the resource is re-loaded (fresh from disk, plus a live
## [MapLoader] build into a throwaway [Node3D]) and a validation report is
## printed so the run doubles as a self-check. Exit code is 0 on success, 1 on
## any validation failure.

## Grid width in cells. 13 (odd) gives a single true centre column so the
## fortify plaza and its flanking pillars sit exactly on the axis of symmetry
## (same reasoning [code]build_proving_grounds.gd[/code] uses).
const MAP_WIDTH := 13
## Grid height in cells. 9 (odd) gives a single true centre row.
const MAP_HEIGHT := 9
## Destination for the generated map resource.
const OUTPUT_PATH := "res://game/maps/resources/elemental_crossroads.tres"

## Centre cell (6, 4) - lies on both axes of symmetry; centre of the fortify plaza.
const CENTRE := Vector2i(6, 4)


## Mirrors a cell through the map centre (180-degree point symmetry).
## Guarantees every hazard/feature placed on one side has an identical
## counterpart on the other, so neither player gains a positional advantage.
func _mirror(pos: Vector2i) -> Vector2i:
	return Vector2i((MAP_WIDTH - 1) - pos.x, (MAP_HEIGHT - 1) - pos.y)


## Paints [param tile_type] at [param pos] and at its mirror image.
func _paint_symmetric(model: MapMakerModel, pos: Vector2i, tile_type: String) -> void:
	model.paint_tile(pos, tile_type)
	model.paint_tile(_mirror(pos), tile_type)


func _initialize() -> void:
	var model := MapMakerModel.new(MAP_WIDTH, MAP_HEIGHT)
	model.map_name = "Elemental Crossroads"
	model.description = "A 13x9 point-symmetric combat testbed built to showcase terrain effects: twin lava fields scorch anything that lingers, twin tidewater pools empower aquatic units, and a fortified shrine holds the centre chokepoint, flanked by a pair of stone pillars. Two balanced 3-unit squads spawn on opposite flanks and must fight through the hazards to contest the middle."
	model.author = "Map Maker (build_elemental_crossroads.gd)"
	model.max_players = 2

	# --- Fortify plaza --------------------------------------------------------
	# A 3x3 SACRED_GROUND shrine sits dead centre, the natural chokepoint both
	# squads have to fight over. Painted via the same tile_type-string pattern
	# already used by game/maps/create_default_maps.gd for its "healing tile" -
	# see the class doc comment above for the live-activation caveat.
	for pos in [Vector2i(5, 3), Vector2i(6, 3), Vector2i(7, 3), Vector2i(5, 4), CENTRE]:
		_paint_symmetric(model, pos, "SACRED_GROUND")

	# A single stone pillar guards each flank mouth of the plaza (west/east),
	# forcing a straight-line push through the centre to route around cover -
	# same "pillars just inside the approach" idea build_proving_grounds.gd
	# uses, scaled down for this more open map.
	_paint_symmetric(model, Vector2i(4, 4), "WALL")  # mirror -> (8, 4)

	# --- Lava hazard fields -----------------------------------------------------
	# A 2x2 scorched patch north-west of centre (mirrored south-east) - LAVA is
	# one of MapLoader's built-in tile types, so it registers a real TileResource
	# and the "fire" TileEffectResource (game/tiles/effects/resources/fire.tres)
	# actually burns any unit that ends a turn standing on it.
	for pos in [Vector2i(2, 1), Vector2i(3, 1), Vector2i(2, 2), Vector2i(3, 2)]:
		_paint_symmetric(model, pos, "LAVA")  # mirrors -> (10,7) (9,7) (10,6) (9,6)

	# --- Water hazard/empowerment pools -----------------------------------------
	# A 2x2 pool north-east of centre (mirrored south-west) - WATER is also a
	# built-in tile type, so it registers deep_water.tres and the "empowering_water"
	# TileEffectResource (attack buff gated to aquatic-tagged units) actually
	# applies to any aquatic unit standing in it.
	for pos in [Vector2i(9, 0), Vector2i(10, 0), Vector2i(9, 1), Vector2i(10, 1)]:
		_paint_symmetric(model, pos, "WATER")  # mirrors -> (3,8) (2,8) (3,7) (2,7)

	# --- Build the MapResource, then apply character spawns directly ----------
	# MapMakerModel.place_spawn()/to_map_resource() predate character_id and
	# don't carry it through, so spawns are written straight onto the
	# resulting MapResource via set_character_spawn_at_position - the
	# authoritative, character-aware API documented on MapResource.gd.
	var res := model.to_map_resource()
	res.difficulty = "Normal"  # balanced skirmish, no boss - a showcase/test map, not an encounter
	_place_spawns(res)

	# --- Save --------------------------------------------------------------
	var saved := _save_map_resource(res, OUTPUT_PATH)
	if not saved:
		push_error("[build_elemental_crossroads] Failed to save map to %s" % OUTPUT_PATH)
		quit(1)
		return

	print("[build_elemental_crossroads] Saved map to %s" % OUTPUT_PATH)

	var ok := _validate(model)
	quit(0 if ok else 1)


## Places every character-backed spawn for both players directly onto
## [param res]. Player 0 (west flank) and player 1 (east flank) each get a
## balanced 3-character squad (warrior/archer/support-or-mage) at mirrored
## positions - a symmetric skirmish, deliberately with no boss and no
## imbalance (unlike Proving Grounds), since this map's job is to showcase
## tile effects rather than stage an encounter.
func _place_spawns(res: MapResource) -> void:
	# Player 0 (west edge, column x=1).
	res.set_character_spawn_at_position(Vector2i(1, 3), 0, "sable_quickarrow", "ARCHER")   # ranged sharpshooter
	res.set_character_spawn_at_position(Vector2i(1, 4), 0, "torvald_ironhide", "WARRIOR")  # bruiser tank
	res.set_character_spawn_at_position(Vector2i(1, 5), 0, "callan_brightvow", "SUPPORT")  # cleric support

	# Player 1 (east edge, column x=11) - mirror image of player 0's rows.
	res.set_character_spawn_at_position(Vector2i(11, 3), 1, "wren_fleetfoot", "ARCHER")     # fast skirmisher
	res.set_character_spawn_at_position(Vector2i(11, 4), 1, "mabel_bulwark", "WARRIOR")     # guardian tank
	res.set_character_spawn_at_position(Vector2i(11, 5), 1, "ysolde_emberwynn", "MAGE")     # AoE mage


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

	# 1. Load as a MapResource for dimension / spawn / rule inspection.
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

	# 3. Tile composition - confirm every showcased effect terrain is present.
	var counts := {}
	for tile in res.tile_layout:
		var t: String = tile.get("tile_type", "NORMAL")
		counts[t] = counts.get(t, 0) + 1
	print("Tile count:  %d (expected %d)" % [res.tile_layout.size(), MAP_WIDTH * MAP_HEIGHT])
	print("Composition: %s" % str(counts))
	if res.tile_layout.size() != MAP_WIDTH * MAP_HEIGHT:
		push_error("[validate] Tile layout is not fully populated")
		ok = false
	for required_type in ["LAVA", "WATER", "SACRED_GROUND", "WALL", "NORMAL"]:
		if counts.get(required_type, 0) <= 0:
			push_error("[validate] Expected at least one %s tile" % required_type)
			ok = false

	# 4. Spawns per player, including character_id resolution.
	var p0 := res.get_total_units_for_player(0)
	var p1 := res.get_total_units_for_player(1)
	print("Spawns:      player0=%d  player1=%d" % [p0, p1])
	if p0 != 3 or p1 != 3:
		push_error("[validate] Expected exactly 3 spawns per player (balanced 3v3)")
		ok = false

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
		print("  pos=%s player=%d character_id=%s is_boss=%s" % [str(pos), player_id, character_id, str(character.is_boss)])

	# 5. MapResource's own validator.
	var report: Dictionary = res.validate_map()
	print("validate_map(): valid=%s issues=%s warnings=%s" % [
		str(report.get("valid", false)),
		str(report.get("issues", [])),
		str(report.get("warnings", [])),
	])
	if not report.get("valid", false):
		push_error("[validate] MapResource.validate_map() reported the map invalid")
		ok = false

	# 6. Full live load through MapLoader (strongest end-to-end check).
	ok = _validate_via_maploader(res) and ok

	print("==== RESULT: %s ====" % ("PASS" if ok else "FAIL"))
	return ok


## Instantiates a real [MapLoader], builds the map into a throwaway [Node3D],
## and confirms it loads without emitting a failure and that both player
## containers end up with the expected unit counts. Non-fatal issues are logged.
func _validate_via_maploader(res: MapResource) -> bool:
	# Load the script explicitly rather than MapLoader.new(): in a `-s` SceneTree
	# script the global class_name may not be resolved at compile time.
	var loader = load("res://game/maps/MapLoader.gd").new()
	get_root().add_child(loader)

	var failed := false
	var fail_msg := ""
	loader.map_load_failed.connect(func(msg: String):
		failed = true
		fail_msg = msg)

	var map_root := Node3D.new()
	map_root.name = "ElementalCrossroadsRoot"
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

	var maploader_ok := loaded and not failed and p0_units == 3 and p1_units == 3
	if p0_units != 3 or p1_units != 3:
		push_error("[validate] Unexpected unit counts: player0=%d (expected 3) player1=%d (expected 3)" % [p0_units, p1_units])

	map_root.queue_free()
	loader.queue_free()
	return maploader_ok
