extends TurnSystemBase

class_name TraditionalTurnSystem

# Traditional Turn System Implementation
# Player-based turns where all units of a player can act before switching to next player

var current_player: Player = null
var units_acted_this_turn: Array[Unit] = []
var turn_completed_manually: bool = false

func _init() -> void:
	super._init()
	system_type = TurnSystemType.TRADITIONAL
	system_name = "Traditional Turn System"

# Abstract method implementations
func start_turn_system() -> void:
	"""Initialize and start the traditional turn system"""
	print("Traditional Turn System: Starting...")
	
	if registered_players.is_empty():
		print("Cannot start turn system: No players registered")
		return
	
	if registered_units.is_empty():
		print("Warning: No units registered with turn system")
	
	is_active = true
	current_turn = 1
	is_turn_in_progress = false
	units_acted_this_turn.clear()
	turn_completed_manually = false
	
	# Start with first player
	current_player = registered_players[0]
	_start_player_turn(current_player)
	
	print("Traditional Turn System started with " + str(registered_players.size()) + " players and " + str(registered_units.size()) + " units")

func end_turn_system() -> void:
	"""Clean up and end the traditional turn system"""
	if current_player and is_turn_in_progress:
		_end_player_turn(current_player)
	
	is_active = false
	is_turn_in_progress = false
	current_player = null
	units_acted_this_turn.clear()
	turn_completed_manually = false
	
	print("Traditional Turn System ended")

func advance_turn() -> void:
	"""Advance to the next player's turn"""
	print("=== ADVANCING TURN ===")
	print("Current player: " + (current_player.get_display_name() if current_player else "None"))
	
	if not is_active or not current_player:
		print("Cannot advance turn - invalid state")
		return
	
	# Don't end the current turn yet - just advance to next player
	# The next player's turn start will handle ending the previous turn
	_advance_to_next_player()
	
	print("=== TURN ADVANCE COMPLETE ===")

func can_unit_act(unit: Unit) -> bool:
	"""Check if a unit can act in the current turn"""
	if not is_active or not current_player or not is_turn_in_progress:
		return false
	
	# Unit must belong to current player
	if not current_player.owns_unit(unit):
		return false
	
	# Unit must not have acted this turn (once they act, they can't act again)
	if unit in units_acted_this_turn:
		return false
	
	# Unit must be able to act (not eliminated, has actions, etc.)
	if unit.has_method("can_act"):
		return unit.can_act()
	
	return true

func get_current_active_player() -> Player:
	"""Get the currently active player"""
	return current_player

func get_turn_order() -> Array:
	"""Get the current turn order (players in this case)"""
	return registered_players.duplicate()

# Traditional turn system specific methods
func _start_player_turn(player: Player) -> void:
	"""Start a specific player's turn"""
	var previous_player = current_player
	
	# End previous player's turn if there was one
	if previous_player and previous_player != player:
		_end_player_turn(previous_player)
	
	# Start new player's turn
	current_player = player
	is_turn_in_progress = true
	units_acted_this_turn.clear()
	turn_completed_manually = false
	
	# Reset all unit actions for the new turn
	reset_all_unit_actions()
	
	# Emit turn started signal
	turn_started.emit(player)
	
	print("Traditional Turn System: " + player.get_display_name() + "'s turn started (Turn " + str(current_turn) + ")")

func _end_player_turn(player: Player) -> void:
	"""End a specific player's turn"""
	if not player or player != current_player:
		return
	
	is_turn_in_progress = false
	
	# Emit turn ended signal
	turn_ended.emit(player)
	
	print("Traditional Turn System: " + player.get_display_name() + "'s turn ended")

