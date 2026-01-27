extends TurnSystemBase

class_name TraditionalTurnSystem

# Traditional Turn System Implementation
# Player-based turns where all units of a player can act before switching to next player

var current_player: Player = null
var units_acted_this_turn: Array[Unit] = []
var turn_completed_manually: bool = false
var players_had_turn_this_round: Array[Player] = []  # Track which players have had a turn this round
var just_started: bool = false  # Flag to prevent immediate turn completion on startup

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
	players_had_turn_this_round.clear()
	just_started = true  # Prevent immediate turn completion
	
	# Initialize BattleEffectsManager for this battle
	if BattleEffectsManager:
		BattleEffectsManager.start_battle()
	
	# Start with first player
	current_player = registered_players[0]
	_start_player_turn(current_player)
	
	print("Traditional Turn System started with " + str(registered_players.size()) + " players and " + str(registered_units.size()) + " units")

func end_turn_system() -> void:
	"""Clean up and end the traditional turn system"""
	if current_player and is_turn_in_progress:
		_end_player_turn(current_player)
	
	# End battle in BattleEffectsManager (clears all battle-scoped effects)
	if BattleEffectsManager:
		BattleEffectsManager.end_battle()
	
	is_active = false
	is_turn_in_progress = false
	current_player = null
	units_acted_this_turn.clear()
	turn_completed_manually = false
	players_had_turn_this_round.clear()
	just_started = false
	
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
	
	print("Traditional Turn System: " + player.get_display_name() + "'s turn started (Round " + str(current_turn) + ")")

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
	
	# Add current player to the list of players who have had a turn this round
	if current_player and current_player not in players_had_turn_this_round:
		players_had_turn_this_round.append(current_player)
		print("Added " + current_player.get_display_name() + " to players who had turn this round")
		var player_names = []
		for p in players_had_turn_this_round:
			player_names.append(p.get_display_name())
		print("  -> Players who had turn this round: " + str(player_names))
	
	if registered_players.is_empty():
		print("No registered players!")
		return
	
	var current_index = registered_players.find(current_player)
	if current_index == -1:
		print("Current player not found in registered players!")
		current_index = 0
	
	print("Current player index: " + str(current_index) + " of " + str(registered_players.size()))
	print("Players who had turn this round: " + str(players_had_turn_this_round.size()) + "/" + str(registered_players.size()))
	
	# Create debug list of player names
	var debug_player_names = []
	for p in players_had_turn_this_round:
		debug_player_names.append(p.get_display_name())
	print("  -> Players list: " + str(debug_player_names))
	
	# Check if all players have had a turn this round
	var all_players_had_turn = (players_had_turn_this_round.size() >= registered_players.size())
	print("All players had turn this round: " + str(all_players_had_turn))
	
	# Find next active player
	var starting_index = current_index
	var next_index = current_index
	
	while true:
		next_index = (next_index + 1) % registered_players.size()
		print("Checking player at index " + str(next_index))
		
		var next_player = registered_players[next_index]
		print("Next player candidate: " + next_player.get_display_name())
		
		# Check if this player can play (not eliminated, has units, etc.)
		if _can_player_take_turn_for_advance(next_player):
			print("Player can take turn - starting their turn")
			
			# Increment round counter for each player switch (running counter)
			current_turn += 1
			print("Traditional Turn System: Round " + str(current_turn) + " - " + next_player.get_display_name() + "'s turn")
			
			# Check if we completed a full round (all players had a turn)
			if all_players_had_turn and next_player in players_had_turn_this_round:
				# All players have had a turn, clear the round tracking
				players_had_turn_this_round.clear()
				print("  -> Full cycle completed, starting new cycle")
				
				# Advance battle effects (use a cycle counter based on rounds)
				if BattleEffectsManager:
					var cycle_number = ((current_turn - 1) / registered_players.size()) + 1
					BattleEffectsManager.advance_round(cycle_number)
			
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
	
	# Don't check turn completion immediately after system starts
	if just_started:
		print("System just started - skipping turn completion check")
		just_started = false
		return
	
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

