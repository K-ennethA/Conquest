extends TurnSystemBase

class_name SpeedFirstTurnSystem

# Speed First Turn System Implementation
# Unit-based turns where units act in order based on their speed stats (fastest first)
# Features:
# - Dynamic turn order based on current speed (including temporary modifiers)
# - Queue system prevents units from acting twice until all others have acted
# - Speed modifications can change turn order mid-round

var turn_queue: Array[Unit] = []  # Current turn queue for this round
var current_acting_unit: Unit = null
var units_acted_this_round: Array[Unit] = []
var round_number: int = 1

# Speed modifications are now handled by BattleEffectsManager
# This ensures consistency across all turn systems

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
	round_number = 1
	is_turn_in_progress = false
	units_acted_this_round.clear()
	
	# Initialize BattleEffectsManager for this battle
	if BattleEffectsManager:
		BattleEffectsManager.start_battle()
	
	# Calculate initial turn queue
	_calculate_turn_queue()
	
	# Start with first unit in queue
	if not turn_queue.is_empty():
		_start_unit_turn(turn_queue[0])
	else:
		print("No units in turn queue - cannot start")
		return
	
	print("Speed First Turn System started with " + str(turn_queue.size()) + " units")
	_print_turn_queue()

func end_turn_system() -> void:
	"""Clean up and end the speed first turn system"""
	if current_acting_unit and is_turn_in_progress:
		_end_unit_turn(current_acting_unit)
	
	# End battle in BattleEffectsManager (clears all battle-scoped effects)
	if BattleEffectsManager:
		BattleEffectsManager.end_battle()
	
	is_active = false
	is_turn_in_progress = false
	current_acting_unit = null
	turn_queue.clear()
	units_acted_this_round.clear()
	round_number = 1
	
	print("Speed First Turn System ended - all battle modifiers cleared")


func reset_battle_state() -> void:
	"""Reset all battle-specific state (call when starting new battle)"""
	if BattleEffectsManager:
		BattleEffectsManager.reset_battle_state()
	
	units_acted_this_round.clear()
	turn_queue.clear()
	round_number = 1
	current_acting_unit = null
	is_turn_in_progress = false
	
	print("Speed First Turn System: Battle state reset - ready for new battle")

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
	"""Get the current turn queue (units in speed order)"""
	return turn_queue.duplicate()

# Speed First turn system specific methods
func _calculate_turn_queue() -> void:
	"""Calculate turn queue based on current unit speeds (including modifiers)"""
	turn_queue.clear()
	
	# Get all active units that haven't acted this round
	var available_units: Array[Unit] = []
	for unit in registered_units:
		if _is_unit_active(unit) and unit not in units_acted_this_round:
			available_units.append(unit)
	
	# Sort by current speed (highest first)
	available_units.sort_custom(_compare_unit_current_speed)
	
	turn_queue = available_units
	
	print("Turn queue calculated: " + str(turn_queue.size()) + " units")

func _print_turn_queue() -> void:
	"""Print current turn queue for debugging"""
	print("Current turn queue:")
	for i in range(turn_queue.size()):
		var unit = turn_queue[i]
		var base_speed = unit.get_stat("speed") if unit.has_method("get_stat") else 0
		var current_speed = get_unit_current_speed(unit)
		var speed_info = str(current_speed)
		if current_speed != base_speed:
			speed_info += " (base: " + str(base_speed) + ")"
		print("  " + str(i + 1) + ". " + unit.get_display_name() + " (Speed: " + speed_info + ")")

func _compare_unit_current_speed(unit_a: Unit, unit_b: Unit) -> bool:
	"""Compare two units by current speed for sorting (higher speed first)"""
	var speed_a = get_unit_current_speed(unit_a)
	var speed_b = get_unit_current_speed(unit_b)
	
	# If speeds are equal, use unit name for consistent ordering
	if speed_a == speed_b:
		return unit_a.get_display_name() < unit_b.get_display_name()
	
	return speed_a > speed_b

func get_unit_current_speed(unit: Unit) -> int:
	"""Get unit's current speed including all battle-scoped modifiers
	
	IMPORTANT: This does NOT modify the unit's base stats resource.
	Battle modifiers are temporary and reset when the battle ends.
	"""
	if BattleEffectsManager:
		return BattleEffectsManager.get_unit_current_speed(unit)
	else:
		# Fallback if BattleEffectsManager is not available
		return unit.get_stat("speed") if unit.has_method("get_stat") else 0

func add_speed_modifier(unit: Unit, modifier_name: String, speed_change: int, duration_rounds: int = -1, source: String = "") -> void:
	"""Add a speed modifier to a unit"""
	if BattleEffectsManager:
		if speed_change > 0:
			BattleEffectsManager.apply_speed_buff(unit, modifier_name, speed_change, duration_rounds, source)
		else:
			BattleEffectsManager.apply_speed_debuff(unit, modifier_name, abs(speed_change), duration_rounds, source)
		
		# Recalculate turn queue if this affects turn order
		if is_active and not is_turn_in_progress:
			_calculate_turn_queue()
			_print_turn_queue()
	else:
		print("Warning: BattleEffectsManager not available for speed modifier")

