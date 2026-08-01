extends GutTest

## Unit tests for MapMakerModel - the pure map-editing logic.
## Covers dimensions, paint/erase, bounds handling, spawns, objective markers,
## and MapResource serialization round-trips (in-memory and via .tres files).

var model: MapMakerModel

const TEST_SAVE_PATH := "user://test_mapmaker_roundtrip.tres"
const TEST_JSON_PATH := "user://maps/test_mapmaker_roundtrip.json"


func before_each():
	model = MapMakerModel.new(5, 5)


func after_each():
	model = null
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(TEST_SAVE_PATH)
	if FileAccess.file_exists(TEST_JSON_PATH):
		DirAccess.remove_absolute(TEST_JSON_PATH)


# --- Dimensions --------------------------------------------------------------
func test_default_dimensions():
	assert_eq(model.width, 5, "Default width should be 5")
	assert_eq(model.height, 5, "Default height should be 5")


func test_set_dimensions_clamps_to_minimum():
	model.set_dimensions(0, -3)
	assert_eq(model.width, 1, "Width should clamp to minimum 1")
	assert_eq(model.height, 1, "Height should clamp to minimum 1")


func test_resize_prunes_out_of_bounds_data():
	model.paint_tile(Vector2i(4, 4), "WALL")
	model.place_spawn(Vector2i(3, 4), 1)
	model.set_objective(Vector2i(4, 3), "THRONE", 0)
	model.set_dimensions(3, 3)
	assert_eq(model.get_painted_tile_count(), 0, "Out-of-bounds tiles pruned on resize")
	assert_eq(model.get_spawn_count(), 0, "Out-of-bounds spawns pruned on resize")
	assert_eq(model.get_objective_count(), 0, "Out-of-bounds objectives pruned on resize")


# --- Bounds ------------------------------------------------------------------
func test_is_in_bounds():
	assert_true(model.is_in_bounds(Vector2i(0, 0)), "Origin in bounds")
	assert_true(model.is_in_bounds(Vector2i(4, 4)), "Max cell in bounds")
	assert_false(model.is_in_bounds(Vector2i(-1, 0)), "Negative x out of bounds")
	assert_false(model.is_in_bounds(Vector2i(5, 0)), "x == width out of bounds")
	assert_false(model.is_in_bounds(Vector2i(0, 5)), "y == height out of bounds")


func test_paint_out_of_bounds_rejected():
	assert_false(model.paint_tile(Vector2i(9, 9), "LAVA"), "Painting out of bounds returns false")
	assert_eq(model.get_painted_tile_count(), 0, "No tile stored out of bounds")


func test_place_spawn_out_of_bounds_rejected():
	assert_false(model.place_spawn(Vector2i(-1, -1), 0), "Spawn out of bounds returns false")
	assert_eq(model.get_spawn_count(), 0, "No spawn stored out of bounds")


# --- Paint / Erase -----------------------------------------------------------
func test_paint_tile():
	assert_true(model.paint_tile(Vector2i(2, 2), "WATER", "res://foo.tres"), "Paint in bounds returns true")
	var tile := model.get_tile(Vector2i(2, 2))
	assert_eq(tile["tile_type"], "WATER", "Tile type stored")
	assert_eq(tile["tile_resource_path"], "res://foo.tres", "Tile resource path stored")


func test_paint_overwrites_same_cell():
	model.paint_tile(Vector2i(1, 1), "WATER")
	model.paint_tile(Vector2i(1, 1), "LAVA")
	assert_eq(model.get_painted_tile_count(), 1, "Same cell not duplicated")
	assert_eq(model.get_tile(Vector2i(1, 1))["tile_type"], "LAVA", "Latest paint wins")


func test_erase_tile():
	model.paint_tile(Vector2i(3, 3), "WALL")
	assert_true(model.erase_tile(Vector2i(3, 3)), "Erasing painted tile returns true")
	assert_eq(model.get_painted_tile_count(), 0, "Tile removed")
	assert_eq(model.get_tile(Vector2i(3, 3))["tile_type"], "NORMAL", "Erased cell defaults to NORMAL")


func test_erase_empty_cell_returns_false():
	assert_false(model.erase_tile(Vector2i(0, 0)), "Erasing empty cell returns false")


# --- Spawns ------------------------------------------------------------------
func test_place_and_remove_spawn():
	assert_true(model.place_spawn(Vector2i(0, 0), 1, "ARCHER"), "Placing spawn returns true")
	var spawn := model.get_spawn(Vector2i(0, 0))
	assert_eq(spawn["player_id"], 1, "Player id stored")
	assert_eq(spawn["unit_type"], "ARCHER", "Unit type stored")
	assert_true(model.remove_spawn(Vector2i(0, 0)), "Removing spawn returns true")
	assert_eq(model.get_spawn_count(), 0, "Spawn removed")


