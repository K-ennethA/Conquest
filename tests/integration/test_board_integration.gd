extends GutTest

# Integration tests for Board system
# Tests interaction between board, units, cursor, and turn system

const BOARD_SCRIPT := preload("res://tile_objects/units/board.gd")

var board: Node3D
var grid: Grid

func before_each():
	# Create a minimal test scene
	grid = Grid.new()
	grid.size = Vector3(3, 0, 3)
	grid.cell_size = Vector3(1, 0, 1)

## A bare board, never added to the tree (so its _ready never wires the GameEvents
## autoload). autofree, not queue_free: the board owns its child units and GUT counts
## orphans before a queued free has run.
func _make_board() -> Node3D:
	return autofree(BOARD_SCRIPT.new())

func test_board_initialization():
	board = _make_board()
	board.grid = grid

	assert_not_null(board.grid, "Board should have grid reference")
	assert_eq(board.units.size(), 0, "Board should start with no units")

func test_unit_scanning():
	# This would require setting up a proper scene tree
	# For now, test the scanning logic with mock objects
	board = _make_board()
	board.grid = grid

	# Unit takes NO constructor args -- stats come from a UnitStatsResource. The old
	# `Unit.new("TestUnit", 10, 3)` raised an engine error (which GUT counts as a
	# failure) and returned null, so this test asserted nothing for a long time.
	var mock_unit := Unit.new()
	mock_unit.position = Vector3(1, 0, 1)

	# Add to board as child (simulating scene structure)
	board.add_child(mock_unit)
	
	# Test scanning
	board.initialize_units()
	
	var expected_tile_pos = grid.get_tile_position(mock_unit.position)
	assert_true(board.units.has(expected_tile_pos), "Board should find unit at tile position")
	assert_true(mock_unit in board.units[expected_tile_pos], "Unit should be in units dictionary")

func test_movement_range_calculation():
	board = _make_board()
	board.grid = grid

	var start_pos = Vector3(1, 0, 1)  # Center of 3x3 grid
	var movement_range = board._calculate_movement_range(start_pos, 1)
	
	# Should include adjacent tiles
	var expected_positions = [
		Vector3(0, 0, 1),  # Left
		Vector3(2, 0, 1),  # Right  
		Vector3(1, 0, 0),  # Forward
		Vector3(1, 0, 2)   # Back
	]
	
	assert_eq(movement_range.size(), 4, "Should find 4 adjacent tiles")
	
	for pos in expected_positions:
		assert_true(pos in movement_range, "Should include position: " + str(pos))

func test_distance_calculation():
	board = _make_board()

	# Test Manhattan distance
	assert_eq(board._calculate_distance(Vector3(0, 0, 0), Vector3(0, 0, 0)), 0, "Same position should have distance 0")
	assert_eq(board._calculate_distance(Vector3(0, 0, 0), Vector3(1, 0, 0)), 1, "Adjacent X should have distance 1")
	assert_eq(board._calculate_distance(Vector3(0, 0, 0), Vector3(0, 0, 1)), 1, "Adjacent Z should have distance 1")
	assert_eq(board._calculate_distance(Vector3(0, 0, 0), Vector3(2, 0, 3)), 5, "Should calculate Manhattan distance correctly")

func test_bounds_checking():
	board = _make_board()
	board.grid = grid

	# With NO selected unit the guard refuses everything - that IS the contract
	# (this suite was null-passing for years and asserted the opposite).
	assert_false(board._can_move_to_position(Vector3(1, 0, 1)),
		"No selected unit -> movement is always refused")

	# Select a unit at the origin; an ORTHOGONALLY adjacent cell (Manhattan distance 1)
	# is within the assigned movement range. A bare Unit REQUIRES a stats resource
	# before entering the tree (its _ready push_errors otherwise, which fails GUT).
	var mover_stats: UnitStatsResource = UnitStatsResource.new()
	mover_stats.movement_range = 3
	var mover: Unit = Unit.new()
	mover.stats_resource = mover_stats
	add_child_autofree(mover)
	mover.position = Vector3(0, 0, 0)
	board._selected_unit = mover
	assert_true(board._can_move_to_position(Vector3(1, 0, 0)),
		"Selected unit with default range covers an adjacent cell")

	# Out of bounds is refused even with a unit selected.
	assert_false(board._can_move_to_position(Vector3(-1, 0, 0)), "Should reject out of bounds movement")
	assert_false(board._can_move_to_position(Vector3(5, 0, 5)), "Should reject out of bounds movement")