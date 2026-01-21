# Represents a grid with its size, the size of each cell in pixels, and some helper functions to
# calculate and convert coordinates.
# It's meant to be shared between game objects that need access to those values.
extends Resource

class_name Grid

# The grid's size in rows and columns.
@export var size := Vector3(5, 0, 5)

@export var cell_size := Vector3(1, 0, 1)

# Half of ``cell_size``.
# We will use this to calculate the center of a grid cell in pixels, on the screen.
# That's how we can place units in the center of a cell.
var _half_cell_size = cell_size / 2


func get_tile_position(grid_position: Vector3) -> Vector3:
	return Vector3(grid_position.x, 0, grid_position.z)

# Returns the position of a cell's center in pixels.
# We'll place units and have them move through cells using this function.
func calculate_map_position(grid_position: Vector3) -> Vector3:
	return grid_position * cell_size + _half_cell_size


# Returns the coordinates of the cell on the grid given a position on the map.
# This is the complementary of `calculate_map_position()` above.
# When designing a level, you'll place units visually in the editor. We'll use this function to find
# the grid coordinates they're placed on, and call `calculate_map_position()` to snap them to the
# cell's center.
func calculate_grid_coordinates(map_position: Vector3) -> Vector3:
	return (map_position / cell_size).floor()


# Returns true if the `cell_coordinates` are within the grid.
# This method and the following one allow us to ensure the cursor or units can never go past the
# map's limit.
#func is_within_bounds(cell_coordinates: Vector3) -> bool:
	#var x_axis := cell_coordinates.x >= 0 and cell_coordinates.x < size.x
	#return x_axis and cell_coordinates.z >= 0 and cell_coordinates.z < size.z

func is_within_bounds(position_to_check: Vector3) -> bool:
	var can_move_x := position_to_check.x >= 0 and position_to_check.x < size.x
	var can_move_z := position_to_check.z >= 0 and position_to_check.z < size.z

	return can_move_x and can_move_z
	
func get_translated_position(original_position: Vector3, new_position: Vector3) -> Vector3:
	return Vector3(new_position.x, original_position.y, new_position.z)
# Makes the `grid_position` fit within the grid's bounds.
# This is a clamp function designed specifically for our grid coordinates.
# The Vector2 class comes with its `Vector2.clamp()` method, but it doesn't work the same way: it
# limits the vector's length instead of clamping each of the vector's components individually.
# That's why we need to code a new method.
## Makes the `grid_position` fit within the grid's bounds.
func grid_clamp(grid_position: Vector3) -> Vector3:
	var out := grid_position
	out.x = clamp(out.x, 0, size.x - 1.0)
	out.y = clamp(out.y, 0, size.y - 1.0)
	return out

# Given Vector2 coordinates, calculates and returns the corresponding integer index. You can use
# this function to convert 2D coordinates to a 1D array's indices.
#
# There are two cases where you need to convert coordinates like so:
# 1. We'll need it for the AStar algorithm, which requires a unique index for each point on the
# graph it uses to find a path.
# 2. You can use it for performance. More on that below.
func as_index(cell: Vector3) -> int:
	return int(cell.x + size.x * cell.y)