# --- Objectives --------------------------------------------------------------
func test_place_and_remove_objective():
	assert_true(model.set_objective(Vector2i(2, 2), "THRONE", 0), "Setting objective returns true")
	var obj := model.get_objective(Vector2i(2, 2))
	assert_eq(obj["marker_type"], "THRONE", "Marker type stored")
	assert_eq(obj["player_id"], 0, "Objective player id stored")
	assert_true(model.remove_objective(Vector2i(2, 2)), "Removing objective returns true")
	assert_eq(model.get_objective_count(), 0, "Objective removed")


# --- Serialization -----------------------------------------------------------
func test_to_map_resource_full_layout():
	var res := model.to_map_resource()
	assert_not_null(res, "MapResource produced")
	assert_eq(res.tile_layout.size(), 25, "Every cell written to layout (5x5)")
	assert_eq(res.width, 5, "Width copied")
	assert_eq(res.height, 5, "Height copied")


func test_to_map_resource_is_loadable_valid():
	# A map maker output should pass MapResource's own validation once spawns exist.
	model.map_name = "Round Trip Map"
	model.place_spawn(Vector2i(0, 0), 0)
	model.place_spawn(Vector2i(4, 4), 1)
	var res := model.to_map_resource()
	var validation := res.validate_map()
	assert_true(validation["valid"], "Produced map should validate: " + str(validation["issues"]))


func test_in_memory_round_trip():
	model.map_name = "RT"
	model.paint_tile(Vector2i(1, 2), "LAVA")
	model.place_spawn(Vector2i(0, 0), 0, "MAGE")
	model.set_objective(Vector2i(3, 3), "THRONE", 1)

	var res := model.to_map_resource()
	var restored: MapMakerModel = MapMakerModel.from_map_resource(res)

	assert_eq(restored.map_name, "RT", "Name round-trips")
	assert_eq(restored.get_tile(Vector2i(1, 2))["tile_type"], "LAVA", "Painted tile round-trips")
	assert_eq(restored.get_spawn(Vector2i(0, 0))["unit_type"], "MAGE", "Spawn round-trips")
	var obj := restored.get_objective(Vector2i(3, 3))
	assert_eq(obj["marker_type"], "THRONE", "Objective marker round-trips")
	assert_eq(obj["player_id"], 1, "Objective player id round-trips")


func test_file_round_trip():
	model.map_name = "File RT"
	model.paint_tile(Vector2i(2, 1), "WATER")
	model.set_objective(Vector2i(4, 0), "OBJECTIVE", 2)

	assert_true(model.save_to_file(TEST_SAVE_PATH), "Save to file succeeds")
	assert_true(FileAccess.file_exists(TEST_SAVE_PATH), "File written to disk")

	var loaded: MapMakerModel = MapMakerModel.load_from_file(TEST_SAVE_PATH)
	assert_not_null(loaded, "Loaded model not null")
	assert_eq(loaded.map_name, "File RT", "Name persisted through file")
	assert_eq(loaded.get_tile(Vector2i(2, 1))["tile_type"], "WATER", "Tile persisted through file")
	var obj := loaded.get_objective(Vector2i(4, 0))
	assert_eq(obj["marker_type"], "OBJECTIVE", "Objective persisted through file")


func test_load_from_missing_file_returns_null():
	var loaded: MapMakerModel = MapMakerModel.load_from_file("user://does_not_exist_mapmaker.tres")
	assert_null(loaded, "Loading a missing file returns null")


func test_objective_does_not_leak_into_special_rules_on_reload():
	model.set_objective(Vector2i(0, 0), "THRONE", 0)
	var res := model.to_map_resource()
	var restored: MapMakerModel = MapMakerModel.from_map_resource(res)
	var res2: MapResource = restored.to_map_resource()
	# The single objective should encode as exactly one special rule, not accumulate.
	assert_eq(res2.special_rules.size(), 1, "Objective encoded once, no duplication")


# --- Terrain-passability placement checks (can_place_unit) -------------------
# Uses an INJECTED tile_resolver (not the real TileCatalog / disk assets) so these
# stay pure, fast, and headless-safe -- see MapMakerModel.tile_resolver's doc comment.

## Fake resolver standing in for TileCatalog.find_by_id: "wall_stub" resolves to an
## impassable TileResource, "grass_stub" to a passable one, anything else to null (so
## the tile_type-family fallback in tile_dict_is_passable is exercised on a miss).
func _stub_tile_resolver(tile_id: String, _path: String) -> TileResource:
	if tile_id == "wall_stub":
		var wall := TileResource.new()
		wall.id = &"wall_stub"
		wall.tile_type = Tile.TileType.WALL
		wall.is_passable = false
		return wall
	if tile_id == "grass_stub":
		var grass := TileResource.new()
		grass.id = &"grass_stub"
		grass.tile_type = Tile.TileType.NORMAL
		grass.is_passable = true
		return grass
	return null