func _advance_to_next_player() -> void:
	"""Advance to the next player in turn order"""
	print("Advancing to next player...")
	
	if registered_players.is_empty():
		print("No registered players!")
		return
	
	var current_index = registered_players.find(current_player)
	if current_index == -1:
		print("Current player not found in registered players!")
		current_index = 0
	
	print("Current player index: " + str(current_index) + " of " + str(registered_players.size()))
	
	# Find next active player
	var starting_index = current_index
	var next_index = current_index
	
	while true:
		next_index = (next_index + 1) % registered_players.size()
		print("Checking player at index " + str(next_index))
		
		# If we've completed a full round, increment turn number
		if next_index == 0:
			current_turn += 1
			print("Traditional Turn System: Turn " + str(current_turn) + " begins")
		
		var next_player = registered_players[next_index]
		print("Next player candidate: " + next_player.get_display_name())
		
		# Check if this player can play (not eliminated, has units, etc.)
		if _can_player_take_turn_for_advance(next_player):
			print("Player can take turn - starting their turn")
			_start_player_turn(next_player)
			break
		else:
			print("Player cannot take turn - checking next player")
		
		# Safety check to prevent infinite loop
		if next_index == starting_index:
			print("Traditional Turn System: No players can take turns - ending game")
			_handle_no_valid_players()
			break

func _can_player_take_turn_for_advance(player: Player) -> bool:
	"""Check if a player can take a turn during turn advancement (doesn't require turn to be in progress)"""
	print("Checking if player can take turn: " + player.get_display_name())
	
	if not player:
		print("  -> Player is null")
		return false
	
	# Player must not be eliminated
	if player.current_state == Player.PlayerState.ELIMINATED:
		print("  -> Player is eliminated")
		return false
	
	# Player must have units that can act
	var player_units = get_units_for_player(player)
	print("  -> Player has " + str(player_units.size()) + " units")
	
	for unit in player_units:
		# Check if unit can act without requiring turn system to be "in progress"
		if _can_unit_act_for_advance(unit, player):
			print("  -> Unit " + unit.get_display_name() + " can act - player can take turn")
			return true
		else:
			print("  -> Unit " + unit.get_display_name() + " cannot act")
	
	print("  -> No units can act - player cannot take turn")
	return false

func _can_unit_act_for_advance(unit: Unit, player: Player) -> bool:
	"""Check if a unit can act for a specific player during turn advancement"""
	# Unit must belong to the player
	if not player.owns_unit(unit):
		return false
	
	# Unit must not have acted this turn (but we're starting a new turn, so reset this check)
	# For turn advancement, we assume units haven't acted in the new turn yet
	
	# Unit must be able to act (not eliminated, has actions, etc.)
	if unit.has_method("can_act"):
		return unit.can_act()
	
	return true

func _can_player_take_turn(player: Player) -> bool:
	"""Check if a player can take a turn (requires turn system to be active)"""
	print("Checking if player can take turn: " + player.get_display_name())
	
	if not player:
		print("  -> Player is null")
		return false
	
	# Player must not be eliminated
	if player.current_state == Player.PlayerState.ELIMINATED:
		print("  -> Player is eliminated")
		return false
	
	# Player must have units that can act
	var player_units = get_units_for_player(player)
	print("  -> Player has " + str(player_units.size()) + " units")
	
	for unit in player_units:
		if can_unit_act(unit):
			print("  -> Unit " + unit.get_display_name() + " can act - player can take turn")
			return true
		else:
			print("  -> Unit " + unit.get_display_name() + " cannot act")
	
	print("  -> No units can act - player cannot take turn")
	return false

func _handle_no_valid_players() -> void:
	"""Handle case where no players can take turns"""
	end_turn_system()
	
	# Notify game that turn system ended due to no valid players
	if PlayerManager:
		PlayerManager.end_game()

# Turn completion detection
func _check_turn_completion() -> void:
	"""Check if the current player's turn should end"""
	print("=== CHECKING TURN COMPLETION ===")
	
	if not is_active or not current_player or not is_turn_in_progress:
		print("Turn completion check failed: invalid state")
		print("  is_active: " + str(is_active))
		print("  current_player: " + str(current_player != null))
		print("  is_turn_in_progress: " + str(is_turn_in_progress))
		return
	
	# If turn was completed manually, don't auto-advance
	if turn_completed_manually:
		print("Turn was completed manually - not auto-advancing")
		return
	
	# Check if all player's units have acted
	var player_units = get_units_for_player(current_player)
	var all_acted = true
	var units_can_act = 0
	var units_acted = 0
	
	print("Checking units for player: " + current_player.get_display_name())
	print("Player has " + str(player_units.size()) + " units")
	print("Units that acted this turn: " + str(units_acted_this_turn.size()))
	
	for unit in player_units:
		if can_unit_act(unit):
			all_acted = false
			units_can_act += 1
			print("  Unit " + unit.get_display_name() + " can still act")
		else:
			units_acted += 1
			var reason = ""
			if unit in units_acted_this_turn:
				reason = " (already acted)"
			elif not current_player.owns_unit(unit):
				reason = " (not owned by current player)"
			else:
				reason = " (cannot act)"
			print("  Unit " + unit.get_display_name() + " has acted or cannot act" + reason)
	
	print("Units summary: " + str(units_acted) + " acted, " + str(units_can_act) + " can still act")
	
	if all_acted:
		print("*** ALL UNITS HAVE ACTED - ADVANCING TURN ***")
		all_units_acted.emit()
		advance_turn()
	else:
		print("Turn continues - " + str(units_can_act) + " units can still act")
	
	print("=== TURN COMPLETION CHECK COMPLETE ===")

