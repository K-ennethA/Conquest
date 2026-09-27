extends GutTest

## FloorNav: cursor floor rules (snap / step / floor cycling / covered cells), the
## unit-cycling order, floor names and link descriptions. Runs on the bridge fixture
## (game/maps/build_test_bridge_map.gd) loaded into a headless BoardAdapter.
##
## Fixture (9 x 7): river col 4; floor-1 INTACT bridge row 1 x 2..6 (stairs at
## (1,1,0)->(2,1,1) and (7,1,0)->(6,1,1)); floor-1 BROKEN bridge row 3 x 2,3 | 5,6
## (ladders cost 2 from (1,3,0) and (7,3,0)).

const BuildBridge := preload("res://game/maps/build_test_bridge_map.gd")

var board: BoardAdapter


func before_each() -> void:
	var grid := Grid.new()
	grid.size = Vector3(9, 0, 7)
	board = BoardAdapter.new(grid, []).configure_from_map(BuildBridge.build())


func test_snap_floor_prefers_top_most_at_or_below_view() -> void:
	assert_eq(FloorNav.snap_floor(board, Vector2i(3, 1), 1), 1, "bridge deck at the top view")
	assert_eq(FloorNav.snap_floor(board, Vector2i(3, 1), 0), 0, "ground under the bridge at view 0")
	assert_eq(FloorNav.snap_floor(board, Vector2i(0, 0), 1), 0, "ground-only column")
	assert_eq(FloorNav.snap_floor(board, Vector2i(4, 3), 1), 0, "broken-bridge gap falls to the river")
	assert_eq(FloorNav.snap_floor(board, Vector2i(-1, 0), 1), -1, "off the board")


func test_step_rides_over_bridge_and_drops_off_its_end() -> void:
	assert_eq(FloorNav.step(board, Vector3i(1, 1, 0), Vector2i(1, 0), 1), Vector3i(2, 1, 1), "onto the deck")
	assert_eq(FloorNav.step(board, Vector3i(6, 1, 1), Vector2i(1, 0), 1), Vector3i(7, 1, 0), "off the east end")
	assert_eq(FloorNav.step(board, Vector3i(1, 1, 0), Vector2i(1, 0), 0), Vector3i(2, 1, 0), "view 0 walks under")
	assert_eq(FloorNav.step(board, Vector3i(0, 0, 0), Vector2i(-1, 0), 1), Cells.INVALID, "board edge")


func test_cycle_floor_moves_within_the_column() -> void:
	var down := FloorNav.cycle_floor(board, Vector3i(3, 1, 1), 1, -1)
	assert_eq(down["cell"], Vector3i(3, 1, 0))
	assert_eq(down["view"], 0)
	var up := FloorNav.cycle_floor(board, Vector3i(3, 1, 0), 0, 1)
	assert_eq(up["cell"], Vector3i(3, 1, 1))
	assert_eq(up["view"], 1)


func test_cycle_floor_on_ground_only_column_changes_view_only() -> void:
	var r := FloorNav.cycle_floor(board, Vector3i(0, 0, 0), 1, -1)
	assert_eq(r["cell"], Vector3i(0, 0, 0))
	assert_eq(r["view"], 0, "look under the bridges from beside them")
	r = FloorNav.cycle_floor(board, Vector3i(0, 0, 0), 0, 1)
	assert_eq(r["view"], 1)
	r = FloorNav.cycle_floor(board, Vector3i(0, 0, 0), 1, 1)
	assert_eq(r["view"], 1, "clamped to the top floor")


func test_is_covered() -> void:
	assert_true(FloorNav.is_covered(board, Vector3i(3, 1, 0)), "road under the bridge")
	assert_false(FloorNav.is_covered(board, Vector3i(3, 1, 1)), "the deck itself")
	assert_false(FloorNav.is_covered(board, Vector3i(4, 3, 0)), "under the gap is open sky")


func test_cell_order_and_cycle_index() -> void:
	var cells: Array = [Vector3i(5, 0, 0), Vector3i(2, 1, 1), Vector3i(1, 1, 0), Vector3i(0, 2, 0)]
	cells.sort_custom(FloorNav.cell_order_less)
	assert_eq(cells, [Vector3i(5, 0, 0), Vector3i(1, 1, 0), Vector3i(2, 1, 1), Vector3i(0, 2, 0)])
	assert_eq(FloorNav.cycle_index(cells, Vector3i(1, 1, 0), 1), 2, "next from a unit")
	assert_eq(FloorNav.cycle_index(cells, Vector3i(5, 0, 0), -1), 3, "prev wraps")
	assert_eq(FloorNav.cycle_index(cells, Vector3i(0, 2, 0), 1), 0, "next wraps")
	assert_eq(FloorNav.cycle_index(cells, Vector3i(3, 1, 0), 1), 3, "from empty ground: next in reading order")
	assert_eq(FloorNav.cycle_index(cells, Vector3i(3, 1, 0), -1), 2, "from empty ground: previous")
	assert_eq(FloorNav.cycle_index([], Vector3i.ZERO, 1), -1)


func test_floor_names_and_link_descriptions() -> void:
	assert_eq(FloorNav.floor_name(0, 2), "Ground")
	assert_eq(FloorNav.floor_name(1, 2), "Upper")
	assert_eq(FloorNav.floor_name(1, 3), "Upper")
	assert_eq(FloorNav.floor_name(2, 3), "Top")
	var up := FloorNav.describe_links(board, Vector3i(1, 1, 0))
	assert_eq(up.size(), 1)
	assert_true(up[0].begins_with("Stairs") and up[0].contains("Upper"), up[0])
	var down := FloorNav.describe_links(board, Vector3i(2, 3, 1))
	assert_true(down[0].begins_with("Ladder") and down[0].contains("cost 2"), down[0])
	assert_eq(FloorNav.describe_links(board, Vector3i(0, 0, 0)).size(), 0)