func test_can_place_unit_false_on_wall_tile_with_injected_resolver():
	model.tile_resolver = Callable(self, "_stub_tile_resolver")
	model.paint_tile(Vector2i(2, 2), "WALL", "", "wall_stub")
	assert_false(model.can_place_unit(Vector2i(2, 2)), "GROUND unit cannot be placed on a wall tile")


func test_can_place_unit_true_on_grass_tile_with_injected_resolver():
	model.tile_resolver = Callable(self, "_stub_tile_resolver")
	model.paint_tile(Vector2i(2, 2), "NORMAL", "", "grass_stub")
	assert_true(model.can_place_unit(Vector2i(2, 2)), "GROUND unit can be placed on a passable tile")


func test_can_place_unit_false_out_of_bounds():
	model.tile_resolver = Callable(self, "_stub_tile_resolver")
	assert_false(model.can_place_unit(Vector2i(-1, 0)), "out-of-bounds cell is never placeable")


func test_can_place_unit_default_cell_with_no_resolver_uses_tile_type_fallback():
	# No tile_resolver set: falls back to the coarse tile_type family (WALL only).
	model.paint_tile(Vector2i(0, 0), "WALL")  # no tile_id/path -> unresolvable -> family fallback
	assert_false(model.can_place_unit(Vector2i(0, 0)), "bare WALL tile_type is impassable via the fallback")
	model.paint_tile(Vector2i(1, 0), "NORMAL")
	assert_true(model.can_place_unit(Vector2i(1, 0)), "bare NORMAL tile_type is passable via the fallback")


func test_can_place_unit_non_ground_kind_ignores_blocked_terrain():
	# Flyers/hover aren't placeable from the Map Creator UI yet (see the class doc caveat
	# this mirrors), but the rule table already honours a non-GROUND kind: it should ignore
	# terrain the way MovementResolver's FLYING/PHASING pathing does.
	model.tile_resolver = Callable(self, "_stub_tile_resolver")
	model.paint_tile(Vector2i(2, 2), "WALL", "", "wall_stub")
	assert_true(model.can_place_unit(Vector2i(2, 2), CombatTypes.MovementKind.FLYING),
		"a FLYING unit ignores blocked terrain")


# --- Strict-mode validator backstop (terrain placement) -----------------------
# Uses REAL TileCatalog ids (stone_wall) since MapResource._append_terrain_placement_issues
# calls the shared passability rule with no resolver override, matching production.

func _has_issue_containing(issues: Array, needle: String) -> bool:
	for i in issues:
		if String(i).to_lower().contains(needle.to_lower()):
			return true
	return false


func test_strict_validate_flags_spawn_on_wall_tile():
	model.map_name = "Wall Spawn Test"
	model.paint_tile(Vector2i(2, 2), "WALL", "", "stone_wall")
	model.place_spawn(Vector2i(2, 2), 0)
	model.place_spawn(Vector2i(4, 4), 1)
	var res := model.to_map_resource()
	var validation := res.validate_map(true)
	assert_false(validation["valid"], "strict validation must reject a spawn placed on a wall tile")
	assert_true(_has_issue_containing(validation["issues"], "impassable"),
		"issue should call out the impassable placement: " + str(validation["issues"]))


func test_strict_validate_flags_objective_on_wall_tile():
	model.map_name = "Wall Objective Test"
	model.paint_tile(Vector2i(1, 1), "WALL", "", "stone_wall")
	model.set_objective(Vector2i(1, 1), "THRONE", 0)
	model.place_spawn(Vector2i(0, 0), 0)
	model.place_spawn(Vector2i(4, 4), 1)
	var res := model.to_map_resource()
	var validation := res.validate_map(true)
	assert_false(validation["valid"], "strict validation must reject an objective placed on a wall tile")
	assert_true(_has_issue_containing(validation["issues"], "impassable"),
		"issue should call out the impassable placement: " + str(validation["issues"]))


func test_non_strict_validate_does_not_check_terrain_placement():
	# Backwards-compat: the many non-strict callers (in-editor autosave, live-game load)
	# must keep behaving exactly as before -- terrain placement is a strict-only check.
	model.map_name = "Wall Spawn Non-Strict"
	model.paint_tile(Vector2i(2, 2), "WALL", "", "stone_wall")
	model.place_spawn(Vector2i(2, 2), 0)
	model.place_spawn(Vector2i(4, 4), 1)
	var res := model.to_map_resource()
	var validation := res.validate_map()
	assert_true(validation["valid"], "non-strict validation should not check terrain placement: " + str(validation.get("issues", [])))