# Unit action handling
func mark_unit_acted(unit: Unit) -> void:
	"""Mark a unit as having acted this turn"""
	if unit not in units_acted_this_turn:
		units_acted_this_turn.append(unit)
		print("Traditional Turn System: Unit " + unit.get_display_name() + " marked as acted")
		print("Units acted this turn: " + str(units_acted_this_turn.size()))
		
		# Check if turn should end
		_check_turn_completion()

func reset_unit_actions() -> void:
	"""Reset all unit actions for the current turn"""
	units_acted_this_turn.clear()
	reset_all_unit_actions()

# Manual turn control
func end_turn_manually() -> bool:
	"""Manually end the current player's turn"""
	if not is_active or not current_player or not is_turn_in_progress:
		print("Traditional Turn System: Cannot end turn manually - invalid state")
		print("  is_active: " + str(is_active))
		print("  current_player: " + str(current_player != null))
		print("  is_turn_in_progress: " + str(is_turn_in_progress))
		return false
	
	turn_completed_manually = true
	print("Traditional Turn System: " + current_player.get_display_name() + " ended turn manually")
	advance_turn()
	return true

func can_end_turn_manually() -> bool:
	"""Check if the current player can manually end their turn"""
	return is_active and current_player and is_turn_in_progress

# Override base class event handler
func _on_unit_action_completed(unit: Unit, action_type: String) -> void:
	"""Handle unit action completion"""
	super._on_unit_action_completed(unit, action_type)
	
	# Mark unit as having acted
	mark_unit_acted(unit)

# Query methods
func get_units_that_acted() -> Array[Unit]:
	"""Get units that have acted this turn"""
	return units_acted_this_turn.duplicate()

func get_units_that_can_act() -> Array[Unit]:
	"""Get units that can still act this turn"""
	if not current_player:
		return []
	
	var can_act_units: Array[Unit] = []
	var player_units = get_units_for_player(current_player)
	
	for unit in player_units:
		if can_unit_act(unit):
			can_act_units.append(unit)
	
	return can_act_units

func get_current_turn_progress() -> Dictionary:
	"""Get information about current turn progress"""
	if not current_player:
		return {}
	
	var player_units = get_units_for_player(current_player)
	var acted_count = 0
	var can_act_count = 0
	
	for unit in player_units:
		if unit in units_acted_this_turn:
			acted_count += 1
		elif can_unit_act(unit):
			can_act_count += 1
	
	return {
		"current_player": current_player.get_display_name(),
		"total_units": player_units.size(),
		"units_acted": acted_count,
		"units_can_act": can_act_count,
		"turn_complete": can_act_count == 0
	}

# Override debug info
func get_turn_system_info() -> Dictionary:
	"""Get detailed information about the traditional turn system state"""
	var base_info = super.get_turn_system_info()
	
	var traditional_info = {
		"current_player": current_player.get_display_name() if current_player else "None",
		"units_acted_this_turn": units_acted_this_turn.size(),
		"turn_completed_manually": turn_completed_manually,
		"turn_progress": get_current_turn_progress()
	}
	
	base_info.merge(traditional_info)
	return base_info

func _to_string() -> String:
	"""String representation for debugging"""
	var player_name = current_player.get_display_name() if current_player else "No Player"
	return system_name + " (Turn " + str(current_turn) + " - " + player_name + ")"