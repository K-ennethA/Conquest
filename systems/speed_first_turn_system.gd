extends TurnSystemBase

class_name SpeedFirstTurnSystem

# Speed First Turn System Implementation
# Unit-based turns where units act in order based on their speed stats (fastest first)

var turn_order: Array[Unit] = []
var current_unit_index: int = 0
var current_acting_unit: Unit = null
var units_acted_this_round: Array[Unit] = []

func _init() -> void:
	super._init()
	system_type = TurnSystemType.INITIATIVE
	system_name = "Speed First Turn System"

# Abstract method implementations
func start_turn_system() -> void:
	"""Initialize and start the speed first turn system"""
	print("Speed First Turn System: Starting...")
	
	if registered_units.is_empty():
		print("Cannot start turn system: No units registered")
		return
	
	is_active = true
	current_turn = 1
	is_turn_in_progress = false
	units_acted_this_round.clear()
	
	# Calculate initial turn order
	_calculate_turn_order()
	
	# Start with first unit
	if not turn_order.is_empty():
		current_unit_index = 0
		_start_unit_turn(turn_order[current_unit_index])
	else:
		print("No units in turn order - cannot start")
		return
	
	print("Speed First Turn System started with " + str(turn_order.size()) + " units")

func end_turn_system() -> void:
	"""Clean up and end the speed first turn system"""
	if current_acting_unit and is_turn_in_progress:
		_end_unit_turn(current_acting_unit)
	
	is_active = false
	is_turn_in_progress = false
	current_acting_unit = null
	turn_order.clear()
	units_acted_this_round.clear()
	current_unit_index = 0
	
	print("Speed First Turn System ended")

func advance_turn() -> void:
	"""Advance to the next unit's turn"""
	if not is_active or not current_acting_unit:
		return
	
	_end_unit_turn(current_acting_unit)
	_advance_to_next_unit()

func can_unit_act(unit: Unit) -> bool:
	"""Check if a unit can act in the current turn"""
	if not is_active or not is_turn_in_progress:
		return false
	
	# Only the current acting unit can act
	return unit == current_acting_unit

func get_current_active_player() -> Player:
	"""Get the player who owns the currently acting unit"""
	if not current_acting_unit:
		return null
	
	# Find which player owns the current unit
	for player in registered_players:
		if player.owns_unit(current_acting_unit):
			return player
	
	return null

func get_turn_order() -> Array:
	"""Get the current turn order (units in speed order)"""
	return turn_order.duplicate()

# Speed First turn system specific methods
func _calculate_turn_order() -> void:
	"""Calculate turn order based on unit speed stats"""
	turn_order.clear()
	
	# Get all active units
	var active_units: Array[Unit] = []
	for unit in registered_units:
		if _is_unit_active(unit):
			active_units.append(unit)
	
	# Sort by speed (highest first)
	active_units.sort_custom(_compare_unit_speed)
	
	turn_order = active_units
	
	print("Turn order calculated: " + str(turn_order.size()) + " units")
	for i in range(turn_order.size()):
		var unit = turn_order[i]
		var speed = unit.get_stat("speed") if unit.has_method("get_stat") else 0
		print("  " + str(i + 1) + ". " + unit.get_display_name() + " (Speed: " + str(speed) + ")")

func _compare_unit_speed(unit_a: Unit, unit_b: Unit) -> bool:
	"""Compare two units by speed for sorting (higher speed first)"""
	var speed_a = unit_a.get_stat("speed") if unit_a.has_method("get_stat") else 0
	var speed_b = unit_b.get_stat("speed") if unit_b.has_method("get_stat") else 0
	
	# If speeds are equal, use unit name for consistent ordering
	if speed_a == speed_b:
		return unit_a.get_display_name() < unit_b.get_display_name()
	
	return speed_a > speed_b

func _is_unit_active(unit: Unit) -> bool:
	"""Check if a unit is active and can participate in turns"""
	if not unit:
		return false
	
	# Unit must be alive/active
	if unit.has_method("is_alive") and not unit.is_alive():
		return false
	
	# Unit must belong to an active player
	var owner = null
	for player in registered_players:
		if player.owns_unit(unit):
			owner = player
			break
	
	if not owner or owner.current_state == Player.PlayerState.ELIMINATED:
		return false
	
	return true

func _start_unit_turn(unit: Unit) -> void:
	"""Start a specific unit's turn"""
	current_acting_unit = unit
	is_turn_in_progress = true
	
	# Find the player who owns this unit
	var owner_player = null
	for player in registered_players:
		if player.owns_unit(unit):
			owner_player = player
			break
	
	# Emit turn started signal with the owning player
	if owner_player:
		turn_started.emit(owner_player)
	
	print("Speed First Turn System: " + unit.get_display_name() + "'s turn started (Turn " + str(current_turn) + ")")

func _end_unit_turn(unit: Unit) -> void:
	"""End a specific unit's turn"""
	if not unit or unit != current_acting_unit:
		return
	
	# Mark unit as having acted this round
	if unit not in units_acted_this_round:
		units_acted_this_round.append(unit)
	
	# Find the player who owns this unit
	var owner_player = null
	for player in registered_players:
		if player.owns_unit(unit):
			owner_player = player
			break
	
	is_turn_in_progress = false
	
	# Emit turn ended signal with the owning player
	if owner_player:
		turn_ended.emit(owner_player)
	
	print("Speed First Turn System: " + unit.get_display_name() + "'s turn ended")

