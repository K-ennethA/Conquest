extends GutTest

# Unit tests for TurnSystem
# Tests turn order, priority queue integration, and turn management

var turn_system: Node
var test_units: Array[Unit]

func before_each():
	# Create turn system instance
	turn_system = preload("res://turns/turn_system.gd").new()
	
	# Create test units with different speeds
	test_units = [
		Unit.new("Fast", 15, 3),
		Unit.new("Medium", 10, 3), 
		Unit.new("Slow", 5, 3),
		Unit.new("VeryFast", 20, 3)
	]

func after_each():
	if turn_system:
		turn_system.queue_free()
	
	for unit in test_units:
		if unit:
			unit.queue_free()

func test_turn_system_initialization():
	assert_not_null(turn_system.priority_queue, "Turn system should have priority queue")
	assert_null(turn_system.get_current_unit(), "Should have no current unit initially")
	assert_false(turn_system.is_unit_turn(test_units[0]), "No unit should have turn initially")

func test_initialize_with_units():
	turn_system.initialize_with_units(test_units)
	
	var current_unit = turn_system.get_current_unit()
	assert_not_null(current_unit, "Should have a current unit after initialization")
	assert_true(current_unit.has_turn, "Current unit should have turn flag set")

func test_turn_order_by_speed():
	turn_system.initialize_with_units(test_units)
	
	# Should start with fastest unit (VeryFast, speed 20)
	var first_unit = turn_system.get_current_unit()
	assert_eq(first_unit.unit_name, "VeryFast", "Fastest unit should go first")
	
	# End turn and check next unit
	turn_system.end_current_turn()
	var second_unit = turn_system.get_current_unit()
	assert_eq(second_unit.unit_name, "Fast", "Second fastest should go second")

func test_is_unit_turn():
	turn_system.initialize_with_units(test_units)
	
	var current_unit = turn_system.get_current_unit()
	assert_true(turn_system.is_unit_turn(current_unit), "Current unit should have turn")
	
	# Other units should not have turn
	for unit in test_units:
		if unit != current_unit:
			assert_false(turn_system.is_unit_turn(unit), "Non-current units should not have turn")

func test_end_current_turn():
	turn_system.initialize_with_units(test_units)
	
	var first_unit = turn_system.get_current_unit()
	turn_system.end_current_turn()
	
	assert_false(first_unit.has_turn, "Previous unit should not have turn after ending")
	
	var second_unit = turn_system.get_current_unit()
	assert_not_null(second_unit, "Should have new current unit")
	assert_ne(second_unit, first_unit, "Should be different unit")
	assert_true(second_unit.has_turn, "New current unit should have turn")

func test_turn_cycling():
	# Test that turns cycle through all units
	turn_system.initialize_with_units(test_units)
	
	var turn_order = []
	var initial_unit = turn_system.get_current_unit()
	
	# Go through several turns
	for i in range(test_units.size() + 2):
		var current = turn_system.get_current_unit()
		turn_order.append(current.unit_name)
		turn_system.end_current_turn()
	
	# Should cycle back to first unit
	assert_true(turn_order[0] in turn_order.slice(test_units.size()), "Should cycle back to first unit")

func test_empty_unit_list():
	turn_system.initialize_with_units([])
	
	assert_null(turn_system.get_current_unit(), "Should have no current unit with empty list")
	
	# Should handle end_current_turn gracefully
	turn_system.end_current_turn()
	assert_null(turn_system.get_current_unit(), "Should still have no current unit")