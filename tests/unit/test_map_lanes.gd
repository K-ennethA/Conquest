extends GutTest

## The push-mode geometry a MapResource carries: [code]lanes[/code] (ordered waypoint
## routes, player 0's end FIRST), [code]base_cells[/code] (player slot -> base cell) and
## [code]control_points[/code] (the unowned cells a mode lets a side claim and hold).
##
## The load-bearing property is BACKWARD COMPATIBILITY, exactly as it is for spawn points:
## every map that shipped before these fields existed declares neither, and has to keep
## validating, exporting and importing completely unchanged. The second is that a BROKEN
## declaration is rejected at the gate and QUIETLY -- a map is player-authored and shared,
## so an unwalkable lane must fail import rather than fault mid-match.

const TEMP_MAP_PATH := "user://test_map_lanes_roundtrip.tres"
## A shipped map known to pass the catalog-strict gate (see unit/test_kings_crossing.gd),
## used as the "authored before lanes existed" fixture.
const LEGACY_MAP_PATH := "res://game/maps/resources/kings_crossing.tres"

const LANE_A: Array[Vector2i] = [Vector2i(1, 1), Vector2i(5, 1), Vector2i(8, 8)]
const LANE_B: Array[Vector2i] = [Vector2i(1, 8), Vector2i(4, 9), Vector2i(8, 8)]
const POINTS: Array[Vector2i] = [Vector2i(4, 4), Vector2i(2, 7)]


func after_all() -> void:
	if FileAccess.file_exists(TEMP_MAP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_MAP_PATH))


# --- Fixtures ----------------------------------------------------------------

## A minimal VALID two-player map that declares no lanes and no bases -- the shape every
## map authored before these fields existed has.
func _legacy_map() -> MapResource:
	var m := MapResource.new()
	m.map_name = "Lane Fixture"
	m.width = 10
	m.height = 10
	# Empty Start slots: legitimate (filled at match setup) and they name no catalog asset,
	# so the fixture passes the strict gate without needing a painted tile layout.
	m.set_unit_spawn_at_position(Vector2i(1, 1), 0, "")
	m.set_unit_spawn_at_position(Vector2i(8, 8), 1, "")
	return m


## The same map with two lanes, both bases and two control points declared.
func _lane_map() -> MapResource:
	var m := _legacy_map()
	m.add_lane(LANE_A)
	m.add_lane(LANE_B)
	m.set_base_cell(0, Vector2i(1, 1))
	m.set_base_cell(1, Vector2i(8, 8))
	for point in POINTS:
		m.add_control_point(point)
	return m


## [param m] through a full JSON export/import round trip, or null when it was rejected.
func _json_round_trip(m: MapResource) -> MapResource:
	return MapResource.import_from_json(m.export_to_json(), true)


func _issues(m: MapResource) -> String:
	return "; ".join(m.validate_map().get("issues", []))


# --- Backward compatibility ---------------------------------------------------

func test_a_map_that_declares_nothing_reads_as_having_no_lanes() -> void:
	var m := _legacy_map()
	assert_eq(m.lane_count(), 0, "a map with no lanes declares none")
	assert_true(m.base_cells.is_empty(), "and no bases")
	assert_eq(m.control_point_count(), 0, "and no control points")
	assert_eq(m.get_lane(0), [] as Array[Vector2i], "reading a lane it has not got is empty, not an error")
	assert_eq(m.get_base_cell(0), Vector2i(-1, -1), "and so is reading a base it has not got")
	assert_eq(m.get_control_point(0), Vector2i(-1, -1),
		"and so is reading a control point it has not got")
	assert_false(m.has_control_point(Vector2i(1, 1)),
		"no cell on a map without control points is one")
	assert_true(m.validate_map(true).get("valid", false), "and it is still a valid map")


func test_every_shipped_map_still_declares_no_lanes() -> void:
	# The fields are additive: nothing that shipped before them may have acquired one.
	var checked: int = 0
	for path in MapLoader.get_available_maps(true):
		var m := load(path) as MapResource
		if m == null:
			continue
		checked += 1
		if path == "res://game/maps/resources/riftwood.tres":
			continue  # the one map authored WITH lanes
		assert_eq(m.lane_count(), 0, "%s declares no lanes" % path)
		assert_true(m.base_cells.is_empty(), "%s declares no base cells" % path)
		assert_eq(m.control_point_count(), 0, "%s declares no control points" % path)
	assert_gt(checked, 1, "the builtin map scan found maps to check")


func test_a_legacy_map_round_trips_through_json_unchanged() -> void:
	var original := load(LEGACY_MAP_PATH) as MapResource
	assert_not_null(original, "the legacy fixture map loads")
	var restored := _json_round_trip(original)
	assert_not_null(restored, "a map with no lanes still imports")
	assert_eq(restored.lane_count(), 0, "and comes back with no lanes")
	assert_true(restored.base_cells.is_empty(), "and no base cells")
	assert_eq(restored.control_point_count(), 0, "and no control points")
	assert_eq(restored.unit_spawns.size(), original.unit_spawns.size(),
		"the rest of the payload is untouched")


