extends Node

# Mock GameEvents for testing
# Provides same interface but tracks calls for verification

var signal_calls: Dictionary = {}

# Mock all the signals from GameEvents
signal unit_selected(unit: Unit, position: Vector3)
signal unit_deselected(unit: Unit)
signal unit_moved(unit: Unit, from_position: Vector3, to_position: Vector3)
signal tile_highlighted(position: Vector3)
signal tile_unhighlighted(position: Vector3)
signal turn_started(unit: Unit)
signal turn_ended(unit: Unit)
signal cursor_moved(position: Vector3)
signal cursor_selected(position: Vector3)
signal movement_range_calculated(positions: Array[Vector3])
signal movement_validated(from_position: Vector3, to_position: Vector3, is_valid: bool)
signal ui_unit_info_requested(unit: Unit)
signal ui_action_menu_requested(unit: Unit, actions: Array)

func _init():
	name = "MockGameEvents"
	_reset_tracking()

func _reset_tracking():
	signal_calls = {
		"unit_selected": [],
		"unit_deselected": [],
		"unit_moved": [],
		"tile_highlighted": [],
		"tile_unhighlighted": [],
		"turn_started": [],
		"turn_ended": [],
		"cursor_moved": [],
		"cursor_selected": [],
		"movement_range_calculated": [],
		"movement_validated": [],
		"ui_unit_info_requested": [],
		"ui_action_menu_requested": []
	}

# Override emit methods to track calls
func emit_unit_selected(unit: Unit, position: Vector3):
	signal_calls.unit_selected.append({"unit": unit, "position": position})
	unit_selected.emit(unit, position)

func emit_unit_deselected(unit: Unit):
	signal_calls.unit_deselected.append({"unit": unit})
	unit_deselected.emit(unit)

func emit_unit_moved(unit: Unit, from_pos: Vector3, to_pos: Vector3):
	signal_calls.unit_moved.append({"unit": unit, "from": from_pos, "to": to_pos})
	unit_moved.emit(unit, from_pos, to_pos)

func emit_cursor_moved(position: Vector3):
	signal_calls.cursor_moved.append({"position": position})
	cursor_moved.emit(position)

func emit_cursor_selected(position: Vector3):
	signal_calls.cursor_selected.append({"position": position})
	cursor_selected.emit(position)

func emit_turn_started(unit: Unit):
	signal_calls.turn_started.append({"unit": unit})
	turn_started.emit(unit)

func emit_turn_ended(unit: Unit):
	signal_calls.turn_ended.append({"unit": unit})
	turn_ended.emit(unit)

# Helper methods for test verification
func get_call_count(signal_name: String) -> int:
	return signal_calls.get(signal_name, []).size()

func was_signal_called(signal_name: String) -> bool:
	return get_call_count(signal_name) > 0

func get_last_call_data(signal_name: String) -> Dictionary:
	var calls = signal_calls.get(signal_name, [])
	return calls[-1] if calls.size() > 0 else {}

func reset():
	_reset_tracking()