extends GutTest

# Performance tests for pathfinding and movement calculations
# Ensures algorithms scale well with larger grids

var board: Node3D
var large_grid: Grid

func before_each():
	board = preload("res://tile_objects/units/board.gd").new()
	
	# Create larger grid for performance testing
	large_grid = Grid.new()
	large_grid.size = Vector3(20, 0, 20)  # 20x20 grid
	large_grid.cell_size = Vector3(1, 0, 1)
	board.grid = large_grid

func after_each():
	if board:
		board.queue_free()

func test_movement_range_performance_small():
	var start_time = Time.get_ticks_msec()
	
	# Calculate movement range multiple times
	for i in range(100):
		var movement_range = board._calculate_movement_range(Vector3(10, 0, 10), 3)
	
	var end_time = Time.get_ticks_msec()
	var duration = end_time - start_time
	
	# Should complete 100 calculations in reasonable time (< 100ms)
	assert_lt(duration, 100, "Movement range calculation should be fast for small ranges")

func test_movement_range_performance_large():
	var start_time = Time.get_ticks_msec()
	
	# Calculate large movement range
	var movement_range = board._calculate_movement_range(Vector3(10, 0, 10), 10)
	
	var end_time = Time.get_ticks_msec()
	var duration = end_time - start_time
	
	# Should complete large range calculation in reasonable time (< 50ms)
	assert_lt(duration, 50, "Movement range calculation should be fast even for large ranges")
	
	# Verify we got a reasonable number of tiles
	assert_gt(movement_range.size(), 100, "Large movement range should include many tiles")

func test_priority_queue_performance():
	var queue = PriorityQueue.new()
	var start_time = Time.get_ticks_msec()
	
	# Add many units to queue
	var units = []
	for i in range(1000):
		var unit = Unit.new("Unit" + str(i), randi() % 20 + 1, 3)
		units.append(unit)
		queue.push(unit)
	
	# Pop all units
	var popped_units = []
	while not queue.is_empty():
		popped_units.append(queue.pop())
	
	var end_time = Time.get_ticks_msec()
	var duration = end_time - start_time
	
	# Should handle 1000 units efficiently (< 10ms)
	assert_lt(duration, 10, "Priority queue should handle large numbers of units efficiently")
	assert_eq(popped_units.size(), 1000, "Should pop all units")

func test_grid_coordinate_conversion_performance():
	var start_time = Time.get_ticks_msec()
	
	# Convert coordinates many times
	for i in range(10000):
		var world_pos = Vector3(randf() * 20, 0, randf() * 20)
		var grid_pos = large_grid.calculate_grid_coordinates(world_pos)
		var back_to_world = large_grid.calculate_map_position(grid_pos)
	
	var end_time = Time.get_ticks_msec()
	var duration = end_time - start_time
	
	# Should handle 10000 conversions quickly (< 20ms)
	assert_lt(duration, 20, "Grid coordinate conversions should be very fast")