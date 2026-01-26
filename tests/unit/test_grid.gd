extends GutTest

# Unit tests for the Grid resource
# Tests coordinate conversion, bounds checking, and utility functions

var grid: Grid

func before_each():
	grid = Grid.new()
	grid.size = Vector3(5, 0, 5)
	grid.cell_size = Vector3(1, 0, 1)

func test_calculate_map_position():
	# Test converting grid coordinates to world position
	var grid_pos = Vector3(2, 0, 3)
	var expected_world_pos = Vector3(2.5, 0, 3.5)  # Center of cell
	var actual_world_pos = grid.calculate_map_position(grid_pos)
	
	assert_eq(actual_world_pos, expected_world_pos, "Map position calculation should center in cell")

func test_calculate_grid_coordinates():
	# Test converting world position to grid coordinates
	var world_pos = Vector3(2.7, 0, 3.2)
	var expected_grid_pos = Vector3(2, 0, 3)  # Should floor to grid cell
	var actual_grid_pos = grid.calculate_grid_coordinates(world_pos)
	
	assert_eq(actual_grid_pos, expected_grid_pos, "Grid coordinates should floor world position")

func test_is_within_bounds_valid_positions():
	# Test valid positions within grid bounds
	assert_true(grid.is_within_bounds(Vector3(0, 0, 0)), "Origin should be within bounds")
	assert_true(grid.is_within_bounds(Vector3(4, 0, 4)), "Max valid position should be within bounds")
	assert_true(grid.is_within_bounds(Vector3(2, 0, 2)), "Center position should be within bounds")

func test_is_within_bounds_invalid_positions():
	# Test invalid positions outside grid bounds
	assert_false(grid.is_within_bounds(Vector3(-1, 0, 0)), "Negative X should be out of bounds")
	assert_false(grid.is_within_bounds(Vector3(0, 0, -1)), "Negative Z should be out of bounds")
	assert_false(grid.is_within_bounds(Vector3(5, 0, 0)), "X >= size.x should be out of bounds")
	assert_false(grid.is_within_bounds(Vector3(0, 0, 5)), "Z >= size.z should be out of bounds")

func test_grid_clamp():
	# Test clamping positions to grid bounds
	assert_eq(grid.grid_clamp(Vector3(-1, 0, -1)), Vector3(0, 0, 0), "Should clamp negative values to 0")
	assert_eq(grid.grid_clamp(Vector3(10, 0, 10)), Vector3(4, 0, 4), "Should clamp large values to max")
	assert_eq(grid.grid_clamp(Vector3(2, 0, 3)), Vector3(2, 0, 3), "Should not change valid positions")

func test_get_tile_position():
	# Test extracting tile position (X, Z only)
	var position = Vector3(2, 5, 3)
	var expected = Vector3(2, 0, 3)
	var actual = grid.get_tile_position(position)
	
	assert_eq(actual, expected, "Should zero out Y coordinate")

func test_as_index():
	# Test converting 2D coordinates to 1D index
	assert_eq(grid.as_index(Vector3(0, 0, 0)), 0, "Origin should map to index 0")
	assert_eq(grid.as_index(Vector3(1, 0, 0)), 1, "X=1 should map to index 1")
	assert_eq(grid.as_index(Vector3(0, 1, 0)), 5, "Y=1 should map to index 5 (size.x)")
	assert_eq(grid.as_index(Vector3(2, 3, 0)), 17, "X=2,Y=3 should map to index 17")