# --- Round trips --------------------------------------------------------------

func test_lanes_and_bases_survive_a_tres_round_trip() -> void:
	var m := _lane_map()
	assert_eq(ResourceSaver.save(m, TEMP_MAP_PATH), OK, "the fixture saves")
	var restored := load(TEMP_MAP_PATH) as MapResource
	assert_not_null(restored, "and loads back")
	assert_eq(restored.lane_count(), 2, "both lanes came back")
	assert_eq(restored.get_lane(0), LANE_A, "lane 0 waypoints are exact")
	assert_eq(restored.get_lane(1), LANE_B, "lane 1 waypoints are exact")
	assert_eq(restored.get_base_cell(0), Vector2i(1, 1), "player 0's base came back")
	assert_eq(restored.get_base_cell(1), Vector2i(8, 8), "player 1's base came back")


func test_lanes_and_bases_survive_a_json_round_trip() -> void:
	var restored := _json_round_trip(_lane_map())
	assert_not_null(restored, "a lane map passes the import gate")
	assert_eq(restored.lane_count(), 2, "both lanes came back")
	assert_eq(restored.get_lane(0), LANE_A, "waypoint order and values are exact")
	assert_eq(restored.get_lane(1), LANE_B, "and so is the second lane's")
	assert_eq(restored.get_base_cell(0), Vector2i(1, 1), "player 0's base came back")
	assert_eq(restored.get_base_cell(1), Vector2i(8, 8), "player 1's base came back")


func test_a_base_cell_comes_back_keyed_on_an_int_not_the_json_string() -> void:
	# JSON object keys are strings; the rest of the game keys players on ints, so the
	# importer has to convert or every get_base_cell() lookup silently misses.
	var restored := _json_round_trip(_lane_map())
	for key in restored.base_cells.keys():
		assert_eq(typeof(key), TYPE_INT, "base_cells key '%s' is an int" % str(key))


func test_a_json_waypoint_is_a_real_vector_not_a_dictionary() -> void:
	var restored := _json_round_trip(_lane_map())
	for waypoint in restored.get_lane(0):
		assert_true(waypoint is Vector2i, "waypoint %s is a cell" % str(waypoint))


# --- Control points -----------------------------------------------------------

func test_control_points_survive_a_tres_round_trip() -> void:
	var m := _lane_map()
	assert_eq(ResourceSaver.save(m, TEMP_MAP_PATH), OK, "the fixture saves")
	var restored := load(TEMP_MAP_PATH) as MapResource
	assert_not_null(restored, "and loads back")
	assert_eq(restored.control_point_count(), POINTS.size(), "both points came back")
	assert_eq(restored.get_control_points(), POINTS, "in the authored order, cell for cell")


func test_control_points_survive_a_json_round_trip() -> void:
	var restored := _json_round_trip(_lane_map())
	assert_not_null(restored, "a map with control points passes the import gate")
	assert_eq(restored.get_control_points(), POINTS, "the cells are exact")
	for point in restored.get_control_points():
		# JSON has no vector type, so a point is written {"x","y"}; if the importer left it a
		# Dictionary every board lookup would silently miss (CONQUEST.md rule 3).
		assert_true(point is Vector2i, "point %s came back a cell, not a dictionary" % str(point))


func test_reading_a_control_point_is_indexed_and_membership_tested() -> void:
	var m := _lane_map()
	assert_eq(m.get_control_point(0), POINTS[0], "point 0 reads back")
	assert_eq(m.get_control_point(9), Vector2i(-1, -1),
		"asking for a point the map has not got answers, it does not fault")
	assert_true(m.has_control_point(POINTS[1]), "a declared cell IS a control point")
	assert_false(m.has_control_point(Vector2i(9, 9)), "and an undeclared one is not")


func test_a_control_point_outside_the_board_is_rejected() -> void:
	var m := _lane_map()
	m.control_points[0] = Vector2i(99, 1)
	assert_false(m.validate_map().get("valid", true), "a point off the board can never be held")
	assert_string_contains(_issues(m), "out of bounds", "and the issue says why")


func test_a_control_point_that_is_not_a_cell_is_rejected() -> void:
	var m := _lane_map()
	m.control_points[1] = "mid"
	assert_false(m.validate_map().get("valid", true), "a control point has to be a cell")


func test_the_same_control_point_declared_twice_is_rejected() -> void:
	# A duplicate would be contested, scored and rewarded twice over from one square of
	# ground -- there is no map that wants it, so it reads as an authoring slip.
	var m := _lane_map()
	m.add_control_point(POINTS[0])
	assert_false(m.validate_map().get("valid", true), "one cell is one control point")
	assert_string_contains(_issues(m), "declared twice", "and the issue says why")


