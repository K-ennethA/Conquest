extends GutTest

## BIG-MAP CLARITY, the parts that are pure data.
##
## Two subjects, both about a board being too large to read at a glance:
##   1. [ObjectiveMarkers.plan] -- which banners a map asks for, derived from
##      [member MapResource.base_cells] ALONE. No mode is consulted anywhere, so the answer
##      is the same whatever is playing the map.
##   2. [code]CameraController.board_zoom_limit[/code] -- how far the camera may pull back,
##      derived from the ACTUAL board rather than from the ~13x11 boards the authored
##      dist_max was tuned against.
##
## The live half (real board, real markers, real fit) is integration/test_objective_markers_live.gd.

const MARKERS := preload("res://game/visuals/ObjectiveMarkers.gd")
const CAMERA_SCRIPT := preload("res://game/visuals/CameraController.gd")
const RIFTWOOD_PATH := "res://game/maps/resources/riftwood.tres"

## World spans of the two boards this pins, in world units (one cell is 2x2).
const SMALL_W: float = 26.0   # kings_crossing, 13 cells wide
const SMALL_D: float = 22.0   # ...and 11 deep
const BIG_W: float = 70.0     # riftwood, 35 cells
const BIG_D: float = 70.0


## A camera carrying the real controller script, NOT in the tree: every function under test
## here is pure arithmetic over the exports, and keeping it out of the tree means _ready
## never subscribes it to CombatServices.
func _camera() -> Camera3D:
	var cam: Camera3D = autofree(CAMERA_SCRIPT.new())
	return cam


# --- The banner plan is base_cells and nothing else --------------------------

func test_a_map_that_declares_no_bases_asks_for_no_banners() -> void:
	var map := MapResource.new()
	map.width = 10
	map.height = 10
	assert_eq(MARKERS.plan(map).size(), 0,
		"the majority of maps declare no bases, and they mount nothing at all")


func test_null_is_planned_as_nothing_rather_than_faulting() -> void:
	assert_eq(MARKERS.plan(null).size(), 0, "a null map plans no banners")


func test_any_map_that_authors_bases_is_planned_generically() -> void:
	# A plain hand-built map -- no lanes, no siege objective, no mode. Declaring base cells
	# is the ONLY thing that earns banners.
	var map := MapResource.new()
	map.width = 8
	map.height = 8
	map.set_base_cell(1, Vector2i(6, 6))
	map.set_base_cell(0, Vector2i(1, 1))

	var plan: Array[Dictionary] = MARKERS.plan(map)
	assert_eq(plan.size(), 2, "both authored bases earned a banner")
	assert_eq(int(plan[0]["player_id"]), 0,
		"planned in ascending player-slot order, so two peers build the same nodes in the same order")
	assert_eq(int(plan[1]["player_id"]), 1, "and slot 1 comes second")
	assert_eq(plan[0]["cell"], Vector2i(1, 1), "slot 0's banner stands on the cell the map named")


func test_riftwood_asks_for_one_banner_per_declared_base() -> void:
	var map := load(RIFTWOOD_PATH) as MapResource
	assert_not_null(map, "the authored 35x35 map loaded")
	if map == null:
		return
	var plan: Array[Dictionary] = MARKERS.plan(map)
	assert_eq(plan.size(), map.base_cells.size(),
		"one banner per base the map declares -- no more, no fewer")
	for entry in plan:
		assert_eq(entry["cell"], map.get_base_cell(int(entry["player_id"])),
			"and each stands on that player's own declared base cell")


func test_a_junk_or_out_of_bounds_base_is_skipped_not_faulted() -> void:
	# A bad decoration must never cost a battle: validate_map already rejects these at the
	# gate, so the builder's job is simply to ignore them.
	var map := MapResource.new()
	map.width = 5
	map.height = 5
	map.base_cells = { 0: Vector2i(1, 1), 1: Vector2i(9, 9), 2: "not a cell", 3: Vector2i(-1, 2) }
	var plan: Array[Dictionary] = MARKERS.plan(map)
	assert_eq(plan.size(), 1, "only the one in-bounds cell entry planned a banner")
	assert_eq(int(plan[0]["player_id"]), 0, "and it is the slot that authored a real cell")


func test_a_banner_stands_at_the_center_of_its_cell() -> void:
	# The same (x * 2 + 1, _, y * 2 + 1) mapping units, tiles and the cursor all use -- a
	# banner half a cell off would point at the wrong tile.
	assert_eq(MARKERS.world_position_for(Vector2i(0, 0)),
		Vector3(1.0, MARKERS.GROUND_Y, 1.0), "cell (0,0) centers on (1, _, 1)")
	assert_eq(MARKERS.world_position_for(Vector2i(3, 31)),
		Vector3(7.0, MARKERS.GROUND_Y, 63.0), "and cell (3,31) on (7, _, 63)")


func test_the_two_sides_are_tinted_apart() -> void:
	var ally: Color = MARKERS.color_for_player(0)
	var enemy: Color = MARKERS.color_for_player(1)
	assert_ne(ally, enemy, "the two sides' banners are never the same colour")
	assert_ne(ally, MARKERS.color_for_player(7),
		"an unnamed slot falls back to neutral rather than borrowing player 0's blue")


# --- Zoom-out scales with the board ------------------------------------------

func test_a_small_board_keeps_the_authored_zoom_out_limit_exactly() -> void:
	# THE PIN. dist_max was tuned against boards this size; the scaling must be invisible
	# here, byte for byte, or every existing map's feel changes.
	var cam := _camera()
	var limit: float = cam.board_zoom_limit(SMALL_W, SMALL_D, 20.3)
	assert_almost_eq(limit, cam.dist_max, 0.0001,
		"a 13x11 board's pull-back limit is still exactly the authored dist_max")


func test_a_big_board_earns_more_pull_back_than_the_authored_limit() -> void:
	var cam := _camera()
	var limit: float = cam.board_zoom_limit(BIG_W, BIG_D, 64.4)
	assert_gt(limit, cam.dist_max,
		"a 35x35 board may pull back further than the authored 13x11-era limit")
	var diagonal: float = Vector2(BIG_W, BIG_D).length()
	assert_almost_eq(limit, cam.zoom_out_board_factor * diagonal, 0.0001,
		"and the extra headroom is exactly the board diagonal times the exported factor")


func test_the_factor_is_a_knob_and_zero_restores_the_old_behaviour() -> void:
	var cam := _camera()
	cam.zoom_out_board_factor = 0.0
	assert_almost_eq(cam.board_zoom_limit(BIG_W, BIG_D, 64.4), cam.dist_max, 0.0001,
		"factor 0 is the pre-scaling behaviour: the authored max, on any board")
	cam.zoom_out_board_factor = 3.0
	assert_gt(cam.board_zoom_limit(SMALL_W, SMALL_D, 20.3), cam.dist_max,
		"raising the factor is how a player-facing tuning pass buys more pull-back")


func test_a_board_that_needs_a_huge_fit_distance_can_still_reach_it() -> void:
	# The pre-existing guarantee: whatever else the limit is derived from, it can never end
	# up BELOW the distance the board needs in order to frame at all.
	var cam := _camera()
	assert_almost_eq(cam.board_zoom_limit(SMALL_W, SMALL_D, 400.0), 400.0, 0.0001,
		"the fit distance is a floor on the limit, exactly as it was before the scaling")