func remove_speed_modifier(unit: Unit, modifier_name: String) -> bool:
	"""Remove a specific speed modifier from a unit"""
	if BattleEffectsManager:
		var result = BattleEffectsManager.remove_speed_effect(unit, modifier_name)
		
		# Recalculate turn queue if this affects turn order
		if result and is_active and not is_turn_in_progress:
			_calculate_turn_queue()
			_print_turn_queue()
		
		return result
	else:
		print("Warning: BattleEffectsManager not available for speed modifier removal")
		return false

func get_unit_speed_modifiers(unit: Unit) -> Array:
	"""Get all speed modifiers for a unit"""
	if BattleEffectsManager:
		return BattleEffectsManager.get_unit_speed_modifiers(unit)
	return []



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
	
	var speed_info = str(get_unit_current_speed(unit))
	var base_speed = unit.get_stat("speed") if unit.has_method("get_stat") else 0
	if get_unit_current_speed(unit) != base_speed:
		speed_info += " (base: " + str(base_speed) + ")"
	
	print("Speed First Turn System: " + unit.get_display_name() + "'s turn started (Round " + str(round_number) + ", Speed: " + speed_info + ")")

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
	"""Advance to the next unit in the queue"""
	# Remove current unit from queue since they've acted
	if current_acting_unit in turn_queue:
		turn_queue.erase(current_acting_unit)
	
	# Check if we need to start a new round
	if turn_queue.is_empty():
		_start_new_round()
		return
	
	# Get next unit from queue (already sorted by speed)
	var next_unit = turn_queue[0]
	
	# Verify unit can still act
	if _is_unit_active(next_unit) and next_unit not in units_acted_this_round:
		_start_unit_turn(next_unit)
	else:
		# Unit can't act, remove from queue and try next
		turn_queue.erase(next_unit)
		if not turn_queue.is_empty():
			_advance_to_next_unit()
		else:
			_start_new_round()

func _start_new_round() -> void:
	"""Start a new round - all units can act again"""
	round_number += 1
	current_turn += 1  # Keep turn counter for compatibility
	
	# Update battle effects for new round
	if BattleEffectsManager:
		BattleEffectsManager.advance_round(round_number)
	
	# Clear acted units for new round
	units_acted_this_round.clear()
	
	# Recalculate turn queue with current speeds
	_calculate_turn_queue()
	
	print("Speed First Turn System: Round " + str(round_number) + " begins")
	_print_turn_queue()
	
	# Start with first unit in new queue
	if not turn_queue.is_empty():
		_start_unit_turn(turn_queue[0])
	else:
		print("Speed First Turn System: No units can act - ending turn system")
		_handle_no_valid_units()

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
	
	for unit in registered_units:
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
	return turn_queue.duplicate()

func get_turn_queue() -> Array[Unit]:
	"""Get the current turn queue"""
	return turn_queue.duplicate()

func get_current_round_progress() -> Dictionary:
	"""Get information about current round progress"""
	var total_active_units = 0
	for unit in registered_units:
		if _is_unit_active(unit):
			total_active_units += 1
	
	var acted_units = units_acted_this_round.size()
	var remaining_units = turn_queue.size()
	
	return {
		"current_unit": current_acting_unit.get_display_name() if current_acting_unit else "None",
		"current_unit_speed": get_unit_current_speed(current_acting_unit) if current_acting_unit else 0,
		"round_number": round_number,
		"total_units": total_active_units,
		"units_acted": acted_units,
		"units_remaining": remaining_units,
		"round_complete": remaining_units == 0,
		"turn_queue_preview": _get_turn_queue_preview()
	}

func _get_turn_queue_preview() -> Array[Dictionary]:
	"""Get preview of upcoming turns for UI display"""
	var preview: Array[Dictionary] = []
	var preview_count = min(5, turn_queue.size())  # Show next 5 units
	
	for i in range(preview_count):
		var unit = turn_queue[i]
		preview.append({
			"name": unit.get_display_name(),
			"speed": get_unit_current_speed(unit),
			"is_current": unit == current_acting_unit
		})
	
	return preview

# Public API for turn manipulation (future-proofing)
func refresh_unit_turn(unit: Unit) -> bool:
	"""Allow a unit to act again this round (for special abilities)"""
	if not is_active or not _is_unit_active(unit):
		return false
	
	# Remove unit from acted list if present
	if unit in units_acted_this_round:
		units_acted_this_round.erase(unit)
		print("Unit " + unit.get_display_name() + " turn refreshed - can act again this round")
		
		# If this unit isn't in the current queue, add them back based on speed
		if unit not in turn_queue:
			_insert_unit_into_queue(unit)
		
		return true
	
	return false