func test_a_control_point_in_a_wall_is_rejected_by_the_strict_gate() -> void:
	# Structural validation cannot know what terrain is underneath; the catalog-strict pass
	# can, and it is the same backstop that refuses a spawn standing in a tree.
	var m := _lane_map()
	m.set_tile_at_position(POINTS[0], "WALL", "", "stone_wall")
	assert_true(m.validate_map().get("valid", false),
		"structurally the point is still a fine cell")
	var strict: Dictionary = m.validate_map(true)
	assert_false(strict.get("valid", true), "but nobody can stand in a wall to claim it")
	assert_string_contains("; ".join(strict.get("issues", [])), "impassable terrain",
		"and the issue says why")


func test_a_broken_control_point_makes_the_json_importer_refuse_the_map_quietly() -> void:
	var json := JSON.new()
	assert_eq(json.parse(_lane_map().export_to_json()), OK, "the fixture exports")
	var data: Dictionary = json.data
	data["layout"]["control_points"][0] = {"x": 404, "y": 0}
	assert_null(MapResource.import_from_json(JSON.stringify(data), true),
		"a map whose control point leaves the board is refused")


# --- Reading ------------------------------------------------------------------

func test_lane_head_reads_player_zeros_end_first_and_player_ones_last() -> void:
	var m := _lane_map()
	assert_eq(m.lane_head(0, 0), LANE_A[0], "player 0's head is the FIRST waypoint")
	assert_eq(m.lane_head(0, 1), LANE_A[LANE_A.size() - 1], "player 1's is the LAST")


func test_lane_head_of_a_lane_that_does_not_exist_is_the_null_cell() -> void:
	assert_eq(_lane_map().lane_head(7, 0), Vector2i(-1, -1),
		"asking for a lane the map has not got answers, it does not fault")


func test_spawn_player_ids_is_the_set_a_base_cell_may_name() -> void:
	var ids: Array[int] = _legacy_map().spawn_player_ids()
	assert_eq(ids.size(), 2, "both slots that own a spawn")
	assert_eq(ids[0], 0, "sorted, player 0 first")
	assert_eq(ids[1], 1, "then player 1")


# --- Rejection ----------------------------------------------------------------

func test_a_waypoint_outside_the_board_is_rejected() -> void:
	var m := _lane_map()
	m.lanes[0] = [Vector2i(1, 1), Vector2i(99, 1)] as Array[Vector2i]
	assert_false(m.validate_map().get("valid", true), "a lane cannot leave the board")
	assert_string_contains(_issues(m), "out of bounds", "and the issue says why")


func test_a_lane_with_no_waypoints_is_rejected() -> void:
	var m := _lane_map()
	m.lanes[1] = [] as Array[Vector2i]
	assert_false(m.validate_map().get("valid", true), "declaring a lane with no route is a slip")


func test_something_that_is_not_a_list_is_not_a_lane() -> void:
	var m := _lane_map()
	m.lanes[0] = "north"
	assert_false(m.validate_map().get("valid", true), "a lane has to be a list of waypoints")


func test_a_base_for_a_player_who_is_not_on_the_map_is_rejected() -> void:
	var m := _lane_map()
	m.set_base_cell(4, Vector2i(2, 2))
	assert_false(m.validate_map().get("valid", true), "a base nobody owns cannot be won or lost")


func test_a_base_cell_outside_the_board_is_rejected() -> void:
	var m := _lane_map()
	m.set_base_cell(1, Vector2i(10, 10))
	assert_false(m.validate_map().get("valid", true), "a base has to stand somewhere on the board")


func test_a_base_cell_keyed_on_a_word_is_rejected() -> void:
	var m := _lane_map()
	m.base_cells["red"] = Vector2i(2, 2)
	assert_false(m.validate_map().get("valid", true), "a base is keyed on a player slot")


func test_a_broken_lane_makes_the_json_importer_refuse_the_map_quietly() -> void:
	# The whole point of validating these fields: an untrusted map with an unwalkable lane
	# must be refused at the gate, through the null return alone (tests/README.md rule 1).
	var json := JSON.new()
	assert_eq(json.parse(_lane_map().export_to_json()), OK, "the fixture exports")
	var data: Dictionary = json.data
	data["layout"]["lanes"][0][0] = {"x": 404, "y": 0}
	assert_null(MapResource.import_from_json(JSON.stringify(data), true),
		"a map whose lane leaves the board is refused")


func test_a_base_cell_for_nobody_makes_the_json_importer_refuse_the_map() -> void:
	var json := JSON.new()
	assert_eq(json.parse(_lane_map().export_to_json()), OK, "the fixture exports")
	var data: Dictionary = json.data
	data["layout"]["base_cells"]["9"] = {"x": 1, "y": 1}
	assert_null(MapResource.import_from_json(JSON.stringify(data), true),
		"a base belonging to a player who is not on the map is refused")
