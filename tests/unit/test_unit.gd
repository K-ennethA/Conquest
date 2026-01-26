extends GutTest

# Unit tests for Unit class
# Tests unit properties, movement validation, and event handling

var unit: Unit
var mock_events: Node

func before_each():
	unit = Unit.new("TestUnit", 10, 3)
	# Mock the GameEvents singleton for testing
	mock_events = Node.new()
	mock_events.name = "MockGameEvents"

func after_each():
	if unit:
		unit.queue_free()
	if mock_events:
		mock_events.queue_free()

func test_unit_initialization():
	assert_eq(unit.unit_name, "TestUnit", "Unit name should be set correctly")
	assert_eq(unit.speed, 10, "Unit speed should be set correctly")
	assert_eq(unit.max_movement, 3, "Unit movement should be set correctly")
	assert_false(unit.has_turn, "Unit should not have turn initially")

func test_unit_default_initialization():
	var default_unit = Unit.new()
	
	assert_eq(default_unit.unit_name, "", "Default unit name should be empty")
	assert_eq(default_unit.speed, 10, "Default speed should be 10")
	assert_eq(default_unit.max_movement, 3, "Default movement should be 3")

func test_get_movement_range():
	assert_eq(unit.get_movement_range(), 3, "Movement range should match max_movement")
	
	unit.max_movement = 5
	assert_eq(unit.get_movement_range(), 5, "Movement range should update with max_movement")

func test_can_move_to():
	# Base implementation should always return true
	assert_true(unit.can_move_to(Vector3(0, 0, 0)), "Base unit should allow movement to any position")
	assert_true(unit.can_move_to(Vector3(10, 5, -3)), "Base unit should allow movement to any position")

func test_unit_properties_export():
	# Test that exported properties can be set
	unit.unit_name = "NewName"
	unit.speed = 15
	unit.max_movement = 4
	unit.has_turn = true
	
	assert_eq(unit.unit_name, "NewName", "Unit name should be settable")
	assert_eq(unit.speed, 15, "Speed should be settable")
	assert_eq(unit.max_movement, 4, "Max movement should be settable")
	assert_true(unit.has_turn, "Has turn should be settable")