func _advance_to_next_unit() -> void:
	"""Advance to the next unit in turn order"""
	if turn_order.is_empty():
		return
	
	var starting_index = current_unit_index
	
	# Find next active unit
	while true:
		current_unit_index = (current_unit_index + 1) % turn_order.size()
		
		# If we've completed a full round, start new round
		if current_unit_index == 0:
			_start_new_round()
		
		var next_unit = turn_order[current_unit_index]
		
		# Check if this unit can act
		if _is_unit_active(next_unit) and next_unit not in units_acted_this_round:
			_start_unit_turn(next_unit)
			break
		
		# Safety check to prevent infinite loop
		if current_unit_index == starting_index:
			print("Speed First Turn System: No units can act - ending turn system")
			_handle_no_valid_units()
			break

func _start_new_round() -> void:
	"""Start a new round - all units can act again"""
	current_turn += 1
	units_acted_this_round.clear()
	
	# Recalculate turn order in case units were added/removed
	_calculate_turn_order()
	
	# Reset index if turn order changed
	if current_unit_index >= turn_order.size():
		current_unit_index = 0
	
	print("Speed First Turn System: Round " + str(current_turn) + " begins")

func _handle_no_valid_units() -> void:
	"""Handle case where no units can act"""
	end_turn_system()
	
	# Notify game that turn system ended due to no valid units
	if PlayerManager:
		PlayerManager.end_game()

# Turn completion detection
func _check_turn_completion() -> void:
	"""Check if all units have acted this round"""
	var active_units = 0
	var acted_units = 0
	
	for unit in turn_order:
		if _is_unit_active(unit):
			active_units += 1
			if unit in units_acted_this_round:
				acted_units += 1
	
	if active_units > 0 and acted_units >= active_units:
		print("Speed First Turn System: All units have acted this round")
		all_units_acted.emit()
		# Note: Don't auto-advance here, let the current unit finish their turn

# Unit action handling
func mark_unit_acted(unit: Unit) -> void:
	"""Mark a unit as having acted and advance turn"""
	if unit == current_acting_unit:
		print("Speed First Turn System: Unit " + unit.get_display_name() + " completed their action")
		advance_turn()

# Manual turn control
func end_turn_manually() -> bool:
	"""Manually end the current unit's turn"""
	if not is_active or not current_acting_unit or not is_turn_in_progress:
		print("Speed First Turn System: Cannot end turn manually - invalid state")
		print("  is_active: " + str(is_active))
		print("  current_acting_unit: " + str(current_acting_unit != null))
		print("  is_turn_in_progress: " + str(is_turn_in_progress))
		return false
	
	print("Speed First Turn System: " + current_acting_unit.get_display_name() + " ended turn manually")
	advance_turn()
	return true

func can_end_turn_manually() -> bool:
	"""Check if the current unit's turn can be ended manually"""
	return is_active and current_acting_unit and is_turn_in_progress

# Override base class event handler
func _on_unit_action_completed(unit: Unit, action_type: String) -> void:
	"""Handle unit action completion"""
	super._on_unit_action_completed(unit, action_type)
	
	# Mark unit as having acted and advance turn
	mark_unit_acted(unit)

# Query methods
func get_current_acting_unit() -> Unit:
	"""Get the unit that is currently acting"""
	return current_acting_unit

func get_units_that_acted_this_round() -> Array[Unit]:
	"""Get units that have acted this round"""
	return units_acted_this_round.duplicate()

func get_units_remaining_this_round() -> Array[Unit]:
	"""Get units that haven't acted this round"""
	var remaining: Array[Unit] = []
	
	for unit in turn_order:
		if _is_unit_active(unit) and unit not in units_acted_this_round:
			remaining.append(unit)
	
	return remaining

func get_current_round_progress() -> Dictionary:
	"""Get information about current round progress"""
	var active_units = 0
	var acted_units = 0
	
	for unit in turn_order:
		if _is_unit_active(unit):
			active_units += 1
			if unit in units_acted_this_round:
				acted_units += 1
	
	return {
		"current_unit": current_acting_unit.get_display_name() if current_acting_unit else "None",
		"total_units": active_units,
		"units_acted": acted_units,
		"units_remaining": active_units - acted_units,
		"round_complete": acted_units >= active_units
	}

# Override debug info
func get_turn_system_info() -> Dictionary:
	"""Get detailed information about the speed first turn system state"""
	var base_info = super.get_turn_system_info()
	
	var speed_first_info = {
		"current_acting_unit": current_acting_unit.get_display_name() if current_acting_unit else "None",
		"current_unit_index": current_unit_index,
		"turn_order_size": turn_order.size(),
		"units_acted_this_round": units_acted_this_round.size(),
		"round_progress": get_current_round_progress()
	}
	
	base_info.merge(speed_first_info)
	return base_info

func _to_string() -> String:
	"""String representation for debugging"""
	var unit_name = current_acting_unit.get_display_name() if current_acting_unit else "No Unit"
	return system_name + " (Round " + str(current_turn) + " - " + unit_name + ")"