# Turn refresh capability (for special abilities)
func refresh_unit_turn(unit: Unit) -> bool:
	"""Allow a unit to act again this turn (for special abilities)"""
	if not is_active or not current_player or not is_turn_in_progress:
		return false
	
	# Unit must belong to current player
	if not current_player.owns_unit(unit):
		return false
	
	# Remove unit from acted list if present
	if unit in units_acted_this_turn:
		units_acted_this_turn.erase(unit)
		print("Unit " + unit.get_display_name() + " turn refreshed - can act again this turn")
		return true
	
	return false

func handle_unit_turn_refresh(unit: Unit) -> void:
	"""Handle turn refresh request from BattleEffectsManager"""
	if refresh_unit_turn(unit):
		print("Traditional Turn System: Handled turn refresh for " + unit.get_display_name())

func can_refresh_unit_turn(unit: Unit) -> bool:
	"""Check if a unit's turn can be refreshed"""
	return is_active and current_player and is_turn_in_progress and current_player.owns_unit(unit) and unit in units_acted_this_turn

func get_units_eligible_for_refresh() -> Array[Unit]:
	"""Get all units that have acted and could have their turn refreshed"""
	if not current_player:
		return []
	
	var eligible: Array[Unit] = []
	for unit in units_acted_this_turn:
		if current_player.owns_unit(unit) and _can_unit_act_for_advance(unit, current_player):
			eligible.append(unit)
	return eligible

# Speed modification API (delegates to BattleEffectsManager)
func apply_speed_buff(unit: Unit, buff_name: String, speed_increase: int, duration_rounds: int = -1, source: String = "") -> void:
	"""Apply a speed buff to a unit"""
	if BattleEffectsManager:
		BattleEffectsManager.apply_speed_buff(unit, buff_name, speed_increase, duration_rounds, source)

func apply_speed_debuff(unit: Unit, debuff_name: String, speed_decrease: int, duration_rounds: int = -1, source: String = "") -> void:
	"""Apply a speed debuff to a unit"""
	if BattleEffectsManager:
		BattleEffectsManager.apply_speed_debuff(unit, debuff_name, speed_decrease, duration_rounds, source)

func remove_speed_effect(unit: Unit, effect_name: String) -> bool:
	"""Remove a speed effect from a unit"""
	if BattleEffectsManager:
		return BattleEffectsManager.remove_speed_effect(unit, effect_name)
	return false

func get_unit_current_speed(unit: Unit) -> int:
	"""Get unit's current speed including all battle-scoped modifiers"""
	if BattleEffectsManager:
		return BattleEffectsManager.get_unit_current_speed(unit)
	else:
		# Fallback if BattleEffectsManager is not available
		return unit.get_stat("speed") if unit.has_method("get_stat") else 0

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
	print("Traditional Turn System: Resetting to initial state...")
	
	# Reset all state variables
	current_turn = 1
	is_turn_in_progress = false
	units_acted_this_turn.clear()
	turn_completed_manually = false
	players_had_turn_this_round.clear()
	just_started = true
	
	# Reset BattleEffectsManager
	if BattleEffectsManager:
		BattleEffectsManager.start_battle()  # This resets battle state
	
	# Reset all unit actions
	reset_all_unit_actions()
	
	# Start with first player again
	if not registered_players.is_empty():
		current_player = registered_players[0]
		_start_player_turn(current_player)
		print("Traditional Turn System: Reset complete - starting with " + current_player.get_display_name() + " on Turn 1")
	else:
		current_player = null
		print("Traditional Turn System: Reset complete - no players registered")

# Override debug info
func get_turn_system_info() -> Dictionary:
	"""Get detailed information about the traditional turn system state"""
	var base_info = super.get_turn_system_info()
	
	var active_effects_count = 0
	if BattleEffectsManager:
		var effects = BattleEffectsManager.get_all_active_effects()
		active_effects_count = effects.size()
	
	var traditional_info = {
		"current_player": current_player.get_display_name() if current_player else "None",
		"units_acted_this_turn": units_acted_this_turn.size(),
		"turn_completed_manually": turn_completed_manually,
		"active_battle_effects": active_effects_count,
		"turn_progress": get_current_turn_progress()
	}
	
	base_info.merge(traditional_info)
	return base_info

func _to_string() -> String:
	"""String representation for debugging"""
	var player_name = current_player.get_display_name() if current_player else "No Player"
	return system_name + " (Round " + str(current_turn) + " - " + player_name + ")"