func handle_unit_turn_refresh(unit: Unit) -> void:
	"""Handle turn refresh request from BattleEffectsManager"""
	if refresh_unit_turn(unit):
		print("Speed First Turn System: Handled turn refresh for " + unit.get_display_name())

func _insert_unit_into_queue(unit: Unit) -> void:
	"""Insert a unit into the turn queue at the correct speed-based position"""
	if unit in turn_queue:
		return  # Already in queue
	
	var unit_speed = get_unit_current_speed(unit)
	var inserted = false
	
	# Find correct position based on speed (highest first)
	for i in range(turn_queue.size()):
		var queue_unit = turn_queue[i]
		var queue_speed = get_unit_current_speed(queue_unit)
		
		if unit_speed > queue_speed or (unit_speed == queue_speed and unit.get_display_name() < queue_unit.get_display_name()):
			turn_queue.insert(i, unit)
			inserted = true
			break
	
	# If not inserted, add to end
	if not inserted:
		turn_queue.append(unit)
	
	print("Unit " + unit.get_display_name() + " inserted into turn queue at position with speed " + str(unit_speed))

func can_refresh_unit_turn(unit: Unit) -> bool:
	"""Check if a unit's turn can be refreshed"""
	return is_active and _is_unit_active(unit) and unit in units_acted_this_round

func get_units_eligible_for_refresh() -> Array[Unit]:
	"""Get all units that have acted and could have their turn refreshed"""
	var eligible: Array[Unit] = []
	for unit in units_acted_this_round:
		if _is_unit_active(unit):
			eligible.append(unit)
	return eligible

# Public API for speed modifications (delegates to BattleEffectsManager)
func apply_speed_buff(unit: Unit, buff_name: String, speed_increase: int, duration_rounds: int = -1, source: String = "") -> void:
	"""Apply a speed buff to a unit"""
	add_speed_modifier(unit, buff_name, speed_increase, duration_rounds, source)

func apply_speed_debuff(unit: Unit, debuff_name: String, speed_decrease: int, duration_rounds: int = -1, source: String = "") -> void:
	"""Apply a speed debuff to a unit"""
	add_speed_modifier(unit, debuff_name, -speed_decrease, duration_rounds, source)

func remove_speed_effect(unit: Unit, effect_name: String) -> bool:
	"""Remove a speed effect from a unit"""
	return remove_speed_modifier(unit, effect_name)

func get_unit_speed_info(unit: Unit) -> Dictionary:
	"""Get detailed speed information for a unit"""
	if BattleEffectsManager:
		return BattleEffectsManager.get_unit_speed_info(unit)
	else:
		# Fallback if BattleEffectsManager is not available
		var base_speed = unit.get_stat("speed") if unit.has_method("get_stat") else 0
		return {
			"base_speed": base_speed,
			"current_speed": base_speed,
			"total_modifier": 0,
			"modifiers": []
		}

# Reset mechanism for testing
func reset_turn_system() -> void:
	"""Reset the turn system to initial state (for testing purposes)"""
	print("Speed First Turn System: Resetting to initial state...")
	
	# Reset all state variables
	current_turn = 1
	round_number = 1
	is_turn_in_progress = false
	turn_queue.clear()
	units_acted_this_round.clear()
	current_acting_unit = null
	
	# Reset BattleEffectsManager
	if BattleEffectsManager:
		BattleEffectsManager.start_battle()  # This resets battle state
	
	# Reset all unit actions
	reset_all_unit_actions()
	
	# Recalculate turn queue and start first unit
	if not registered_units.is_empty():
		_calculate_turn_queue()
		if not turn_queue.is_empty():
			_start_unit_turn(turn_queue[0])
			print("Speed First Turn System: Reset complete - starting with " + turn_queue[0].get_display_name() + " on Round 1")
		else:
			print("Speed First Turn System: Reset complete - no active units")
	else:
		print("Speed First Turn System: Reset complete - no units registered")

# Override debug info
func get_turn_system_info() -> Dictionary:
	"""Get detailed information about the speed first turn system state"""
	var base_info = super.get_turn_system_info()
	
	var active_effects_count = 0
	if BattleEffectsManager:
		var effects = BattleEffectsManager.get_all_active_effects()
		active_effects_count = effects.size()
	
	var speed_first_info = {
		"current_acting_unit": current_acting_unit.get_display_name() if current_acting_unit else "None",
		"round_number": round_number,
		"turn_queue_size": turn_queue.size(),
		"units_acted_this_round": units_acted_this_round.size(),
		"active_battle_effects": active_effects_count,
		"round_progress": get_current_round_progress()
	}
	
	base_info.merge(speed_first_info)
	return base_info

func _to_string() -> String:
	"""String representation for debugging"""
	var unit_name = current_acting_unit.get_display_name() if current_acting_unit else "No Unit"
	return system_name + " (Round " + str(round_number) + " - " + unit_name + ")"
