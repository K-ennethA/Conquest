extends GutTest

# Integration tests for GameEvents system
# Tests signal emission and event flow between systems

var events: Node
var signal_received: bool
var received_data: Dictionary

func before_each():
	events = preload("res://systems/game_events.gd").new()
	signal_received = false
	received_data = {}

func after_each():
	if events:
		events.queue_free()

func test_unit_selection_signals():
	# Connect to signal
	events.unit_selected.connect(_on_unit_selected)
	
	var test_unit = Unit.new("TestUnit", 10, 3)
	var test_position = Vector3(1, 0, 1)
	
	# Emit signal
	events.unit_selected.emit(test_unit, test_position)
	
	assert_true(signal_received, "Signal should be received")
	assert_eq(received_data.unit, test_unit, "Should receive correct unit")
	assert_eq(received_data.position, test_position, "Should receive correct position")

func test_cursor_movement_signals():
	events.cursor_moved.connect(_on_cursor_moved)
	
	var test_position = Vector3(2, 0, 3)
	events.cursor_moved.emit(test_position)
	
	assert_true(signal_received, "Cursor moved signal should be received")
	assert_eq(received_data.position, test_position, "Should receive correct cursor position")

func test_turn_system_signals():
	events.turn_started.connect(_on_turn_started)
	events.turn_ended.connect(_on_turn_ended)
	
	var test_unit = Unit.new("TurnUnit", 15, 4)
	
	# Test turn started
	events.turn_started.emit(test_unit)
	assert_true(signal_received, "Turn started signal should be received")
	assert_eq(received_data.unit, test_unit, "Should receive correct unit for turn start")
	
	# Reset and test turn ended
	signal_received = false
	received_data.clear()
	
	events.turn_ended.emit(test_unit)
	assert_true(signal_received, "Turn ended signal should be received")
	assert_eq(received_data.unit, test_unit, "Should receive correct unit for turn end")

func test_movement_signals():
	events.unit_moved.connect(_on_unit_moved)
	
	var test_unit = Unit.new("MovingUnit", 12, 3)
	var from_pos = Vector3(0, 0, 0)
	var to_pos = Vector3(1, 0, 1)
	
	events.unit_moved.emit(test_unit, from_pos, to_pos)
	
	assert_true(signal_received, "Unit moved signal should be received")
	assert_eq(received_data.unit, test_unit, "Should receive correct unit")
	assert_eq(received_data.from_position, from_pos, "Should receive correct from position")
	assert_eq(received_data.to_position, to_pos, "Should receive correct to position")

# Signal handlers for testing
func _on_unit_selected(unit: Unit, position: Vector3):
	signal_received = true
	received_data.unit = unit
	received_data.position = position

func _on_cursor_moved(position: Vector3):
	signal_received = true
	received_data.position = position

func _on_turn_started(unit: Unit):
	signal_received = true
	received_data.unit = unit

func _on_turn_ended(unit: Unit):
	signal_received = true
	received_data.unit = unit

func _on_unit_moved(unit: Unit, from_position: Vector3, to_position: Vector3):
	signal_received = true
	received_data.unit = unit
	received_data.from_position = from_position
	received_data.to_position = to_position